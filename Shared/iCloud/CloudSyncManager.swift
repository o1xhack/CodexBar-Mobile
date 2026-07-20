import CloudKit
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if canImport(Security)
import Security
#endif

// MARK: - Sync Push Protocol

/// Protocol for pushing usage snapshots, enabling mock injection in tests.
public protocol SyncPushing: Sendable {
    @discardableResult
    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult

    /// Per-provider incremental write (P4). The `pushSnapshot` path keeps
    /// legacy-zone consumers happy; this one populates the new
    /// `DeviceProvidersZone` so future iOS builds can consume changes without
    /// downloading the whole monolithic blob.
    @discardableResult
    func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]) async -> SyncPushResult

    /// Delete per-provider records by their composite recordName
    /// (`{deviceID}|{providerID}|{accountEmail-or-_}`). Called when a
    /// provider transitions from enabled → disabled, or when its account
    /// identity drifts (composite key changes between Mac versions). Without
    /// this, stale records accumulate in `DeviceProvidersZone` and surface
    /// on iOS as ghost cards (user-reported on iOS 1.3.0; Build 94 added a
    /// display-time filter as L2; this is L1, the root-cause fix).
    @discardableResult
    func deletePerProviderRecords(
        recordNames: [String]) async -> SyncPushResult

    /// Fetches the recordNames of every per-provider record currently in
    /// `DeviceProvidersZone` whose `deviceID` field matches the caller's
    /// device. Used by `SyncCoordinator` at startup to seed
    /// `lastPushedRecordNames` from the actual CloudKit state, so L1
    /// cleanup can detect and delete records pushed by previous Mac
    /// process incarnations (e.g. mock entries left stranded after the
    /// user toggled mock injection off and restarted Mac before any
    /// cleanup cycle ran). Without this seed, the in-memory
    /// `lastPushedRecordNames` starts empty on every Mac launch, and
    /// `pushHistorySeeded`'s first-cycle guard hides any pre-existing
    /// stranded record from the diff forever.
    func fetchPerProviderRecordNames(
        forDeviceID deviceID: String) async -> PerProviderRecordNameFetchResult
}

extension SyncPushing {
    /// Default no-op so existing test doubles don't have to implement the new
    /// method. CloudSyncManager overrides with the real CloudKit write.
    public func pushPerProviderRecords(
        _: [ProviderUsageEnvelope]) async -> SyncPushResult
    {
        .success
    }

    /// Default no-op for delete path — test doubles that don't track CKRecord
    /// state get a successful no-op.
    public func deletePerProviderRecords(
        recordNames _: [String]) async -> SyncPushResult
    {
        .success
    }

    /// Default empty result — test doubles that don't simulate CloudKit
    /// state report no pre-existing records, which makes startup reconcile
    /// a no-op. Real CloudSyncManager overrides with the live query.
    public func fetchPerProviderRecordNames(
        forDeviceID _: String) async -> PerProviderRecordNameFetchResult
    {
        .success([])
    }
}

public struct SyncPushResult: Sendable, Equatable {
    public let succeeded: Bool
    public let message: String?

    public init(succeeded: Bool, message: String? = nil) {
        self.succeeded = succeeded
        self.message = message
    }

    public static let success = SyncPushResult(succeeded: true)

    public static func failure(_ message: String) -> SyncPushResult {
        SyncPushResult(succeeded: false, message: message)
    }
}

public enum PerProviderRecordNameFetchResult: Sendable, Equatable {
    case success([String])
    case failure(String)
}

public struct CloudReadOnlyDiagnosticReport: Sendable, Equatable {
    public let generatedAt: Date
    public let accountStatus: String
    public let legacyZoneStatus: String
    public let providerZoneStatus: String
    public let kvsStatus: String

    public var text: String {
        """
        iCloud Sync Read-Only Check
        Generated: \(self.generatedAt.formatted(.iso8601))
        Account: \(self.accountStatus)
        Legacy zone: \(self.legacyZoneStatus)
        Provider zone: \(self.providerZoneStatus)
        KVS fallback: \(self.kvsStatus)
        """
    }
}

// MARK: - Sync Error

/// Detailed sync error with user-readable descriptions.
public enum CloudSyncError: Error, Sendable, CustomStringConvertible {
    case networkUnavailable
    case notAuthenticated
    case quotaExceeded
    case serverError(String)
    case decodingFailed(String)
    case unknown(String)

    public var description: String {
        switch self {
        case .networkUnavailable:
            "Network unavailable"
        case .notAuthenticated:
            "iCloud account not signed in"
        case .quotaExceeded:
            "iCloud storage quota exceeded"
        case let .serverError(msg):
            "Server error: \(msg)"
        case let .decodingFailed(msg):
            "Data format error: \(msg)"
        case let .unknown(msg):
            msg
        }
    }

    public init(from ckError: CKError) {
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            self = .networkUnavailable
        case .notAuthenticated:
            self = .notAuthenticated
        case .quotaExceeded:
            self = .quotaExceeded
        case .serverResponseLost, .serviceUnavailable, .requestRateLimited:
            self = .serverError(ckError.localizedDescription)
        default:
            self = .unknown(ckError.localizedDescription)
        }
    }
}

// MARK: - Multi-device Sync Result

/// Result of fetching snapshots from all devices via CloudKit.
public enum MultiDeviceSyncResult: Sendable {
    /// Successfully fetched snapshots from one or more devices.
    case success([SyncedUsageSnapshot])
    /// No device records found in CloudKit.
    case empty
    /// CloudKit operation failed with a specific error.
    case error(CloudSyncError)
}

// MARK: - Legacy KVS Sync Result (backward compatibility)

/// Result of an iCloud KVS sync event (kept for transition period).
public enum SyncResult: Sendable {
    case success(SyncedUsageSnapshot)
    case empty
    case quotaExceeded
    case accountChanged
    case initialSync
}

// MARK: - Cloud Sync Manager

/// Manages reading/writing usage snapshots via CloudKit (primary) and KVS (legacy fallback).
///
/// - Mac side calls `pushSnapshot(_:)` to save a per-device record to CloudKit.
/// - iOS side calls `fetchAllDeviceSnapshots()` to read all device records and merge.
/// - KVS dual-write is maintained during the transition period for older app versions.
///
/// **Custom zone:** All `DeviceSnapshot` records live in a custom record zone
/// (`CloudSyncConstants.customZoneName`), not the default zone. This is required for
/// CloudKit silent push notifications via `CKRecordZoneSubscription` to fire reliably
/// on the private database — the default zone of the private database does not deliver
/// silent push reliably (see `apple/sample-cloudkit-privatedb-sync` and Apple's
/// "Remote Records" documentation).
/// `@unchecked Sendable` rationale:
/// - `_container` / `_privateDatabase` are set once in init and never mutated;
///   CloudKit's CKContainer + CKDatabase are documented thread-safe per Apple.
/// - `encoder` / `decoder` are factory-built `let` values whose only instance
///   methods we call (`encode`/`decode`) don't mutate shared state.
/// - `shared` is a single instance; there is no cross-instance aliasing.
/// We don't cleanly express these constraints in Swift 6's checked `Sendable`
/// (CKContainer isn't annotated), so `@unchecked` is deliberate. If any
/// mutable stored property is added here in the future, switch to an actor
/// rather than relaxing this comment.
public final class CloudSyncManager: SyncPushing, @unchecked Sendable {
    public static let shared = CloudSyncManager()
    private static let writeDeadlineSeconds: TimeInterval = 45
    private static let diagnosticDeadlineSeconds: TimeInterval = 12

    /// CloudKit container and database — optional because CKContainer(identifier:) will
    /// hard-crash (_os_crash / SIGTRAP) if the CloudKit entitlement is missing or misconfigured.
    /// We probe for the entitlement at init time; if absent, CloudKit is disabled and we use KVS only.
    private let _container: CKContainer?
    private let _privateDatabase: CKDatabase?
    private let cloudKitAvailable: Bool
    /// Always go through `CloudSyncConstants.makeJSONEncoder/Decoder` so
    /// `Date` strategy stays consistent across the codebase. Build 66
    /// regression originated in a hand-rolled `JSONEncoder()` instance.
    private let encoder = CloudSyncConstants.makeJSONEncoder()
    private let decoder = CloudSyncConstants.makeJSONDecoder()

    /// The custom record zone where all `DeviceSnapshot` records live.
    /// See class doc-comment for why a custom zone is required.
    private let customZone = CKRecordZone(zoneName: CloudSyncConstants.customZoneName)

    /// Per-provider record zone (P4). One `DeviceProviderSnapshot` record per
    /// (deviceID, providerID, accountEmail) — see
    /// `CodexBarMobile/Research/010-mac-per-provider-cloudkit.md`.
    private let providerZone = CKRecordZone(zoneName: CloudSyncConstants.providerZoneName)

    // Legacy KVS
    private let kvsStore = NSUbiquitousKeyValueStore.default
    private var kvsObserverToken: NSObjectProtocol?

