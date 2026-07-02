import CloudKit
import CodexBarSync
import Foundation
import SwiftData

struct SyncDeviceManagementItem: Identifiable {
    enum State {
        case active
        case mergedAlias
        case archived
    }

    let canonicalDeviceID: String
    let sourceDeviceIDs: [String]
    let snapshot: SyncedUsageSnapshot
    let state: State

    var id: String { self.canonicalDeviceID }
    var aliasCount: Int { max(0, self.sourceDeviceIDs.count - 1) }
    var isArchived: Bool {
        if case .archived = self.state { return true }
        return false
    }
    var isMergedAlias: Bool {
        if case .mergedAlias = self.state { return true }
        return false
    }
}

struct DeviceLifecycleResolution {
    let activeSnapshots: [SyncedUsageSnapshot]
    let archivedSnapshots: [SyncedUsageSnapshot]
    let items: [SyncDeviceManagementItem]

    var activeItems: [SyncDeviceManagementItem] {
        self.items.filter { !$0.isArchived }
    }

    var archivedItems: [SyncDeviceManagementItem] {
        self.items.filter(\.isArchived)
    }
}

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
        guard !snapshots.isEmpty else {
            return DeviceLifecycleResolution(
                activeSnapshots: [],
                archivedSnapshots: [],
                items: [])
        }

        var uf = StringUnionFind()
        for snapshot in snapshots {
            uf.add(Self.deviceKey(for: snapshot))
        }

        for edge in Self.activeAliasEdges(from: lifecycleEvents) {
            uf.add(edge.first)
            uf.add(edge.second)
            uf.union(edge.first, edge.second)
        }

        var grouped: [String: [SyncedUsageSnapshot]] = [:]
        for snapshot in snapshots {
            let key = Self.deviceKey(for: snapshot)
            let root = uf.find(key)
            grouped[root, default: []].append(snapshot)
        }

        let archiveState = Self.latestArchiveState(from: lifecycleEvents)
        var items: [SyncDeviceManagementItem] = []
        for (_, group) in grouped {
            let sourceIDs = group
                .map(Self.deviceKey(for:))
                .sorted()
            let newest = group.max(by: { $0.syncTimestamp < $1.syncTimestamp })!
            let canonicalID = Self.deviceKey(for: newest)
            let collapsed = Self.collapsePhysicalDeviceGroup(
                group,
                canonicalDeviceID: canonicalID,
                providerLinkages: providerLinkages)
            let archived = Self.isGroupArchived(
                sourceDeviceIDs: sourceIDs,
                canonicalDeviceID: canonicalID,
                archiveState: archiveState)
            let state: SyncDeviceManagementItem.State = archived
                ? .archived
                : (sourceIDs.count > 1 ? .mergedAlias : .active)
            items.append(SyncDeviceManagementItem(
                canonicalDeviceID: canonicalID,
                sourceDeviceIDs: sourceIDs,
                snapshot: collapsed,
                state: state))
        }

        items.sort {
            if $0.isArchived != $1.isArchived {
                return !$0.isArchived
            }
            return $0.snapshot.syncTimestamp > $1.snapshot.syncTimestamp
        }

        let active = items.filter { !$0.isArchived }.map(\.snapshot)
        let archived = items.filter(\.isArchived).map(\.snapshot)
        return DeviceLifecycleResolution(
            activeSnapshots: active,
            archivedSnapshots: archived,
            items: items)
    }

    static func deviceKey(for snapshot: SyncedUsageSnapshot) -> String {
        snapshot.deviceID ?? SnapshotCache.syntheticDeviceID(from: snapshot)
    }

    private static func collapsePhysicalDeviceGroup(
        _ snapshots: [SyncedUsageSnapshot],
        canonicalDeviceID: String,
        providerLinkages: [ProviderAccountLinkage]
    ) -> SyncedUsageSnapshot {
        guard snapshots.count > 1,
              let merged = Self.mergeSnapshots(
                  snapshots,
                  linkages: providerLinkages,
                  sumLocalCostsAcrossDevices: false)
        else {
            return snapshots[0]
        }
        let newest = snapshots.max(by: { $0.syncTimestamp < $1.syncTimestamp })!
        return SyncedUsageSnapshot(
            providers: merged.providers,
            syncTimestamp: merged.syncTimestamp,
            deviceName: newest.deviceName,
            deviceID: canonicalDeviceID,
            appVersion: merged.appVersion,
            mobileVersion: merged.mobileVersion,
            notificationPushEnabled: merged.notificationPushEnabled)
    }

    private struct AliasEdge: Hashable {
        let first: String
        let second: String
        let deviceIDs: Set<String>

        init?(_ lhs: String, _ rhs: String) {
            guard !lhs.isEmpty, !rhs.isEmpty, lhs != rhs else { return nil }
            let sorted = [lhs, rhs].sorted()
            self.first = sorted[0]
            self.second = sorted[1]
            self.deviceIDs = Set(sorted)
        }
    }

    private static func activeAliasEdges(
        from events: [DeviceLifecycleEvent]
    ) -> Set<AliasEdge> {
        var edges = Set<AliasEdge>()
        for event in events.sorted(by: Self.lifecycleEventSort) {
            let deviceIDs = Self.normalizedDeviceIDs(for: event)
            guard deviceIDs.count >= 2 else { continue }

            switch event.kind {
            case .alias:
                let primary = deviceIDs[0]
                for related in deviceIDs.dropFirst() {
                    if let edge = AliasEdge(primary, related) {
                        edges.insert(edge)
                    }
                }
            case .unalias:
                let unaliasSet = Set(deviceIDs)
                edges = edges.filter { !$0.deviceIDs.isSubset(of: unaliasSet) }
            case .archive, .unarchive:
                continue
            }
        }
        return edges
    }

    private static func normalizedDeviceIDs(
        for event: DeviceLifecycleEvent
    ) -> [String] {
        ([event.primaryDeviceID] + event.relatedDeviceIDs)
            .filter { !$0.isEmpty }
    }

    private static func latestArchiveState(
        from events: [DeviceLifecycleEvent]
    ) -> [String: Bool] {
        var state: [String: Bool] = [:]
        for event in events.sorted(by: Self.lifecycleEventSort) {
            switch event.kind {
            case .archive:
                state[event.primaryDeviceID] = true
            case .unarchive:
                state[event.primaryDeviceID] = false
            case .alias, .unalias:
                continue
            }
        }
        return state
    }

    private static func lifecycleEventSort(
        _ lhs: DeviceLifecycleEvent,
        _ rhs: DeviceLifecycleEvent
    ) -> Bool {
        if lhs.confirmedAt == rhs.confirmedAt {
            return lhs.recordID < rhs.recordID
        }
        return lhs.confirmedAt < rhs.confirmedAt
    }

    private static func isGroupArchived(
        sourceDeviceIDs: [String],
        canonicalDeviceID: String,
        archiveState: [String: Bool]
    ) -> Bool {
        if sourceDeviceIDs.count > 1,
           sourceDeviceIDs.contains(where: { archiveState[$0] == true })
        {
            return true
        }
        if let canonicalArchived = archiveState[canonicalDeviceID] {
            return canonicalArchived
        }
        let explicitStates = sourceDeviceIDs.compactMap { archiveState[$0] }
        guard explicitStates.count == sourceDeviceIDs.count,
              !explicitStates.isEmpty
        else {
            return false
        }
        return explicitStates.allSatisfy { $0 }
    }
}

private struct StringUnionFind {
    private var parent: [String: String] = [:]

    mutating func add(_ x: String) {
        if self.parent[x] == nil {
            self.parent[x] = x
        }
    }

    mutating func find(_ x: String) -> String {
        self.add(x)
        let current = self.parent[x] ?? x
        if current != x {
            let root = self.find(current)
            self.parent[x] = root
            return root
        }
        return x
    }

    mutating func union(_ a: String, _ b: String) {
        let ra = self.find(a)
        let rb = self.find(b)
        if ra != rb {
            self.parent[ra] = rb
        }
    }
}
