import AppIntents
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
        // Research/072: from iOS 27 the gallery offers App Intents versions
        // under new kinds; placed SiriKit widgets keep working.
        if #available(iOS 27.0, *) {
            CodexBarTokenActivitySingleAppIntentWidget()
        }
        if #available(iOS 27.0, *) {
            CodexBarTokenActivityComparisonAppIntentWidget()
        }
        if #available(iOS 27.0, *) {
            CodexBarStatusAppIntentWidget()
        }
        if #available(iOS 27.0, *) {
            CodexBarQuotaPaceAppIntentWidget()
        }
    }
}

/// Where the SiriKit widgets are hidden from the gallery: nowhere before
/// iOS 27, and every location from iOS 27, where their App Intents versions
/// take their place (Research/072). Placed widgets are not affected.
enum SiriKitWidgetGallery {
    static var disfavoredLocations: [WidgetLocation] {
        guard #available(iOS 27.0, *) else { return [] }
        return [.homeScreen, .lockScreen, .standBy, .iPhoneWidgetsOnMac, .carPlay]
    }
}

// MARK: - SiriKit widgets (every system)

struct CodexBarTokenActivitySingleWidget: Widget {
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium]

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
        .supportedFamilies(Self.families)
        .disfavoredLocations(SiriKitWidgetGallery.disfavoredLocations, for: Self.families)
        .contentMarginsDisabled()
    }
}

struct CodexBarTokenActivityComparisonWidget: Widget {
    private static let families: [WidgetFamily] = [.systemLarge, .systemExtraLarge]

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
        .supportedFamilies(Self.families)
        .disfavoredLocations(SiriKitWidgetGallery.disfavoredLocations, for: Self.families)
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
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: WidgetKinds.status,
            intent: SelectStatusWidgetIntent.self,
            provider: CodexBarStatusTimelineProvider())
        { entry in
            CodexBarWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Widget")
        .description("View synced provider usage, cost, and sync health.")
        .supportedFamilies(Self.families)
        .disfavoredLocations(SiriKitWidgetGallery.disfavoredLocations, for: Self.families)
        .contentMarginsDisabled()
    }
}

struct CodexBarQuotaPaceWidget: Widget {
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: WidgetKinds.quotaPace,
            intent: SelectQuotaPaceWidgetIntent.self,
            provider: QuotaPaceTimelineProvider())
        { entry in
            CodexBarWidgetView(entry: entry)
        }
        .configurationDisplayName("Quota pace")
        .description("See whether a provider's quota lasts until it resets.")
        .supportedFamilies(Self.families)
        .disfavoredLocations(SiriKitWidgetGallery.disfavoredLocations, for: Self.families)
        .contentMarginsDisabled()
    }
}

// MARK: - App Intents widgets (iOS 27 and later, Research/072)

@available(iOS 27.0, *)
struct CodexBarTokenActivitySingleAppIntentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetActivityKind.singleAppIntent,
            intent: TokenActivityWidgetAppIntent.self,
            provider: WidgetActivitySingleAppIntentProvider())
        { entry in
            WidgetActivityView(entry: entry)
        }
        .configurationDisplayName("Token Activity")
        // The App Intents editor shows the source as a pop-up menu.
        .description("Choose the token history to show.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@available(iOS 27.0, *)
struct CodexBarTokenActivityComparisonAppIntentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetActivityKind.comparisonAppIntent,
            intent: TokenActivityComparisonAppIntent.self,
            provider: WidgetActivityComparisonAppIntentProvider())
        { entry in
            WidgetActivityView(entry: entry)
        }
        .configurationDisplayName("Token Activity Comparison")
        .description("Compare daily token activity from two sources.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

@available(iOS 27.0, *)
struct CodexBarStatusAppIntentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKinds.statusAppIntent,
            intent: StatusWidgetAppIntent.self,
            provider: StatusAppIntentTimelineProvider())
        { entry in
            CodexBarWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Widget")
        .description("View synced provider usage, cost, and sync health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

@available(iOS 27.0, *)
struct CodexBarQuotaPaceAppIntentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKinds.quotaPaceAppIntent,
            intent: QuotaPaceWidgetAppIntent.self,
            provider: QuotaPaceAppIntentTimelineProvider())
        { entry in
            CodexBarWidgetView(entry: entry)
        }
        .configurationDisplayName("Quota pace")
        .description("See whether a provider's quota lasts until it resets.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
