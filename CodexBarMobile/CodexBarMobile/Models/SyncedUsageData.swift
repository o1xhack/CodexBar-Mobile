import CloudKit
import CodexBarSync
import Foundation
import Observation
import SwiftData

/// Detailed sync status for UI display.
enum SyncStatus: Sendable, Equatable {
    /// Successfully synced, showing how long ago.
    case synced(ago: TimeInterval)
    /// Currently fetching data from CloudKit.
    case syncing
    /// Sync failed with a specific error message.
    case error(message: String)
    /// No Mac data found — Mac app may not be running or sync is not configured.
    case noData
    /// CloudKit returned data but it couldn't be decoded (version mismatch).
    case incompatibleData

    var isError: Bool {
        switch self {
        case .error, .noData, .incompatibleData: true
        default: false
        }
    }
}

/// ViewModel for the iOS app. Fetches usage snapshots from CloudKit (all
/// devices), maintains an in-memory `SnapshotCache` with explicit per-zone
/// slots, and exposes the merged view to SwiftUI. Falls back to KVS for
/// older Mac app versions.
///
/// See `Research/011-mac-sync-incremental-v2.md` for the cache design + the
/// multi-device traces that fixes the v1 P6/P7 regression.
@Observable
@MainActor
final class SyncedUsageData {
    /// Merged snapshot from all devices (primary data source for views).
    var snapshot: SyncedUsageSnapshot? {
        didSet { self.publicationRevision &+= 1 }
    }

    private(set) var publicationRevision: UInt64 = 0

    /// Per-device snapshots before merging (for debug/display).
    var deviceSnapshots: [SyncedUsageSnapshot] = []

    /// Raw per-device snapshots before device lifecycle alias/archive replay.
    /// Developer diagnostics use this so archived devices and old aliases
    /// remain inspectable even when the main UI hides them from active state.
    var rawDeviceSnapshots: [SyncedUsageSnapshot] = []

    /// Device rows derived from raw snapshots + lifecycle events.
    var deviceManagementItems: [SyncDeviceManagementItem] = []

    /// Current sync status with detailed error information.
    var syncStatus: SyncStatus = .noData

    /// True when data comes from KVS fallback (old Mac app without CloudKit).
    var usingKVSFallback: Bool = false

    /// Legacy error string (kept for backward compat with existing UI).
    var lastSyncError: String? {
        switch self.syncStatus {
        case let .error(message): message
        case .noData: String(localized: "No Mac data found")
        case .incompatibleData: String(localized: "Data format incompatible. Please update Mac app.")
        default: nil
        }
    }

    /// Number of Mac devices contributing data.
    var deviceCount: Int {
        self.deviceSnapshots.count
    }

    // MARK: - Private state

    private let reader: CloudSyncReader
    private var isObservingKVS = false
    private var isObservingSilentPush = false

    /// In-memory zone-separated cache. Mutated only on MainActor. Never
    /// persisted — cold start rehydrates via SwiftData (P3).
    private var cache = SnapshotCache()

    /// User-confirmed account linkages from CloudKit (Research/019 §7).
    /// Refreshed on every full fetch alongside the per-zone snapshots.
    /// Mutations go through `confirmLinkage` / `revokeLinkage` which
    /// also write to CloudKit so other iPhones see the same union state.
    private(set) var providerLinkages: [ProviderAccountLinkage] = []

    /// User-confirmed device lifecycle events from CloudKit (issue #29).
    /// Mutations go through merge/archive/restore/unmerge actions below.
    private(set) var deviceLifecycleEvents: [DeviceLifecycleEvent] = []

    /// Serialization handle for refresh paths. `fetchFromCloudKit` and
    /// `refreshIncremental` both go through `coalesceRefresh`, which awaits
    /// any already-in-flight refresh before starting a new one. Without
    /// this, a silent-push storm can race against a concurrent full fetch
    /// and an older delta can land on top of newer state. Hardening fix
    /// from Build 68 review.
    private var inFlightRefresh: Task<Void, Never>?

