import CloudKit
import CodexBarSync
import Foundation
import SwiftData

/// iOS-side reader that fetches usage snapshots from CloudKit (all devices)
/// and falls back to legacy KVS for older Mac app versions.
final class CloudSyncReader: @unchecked Sendable {
    private let syncManager: CloudSyncManager

    init(syncManager: CloudSyncManager = .shared) {
        self.syncManager = syncManager
    }

    // MARK: - CloudKit (primary)

    /// Fetches snapshots from all devices via CloudKit.
    func fetchAllDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchAllDeviceSnapshots()
    }

    // MARK: - Cache-based flow (v2 — Research/011)

    /// Per-provider zone only. Caller owns the priority-merge decision.
    func fetchPerProviderDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchPerProviderDeviceSnapshots()
    }

    /// Legacy zones only (custom zone + default zone).
    func fetchLegacyDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchLegacyDeviceSnapshots()
    }

    /// Incremental change-token fetch for the per-provider zone.
    func fetchPerProviderZoneChanges(
        since token: CKServerChangeToken?
    ) async -> CloudSyncManager.PerProviderZoneChanges {
        await syncManager.fetchPerProviderZoneChanges(since: token)
    }

    // MARK: - Account linkage (Research/019 §7)

    /// Fetch all `ProviderAccountLinkage` records from CloudKit. Returns
    /// empty when the zone or record type doesn't exist yet (= no user
    /// has confirmed a merge on this iCloud account).
    func fetchProviderAccountLinkages() async -> [ProviderAccountLinkage] {
        await syncManager.fetchProviderAccountLinkages()
    }

    /// Fetch all `DeviceLifecycleEvent` records from CloudKit. Returns empty
    /// when no lifecycle record has been written yet or Production schema is
    /// not deployed.
    func fetchDeviceLifecycleEvents() async -> [DeviceLifecycleEvent] {
        await syncManager.fetchDeviceLifecycleEvents()
    }

    /// Save a user-confirmed merge or unmerge to CloudKit.
    @discardableResult
    func saveProviderAccountLinkage(
        _ linkage: ProviderAccountLinkage
    ) async -> SyncPushResult {
        await syncManager.saveProviderAccountLinkage(linkage)
    }

    /// Save a user-confirmed device lifecycle event to CloudKit.
    @discardableResult
    func saveDeviceLifecycleEvent(
        _ event: DeviceLifecycleEvent
    ) async -> SyncPushResult {
        await syncManager.saveDeviceLifecycleEvent(event)
    }

    /// Stable iPhone UUID for stamping LinkageRecord `confirmedFromDeviceID`.
    func currentDeviceID() -> String {
        syncManager.stableDeviceID()
    }

    // MARK: - Legacy KVS (backward compatibility)

    /// Returns the most recently synced snapshot from KVS (fallback).
    func latestKVSSnapshot() -> SyncedUsageSnapshot? {
        syncManager.fetchKVSSnapshot()
    }

    /// Starts observing KVS changes (backward compat with older Mac apps).
    func startKVSObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        syncManager.startKVSObserving(handler: handler)
    }

    @discardableResult
    func synchronizeKVS() -> Bool {
        syncManager.synchronizeKVSStore()
    }

    func stopKVSObserving() {
        syncManager.stopKVSObserving()
    }

    // MARK: - Deprecated shims (keep callers compiling during transition)

    func latestSnapshot() -> SyncedUsageSnapshot? {
        syncManager.fetchKVSSnapshot()
    }

    func startObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        syncManager.startKVSObserving(handler: handler)
    }

    @discardableResult
    func synchronize() -> Bool {
        syncManager.synchronizeKVSStore()
    }

    func stopObserving() {
        syncManager.stopKVSObserving()
    }

    // MARK: - SwiftData parallel write (P2a)

    /// Mirrors the raw per-device CloudKit snapshots into the SwiftData store.
    ///
    /// P2a is additive: the old `@Observable` path continues to drive views.
    /// This method exists so `SyncedUsageData` can call it right after
    /// `mergeSnapshots(...)` completes, keeping the two sources in lockstep.
    ///
    /// Writes ONLY per-device rows. The merged snapshot is not persisted —
    /// P2b's @Query-based views will re-derive the merged view on the fly
    /// from per-device rows, so storing a separate merged row would be
    /// redundant duplication. Codex review (P2) also flagged that the
    /// synthetic "legacy:<deviceName>" key for merged snapshots shifts
    /// whenever the set of contributing devices changes, which would
    /// orphan prior merged rows. Per-device rows are keyed by stable
    /// deviceID, so they accumulate cleanly.
    static func persistToSwiftData(
        deviceSnapshots: [SyncedUsageSnapshot],
        merged _: SyncedUsageSnapshot?,
        context: ModelContext
    ) {
        do {
            try SwiftDataBridge.upsert(deviceSnapshots: deviceSnapshots, into: context)
        } catch {
            // P2a is parallel-write; failures here must never break the
            // legacy path. Log and move on.
            print("[CodexBar SwiftData] Parallel-write upsert failed: \(error)")
        }
    }

    static func persistIncrementalCacheMirrorToSwiftData(
        cacheDeviceSnapshots: [SyncedUsageSnapshot],
        deletedRecordNames: [String] = [],
        context: ModelContext
    ) {
        do {
            try SwiftDataBridge.upsertIncrementalCacheMirror(
                cacheDeviceSnapshots: cacheDeviceSnapshots,
                deletedRecordNames: deletedRecordNames,
                into: context)
        } catch {
            print("[CodexBar SwiftData] Incremental upsert failed: \(error)")
        }
    }

    // MARK: - Multi-device merge

    static func mergeSnapshots(
        _ snapshots: [SyncedUsageSnapshot],
        linkages: [ProviderAccountLinkage] = [],
        sumLocalCostsAcrossDevices: Bool = true
    ) -> SyncedUsageSnapshot? {
        ProviderSnapshotMerger.mergeSnapshots(
            snapshots,
            linkages: linkages,
            sumLocalCostsAcrossDevices: sumLocalCostsAcrossDevices,
            providerFilter: MockProviderDetector.filteredProviders(from:))
    }

    static func effectiveIdentifiers(for provider: ProviderUsageSnapshot) -> [String] {
        ProviderSnapshotMerger.effectiveIdentifiers(for: provider)
    }

    static func semverLessThan(_ lhs: String, _ rhs: String) -> Bool {
        ProviderSnapshotMerger.semverLessThan(lhs, rhs)
    }

    static func partitionLinkages(
        _ linkages: [ProviderAccountLinkage]
    ) -> (merges: [ProviderAccountLinkage], unmerges: [ProviderAccountLinkage]) {
        ProviderSnapshotMerger.partitionLinkages(linkages)
    }

    static func suppressedEdges(
        unmergeLinkages: [ProviderAccountLinkage]
    ) -> Set<String> {
        ProviderSnapshotMerger.suppressedEdges(unmergeLinkages: unmergeLinkages)
    }

    static func isLinkageSuppressed(
        _ linkage: ProviderAccountLinkage,
        by suppressedKeys: Set<String>
    ) -> Bool {
        ProviderSnapshotMerger.isLinkageSuppressed(linkage, by: suppressedKeys)
    }

    static func indices(
        forProviderID providerID: String,
        in allProviders: [ProviderUsageSnapshot]
    ) -> [Int] {
        ProviderSnapshotMerger.indices(forProviderID: providerID, in: allProviders)
    }

    // MARK: - Device lifecycle reducer (issue #29)

    static func resolveDeviceSnapshots(
        _ snapshots: [SyncedUsageSnapshot],
        lifecycleEvents: [DeviceLifecycleEvent],
        providerLinkages: [ProviderAccountLinkage] = []
    ) -> DeviceLifecycleResolution {
        DeviceSnapshotResolver.resolveDeviceSnapshots(
            snapshots,
            lifecycleEvents: lifecycleEvents,
            providerLinkages: providerLinkages,
            providerFilter: MockProviderDetector.filteredProviders(from:))
    }

    static func deviceKey(for snapshot: SyncedUsageSnapshot) -> String {
        DeviceSnapshotResolver.deviceKey(for: snapshot)
    }
}
