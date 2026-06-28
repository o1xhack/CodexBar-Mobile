import AppIntents
import WidgetKit

enum CodexBarWidgetMode: String, AppEnum {
    case overview
    case providerFocus
    case todayCost
    case syncHealth

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget Type"

    static let caseDisplayRepresentations: [CodexBarWidgetMode: DisplayRepresentation] = [
        .overview: "Overview",
        .providerFocus: "Provider Focus",
        .todayCost: "Today Cost",
        .syncHealth: "Sync Health",
    ]
}

struct CodexBarWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "CodexBar Widget"
    static let description = IntentDescription("Choose which CodexBar sync summary this widget shows.")

    @Parameter(title: "Widget Type", default: .overview)
    var mode: CodexBarWidgetMode

    init() {
        self.mode = .overview
    }

    init(mode: CodexBarWidgetMode) {
        self.mode = mode
    }
}
