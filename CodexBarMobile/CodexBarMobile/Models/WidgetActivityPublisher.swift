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
        if let snapshot {
            do {
                let providers = MockProviderDetector.filteredProviders(from: snapshot)
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
            projection = state == .error
                ? Self.statePreservingHistory(
                    state,
                    previous: try? WidgetActivityStore.read(),
                    latestSyncAt: nil,
                    now: referenceDate)
                : Self.state(state, latestSyncAt: nil, now: referenceDate)
        }

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
        return WidgetActivityProjection(
            version: WidgetActivityProjection.schemaVersion,
            state: state,
            generatedAt: now,
            latestSyncAt: previous?.latestSyncAt ?? latestSyncAt,
            sources: previous?.sources ?? [])
    }
}
