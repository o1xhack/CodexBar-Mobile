// The engine keeps CKSyncEngine pending state, fork reconciliation, revision
// gates, and snapshot ownership on the MainActor so those invariants stay atomic
// with the settings and fleet state they mutate.
// swiftlint:disable file_length
import AppKit
import CloudKit
import CodexBarCore
import CodexBarSync
import Foundation
import Observation
import os
import Security

enum SyncAvailability: Equatable, Sendable {
    case available
    case missingEntitlement
    case noICloudAccount
    case restricted
}

struct SyncStatus: Equatable, Sendable {
    var needsAppUpdate = false
    var lastError: String?
    var lastSuccessfulFetchAt: Date?
    var lastSuccessfulPushAt: Date?
}

enum CloudSyncErrorScope: Hashable, Sendable {
    case fetch
    case push
}

/// Device removal reads the fleet before deleting and reads it again afterward.
/// Keep failures tied to the actual operation, including the final confirmation fetch.
enum CloudSyncDeviceRemoval {
    struct Failure {
        let error: any Error
        let scope: CloudSyncErrorScope
    }

    static func run(
        isolation: isolated (any Actor)? = #isolation,
        fetch: () async throws -> Void,
        delete: () async throws -> Bool,
        didDelete: () async -> Void = {}) async -> Failure?
    {
        do {
            try await fetch()
        } catch {
            return Failure(error: error, scope: .fetch)
        }
        do {
            guard try await delete() else { return nil }
        } catch {
            return Failure(error: error, scope: .push)
        }
        await didDelete()
        do {
            try await fetch()
        } catch {
            return Failure(error: error, scope: .fetch)
        }
        return nil
    }
}

/// A successful operation only recovers older errors in its own direction.
/// Errors reported while that operation is running survive its completion.
struct CloudSyncErrorRecovery {
    private struct Failure {
        let revision: UInt64
        let message: String
    }

    private(set) var revision: UInt64 = 0
    private var failures: [CloudSyncErrorScope: Failure] = [:]

    var message: String? {
        self.failures.values.max { $0.revision < $1.revision }?.message
    }

    mutating func record(_ message: String, scope: CloudSyncErrorScope) {
        self.revision += 1
        self.failures[scope] = Failure(revision: self.revision, message: message)
    }

    mutating func recover(scope: CloudSyncErrorScope, startedAt revision: UInt64, succeeded: Bool) {
        guard succeeded, let failure = self.failures[scope], failure.revision <= revision else { return }
        self.failures[scope] = nil
    }
}

/// Each engine owns one lease. Invalidation and a MainActor success commit
/// share the same short lock, so stopping an engine cannot race a queued commit.
final class CloudSyncEngineLease: Sendable {
    private let active = OSAllocatedUnfairLock(initialState: true)

    func invalidate() {
        self.active.withLock { $0 = false }
    }

    @MainActor
    func finishDeviceDeletion(state: CloudSyncState, startedAt revision: UInt64, pushedAt: Date) {
        // The closure never escapes or suspends; MainActor isolation stays intact.
        self.active.withLockUnchecked { active in
            guard active else { return }
            state.status.lastSuccessfulPushAt = pushedAt
            state.finishErrorRecovery(scope: .push, startedAt: revision, succeeded: true)
        }
    }
}

@MainActor
@Observable
final class CloudSyncState {
    var availability: SyncAvailability = .available
    var status = SyncStatus()
    var fleetDevices: [String: DeviceSyncPayload] = [:]
    var fleetSnapshots: [String: AccountSnapshotSyncPayload] = [:]
    var removeDeviceHandler: ((String) async -> Void)?
    var refreshHandler: (() async -> Void)?
    private(set) var isRefreshing = false
    @ObservationIgnored private var errorRecovery = CloudSyncErrorRecovery()

    var errorRevision: UInt64 {
        self.errorRecovery.revision
    }

    func recordError(_ message: String, scope: CloudSyncErrorScope) {
        self.errorRecovery.record(message, scope: scope)
        self.status.lastError = self.errorRecovery.message
    }

    func finishErrorRecovery(scope: CloudSyncErrorScope, startedAt revision: UInt64, succeeded: Bool) {
        self.errorRecovery.recover(scope: scope, startedAt: revision, succeeded: succeeded)
        self.status.lastError = self.errorRecovery.message
    }

    func requestRefresh() async {
        guard !self.isRefreshing, let refreshHandler else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }
        await refreshHandler()
    }

    @ObservationIgnored private var removingDevices: Set<String> = []

    func requestDeviceRemoval(_ deviceID: String) async {
        guard self.removingDevices.insert(deviceID).inserted else { return }
        defer { self.removingDevices.remove(deviceID) }
        await self.removeDeviceHandler?(deviceID)
    }

    func recordNames(removing deviceID: String, currentDeviceID: String) -> [String] {
        guard deviceID != currentDeviceID else { return [] }
        return self.fleetDevices.filter { $0.value.deviceID == deviceID }.map(\.key) +
            self.fleetSnapshots.filter { $0.value.deviceID == deviceID }.map(\.key)
    }

    func removeRecords(_ names: [String]) {
        for name in names {
            self.fleetDevices.removeValue(forKey: name)
            self.fleetSnapshots.removeValue(forKey: name)
        }
    }
}

struct CloudSyncQuotaRetryState: Equatable, Sendable {
    private(set) var baseDelay: TimeInterval?
    private(set) var failureCount = 0

    mutating func nextDelay(serverRetryAfter: TimeInterval?) -> TimeInterval {
        if self.baseDelay == nil {
            self.baseDelay = max(serverRetryAfter ?? 60, 0)
        }
        let multiplier = pow(2, Double(self.failureCount))
        self.failureCount += 1
        return min((self.baseDelay ?? 60) * multiplier, 60 * 60)
    }

    mutating func reset() {
        self = Self()
    }
}

/// Runs CKSyncEngine delegate events serially without retaining the delegate callback's task context.
final class CloudSyncDelegateEventQueue: Sendable {
    typealias Operation = @Sendable () async -> Void

    private let continuation: AsyncStream<Operation>.Continuation
    private let worker: Task<Void, Never>

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Operation.self)
        self.continuation = continuation
        self.worker = Task.detached(priority: .utility) {
            for await operation in stream {
                guard !Task.isCancelled else { return }
                await operation()
            }
        }
    }

    deinit {
        self.continuation.finish()
        self.worker.cancel()
    }

    func enqueue(_ operation: @escaping Operation) {
        self.continuation.yield(operation)
    }

    func drain() async {
        await withCheckedContinuation { continuation in
            self.enqueue { continuation.resume() }
        }
    }
}

enum CloudSyncBatchRecordProvider {
    static func record(
        for recordID: CKRecord.ID,
        desiredRecords: [CKRecord.ID: CKRecord],
        removePendingChange: (CKSyncEngine.PendingRecordZoneChange) -> Void) -> CKRecord?
    {
        guard let record = desiredRecords[recordID] else {
            removePendingChange(.saveRecord(recordID))
            return nil
        }
        return record
    }
}

enum CloudSyncDirtyState {
    private static let providerIntentPrefix = "intent-"

    static func configurationRecordNamesToQueue(
        envelope: CloudSyncPersistence.Envelope,
        configuredProviders: [ProviderInstanceID]) -> Set<String>
    {
        var recordNames = Set(configuredProviders.compactMap { provider in
            envelope.dirtyProviders.contains(provider.rawValue)
                ? ProviderIntentPayload.recordName(for: provider)
                : nil
        })
        if envelope.preferencesDirty {
            recordNames.insert(PreferencesSyncPayload.recordName)
        }
        return recordNames
    }

    static func markBootstrapDirtyIfNeeded(
        configuredProviders: [ProviderInstanceID],
        envelope: inout CloudSyncPersistence.Envelope)
    {
        guard !envelope.recordMetadata.keys.contains(where: { $0.hasPrefix(self.providerIntentPrefix) }) else {
            return
        }
        envelope.dirtyProviders.formUnion(configuredProviders.map(\.rawValue))
        envelope.preferencesDirty = true
    }

    static func clearSavedRecords(
        _ recordNames: some Sequence<String>,
        envelope: inout CloudSyncPersistence.Envelope)
    {
        for recordName in recordNames {
            if recordName == PreferencesSyncPayload.recordName {
                envelope.preferencesDirty = false
            } else if recordName.hasPrefix(self.providerIntentPrefix) {
                envelope.dirtyProviders.remove(String(recordName.dropFirst(self.providerIntentPrefix.count)))
            }
        }
    }

    static func providerSyncContentChanged(
        from previous: ProviderConfig,
        previousSuppressedEnableIntents: Set<String>,
        to current: ProviderConfig,
        currentSuppressedEnableIntents: Set<String>) throws -> Bool
    {
        let previousPayload = CloudSyncEngine.providerIntentPayload(
            config: previous,
            suppressedEnableIntents: previousSuppressedEnableIntents)
        let currentPayload = CloudSyncEngine.providerIntentPayload(
            config: current,
            suppressedEnableIntents: currentSuppressedEnableIntents)
        guard try CanonicalSyncJSON.encode(previousPayload) == CanonicalSyncJSON.encode(currentPayload) else {
            return true
        }
        let previousSecrets = try ProviderIntentPayload.secretFields(for: previous, includeSecrets: true)
        let currentSecrets = try ProviderIntentPayload.secretFields(for: current, includeSecrets: true)
        return previousSecrets != currentSecrets
    }
}

enum CloudSyncSnapshotReconciliation {
    struct Plan: Equatable {
        let recordNamesToCancelPendingDeletes: Set<String>
        let recordNamesToDelete: Set<String>
    }

    static func plan(
        currentSnapshots: [AccountSnapshotSyncPayload],
        persistedSnapshots: [String: AccountSnapshotSyncPayload],
        deviceID: String,
        enabledProviders: Set<ProviderInstanceID>,
        authoritativeProviders: Set<ProviderInstanceID>) -> Plan
    {
        let currentRecordNames = Set(currentSnapshots.lazy
            .filter { enabledProviders.contains($0.provider) }
            .map(\.recordName))
        let recordNamesToDelete = Set<String>(persistedSnapshots.compactMap { recordName, snapshot in
            guard snapshot.deviceID == deviceID, !currentRecordNames.contains(recordName) else { return nil }
            guard !enabledProviders.contains(snapshot.provider) || authoritativeProviders.contains(snapshot.provider)
            else { return nil }
            return recordName
        })
        return Plan(
            recordNamesToCancelPendingDeletes: currentRecordNames,
            recordNamesToDelete: recordNamesToDelete)
    }
}

enum CloudSyncSnapshotPublicationRevisionGate {
    static func acceptedProviders(
        claimedProviders: Set<ProviderInstanceID>,
        sourceRevisions: [ProviderInstanceID: UInt64],
        currentRevisions: [ProviderInstanceID: UInt64]) -> Set<ProviderInstanceID>
    {
        Set(claimedProviders.filter { provider in
            guard let sourceRevision = sourceRevisions[provider],
                  let currentRevision = currentRevisions[provider]
            else { return false }
            return sourceRevision == currentRevision
        })
    }
}

enum CloudSyncSnapshotPublicationGenerationGate {
    static func acceptedProviders(
        claimedProviders: Set<ProviderInstanceID>,
        sourceGenerations: [ProviderInstanceID: UInt64],
        latestAcceptedGenerations: [ProviderInstanceID: UInt64]) -> Set<ProviderInstanceID>
    {
        Set(claimedProviders.filter { provider in
            guard let sourceGeneration = sourceGenerations[provider] else { return false }
            return sourceGeneration >= latestAcceptedGenerations[provider, default: 0]
        })
    }
}

enum CloudSyncPendingSnapshotPublicationReconciliation {
    struct State {
        let snapshots: [AccountSnapshotSyncPayload]
        let authoritativeProviders: Set<ProviderInstanceID>
        let tokenAccountIDsByRecordName: [String: UUID]
        let providerConfigRevisions: [ProviderInstanceID: UInt64]
    }

    struct Plan {
        let snapshots: [AccountSnapshotSyncPayload]
        let authoritativeProviders: Set<ProviderInstanceID>
        let tokenAccountIDsByRecordName: [String: UUID]
        let providerConfigRevisions: [ProviderInstanceID: UInt64]
    }

    struct Incoming {
        let snapshots: [AccountSnapshotSyncPayload]
        let authoritativeProviders: Set<ProviderInstanceID>
        let tokenAccountIDsByRecordName: [String: UUID]
        let providerConfigRevisions: [ProviderInstanceID: UInt64]
    }

