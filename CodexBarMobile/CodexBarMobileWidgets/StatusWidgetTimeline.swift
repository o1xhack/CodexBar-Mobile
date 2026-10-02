import OSLog
import WidgetKit

struct CodexBarStatusTimelineProvider: IntentTimelineProvider {
    func placeholder(in _: Context) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(date: .now, configuration: .init(mode: .overview), snapshot: .placeholder())
    }

    func getSnapshot(
        for configuration: SelectStatusWidgetIntent,
        in context: Context,
        completion: @escaping @Sendable (CodexBarWidgetEntry) -> Void)
    {
        completion(CodexBarWidgetEntry(
            date: .now,
            configuration: StatusWidgetConfigurationAdapter.configuration(from: configuration),
            snapshot: context.isPreview ? .placeholder() : .syncing()))
    }

    func getTimeline(
        for intent: SelectStatusWidgetIntent,
        in _: Context,
        completion: @escaping @Sendable (Timeline<CodexBarWidgetEntry>) -> Void)
    {
        let configuration = StatusWidgetConfigurationAdapter.configuration(from: intent)
        #if DEBUG
        let providerIDs = (configuration.providers ?? []).map(\.id).joined(separator: ",")
        Logger(subsystem: "com.o1xhack.codexbar.mobile.widgets", category: "status")
            .notice(
                """
                mode=\(configuration.mode.rawValue, privacy: .public), \
                style=\(configuration.colorStyle.rawValue, privacy: .public), \
                providerIDs=\(providerIDs, privacy: .public)
                """)
        #endif
        // WidgetKit owns this one-shot callback request and provides no cancellation hook.
        // Convert INIntent before crossing isolation; fetches stay in the shared timeline path.
        Task {
            await completion(CodexBarWidgetProvider.makeTimeline(configuration: configuration))
        }
    }
}
