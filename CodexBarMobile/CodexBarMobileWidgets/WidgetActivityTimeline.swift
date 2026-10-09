import AppIntents
import Foundation
import Intents
import OSLog
import WidgetKit

private let widgetActivityLogger = Logger(subsystem: "com.o1xhack.codexbar.mobile.widgets", category: "activity")

enum WidgetActivityTimeline {
    static func sourceID(_ choice: TokenActivitySource) -> String {
        switch choice {
        case .claude: "claude"
        case .codex: "codex"
        default: WidgetActivityProjection.allSourceID
        }
    }

    static func entry(sourceIDs: [String], preview: Bool) -> WidgetActivityEntry {
        let now = Date()
        let projection: WidgetActivityProjection
        if preview {
            projection = .preview(now: now)
        } else {
            do {
                projection = try WidgetActivityStore.read() ?? .state(.syncing, now: now)
            } catch {
                projection = .state(.error, now: now)
            }
        }
        return WidgetActivityEntry(date: now, sourceIDs: sourceIDs, projection: projection)
    }

    static func timeline(sourceIDs: [String]) -> Timeline<WidgetActivityEntry> {
        let entry = Self.entry(sourceIDs: sourceIDs, preview: false)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60)))
    }
}

struct WidgetActivitySingleProvider: IntentTimelineProvider {
    func placeholder(in _: Context) -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(sourceIDs: [WidgetActivityProjection.allSourceID], preview: true)
    }

    func getSnapshot(for configuration: SelectTokenActivityIntent, in context: Context, completion: @escaping (WidgetActivityEntry) -> Void) {
        #if DEBUG
        widgetActivityLogger.notice(
            "sirikit single snapshot source: \(configuration.source.rawValue, privacy: .public)")
        #endif
        completion(WidgetActivityTimeline.entry(
            sourceIDs: [WidgetActivityTimeline.sourceID(configuration.source)],
            preview: context.isPreview))
    }

    func getTimeline(for configuration: SelectTokenActivityIntent, in _: Context, completion: @escaping (Timeline<WidgetActivityEntry>) -> Void) {
        #if DEBUG
        widgetActivityLogger.notice(
            "sirikit single timeline source: \(configuration.source.rawValue, privacy: .public)")
        #endif
        completion(WidgetActivityTimeline.timeline(sourceIDs: [WidgetActivityTimeline.sourceID(configuration.source)]))
    }
}

struct WidgetActivityComparisonProvider: IntentTimelineProvider {
    func placeholder(in _: Context) -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(sourceIDs: [WidgetActivityProjection.allSourceID, "claude"], preview: true)
    }

    func getSnapshot(for configuration: CompareTokenActivityIntent, in context: Context, completion: @escaping (WidgetActivityEntry) -> Void) {
        completion(WidgetActivityTimeline.entry(
            sourceIDs: [
                WidgetActivityTimeline.sourceID(configuration.firstSource),
                WidgetActivityTimeline.sourceID(configuration.secondSource),
            ],
            preview: context.isPreview))
    }

    func getTimeline(for configuration: CompareTokenActivityIntent, in _: Context, completion: @escaping (Timeline<WidgetActivityEntry>) -> Void) {
        #if DEBUG
        let sources = [configuration.firstSource, configuration.secondSource].map { "\($0.rawValue)" }
        widgetActivityLogger.notice(
            "sirikit comparison timeline sources: \(sources.joined(separator: ","), privacy: .public)")
        #endif
        completion(WidgetActivityTimeline.timeline(sourceIDs: [
            WidgetActivityTimeline.sourceID(configuration.firstSource),
            WidgetActivityTimeline.sourceID(configuration.secondSource),
        ]))
    }
}

// MARK: - App Intents (iOS 27 and later, Research/072)

@available(iOS 27.0, *)
struct WidgetActivitySingleAppIntentProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(sourceIDs: [WidgetActivityProjection.allSourceID], preview: true)
    }

    func snapshot(for configuration: TokenActivityWidgetAppIntent, in context: Context) async -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(sourceIDs: [configuration.source.sourceID], preview: context.isPreview)
    }

    func timeline(
        for configuration: TokenActivityWidgetAppIntent,
        in _: Context) async -> Timeline<WidgetActivityEntry>
    {
        #if DEBUG
        widgetActivityLogger.notice(
            "appintent single timeline source: \(configuration.source.rawValue, privacy: .public)")
        #endif
        return WidgetActivityTimeline.timeline(sourceIDs: [configuration.source.sourceID])
    }
}

@available(iOS 27.0, *)
struct WidgetActivityComparisonAppIntentProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(sourceIDs: [WidgetActivityProjection.allSourceID, "claude"], preview: true)
    }

    func snapshot(
        for configuration: TokenActivityComparisonAppIntent,
        in context: Context) async -> WidgetActivityEntry
    {
        WidgetActivityTimeline.entry(sourceIDs: configuration.sourceIDs, preview: context.isPreview)
    }

    func timeline(
        for configuration: TokenActivityComparisonAppIntent,
        in _: Context) async -> Timeline<WidgetActivityEntry>
    {
        #if DEBUG
        let sources = configuration.sourceIDs.joined(separator: ",")
        widgetActivityLogger.notice("appintent comparison timeline sources: \(sources, privacy: .public)")
        #endif
        return WidgetActivityTimeline.timeline(sourceIDs: configuration.sourceIDs)
    }
}
