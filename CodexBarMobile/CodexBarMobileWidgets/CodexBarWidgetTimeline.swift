import CodexBarSync
import Foundation
import WidgetKit

struct CodexBarWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: CodexBarWidgetConfigurationIntent
    let snapshot: CodexBarWidgetSnapshot
}

struct CodexBarWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(
            date: .now,
            configuration: CodexBarWidgetConfigurationIntent(mode: .overview),
            snapshot: .placeholder())
    }

    func snapshot(
        for configuration: CodexBarWidgetConfigurationIntent,
        in context: Context
    ) async -> CodexBarWidgetEntry {
        if context.isPreview {
            return CodexBarWidgetEntry(
                date: .now,
                configuration: configuration,
                snapshot: .placeholder())
        }
        return CodexBarWidgetEntry(
            date: .now,
            configuration: configuration,
            snapshot: .syncing())
    }

    func timeline(
        for configuration: CodexBarWidgetConfigurationIntent,
        in _: Context
    ) async -> Timeline<CodexBarWidgetEntry> {
        let now = Date()
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["CODEXBAR_WIDGET_DISABLE_SIMULATOR_MOCK"] != "1" {
            let entry = CodexBarWidgetEntry(
                date: now,
                configuration: configuration,
                snapshot: .simulatorMock(now: now))
            return Timeline(
                entries: [entry],
                policy: .after(now.addingTimeInterval(15 * 60)))
        }
        #endif
        let result = await CloudSyncManager.shared.fetchAllDeviceSnapshots()
        let fallback = CloudSyncManager.shared.fetchKVSSnapshot()
        let snapshot = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: result,
            fallbackKVSSnapshot: fallback,
            now: now)
        let entry = CodexBarWidgetEntry(
            date: now,
            configuration: configuration,
            snapshot: snapshot)
        let refreshInterval: TimeInterval = switch snapshot.state {
        case .loaded: 15 * 60
        case .placeholder, .syncing: 5 * 60
        case .noData, .error: 10 * 60
        }
        return Timeline(
            entries: [entry],
            policy: .after(now.addingTimeInterval(refreshInterval)))
    }
}
