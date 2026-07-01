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

enum CodexBarWidgetColorStyle: String, AppEnum, CaseIterable {
    case mono
    case colorful

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Color Style"

    static let caseDisplayRepresentations: [CodexBarWidgetColorStyle: DisplayRepresentation] = [
        .mono: "Mono",
        .colorful: "Colorful",
    ]
}

struct CodexBarWidgetConfigurationIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "CodexBar Widget"
    static let description = IntentDescription("Choose which CodexBar sync summary this widget shows.")
    static let openAppWhenRun = false

    @Parameter(title: "Widget Type", default: .overview)
    var mode: CodexBarWidgetMode

    @Parameter(title: "Color Style", default: .mono)
    var colorStyle: CodexBarWidgetColorStyle

    init() {}

    init(mode: CodexBarWidgetMode, colorStyle: CodexBarWidgetColorStyle = .mono) {
        self.mode = mode
        self.colorStyle = colorStyle
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