    /// NotificationCenter token for the silent-push observer; held so the
    /// observer can be removed if `stopObserving()` is added later. Today
    /// `SyncedUsageData` is created once at `@main` via `@State` and lives
    /// for the app's lifetime, so explicit removal isn't strictly required
    /// — the `isObservingSilentPush` guard already prevents
    /// double-registration on accidental re-entry into `startObserving`.
    /// `[weak self]` in the closure means a hypothetically-deallocated
    /// instance would no-op rather than crash.
    private var silentPushObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    init(reader: CloudSyncReader = CloudSyncReader(), hydrateFromPersistence: Bool = true) {
        self.reader = reader
        // Preview fixtures must not scan the real store or import account/KVS state.
        guard hydrateFromPersistence else { return }

        // Linkages cached in UserDefaults so cold start applies them
        // BEFORE the first CloudKit fetch returns. Without this the user
        // sees 2 cards (the unmerged pre-link state) for the 1–2 seconds
        // it takes the per-provider zone query to round-trip — minor but
        // user-visible regression vs the "merge feels permanent" UX
        // promise of Research/019 §7. CloudKit remains the source of
        // truth; the cache is invalidated + repopulated on every
        // `performFullFetch`.
        self.providerLinkages = Self.loadCachedLinkages()
        self.deviceLifecycleEvents = Self.loadCachedDeviceLifecycleEvents()

        // P3: hydrate from SwiftData so the Cost tab shows something
        // immediately on cold start. We seed into legacyByDevice bucket —
        // SwiftData doesn't track zone-of-origin.
        let context = ModelContainerFactory.sharedMainContext()
        if let hydrated = Self.hydrateFromSwiftData(context: context) {
            self.cache.seedFromColdStart(hydrated.devices)
            self.republishFromCache()
            return
        }

        // KVS fallback for legacy Mac apps.
        if let kvsSnapshot = reader.latestKVSSnapshot() {
            self.cache.seedFromColdStart([kvsSnapshot])
            self.republishFromCache()
        }
    }

    // MARK: - Linkage cache (UserDefaults)

    /// UserDefaults key for the local linkage cache. Re-derived from
    /// CloudKit on every full fetch; the local copy exists only to bridge
    /// the cold-start gap before that first CloudKit round-trip returns.
    private nonisolated static let linkageCacheDefaultsKey = "com.codexbar.linkageCache.v1"
    private nonisolated static let deviceLifecycleCacheDefaultsKey = "com.codexbar.deviceLifecycleCache.v1"

    nonisolated static func loadCachedLinkages() -> [ProviderAccountLinkage] {
        guard let data = UserDefaults.standard.data(forKey: linkageCacheDefaultsKey) else {
            return []
        }
        let decoder = CloudSyncConstants.makeJSONDecoder()
        return (try? decoder.decode([ProviderAccountLinkage].self, from: data)) ?? []
    }

    nonisolated static func saveCachedLinkages(_ linkages: [ProviderAccountLinkage]) {
        let encoder = CloudSyncConstants.makeJSONEncoder()
        if let data = try? encoder.encode(linkages) {
            UserDefaults.standard.set(data, forKey: Self.linkageCacheDefaultsKey)
        }
    }

    nonisolated static func loadCachedDeviceLifecycleEvents() -> [DeviceLifecycleEvent] {
        guard let data = UserDefaults.standard.data(forKey: deviceLifecycleCacheDefaultsKey) else {
            return []
        }
        let decoder = CloudSyncConstants.makeJSONDecoder()
        return (try? decoder.decode([DeviceLifecycleEvent].self, from: data)) ?? []
    }

    nonisolated static func saveCachedDeviceLifecycleEvents(_ events: [DeviceLifecycleEvent]) {
        let encoder = CloudSyncConstants.makeJSONEncoder()
        if let data = try? encoder.encode(events) {
            UserDefaults.standard.set(data, forKey: Self.deviceLifecycleCacheDefaultsKey)
        }
    }

    private nonisolated static func mergeCloudWithLocalPending<T>(
        cloud: [T],
        local: [T],
        recordID: (T) -> String) -> (records: [T], localOnly: [T])
    {
        let cloudRecordIDs = Set(cloud.map(recordID))
        let localOnly = local.filter { !cloudRecordIDs.contains(recordID($0)) }
        return (cloud + localOnly, localOnly)
    }

