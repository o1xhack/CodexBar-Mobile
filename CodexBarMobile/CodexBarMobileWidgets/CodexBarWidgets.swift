import Intents
import SwiftUI
import WidgetKit

@main
struct CodexBarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CodexBarTokenActivitySingleWidget()
        CodexBarTokenActivityComparisonWidget()
        CodexBarStatusWidget()
        CodexBarQuotaPaceWidget()
        CodexBarLegacyStatusWidget()
    }
}

struct CodexBarTokenActivitySingleWidget: Widget {
    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: WidgetActivityKind.single,
            intent: SelectTokenActivityIntent.self,
            provider: WidgetActivitySingleProvider())
        { entry in
            WidgetActivityView(entry: entry)
        }
        .configurationDisplayName("Token Activity")
        .description("Tap the current source once, then choose All, Claude Code, or Codex.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct CodexBarTokenActivityComparisonWidget: Widget {
    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: WidgetActivityKind.comparison,
            intent: CompareTokenActivityIntent.self,
            provider: WidgetActivityComparisonProvider())
        { entry in
            WidgetActivityView(entry: entry)
        }
        .configurationDisplayName("Token Activity Comparison")
        .description("Compare daily token activity from two sources.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct CodexBarLegacyStatusWidget: Widget {
    private let kind = "CodexBarStatusWidget"

    private static var galleryLocations: [WidgetLocation] {
        var locations: [WidgetLocation] = [.homeScreen, .lockScreen, .standBy, .iPhoneWidgetsOnMac]
        if #available(iOS 26.0, *) {
            locations.append(.carPlay)
        }
        return locations
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: CodexBarWidgetConfigurationIntent.self,
            provider: CodexBarWidgetProvider())
        { _ in
            VStack {
                Text(String(localized: "Add this widget again"))
                Text(
                    String(
                        localized: "Remove this older widget, add CodexBar Widget again, and choose its settings."))
            }
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("CodexBar Widget (Legacy)")
        .description("View synced provider usage, cost, and sync health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        // Kept only so widgets placed before 2.4.0 explain how to re-add
        // themselves; hidden from the gallery so it is never picked anew.
        .disfavoredLocations(
            Self.galleryLocations,
            for: [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct CodexBarStatusWidget: Widget {
    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: "CodexBarStatusWidgetV2",
            intent: SelectStatusWidgetIntent.self,
            provider: CodexBarStatusTimelineProvider())
        { entry in
            CodexBarWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Widget")
        .description("View synced provider usage, cost, and sync health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct CodexBarQuotaPaceWidget: Widget {
    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: "CodexBarQuotaPaceWidget",
            intent: SelectQuotaPaceWidgetIntent.self,
            provider: QuotaPaceTimelineProvider())
        { entry in
            CodexBarWidgetView(entry: entry)
        }
        .configurationDisplayName("Quota pace")
        .description("See whether a provider's quota lasts until it resets.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
