import CloudKit
import CodexBarCore
import CodexBarSync
import Foundation
import Observation
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

@MainActor
@Observable
final class CloudSyncState {
    var availability: SyncAvailability = .available
    var status = SyncStatus()
    var fleetDevices: [String: DeviceSyncPayload] = [:]
    var fleetSnapshots: [String: AccountSnapshotSyncPayload] = [:]
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
        configuredProviders: [UsageProvider]) -> Set<String>
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
        configuredProviders: [UsageProvider],
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
        enabledProviders: Set<UsageProvider>,
        authoritativeProviders: Set<UsageProvider>) -> Plan
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
        claimedProviders: Set<UsageProvider>,
        sourceRevisions: [UsageProvider: UInt64],
        currentRevisions: [UsageProvider: UInt64]) -> Set<UsageProvider>
    {
        Set(claimedProviders.filter { provider in
            guard let sourceRevision = sourceRevisions[provider],
                  let currentRevision = currentRevisions[provider]
            else { return false }
            return sourceRevision == currentRevision
        })
    }
}

enum CloudSyncPendingSnapshotPublicationReconciliation {
    struct State {
        let snapshots: [AccountSnapshotSyncPayload]
        let authoritativeProviders: Set<UsageProvider>
        let tokenAccountIDsByRecordName: [String: UUID]
        let providerConfigRevisions: [UsageProvider: UInt64]
    }

    struct Plan {
        let snapshots: [AccountSnapshotSyncPayload]
        let authoritativeProviders: Set<UsageProvider>
        let tokenAccountIDsByRecordName: [String: UUID]
        let providerConfigRevisions: [UsageProvider: UInt64]
    }

    struct Incoming {
        let snapshots: [AccountSnapshotSyncPayload]
        let authoritativeProviders: Set<UsageProvider>
        let tokenAccountIDsByRecordName: [String: UUID]
        let providerConfigRevisions: [UsageProvider: UInt64]
    }

