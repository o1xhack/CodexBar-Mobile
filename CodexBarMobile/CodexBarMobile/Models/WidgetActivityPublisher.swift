import CodexBarSync
import Foundation
import WidgetKit

/// Publishes the same resolved history the app uses, after its normal refresh.
/// A failed refresh is explicit and never converted into a zero-activity day.
@MainActor
enum WidgetActivityPublisher {
    static func refresh(
        snapshot: SyncedUsageSnapshot?,
        sourceSnapshots: [SyncedUsageSnapshot],
        syncStatus: SyncStatus,
        useLedger: Bool,
        referenceDate: Date)
    async {
        let projection: WidgetActivityProjection
        if let catalogue = Self.catalogueUpdate(snapshot: snapshot, syncStatus: syncStatus) {
            try? WidgetProviderCatalogue.write(catalogue)
        }
        if let snapshot {
            let providers = MockProviderDetector.filteredProviders(from: snapshot)
            // Make the current synced days available before the longer ledger
            // read. SwiftUI can cancel this task during a sync publication;
            // without this first write a newly installed widget has no file.
            if (try? WidgetActivityStore.read())?.sources.isEmpty != false {
                let currentSeries = TokenActivity.series(
                    providers: providers,
                    rollups: nil,
                    referenceDate: referenceDate)
                let current = WidgetActivityProjectionBuilder.make(
                    series: currentSeries,
                    latestSyncAt: snapshot.syncTimestamp,
                    now: referenceDate)
                if !current.sources.isEmpty {
                    Self.publish(current)
                }
            }
            do {
                let series: [TokenActivitySeries] = if useLedger {
                    try await CostHistoryWorker.shared.tokenActivity(
                        providers: providers,
                        sourceSnapshots: sourceSnapshots,
                        referenceDate: referenceDate)
                } else {
                    try await CostHistoryWorker.shared.snapshotTokenActivity(
                        providers: providers,
                        referenceDate: referenceDate)
                }
                guard !Task.isCancelled else { return }
                let resolved = WidgetActivityProjectionBuilder.make(
                    series: series,
                    latestSyncAt: snapshot.syncTimestamp,
                    now: referenceDate)
                let state: WidgetActivityState = switch syncStatus {
                case .syncing: .syncing
                case .error, .incompatibleData: .error
                case .synced, .noData: resolved.state
                }
                projection = WidgetActivityProjection(
                    version: resolved.version,
                    state: state,
                    generatedAt: resolved.generatedAt,
                    latestSyncAt: resolved.latestSyncAt,
                    sources: resolved.sources)
            } catch {
                guard !Task.isCancelled else { return }
                projection = Self.statePreservingHistory(
                    .error,
                    previous: try? WidgetActivityStore.read(),
                    latestSyncAt: snapshot.syncTimestamp,
                    now: referenceDate)
            }
        } else {
            let state: WidgetActivityState = switch syncStatus {
            case .syncing: .syncing
            case .error, .incompatibleData: .error
            case .synced, .noData: .noData
            }
            projection = state == .error || state == .syncing
                ? Self.statePreservingHistory(
                    state,
                    previous: try? WidgetActivityStore.read(),
                    latestSyncAt: nil,
                    now: referenceDate)
                : Self.state(state, latestSyncAt: nil, now: referenceDate)
        }

        Self.publish(projection)
    }

    static func catalogueEntities(
        from providers: [ProviderUsageSnapshot],
        now: Date = .now) -> [WidgetProviderRecord]
    {
        providers.filter { !$0.isProviderLevelCostEnvelope }.map {
            WidgetProviderRecord(
                id: $0.providerID,
                name: $0.providerName,
                windows: QuotaPaceWindowSelection.catalogueWindows(for: $0),
                defaultWindowID: QuotaPaceWindowSelection.defaultWindowID(for: $0, now: now))
        }
    }

    /// Empty authoritative results remove suggestions; transient failures keep
    /// the last successful catalogue available while data is being recovered.
    static func catalogueUpdate(
        snapshot: SyncedUsageSnapshot?,
        syncStatus: SyncStatus) -> [WidgetProviderRecord]?
    {
        if let snapshot {
            return self.catalogueEntities(from: MockProviderDetector.filteredProviders(from: snapshot))
        }
        switch syncStatus {
        case .noData, .synced: return []
        case .syncing, .error, .incompatibleData: return nil
        }
    }

    private static func publish(_ projection: WidgetActivityProjection) {
        do {
            try WidgetActivityStore.write(projection)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetActivityKind.single)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetActivityKind.comparison)
        } catch {
            print("[CodexBar Widget] Token Activity projection unavailable: \(error)")
        }
    }

    private static func state(
        _ state: WidgetActivityState,
        latestSyncAt: Date?,
        now: Date) -> WidgetActivityProjection
    {
        WidgetActivityProjection(
            version: WidgetActivityProjection.schemaVersion,
            state: state,
            generatedAt: now,
            latestSyncAt: latestSyncAt,
            sources: [])
    }

    static func statePreservingHistory(
        _ state: WidgetActivityState,
        previous: WidgetActivityProjection?,
        latestSyncAt: Date?,
        now: Date) -> WidgetActivityProjection
    {
        WidgetActivityProjection(
            version: WidgetActivityProjection.schemaVersion,
            state: state,
            generatedAt: now,
            latestSyncAt: previous?.latestSyncAt ?? latestSyncAt,
            sources: previous?.sources ?? [])
    }
}