    /// Reads SwiftData's per-device rows + the standard merge. Returns nil
    /// when the store is empty or any decode fails.
    private static func hydrateFromSwiftData(
        context: ModelContext) -> (devices: [SyncedUsageSnapshot], merged: SyncedUsageSnapshot)?
    {
        do {
            let devices = try SwiftDataBridge.readAllDeviceSnapshots(from: context)
            guard !devices.isEmpty, let merged = CloudSyncReader.mergeSnapshots(devices) else {
                return nil
            }
            return (devices, merged)
        } catch {
            print("[CodexBar SwiftData] hydrate on launch failed: \(error)")
            return nil
        }
    }

    /// Starts observing: runs a fresh full fetch, wires KVS + silent push.
    func startObserving() {
        // 1. Start KVS observation (backward compat with old Mac apps that
        //    only write KVS, pre-CloudKit).
        if !self.isObservingKVS {
            self.isObservingKVS = true
            self.reader.startKVSObserving { [weak self] result in
                guard let self else { return }
                // KVS is a last-resort fallback; only use it if we have no
                // CloudKit data at all.
                if self.cache.legacyByDevice.isEmpty, self.cache.perProviderByDevice.isEmpty {
                    switch result {
                    case let .success(kvsSnapshot):
                        self.cache.seedFromColdStart([kvsSnapshot])
                        self.republishFromCache()
                    case .empty, .initialSync:
                        break
                    case .quotaExceeded:
                        self.syncStatus = .error(message: String(localized: "iCloud storage quota exceeded"))
                    case .accountChanged:
                        if let kvsSnapshot = self.reader.latestKVSSnapshot() {
                            self.cache.seedFromColdStart([kvsSnapshot])
                            self.republishFromCache()
                        }
                    }
                }
            }
        }

        // 2. Subscribe to silent-push-triggered incremental refresh.
        //    AppDelegate posts .codexBarProviderZoneDidChange on every
        //    DeviceProvidersZone push. Token retained on `silentPushObserver`
        //    so deinit can remove it cleanly.
        if !self.isObservingSilentPush {
            self.isObservingSilentPush = true
            self.silentPushObserver = NotificationCenter.default.addObserver(
                forName: .codexBarProviderZoneDidChange,
                object: nil,
                queue: .main)
            { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshIncremental()
                }
            }
        }

