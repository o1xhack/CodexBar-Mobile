import WidgetKit
import SwiftUI

@main
struct CodexBarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CodexBarStatusWidget()
        CodexBarTokenActivitySingleWidget()
        CodexBarTokenActivityComparisonWidget()
    }
}

struct CodexBarTokenActivitySingleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetActivityKind.single,
            intent: WidgetActivitySingleIntent.self,
            provider: WidgetActivitySingleProvider()
        ) { entry in
            WidgetActivityView(entry: entry)
        }
        .configurationDisplayName("Token Activity")
        .description("See daily token activity for one source.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CodexBarTokenActivityComparisonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetActivityKind.comparison,
            intent: WidgetActivityComparisonIntent.self,
            provider: WidgetActivityComparisonProvider()
        ) { entry in
            WidgetActivityView(entry: entry)
        }
        .configurationDisplayName("Token Activity Comparison")
        .description("Compare daily token activity from two sources.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

struct CodexBarStatusWidget: Widget {
    private let kind = "CodexBarStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CodexBarWidgetConfigurationIntent.self,
            provider: CodexBarWidgetProvider()
        ) { entry in
            CodexBarWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Widget")
        .description("View synced provider usage, cost, and sync health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