    static func plan(
        state: State,
        incoming: Incoming,
        currentProviderConfigRevisions: [ProviderInstanceID: UInt64]) -> Plan
    {
        let currentPendingProviders = CloudSyncSnapshotPublicationRevisionGate.acceptedProviders(
            claimedProviders: Set(state.providerConfigRevisions.keys),
            sourceRevisions: state.providerConfigRevisions,
            currentRevisions: currentProviderConfigRevisions)
        let acceptedIncomingProviders = CloudSyncSnapshotPublicationRevisionGate.acceptedProviders(
            claimedProviders: Set(incoming.providerConfigRevisions.keys),
            sourceRevisions: incoming.providerConfigRevisions,
            currentRevisions: currentProviderConfigRevisions)
        let completeIncomingProviders = incoming.authoritativeProviders.intersection(acceptedIncomingProviders)

        var snapshotsByRecordName: [String: AccountSnapshotSyncPayload] = Dictionary(
            uniqueKeysWithValues: state.snapshots.compactMap { snapshot -> (String, AccountSnapshotSyncPayload)? in
                guard currentPendingProviders.contains(snapshot.provider),
                      !completeIncomingProviders.contains(snapshot.provider)
                else { return nil }
                return (snapshot.recordName, snapshot)
            })
        for snapshot in incoming.snapshots where acceptedIncomingProviders.contains(snapshot.provider) {
            snapshotsByRecordName[snapshot.recordName] = snapshot
        }
        let snapshots = snapshotsByRecordName.values.sorted { $0.recordName < $1.recordName }
        let recordNames = Set(snapshotsByRecordName.keys)

        var authoritativeProviders = state.authoritativeProviders
            .intersection(currentPendingProviders)
            .subtracting(completeIncomingProviders)
        authoritativeProviders.formUnion(completeIncomingProviders)

        var tokenAccountIDsByRecordName = state.tokenAccountIDsByRecordName.filter {
            recordNames.contains($0.key)
        }
        for snapshot in incoming.snapshots where acceptedIncomingProviders.contains(snapshot.provider) {
            tokenAccountIDsByRecordName.removeValue(forKey: snapshot.recordName)
            if let accountID = incoming.tokenAccountIDsByRecordName[snapshot.recordName] {
                tokenAccountIDsByRecordName[snapshot.recordName] = accountID
            }
        }

        var providerConfigRevisions = state.providerConfigRevisions.filter {
            currentPendingProviders.contains($0.key)
        }
        for provider in acceptedIncomingProviders {
            providerConfigRevisions[provider] = incoming.providerConfigRevisions[provider]
        }
        return Plan(
            snapshots: snapshots,
            authoritativeProviders: authoritativeProviders,
            tokenAccountIDsByRecordName: tokenAccountIDsByRecordName,
            providerConfigRevisions: providerConfigRevisions)
    }
}

enum CloudSyncSnapshotConfigurationReconciliation {
    struct State {
        let candidateSnapshots: [String: AccountSnapshotSyncPayload]
        let ownershipKnownRecordNames: Set<String>
        let tokenAccountIDsByRecordName: [String: UUID]
        let deviceID: String
        let pendingRecordNames: Set<String>
    }

    struct Plan: Equatable {
        let pendingRecordNames: Set<String>
        let recordNamesToDelete: Set<String>
        let recordNamesToCancel: Set<String>
        let providersRequiringFreshAuthority: Set<ProviderInstanceID>
        let ownershipKnownRecordNames: Set<String>
        let tokenAccountIDsByRecordName: [String: UUID]
    }

    static func plan(
        previousConfigs: [ProviderInstanceID: ProviderConfig],
        currentConfig: CodexBarConfig,
        authoritativeProviders: Set<ProviderInstanceID>? = nil,
        state: State) -> Plan
    {
        let currentConfigs = Dictionary(uniqueKeysWithValues: currentConfig.providers.map { ($0.id, $0) })
        let authoritativeProviders = authoritativeProviders ?? Set(currentConfigs.keys)
        let knownProviders = Set(previousConfigs.keys)
            .union(currentConfigs.keys)
            .union(state.candidateSnapshots.values.map(\.provider))
        let currentAccounts = currentConfigs.mapValues { $0.tokenAccounts?.accounts ?? [] }
        let ownership = self.backfillOwnership(
            previousConfigs: previousConfigs,
            currentAccounts: currentAccounts,
            state: state)
        let newlyRemovedRecordNames = Set<String>(state.candidateSnapshots.compactMap { recordName, snapshot in
            guard snapshot.deviceID == state.deviceID,
                  authoritativeProviders.contains(snapshot.provider)
            else { return nil }
            guard ownership.knownRecordNames.contains(recordName),
                  let accountID = ownership.tokenAccountIDsByRecordName[recordName]
            else { return nil }
            let currentIDs = Set(currentAccounts[snapshot.provider, default: []].map(\.id))
            return currentIDs.contains(accountID) ? nil : recordName
        })
        // Presence can safely cancel a destructive intent even when the configuration cannot
        // authorize absence. This also repairs pending CKSyncEngine deletes after sync was off.
        let restoredRecordNames = Set(state.pendingRecordNames.filter { recordName in
            guard let provider = self.provider(
                for: recordName,
                candidateSnapshots: state.candidateSnapshots,
                knownProviders: knownProviders),
                let accounts = currentAccounts[provider],
                !accounts.isEmpty
            else { return false }
            if ownership.knownRecordNames.contains(recordName) {
                guard let accountID = ownership.tokenAccountIDsByRecordName[recordName] else { return false }
                return accounts.contains(where: { $0.id == accountID })
            }
            if let snapshot = state.candidateSnapshots[recordName] {
                return accounts.contains(where: { self.matches(snapshot: snapshot, account: $0) })
            }
            return accounts.contains { self.candidateRecordNames(
                provider: provider,
                account: $0,
                deviceID: state.deviceID).contains(recordName)
            }
        })
        let nextPendingRecordNames = state.pendingRecordNames
            .union(newlyRemovedRecordNames)
            .subtracting(restoredRecordNames)
        let providersRequiringFreshAuthority = Set(nextPendingRecordNames.compactMap {
            self.provider(
                for: $0,
                candidateSnapshots: state.candidateSnapshots,
                knownProviders: knownProviders)
        })
        return Plan(
            pendingRecordNames: nextPendingRecordNames,
            recordNamesToDelete: nextPendingRecordNames,
            recordNamesToCancel: restoredRecordNames,
            providersRequiringFreshAuthority: providersRequiringFreshAuthority,
            ownershipKnownRecordNames: ownership.knownRecordNames,
            tokenAccountIDsByRecordName: ownership.tokenAccountIDsByRecordName)
    }

    private static func provider(
        for recordName: String,
        candidateSnapshots: [String: AccountSnapshotSyncPayload],
        knownProviders: Set<ProviderInstanceID>) -> ProviderInstanceID?
    {
        if let provider = candidateSnapshots[recordName]?.provider { return provider }
        return knownProviders
            .sorted { $0.rawValue.count > $1.rawValue.count }
            .first { recordName.hasPrefix("snap-\($0.rawValue)-") }
    }

    private static func backfillOwnership(
        previousConfigs: [ProviderInstanceID: ProviderConfig],
        currentAccounts: [ProviderInstanceID: [ProviderTokenAccount]],
        state: State) -> (knownRecordNames: Set<String>, tokenAccountIDsByRecordName: [String: UUID])
    {
        var accountsByProvider = previousConfigs.mapValues { $0.tokenAccounts?.accounts ?? [] }
        for (provider, accounts) in currentAccounts {
            var knownIDs = Set(accountsByProvider[provider, default: []].map(\.id))
            let newAccounts = accounts.filter { knownIDs.insert($0.id).inserted }
            accountsByProvider[provider, default: []].append(contentsOf: newAccounts)
        }
        let localSnapshots = state.candidateSnapshots.filter { $0.value.deviceID == state.deviceID }
        var knownRecordNames = state.ownershipKnownRecordNames
        var tokenAccountIDsByRecordName = state.tokenAccountIDsByRecordName
        for (recordName, snapshot) in localSnapshots where !knownRecordNames.contains(recordName) {
            let accounts = accountsByProvider[snapshot.provider, default: []]
            let keyMatches = accounts.filter { self.matches(snapshot: snapshot, account: $0) }
            guard keyMatches.count == 1, let owner = keyMatches.first else { continue }
            knownRecordNames.insert(recordName)
            tokenAccountIDsByRecordName[recordName] = owner.id
        }
        return (knownRecordNames, tokenAccountIDsByRecordName)
    }

    private static func matches(
        snapshot: AccountSnapshotSyncPayload,
        account: ProviderTokenAccount) -> Bool
    {
        self.candidateAccountKeys(account).contains(snapshot.accountKey)
    }

    private static func candidateRecordNames(
        provider: ProviderInstanceID,
        account: ProviderTokenAccount,
        deviceID: String) -> Set<String>
    {
        Set(self.candidateAccountKeys(account).map { "snap-\(provider.rawValue)-\($0)-\(deviceID)" })
    }

    private static func candidateAccountKeys(_ account: ProviderTokenAccount) -> Set<String> {
        Set(self.normalizedAccountIdentities(account).map(AccountSnapshotSyncPayload.accountKey(for:)))
    }

    private static func normalizedAccountIdentities(_ account: ProviderTokenAccount) -> Set<String> {
        Set([
            account.externalIdentifier,
            account.id.uuidString,
        ].compactMap(self.normalized))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else { return nil }
        return value
    }
}

enum CloudSyncStartupSnapshotDeletionAuthority {
    static func loadConfiguration(
        from store: CodexBarConfigStore,
        matching currentConfig: CodexBarConfig) -> CodexBarConfig?
    {
        do {
            guard let loaded = try store.load(),
                  try store.encodedData(for: loaded) == store.encodedData(for: currentConfig)
            else { return nil }
            return loaded
        } catch {
            return nil
        }
    }
}

enum CloudSyncSnapshotDeletionIntentReconciliation {
    struct Plan: Equatable {
        let pendingRecordNames: Set<String>
        let recordNamesToCancel: Set<String>
        let blockedRecordNames: Set<String>
        let providersRequiringFreshAuthority: Set<ProviderInstanceID>
    }

    static func plan(
        snapshots: [AccountSnapshotSyncPayload],
        tokenAccountIDsByRecordName: [String: UUID],
        authoritativeProviders: Set<ProviderInstanceID>,
        activeTokenAccountIDs: Set<UUID>,
        pendingRecordNames: Set<String>) -> Plan
    {
        let recordNamesToCancel = Set(snapshots.compactMap { snapshot -> String? in
            guard pendingRecordNames.contains(snapshot.recordName),
                  authoritativeProviders.contains(snapshot.provider)
            else { return nil }
            guard let tokenAccountID = tokenAccountIDsByRecordName[snapshot.recordName] else {
                return snapshot.recordName
            }
            return activeTokenAccountIDs.contains(tokenAccountID) ? snapshot.recordName : nil
        })
        let nextPendingRecordNames = pendingRecordNames.subtracting(recordNamesToCancel)
        let providersRequiringFreshAuthority = Set(snapshots.compactMap { snapshot in
            nextPendingRecordNames.contains(snapshot.recordName) ? snapshot.provider : nil
        })
        return Plan(
            pendingRecordNames: nextPendingRecordNames,
            recordNamesToCancel: recordNamesToCancel,
            blockedRecordNames: nextPendingRecordNames,
            providersRequiringFreshAuthority: providersRequiringFreshAuthority)
    }
}

enum CloudSyncSnapshotMigration {
    static func obsoleteRecordNames(
        liveSnapshots: [AccountSnapshotSyncPayload],
        hashes: [String: String],
        envelope: CloudSyncPersistence.Envelope) -> Set<String>
    {
        AccountSnapshotSyncPayload.obsoleteEmailKeyedRecordNames(
            liveSnapshots: liveSnapshots,
            knownRecordNames: Set(hashes.keys).union(envelope.fleetSnapshots.keys))
    }

    static func immediateReconciliationDeletes(
        _ recordNamesToDelete: Set<String>,
        protecting obsoleteNames: Set<String>) -> Set<String>
    {
        recordNamesToDelete.subtracting(obsoleteNames)
    }

    static func drop(
        _ names: Set<String>,
        hashes: inout [String: String],
        envelope: inout CloudSyncPersistence.Envelope,
        desiredRecords: inout [CKRecord.ID: CKRecord],
        zoneID: CKRecordZone.ID) -> [CKRecord.ID]
    {
        names.map { name in
            let recordID = CKRecord.ID(recordName: name, zoneID: zoneID)
            desiredRecords.removeValue(forKey: recordID)
            hashes.removeValue(forKey: name)
            envelope.fleetSnapshots.removeValue(forKey: name)
            envelope.encodedSystemFields.removeValue(forKey: name)
            envelope.recordMetadata.removeValue(forKey: name)
            return recordID
        }
    }