    static func plan(
        state: State,
        incoming: Incoming,
        currentProviderConfigRevisions: [UsageProvider: UInt64]) -> Plan
    {
        let currentPendingProviders = CloudSyncSnapshotPublicationRevisionGate.acceptedProviders(
            claimedProviders: Set(state.providerConfigRevisions.keys),
            sourceRevisions: state.providerConfigRevisions,
            currentRevisions: currentProviderConfigRevisions)
        let acceptedIncomingProviders = CloudSyncSnapshotPublicationRevisionGate.acceptedProviders(
            claimedProviders: Set(incoming.providerConfigRevisions.keys),
            sourceRevisions: incoming.providerConfigRevisions,
            currentRevisions: currentProviderConfigRevisions)

        var snapshotsByRecordName: [String: AccountSnapshotSyncPayload] = Dictionary(
            uniqueKeysWithValues: state.snapshots.compactMap { snapshot -> (String, AccountSnapshotSyncPayload)? in
                guard currentPendingProviders.contains(snapshot.provider),
                      !acceptedIncomingProviders.contains(snapshot.provider)
                else { return nil }
                return (snapshot.recordName, snapshot)
            })
        let retainedRecordNames = Set(snapshotsByRecordName.keys)
        for snapshot in incoming.snapshots where acceptedIncomingProviders.contains(snapshot.provider) {
            snapshotsByRecordName[snapshot.recordName] = snapshot
        }
        let snapshots = snapshotsByRecordName.values.sorted { $0.recordName < $1.recordName }
        let recordNames = Set(snapshotsByRecordName.keys)

        var authoritativeProviders = state.authoritativeProviders
            .intersection(currentPendingProviders)
            .subtracting(acceptedIncomingProviders)
        authoritativeProviders.formUnion(incoming.authoritativeProviders.intersection(acceptedIncomingProviders))

        var tokenAccountIDsByRecordName = state.tokenAccountIDsByRecordName.filter {
            retainedRecordNames.contains($0.key)
        }
        for (recordName, accountID) in incoming.tokenAccountIDsByRecordName where recordNames.contains(recordName) {
            tokenAccountIDsByRecordName[recordName] = accountID
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
        let providersRequiringFreshAuthority: Set<UsageProvider>
        let ownershipKnownRecordNames: Set<String>
        let tokenAccountIDsByRecordName: [String: UUID]
    }

    static func plan(
        previousConfigs: [UsageProvider: ProviderConfig],
        currentConfig: CodexBarConfig,
        state: State) -> Plan
    {
        let currentConfigs = Dictionary(uniqueKeysWithValues: currentConfig.providers.map { ($0.id, $0) })
        let currentAccounts = currentConfigs.mapValues { $0.tokenAccounts?.accounts ?? [] }
        let ownership = self.backfillOwnership(
            previousConfigs: previousConfigs,
            currentAccounts: currentAccounts,
            state: state)
        let removedAccounts = previousConfigs.compactMapValues { previousConfig -> [ProviderTokenAccount]? in
            let currentIDs = Set(currentAccounts[previousConfig.id, default: []].map(\.id))
            let removed = (previousConfig.tokenAccounts?.accounts ?? []).filter { !currentIDs.contains($0.id) }
            return removed.isEmpty ? nil : removed
        }
        let newlyRemovedRecordNames = Set<String>(state.candidateSnapshots.compactMap { recordName, snapshot in
            guard snapshot.deviceID == state.deviceID,
                  let removed = removedAccounts[snapshot.provider]
            else { return nil }
            guard ownership.knownRecordNames.contains(recordName),
                  let accountID = ownership.tokenAccountIDsByRecordName[recordName]
            else { return nil }
            return removed.contains(where: { $0.id == accountID }) ? recordName : nil
        })
        let restoredRecordNames = Set(state.pendingRecordNames.filter { recordName in
            guard let provider = self.provider(
                for: recordName,
                candidateSnapshots: state.candidateSnapshots),
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
            self.provider(for: $0, candidateSnapshots: state.candidateSnapshots)
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
        candidateSnapshots: [String: AccountSnapshotSyncPayload]) -> UsageProvider?
    {
        if let provider = candidateSnapshots[recordName]?.provider { return provider }
        return UsageProvider.allCases.first { recordName.hasPrefix("snap-\($0.rawValue)-") }
    }

    private static func backfillOwnership(
        previousConfigs: [UsageProvider: ProviderConfig],
        currentAccounts: [UsageProvider: [ProviderTokenAccount]],
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
        provider: UsageProvider,
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

enum CloudSyncSnapshotDeletionIntentReconciliation {
    struct Plan: Equatable {
        let pendingRecordNames: Set<String>
        let recordNamesToCancel: Set<String>
        let blockedRecordNames: Set<String>
        let providersRequiringFreshAuthority: Set<UsageProvider>
    }

    static func plan(
        snapshots: [AccountSnapshotSyncPayload],
        tokenAccountIDsByRecordName: [String: UUID],
        authoritativeProviders: Set<UsageProvider>,
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

enum CloudSyncEntitlementGate {
    static let entitlement = "com.apple.developer.icloud-services"

    static func hasICloudServicesEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, self.entitlement as CFString, nil)
        else {
            return false
        }
        if let services = value as? [String] {
            return services.contains("CloudKit")
        }
        return false
    }
}

actor CloudSyncEngine: CKSyncEngineDelegate {
    static let containerIdentifier = CloudSyncConstants.containerIdentifier
    static let zoneID = CKRecordZone.ID(zoneName: "CodexBarSync", ownerName: CKCurrentUserDefaultName)

    private let settings: SettingsStore
    private let state: CloudSyncState
    private let persistence: CloudSyncPersistence
    private var persistenceEnvelope: CloudSyncPersistence.Envelope
    private var engine: CKSyncEngine?
    private var desiredRecords: [CKRecord.ID: CKRecord] = [:]
    private var enabled = false
    private var configPushTask: Task<Void, Never>?
    private var snapshotPushTask: Task<Void, Never>?
    private var periodicFetchTask: Task<Void, Never>?
    private var lastSnapshotPushAt: Date?
    private var pendingSnapshots: [AccountSnapshotSyncPayload] = []
    private var pendingSnapshotAuthoritativeProviders: Set<UsageProvider> = []
    private var pendingSnapshotTokenAccountIDs: [String: UUID] = [:]
    private var pendingSnapshotProviderConfigRevisions: [UsageProvider: UInt64] = [:]
    private var lastSnapshotHashes: [String: String] = [:]
    private var lastKnownProviderConfigs: [UsageProvider: ProviderConfig] = [:]
    private var lastKnownPreferences: SyncedPreferences?
    private var lastKnownIncludeSecrets: Bool?
    private var quotaRetryState = CloudSyncQuotaRetryState()
    private var didRehydrateFleetState = false
    private let logger = CodexBarLog.logger(LogCategories.settings)

    init(
        settings: SettingsStore,
        state: CloudSyncState,
        persistence: CloudSyncPersistence = CloudSyncPersistence(),
        initialConfiguration: CodexBarConfig? = nil,
        initialPreferences: SyncedPreferences? = nil,
        initialIncludeSecrets: Bool? = nil)
    {
        self.settings = settings
        self.state = state
        self.persistence = persistence
        self.persistenceEnvelope = persistence.load()
        if let initialConfiguration {
            self.lastKnownProviderConfigs = Dictionary(
                uniqueKeysWithValues: initialConfiguration.providers.map { ($0.id, $0) })
        }
        self.lastKnownPreferences = initialPreferences
        self.lastKnownIncludeSecrets = initialIncludeSecrets
    }

    func start(enabled: Bool) async {
        guard CloudSyncEntitlementGate.hasICloudServicesEntitlement() else {
            await self.updateAvailability(.missingEntitlement)
            return
        }
        await self.updateAvailability(.available)
        guard enabled else { return }
        await self.setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        guard enabled else {
            await self.stopEngine(clearPersistence: false)
            return
        }
        guard CloudSyncEntitlementGate.hasICloudServicesEntitlement() else {
            await self.updateAvailability(.missingEntitlement)
            return
        }
        do {
            let initialized = try await self.initializeEngineIfNeeded()
            guard self.engine != nil else { return }
            // First sync on this device: apply the fleet's existing state before composing
            // any push. Otherwise a fresh device's records (editCount 1, newer timestamps)
            // win conflict ties against the fleet's records and clobber them server-side.
            if !self.persistenceEnvelope.recordMetadata.keys.contains(where: { $0.hasPrefix("intent-") }) {
                await self.fetchChanges()
            }
            let configuredProviders = await MainActor.run { self.settings.configSnapshot.providers.map(\.id) }
            CloudSyncDirtyState.markBootstrapDirtyIfNeeded(
                configuredProviders: configuredProviders,
                envelope: &self.persistenceEnvelope)
            self.persistEnvelope()
            try await self.queueCurrentConfigurationAndPreferences()
            guard await MainActor.run(body: { !self.state.status.needsAppUpdate }) else { return }
            try await self.queueDeviceRecord()
            await self.applySnapshotConfigurationDeletionIntents(
                recordNamesToDelete: self.persistenceEnvelope.snapshotDeletionRecordNames,
                recordNamesToCancel: [])
            self.startPeriodicFetchTimer()
            self.scheduleFetchChanges(scopedToSyncZone: !initialized)
        } catch {
            await self.record(error: error)
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
                try await self?.queueCurrentConfigurationAndPreferences()
            } catch is CancellationError {
                return
            } catch {
                await self?.record(error: error)
            }
        }
    }

    func fetchChanges() async {
        guard self.enabled, let engine = self.engine else { return }
        do {
            try await engine.fetchChanges(.init(scope: .zoneIDs([Self.zoneID])))
            await MainActor.run { self.state.status.lastSuccessfulFetchAt = Date() }
        } catch {
            await self.record(error: error)
        }
    }

    func stop() async {
        self.enabled = false
        await self.stopEngine(clearPersistence: false)
    }

    private func initializeEngineIfNeeded() async throws -> Bool {
        guard self.engine == nil else { return false }
        // This is the first CKContainer access, and every path here has already passed the entitlement gate.
        let container = CKContainer(identifier: Self.containerIdentifier)
        let accountStatus = try await container.accountStatus()
        switch accountStatus {
        case .available:
            await self.updateAvailability(.available)
        case .restricted:
            await self.updateAvailability(.restricted)
            return false
        case .noAccount, .couldNotDetermine, .temporarilyUnavailable:
            await self.updateAvailability(.noICloudAccount)
            return false
        @unknown default:
            await self.updateAvailability(.noICloudAccount)
            return false
        }

        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: self.persistenceEnvelope.stateSerialization,
            delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        await self.rehydrateFleetStateIfNeeded()
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        return true
    }

    private func queueCurrentConfigurationAndPreferences() async throws {
        guard let engine = self.engine else { return }
        if self.persistenceEnvelope.recordMetadata.values.contains(where: {
            ($0.schemaVersion ?? 0) > CodexBarSyncSchema.currentVersion
        }) {
            await MainActor.run { self.state.status.needsAppUpdate = true }
            return
        }
        let snapshot = await MainActor.run {
            (
                config: self.settings.configSnapshot,
                includeSecrets: self.settings.macFleetSyncIncludeSecrets,
                preferences: self.settings.syncedPreferences)
        }
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

    static func providerIntentPayload(
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

    private func queueDeviceRecord() async throws {
        guard let engine = self.engine else { return }
        let deviceID = await MainActor.run { self.settings.macFleetSyncDeviceID }
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
        await MainActor.run { self.state.fleetDevices[payload.recordName] = payload }
        self.persistEnvelope()
    }

    private func pushPendingSnapshots() async {
        guard let engine = self.engine else { return }
        guard await MainActor.run(body: { !self.state.status.needsAppUpdate }) else { return }
        do {
            let pendingProviders = Set(self.pendingSnapshotProviderConfigRevisions.keys)
            let currentPublicationState = await MainActor.run {
                (
                    enabledProviders: Set(self.settings.enabledProvidersOrdered(
                        metadataByProvider: ProviderDescriptorRegistry.metadata)),
                    providerConfigRevisions: Dictionary(uniqueKeysWithValues: pendingProviders.map {
                        ($0, self.settings.providerConfigRevision(for: $0))
                    }))
            }
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
            let deviceID = await MainActor.run { self.settings.macFleetSyncDeviceID }
            let reconciliation = CloudSyncSnapshotReconciliation.plan(
                currentSnapshots: snapshots,
                persistedSnapshots: self.persistenceEnvelope.fleetSnapshots,
                deviceID: deviceID,
                enabledProviders: enabledProviders,
                authoritativeProviders: authoritativeProviders)
            for recordName in reconciliation.recordNamesToCancelPendingDeletes {
                let recordID = self.recordID(named: recordName)
                engine.state.remove(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
            for recordName in reconciliation.recordNamesToDelete {
                let recordID = self.recordID(named: recordName)
                self.desiredRecords.removeValue(forKey: recordID)
                engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
            for payload in snapshots {
                self.persistenceEnvelope.snapshotOwnershipKnownRecordNames.insert(payload.recordName)
                if let tokenAccountID = tokenAccountIDsByRecordName[payload.recordName] {
                    self.persistenceEnvelope.snapshotTokenAccountIDs[payload.recordName] = tokenAccountID
                } else {
                    self.persistenceEnvelope.snapshotTokenAccountIDs.removeValue(forKey: payload.recordName)
                }
                let hash = try CanonicalSyncJSON.hash(payload)
                guard self.lastSnapshotHashes[payload.recordName] != hash else { continue }
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
                self.lastSnapshotHashes[payload.recordName] = hash
                self.persistenceEnvelope.fleetSnapshots[payload.recordName] = payload
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
            self.pendingSnapshots = []
            self.pendingSnapshotAuthoritativeProviders = []
            self.pendingSnapshotTokenAccountIDs = [:]
            self.pendingSnapshotProviderConfigRevisions = [:]
            self.lastSnapshotPushAt = Date()
            self.persistEnvelope()
        } catch {
            await self.record(error: error)
        }
    }

    // MARK: CKSyncEngineDelegate

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await self.processEvent(event, syncEngine: syncEngine)
    }

    private func processEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
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
            await self.applyFetchedRecords(changes.modifications.map(\.record))
            let deletedRecordNames = changes.deletions.map(\.recordID.recordName)
            await self.removeDeletedRecordsFromCaches(deletedRecordNames)
            self.persistEnvelope()
            await MainActor.run { self.state.status.lastSuccessfulFetchAt = Date() }
        case let .sentRecordZoneChanges(changes):
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
            await self.removeDeletedRecordsFromCaches(changes.deletedRecordIDs.map(\.recordName))
            for failure in changes.failedRecordSaves {
                await self.handleSaveFailure(failure, syncEngine: syncEngine)
            }
            for (recordID, error) in changes.failedRecordDeletes {
                if error.code == .unknownItem {
                    syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(recordID)])
                    await self.removeDeletedRecordsFromCaches([recordID.recordName])
                } else {
                    await self.record(error: error)
                }
            }
            self.persistEnvelope()
            if !changes.savedRecords.isEmpty || !changes.deletedRecordIDs.isEmpty {
                await MainActor.run { self.state.status.lastSuccessfulPushAt = Date() }
            }
        case let .fetchedDatabaseChanges(changes):
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

    private func recordForPendingSave(_ recordID: CKRecord.ID, syncEngine: CKSyncEngine) -> CKRecord? {
        CloudSyncBatchRecordProvider.record(for: recordID, desiredRecords: self.desiredRecords) { change in
            syncEngine.state.remove(pendingRecordZoneChanges: [change])
        }
    }

    func applyFetchedRecords(_ records: [CKRecord]) async {
        if records.contains(where: { self.schemaVersion($0) > CodexBarSyncSchema.currentVersion }) {
            await MainActor.run { self.state.status.needsAppUpdate = true }
            for record in records {
                self.cacheSystemFields(record)
            }
            return
        }
        guard await MainActor.run(body: { !self.state.status.needsAppUpdate }) else { return }

        for record in records {
            self.cacheSystemFields(record)
            guard self.shouldApplyServerRecord(record) else { continue }
            do {
                switch record.recordType {
                case SyncRecordType.providerIntent.rawValue:
                    try await self.applyProviderIntent(record)
                case SyncRecordType.preferences.rawValue:
                    try await self.applyPreferences(record)
                case SyncRecordType.device.rawValue:
                    try await self.applyDevice(record)
                case SyncRecordType.accountSnapshot.rawValue:
                    try await self.applyAccountSnapshot(record)
                default:
                    break
                }
            } catch {
                await self.record(error: error)
            }
        }
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
        let localValue = SyncConflictValue(
            value: local,
            editCount: self.editCount(local),
            modifiedAt: self.modifiedAt(local))
        let serverValue = SyncConflictValue(
            value: server,
            editCount: self.editCount(server),
            modifiedAt: self.modifiedAt(server))
        let winner = SyncConflictResolver.winner(local: localValue, server: serverValue)
        guard winner.value === local else {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
            self.desiredRecords.removeValue(forKey: server.recordID)
            return true
        }
        let rebased = Self.copyUserFields(from: local, onto: server)
        self.desiredRecords[server.recordID] = rebased
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
        return false
    }

    private func applyProviderIntent(_ record: CKRecord) async throws {
        guard let payloadString = record["payload"] as? String else { return }
        let payload = try CanonicalSyncJSON.decode(ProviderIntentPayload.self, from: payloadString)
        let secrets = self.encryptedStringFields(record)
        let merged = try await MainActor.run {
            var config = self.settings.configSnapshot
            guard let local = config.providerConfig(for: payload.provider) else { return nil as ProviderConfig? }
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
            return merged
        }
        guard let merged else { return }
        self.lastKnownProviderConfigs[payload.provider] = merged
        if payload.enabled == true, merged.enabled != true {
            self.persistenceEnvelope.suppressedEnableIntents.insert(payload.provider.rawValue)
        } else {
            self.persistenceEnvelope.suppressedEnableIntents.remove(payload.provider.rawValue)
        }
        self.persistEnvelope()
    }

    private func applyPreferences(_ record: CKRecord) async throws {
        guard let payloadString = record["payload"] as? String else { return }
        let payload = try CanonicalSyncJSON.decode(PreferencesSyncPayload.self, from: payloadString)
        self.lastKnownPreferences = payload.preferences
        await MainActor.run {
            self.settings.applySyncedPreferences(payload.preferences)
        }
    }

    private func applyDevice(_ record: CKRecord) async throws {
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
        await MainActor.run { self.state.fleetDevices[record.recordID.recordName] = payload }
    }

    private func applyAccountSnapshot(_ record: CKRecord) async throws {
        guard let providerRaw = record["provider"] as? String,
              let provider = UsageProvider(rawValue: providerRaw),
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
        await MainActor.run { self.state.fleetSnapshots[record.recordID.recordName] = payload }
    }

    private func handleSaveFailure(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine) async
    {
        switch failure.error.code {
        case .quotaExceeded:
            let retry = self.quotaRetryState.nextDelay(serverRetryAfter: failure.error.retryAfterSeconds)
            self.scheduleRetry(recordID: failure.record.recordID, after: retry)
        case .serverRecordChanged:
            guard let server = failure.error.serverRecord else {
                await self.record(error: failure.error)
                return
            }
            await self.resolveConflict(with: server, syncEngine: syncEngine)
        case .zoneNotFound:
            self.recreateZoneAndRequeue(failure.record, syncEngine: syncEngine)
        default:
            let resetEncryptedData = (failure.error.userInfo[CKErrorUserDidResetEncryptedDataKey] as? NSNumber)?
                .boolValue == true
            if resetEncryptedData {
                self.recreateZoneAndRequeue(failure.record, syncEngine: syncEngine)
            } else {
                await self.record(error: failure.error)
            }
        }
    }

    private func recreateZoneAndRequeue(_ record: CKRecord, syncEngine: CKSyncEngine) {
        if self.desiredRecords[record.recordID] == nil {
            self.desiredRecords[record.recordID] = record
        }
        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
    }

    private func scheduleRetry(recordID: CKRecord.ID, after delay: TimeInterval) {
        Task { [weak self] in
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }
                await Task.yield()
                guard let self, let engine = await self.engine, await self.enabled else { return }
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                try await engine.sendChanges(.init(scope: .recordIDs([recordID])))
            } catch {
                await self?.record(error: error)
            }
        }
    }

    private func resolveConflict(with server: CKRecord, syncEngine: CKSyncEngine) async {
        guard self.schemaVersion(server) <= CodexBarSyncSchema.currentVersion else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
            self.desiredRecords.removeValue(forKey: server.recordID)
            self.cacheSystemFields(server)
            self.persistEnvelope()
            await MainActor.run { self.state.status.needsAppUpdate = true }
            return
        }
        guard let local = self.desiredRecords[server.recordID] else { return }
        self.cacheSystemFields(server)
        let localValue = SyncConflictValue(
            value: local,
            editCount: self.editCount(local),
            modifiedAt: self.modifiedAt(local))
        let serverValue = SyncConflictValue(
            value: server,
            editCount: self.editCount(server),
            modifiedAt: self.modifiedAt(server))
        if SyncConflictResolver.winner(local: localValue, server: serverValue).value === local {
            self.desiredRecords[server.recordID] = Self.copyUserFields(from: local, onto: server)
            self.scheduleRetry(recordID: server.recordID, after: 0)
        } else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
            self.desiredRecords.removeValue(forKey: server.recordID)
            await self.applyFetchedRecords([server])
        }
    }

    private func scheduleFetchChanges(scopedToSyncZone: Bool) {
        Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            if scopedToSyncZone {
                await self.fetchChanges()
            } else {
                await self.fetchAllChanges()
            }
        }
    }

    private func fetchAllChanges() async {
        guard self.enabled, let engine = self.engine else { return }
        do {
            try await engine.fetchChanges()
            await MainActor.run { self.state.status.lastSuccessfulFetchAt = Date() }
        } catch {
            await self.record(error: error)
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
        self.configPushTask?.cancel()
        self.snapshotPushTask?.cancel()
        self.periodicFetchTask?.cancel()
        if let engine = self.engine {
            await engine.cancelOperations()
        }
        self.engine = nil
        self.desiredRecords = [:]
        self.quotaRetryState.reset()
        if clearPersistence {
            self.persistenceEnvelope = .init(stateSerialization: nil, encodedSystemFields: [:])
            self.didRehydrateFleetState = false
            try? self.persistence.delete()
            await MainActor.run {
                self.state.fleetDevices = [:]
                self.state.fleetSnapshots = [:]
            }
        }
    }

    private func rehydrateFleetStateIfNeeded() async {
        guard !self.didRehydrateFleetState else { return }
        self.didRehydrateFleetState = true
        let devices = self.persistenceEnvelope.fleetDevices
        let snapshots = self.persistenceEnvelope.fleetSnapshots
        await MainActor.run {
            self.state.fleetDevices = devices
            self.state.fleetSnapshots = snapshots
        }
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

    static func copyUserFields(from source: CKRecord, onto server: CKRecord) -> CKRecord {
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

    private func updateAvailability(_ availability: SyncAvailability) async {
        await MainActor.run { self.state.availability = availability }
    }

    private func record(error: Error) async {
        self.logger.error("iCloud sync failed: \(error)")
        await MainActor.run { self.state.status.lastError = error.localizedDescription }
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
    func localUserConfigurationDidChange(_ config: CodexBarConfig) async {
        let deviceID = await MainActor.run { self.settings.macFleetSyncDeviceID }
        var candidateSnapshots = self.persistenceEnvelope.fleetSnapshots
        for snapshot in self.pendingSnapshots {
            candidateSnapshots[snapshot.recordName] = snapshot
        }
        var ownershipKnownRecordNames = self.persistenceEnvelope.snapshotOwnershipKnownRecordNames
        ownershipKnownRecordNames.formUnion(self.pendingSnapshots.map(\.recordName))
        var tokenAccountIDsByRecordName = self.persistenceEnvelope.snapshotTokenAccountIDs
        tokenAccountIDsByRecordName.merge(self.pendingSnapshotTokenAccountIDs) { _, pending in pending }
        let snapshotPlan = CloudSyncSnapshotConfigurationReconciliation.plan(
            previousConfigs: self.lastKnownProviderConfigs,
            currentConfig: config,
            state: .init(
                candidateSnapshots: candidateSnapshots,
                ownershipKnownRecordNames: ownershipKnownRecordNames,
                tokenAccountIDsByRecordName: tokenAccountIDsByRecordName,
                deviceID: deviceID,
                pendingRecordNames: self.persistenceEnvelope.snapshotDeletionRecordNames))
        self.persistenceEnvelope.snapshotDeletionRecordNames = snapshotPlan.pendingRecordNames
        self.persistenceEnvelope.snapshotOwnershipKnownRecordNames = snapshotPlan.ownershipKnownRecordNames
        self.persistenceEnvelope.snapshotTokenAccountIDs = snapshotPlan.tokenAccountIDsByRecordName
        self.pendingSnapshotAuthoritativeProviders.subtract(snapshotPlan.providersRequiringFreshAuthority)
        let previousSuppressedEnableIntents = self.persistenceEnvelope.suppressedEnableIntents
        for providerConfig in config.providers {
            if let previous = self.lastKnownProviderConfigs[providerConfig.id],
               previous.enabled != providerConfig.enabled
            {
                self.persistenceEnvelope.suppressedEnableIntents.remove(providerConfig.id.rawValue)
            }
            guard let previous = self.lastKnownProviderConfigs[providerConfig.id] else {
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
        self.lastKnownProviderConfigs = Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0) })
        self.persistEnvelope()
        await self.applySnapshotConfigurationDeletionIntents(
            recordNamesToDelete: snapshotPlan.recordNamesToDelete,
            recordNamesToCancel: snapshotPlan.recordNamesToCancel)
    }

    func queueSnapshots(
        _ snapshots: [AccountSnapshotSyncPayload],
        authoritativeProviders: Set<UsageProvider>,
        sourceProviderConfigRevisions: [UsageProvider: UInt64],
        tokenAccountIDsByRecordName: [String: UUID]) async
    {
        guard self.enabled, self.engine != nil else { return }
        let options = await MainActor.run {
            (
                enabled: self.settings.macFleetSyncSnapshotsEnabled,
                lowPower: self.settings.backgroundWorkLowPowerModeEnabled
                    || ProcessInfo.processInfo.isLowPowerModeEnabled,
                needsAppUpdate: self.state.status.needsAppUpdate)
        }
        guard options.enabled, !options.lowPower, !options.needsAppUpdate else { return }
        let sourceProviders = Set(sourceProviderConfigRevisions.keys)
        let pendingProviders = Set(self.pendingSnapshotProviderConfigRevisions.keys)
        let providersToValidate = sourceProviders.union(pendingProviders)
        let currentPublicationState = await MainActor.run {
            (
                enabledProviders: Set(self.settings.enabledProvidersOrdered(
                    metadataByProvider: ProviderDescriptorRegistry.metadata)),
                providerConfigRevisions: Dictionary(uniqueKeysWithValues: providersToValidate.map {
                    ($0, self.settings.providerConfigRevision(for: $0))
                }),
                activeTokenAccountIDs: Set(self.settings.configSnapshot.providers.flatMap {
                    $0.tokenAccounts?.accounts.map(\.id) ?? []
                }))
        }
        let acceptedPublicationProviders = CloudSyncSnapshotPublicationRevisionGate.acceptedProviders(
            claimedProviders: sourceProviders,
            sourceRevisions: sourceProviderConfigRevisions,
            currentRevisions: currentPublicationState.providerConfigRevisions)
        var acceptedAuthoritativeProviders = authoritativeProviders.intersection(acceptedPublicationProviders)
        let currentSnapshots = snapshots.filter { acceptedPublicationProviders.contains($0.provider) }
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
                providerConfigRevisions: sourceProviderConfigRevisions),
            currentProviderConfigRevisions: currentPublicationState.providerConfigRevisions)
        self.pendingSnapshots = pendingPlan.snapshots
        self.pendingSnapshotAuthoritativeProviders = pendingPlan.authoritativeProviders
        self.pendingSnapshotTokenAccountIDs = pendingPlan.tokenAccountIDsByRecordName
        self.pendingSnapshotProviderConfigRevisions = pendingPlan.providerConfigRevisions
        self.persistEnvelope()
        let elapsed = self.lastSnapshotPushAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if elapsed >= 120 {
            await self.pushPendingSnapshots()
            return
        }
        self.snapshotPushTask?.cancel()
        self.snapshotPushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(120 - elapsed))
                guard !Task.isCancelled else { return }
                await self?.pushPendingSnapshots()
            } catch {
                return
            }
        }
    }

    private func removeDeletedRecordsFromCaches(_ recordNames: some Sequence<String>) async {
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
        await MainActor.run {
            for recordName in recordNames {
                self.state.fleetDevices.removeValue(forKey: recordName)
                self.state.fleetSnapshots.removeValue(forKey: recordName)
            }
        }
    }

    private func applySnapshotConfigurationDeletionIntents(
        recordNamesToDelete: Set<String>,
        recordNamesToCancel: Set<String>) async
    {
        guard self.enabled, let engine = self.engine else { return }
        for recordName in recordNamesToCancel {
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
}