        // 3. Fetch from CloudKit (primary, full fetch).
        Task {
            await self.fetchFromCloudKit()
        }
    }

    // MARK: - Refresh coalescer

    /// Funnel for the two refresh entry points (full fetch + incremental).
    /// If a refresh is already in flight, just await it instead of starting
    /// a parallel one — prevents an older delta or fetch from landing on
    /// top of newer cache state under a silent-push storm.
    private func coalesceRefresh(_ work: @escaping @MainActor () async -> Void) async {
        if let inFlight = self.inFlightRefresh {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            await work()
        }
        self.inFlightRefresh = task
        await task.value
        // Clear ONLY if the task we just awaited is still the registered
        // one — a new refresh might have started after ours finished.
        if self.inFlightRefresh == task {
            self.inFlightRefresh = nil
        }
    }

    // MARK: - Full fetch (CKQuery on both zones)

    /// Runs a full fetch against BOTH zones, rebuilds the cache from the
    /// result, and republishes. Called on app launch, pull-to-refresh, and
    /// as a fallback when the incremental path errors out.
    func fetchFromCloudKit() async {
        await self.coalesceRefresh {
            await self.performFullFetch()
        }
    }

    private func performFullFetch() async {
        self.syncStatus = .syncing

        // Fire zone queries in parallel (independent network I/O).
        // Linkages share the per-provider zone so they ride the same
        // CKQuery surface; isolated as a third async let to keep the
        // existing per/legacy unpacking logic untouched.
        async let perProviderResult = self.reader.fetchPerProviderDeviceSnapshots()
        async let legacyResult = self.reader.fetchLegacyDeviceSnapshots()
        async let linkagesResult = self.reader.fetchProviderAccountLinkages()
        async let lifecycleResult = self.reader.fetchDeviceLifecycleEvents()

        let per = await perProviderResult
        let legacy = await legacyResult
        // Union CloudKit's list with any local linkages that haven't yet
        // round-tripped through CloudKit's eventual-consistency window.
        // Without this, a user who taps "Same account?" right before a
        // pull-to-refresh fires would see the merged view briefly, then
        // see the cards split back when the refresh completes BEFORE CK
        // has indexed their fresh write. Survives until the next refresh
        // when CK returns the user's own record (then dedupe by recordID).
        let cloudLinkages = await linkagesResult
        let mergedLinkages = Self.mergeCloudWithLocalPending(
            cloud: cloudLinkages,
            local: self.providerLinkages,
            recordID: \.recordID)
        self.providerLinkages = mergedLinkages.records
        Self.saveCachedLinkages(self.providerLinkages)

        let cloudLifecycleEvents = await lifecycleResult
        let mergedLifecycleEvents = Self.mergeCloudWithLocalPending(
            cloud: cloudLifecycleEvents,
            local: self.deviceLifecycleEvents,
            recordID: \.recordID)
        self.deviceLifecycleEvents = mergedLifecycleEvents.records
        Self.saveCachedDeviceLifecycleEvents(self.deviceLifecycleEvents)

        // Retry CloudKit save for any locally-cached linkage that never
        // made it to the cloud. Common cause: a prior build crashed
        // mid-save (build 115's `record["recordID"]` ObjC exception),
        // leaving the linkage applied locally + persisted in
        // UserDefaults but invisible to other iPhones on the same iCloud
        // account. Fire-and-forget — failures stay local and re-retry
        // next launch / refresh.
        //
        // **Trade-offs (deliberate, NOT bugs):**
        //
        // 1. No retry backoff. If CloudKit is persistently unreachable,
        //    every `performFullFetch` re-dispatches a save Task. Typical
        //    session has 1–5 fetches with 1–2 pending linkages, so the
        //    waste is small. Adding per-recordID exponential backoff
        //    would require persisted retry-count state (UserDefaults
        //    again) for a corner-case rarely hit in practice.
        //
        // 2. No in-flight deduplication. Two overlapping refreshes can
        //    dispatch two Tasks for the same `recordID`. CKDatabase.save
        //    is idempotent on identical recordID (last-writer-wins, same
        //    payload → no observable difference), so the only cost is
        //    one wasted CK round-trip. Bookkeeping for in-flight save
        //    set would add complexity to handle the rare case.
        //
        // 3. `pending` captured by value (struct) — safe across the
        //    refresh's actor hop. `[weak self]` defensive; SyncedUsageData
        //    is app-lifetime so the weak unwrap is effectively non-nil.
        for pending in mergedLinkages.localOnly {
            Task { [weak self] in
                _ = await self?.reader.saveProviderAccountLinkage(pending)
            }
        }
        for pending in mergedLifecycleEvents.localOnly {
            Task { [weak self] in
                _ = await self?.reader.saveDeviceLifecycleEvent(pending)
            }
        }

        // Unpack results per zone. `.error` means transient failure — DO NOT
        // wipe that bucket, preserve whatever was cached before (Codex
        // review P1). `.empty` / `.success` are authoritative and DO replace
        // the bucket.
        let perArg: [SyncedUsageSnapshot]?
        var firstError: CloudSyncError?
        switch per {
        case let .success(snaps): perArg = snaps
        case .empty: perArg = []
        case let .error(e):
            perArg = nil
            firstError = e
        }
        let legacyArg: [SyncedUsageSnapshot]?
        switch legacy {
        case let .success(snaps): legacyArg = snaps
        case .empty: legacyArg = []
        case let .error(e):
            legacyArg = nil
            firstError = firstError ?? e
        }

        // If BOTH zones errored, preserve the entire cache — don't show the
        // user blank content just because CloudKit was momentarily
        // unreachable. Surface the error in status but leave `snapshot`
        // pointing at whatever was hydrated / from last successful fetch.
        if perArg == nil, legacyArg == nil {
            if let firstError {
                self.syncStatus = .error(message: firstError.description)
            } else {
                self.syncStatus = .noData
            }
            return
        }

        var nextCache = self.cache
        nextCache.replaceFromFullFetch(perProviderSnapshots: perArg, legacySnapshots: legacyArg)
        let rawDeviceSnapshots = nextCache.buildDeviceSnapshots()
        if rawDeviceSnapshots.isEmpty {
            if let kvsSnapshot = reader.latestKVSSnapshot() {
                nextCache.seedFromColdStart([kvsSnapshot])
                self.cache = nextCache
                self.usingKVSFallback = true
                self.republishFromCache()
                return
            }
            self.cache = nextCache
            self.rawDeviceSnapshots = []
            self.deviceSnapshots = []
            self.deviceManagementItems = []
            self.snapshot = nil
            self.syncStatus = firstError.map { .error(message: $0.description) } ?? .noData
            return
        }
        do {
            while true {
                let revision = self.publicationRevision
                try await CostHistoryWorker.shared.persistFull(nextCache.buildDeviceSnapshots())
                var rebasedCache = self.cache
                let changedDuringSave = revision != self.publicationRevision
                // Publish each successful durable commit before attempting any
                // rebase. A later failure must retain this committed state.
                self.cache = nextCache
                self.usingKVSFallback = false
                self.republishFromCache()
                guard changedDuringSave else { break }
                rebasedCache.replaceFromFullFetch(perProviderSnapshots: perArg, legacySnapshots: legacyArg)
                nextCache = rebasedCache
            }
        } catch {
            self.syncStatus = .error(message: String(localized:
                "Could not save synced data. Your previous data has been kept. Pull to refresh and try again."))
        }
    }

    // MARK: - Provider account linkage (Research/019 §7)

    /// Confirm that two existing provider cards represent the same logical
    /// account. Writes a `ProviderAccountLinkage` CKRecord and re-merges
    /// locally so the UI updates immediately, without waiting for the
    /// CloudKit round-trip + zone change-token push to fire.
    func confirmLinkage(
        providerID: String,
        linkedIdentifiers: [String]) async
    {
        let linkage = ProviderAccountLinkage(
            providerID: providerID,
            linkedIdentifiers: linkedIdentifiers,
            confirmedFromDeviceID: self.reader.currentDeviceID(),
            unmerge: false)
        self.providerLinkages.append(linkage)
        Self.saveCachedLinkages(self.providerLinkages)
        self.republishFromCache()
        // CloudKit write happens after local apply — failure logs a
        // message but doesn't roll back the local union (the user
        // experienced the merge; we don't want to flicker back). Next
        // refresh will re-fetch and reconcile.
        _ = await self.reader.saveProviderAccountLinkage(linkage)
    }

    /// Revoke a previously-confirmed merge. Writes an inverse linkage with
    /// `unmerge=true` and re-merges locally. Additive on the CK side
    /// (never deletes the original) so the audit trail survives.
    func revokeLinkage(
        providerID: String,
        linkedIdentifiers: [String]) async
    {
        let inverse = ProviderAccountLinkage(
            providerID: providerID,
            linkedIdentifiers: linkedIdentifiers,
            confirmedFromDeviceID: self.reader.currentDeviceID(),
            unmerge: true)
        self.providerLinkages.append(inverse)
        Self.saveCachedLinkages(self.providerLinkages)
        self.republishFromCache()
        _ = await self.reader.saveProviderAccountLinkage(inverse)
    }

    // MARK: - Device lifecycle management (issue #29)

    func mergeDevice(
        sourceDeviceID: String,
        into targetDeviceID: String) async
    {
        guard sourceDeviceID != targetDeviceID else { return }
        let event = DeviceLifecycleEvent(
            kind: .alias,
            primaryDeviceID: targetDeviceID,
            relatedDeviceIDs: [sourceDeviceID],
            confirmedFromDeviceID: self.reader.currentDeviceID())
        self.deviceLifecycleEvents.append(event)
        Self.saveCachedDeviceLifecycleEvents(self.deviceLifecycleEvents)
        self.republishFromCache()
        _ = await self.reader.saveDeviceLifecycleEvent(event)
    }

    func unmergeDevice(sourceDeviceIDs: [String]) async {
        let ids = Array(Set(sourceDeviceIDs)).sorted()
        guard ids.count >= 2 else { return }
        let event = DeviceLifecycleEvent(
            kind: .unalias,
            primaryDeviceID: ids[0],
            relatedDeviceIDs: Array(ids.dropFirst()),
            confirmedFromDeviceID: self.reader.currentDeviceID())
        self.deviceLifecycleEvents.append(event)
        Self.saveCachedDeviceLifecycleEvents(self.deviceLifecycleEvents)
        self.republishFromCache()
        _ = await self.reader.saveDeviceLifecycleEvent(event)
    }

    func archiveDevice(_ deviceID: String) async {
        await self.archiveDevices([deviceID])
    }

    func archiveDevices(_ deviceIDs: [String]) async {
        await self.applyDeviceLifecycleEvents(.archive, deviceIDs: deviceIDs)
    }

    func restoreDevice(_ deviceID: String) async {
        await self.restoreDevices([deviceID])
    }

    func restoreDevices(_ deviceIDs: [String]) async {
        await self.applyDeviceLifecycleEvents(.unarchive, deviceIDs: deviceIDs)
    }

    private func applyDeviceLifecycleEvents(
        _ kind: DeviceLifecycleEvent.Kind,
        deviceIDs: [String]) async
    {
        let ids = Array(Set(deviceIDs.filter { !$0.isEmpty })).sorted()
        guard !ids.isEmpty else { return }
        let confirmedFromDeviceID = self.reader.currentDeviceID()
        let events = ids.map {
            DeviceLifecycleEvent(
                kind: kind,
                primaryDeviceID: $0,
                confirmedFromDeviceID: confirmedFromDeviceID)
        }
        self.deviceLifecycleEvents.append(contentsOf: events)
        Self.saveCachedDeviceLifecycleEvents(self.deviceLifecycleEvents)
        self.republishFromCache()
        for event in events {
            _ = await self.reader.saveDeviceLifecycleEvent(event)
        }
    }

    // MARK: - Incremental fetch (silent push → cache update)

    /// Apply a change-token delta for `DeviceProvidersZone` to the cache,
    /// then republish. Fired from the silent-push observer. Legacy bucket
    /// is NEVER touched by this path.
    func refreshIncremental() async {
        await self.coalesceRefresh {
            await self.performIncrementalRefresh()
        }
    }

    private func performIncrementalRefresh() async {
        let zoneName = CloudSyncConstants.providerZoneName

        // 1. Load persisted token.
        let storedToken: CKServerChangeToken?
        do {
            if let data = try await CostHistoryWorker.shared.loadToken(zoneName: zoneName) {
                storedToken = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: CKServerChangeToken.self, from: data)
            } else {
                storedToken = nil
            }
        } catch {
            print("[CodexBar Sync v2] token unarchive failed: \(error)")
            storedToken = nil
        }

        // 2. Fetch delta.
        var delta = await reader.fetchPerProviderZoneChanges(since: storedToken)

        // 3. Handle token expiry: clear + retry once with nil. The server's
        //    nil-token reply replays every record currently in the zone, so
        //    we treat it as a FULL replacement of the per-provider bucket
        //    (equivalent to a full fetch of the new zone).
        var didReplayProviderZoneReplacement = false
        if delta.tokenExpired {
            try? await CostHistoryWorker.shared.resetToken(zoneName: zoneName)
            delta = await self.reader.fetchPerProviderZoneChanges(since: nil)
            if !delta.tokenExpired, !delta.zoneMissing {
                didReplayProviderZoneReplacement = true
            }
        } else if delta.zoneMissing {
            // No zone yet — nothing to apply. The priority merge will fall
            // through to the legacy bucket. This is normal before any Mac
            // has upgraded to P4.
        }

        async let linkagesResult = self.reader.fetchProviderAccountLinkages()
        async let lifecycleResult = self.reader.fetchDeviceLifecycleEvents()
        let mergedLinkages = await Self.mergeCloudWithLocalPending(
            cloud: linkagesResult,
            local: self.providerLinkages,
            recordID: \.recordID)
        self.providerLinkages = mergedLinkages.records
        Self.saveCachedLinkages(self.providerLinkages)
        let mergedLifecycleEvents = await Self.mergeCloudWithLocalPending(
            cloud: lifecycleResult,
            local: self.deviceLifecycleEvents,
            recordID: \.recordID)
        self.deviceLifecycleEvents = mergedLifecycleEvents.records
        Self.saveCachedDeviceLifecycleEvents(self.deviceLifecycleEvents)
        for pending in mergedLinkages.localOnly {
            Task { [weak self] in
                _ = await self?.reader.saveProviderAccountLinkage(pending)
            }
        }
        for pending in mergedLifecycleEvents.localOnly {
            Task { [weak self] in
                _ = await self?.reader.saveDeviceLifecycleEvent(pending)
            }
        }

        do {
            let tokenData = try delta.newToken.map {
                try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
            }
            // A KVS callback can publish while the worker persists. Rebase and
            // repeat if that happens; no newly received legacy data is discarded.
            var baseCache = self.cache
            while true {
                let revision = self.publicationRevision
                var nextCache = baseCache
                if didReplayProviderZoneReplacement {
                    nextCache.replacePerProviderFromReplay(delta.upserted)
                } else if !delta.zoneMissing, !delta.tokenExpired {
                    nextCache.applyDelta(upserted: delta.upserted, deletedRecordNames: delta.deletedRecordNames)
                }
                let rawSnapshots = nextCache.buildDeviceSnapshots()
                let snapshots = didReplayProviderZoneReplacement
                    ? rawSnapshots
                    : Self.snapshotsFilteringDeletedProvidersForIncrementalPersistence(
                        rawSnapshots, deletedRecordNames: delta.deletedRecordNames)
                try await CostHistoryWorker.shared.persistIncremental(
                    snapshots: snapshots,
                    deletedRecordNames: delta.deletedRecordNames,
                    replacingAllDevices: didReplayProviderZoneReplacement,
                    zoneName: zoneName,
                    tokenData: tokenData)
                let changedDuringSave = revision != self.publicationRevision
                baseCache = self.cache
                self.cache = nextCache
                self.republishFromCache()
                guard changedDuringSave else { break }
            }
        } catch {
            self.syncStatus = .error(message: String(localized:
                "Could not save synced data. Your previous data has been kept. Pull to refresh and try again."))
        }
    }

    // MARK: - Republish helper

    /// Derive the published state from the current cache. Called after every
    /// mutation (full fetch, incremental delta, cold-start seed).
    private func republishFromCache(
        persistToSwiftData context: ModelContext? = nil,
        persistIncrementallyToSwiftData incrementalContext: ModelContext? = nil,
        deletedRecordNames: [String] = [])
    {
        let rawDeviceSnapshots = self.cache.buildDeviceSnapshots()
        self.rawDeviceSnapshots = rawDeviceSnapshots
        let resolution = CloudSyncReader.resolveDeviceSnapshots(
            rawDeviceSnapshots,
            lifecycleEvents: self.deviceLifecycleEvents,
            providerLinkages: self.providerLinkages)
        self.deviceSnapshots = resolution.activeSnapshots
        self.deviceManagementItems = resolution.items

        let merged = CloudSyncReader.mergeSnapshots(
            resolution.activeSnapshots,
            linkages: self.providerLinkages)
        if let context {
            CloudSyncReader.persistToSwiftData(
                deviceSnapshots: rawDeviceSnapshots,
                merged: merged,
                context: context)
        }
        if let incrementalContext {
            CloudSyncReader.persistIncrementalCacheMirrorToSwiftData(
                cacheDeviceSnapshots: Self.snapshotsFilteringDeletedProvidersForIncrementalPersistence(
                    rawDeviceSnapshots,
                    deletedRecordNames: deletedRecordNames),
                deletedRecordNames: deletedRecordNames,
                context: incrementalContext)
        }

        if rawDeviceSnapshots.isEmpty {
            self.snapshot = nil
            self.deviceManagementItems = []
            if case .syncing = self.syncStatus {
                // don't clobber an in-flight syncing state
            } else {
                self.syncStatus = .noData
            }
            return
        }
        if let merged {
            self.snapshot = merged
            self.syncStatus = .synced(ago: Date().timeIntervalSince(merged.syncTimestamp))
        } else if resolution.activeSnapshots.isEmpty {
            self.snapshot = nil
            let latestRawSync = rawDeviceSnapshots.map(\.syncTimestamp).max() ?? Date()
            self.syncStatus = .synced(ago: Date().timeIntervalSince(latestRawSync))
        } else {
            self.syncStatus = .incompatibleData
        }
    }

    nonisolated static func snapshotsFilteringDeletedProvidersForIncrementalPersistence(
        _ snapshots: [SyncedUsageSnapshot],
        deletedRecordNames: [String]) -> [SyncedUsageSnapshot]
    {
        var deletedByDevice: [String: Set<String>] = [:]
        for recordName in deletedRecordNames {
            guard let parsed = Self.splitProviderRecordName(recordName) else { continue }
            deletedByDevice[parsed.deviceID, default: []].insert(parsed.composite)
        }
        guard !deletedByDevice.isEmpty else { return snapshots }

        return snapshots.map { snapshot in
            guard let deviceID = snapshot.deviceID,
                  let deletedComposites = deletedByDevice[deviceID],
                  !deletedComposites.isEmpty
            else {
                return snapshot
            }
            let providers = snapshot.providers.filter { provider in
                !deletedComposites.contains(Self.providerCompositeKey(provider))
            }
            guard providers.count != snapshot.providers.count else { return snapshot }
            let providerPublicationTimestamps = Dictionary(
                providers.map {
                    (SyncedUsageSnapshot.providerPublicationKey(for: $0), snapshot.publicationTimestamp(for: $0))
                },
                uniquingKeysWith: max)
            return SyncedUsageSnapshot(
                providers: providers,
                syncTimestamp: snapshot.syncTimestamp,
                deviceName: snapshot.deviceName,
                deviceID: snapshot.deviceID,
                appVersion: snapshot.appVersion,
                mobileVersion: snapshot.mobileVersion,
                notificationPushEnabled: snapshot.notificationPushEnabled,
                providerPublicationTimestamps: providerPublicationTimestamps,
                providerQuotaSources: snapshot.providerQuotaSources.filter {
                    providerPublicationTimestamps[$0.key] != nil
                })
        }
    }

    private nonisolated static func splitProviderRecordName(_ recordName: String) -> (
        deviceID: String,
        composite: String)?
    {
        let parts = recordName.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return (String(parts[0]), "\(parts[1])|\(parts[2])")
    }

    private nonisolated static func providerCompositeKey(_ provider: ProviderUsageSnapshot) -> String {
        "\(provider.providerID)|\(provider.accountRecordKey ?? provider.accountEmail ?? "_")"
    }

    // MARK: - Public API

    /// Force-refreshes data from CloudKit (full fetch).
    func refresh() async {
        await self.fetchFromCloudKit()
    }

    /// Returns the age of the last sync in a human-readable format, or nil if no sync exists.
    var syncAge: String? {
        guard let timestamp = snapshot?.syncTimestamp else { return nil }
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 {
            return String(localized: "Just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes.formatted()) \(String(localized: "min ago"))"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours.formatted())\(String(localized: "h ago"))"
        } else {
            let days = Int(interval / 86400)
            return "\(days.formatted())\(String(localized: "d ago"))"
        }
    }

    /// Names of all Mac devices contributing data.
    var deviceNames: [String] {
        self.deviceSnapshots.map(\.deviceName)
    }

    /// Stable identity for view-layer cache invalidation (Contract C3).
    /// Returns nil when there is no merged snapshot yet.
    var snapshotIdentityKey: SnapshotIdentityKey? {
        guard let snapshot else { return nil }
        let providers = snapshot.providers
        let latest = providers.map(\.lastUpdated).max() ?? snapshot.syncTimestamp
        return SnapshotIdentityKey.make(
            providerIDs: providers.map(\.providerID),
            lastUpdated: latest)
    }
}