    static func predecessorNames(
        for snapshot: AccountSnapshotSyncPayload,
        obsoleteNames: Set<String>) -> Set<String>
    {
        guard let predecessor = snapshot.emailKeyedPredecessorRecordName(),
              obsoleteNames.contains(predecessor)
        else {
            return []
        }
        return [predecessor]
    }

    static func takeDeletes(
        forSavedRecordNames savedNames: [String],
        pending: inout [String: Set<String>],
        afterLiveSnapshotReconciliation hasReconciledLiveSnapshots: Bool,
        liveNames: Set<String> = []) -> Set<String>
    {
        guard hasReconciledLiveSnapshots else { return [] }
        return self.takeDeletes(
            forSavedRecordNames: savedNames,
            pending: &pending,
            liveNames: liveNames)
    }

    static func takeDeletes(
        forSavedRecordNames savedNames: [String],
        pending: inout [String: Set<String>],
        liveNames: Set<String> = []) -> Set<String>
    {
        var toDrop: Set<String> = []
        for name in savedNames {
            if let obsolete = pending.removeValue(forKey: name) {
                toDrop.formUnion(obsolete)
            }
        }
        let stillReferenced = Set(pending.values.joined())
        // The pending predecessor map is durable, while the account topology can
        // change again before an earlier save confirmation arrives. The final
        // destructive boundary therefore re-checks the latest accepted live set
        // instead of relying only on the reconciliation that staged the mapping.
        return toDrop.subtracting(stillReferenced).subtracting(liveNames)
    }

    static func retainingObsoletePredecessors(
        in pending: inout [String: Set<String>],
        obsoleteNames: Set<String>)
    {
        pending = pending.compactMapValues { predecessors in
            let live = predecessors.intersection(obsoleteNames)
            return live.isEmpty ? nil : live
        }
    }

    static func assigningPredecessors(
        _ predecessors: Set<String>,
        to replacement: String,
        pending: inout [String: Set<String>])
    {
        if predecessors.isEmpty {
            pending.removeValue(forKey: replacement)
        } else {
            pending[replacement] = predecessors
        }
    }

    /// Stage every sibling mapping before any already-published replacement can
    /// finish migration. This also repairs mappings removed by older builds after
    /// a terminal save skip.
    static func stagePredecessors(
        for snapshots: [AccountSnapshotSyncPayload],
        obsoleteNames: Set<String>,
        pending: inout [String: Set<String>])
    {
        for snapshot in snapshots {
            let predecessors = self.predecessorNames(for: snapshot, obsoleteNames: obsoleteNames)
            // Replace, don't union: a later live email-keyed snapshot must not stay queued
            // for delete after the slot-keyed save is confirmed.
            self.assigningPredecessors(
                predecessors,
                to: snapshot.recordName,
                pending: &pending)
        }
    }

    /// Remove guards owned by replacements that authoritative reconciliation has
    /// removed. A predecessor is released only when no current sibling still
    /// references it and it has not become a live snapshot again.
    static func releasePredecessors(
        forRemovedReplacementNames removedNames: Set<String>,
        liveNames: Set<String>,
        pending: inout [String: Set<String>]) -> Set<String>
    {
        var candidates: Set<String> = []
        for name in removedNames {
            if let predecessors = pending.removeValue(forKey: name) {
                candidates.formUnion(predecessors)
            }
        }
        let stillReferenced = Set(pending.values.joined())
        return candidates.subtracting(stillReferenced).subtracting(liveNames)
    }

    static func cancelledPersistedDeletes(
        pendingDeletes: Set<String>,
        liveNames: Set<String>) -> Set<String>
    {
        pendingDeletes.intersection(liveNames)
    }

    static func pendingDeletesToRequeue(
        pendingDeletes: Set<String>,
        liveNames: Set<String>) -> Set<String>
    {
        pendingDeletes.subtracting(liveNames)
    }

    static func liveSnapshotRecordNames(
        pendingRecordNames: some Sequence<String>,
        storedRecordNames: some Sequence<String>) -> Set<String>
    {
        Set(pendingRecordNames).union(storedRecordNames)
    }

    static func retryableFailedDeletes(
        _ failures: [CKRecord.ID: CKError],
        liveNames: Set<String> = []) -> [CKRecord.ID]
    {
        failures.compactMap { recordID, error in
            guard self.retryDelay(for: error) != nil else { return nil }
            guard !liveNames.contains(recordID.recordName) else { return nil }
            return recordID
        }
    }

    static func reportableFailedDeletes(_ failures: [CKRecord.ID: CKError]) -> [CKError] {
        failures.values.filter { error in
            error.code != .unknownItem && self.retryDelay(for: error) == nil
        }
    }

    /// Delayed retries only for recoverable CloudKit failures. Terminal per-record errors such as
    /// `permissionFailure`, `notAuthenticated`, and `invalidArguments` are reported once.
    static func retryDelay(for error: CKError) -> TimeInterval? {
        switch error.code {
        case .unknownItem, .permissionFailure, .notAuthenticated, .invalidArguments:
            return nil
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .quotaExceeded,
             .serverResponseLost, .accountTemporarilyUnavailable:
            return max(error.retryAfterSeconds ?? 1, 1)
        default:
            guard let retryAfter = error.retryAfterSeconds else { return nil }
            return max(retryAfter, 1)
        }
    }

    static func finishedFailedDeleteNames(_ failures: [CKRecord.ID: CKError]) -> Set<String> {
        Set(failures.compactMap { recordID, error in
            self.retryDelay(for: error) == nil ? recordID.recordName : nil
        })
    }

    /// `unknownItem` confirms that the server no longer has the record, so local caches and
    /// ownership can be cleared. Other terminal failures stop retrying but do not prove deletion.
    static func confirmedMissingDeleteNames(_ failures: [CKRecord.ID: CKError]) -> Set<String> {
        Set(failures.compactMap { recordID, error in
            error.code == .unknownItem ? recordID.recordName : nil
        })
    }

    static func applyConfirmedSaveHashes(
        savedRecordNames: [String],
        pendingSaveHashes: inout [String: String],
        lastSnapshotHashes: inout [String: String])
    {
        for name in savedRecordNames {
            guard let hash = pendingSaveHashes.removeValue(forKey: name) else { continue }
            lastSnapshotHashes[name] = hash
        }
    }

    static func applyTerminalSaveSkip(
        recordName: String,
        error: CKError,
        pendingSaveHashes: inout [String: String],
        skippedTerminalReplacementHashes: inout [String: String])
    {
        guard self.retryDelay(for: error) == nil else { return }
        guard let hash = pendingSaveHashes.removeValue(forKey: recordName) else { return }
        skippedTerminalReplacementHashes[recordName] = hash
    }

    static func hasInFlightSave(recordName: String, pendingSaveHashes: [String: String]) -> Bool {
        pendingSaveHashes[recordName] != nil
    }

    static func mergingPendingSnapshots(
        _ pending: [AccountSnapshotSyncPayload],
        with extras: [AccountSnapshotSyncPayload]) -> [AccountSnapshotSyncPayload]
    {
        var byName: [String: Int] = [:]
        var result = pending
        for (index, payload) in pending.enumerated() {
            byName[payload.recordName] = index
        }
        for payload in extras where byName[payload.recordName] == nil {
            byName[payload.recordName] = result.count
            result.append(payload)
        }
        return result
    }

    static func unpublishedFleetSnapshots(
        savedRecordNames: [String],
        fleetSnapshots: [String: AccountSnapshotSyncPayload],
        lastSnapshotHashes: [String: String]) -> [AccountSnapshotSyncPayload]
    {
        savedRecordNames.compactMap { name in
            guard let payload = fleetSnapshots[name],
                  let hash = try? CanonicalSyncJSON.hash(payload),
                  lastSnapshotHashes[name] != hash
            else { return nil }
            return payload
        }
    }
}

enum CloudSyncLifecycle {
    static func isCurrentEngine(
        originatingEngine: ObjectIdentifier?,
        currentEngine: ObjectIdentifier?) -> Bool
    {
        guard let originatingEngine, let currentEngine else { return false }
        return originatingEngine == currentEngine
    }
}

enum CloudSyncEntitlementGate {
    static let entitlement = "com.apple.developer.icloud-services"

    private static func entitlementValue(_ name: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil)
    }

    static func hasICloudServicesEntitlement() -> Bool {
        (self.entitlementValue(self.entitlement) as? [String])?.contains("CloudKit") == true
    }

    /// Register for CloudKit change pushes only when the signed build carries both the CloudKit
    /// service and a valid push environment; the caller must still be opted in to fleet sync.
    @MainActor
    static func prepareForSync(
        enabled: Bool,
        entitlementValue: (String) -> Any? = Self.entitlementValue,
        register: () -> Void = { NSApplication.shared.registerForRemoteNotifications() }) -> Bool
    {
        guard enabled, (entitlementValue(self.entitlement) as? [String])?.contains("CloudKit") == true else {
            return false
        }
        if let environment = entitlementValue("com.apple.developer.aps-environment") as? String,
           ["development", "production"].contains(environment)
        {
            register()
        }
        return true
    }
}

@MainActor
final class CloudSyncEngine: CKSyncEngineDelegate {
    nonisolated static let containerIdentifier = CloudSyncConstants.containerIdentifier
    nonisolated static let zoneID = CKRecordZone.ID(zoneName: "CodexBarSync", ownerName: CKCurrentUserDefaultName)

    private let settings: SettingsStore
    private let state: CloudSyncState
    private let persistence: CloudSyncPersistence
    private nonisolated let delegateEventQueue = CloudSyncDelegateEventQueue()
    private var persistenceEnvelope: CloudSyncPersistence.Envelope
    private var engine: CKSyncEngine?
    private var engineLease: CloudSyncEngineLease?
    private var desiredRecords: [CKRecord.ID: CKRecord] = [:]
    private var enabled = false
    private var configPushTask: Task<Void, Never>?
    private var snapshotPushTask: Task<Void, Never>?
    private var periodicFetchTask: Task<Void, Never>?
    private var fetchRecoveryCheckpoint: UInt64?
    private var pushRecoveryCheckpoint: UInt64?
    private var fetchHadSuccessfulResponse = false
    private var pushHadSuccessfulResponse = false
    private var pushHadFailure = false
    private var lastSnapshotPushAt: Date?
    private var pendingSnapshots: [AccountSnapshotSyncPayload] = []
    private var pendingSnapshotAuthoritativeProviders: Set<ProviderInstanceID> = []
    private var pendingSnapshotTokenAccountIDs: [String: UUID] = [:]
    private var pendingSnapshotProviderConfigRevisions: [ProviderInstanceID: UInt64] = [:]
    private var latestAcceptedSnapshotPublicationGenerations: [ProviderInstanceID: UInt64] = [:]
    private var lastSnapshotHashes: [String: String] = [:]
    private var skippedTerminalReplacementHashes: [String: String] = [:]
    private var pendingSaveHashes: [String: String] = [:]
    /// Latest accepted producer topology, retained by provider until a newer
    /// publication for that provider arrives. Save callbacks can lag behind a
    /// subsequent topology change, so predecessor deletion must consult this
    /// set at the final destructive boundary.
    private var latestLiveSnapshotRecordNamesByProvider: [ProviderInstanceID: Set<String>] = [:]
    private var lastKnownProviderConfigs: [ProviderInstanceID: ProviderConfig] = [:]
    private var lastAppliedConfigurationRevision: Int
    private var lastKnownPreferences: SyncedPreferences?
    private var lastKnownIncludeSecrets: Bool?
    private var quotaRetryState = CloudSyncQuotaRetryState()
    private var didRehydrateFleetState = false
    /// Restored predecessor mappings must not delete until local live snapshots have been applied.
    private var hasReconciledLiveSnapshots = false
    /// Bumped by every fetched-record apply and engine stop; a suspended apply commits only while current.
    private var applyGeneration = 0
    private let beforeApply: (@Sendable () async -> Void)?
    private let logger = CodexBarLog.logger(LogCategories.settings)

    init(
        settings: SettingsStore,
        state: CloudSyncState,
        persistence: CloudSyncPersistence = CloudSyncPersistence(),
        initialConfiguration: CodexBarConfig? = nil,
        initialConfigurationRevision: Int = 0,
        initialPreferences: SyncedPreferences? = nil,
        initialIncludeSecrets: Bool? = nil,
        beforeApply: (@Sendable () async -> Void)? = nil)
    {
        self.settings = settings
        self.state = state
        self.persistence = persistence
        self.persistenceEnvelope = persistence.load()
        self.lastAppliedConfigurationRevision = initialConfigurationRevision
        if let initialConfiguration {
            self.lastKnownProviderConfigs = Dictionary(
                uniqueKeysWithValues: initialConfiguration.providers.map { ($0.id, $0) })
        }
        self.lastKnownPreferences = initialPreferences
        self.lastKnownIncludeSecrets = initialIncludeSecrets
        self.beforeApply = beforeApply
    }

