import AppIntents
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
                sirikit status timeline mode=\(configuration.mode.rawValue, privacy: .public), \
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

struct QuotaPaceTimelineProvider: IntentTimelineProvider {
    func placeholder(in _: Context) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(date: .now, configuration: .init(mode: .quotaPace), snapshot: .placeholder())
    }

    func getSnapshot(
        for configuration: SelectQuotaPaceWidgetIntent,
        in context: Context,
        completion: @escaping @Sendable (CodexBarWidgetEntry) -> Void)
    {
        completion(CodexBarWidgetEntry(
            date: .now,
            configuration: StatusWidgetConfigurationAdapter.configuration(from: configuration),
            snapshot: context.isPreview ? .placeholder() : .syncing(),
            paceWindowChoice: StatusWidgetConfigurationAdapter.paceWindowChoice(from: configuration)))
    }

    func getTimeline(
        for intent: SelectQuotaPaceWidgetIntent,
        in _: Context,
        completion: @escaping @Sendable (Timeline<CodexBarWidgetEntry>) -> Void)
    {
        let configuration = StatusWidgetConfigurationAdapter.configuration(from: intent)
        let windowChoice = StatusWidgetConfigurationAdapter.paceWindowChoice(from: intent)
        #if DEBUG
        let providerIDs = (configuration.providers ?? []).map(\.id).joined(separator: ",")
        Logger(subsystem: "com.o1xhack.codexbar.mobile.widgets", category: "pace")
            .notice(
                """
                sirikit pace timeline style=\(configuration.colorStyle.rawValue, privacy: .public), \
                providerIDs=\(providerIDs, privacy: .public), \
                window=\(windowChoice ?? "default", privacy: .public)
                """)
        #endif
        // Convert INIntent before crossing isolation, as the status widget does.
        Task {
            await completion(CodexBarWidgetProvider.makeTimeline(
                configuration: configuration,
                paceWindowChoice: windowChoice))
        }
    }
}

// MARK: - App Intents (iOS 27 and later, Research/072)

private let appIntentTimelineLogger = Logger(subsystem: "com.o1xhack.codexbar.mobile.widgets", category: "appintent")

@available(iOS 27.0, *)
struct StatusAppIntentTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(date: .now, configuration: .init(mode: .overview), snapshot: .placeholder())
    }

    func snapshot(for intent: StatusWidgetAppIntent, in context: Context) async -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(
            date: .now,
            configuration: StatusWidgetConfigurationAdapter.configuration(from: intent),
            snapshot: context.isPreview ? .placeholder() : .syncing())
    }

    func timeline(for intent: StatusWidgetAppIntent, in _: Context) async -> Timeline<CodexBarWidgetEntry> {
        let configuration = StatusWidgetConfigurationAdapter.configuration(from: intent)
        #if DEBUG
        let providerIDs = (configuration.providers ?? []).map(\.id).joined(separator: ",")
        appIntentTimelineLogger.notice(
            """
            appintent status timeline mode=\(configuration.mode.rawValue, privacy: .public), \
            style=\(configuration.colorStyle.rawValue, privacy: .public), \
            providerIDs=\(providerIDs, privacy: .public)
            """)
        #endif
        return await CodexBarWidgetProvider.makeTimeline(configuration: configuration)
    }
}

@available(iOS 27.0, *)
struct QuotaPaceAppIntentTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(date: .now, configuration: .init(mode: .quotaPace), snapshot: .placeholder())
    }

    func snapshot(for intent: QuotaPaceWidgetAppIntent, in context: Context) async -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(
            date: .now,
            configuration: StatusWidgetConfigurationAdapter.configuration(from: intent),
            snapshot: context.isPreview ? .placeholder() : .syncing(),
            paceWindowChoice: StatusWidgetConfigurationAdapter.paceWindowChoice(from: intent))
    }

    func timeline(for intent: QuotaPaceWidgetAppIntent, in _: Context) async -> Timeline<CodexBarWidgetEntry> {
        let configuration = StatusWidgetConfigurationAdapter.configuration(from: intent)
        let windowChoice = StatusWidgetConfigurationAdapter.paceWindowChoice(from: intent)
        #if DEBUG
        let providerIDs = (configuration.providers ?? []).map(\.id).joined(separator: ",")
        appIntentTimelineLogger.notice(
            """
            appintent pace timeline style=\(configuration.colorStyle.rawValue, privacy: .public), \
            providerIDs=\(providerIDs, privacy: .public), \
            window=\(windowChoice ?? "default", privacy: .public)
            """)
        #endif
        return await CodexBarWidgetProvider.makeTimeline(
            configuration: configuration,
            paceWindowChoice: windowChoice)
    }
}
