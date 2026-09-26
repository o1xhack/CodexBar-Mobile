import Foundation
import WidgetKit

enum WidgetActivityTimeline {
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

struct WidgetActivitySingleProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(sourceIDs: [WidgetActivitySourceEntity.all.id], preview: true)
    }

    func snapshot(for configuration: WidgetActivitySingleIntent, in context: Context) async -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(
            sourceIDs: [configuration.source?.id ?? WidgetActivityProjection.allSourceID],
            preview: context.isPreview)
    }

    func timeline(for configuration: WidgetActivitySingleIntent, in _: Context) async -> Timeline<WidgetActivityEntry> {
        WidgetActivityTimeline.timeline(sourceIDs: [configuration.source?.id ?? WidgetActivityProjection.allSourceID])
    }
}

struct WidgetActivityComparisonProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(sourceIDs: [WidgetActivitySourceEntity.all.id, "codex"], preview: true)
    }

    func snapshot(for configuration: WidgetActivityComparisonIntent, in context: Context) async -> WidgetActivityEntry {
        WidgetActivityTimeline.entry(
            sourceIDs: [
                configuration.firstSource?.id ?? WidgetActivityProjection.allSourceID,
                configuration.secondSource?.id ?? WidgetActivitySourceQuery.firstProvider()?.id ?? WidgetActivityProjection.allSourceID,
            ],
            preview: context.isPreview)
    }

    func timeline(for configuration: WidgetActivityComparisonIntent, in _: Context) async -> Timeline<WidgetActivityEntry> {
        WidgetActivityTimeline.timeline(sourceIDs: [
            configuration.firstSource?.id ?? WidgetActivityProjection.allSourceID,
            configuration.secondSource?.id ?? WidgetActivitySourceQuery.firstProvider()?.id ?? WidgetActivityProjection.allSourceID,
        ])
    }
}