    func start(enabled: Bool) async {
        guard CloudSyncEntitlementGate.hasICloudServicesEntitlement() else {
            self.state.availability = .missingEntitlement
            return
        }
        self.state.availability = .available
        guard enabled else { return }
        await self.setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        guard enabled else {
            self.engineLease?.invalidate()
            await self.stopEngine(clearPersistence: false)
            return
        }
        guard CloudSyncEntitlementGate.hasICloudServicesEntitlement() else {
            self.state.availability = .missingEntitlement
            return
        }
        do {
            // Snapshot deletion is destructive, so only repair removals from a configuration
            // that was decoded from disk successfully. SettingsStore intentionally falls back
            // to defaults when its startup load fails; that fallback is not removal evidence.
            let currentStartupConfig = self.settings.configSnapshot
            let startupConfiguration = (
                config: currentStartupConfig,
                canDelete: CloudSyncStartupSnapshotDeletionAuthority.loadConfiguration(
                    from: self.settings.configStore,
                    matching: currentStartupConfig) != nil,
                deviceID: self.settings.macFleetSyncDeviceID)
            let startupSnapshotPlan = self.stageSnapshotConfigurationReconciliation(
                previousConfigs: self.lastKnownProviderConfigs,
                currentConfig: startupConfiguration.config,
                authoritativeProviders: startupConfiguration.canDelete
                    ? Set(startupConfiguration.config.providers.map(\.id))
                    : [],
                deviceID: startupConfiguration.deviceID)
            self.persistEnvelope()
            let initialized = try await self.initializeEngineIfNeeded()
            guard self.engine != nil else { return }
            // Re-apply durable cancellations immediately after restoring CKSyncEngine state.
            // A prior launch may have persisted the cancellation before engine initialization,
            // fetch, or queueing failed, leaving the serialized engine with a stale delete.
            self.applySnapshotConfigurationDeletionIntents(
                recordNamesToDelete: self.persistenceEnvelope.snapshotDeletionRecordNames,
                recordNamesToCancel: startupSnapshotPlan.recordNamesToCancel)
            // First sync on this device: apply the fleet's existing state before composing
            // any push. Otherwise a fresh device's records (editCount 1, newer timestamps)
            // win conflict ties against the fleet's records and clobber them server-side.
            if !self.persistenceEnvelope.recordMetadata.keys.contains(where: { $0.hasPrefix("intent-") }) {
                await self.fetchChanges()
            }
            CloudSyncDirtyState.markBootstrapDirtyIfNeeded(
                configuredProviders: self.settings.configSnapshot.providers.map(\.id),
                envelope: &self.persistenceEnvelope)
            self.persistEnvelope()
            try self.queueCurrentConfigurationAndPreferences()
            guard !self.state.status.needsAppUpdate else { return }
            try self.queueDeviceRecord()
            self.startPeriodicFetchTimer()
            self.scheduleFetchChanges(scopedToSyncZone: !initialized)
        } catch {
            self.record(error: error, scope: .push)
        }
    }

    func resumeOrFetch(enabled: Bool) async {
        guard enabled else { return }
        if self.engine == nil {
            await self.start(enabled: true)
        } else {
            await self.fetchChanges()
        }
    }

    func localUserPreferencesDidChange(_ preferences: SyncedPreferences) {
        defer { self.lastKnownPreferences = preferences }
        guard let previous = self.lastKnownPreferences else { return }
        do {
            guard try CanonicalSyncJSON.encode(previous) != CanonicalSyncJSON.encode(preferences) else { return }
            self.persistenceEnvelope.preferencesDirty = true
            self.persistEnvelope()
        } catch {
            self.persistenceEnvelope.preferencesDirty = true
            self.persistEnvelope()
            self.logger.error("Failed to compare synced preferences: \(error)")
        }
    }

    func localIncludeSecretsDidChange(_ includeSecrets: Bool, config: CodexBarConfig) {
        defer { self.lastKnownIncludeSecrets = includeSecrets }
        guard let previous = self.lastKnownIncludeSecrets, previous != includeSecrets else { return }
        self.persistenceEnvelope.dirtyProviders.formUnion(config.providers.map(\.id.rawValue))
        self.persistEnvelope()
    }

