import CodexBarSync
import Foundation

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

enum DeviceSnapshotResolver {
    static func resolveDeviceSnapshots(
        _ snapshots: [SyncedUsageSnapshot],
        lifecycleEvents: [DeviceLifecycleEvent],
        providerLinkages: [ProviderAccountLinkage] = [],
        providerFilter: ProviderSnapshotMerger.ProviderFilter? = nil
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
                providerLinkages: providerLinkages,
                providerFilter: providerFilter)
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
        snapshot.deviceID ?? Self.syntheticDeviceID(from: snapshot)
    }

    private static func syntheticDeviceID(from snapshot: SyncedUsageSnapshot) -> String {
        "legacy:" + snapshot.deviceName
    }

    private static func collapsePhysicalDeviceGroup(
        _ snapshots: [SyncedUsageSnapshot],
        canonicalDeviceID: String,
        providerLinkages: [ProviderAccountLinkage],
        providerFilter: ProviderSnapshotMerger.ProviderFilter?
    ) -> SyncedUsageSnapshot {
        guard snapshots.count > 1,
              let merged = ProviderSnapshotMerger.mergeSnapshots(
                  snapshots,
                  linkages: providerLinkages,
                  sumLocalCostsAcrossDevices: false,
                  providerFilter: providerFilter)
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
            notificationPushEnabled: merged.notificationPushEnabled,
            providerPublicationTimestamps: merged.providerPublicationTimestamps)
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
