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
        widgetActivityLogger.notice("single snapshot source: \(String(describing: configuration.source), privacy: .public)")
        #endif
        completion(WidgetActivityTimeline.entry(
            sourceIDs: [WidgetActivityTimeline.sourceID(configuration.source)],
            preview: context.isPreview))
    }

    func getTimeline(for configuration: SelectTokenActivityIntent, in _: Context, completion: @escaping (Timeline<WidgetActivityEntry>) -> Void) {
        #if DEBUG
        widgetActivityLogger.notice("single timeline source: \(String(describing: configuration.source), privacy: .public)")
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
        completion(WidgetActivityTimeline.timeline(sourceIDs: [
            WidgetActivityTimeline.sourceID(configuration.firstSource),
            WidgetActivityTimeline.sourceID(configuration.secondSource),
        ]))
    }
}