    func scheduleConfigurationPush() {
        guard self.enabled, self.engine != nil else { return }
        self.configPushTask?.cancel()
        self.configPushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                try self?.queueCurrentConfigurationAndPreferences()
            } catch is CancellationError {
                return
            } catch {
                self?.record(error: error, scope: .push)
            }
        }
    }

    func fetchChanges(scopedToSyncZone: Bool = true) async {
        guard self.enabled, let engine = self.engine else { return }
        do {
            try await engine.fetchChanges(.init(scope: scopedToSyncZone ? .zoneIDs([Self.zoneID]) : .all))
            self.state.status.lastSuccessfulFetchAt = Date()
        } catch {
            self.record(error: error, scope: .fetch)
        }
    }

    func stop() async {
        self.enabled = false
        self.engineLease?.invalidate()
        await self.stopEngine(clearPersistence: false)
    }

    private func initializeEngineIfNeeded() async throws -> Bool {
        guard self.engine == nil else { return false }
        // This is the first CKContainer access, and every path here has already passed the entitlement gate.
        let container = CKContainer(identifier: Self.containerIdentifier)
        let accountStatus = try await container.accountStatus()
        switch accountStatus {
        case .available:
            self.state.availability = .available
        case .restricted:
            self.state.availability = .restricted
            return false
        case .noAccount, .couldNotDetermine, .temporarilyUnavailable:
            self.state.availability = .noICloudAccount
            return false
        @unknown default:
            self.state.availability = .noICloudAccount
            return false
        }

        // The account-status await can overlap an opt-out or another activation; re-check both
        // before registering for pushes or creating an engine.
        guard CloudSyncEntitlementGate.prepareForSync(enabled: self.settings.macFleetSyncEnabled),
              self.enabled, self.engine == nil else { return false }
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: self.persistenceEnvelope.stateSerialization,
            delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engineLease?.invalidate()
        self.engine = engine
        self.engineLease = CloudSyncEngineLease()
        self.rehydrateFleetStateIfNeeded()
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        return true
    }

    private func queueCurrentConfigurationAndPreferences() throws {
        guard let engine = self.engine else { return }
        if self.persistenceEnvelope.recordMetadata.values.contains(where: {
            ($0.schemaVersion ?? 0) > CodexBarSyncSchema.currentVersion
        }) {
            self.state.status.needsAppUpdate = true
            return
        }
        let snapshot = (
            config: self.settings.configSnapshot,
            includeSecrets: self.settings.macFleetSyncIncludeSecrets,
            preferences: self.settings.syncedPreferences)
        for config in snapshot.config.providers where self.lastKnownProviderConfigs[config.id] == nil {
            self.lastKnownProviderConfigs[config.id] = config
        }
        if self.lastKnownPreferences == nil {
            self.lastKnownPreferences = snapshot.preferences
        }
        if self.lastKnownIncludeSecrets == nil {
            self.lastKnownIncludeSecrets = snapshot.includeSecrets
        }
        let recordNames = CloudSyncDirtyState.configurationRecordNamesToQueue(
            envelope: self.persistenceEnvelope,
            configuredProviders: snapshot.config.providers.map(\.id))
        for config in snapshot.config.providers
            where recordNames.contains(ProviderIntentPayload.recordName(for: config.id))
        {
            try self.queueProviderIntent(config, includeSecrets: snapshot.includeSecrets, engine: engine)
        }
        if recordNames.contains(PreferencesSyncPayload.recordName) {
            try self.queuePreferences(snapshot.preferences, engine: engine)
        }
    }

    private func queueProviderIntent(
        _ config: ProviderConfig,
        includeSecrets: Bool,
        engine: CKSyncEngine) throws
    {
        let intent = Self.providerIntentPayload(
            config: config,
            suppressedEnableIntents: self.persistenceEnvelope.suppressedEnableIntents)
        let payload = try CanonicalSyncJSON.string(intent)
        let recordID = self.recordID(named: ProviderIntentPayload.recordName(for: config.id))
        let record = self.record(type: .providerIntent, id: recordID)
        let existingSecretKeys = Set(record.encryptedValues.allKeys())
        let secretFields = try ProviderIntentPayload.secretFields(
            for: config,
            includeSecrets: includeSecrets,
            previouslyUploadedFields: existingSecretKeys)
        let unchanged = (record["payload"] as? String) == payload
            && self.encryptedStringFields(record) == secretFields
        guard !unchanged else { return }

        record["schemaVersion"] = CodexBarSyncSchema.currentVersion as CKRecordValue
        record["provider"] = config.id.rawValue as CKRecordValue
        record["payload"] = payload as CKRecordValue
        record["editCount"] = (self.editCount(record) + 1) as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue
        for field in ProviderIntentSecretField.allCases {
            record.encryptedValues[field.rawValue] = nil
        }
        for (key, value) in secretFields {
            record.encryptedValues[key] = value as CKRecordValue
        }
        self.desiredRecords[recordID] = record
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    nonisolated static func providerIntentPayload(
        config: ProviderConfig,
        suppressedEnableIntents: Set<String>) -> ProviderIntentPayload
    {
        var payload = ProviderIntentPayload(config: config)
        if suppressedEnableIntents.contains(config.id.rawValue), config.enabled != true {
            payload.enabled = true
        }
        return payload
    }

    private func queuePreferences(_ preferences: SyncedPreferences, engine: CKSyncEngine) throws {
        let payload = try CanonicalSyncJSON.string(PreferencesSyncPayload(preferences: preferences))
        let recordID = self.recordID(named: PreferencesSyncPayload.recordName)
        let record = self.record(type: .preferences, id: recordID)
        guard (record["payload"] as? String) != payload else { return }
        record["schemaVersion"] = CodexBarSyncSchema.currentVersion as CKRecordValue
        record["payload"] = payload as CKRecordValue
        record["editCount"] = (self.editCount(record) + 1) as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue
        self.desiredRecords[recordID] = record
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    private func queueDeviceRecord() throws {
        guard let engine = self.engine else { return }
        let deviceID = self.settings.macFleetSyncDeviceID
        let payload = DeviceSyncPayload(
            deviceID: deviceID,
            hostName: ProcessInfo.processInfo.hostName,
            model: Self.deviceModel(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            lastSeen: Date())
        let recordID = self.recordID(named: payload.recordName)
        let record = self.record(type: .device, id: recordID)
        record["schemaVersion"] = payload.schemaVersion as CKRecordValue
        record["deviceID"] = payload.deviceID as CKRecordValue
        record["hostName"] = payload.hostName as CKRecordValue
        record["model"] = payload.model as CKRecordValue
        record["appVersion"] = payload.appVersion as CKRecordValue
        record["lastSeen"] = payload.lastSeen as CKRecordValue
        self.desiredRecords[recordID] = record
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        self.persistenceEnvelope.fleetDevices[payload.recordName] = payload
        self.state.fleetDevices[payload.recordName] = payload
        self.persistEnvelope()
    }

    // MARK: CKSyncEngineDelegate

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        self.delegateEventQueue.enqueue { [weak self] in
            await self?.processEvent(event, syncEngine: syncEngine)
        }
    }

    private func processErrorRecoveryEvent(_ event: CKSyncEngine.Event) -> Bool {
        switch event {
        case .willFetchChanges:
            self.fetchRecoveryCheckpoint = self.state.errorRevision
            self.fetchHadSuccessfulResponse = false
        case let .didFetchRecordZoneChanges(changes):
            if let error = changes.error {
                self.record(error: error, scope: .fetch)
            } else {
                self.fetchHadSuccessfulResponse = true
            }
        case .didFetchChanges:
            if let checkpoint = self.fetchRecoveryCheckpoint {
                self.state.finishErrorRecovery(
                    scope: .fetch,
                    startedAt: checkpoint,
                    succeeded: self.fetchHadSuccessfulResponse)
            }
            self.fetchRecoveryCheckpoint = nil
        case .willSendChanges:
            self.pushRecoveryCheckpoint = self.state.errorRevision
            self.pushHadSuccessfulResponse = false
            self.pushHadFailure = false
        case .didSendChanges:
            if let checkpoint = self.pushRecoveryCheckpoint {
                self.state.finishErrorRecovery(
                    scope: .push,
                    startedAt: checkpoint,
                    succeeded: self.pushHadSuccessfulResponse && !self.pushHadFailure)
            }
            self.pushRecoveryCheckpoint = nil
        case let .sentDatabaseChanges(changes):
            self.pushHadSuccessfulResponse = self.pushHadSuccessfulResponse ||
                !changes.savedZones.isEmpty || !changes.deletedZoneIDs.isEmpty
            for error in changes.failedZoneSaves.map(\.error) + Array(changes.failedZoneDeletes.values) {
                self.pushHadFailure = true
                self.record(error: error, scope: .push)
            }
        default:
            return false
        }
        return true
    }

    private func processEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // Retired records, recovery checkpoints, and their fetch checkpoint must be discarded together.
        guard self.enabled, self.engine === syncEngine, !Task.isCancelled else { return }
        if self.processErrorRecoveryEvent(event) { return }
        switch event {
        case let .stateUpdate(update):
            self.persistenceEnvelope.stateSerialization = update.stateSerialization
            self.persistEnvelope()
        case let .accountChange(change):
            switch change.changeType {
            case .signOut, .switchAccounts:
                await self.stopEngine(clearPersistence: true)
            case .signIn:
                break
            @unknown default:
                await self.stopEngine(clearPersistence: true)
            }
        case let .fetchedRecordZoneChanges(changes):
            self.fetchHadSuccessfulResponse = true
            await self.applyFetchedRecords(changes.modifications.map(\.record))
            guard self.engine === syncEngine, !Task.isCancelled else { return }
            self.applyDeletedRecords(changes.deletions.map(\.recordID.recordName))
            self.state.status.lastSuccessfulFetchAt = Date()
        case let .sentRecordZoneChanges(changes):
            self.pushHadSuccessfulResponse = self.pushHadSuccessfulResponse ||
                !changes.savedRecords.isEmpty || !changes.deletedRecordIDs.isEmpty ||
                changes.failedRecordDeletes.values.contains { $0.code == .unknownItem }
            if !changes.failedRecordSaves.isEmpty ||
                changes.failedRecordDeletes.values.contains(where: { $0.code != .unknownItem })
            {
                self.pushHadFailure = true
            }
            if !changes.savedRecords.isEmpty || !changes.deletedRecordIDs.isEmpty {
                self.quotaRetryState.reset()
            }
            for record in changes.savedRecords {
                self.cacheSystemFields(record)
                self.desiredRecords.removeValue(forKey: record.recordID)
            }
            CloudSyncDirtyState.clearSavedRecords(
                changes.savedRecords.map(\.recordID.recordName),
                envelope: &self.persistenceEnvelope)
            // Evaluate confirmed saves before abandoning terminal failures so a mixed batch
            // still counts a failed sibling's shared predecessor as referenced.
            self.finishConfirmedSnapshotMigrations(
                savedRecordNames: changes.savedRecords.map(\.recordID.recordName),
                syncEngine: syncEngine)
            self.removeDeletedRecordsFromCaches(changes.deletedRecordIDs.map(\.recordName))
            for failure in changes.failedRecordSaves {
                await self.handleSaveFailure(failure.record, error: failure.error, syncEngine: syncEngine)
            }
            self.handleSentRecordDeletes(
                deletedIDs: changes.deletedRecordIDs,
                failures: changes.failedRecordDeletes)
            self.persistEnvelope()
            if !changes.savedRecords.isEmpty || !changes.deletedRecordIDs.isEmpty {
                self.state.status.lastSuccessfulPushAt = Date()
            }
            if !self.pendingSnapshots.isEmpty {
                Task { [weak self] in
                    self?.pushPendingSnapshots()
                }
            }
        case let .fetchedDatabaseChanges(changes):
            self.fetchHadSuccessfulResponse = true
            if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            }
        default:
            break
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch?
    {
        await self.makeChangeBatch(context, syncEngine: syncEngine)
    }

    private func makeChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch?
    {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter(context.options.scope.contains)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] recordID in
            guard let self else { return nil }
            return await self.recordForPendingSave(recordID, syncEngine: syncEngine)
        }
    }

    func recordForPendingSave(_ recordID: CKRecord.ID, syncEngine: CKSyncEngine? = nil) -> CKRecord? {
        CloudSyncBatchRecordProvider.record(for: recordID, desiredRecords: self.desiredRecords) { change in
            syncEngine?.state.remove(pendingRecordZoneChanges: [change])
        }
    }

    func applyFetchedRecords(_ records: [CKRecord], errorScope: CloudSyncErrorScope = .fetch) async {
        guard !Task.isCancelled else { return }
        self.applyGeneration &+= 1
        let generation = self.applyGeneration
        guard await self.applyIfCurrent(generation, body: {
            if records.contains(where: { self.schemaVersion($0) > CodexBarSyncSchema.currentVersion }) {
                self.state.status.needsAppUpdate = true
                records.forEach(self.cacheSystemFields)
                return false
            }
            return true
        }) == true else { return }

        for record in records {
            do {
                guard try await self.applyIfCurrent(generation, body: {
                    self.cacheSystemFields(record)
                    guard self.shouldApplyServerRecord(record) else { return }
                    switch record.recordType {
                    case SyncRecordType.providerIntent.rawValue:
                        try self.applyProviderIntent(record)
                    case SyncRecordType.preferences.rawValue:
                        try self.applyPreferences(record)
                    case SyncRecordType.device.rawValue:
                        self.applyDevice(record)
                    case SyncRecordType.accountSnapshot.rawValue:
                        try self.applyAccountSnapshot(record)
                    default:
                        break
                    }
                }) != nil else { return }
            } catch {
                self.record(error: error, scope: errorScope)
            }
        }
    }

    /// Validate after suspension, then commit settings and bookkeeping without another actor hop.
    private func applyIfCurrent<Value>(_ generation: Int, body: () throws -> Value) async rethrows -> Value? {
        await self.beforeApply?()
        guard !Task.isCancelled, generation == self.applyGeneration,
              !self.state.status.needsAppUpdate else { return nil }
        return try body()
    }

    private func shouldApplyServerRecord(_ server: CKRecord) -> Bool {
        guard let engine = self.engine,
              engine.state.pendingRecordZoneChanges.contains(.saveRecord(server.recordID)),
              let local = self.desiredRecords[server.recordID],
              server.recordType == SyncRecordType.providerIntent.rawValue
              || server.recordType == SyncRecordType.preferences.rawValue
        else {
            return true
        }
        guard self.localWinsConflict(local, server: server) else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
            self.desiredRecords.removeValue(forKey: server.recordID)
            return true
        }
        let rebased = Self.copyUserFields(from: local, onto: server)
        self.desiredRecords[server.recordID] = rebased
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
        return false
    }

    private func applyPreferences(_ record: CKRecord) throws {
        guard let payloadString = record["payload"] as? String else { return }
        let payload = try CanonicalSyncJSON.decode(PreferencesSyncPayload.self, from: payloadString)
        self.lastKnownPreferences = payload.preferences
        self.settings.applySyncedPreferences(payload.preferences)
    }

    private func applyDevice(_ record: CKRecord) {
        guard let deviceID = record["deviceID"] as? String,
              let hostName = record["hostName"] as? String,
              let model = record["model"] as? String,
              let appVersion = record["appVersion"] as? String,
              let lastSeen = record["lastSeen"] as? Date
        else { return }
        let payload = DeviceSyncPayload(
            deviceID: deviceID,
            hostName: hostName,
            model: model,
            appVersion: appVersion,
            lastSeen: lastSeen,
            schemaVersion: self.schemaVersion(record))
        self.persistenceEnvelope.fleetDevices[record.recordID.recordName] = payload
        self.state.fleetDevices[record.recordID.recordName] = payload
    }

    private func applyAccountSnapshot(_ record: CKRecord) throws {
        guard !CloudSyncSnapshotMigration.hasInFlightSave(
            recordName: record.recordID.recordName,
            pendingSaveHashes: self.pendingSaveHashes)
        else { return }
        guard let providerRaw = record["provider"] as? String,
              let provider = ProviderInstanceID(rawValue: providerRaw),
              let deviceID = record["deviceID"] as? String,
              let accountKey = record["accountKey"] as? String,
              let fetchedAt = record["fetchedAt"] as? Date,
              let displayLabel = record.encryptedValues["displayLabel"] as? String,
              let usagePayload = record.encryptedValues["usagePayload"] as? String
        else { return }
        let usage = try CanonicalSyncJSON.decode(UsageSnapshot.self, from: usagePayload)
        let payload = AccountSnapshotSyncPayload(
            provider: provider,
            deviceID: deviceID,
            accountKey: accountKey,
            fetchedAt: fetchedAt,
            displayLabel: displayLabel,
            usage: usage,
            schemaVersion: self.schemaVersion(record))
        self.persistenceEnvelope.fleetSnapshots[record.recordID.recordName] = payload
        self.state.fleetSnapshots[record.recordID.recordName] = payload
    }

    func handleSaveFailure(
        _ record: CKRecord,
        error: CKError,
        syncEngine: CKSyncEngine? = nil) async
    {
        guard syncEngine == nil || (self.enabled && self.engine === syncEngine) else { return }
        switch error.code {
        case .quotaExceeded:
            let retry = self.quotaRetryState.nextDelay(serverRetryAfter: error.retryAfterSeconds)
            self.scheduleRetry(recordID: record.recordID, after: retry)
        case .accountTemporarilyUnavailable:
            let retry = CloudSyncSnapshotMigration.retryDelay(for: error) ?? 1
            self.scheduleRetry(recordID: record.recordID, after: retry)
        case .serverRecordChanged:
            guard let server = error.serverRecord else {
                self.record(error: error, scope: .push)
                self.pendingSaveHashes.removeValue(forKey: record.recordID.recordName)
                return
            }
            if let syncEngine { await self.resolveConflict(with: server, syncEngine: syncEngine) }
        case .unknownItem where record.recordChangeTag != nil
            || self.persistenceEnvelope.encodedSystemFields[record.recordID.recordName] != nil:
            // The server dropped a record this Mac had saved before (for example, another Mac
            // removed this one). Forget the stale system fields and recreate it once.
            await self.applyIfCurrent(self.applyGeneration) {
                let name = record.recordID.recordName
                self.persistenceEnvelope.encodedSystemFields.removeValue(forKey: name)
                self.persistenceEnvelope.recordMetadata.removeValue(forKey: name)
                self.lastSnapshotHashes.removeValue(forKey: name)
                self.skippedTerminalReplacementHashes.removeValue(forKey: name)
                // Rebuild the prepared record too; clearing the persisted change tag alone cannot heal this save.
                let desired = self.desiredRecords[record.recordID] ?? record
                self.desiredRecords[record.recordID] = Self.copyUserFields(
                    from: desired, onto: CKRecord(recordType: desired.recordType, recordID: record.recordID))
                self.persistEnvelope()
                syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }
        case .zoneNotFound:
            self.recreateZoneAndRequeue(record, syncEngine: syncEngine)
        default:
            let resetEncryptedData = (error.userInfo[CKErrorUserDidResetEncryptedDataKey] as? NSNumber)?
                .boolValue == true
            if resetEncryptedData {
                self.recreateZoneAndRequeue(record, syncEngine: syncEngine)
            } else {
                self.record(error: error, scope: .push)
                self.skipTerminalReplacementSave(recordName: record.recordID.recordName, error: error)
            }
        }
    }

    private func recreateZoneAndRequeue(_ record: CKRecord, syncEngine: CKSyncEngine?) {
        if self.desiredRecords[record.recordID] == nil {
            self.desiredRecords[record.recordID] = record
        }
        syncEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
    }

    private func resolveConflict(with server: CKRecord, syncEngine: CKSyncEngine) async {
        guard self.schemaVersion(server) <= CodexBarSyncSchema.currentVersion else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
            self.desiredRecords.removeValue(forKey: server.recordID)
            self.pendingSaveHashes.removeValue(forKey: server.recordID.recordName)
            self.cacheSystemFields(server)
            self.persistEnvelope()
            self.state.status.needsAppUpdate = true
            return
        }
        guard let local = self.desiredRecords[server.recordID] else { return }
        self.cacheSystemFields(server)
        if self.localWinsConflict(local, server: server) {
            self.desiredRecords[server.recordID] = Self.copyUserFields(from: local, onto: server)
            self.scheduleRetry(recordID: server.recordID, after: 0)
        } else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
            self.desiredRecords.removeValue(forKey: server.recordID)
            self.pendingSaveHashes.removeValue(forKey: server.recordID.recordName)
            await self.applyFetchedRecords([server], errorScope: .push)
        }
    }

    private func localWinsConflict(_ local: CKRecord, server: CKRecord) -> Bool {
        let localValue = SyncConflictValue(
            value: local,
            editCount: self.editCount(local),
            modifiedAt: self.modifiedAt(local))
        let serverValue = SyncConflictValue(
            value: server, editCount: self.editCount(server), modifiedAt: self.modifiedAt(server))
        return SyncConflictResolver.winner(local: localValue, server: serverValue).value === local
    }

    private func scheduleFetchChanges(scopedToSyncZone: Bool) {
        Task { [weak self] in
            await Task.yield()
            await self?.fetchChanges(scopedToSyncZone: scopedToSyncZone)
        }
    }

    private func startPeriodicFetchTimer() {
        self.periodicFetchTask?.cancel()
        self.periodicFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15 * 60))
                } catch {
                    return
                }
                await self?.fetchChanges()
            }
        }
    }

    private func stopEngine(clearPersistence: Bool) async {
        // Retire the engine synchronously before the cancellation await so queued events,
        // suspended applies, and delayed retries all observe the stop.
        self.applyGeneration &+= 1
        self.engineLease?.invalidate()
        self.engineLease = nil
        let retiringEngine = self.engine
        self.engine = nil
        self.configPushTask?.cancel()
        self.snapshotPushTask?.cancel()
        self.periodicFetchTask?.cancel()
        self.desiredRecords = [:]
        self.quotaRetryState.reset()
        self.pendingSaveHashes = [:]
        self.pendingSnapshots = []
        self.pendingSnapshotAuthoritativeProviders = []
        self.pendingSnapshotTokenAccountIDs = [:]
        self.pendingSnapshotProviderConfigRevisions = [:]
        self.latestLiveSnapshotRecordNamesByProvider = [:]
        self.hasReconciledLiveSnapshots = false
        if clearPersistence {
            self.persistenceEnvelope = .init(stateSerialization: nil, encodedSystemFields: [:])
            self.lastSnapshotHashes = [:]
            self.skippedTerminalReplacementHashes = [:]
            self.didRehydrateFleetState = false
            try? self.persistence.delete()
            self.state.fleetDevices = [:]
            self.state.fleetSnapshots = [:]
        }
        await retiringEngine?.cancelOperations()
    }

    private func rehydrateFleetStateIfNeeded() {
        guard !self.didRehydrateFleetState else { return }
        self.didRehydrateFleetState = true
        self.state.fleetDevices = self.persistenceEnvelope.fleetDevices
        self.state.fleetSnapshots = self.persistenceEnvelope.fleetSnapshots
    }

    private func record(type: SyncRecordType, id: CKRecord.ID) -> CKRecord {
        if let data = self.persistenceEnvelope.encodedSystemFields[id.recordName],
           let record = CloudSyncPersistence.decodeRecord(from: data),
           record.recordType == type.rawValue
        {
            if let metadata = self.persistenceEnvelope.recordMetadata[id.recordName] {
                if let schemaVersion = metadata.schemaVersion {
                    record["schemaVersion"] = schemaVersion as CKRecordValue
                }
                if let editCount = metadata.editCount {
                    record["editCount"] = editCount as CKRecordValue
                }
                if let modifiedAt = metadata.modifiedAt {
                    record["modifiedAt"] = modifiedAt as CKRecordValue
                }
            }
            return record
        }
        return CKRecord(recordType: type.rawValue, recordID: id)
    }

    private func recordID(named recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: Self.zoneID)
    }

    private func cacheSystemFields(_ record: CKRecord) {
        CloudSyncPersistence.cacheSystemFields(of: record, in: &self.persistenceEnvelope)
    }

    private func persistEnvelope() {
        do {
            try self.persistence.save(self.persistenceEnvelope)
        } catch {
            self.logger.error("Failed to persist CloudKit sync state: \(error)")
        }
    }

    private func encryptedStringFields(_ record: CKRecord) -> [String: String] {
        Dictionary(uniqueKeysWithValues: record.encryptedValues.allKeys().compactMap { key in
            (record.encryptedValues[key] as? String).map { (key, $0) }
        })
    }

    nonisolated static func copyUserFields(from source: CKRecord, onto server: CKRecord) -> CKRecord {
        // allKeys() includes encrypted field names, but CloudKit throws NSInvalidArgumentException
        // when an encrypted field goes through the plain subscript — every key must stay on the
        // API surface (plain vs encryptedValues) it was written with.
        let serverEncryptedKeys = Set(server.encryptedValues.allKeys())
        let sourceEncryptedKeys = Set(source.encryptedValues.allKeys())
        for key in server.allKeys() where !serverEncryptedKeys.contains(key) {
            server[key] = nil
        }
        for key in serverEncryptedKeys {
            server.encryptedValues[key] = nil
        }
        for key in source.allKeys() where !sourceEncryptedKeys.contains(key) {
            server[key] = source[key]
        }
        for key in sourceEncryptedKeys {
            server.encryptedValues[key] = source.encryptedValues[key]
        }
        return server
    }

    private func editCount(_ record: CKRecord) -> Int64 {
        (record["editCount"] as? NSNumber)?.int64Value ?? 0
    }

    private func modifiedAt(_ record: CKRecord) -> Date {
        record["modifiedAt"] as? Date ?? .distantPast
    }

    private func schemaVersion(_ record: CKRecord) -> Int {
        (record["schemaVersion"] as? NSNumber)?.intValue ?? 0
    }

    private func record(error: Error, scope: CloudSyncErrorScope) {
        self.logger.error("iCloud sync failed: \(error)")
        self.state.recordError(error.localizedDescription, scope: scope)
    }

    private static func deviceModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }
}