    #if canImport(OSLog)
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.o1xhack.codexbar",
        category: "cloudkit-sync")
    #endif

    private init() {
        // Probe for CloudKit entitlement before touching CKContainer.
        var available = false
        #if os(macOS)
        // SecTaskCopyValueForEntitlement reads the actual code-signing entitlements.
        if let task = SecTaskCreateFromSelf(nil) {
            let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-services" as CFString, nil)
            if let services = value as? [String], services.contains("CloudKit") {
                available = true
            }
        }
        #else
        // iOS entitlements are guaranteed by the provisioning profile.
        available = true
        #endif
        #if os(macOS)
        if available {
            let c = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
            self._container = c
            self._privateDatabase = c.privateCloudDatabase
        } else {
            self._container = nil
            self._privateDatabase = nil
        }
        #else
        let c = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        self._container = c
        self._privateDatabase = c.privateCloudDatabase
        #endif
        self.cloudKitAvailable = available
    }

    // MARK: - CloudKit Write (Mac side)

    /// Performs a bounded, read-only health check. It never creates zones,
    /// records, subscriptions, or schema, so running diagnostics cannot change
    /// another device's iCloud state.
    public func runReadOnlyDiagnostic() async -> CloudReadOnlyDiagnosticReport {
        let generatedAt = Date()
        let kvsSynced = self.synchronizeKVSStore()
        let kvsStatus: String
        if let data = self.kvsStore.data(forKey: CloudSyncConstants.kvsSnapshotKey) {
            let decodable = (try? self.decoder.decode(SyncedUsageSnapshot.self, from: data)) != nil
            kvsStatus = "\(kvsSynced ? "available" : "unavailable"), payload \(data.count) bytes, "
                + (decodable ? "decodable" : "invalid")
        } else {
            kvsStatus = "\(kvsSynced ? "available" : "unavailable"), no payload"
        }

        guard self.cloudKitAvailable,
              let container = self._container
        else {
            return .init(
                generatedAt: generatedAt,
                accountStatus: "CloudKit entitlement unavailable",
                legacyZoneStatus: "not checked",
                providerZoneStatus: "not checked",
                kvsStatus: kvsStatus)
        }

        let accountStatus: String
        do {
            let status: CKAccountStatus = try await CloudOperationDeadline.run(
                stage: "account status diagnostic",
                timeout: Self.diagnosticDeadlineSeconds,
                cancel: {})
            { finish in
                container.accountStatus { status, error in
                    if let error {
                        finish(.failure(error))
                    } else {
                        finish(.success(status))
                    }
                }
            }
            accountStatus = Self.accountStatusDescription(status)
        } catch {
            accountStatus = "error: \(error.localizedDescription)"
        }

        let budget = CloudOperationBudget(seconds: Self.diagnosticDeadlineSeconds)
        let legacyZoneStatus = await self.readOnlyZoneStatus(
            self.customZone.zoneID,
            label: "legacy",
            budget: budget)
        let providerZoneStatus = await self.readOnlyZoneStatus(
            self.providerZone.zoneID,
            label: "provider",
            budget: budget)
        return .init(
            generatedAt: generatedAt,
            accountStatus: accountStatus,
            legacyZoneStatus: legacyZoneStatus,
            providerZoneStatus: providerZoneStatus,
            kvsStatus: kvsStatus)
    }

    private static func accountStatusDescription(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: "available"
        case .couldNotDetermine: "could not determine"
        case .noAccount: "no account"
        case .restricted: "restricted"
        case .temporarilyUnavailable: "temporarily unavailable"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }

    private func readOnlyZoneStatus(
        _ zoneID: CKRecordZone.ID,
        label: String,
        budget: CloudOperationBudget) async -> String
    {
        do {
            _ = try await self.fetchRecordZone(
                zoneID,
                stage: "\(label) zone diagnostic",
                budget: budget)
            return "available"
        } catch let error as CKError where error.code == .zoneNotFound {
            return "missing"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    /// Pushes the latest usage snapshot to CloudKit as a per-device record,
    /// and also writes to KVS for backward compatibility with older iOS versions.
    @discardableResult
    public func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult {
        guard let data = try? encoder.encode(snapshot) else {
            let message = "iCloud sync failed: could not encode the snapshot payload."
            self.logError(message)
            return .failure(message)
        }

        // KVS is the compatibility fallback. Write it before the first
        // CloudKit await so a stuck CloudKit daemon cannot also starve older
        // readers. This never upgrades a CloudKit timeout into success.
        self.pushToKVS(data: data)

        // Push to CloudKit (primary) — skipped if entitlement not available.
        let result: SyncPushResult
        if self.cloudKitAvailable {
            result = await self.pushToCloudKit(
                snapshot: snapshot,
                data: data,
                budget: CloudOperationBudget(seconds: Self.writeDeadlineSeconds))
        } else {
            self.logInfo("CloudKit not available (missing entitlement), using KVS only")
            result = .success
        }

        return result
    }

    private func configureDeadline(
        _ operation: CKOperation,
        stage: String,
        budget: CloudOperationBudget) throws -> TimeInterval
    {
        let remaining = try budget.remaining(for: stage)
        Self.configureOperation(operation, deadline: remaining)
        return remaining
    }

    static func configureOperation(_ operation: CKOperation, deadline: TimeInterval) {
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = deadline
        configuration.timeoutIntervalForResource = deadline
        operation.configuration = configuration
        operation.qualityOfService = .utility
    }

    private static func pushFailureDescription(_ error: Error) -> String {
        if let deadlineError = error as? CloudOperationDeadlineError {
            return deadlineError.localizedDescription
        }
        if let cloudError = error as? CKError {
            return CloudSyncError(from: cloudError).description
        }
        return error.localizedDescription
    }

    private func fetchRecordZone(
        _ zoneID: CKRecordZone.ID,
        stage: String,
        budget: CloudOperationBudget) async throws -> CKRecordZone
    {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
        let resultBox = LockedResultBox<CKRecordZone>()
        operation.perRecordZoneResultBlock = { _, result in
            resultBox.set(result)
        }
        let timeout = try self.configureDeadline(operation, stage: stage, budget: budget)

        return try await CloudOperationDeadline.run(
            stage: stage,
            timeout: timeout,
            cancel: { operation.cancel() })
        { finish in
            operation.fetchRecordZonesResultBlock = { operationResult in
                switch operationResult {
                case .success:
                    finish(resultBox.get() ?? .failure(CKError(.internalError)))
                case let .failure(error):
                    finish(resultBox.get() ?? .failure(error))
                }
            }
            self._privateDatabase!.add(operation)
        }
    }

    private func saveRecordZone(
        _ zone: CKRecordZone,
        stage: String,
        budget: CloudOperationBudget) async throws
    {
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil)
        let timeout = try self.configureDeadline(operation, stage: stage, budget: budget)
        try await CloudOperationDeadline.run(
            stage: stage,
            timeout: timeout,
            cancel: { operation.cancel() })
        { finish in
            operation.modifyRecordZonesResultBlock = { result in
                finish(result.map { _ in () })
            }
            self._privateDatabase!.add(operation)
        }
    }

    private func fetchRecord(
        _ recordID: CKRecord.ID,
        stage: String,
        budget: CloudOperationBudget) async throws -> CKRecord
    {
        let operation = CKFetchRecordsOperation(recordIDs: [recordID])
        let resultBox = LockedResultBox<CKRecord>()
        operation.perRecordResultBlock = { _, result in
            resultBox.set(result)
        }
        let timeout = try self.configureDeadline(operation, stage: stage, budget: budget)

        return try await CloudOperationDeadline.run(
            stage: stage,
            timeout: timeout,
            cancel: { operation.cancel() })
        { finish in
            operation.fetchRecordsResultBlock = { operationResult in
                switch operationResult {
                case .success:
                    finish(resultBox.get() ?? .failure(CKError(.internalError)))
                case let .failure(error):
                    finish(resultBox.get() ?? .failure(error))
                }
            }
            self._privateDatabase!.add(operation)
        }
    }

    private func saveRecord(
        _ record: CKRecord,
        stage: String,
        budget: CloudOperationBudget) async throws -> CKRecord
    {
        let operation = CKModifyRecordsOperation(
            recordsToSave: [record],
            recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged
        let resultBox = LockedResultBox<CKRecord>()
        operation.perRecordSaveBlock = { _, result in
            resultBox.set(result)
        }
        let timeout = try self.configureDeadline(operation, stage: stage, budget: budget)

        return try await CloudOperationDeadline.run(
            stage: stage,
            timeout: timeout,
            cancel: { operation.cancel() })
        { finish in
            operation.modifyRecordsResultBlock = { operationResult in
                switch operationResult {
                case .success:
                    finish(resultBox.get() ?? .failure(CKError(.internalError)))
                case let .failure(error):
                    finish(resultBox.get() ?? .failure(error))
                }
            }
            self._privateDatabase!.add(operation)
        }
    }

    /// Ensures the custom record zone exists on the server.
    ///
    /// Uses fetch-then-create pattern: queries the server for the zone, only creates if
    /// missing. This is self-healing across iCloud account switches and server-side
    /// resets — a stale local cache cannot mask a missing server zone (which would
    /// otherwise cause every write to fail with `.zoneNotFound`).
    ///
    /// Cost: one extra zone fetch per call. Cheap enough to call from every push.
    private func ensureCustomZoneExists(budget: CloudOperationBudget) async throws {
        // Fast path: zone already exists on server.
        do {
            _ = try await self.fetchRecordZone(
                self.customZone.zoneID,
                stage: "legacy zone check",
                budget: budget)
            return
        } catch let error as CKError {
            if error.code != .zoneNotFound {
                // Network or other error — propagate, don't silently mask
                throw error
            }
            // Fall through to create
        }

        try await self.saveRecordZone(
            self.customZone,
            stage: "legacy zone create",
            budget: budget)
        self.logInfo("Custom zone created", metadata: [
            "zone": self.customZone.zoneID.zoneName,
        ])
    }

    private func pushToCloudKit(
        snapshot: SyncedUsageSnapshot,
        data: Data,
        budget: CloudOperationBudget) async -> SyncPushResult
    {
        guard let deviceID = snapshot.deviceID else {
            let message = "iCloud sync failed: no device ID in snapshot."
            self.logError(message)
            return .failure(message)
        }

        // Ensure the custom zone exists before writing into it. Without this, the first
        // write to a non-existent zone fails with .zoneNotFound.
        do {
            try await self.ensureCustomZoneExists(budget: budget)
        } catch {
            let message = "Failed to prepare iCloud sync: \(Self.pushFailureDescription(error))"
            self.logError(message)
            return .failure(message)
        }

        let recordID = CKRecord.ID(recordName: deviceID, zoneID: self.customZone.zoneID)

        // Fetch existing record to avoid conflicts, or create new
        let record: CKRecord
        do {
            record = try await self.fetchRecord(
                recordID,
                stage: "legacy record fetch",
                budget: budget)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudSyncConstants.recordType, recordID: recordID)
        } catch {
            let message = Self.pushFailureDescription(error)
            self.logError("CloudKit fetch failed: \(message)")
            return .failure(message)
        }

        record["deviceName"] = snapshot.deviceName as CKRecordValue
        record["deviceID"] = deviceID as CKRecordValue
        record["appVersion"] = (snapshot.appVersion ?? "") as CKRecordValue
        record["syncTimestamp"] = snapshot.syncTimestamp as CKRecordValue
        record["payload"] = data as CKRecordValue

        do {
            _ = try await self.saveRecord(
                record,
                stage: "legacy record save",
                budget: budget)
            self.logInfo("Pushed snapshot to CloudKit", metadata: [
                "deviceID": deviceID,
                "providers": "\(snapshot.providers.count)",
                "bytes": "\(data.count)",
            ])
            return .success
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Conflict: re-fetch the server record and retry once
            self.logInfo("CloudKit conflict, retrying with server record")
            guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                return .failure("CloudKit conflict but no server record returned")
            }
            serverRecord["deviceName"] = snapshot.deviceName as CKRecordValue
            serverRecord["deviceID"] = deviceID as CKRecordValue
            serverRecord["appVersion"] = (snapshot.appVersion ?? "") as CKRecordValue
            serverRecord["syncTimestamp"] = snapshot.syncTimestamp as CKRecordValue
            serverRecord["payload"] = data as CKRecordValue
            do {
                _ = try await self.saveRecord(
                    serverRecord,
                    stage: "legacy conflict retry",
                    budget: budget)
                self.logInfo("CloudKit conflict resolved, snapshot saved")
                return .success
            } catch {
                let message = Self.pushFailureDescription(error)
                self.logError("CloudKit retry failed: \(message)")
                return .failure(message)
            }
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("CloudKit save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("CloudKit save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - CloudKit Per-Provider Write (Mac side, P4)

    /// Pushes per-provider snapshot records to `DeviceProvidersZone`.
    ///
    /// Each envelope becomes one `DeviceProviderSnapshot` CKRecord keyed by the
    /// composite (`deviceID`, `providerID`, `accountEmail`). Payload is JSON +
    /// zlib-compressed. Legacy zone writes continue via `pushSnapshot`; callers
    /// should treat this as an **additive** write — failure here must not stop
    /// the legacy write from succeeding.
    ///
    /// An empty `envelopes` array is a successful no-op (caller's per-provider
    /// diff produced no changes this cycle).
    @discardableResult
    public func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]) async -> SyncPushResult
    {
        guard !envelopes.isEmpty else { return .success }
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        let budget = CloudOperationBudget(seconds: Self.writeDeadlineSeconds)

        do {
            try await self.ensureProviderZoneExists(budget: budget)
        } catch {
            let message = "Failed to prepare provider sync: \(Self.pushFailureDescription(error))"
            self.logError(message)
            return .failure(message)
        }

        // Build CKRecords. Any encode/compress failure is surfaced individually
        // but does not abort the whole batch — we still push the records we
        // could build.
        var records: [CKRecord] = []
        var encodeFailures: [String] = []
        for envelope in envelopes {
            do {
                let record = try self.makePerProviderRecord(from: envelope)
                records.append(record)
            } catch {
                encodeFailures.append(
                    "\(envelope.provider.providerID): \(error.localizedDescription)")
                self.logError(
                    "Per-provider encode failed for \(envelope.provider.providerID): " +
                        error.localizedDescription)
            }
        }
        guard !records.isEmpty else {
            return .failure("All per-provider payloads failed to encode")
        }

        // CloudKit API hard limit: `CKModifyRecordsOperation` rejects any
        // single `save()` call with more than 200 records (see Apple's
        // CloudKit Reference under "Working with Records"). Real users
        // rarely have >30 providers, but chunking defensively means we
        // don't have to re-test this when a user with a genuinely large
        // fleet shows up — or when we add a new record type that multiplies
        // the per-push count. Raising this number without verifying the
        // current limit against CloudKit docs **silently drops records
        // above 200** with a generic `.limitExceeded` error.
        let batchSize = 200
        for chunkStart in stride(from: 0, to: records.count, by: batchSize) {
            let chunkEnd = min(chunkStart + batchSize, records.count)
            let chunk = Array(records[chunkStart..<chunkEnd])
            if let failure = await self.saveChunk(
                chunk,
                stage: "provider records \(chunkStart / batchSize + 1)",
                budget: budget)
            {
                return failure
            }
        }

        self.logInfo("Pushed per-provider records to CloudKit", metadata: [
            "count": "\(records.count)",
            "encodeFailures": "\(encodeFailures.count)",
            "zone": self.providerZone.zoneID.zoneName,
        ])
        if !encodeFailures.isEmpty {
            // Partial-encode failures: return `.failure` so the coordinator
            // does NOT mark the failed composites as synced. Next push
            // re-attempts them. A `.success` with warning would update the
            // coordinator's hash cache for composites that never uploaded,
            // silently skipping retries until their content changes again
            // (Codex review P2 on Build 66 — the re-upload of the composites
            // that DID land this cycle is wasted bandwidth but correct,
            // and encode failures are exceedingly rare in practice).
            return .failure(
                "Encoded \(records.count), failed to encode \(encodeFailures.count); will retry next cycle")
        }
        return .success
    }

    /// Delete per-provider records by composite recordName. Caller passes the
    /// full `{deviceID}|{providerID}|{accountEmail-or-_}` recordName matching
    /// `perProviderRecordName(...)`. Empty input is a successful no-op.
    ///
    /// L1 ghost-records cleanup: SyncCoordinator computes the set of
    /// composites it pushed last cycle vs this cycle; the difference
    /// represents providers the user disabled (or whose account identity
    /// drifted between Mac versions, leaving an old composite orphan).
    /// Deleting those records eliminates the source of the iOS-1.3.0
    /// ghost-card bug at the data layer; iOS 1.3.1's display-time filter
    /// (Build 94) is the L2 backup.
    @discardableResult
    public func deletePerProviderRecords(
        recordNames: [String]) async -> SyncPushResult
    {
        guard !recordNames.isEmpty else { return .success }
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        let recordIDs = recordNames.map { name in
            CKRecord.ID(recordName: name, zoneID: self.providerZone.zoneID)
        }
        let budget = CloudOperationBudget(seconds: Self.writeDeadlineSeconds)

        // Same 200-record batch limit as `pushPerProviderRecords`. Apple's
        // `CKModifyRecordsOperation` rejects >200 in a single call.
        let batchSize = 200
        for chunkStart in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let chunkEnd = min(chunkStart + batchSize, recordIDs.count)
            let chunk = Array(recordIDs[chunkStart..<chunkEnd])
            do {
                let op = CKModifyRecordsOperation(
                    recordsToSave: nil, recordIDsToDelete: chunk)
                op.savePolicy = .changedKeys
                let stage = "stale record delete \(chunkStart / batchSize + 1)"
                let timeout = try self.configureDeadline(op, stage: stage, budget: budget)
                try await CloudOperationDeadline.run(
                    stage: stage,
                    timeout: timeout,
                    cancel: { op.cancel() })
                { finish in
                    op.modifyRecordsResultBlock = { result in
                        finish(result.map { _ in () })
                    }
                    self._privateDatabase!.add(op)
                }
            } catch let error as CKError {
                // .partialFailure with .unknownItem (record already gone) is
                // benign — treat as success. Other CK errors propagate.
                if error.code == .partialFailure {
                    let perItem = error.partialErrorsByItemID ?? [:]
                    let nonBenign = perItem.values.contains { itemError in
                        guard let itemError = itemError as? CKError else { return true }
                        return itemError.code != .unknownItem
                    }
                    if !nonBenign { continue }
                }
                let syncError = CloudSyncError(from: error)
                self.logError("Per-provider delete failed: \(syncError.description)")
                return .failure(syncError.description)
            } catch {
                self.logError("Per-provider delete failed: \(error.localizedDescription)")
                return .failure(error.localizedDescription)
            }
        }

        self.logInfo("Deleted per-provider records from CloudKit", metadata: [
            "count": "\(recordIDs.count)",
            "zone": self.providerZone.zoneID.zoneName,
        ])
        return .success
    }

    /// Fetches all per-provider record names in `DeviceProvidersZone` for
    /// a specific deviceID. Used by `SyncCoordinator.startObserving` to
    /// seed `lastPushedRecordNames` from CloudKit's actual state, so L1
    /// cleanup survives Mac process restarts.
    ///
    /// Returns only recordNames (not full records / payloads) — the
    /// cleanup logic only needs the composite-key set to compute diffs.
    /// The CKQuery uses `desiredKeys: []` to skip payload download, so
    /// the network cost is just the result-set metadata regardless of
    /// how many records exist.
    public func fetchPerProviderRecordNames(
        forDeviceID deviceID: String) async -> PerProviderRecordNameFetchResult
    {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .failure("CloudKit not available")
        }
        // Query by deviceID field, filter server-side. The Production
        // schema indexes `deviceID` as Queryable (verified via Capabilities
        // in CloudKit Console). Empty deviceID would be invalid here so
        // skip rather than do a full-zone scan.
        guard !deviceID.isEmpty else { return .success([]) }

        let predicate = NSPredicate(format: "deviceID == %@", deviceID)
        let query = CKQuery(
            recordType: CloudSyncConstants.providerRecordType,
            predicate: predicate)
        do {
            let operation = CKQueryOperation(query: query)
            operation.zoneID = self.providerZone.zoneID
            operation.desiredKeys = []
            operation.resultsLimit = CKQueryOperation.maximumResults
            let names = LockedArrayBox<String>()
            operation.recordMatchedBlock = { recordID, result in
                if case .success = result {
                    names.append(recordID.recordName)
                }
            }
            let budget = CloudOperationBudget(seconds: Self.writeDeadlineSeconds)
            let stage = "provider reconcile query"
            let timeout = try self.configureDeadline(operation, stage: stage, budget: budget)
            try await CloudOperationDeadline.run(
                stage: stage,
                timeout: timeout,
                cancel: { operation.cancel() })
            { finish in
                operation.queryResultBlock = { result in
                    finish(result.map { _ in () })
                }
                self._privateDatabase!.add(operation)
            }
            let recordNames = names.snapshot()
            self.logInfo("Reconciled per-provider records from CloudKit", metadata: [
                "count": "\(recordNames.count)",
            ])
            return .success(recordNames)
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone doesn't exist yet — first push of this Mac's lifetime.
            return .success([])
        } catch let error as CKError where error.code == .unknownItem {
            // Record type not yet deployed in Production schema. Same as zone-missing.
            return .success([])
        } catch {
            self.logError(
                "Failed to fetch per-provider record names for reconcile: " +
                    error.localizedDescription)
            return .failure(error.localizedDescription)
        }
    }

    /// Ensures `DeviceProvidersZone` exists. Same fetch-first self-heal pattern
    /// as `ensureCustomZoneExists`.
    private func ensureProviderZoneExists(budget: CloudOperationBudget) async throws {
        do {
            _ = try await self.fetchRecordZone(
                self.providerZone.zoneID,
                stage: "provider zone check",
                budget: budget)
            return
        } catch let error as CKError {
            if error.code != .zoneNotFound { throw error }
        }
        try await self.saveRecordZone(
            self.providerZone,
            stage: "provider zone create",
            budget: budget)
        self.logInfo("Provider zone created", metadata: [
            "zone": self.providerZone.zoneID.zoneName,
        ])
    }

    /// Retains the existing behavior for independent iOS-originated linkage
    /// and lifecycle-event writes. The hotfix's bounded operations are scoped
    /// to the Mac snapshot push path only.
    private func ensureProviderZoneExists() async throws {
        do {
            _ = try await self._privateDatabase!.recordZone(for: self.providerZone.zoneID)
            return
        } catch let error as CKError {
            if error.code != .zoneNotFound { throw error }
        }
        _ = try await self._privateDatabase!.modifyRecordZones(
            saving: [self.providerZone], deleting: [])
        self.logInfo("Provider zone created", metadata: [
            "zone": self.providerZone.zoneID.zoneName,
        ])
    }

    /// Encodes one envelope into a CKRecord in `DeviceProvidersZone` with a
    /// zlib-compressed JSON payload and all queryable metadata fields set.
    private func makePerProviderRecord(from envelope: ProviderUsageEnvelope) throws -> CKRecord {
        let json = try encoder.encode(envelope)
        let compressed = try PayloadCompression.compress(json)

        let recordName = Self.perProviderRecordName(
            deviceID: envelope.deviceID,
            providerID: envelope.provider.providerID,
            accountEmail: envelope.provider.accountEmail,
            accountRecordKey: envelope.provider.accountRecordKey)
        let recordID = CKRecord.ID(recordName: recordName, zoneID: self.providerZone.zoneID)
        let record = CKRecord(
            recordType: CloudSyncConstants.providerRecordType, recordID: recordID)
        record["deviceID"] = envelope.deviceID as CKRecordValue
        record["deviceName"] = envelope.deviceName as CKRecordValue
        record["providerID"] = envelope.provider.providerID as CKRecordValue
        record["providerName"] = envelope.provider.providerName as CKRecordValue
        // CloudKit coerces nil strings awkwardly — store empty "" and have the
        // reader treat empty as nil. Matches how we already handle `appVersion`
        // in the legacy writer.
        record["accountEmail"] = (envelope.provider.accountEmail ?? "") as CKRecordValue
        record["lastUpdated"] = envelope.provider.lastUpdated as CKRecordValue
        record["encodingVersion"] = CloudSyncConstants.providerPayloadVersion as CKRecordValue
        record["payload"] = compressed as CKRecordValue
        return record
    }

    /// Composite record name matching iOS `ProviderSnapshotModel.makeCompositeKey`.
    /// Stable across pushes so repeated saves overwrite in place.
    ///
    /// **WIRE CONTRACT.** Format: `"{deviceID}|{providerID}|{identity}"`, where
    /// identity is `accountRecordKey`, then legacy `accountEmail`, then `"_"`.
    /// - The pipe `|` separator was chosen because provider IDs never contain it
    ///   (they're kebab-case ASCII) and neither do email addresses.
    /// - The `"_"` sentinel for nil `accountEmail` must exactly match the four
    ///   other composite-key sites: iOS `SnapshotCache.compositeKey`, iOS
    ///   `ProviderSnapshotModel.makeCompositeKey`, iOS
    ///   `CloudSyncReader.mergeSnapshots` grouping, and any future
    ///   delete-by-recordName code path. Build 67 discovered a drift where
    ///   one site used `""` and another used `"_"`, silently breaking
    ///   delete cascades. If you change the sentinel, you MUST change all
    ///   sites at once.
    /// - Changing the field order (`deviceID|providerID|accountEmail`) or
    ///   separator orphans every already-uploaded record.
    public static func perProviderRecordName(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        accountRecordKey: String? = nil) -> String
    {
        "\(deviceID)|\(providerID)|\(accountRecordKey ?? accountEmail ?? "_")"
    }

    /// Sends one batch of provider records via `CKModifyRecordsOperation`. On
    /// success returns `nil`; on hard failure returns a `SyncPushResult` that
    /// the caller should return to the coordinator.
    private func saveChunk(
        _ records: [CKRecord],
        stage: String,
        budget: CloudOperationBudget) async -> SyncPushResult?
    {
        do {
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            let timeout = try self.configureDeadline(op, stage: stage, budget: budget)
            return try await CloudOperationDeadline.run(
                stage: stage,
                timeout: timeout,
                cancel: { op.cancel() })
            { finish in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        finish(.success(nil))
                    case let .failure(error):
                        finish(.failure(error))
                    }
                }
                self._privateDatabase!.add(op)
            }
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("Per-provider batch save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("Per-provider batch save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - CloudKit Change-Token Incremental Fetch (iOS side)

    /// Result of an incremental fetch against `DeviceProvidersZone`.
    public struct PerProviderZoneChanges: Sendable {
        /// Envelopes decoded from records that were added or modified since
        /// the caller's previous token.
        public let upserted: [ProviderUsageEnvelope]
        /// Composite recordNames of records the server reports as deleted.
        public let deletedRecordNames: [String]
        /// Token to persist for the next incremental fetch. May be `nil` only
        /// when the server had nothing to report and no previous token was
        /// provided.
        public let newToken: CKServerChangeToken?
        /// `true` when the server rejected the input token as expired. The
        /// caller MUST clear its stored token and retry with `token: nil`,
        /// expecting a full replay.
        public let tokenExpired: Bool
        /// `true` when the zone doesn't exist on the server (no P4 Mac has
        /// written yet, or account reset). Treat as empty.
        public let zoneMissing: Bool

        public init(
            upserted: [ProviderUsageEnvelope],
            deletedRecordNames: [String],
            newToken: CKServerChangeToken?,
            tokenExpired: Bool,
            zoneMissing: Bool)
        {
            self.upserted = upserted
            self.deletedRecordNames = deletedRecordNames
            self.newToken = newToken
            self.tokenExpired = tokenExpired
            self.zoneMissing = zoneMissing
        }
    }

    /// Fetch per-provider record changes since `token`. Pass `nil` for a full
    /// replay (first sync on this device, or after a prior token expiry).
    public func fetchPerProviderZoneChanges(
        since token: CKServerChangeToken?) async -> PerProviderZoneChanges
    {
        guard self.cloudKitAvailable, let db = _privateDatabase else {
            return .init(
                upserted: [], deletedRecordNames: [],
                newToken: token, tokenExpired: false, zoneMissing: false)
        }

        let zoneID = self.providerZone.zoneID
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = token
        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: config])
        op.fetchAllChanges = true
        op.qualityOfService = .utility

        // Accumulators — CloudKit serialises these per op, so
        // `nonisolated(unsafe)` keeps Swift 6 strict concurrency happy.
        nonisolated(unsafe) var upserted: [ProviderUsageEnvelope] = []
        nonisolated(unsafe) var deleted: [String] = []
        nonisolated(unsafe) var capturedToken: CKServerChangeToken? = token

        op.recordWasChangedBlock = { _, result in
            switch result {
            case let .success(record):
                if let envelope = Self.decodeEnvelopeStatic(from: record) {
                    upserted.append(envelope)
                }
            case .failure:
                break
            }
        }
        op.recordWithIDWasDeletedBlock = { recordID, _ in
            deleted.append(recordID.recordName)
        }
        op.recordZoneChangeTokensUpdatedBlock = { _, newToken, _ in
            if let newToken { capturedToken = newToken }
        }
        op.recordZoneFetchResultBlock = { _, result in
            if case let .success(fetchResult) = result {
                capturedToken = fetchResult.serverChangeToken
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                op.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
                db.add(op)
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            self.logInfo("Change token expired — caller should retry with nil")
            return .init(
                upserted: [], deletedRecordNames: [],
                newToken: nil, tokenExpired: true, zoneMissing: false)
        } catch let error as CKError where error.code == .zoneNotFound {
            self.logInfo("Provider zone not found (pre-P4 Mac or schema pending)")
            return .init(
                upserted: [], deletedRecordNames: [],
                newToken: nil, tokenExpired: false, zoneMissing: true)
        } catch let error as CKError where error.code == .userDeletedZone {
            self.logInfo("Provider zone was deleted server-side")
            return .init(
                upserted: [], deletedRecordNames: [],
                newToken: nil, tokenExpired: false, zoneMissing: true)
        } catch {
            self.logError("Change-token fetch failed: \(error.localizedDescription)")
            return .init(
                upserted: [], deletedRecordNames: [],
                newToken: token, tokenExpired: false, zoneMissing: false)
        }

        self.logInfo("Per-provider zone changes fetched", metadata: [
            "upserted": "\(upserted.count)",
            "deleted": "\(deleted.count)",
            "token": capturedToken == nil ? "nil" : "captured",
        ])
        return .init(
            upserted: upserted,
            deletedRecordNames: deleted,
            newToken: capturedToken,
            tokenExpired: false,
            zoneMissing: false)
    }

    /// Static version of `decodeEnvelope` for use inside CloudKit operation
    /// callbacks where `self` can't be captured safely.
    private static func decodeEnvelopeStatic(from record: CKRecord) -> ProviderUsageEnvelope? {
        guard let payload = record["payload"] as? Data else { return nil }
        if let version = record["encodingVersion"] as? Int,
           version > CloudSyncConstants.providerPayloadVersion
        {
            return nil
        }
        guard let json = try? PayloadCompression.decompress(payload) else { return nil }
        return try? CloudSyncConstants.makeJSONDecoder().decode(
            ProviderUsageEnvelope.self, from: json)
    }

    // MARK: - CloudKit Quota Transition Write (Mac side, alert push trigger)

    /// Ensures a given quota push zone exists on the private database.
    /// Same fetch-first pattern as `ensureCustomZoneExists`.
    private func ensureQuotaZoneExists(_ zone: CKRecordZone) async throws {
        do {
            _ = try await self._privateDatabase!.recordZone(for: zone.zoneID)
            return
        } catch let error as CKError {
            if error.code != .zoneNotFound { throw error }
        }
        _ = try await self._privateDatabase!.modifyRecordZones(
            saving: [zone], deleting: [])
        self.logInfo("\(zone.zoneID.zoneName) created")
    }

    /// Writes a `QuotaTransition` record to a **per-provider × state** CloudKit
    /// zone so iOS receives a visible alert push whose body already includes
    /// the provider's name.
    ///
    /// State **and** provider are both encoded in the zone name — e.g. Codex
    /// depleted goes to `Quota-codex-depletedZone`. iOS pre-creates one
    /// `CKRecordZoneSubscription` per `(provider, state)` pair at app launch,
    /// each with an `alertBody` already formatted as "Codex 会话额度已耗尽" /
    /// "Codex session depleted" / etc. for the iPhone's locale. No subscription
    /// args, no `desiredKeys`, no NotificationServiceExtension — this is purely
    /// the Build 48/52 static-alertBody mechanism that is known to persist
    /// reliably on this container, scaled to `#providers × 2` subscriptions.
    ///
    /// Six fields total — five in the Production schema since v0.25.2
    /// (`providerName`, `providerID`, `state`, `transitionAt`, `deviceID`)
    /// plus the v0.27.0 build-65.2 addition `accountEmail` for
    /// multi-account scoping. CloudKit auto-replicates the new field
    /// to Production on first record write because it's a stored String
    /// with no queryable / sortable / searchable index. iOS NSE pulls
    /// it via `desiredKeys` and falls back gracefully when nil (i.e.
    /// Mac is on a pre-65.2 build that never set the field).
    ///
    /// `recordName` is derived from `(providerID, hourBucket)` so concurrent
    /// transitions from multiple Macs within the same hour collapse to a
    /// single record per zone (idempotent overwrite). Provider and state are
    /// not part of the name because they are already implied by the zone.
    public func writeQuotaTransition(
        providerName: String,
        providerID: String,
        state: String,
        transitionAt: Date,
        accountEmail: String? = nil) async -> SyncPushResult
    {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        let zoneName = QuotaProviderList.quotaZoneName(
            providerID: providerID, state: state)
        let zone = CKRecordZone(zoneName: zoneName)

        do {
            try await self.ensureQuotaZoneExists(zone)
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            return .failure("Failed to create \(zone.zoneID.zoneName): \(syncError.description)")
        }

        let deviceID = self.stableDeviceID()
        let hourBucket = Int(transitionAt.timeIntervalSince1970 / 3600)
        let recordName = "\(providerID)-\(hourBucket)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)

        let record = CKRecord(
            recordType: CloudSyncConstants.quotaTransitionRecordType, recordID: recordID)
        record["providerName"] = providerName as CKRecordValue
        record["providerID"] = providerID as CKRecordValue
        record["state"] = state as CKRecordValue
        record["transitionAt"] = transitionAt as CKRecordValue
        record["deviceID"] = deviceID as CKRecordValue
        // v0.27.0 build 65.2 — Mac-side multi-account scoping. Only
        // written when the caller has a non-empty account display
        // string so old iOS clients (and the production CKRecord
        // schema before this field rolled out) keep parsing cleanly.
        if let accountEmail, !accountEmail.isEmpty {
            record["accountEmail"] = accountEmail as CKRecordValue
        }

        do {
            try await self._privateDatabase!.save(record)
            self.logInfo("QuotaTransition record written", metadata: [
                "providerName": providerName,
                "state": state,
                "zone": zone.zoneID.zoneName,
                "recordName": recordName,
                "accountEmail": EmailRedaction.redact(accountEmail),
            ])
            return .success
        } catch let error as CKError where error.code == .serverRecordChanged {
            self.logInfo("QuotaTransition same-hour collision (idempotent overwrite)")
            return .success
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("QuotaTransition save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("QuotaTransition save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    /// Writes a quota **warning** transition record (iOS 1.6.0 / Mac 0.25.2).
    ///
    /// Reuses the existing `QuotaTransition` CKRecord type with **no new
    /// fields** — the threshold and window are packed into `recordName` so
    /// no CloudKit Production Dashboard schema deploy is required. `state`
    /// is set to the literal string `"warning"` so the same NSE that
    /// handles `depleted`/`restored` zone notifications can dispatch by
    /// state and read the recordName to construct a richer body
    /// ("Codex session at 50% warning threshold").
    ///
    /// **recordName format**: `"{providerID}-{window}-t{threshold}-{hourBucket}"`
    /// — e.g. `"codex-session-t50-477312"`. Different thresholds for the
    /// same (provider, window) produce different recordNames, so a user
    /// crossing 50% and then 20% within the same hour gets two distinct
    /// records and two distinct pushes (not collapsed by idempotency).
    /// Two Macs crossing the same threshold for the same provider+window
    /// in the same hour DO collapse — that's the intended dedupe.
    ///
    /// Zone: `Quota-{providerID}-warningZone` (per `QuotaProviderList`),
    /// which iOS subscribes to via the same `CKRecordZoneSubscription`
    /// mechanism used for depleted/restored. Each warning sub has a
    /// generic locale-resolved alertBody ("Codex usage warning"); the
    /// NSE replaces title + body with parsed context.
    ///
    /// See `Sources/CodexBar/Sync/QuotaTransitionWriter.swift` and
    /// `Research/020-multi-account-comprehensive.md` §R7.4 Phase 2.
    public func writeQuotaWarningTransition(
        providerName: String,
        providerID: String,
        window: String,
        threshold: Int,
        transitionAt: Date,
        accountEmail: String? = nil) async -> SyncPushResult
    {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        let zoneName = QuotaProviderList.quotaZoneName(
            providerID: providerID, state: "warning")
        let zone = CKRecordZone(zoneName: zoneName)

        do {
            try await self.ensureQuotaZoneExists(zone)
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            return .failure("Failed to create \(zone.zoneID.zoneName): \(syncError.description)")
        }

        let deviceID = self.stableDeviceID()
        let hourBucket = Int(transitionAt.timeIntervalSince1970 / 3600)
        // Pack (window, threshold) into recordName so multi-threshold
        // crossings within the same hour produce distinct records.
        // v0.27.0 build 65.2 adds the `accountEmail` field for
        // multi-account scoping — written as a record field rather
        // than packed into recordName so each iOS NSE invocation
        // can fetch + display the triggering account without having
        // to re-parse a longer recordName.
        let recordName = "\(providerID)-\(window)-t\(threshold)-\(hourBucket)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)

        let record = CKRecord(
            recordType: CloudSyncConstants.quotaTransitionRecordType, recordID: recordID)
        record["providerName"] = providerName as CKRecordValue
        record["providerID"] = providerID as CKRecordValue
        record["state"] = "warning" as CKRecordValue
        record["transitionAt"] = transitionAt as CKRecordValue
        record["deviceID"] = deviceID as CKRecordValue
        if let accountEmail, !accountEmail.isEmpty {
            record["accountEmail"] = accountEmail as CKRecordValue
        }

        do {
            try await self._privateDatabase!.save(record)
            self.logInfo("QuotaWarning record written", metadata: [
                "providerName": providerName,
                "window": window,
                "threshold": "\(threshold)",
                "zone": zone.zoneID.zoneName,
                "recordName": recordName,
                "accountEmail": EmailRedaction.redact(accountEmail),
            ])
            return .success
        } catch let error as CKError where error.code == .serverRecordChanged {
            self.logInfo("QuotaWarning same-hour collision (idempotent overwrite)")
            return .success
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("QuotaWarning save failed: \(syncError.description)")
            return .failure(syncError.description)
        } catch {
            self.logError("QuotaWarning save failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Provider Account Linkage (Research/019 §7)

    /// Save (or replace) a single `ProviderAccountLinkage` record.
    ///
    /// Same-`recordID` writes from two iPhones use CloudKit's last-writer-wins
    /// semantics (idempotent for merges; "last unmerge sticks" for inverses —
    /// matches user expectation that the most recent action holds).
    ///
    /// Concurrent merge confirmations from two iPhones produce **different**
    /// `recordID`s (each writes a fresh UUID record). Both records land; the
    /// reader unions on either. Idempotent in the union-find graph. See
    /// `Research/019` §11.5 row M.
    ///
    /// Lives in `DeviceProvidersZone` so the existing per-provider zone
    /// subscription delivers linkage upserts via the same change-token
    /// path snapshot records use.
    @discardableResult
    public func saveProviderAccountLinkage(
        _ linkage: ProviderAccountLinkage) async -> SyncPushResult
    {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        do {
            try await self.ensureProviderZoneExists()
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            return .failure("Failed to create provider zone: \(syncError.description)")
        }

        let ckRecordID = CKRecord.ID(
            recordName: ProviderAccountLinkage.recordName(for: linkage.recordID),
            zoneID: self.providerZone.zoneID)
        let record = CKRecord(
            recordType: CloudSyncConstants.providerAccountLinkageRecordType,
            recordID: ckRecordID)
        // CKRecord reserves the field name `recordID` (it's the built-in
        // CKRecord.ID property). Setting it via subscript raises an ObjC
        // exception (crash on build 115). The linkage UUID is already
        // embedded in the record's name (`"linkage-{UUID}"`) so we don't
        // need a redundant payload field — `decodeLinkage` reads the UUID
        // back from `record.recordID.recordName`.
        record["providerID"] = linkage.providerID as CKRecordValue
        record["linkedIdentifiers"] = linkage.linkedIdentifiers as CKRecordValue
        record["confirmedAt"] = linkage.confirmedAt as CKRecordValue
        record["confirmedFromDeviceID"] = linkage.confirmedFromDeviceID as CKRecordValue
        record["unmerge"] = (linkage.unmerge ? 1 : 0) as CKRecordValue

        do {
            _ = try await self._privateDatabase!.save(record)
            self.logInfo("Linkage record written", metadata: [
                "providerID": linkage.providerID,
                "linkedCount": "\(linkage.linkedIdentifiers.count)",
                "unmerge": "\(linkage.unmerge)",
            ])
            return .success
        } catch let ckError as CKError {
            let syncError = CloudSyncError(from: ckError)
            self.logError("Linkage save failed: \(syncError.description)")
            return .failure("Linkage save failed: \(syncError.description)")
        } catch {
            self.logError("Linkage save failed: \(error.localizedDescription)")
            return .failure("Linkage save failed: \(error.localizedDescription)")
        }
    }

    /// Fetch all linkage records from `DeviceProvidersZone`. Returns an empty
    /// array on zone-not-found OR unknown-record-type (= no linkage has ever
    /// been confirmed on this iCloud account yet; the record type is created
    /// lazily on first write).
    ///
    /// Individual decode failures are logged + skipped — one corrupt record
    /// never fails the whole fetch (mirrors `fetchPerProviderDeviceSnapshots`).
    public func fetchProviderAccountLinkages() async -> [ProviderAccountLinkage] {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return []
        }

        let query = CKQuery(
            recordType: CloudSyncConstants.providerAccountLinkageRecordType,
            predicate: NSPredicate(value: true))

        var matchResults: [(CKRecord.ID, Result<CKRecord, Error>)] = []
        do {
            let (results, queryCursor) = try await self._privateDatabase!.records(
                matching: query, inZoneWith: self.providerZone.zoneID)
            matchResults.append(contentsOf: results)

            var cursor = queryCursor
            while let currentCursor = cursor {
                let (nextResults, nextCursor) = try await self._privateDatabase!.records(
                    continuingMatchFrom: currentCursor)
                matchResults.append(contentsOf: nextResults)
                cursor = nextCursor
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            return []
        } catch {
            self.logError("Linkage fetch failed: \(error.localizedDescription)")
            return []
        }

        var linkages: [ProviderAccountLinkage] = []
        linkages.reserveCapacity(matchResults.count)
        for (recordID, result) in matchResults {
            switch result {
            case let .success(record):
                if let linkage = Self.decodeLinkage(from: record) {
                    linkages.append(linkage)
                } else {
                    self.logError(
                        "Failed to decode linkage record \(recordID.recordName)")
                }
            case let .failure(error):
                self.logError(
                    "Failed to fetch linkage record \(recordID.recordName): " +
                        error.localizedDescription)
            }
        }
        return linkages
    }

    /// Decode a `ProviderAccountLinkage` from a CKRecord. Returns `nil` if
    /// any required field is missing OR the record name lacks the
    /// `"linkage-"` prefix (= not one of our records — likely a
    /// different record type that hit our query by mistake). Exposed
    /// `public` so the iOS test target can exercise the CKRecord
    /// round-trip without going through the network layer.
    public static func decodeLinkage(from record: CKRecord) -> ProviderAccountLinkage? {
        let recordName = record.recordID.recordName
        let prefix = "linkage-"
        guard recordName.hasPrefix(prefix) else { return nil }
        let recordID = String(recordName.dropFirst(prefix.count))
        guard !recordID.isEmpty,
              let providerID = record["providerID"] as? String,
              let linkedIdentifiers = record["linkedIdentifiers"] as? [String],
              let confirmedAt = record["confirmedAt"] as? Date,
              let confirmedFromDeviceID = record["confirmedFromDeviceID"] as? String
        else {
            return nil
        }
        let unmergeValue = record["unmerge"]
        let unmerge: Bool = if let bool = unmergeValue as? Bool {
            bool
        } else if let int = unmergeValue as? Int {
            int != 0
        } else if let num = unmergeValue as? NSNumber {
            num.boolValue
        } else {
            false
        }
        return ProviderAccountLinkage(
            recordID: recordID,
            providerID: providerID,
            linkedIdentifiers: linkedIdentifiers,
            confirmedAt: confirmedAt,
            confirmedFromDeviceID: confirmedFromDeviceID,
            unmerge: unmerge)
    }

    // MARK: - Device Lifecycle Events (issue #29)

    /// Save a user-confirmed lifecycle event for a Mac sync device identity.
    /// The record is additive: archive/unarchive and alias/unalias are replayed
    /// by readers, while raw provider/device records remain untouched.
    @discardableResult
    public func saveDeviceLifecycleEvent(
        _ event: DeviceLifecycleEvent) async -> SyncPushResult
    {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .failure("CloudKit not available")
        }

        do {
            try await self.ensureProviderZoneExists()
        } catch {
            let syncError = CloudSyncError(from: error as? CKError ?? CKError(.internalError))
            return .failure("Failed to create provider zone: \(syncError.description)")
        }

        let ckRecordID = CKRecord.ID(
            recordName: DeviceLifecycleEvent.recordName(for: event.recordID),
            zoneID: self.providerZone.zoneID)
        let record = CKRecord(
            recordType: CloudSyncConstants.deviceLifecycleEventRecordType,
            recordID: ckRecordID)
        record["kind"] = event.kind.rawValue as CKRecordValue
        record["primaryDeviceID"] = event.primaryDeviceID as CKRecordValue
        record["relatedDeviceIDs"] = event.relatedDeviceIDs as CKRecordValue
        record["confirmedAt"] = event.confirmedAt as CKRecordValue
        record["confirmedFromDeviceID"] = event.confirmedFromDeviceID as CKRecordValue
        if let note = event.note {
            record["note"] = note as CKRecordValue
        }

        do {
            _ = try await self._privateDatabase!.save(record)
            self.logInfo("Device lifecycle event written", metadata: [
                "kind": event.kind.rawValue,
                "primaryDeviceID": event.primaryDeviceID,
                "relatedCount": "\(event.relatedDeviceIDs.count)",
            ])
            return .success
        } catch let ckError as CKError {
            let syncError = CloudSyncError(from: ckError)
            self.logError("Device lifecycle save failed: \(syncError.description)")
            return .failure("Device lifecycle save failed: \(syncError.description)")
        } catch {
            self.logError("Device lifecycle save failed: \(error.localizedDescription)")
            return .failure("Device lifecycle save failed: \(error.localizedDescription)")
        }
    }

    /// Fetch all device lifecycle events from `DeviceProvidersZone`. Unknown
    /// record type means no device lifecycle records exist or Production schema
    /// is not deployed yet; callers treat that as an empty decision log.
    public func fetchDeviceLifecycleEvents() async -> [DeviceLifecycleEvent] {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return []
        }

        let query = CKQuery(
            recordType: CloudSyncConstants.deviceLifecycleEventRecordType,
            predicate: NSPredicate(value: true))

        var matchResults: [(CKRecord.ID, Result<CKRecord, Error>)] = []
        do {
            let (results, queryCursor) = try await self._privateDatabase!.records(
                matching: query, inZoneWith: self.providerZone.zoneID)
            matchResults.append(contentsOf: results)

            var cursor = queryCursor
            while let currentCursor = cursor {
                let (nextResults, nextCursor) = try await self._privateDatabase!.records(
                    continuingMatchFrom: currentCursor)
                matchResults.append(contentsOf: nextResults)
                cursor = nextCursor
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            return []
        } catch {
            self.logError("Device lifecycle fetch failed: \(error.localizedDescription)")
            return []
        }

        var events: [DeviceLifecycleEvent] = []
        events.reserveCapacity(matchResults.count)
        for (recordID, result) in matchResults {
            switch result {
            case let .success(record):
                if let event = Self.decodeDeviceLifecycleEvent(from: record) {
                    events.append(event)
                } else {
                    self.logError(
                        "Failed to decode device lifecycle record \(recordID.recordName)")
                }
            case let .failure(error):
                self.logError(
                    "Failed to fetch device lifecycle record \(recordID.recordName): " +
                        error.localizedDescription)
            }
        }
        return events
    }

    /// Decode a `DeviceLifecycleEvent` from an in-memory CKRecord. Exposed for
    /// tests and mirrors `decodeLinkage`: the record UUID lives in recordName
    /// so we never set CloudKit's reserved `recordID` field.
    public static func decodeDeviceLifecycleEvent(from record: CKRecord) -> DeviceLifecycleEvent? {
        let recordName = record.recordID.recordName
        let prefix = "device-lifecycle-"
        guard recordName.hasPrefix(prefix) else { return nil }
        let recordID = String(recordName.dropFirst(prefix.count))
        guard !recordID.isEmpty,
              let kindRaw = record["kind"] as? String,
              let kind = DeviceLifecycleEvent.Kind(rawValue: kindRaw),
              let primaryDeviceID = record["primaryDeviceID"] as? String,
              let confirmedAt = record["confirmedAt"] as? Date,
              let confirmedFromDeviceID = record["confirmedFromDeviceID"] as? String
        else {
            return nil
        }
        let relatedDeviceIDs = record["relatedDeviceIDs"] as? [String] ?? []
        let note = record["note"] as? String
        return DeviceLifecycleEvent(
            recordID: recordID,
            kind: kind,
            primaryDeviceID: primaryDeviceID,
            relatedDeviceIDs: relatedDeviceIDs,
            confirmedAt: confirmedAt,
            confirmedFromDeviceID: confirmedFromDeviceID,
            note: note)
    }

    /// Returns a stable UUID for this device, persisted across launches in
    /// `UserDefaults`. On Mac it matches the SyncCoordinator's record-name
    /// `deviceID` (same UserDefaults key). On iOS it's a separate value, since
    /// iOS UserDefaults is per-app and the iPhone doesn't run SyncCoordinator.
    /// Exposed publicly for the LinkageRecord writer to stamp
    /// `confirmedFromDeviceID` on user-confirmed merges.
    public func stableDeviceID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: CloudSyncConstants.deviceIDKey) {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: CloudSyncConstants.deviceIDKey)
        return newID
    }

    // MARK: - CloudKit Read (iOS side)

    /// Fetches usage snapshots from all devices via CloudKit.
    ///
    /// Queries **three** sources and merges them by `deviceID`:
    /// - `DeviceProvidersZone` — per-provider records (P4 Mac builds). Winner
    ///   per device: a device that shows up here is fully represented by its
    ///   per-provider records and its legacy monolithic record is ignored.
    /// - `DeviceSnapshotsZone` custom zone — monolithic records from post-Build
    ///   48 Mac builds that predate P4.
    /// - default zone — monolithic records from the pre-42 era that wrote to
    ///   the default zone.
    ///
    /// Dedup rule: per-device priority is `providerZone > customZone > defaultZone`.
    /// Within a tier, most recent `syncTimestamp` wins (e.g. two legacy records
    /// for the same device across the Build 48 migration). `.empty` from the
    /// new zone is normal pre-P4 and does not cascade into the overall result.
    public func fetchAllDeviceSnapshots() async -> MultiDeviceSyncResult {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .error(CloudSyncError(from: CKError(.serviceUnavailable)))
        }

        // Fetch new zone first. Its failures are non-fatal (pre-P4, schema not
        // deployed, etc.) — we still want legacy data to flow through.
        let perProviderResult = await self.fetchPerProviderDeviceSnapshots()
        var perProviderSnapshots: [SyncedUsageSnapshot] = []
        var perProviderError: CloudSyncError?
        switch perProviderResult {
        case let .success(snaps):
            perProviderSnapshots = snaps
        case .empty:
            break
        case let .error(error):
            perProviderError = error
        }

        let legacyResult = await self.fetchLegacyDeviceSnapshots()
        var legacySnapshots: [SyncedUsageSnapshot] = []
        var legacyError: CloudSyncError?
        switch legacyResult {
        case let .success(snaps):
            legacySnapshots = snaps
        case .empty:
            break
        case let .error(error):
            legacyError = error
        }

        let merged = Self.prioritiseByDevice(
            perProvider: perProviderSnapshots, legacy: legacySnapshots)

        if merged.isEmpty {
            // Surface whichever error came up, preferring legacy since that
            // was historically the canonical failure signal.
            if let legacyError { return .error(legacyError) }
            if let perProviderError { return .error(perProviderError) }
            self.logInfo("CloudKit query returned no decodable snapshots")
            return .empty
        }

        self.logInfo("Fetched merged snapshots from CloudKit", metadata: [
            "devices": "\(merged.count)",
            "providerZone": "\(perProviderSnapshots.count)",
            "legacy": "\(legacySnapshots.count)",
        ])
        return .success(merged)
    }

    /// Reads legacy `DeviceSnapshot` records from both the custom zone (Build
    /// 48+ Macs) and the default zone (pre-42 Macs). Used as fallback when the
    /// new per-provider zone has no data for a given device. This is the
    /// pre-P4 implementation of `fetchAllDeviceSnapshots`, renamed.
    ///
    /// Public so iOS's cache-based flow (v2 — Research/011) can pull ONLY the
    /// legacy slice without re-querying the per-provider zone.
    public func fetchLegacyDeviceSnapshots() async -> MultiDeviceSyncResult {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .error(CloudSyncError(from: CKError(.serviceUnavailable)))
        }
        let query = CKQuery(
            recordType: CloudSyncConstants.recordType,
            predicate: NSPredicate(value: true))

        var snapshots: [SyncedUsageSnapshot] = []
        var firstError: CloudSyncError?

        // Read from custom zone (primary, where new builds write).
        // .zoneNotFound is an expected first-run condition — treat it as empty, not error.
        do {
            let (matchResults, _) = try await _privateDatabase!.records(
                matching: query, inZoneWith: self.customZone.zoneID)
            snapshots.append(contentsOf: self.decodeSnapshots(matchResults, source: "custom"))
        } catch let error as CKError where error.code == .zoneNotFound {
            self.logInfo("Custom zone does not exist yet (first run on this device)")
        } catch let error as CKError {
            firstError = CloudSyncError(from: error)
            self.logError("Custom zone query failed: \(firstError!.description)")
        } catch {
            firstError = .unknown(error.localizedDescription)
            self.logError("Custom zone query failed: \(error.localizedDescription)")
        }

        // Read from default zone (legacy, where old Mac builds still write).
        // This is the migration safety net — once all Macs are on the new build, the
        // default zone is empty and this query returns nothing.
        do {
            let (matchResults, _) = try await _privateDatabase!.records(matching: query)
            snapshots.append(contentsOf: self.decodeSnapshots(matchResults, source: "default"))
        } catch let error as CKError {
            // Only surface this error if the custom-zone read also failed.
            if firstError == nil {
                firstError = CloudSyncError(from: error)
                self.logError("Default zone query failed: \(firstError!.description)")
            } else {
                self.logError("Default zone query also failed: \(error.localizedDescription)")
            }
        } catch {
            if firstError == nil {
                firstError = .unknown(error.localizedDescription)
            }
        }

        // Dedupe by deviceID, keeping the most recent syncTimestamp per device.
        // After Mac upgrades, the custom-zone version of each device will be newer.
        var byDeviceID: [String: SyncedUsageSnapshot] = [:]
        for snapshot in snapshots {
            let key = snapshot.deviceID ?? snapshot.deviceName
            if let existing = byDeviceID[key] {
                if snapshot.syncTimestamp > existing.syncTimestamp {
                    byDeviceID[key] = snapshot
                }
            } else {
                byDeviceID[key] = snapshot
            }
        }
        snapshots = Array(byDeviceID.values)

        // Sort by syncTimestamp descending (newest first), client-side.
        snapshots.sort { $0.syncTimestamp > $1.syncTimestamp }

        if snapshots.isEmpty {
            if let firstError {
                return .error(firstError)
            }
            self.logInfo("CloudKit query returned no decodable snapshots")
            return .empty
        }

        self.logInfo("Fetched snapshots from CloudKit", metadata: [
            "devices": "\(snapshots.count)",
        ])
        return .success(snapshots)
    }

    // MARK: - CloudKit Per-Provider Read (iOS side, P5)

    /// Fetches per-provider snapshot records from `DeviceProvidersZone` (P4's
    /// write target) and reconstructs one `SyncedUsageSnapshot` per device by
    /// grouping the envelopes by `deviceID`.
    ///
    /// Returns `.empty` when the zone doesn't exist yet — this is the expected
    /// state on iOS builds before any P4 Mac has written to the new zone (or
    /// when Production schema isn't deployed yet). Callers fall back to
    /// `fetchAllDeviceSnapshots()` (legacy zones) for those devices.
    ///
    /// Individual record decode/decompress failures are logged and skipped —
    /// one bad record never fails the whole fetch, matching the legacy
    /// `decodeSnapshots` behavior.
    public func fetchPerProviderDeviceSnapshots() async -> MultiDeviceSyncResult {
        guard self.cloudKitAvailable, self._privateDatabase != nil else {
            return .error(CloudSyncError(from: CKError(.serviceUnavailable)))
        }

        let query = CKQuery(
            recordType: CloudSyncConstants.providerRecordType,
            predicate: NSPredicate(value: true))

        let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            let (results, _) = try await _privateDatabase!.records(
                matching: query, inZoneWith: self.providerZone.zoneID)
            matchResults = results
        } catch let error as CKError where error.code == .zoneNotFound {
            self.logInfo("Provider zone does not exist yet (no P4 Mac has uploaded)")
            return .empty
        } catch let error as CKError where error.code == .unknownItem {
            // Record type hasn't been deployed in Production yet. Not a failure
            // — we just haven't gotten the new data path to light up yet.
            self.logInfo("Provider record type not in Production schema yet")
            return .empty
        } catch let error as CKError {
            let syncError = CloudSyncError(from: error)
            self.logError("Provider zone query failed: \(syncError.description)")
            return .error(syncError)
        } catch {
            self.logError("Provider zone query failed: \(error.localizedDescription)")
            return .error(.unknown(error.localizedDescription))
        }

        // Decode each record into an envelope.
        var envelopesByDeviceID: [String: [ProviderUsageEnvelope]] = [:]
        for (recordID, result) in matchResults {
            switch result {
            case let .success(record):
                guard let envelope = self.decodeEnvelope(from: record) else {
                    self.logError(
                        "Failed to decode provider envelope from \(recordID.recordName)")
                    continue
                }
                envelopesByDeviceID[envelope.deviceID, default: []].append(envelope)
            case let .failure(error):
                self.logError(
                    "Failed to fetch provider record \(recordID.recordName): " +
                        error.localizedDescription)
            }
        }

        if envelopesByDeviceID.isEmpty {
            return .empty
        }

        let snapshots = Self.reconstructSnapshots(envelopesByDeviceID: envelopesByDeviceID)

        self.logInfo("Fetched per-provider records from CloudKit", metadata: [
            "devices": "\(snapshots.count)",
            "records": "\(matchResults.count)",
        ])
        return .success(snapshots)
    }

    /// Groups per-provider envelopes into one `SyncedUsageSnapshot` per
    /// device. Device-level metadata is taken from the envelope with the most
    /// recent `syncTimestamp`; provider order inside the snapshot is sorted
    /// by `lastUpdated` descending so the most-recently-refreshed provider
    /// bubbles up. Pure function — lifted out for unit testing.
    public static func reconstructSnapshots(
        envelopesByDeviceID: [String: [ProviderUsageEnvelope]]) -> [SyncedUsageSnapshot]
    {
        var snapshots: [SyncedUsageSnapshot] = []
        snapshots.reserveCapacity(envelopesByDeviceID.count)
        for (_, envelopes) in envelopesByDeviceID {
            guard let latestEnvelope = envelopes.max(by: {
                $0.syncTimestamp < $1.syncTimestamp
            }) else {
                continue
            }
            let providers = envelopes
                .map(\.provider)
                .sorted { $0.lastUpdated > $1.lastUpdated }

            snapshots.append(SyncedUsageSnapshot(
                providers: providers,
                syncTimestamp: latestEnvelope.syncTimestamp,
                deviceName: latestEnvelope.deviceName,
                deviceID: latestEnvelope.deviceID,
                appVersion: latestEnvelope.appVersion,
                mobileVersion: latestEnvelope.mobileVersion,
                notificationPushEnabled: latestEnvelope.notificationPushEnabled))
        }
        snapshots.sort { $0.syncTimestamp > $1.syncTimestamp }
        return snapshots
    }

    /// Per-device priority merge of new-zone and legacy-zone results. Pure
    /// function — lifted out for unit testing. A device in `perProvider` wins
    /// over the same device in `legacy`; devices only in one side pass
    /// through unchanged.
    public static func prioritiseByDevice(
        perProvider: [SyncedUsageSnapshot],
        legacy: [SyncedUsageSnapshot]) -> [SyncedUsageSnapshot]
    {
        var byKey: [String: SyncedUsageSnapshot] = [:]
        for snapshot in perProvider {
            let key = snapshot.deviceID ?? snapshot.deviceName
            byKey[key] = snapshot
        }
        for snapshot in legacy {
            let key = snapshot.deviceID ?? snapshot.deviceName
            if byKey[key] == nil {
                byKey[key] = snapshot
            }
        }
        return Array(byKey.values).sorted { $0.syncTimestamp > $1.syncTimestamp }
    }

    /// Extracts a `ProviderUsageEnvelope` from a `DeviceProviderSnapshot`
    /// CKRecord. Returns `nil` if the payload is missing, version-mismatched,
    /// or fails to decompress/decode.
    private func decodeEnvelope(from record: CKRecord) -> ProviderUsageEnvelope? {
        guard let payload = record["payload"] as? Data else { return nil }
        // encodingVersion is advisory — missing or zero means "legacy v1 zlib
        // JSON", which is what we know how to decode. Unknown future versions
        // return nil so we don't silently mis-decode.
        if let version = record["encodingVersion"] as? Int,
           version > CloudSyncConstants.providerPayloadVersion
        {
            return nil
        }
        guard let json = try? PayloadCompression.decompress(payload) else { return nil }
        return try? self.decoder.decode(ProviderUsageEnvelope.self, from: json)
    }

    /// Decodes a CloudKit query match result list into snapshot objects, logging any failures.
    private func decodeSnapshots(
        _ matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
        source: String) -> [SyncedUsageSnapshot]
    {
        var result: [SyncedUsageSnapshot] = []
        for (recordID, queryResult) in matchResults {
            switch queryResult {
            case let .success(record):
                if let data = record["payload"] as? Data,
                   let snapshot = try? decoder.decode(SyncedUsageSnapshot.self, from: data)
                {
                    result.append(snapshot)
                } else {
                    self.logError(
                        "Failed to decode snapshot from \(source) record \(recordID.recordName)")
                }
            case let .failure(error):
                self.logError(
                    "Failed to fetch \(source) record \(recordID.recordName): " +
                        error.localizedDescription)
            }
        }
        return result
    }

    // MARK: - Legacy KVS (backward compatibility)

    /// Fetches the latest snapshot from KVS (fallback for when CloudKit has no data).
    public func fetchKVSSnapshot() -> SyncedUsageSnapshot? {
        guard let data = kvsStore.data(forKey: CloudSyncConstants.kvsSnapshotKey) else { return nil }
        return try? self.decoder.decode(SyncedUsageSnapshot.self, from: data)
    }

    @discardableResult
    public func synchronizeKVSStore() -> Bool {
        let result = self.kvsStore.synchronize()
        if !result {
            self.logError("iCloud Key-Value Store synchronize() returned unavailable")
        }
        return result
    }

    /// Starts observing KVS changes (backward compat with older Mac apps that only write KVS).
    public func startKVSObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        self.stopKVSObserving()
        self.kvsObserverToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self.kvsStore,
            queue: .main)
        { [weak self] notification in
            let result = self?.parseKVSSyncResult(from: notification) ?? .empty
            Task { @MainActor in
                handler(result)
            }
        }
        _ = self.synchronizeKVSStore()
    }

    /// Stops observing KVS changes.
    public func stopKVSObserving() {
        guard let kvsObserverToken else { return }
        NotificationCenter.default.removeObserver(kvsObserverToken)
        self.kvsObserverToken = nil
    }

    // MARK: - Deprecated compatibility shims

    /// Legacy fetch — reads from KVS. Prefer `fetchAllDeviceSnapshots()` for CloudKit.
    public func fetchSnapshot() -> SyncedUsageSnapshot? {
        self.fetchKVSSnapshot()
    }

    /// Legacy observe — uses KVS. Prefer CloudKit subscription for real-time updates.
    public func startObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        self.startKVSObserving(handler: handler)
    }

    /// Legacy stop — stops KVS observation.
    public func stopObserving() {
        self.stopKVSObserving()
    }

    /// Legacy synchronize — triggers KVS sync.
    @discardableResult
    public func synchronizeStore() -> Bool {
        self.synchronizeKVSStore()
    }

    // MARK: - Private

    private func pushToKVS(data: Data) {
        guard data.count <= CloudSyncConstants.maxKVSPayloadBytes else {
            self.logError("Snapshot too large for KVS fallback (\(data.count) bytes)")
            return
        }
        self.kvsStore.set(data, forKey: CloudSyncConstants.kvsSnapshotKey)
        self.kvsStore.synchronize()
    }

    private func parseKVSSyncResult(from notification: Notification) -> SyncResult {
        let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int

        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            return .quotaExceeded
        case NSUbiquitousKeyValueStoreAccountChange:
            if let snapshot = fetchKVSSnapshot() {
                return .success(snapshot)
            }
            return .accountChanged
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            if let snapshot = fetchKVSSnapshot() {
                return .success(snapshot)
            }
            return .initialSync
        default:
            if let snapshot = fetchKVSSnapshot() {
                return .success(snapshot)
            }
            return .empty
        }
    }

    private func logInfo(_ message: String, metadata: [String: String]? = nil) {
        #if canImport(OSLog)
        if let metadata, !metadata.isEmpty {
            let rendered = metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            self.logger.info("\(message, privacy: .public) \(rendered, privacy: .public)")
        } else {
            self.logger.info("\(message, privacy: .public)")
        }
        #endif
    }

    private func logError(_ message: String) {
        #if canImport(OSLog)
        self.logger.error("\(message, privacy: .public)")
        #endif
    }
}