extension CloudSyncEngine {
    /// Runs inside the fetched-record apply boundary: the settings write, the snapshot
    /// reconciliation for the new configuration, and the sync bookkeeping commit together.
    private func applyProviderIntent(_ record: CKRecord) throws {
        guard let payloadString = record["payload"] as? String else { return }
        let payload = try CanonicalSyncJSON.decode(ProviderIntentPayload.self, from: payloadString)
        let secrets = self.encryptedStringFields(record)
        let previousConfig = self.settings.configSnapshot
        var config = previousConfig
        guard let local = config.providerConfig(for: payload.provider) else { return }
        let merged = try payload.applying(
            to: local,
            secretFields: self.settings.macFleetSyncIncludeSecrets ? secrets : [:],
            canEnable: self.settings.canEnableProviderFromSync)
        config.setProviderConfig(merged)
        self.settings.applyExternalConfig(config, reason: "icloud", affectsBackgroundWork: true)
        // applyExternalConfig deliberately skips persistence (its other caller reloads FROM
        // the config file). Sync applies originate remotely, so the merge must reach disk —
        // the CLI and the next app launch read config.json, not our in-memory state.
        self.settings.schedulePersistConfig()
        self.externalConfigurationDidChange(
            previousConfig: previousConfig,
            currentConfig: self.settings.configSnapshot,
            revision: self.settings.configRevision,
            deviceID: self.settings.macFleetSyncDeviceID)
        if payload.enabled == true, merged.enabled != true {
            self.persistenceEnvelope.suppressedEnableIntents.insert(payload.provider.rawValue)
        } else {
            self.persistenceEnvelope.suppressedEnableIntents.remove(payload.provider.rawValue)
        }
        self.persistEnvelope()
    }

    func localUserConfigurationDidChange(
        _ config: CodexBarConfig,
        revision: Int? = nil,
        deviceID: String? = nil)
    {
        guard self.acceptConfigurationRevision(revision) else { return }
        let resolvedDeviceID = deviceID ?? self.settings.macFleetSyncDeviceID
        let previousConfigs = self.lastKnownProviderConfigs
        let snapshotPlan = self.stageLocalConfigurationChanges(
            previousConfigs: previousConfigs,
            currentConfig: config,
            deviceID: resolvedDeviceID)
        self.lastKnownProviderConfigs = Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0) })
        self.persistEnvelope()
        self.applySnapshotConfigurationDeletionIntents(
            recordNamesToDelete: snapshotPlan.recordNamesToDelete,
            recordNamesToCancel: snapshotPlan.recordNamesToCancel)
    }

    private func stageLocalConfigurationChanges(
        previousConfigs: [ProviderInstanceID: ProviderConfig],
        currentConfig config: CodexBarConfig,
        deviceID: String) -> CloudSyncSnapshotConfigurationReconciliation.Plan
    {
        let snapshotPlan = self.stageSnapshotConfigurationReconciliation(
            previousConfigs: previousConfigs,
            currentConfig: config,
            authoritativeProviders: self.providersWithChangedTokenAccounts(
                previousConfigs: previousConfigs,
                currentConfig: config),
            deviceID: deviceID)
        let previousSuppressedEnableIntents = self.persistenceEnvelope.suppressedEnableIntents
        for providerConfig in config.providers {
            if let previous = previousConfigs[providerConfig.id],
               previous.enabled != providerConfig.enabled
            {
                self.persistenceEnvelope.suppressedEnableIntents.remove(providerConfig.id.rawValue)
            }
            guard let previous = previousConfigs[providerConfig.id] else {
                self.persistenceEnvelope.dirtyProviders.insert(providerConfig.id.rawValue)
                continue
            }
            do {
                if try CloudSyncDirtyState.providerSyncContentChanged(
                    from: previous,
                    previousSuppressedEnableIntents: previousSuppressedEnableIntents,
                    to: providerConfig,
                    currentSuppressedEnableIntents: self.persistenceEnvelope.suppressedEnableIntents)
                {
                    self.persistenceEnvelope.dirtyProviders.insert(providerConfig.id.rawValue)
                }
            } catch {
                self.persistenceEnvelope.dirtyProviders.insert(providerConfig.id.rawValue)
                self.logger.error("Failed to compare provider sync content: \(error)")
            }
        }
        return snapshotPlan
    }

    func externalConfigurationDidChange(
        previousConfig: CodexBarConfig,
        currentConfig: CodexBarConfig,
        revision: Int,
        deviceID: String)
    {
        guard self.acceptConfigurationRevision(revision) else { return }
        let previousConfigs = Dictionary(uniqueKeysWithValues: previousConfig.providers.map { ($0.id, $0) })
        // A remote apply can overtake a queued local notification. Preserve any local delta
        // already present in the remote transition's previousConfig before advancing the
        // baseline to the newer external revision.
        let overtakenLocalPlan = self.stageLocalConfigurationChanges(
            previousConfigs: self.lastKnownProviderConfigs,
            currentConfig: previousConfig,
            deviceID: deviceID)
        let snapshotPlan = self.stageSnapshotConfigurationReconciliation(
            previousConfigs: previousConfigs,
            currentConfig: currentConfig,
            authoritativeProviders: self.providersWithChangedTokenAccounts(
                previousConfigs: previousConfigs,
                currentConfig: currentConfig),
            deviceID: deviceID)
        self.lastKnownProviderConfigs = Dictionary(
            uniqueKeysWithValues: currentConfig.providers.map { ($0.id, $0) })
        self.persistEnvelope()
        self.applySnapshotConfigurationDeletionIntents(
            recordNamesToDelete: snapshotPlan.recordNamesToDelete,
            recordNamesToCancel: overtakenLocalPlan.recordNamesToCancel.union(snapshotPlan.recordNamesToCancel))
    }

    private func acceptConfigurationRevision(_ revision: Int?) -> Bool {
        guard let revision else { return true }
        guard revision > self.lastAppliedConfigurationRevision else { return false }
        self.lastAppliedConfigurationRevision = revision
        return true
    }

    private func stageSnapshotConfigurationReconciliation(
        previousConfigs: [ProviderInstanceID: ProviderConfig],
        currentConfig: CodexBarConfig,
        authoritativeProviders: Set<ProviderInstanceID>,
        deviceID: String) -> CloudSyncSnapshotConfigurationReconciliation.Plan
    {
        var candidateSnapshots = self.persistenceEnvelope.fleetSnapshots
        for snapshot in self.pendingSnapshots {
            candidateSnapshots[snapshot.recordName] = snapshot
        }
        var ownershipKnownRecordNames = self.persistenceEnvelope.snapshotOwnershipKnownRecordNames
        ownershipKnownRecordNames.formUnion(self.pendingSnapshots.map(\.recordName))
        var tokenAccountIDsByRecordName = self.persistenceEnvelope.snapshotTokenAccountIDs
        tokenAccountIDsByRecordName.merge(self.pendingSnapshotTokenAccountIDs) { _, pending in pending }
        let snapshotPlan = CloudSyncSnapshotConfigurationReconciliation.plan(
            previousConfigs: previousConfigs,
            currentConfig: currentConfig,
            authoritativeProviders: authoritativeProviders,
            state: .init(
                candidateSnapshots: candidateSnapshots,
                ownershipKnownRecordNames: ownershipKnownRecordNames,
                tokenAccountIDsByRecordName: tokenAccountIDsByRecordName,
                deviceID: deviceID,
                pendingRecordNames: self.persistenceEnvelope.snapshotDeletionRecordNames))
        self.persistenceEnvelope.snapshotDeletionRecordNames = snapshotPlan.pendingRecordNames
        self.stageSnapshotDeletionIntents(
            recordNamesToDelete: snapshotPlan.recordNamesToDelete,
            recordNamesToCancel: snapshotPlan.recordNamesToCancel)
        self.persistenceEnvelope.snapshotOwnershipKnownRecordNames = snapshotPlan.ownershipKnownRecordNames
        self.persistenceEnvelope.snapshotTokenAccountIDs = snapshotPlan.tokenAccountIDsByRecordName
        self.pendingSnapshotAuthoritativeProviders.subtract(snapshotPlan.providersRequiringFreshAuthority)
        return snapshotPlan
    }

    private func stageSnapshotDeletionIntents(
        recordNamesToDelete: Set<String>,
        recordNamesToCancel: Set<String>)
    {
        // Cancellation intent is local-only and deliberately outlives one CKSyncEngine
        // instance. A later authoritative delete supersedes the cancellation.
        self.persistenceEnvelope.snapshotDeletionCancellationRecordNames.formUnion(recordNamesToCancel)
        self.persistenceEnvelope.snapshotDeletionCancellationRecordNames.subtract(recordNamesToDelete)
    }

    private func providersWithChangedTokenAccounts(
        previousConfigs: [ProviderInstanceID: ProviderConfig],
        currentConfig: CodexBarConfig) -> Set<ProviderInstanceID>
    {
        let currentConfigs = Dictionary(uniqueKeysWithValues: currentConfig.providers.map { ($0.id, $0) })
        return Set(previousConfigs.keys).union(currentConfigs.keys).filter { provider in
            let previousIDs = Set(previousConfigs[provider]?.tokenAccounts?.accounts.map(\.id) ?? [])
            let currentIDs = Set(currentConfigs[provider]?.tokenAccounts?.accounts.map(\.id) ?? [])
            return previousIDs != currentIDs
        }
    }

    func queueSnapshots(
        _ snapshots: [AccountSnapshotSyncPayload],
        authoritativeProviders: Set<ProviderInstanceID>,
        sourceProviderConfigRevisions: [ProviderInstanceID: UInt64],
        sourceProviderPublicationGenerations: [ProviderInstanceID: UInt64],
        tokenAccountIDsByRecordName: [String: UUID]) async
    {
        guard self.enabled, self.engine != nil else { return }
        let options = (
            enabled: self.settings.macFleetSyncSnapshotsEnabled,
            lowPower: self.settings.backgroundWorkLowPowerModeEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled,
            needsAppUpdate: self.state.status.needsAppUpdate)
        guard options.enabled, !options.lowPower, !options.needsAppUpdate else { return }
        let sourceProviders = Set(sourceProviderConfigRevisions.keys)
        let pendingProviders = Set(self.pendingSnapshotProviderConfigRevisions.keys)
        let providersToValidate = sourceProviders.union(pendingProviders)
        let currentPublicationState = (
            enabledProviders: Set(self.settings.enabledProvidersOrdered(
                metadataByProvider: ProviderDescriptorRegistry.metadata)),
            providerConfigRevisions: Dictionary(uniqueKeysWithValues: providersToValidate.map {
                ($0, self.settings.providerInstanceConfigRevision(for: $0))
            }),
            activeTokenAccountIDs: Set(self.settings.configSnapshot.providers.flatMap {
                $0.tokenAccounts?.accounts.map(\.id) ?? []
            }))
        let revisionAcceptedProviders = CloudSyncSnapshotPublicationRevisionGate.acceptedProviders(
            claimedProviders: sourceProviders,
            sourceRevisions: sourceProviderConfigRevisions,
            currentRevisions: currentPublicationState.providerConfigRevisions)
        let generationAcceptedProviders = CloudSyncSnapshotPublicationGenerationGate.acceptedProviders(
            claimedProviders: revisionAcceptedProviders,
            sourceGenerations: sourceProviderPublicationGenerations,
            latestAcceptedGenerations: self.latestAcceptedSnapshotPublicationGenerations)
        let acceptedPublicationProviders = revisionAcceptedProviders.intersection(generationAcceptedProviders)
        for provider in acceptedPublicationProviders {
            self.latestAcceptedSnapshotPublicationGenerations[provider] = sourceProviderPublicationGenerations[provider]
        }
        let acceptedProviderConfigRevisions = sourceProviderConfigRevisions.filter {
            acceptedPublicationProviders.contains($0.key)
        }
        var acceptedAuthoritativeProviders = authoritativeProviders.intersection(acceptedPublicationProviders)
        let currentSnapshots = snapshots.filter { acceptedPublicationProviders.contains($0.provider) }
        for provider in acceptedPublicationProviders {
            self.latestLiveSnapshotRecordNamesByProvider[provider] = Set(
                currentSnapshots.lazy.filter { $0.provider == provider }.map(\.recordName))
        }
        let currentRecordNames = Set(currentSnapshots.map(\.recordName))
        let currentTokenAccountIDsByRecordName = tokenAccountIDsByRecordName.filter { recordName, _ in
            currentRecordNames.contains(recordName)
        }
        let intentPlan = CloudSyncSnapshotDeletionIntentReconciliation.plan(
            snapshots: currentSnapshots,
            tokenAccountIDsByRecordName: currentTokenAccountIDsByRecordName,
            authoritativeProviders: acceptedAuthoritativeProviders,
            activeTokenAccountIDs: currentPublicationState.activeTokenAccountIDs,
            pendingRecordNames: self.persistenceEnvelope.snapshotDeletionRecordNames)
        acceptedAuthoritativeProviders.subtract(intentPlan.providersRequiringFreshAuthority)
        self.persistenceEnvelope.snapshotDeletionRecordNames = intentPlan.pendingRecordNames
        self.stageSnapshotDeletionIntents(
            recordNamesToDelete: intentPlan.pendingRecordNames,
            recordNamesToCancel: intentPlan.recordNamesToCancel)
        self.persistEnvelope()
        for recordName in intentPlan.recordNamesToCancel {
            self.engine?.state.remove(pendingRecordZoneChanges: [.deleteRecord(self.recordID(named: recordName))])
        }
        let publishableSnapshots = currentSnapshots.filter { !intentPlan.blockedRecordNames.contains($0.recordName) }
        for payload in publishableSnapshots {
            self.persistenceEnvelope.snapshotOwnershipKnownRecordNames.insert(payload.recordName)
            if let tokenAccountID = currentTokenAccountIDsByRecordName[payload.recordName] {
                self.persistenceEnvelope.snapshotTokenAccountIDs[payload.recordName] = tokenAccountID
            } else {
                self.persistenceEnvelope.snapshotTokenAccountIDs.removeValue(forKey: payload.recordName)
            }
        }
        let incomingTokenAccountIDsByRecordName = currentTokenAccountIDsByRecordName.filter {
            !intentPlan.blockedRecordNames.contains($0.key)
        }
        let pendingPlan = CloudSyncPendingSnapshotPublicationReconciliation.plan(
            state: .init(
                snapshots: self.pendingSnapshots,
                authoritativeProviders: self.pendingSnapshotAuthoritativeProviders,
                tokenAccountIDsByRecordName: self.pendingSnapshotTokenAccountIDs,
                providerConfigRevisions: self.pendingSnapshotProviderConfigRevisions),
            incoming: .init(
                snapshots: publishableSnapshots,
                authoritativeProviders: acceptedAuthoritativeProviders,
                tokenAccountIDsByRecordName: incomingTokenAccountIDsByRecordName,
                providerConfigRevisions: acceptedProviderConfigRevisions),
            currentProviderConfigRevisions: currentPublicationState.providerConfigRevisions)
        self.pendingSnapshots = pendingPlan.snapshots
        self.pendingSnapshotAuthoritativeProviders = pendingPlan.authoritativeProviders
        self.pendingSnapshotTokenAccountIDs = pendingPlan.tokenAccountIDsByRecordName
        self.pendingSnapshotProviderConfigRevisions = pendingPlan.providerConfigRevisions
        self.persistEnvelope()
        let elapsed = self.lastSnapshotPushAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if elapsed >= 120 {
            self.pushPendingSnapshots()
            return
        }
        self.snapshotPushTask?.cancel()
        self.snapshotPushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(120 - elapsed))
                guard !Task.isCancelled else { return }
                self?.pushPendingSnapshots()
            } catch {
                return
            }
        }
    }

    func removeDevice(_ deviceID: String) async {
        guard self.enabled, let engine = self.engine, let lease = self.engineLease else { return }
        var deletionCheckpoint: UInt64?
        let failure = await CloudSyncDeviceRemoval.run {
            guard self.engine === engine else { return }
            try await engine.fetchChanges(.init(scope: .zoneIDs([Self.zoneID])))
            await self.delegateEventQueue.drain()
        } delete: {
            let names = self.state.status.needsAppUpdate ? [] : self.state.recordNames(
                removing: deviceID, currentDeviceID: self.settings.macFleetSyncDeviceID)
            guard self.enabled, self.engine === engine, !names.isEmpty else { return false }
            deletionCheckpoint = self.state.errorRevision
            let result = try await engine.database.modifyRecords(
                saving: [], deleting: names.map { self.recordID(named: $0) }, atomically: true)
            for deletion in result.deleteResults.values {
                try deletion.get()
            }
            return self.enabled && self.engine === engine
        } didDelete: {
            guard self.enabled, self.engine === engine, let deletionCheckpoint else { return }
            lease.finishDeviceDeletion(state: self.state, startedAt: deletionCheckpoint, pushedAt: Date())
        }
        if let failure, self.engine === engine {
            self.record(error: failure.error, scope: failure.scope)
        }
    }

    private func removeDeletedRecordsFromCaches(_ recordNames: some Sequence<String>) {
        let recordNames = Array(recordNames)
        for recordName in recordNames {
            self.persistenceEnvelope.encodedSystemFields.removeValue(forKey: recordName)
            self.persistenceEnvelope.recordMetadata.removeValue(forKey: recordName)
            self.persistenceEnvelope.fleetDevices.removeValue(forKey: recordName)
            self.persistenceEnvelope.fleetSnapshots.removeValue(forKey: recordName)
            if !self.persistenceEnvelope.snapshotDeletionRecordNames.contains(recordName) {
                self.persistenceEnvelope.snapshotOwnershipKnownRecordNames.remove(recordName)
                self.persistenceEnvelope.snapshotTokenAccountIDs.removeValue(forKey: recordName)
            }
            self.lastSnapshotHashes.removeValue(forKey: recordName)
        }
        self.state.removeRecords(recordNames)
    }

    /// Keep the upstream device-removal test seam while applying the fork's
    /// fuller cache cleanup, including snapshot migration metadata.
    func applyDeletedRecords(_ names: [String]) {
        self.removeDeletedRecordsFromCaches(names)
        self.persistEnvelope()
    }

    private func applySnapshotConfigurationDeletionIntents(
        recordNamesToDelete: Set<String>,
        recordNamesToCancel: Set<String>)
    {
        self.stageSnapshotDeletionIntents(
            recordNamesToDelete: recordNamesToDelete,
            recordNamesToCancel: recordNamesToCancel)
        // Persist before touching CKSyncEngine. If initialization or later startup work
        // fails, the next engine instance can still remove every stale pending delete.
        self.persistEnvelope()
        guard self.enabled, let engine = self.engine else { return }
        let durableCancellations = self.persistenceEnvelope.snapshotDeletionCancellationRecordNames
            .subtracting(recordNamesToDelete)
        for recordName in durableCancellations {
            engine.state.remove(pendingRecordZoneChanges: [.deleteRecord(self.recordID(named: recordName))])
        }
        self.pendingSnapshots.removeAll { recordNamesToDelete.contains($0.recordName) }
        for recordName in recordNamesToDelete {
            let recordID = self.recordID(named: recordName)
            self.desiredRecords.removeValue(forKey: recordID)
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        }
        self.persistEnvelope()
    }

    private func finishConfirmedSnapshotMigrations(
        savedRecordNames: [String],
        syncEngine: CKSyncEngine)
    {
        let toDrop = CloudSyncSnapshotMigration.takeDeletes(
            forSavedRecordNames: savedRecordNames,
            pending: &self.persistenceEnvelope.pendingPredecessorDeletes,
            afterLiveSnapshotReconciliation: self.hasReconciledLiveSnapshots,
            liveNames: Set(self.latestLiveSnapshotRecordNamesByProvider.values.joined()))
        CloudSyncSnapshotMigration.applyConfirmedSaveHashes(
            savedRecordNames: savedRecordNames,
            pendingSaveHashes: &self.pendingSaveHashes,
            lastSnapshotHashes: &self.lastSnapshotHashes)
        self.pendingSnapshots = CloudSyncSnapshotMigration.mergingPendingSnapshots(
            self.pendingSnapshots,
            with: CloudSyncSnapshotMigration.unpublishedFleetSnapshots(
                savedRecordNames: savedRecordNames,
                fleetSnapshots: self.persistenceEnvelope.fleetSnapshots,
                lastSnapshotHashes: self.lastSnapshotHashes))
        guard !toDrop.isEmpty else { return }
        self.stageSnapshotDeletionIntents(
            recordNamesToDelete: toDrop,
            recordNamesToCancel: [])
        let recordIDs = CloudSyncSnapshotMigration.drop(
            toDrop,
            hashes: &self.lastSnapshotHashes,
            envelope: &self.persistenceEnvelope,
            desiredRecords: &self.desiredRecords,
            zoneID: Self.zoneID)
        for recordID in recordIDs {
            syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        }
        self.rememberPendingSnapshotDeletes(toDrop)
        toDrop.forEach { self.state.fleetSnapshots.removeValue(forKey: $0) }
    }

    private func handleSentRecordDeletes(deletedIDs: [CKRecord.ID], failures: [CKRecord.ID: CKError]) {
        var finished = Set(deletedIDs.map(\.recordName))
        let finishedFailedDeletes = CloudSyncSnapshotMigration.finishedFailedDeleteNames(failures)
        finished.formUnion(finishedFailedDeletes)
        self.forgetPendingSnapshotDeletes(finished)
        self.removeDeletedRecordsFromCaches(
            CloudSyncSnapshotMigration.confirmedMissingDeleteNames(failures))
        for error in CloudSyncSnapshotMigration.reportableFailedDeletes(failures) {
            self.record(error: error, scope: .push)
        }
        let liveNames = CloudSyncSnapshotMigration.liveSnapshotRecordNames(
            pendingRecordNames: self.pendingSnapshots.map(\.recordName) +
                self.desiredRecords.keys.map(\.recordName),
            storedRecordNames: self.lastSnapshotHashes.keys)
        for recordID in CloudSyncSnapshotMigration.retryableFailedDeletes(failures, liveNames: liveNames) {
            self.rememberPendingSnapshotDeletes([recordID.recordName])
            let delay = failures[recordID].flatMap(CloudSyncSnapshotMigration.retryDelay(for:)) ?? 1
            self.scheduleRetry(recordID: recordID, after: delay, deleting: true)
        }
    }

    private func rememberPendingSnapshotDeletes(_ names: Set<String>) {
        guard !names.isEmpty else { return }
        self.persistenceEnvelope.pendingSnapshotDeletes.formUnion(names)
        self.persistEnvelope()
    }

    private func forgetPendingSnapshotDeletes(_ names: Set<String>) {
        let remaining = self.persistenceEnvelope.pendingSnapshotDeletes.subtracting(names)
        guard remaining != self.persistenceEnvelope.pendingSnapshotDeletes else { return }
        self.persistenceEnvelope.pendingSnapshotDeletes = remaining
        self.persistEnvelope()
    }

    private func cancelPendingSnapshotDeletes(_ names: Set<String>) {
        guard !names.isEmpty else { return }
        self.forgetPendingSnapshotDeletes(names)
        guard let engine = self.engine else { return }
        engine.state.remove(pendingRecordZoneChanges: names.map { name in
            .deleteRecord(self.recordID(named: name))
        })
    }

    private func requeuePendingSnapshotDeletes() {
        guard let engine = self.engine else { return }
        let liveNames = CloudSyncSnapshotMigration.liveSnapshotRecordNames(
            pendingRecordNames: self.pendingSnapshots.map(\.recordName) +
                self.desiredRecords.keys.map(\.recordName),
            storedRecordNames: self.lastSnapshotHashes.keys)
        let names = CloudSyncSnapshotMigration.pendingDeletesToRequeue(
            pendingDeletes: self.persistenceEnvelope.pendingSnapshotDeletes,
            liveNames: liveNames)
        for name in names {
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(self.recordID(named: name))])
        }
    }

    private func skipTerminalReplacementSave(recordName name: String, error: CKError) {
        // A terminal skip stops retrying this exact payload, but the unsaved replacement
        // must continue protecting its legacy predecessor. A later changed payload or an
        // engine restart can retry and release the mapping only after a confirmed save.
        CloudSyncSnapshotMigration.applyTerminalSaveSkip(
            recordName: name,
            error: error,
            pendingSaveHashes: &self.pendingSaveHashes,
            skippedTerminalReplacementHashes: &self.skippedTerminalReplacementHashes)
    }

    private func scheduleRetry(recordID: CKRecord.ID, after delay: TimeInterval, deleting: Bool = false) {
        let originatingEngine = self.engine.map(ObjectIdentifier.init)
        Task { [weak self] in
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }
                await Task.yield()
                guard let self, self.enabled else { return }
                if deleting, !self.persistenceEnvelope.pendingSnapshotDeletes.contains(recordID.recordName) {
                    return
                }
                guard let engine = self.engine,
                      CloudSyncLifecycle.isCurrentEngine(
                          originatingEngine: originatingEngine,
                          currentEngine: ObjectIdentifier(engine))
                else { return }
                engine.state.add(pendingRecordZoneChanges: [
                    deleting ? .deleteRecord(recordID) : .saveRecord(recordID),
                ])
                try await engine.sendChanges(.init(scope: .recordIDs([recordID])))
            } catch is CancellationError {
                return
            } catch {
                self?.record(error: error, scope: .push)
            }
        }
    }

    private func pushPendingSnapshots() {
        guard let engine = self.engine else { return }
        guard !self.pendingSnapshots.isEmpty
            || !self.persistenceEnvelope.pendingSnapshotDeletes.isEmpty
            || !self.pendingSnapshotProviderConfigRevisions.isEmpty
            || !self.pendingSnapshotAuthoritativeProviders.isEmpty
        else {
            return
        }
        guard !self.state.status.needsAppUpdate else { return }

        do {
            let pendingProviders = Set(self.pendingSnapshotProviderConfigRevisions.keys)
            let currentPublicationState = (
                enabledProviders: Set(self.settings.enabledProvidersOrdered(
                    metadataByProvider: ProviderDescriptorRegistry.metadata)),
                providerConfigRevisions: Dictionary(uniqueKeysWithValues: pendingProviders.map {
                    ($0, self.settings.providerInstanceConfigRevision(for: $0))
                }))
            let currentPendingProviders = CloudSyncSnapshotPublicationRevisionGate.acceptedProviders(
                claimedProviders: pendingProviders,
                sourceRevisions: self.pendingSnapshotProviderConfigRevisions,
                currentRevisions: currentPublicationState.providerConfigRevisions)
            let enabledProviders = currentPublicationState.enabledProviders
            let authoritativeProviders = self.pendingSnapshotAuthoritativeProviders
                .intersection(currentPendingProviders)
            let snapshots = self.pendingSnapshots.filter {
                currentPendingProviders.contains($0.provider) && enabledProviders.contains($0.provider)
            }
            let snapshotRecordNames = Set(snapshots.map(\.recordName))
            let tokenAccountIDsByRecordName = self.pendingSnapshotTokenAccountIDs.filter {
                snapshotRecordNames.contains($0.key)
            }
            let deviceID = self.settings.macFleetSyncDeviceID
            let reconciliation = CloudSyncSnapshotReconciliation.plan(
                currentSnapshots: snapshots,
                persistedSnapshots: self.persistenceEnvelope.fleetSnapshots,
                deviceID: deviceID,
                enabledProviders: enabledProviders,
                authoritativeProviders: authoritativeProviders)
            let obsoleteNames = CloudSyncSnapshotMigration.obsoleteRecordNames(
                liveSnapshots: snapshots,
                hashes: self.lastSnapshotHashes,
                envelope: self.persistenceEnvelope)

            if !snapshots.isEmpty {
                CloudSyncSnapshotMigration.retainingObsoletePredecessors(
                    in: &self.persistenceEnvelope.pendingPredecessorDeletes,
                    obsoleteNames: obsoleteNames)
            }
            // Stage every current sibling before pruning removed replacements. Otherwise
            // removing a terminally skipped sibling could release a shared predecessor
            // before a current replacement has been confirmed.
            CloudSyncSnapshotMigration.stagePredecessors(
                for: snapshots,
                obsoleteNames: obsoleteNames,
                pending: &self.persistenceEnvelope.pendingPredecessorDeletes)
            let releasedPredecessors = CloudSyncSnapshotMigration.releasePredecessors(
                forRemovedReplacementNames: reconciliation.recordNamesToDelete,
                liveNames: snapshotRecordNames,
                pending: &self.persistenceEnvelope.pendingPredecessorDeletes)
            let immediateDeletes = CloudSyncSnapshotMigration.immediateReconciliationDeletes(
                reconciliation.recordNamesToDelete,
                protecting: obsoleteNames).union(releasedPredecessors)

            self.stageSnapshotDeletionIntents(
                recordNamesToDelete: immediateDeletes,
                recordNamesToCancel: reconciliation.recordNamesToCancelPendingDeletes)
            self.persistEnvelope()
            for recordName in reconciliation.recordNamesToCancelPendingDeletes {
                engine.state.remove(pendingRecordZoneChanges: [.deleteRecord(self.recordID(named: recordName))])
            }
            for recordName in immediateDeletes {
                let recordID = self.recordID(named: recordName)
                self.desiredRecords.removeValue(forKey: recordID)
                engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }

            if !snapshots.isEmpty {
                self.cancelPendingSnapshotDeletes(
                    CloudSyncSnapshotMigration.cancelledPersistedDeletes(
                        pendingDeletes: self.persistenceEnvelope.pendingSnapshotDeletes,
                        liveNames: snapshotRecordNames))
                self.hasReconciledLiveSnapshots = true
            }
            self.requeuePendingSnapshotDeletes()

            var stillPending: [AccountSnapshotSyncPayload] = []
            for payload in snapshots {
                self.persistenceEnvelope.snapshotOwnershipKnownRecordNames.insert(payload.recordName)
                if let tokenAccountID = tokenAccountIDsByRecordName[payload.recordName] {
                    self.persistenceEnvelope.snapshotTokenAccountIDs[payload.recordName] = tokenAccountID
                } else {
                    self.persistenceEnvelope.snapshotTokenAccountIDs.removeValue(forKey: payload.recordName)
                }

                let hash = try CanonicalSyncJSON.hash(payload)
                if self.skippedTerminalReplacementHashes[payload.recordName] == hash {
                    continue
                }
                let predecessors = CloudSyncSnapshotMigration.predecessorNames(
                    for: payload,
                    obsoleteNames: obsoleteNames)
                // Hashes are recorded only after CloudKit confirms a save.
                let alreadyPublished = self.lastSnapshotHashes[payload.recordName] == hash
                if alreadyPublished {
                    if !predecessors.isEmpty {
                        self.finishConfirmedSnapshotMigrations(
                            savedRecordNames: [payload.recordName],
                            syncEngine: engine)
                    }
                    continue
                }
                if CloudSyncSnapshotMigration.hasInFlightSave(
                    recordName: payload.recordName,
                    pendingSaveHashes: self.pendingSaveHashes)
                {
                    self.persistenceEnvelope.fleetSnapshots[payload.recordName] = payload
                    stillPending.append(payload)
                    continue
                }
                let recordID = self.recordID(named: payload.recordName)
                let record = self.record(type: .accountSnapshot, id: recordID)
                record["schemaVersion"] = payload.schemaVersion as CKRecordValue
                record["provider"] = payload.provider.rawValue as CKRecordValue
                record["deviceID"] = payload.deviceID as CKRecordValue
                record["accountKey"] = payload.accountKey as CKRecordValue
                record["fetchedAt"] = payload.fetchedAt as CKRecordValue
                record.encryptedValues["displayLabel"] = payload.displayLabel as CKRecordValue
                record.encryptedValues["usagePayload"] = try CanonicalSyncJSON.string(payload.usage) as CKRecordValue
                self.desiredRecords[recordID] = record
                self.persistenceEnvelope.fleetSnapshots[payload.recordName] = payload
                self.skippedTerminalReplacementHashes.removeValue(forKey: payload.recordName)
                self.pendingSaveHashes[payload.recordName] = hash
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }

            self.pendingSnapshots = stillPending
            let stillPendingRecordNames = Set(stillPending.map(\.recordName))
            let stillPendingProviders = Set(stillPending.map(\.provider))
            self.pendingSnapshotAuthoritativeProviders.formIntersection(stillPendingProviders)
            self.pendingSnapshotTokenAccountIDs = self.pendingSnapshotTokenAccountIDs.filter {
                stillPendingRecordNames.contains($0.key)
            }
            self.pendingSnapshotProviderConfigRevisions = self.pendingSnapshotProviderConfigRevisions.filter {
                stillPendingProviders.contains($0.key)
            }
            self.lastSnapshotPushAt = Date()
            self.persistEnvelope()
        } catch {
            self.record(error: error, scope: .push)
        }
    }
}
