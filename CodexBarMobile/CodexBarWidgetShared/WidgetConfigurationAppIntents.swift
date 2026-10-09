import AppIntents
import Foundation
import WidgetKit

// App Intents configuration for the iOS 27 widgets (Research/072). They are
// new widget kinds (`WidgetKinds`, `WidgetActivityKind`) next to the SiriKit
// widgets, which keep working on every system and stay the only ones in the
// gallery before iOS 27.
//
// Deliberately no `CustomIntentMigratedAppIntent`: iOS 26 looks up a migrated
// App Intent by SiriKit class name in the App Intents metadata and then edits
// the SiriKit widgets through it, which breaks them there (Research/072 §2).
// So no type here names a SiriKit intent class. The parameters still mirror
// the SiriKit ones so both widget generations configure the same way.
//
// Every type is available from iOS 27 only: an `AppIntentConfiguration` built
// with the iOS 27 SDK never receives its parameters on iOS 26 (FB23176939).

// MARK: - Kinds

/// Kinds of the CodexBar and Quota pace widgets. The SiriKit ones keep their
/// historical names; the App Intents ones (iOS 27 and later, Research/072) are
/// new so the system never migrates a SiriKit widget into them. Stable: a kind
/// change drops every placed widget.
enum WidgetKinds {
    static let status = "CodexBarStatusWidgetV2"
    static let quotaPace = "CodexBarQuotaPaceWidget"
    static let statusAppIntent = "CodexBarStatusWidgetAppIntent"
    static let quotaPaceAppIntent = "CodexBarQuotaPaceWidgetAppIntent"
}

// MARK: - Enums

/// The CodexBar widget's type: SiriKit `StatusWidgetMode` without its
/// `unknown` and retired `quotaPace` values.
@available(iOS 27.0, *)
enum StatusWidgetModeAppEnum: String, AppEnum {
    case overview
    case providerFocus
    case todayCost
    case syncHealth

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "Widget Type",
        table: "WidgetConfiguration"))

    static let caseDisplayRepresentations: [StatusWidgetModeAppEnum: DisplayRepresentation] = [
        .overview: DisplayRepresentation(title: LocalizedStringResource("Overview", table: "WidgetConfiguration")),
        .providerFocus: DisplayRepresentation(title: LocalizedStringResource(
            "Provider Focus",
            table: "WidgetConfiguration")),
        .todayCost: DisplayRepresentation(title: LocalizedStringResource("Today Cost", table: "WidgetConfiguration")),
        .syncHealth: DisplayRepresentation(title: LocalizedStringResource("Sync Health", table: "WidgetConfiguration")),
    ]
}

/// SiriKit `StatusWidgetColorStyle`, shared by the status and Quota pace widgets.
@available(iOS 27.0, *)
enum StatusWidgetColorStyleAppEnum: String, AppEnum {
    case mono
    case colorful

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "Color Style",
        table: "WidgetConfiguration"))

    static let caseDisplayRepresentations: [StatusWidgetColorStyleAppEnum: DisplayRepresentation] = [
        .mono: DisplayRepresentation(title: LocalizedStringResource("Mono", table: "WidgetConfiguration")),
        .colorful: DisplayRepresentation(title: LocalizedStringResource("Colorful", table: "WidgetConfiguration")),
    ]
}

/// SiriKit `TokenActivitySource`.
@available(iOS 27.0, *)
enum TokenActivitySourceAppEnum: String, AppEnum {
    case all
    case claude
    case codex

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "Token Source",
        table: "WidgetConfiguration"))

    static let caseDisplayRepresentations: [TokenActivitySourceAppEnum: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: LocalizedStringResource("All", table: "WidgetConfiguration")),
        .claude: DisplayRepresentation(title: LocalizedStringResource("Claude Code", table: "WidgetConfiguration")),
        .codex: DisplayRepresentation(title: LocalizedStringResource("Codex", table: "WidgetConfiguration")),
    ]

    /// The Token Activity projection source this choice shows.
    var sourceID: String {
        switch self {
        case .all: WidgetActivityProjection.allSourceID
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}

// MARK: - Provider entity

/// A provider choice, like SiriKit `StatusWidgetProvider`. The id is the
/// provider id, or the reserved "Not selected" id.
@available(iOS 27.0, *)
struct StatusWidgetProviderAppEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "Provider",
        table: "WidgetConfiguration"))
    static let defaultQuery = StatusWidgetProviderAppEntityQuery()

    let id: String
    let displayString: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(self.displayString)")
    }

    /// The unused slot, listed first like the SiriKit options; leaving every
    /// slot unused selects providers automatically.
    static var notSelected: StatusWidgetProviderAppEntity {
        StatusWidgetProviderAppEntity(
            id: StatusWidgetProviderChoice.emptyIdentifier,
            displayString: StatusWidgetProviderChoice.emptyTitle)
    }
}

@available(iOS 27.0, *)
struct StatusWidgetProviderAppEntityQuery: EntityQuery {
    /// Test seam; nil reads the App Group catalogue.
    var catalogueURL: URL?

    init() {}

    init(catalogueURL: URL?) {
        self.catalogueURL = catalogueURL
    }

    func entities(for identifiers: [String]) async throws -> [StatusWidgetProviderAppEntity] {
        let catalogue = self.catalogue()
        return identifiers.map { id in
            if id == StatusWidgetProviderChoice.emptyIdentifier { return .notSelected }
            // A provider missing from the catalogue (not synced yet, or
            // retired) keeps the widget's choice under its stable id.
            let name = catalogue.first { $0.id == id }?.name ?? id
            return StatusWidgetProviderAppEntity(id: id, displayString: name)
        }
    }

    func suggestedEntities() async throws -> [StatusWidgetProviderAppEntity] {
        StatusWidgetProviderChoice.choices { try self.readCatalogue() }
            .map { StatusWidgetProviderAppEntity(id: $0.id, displayString: $0.name) }
    }

    func defaultResult() async -> StatusWidgetProviderAppEntity? {
        .notSelected
    }

    private func readCatalogue() throws -> [WidgetProviderRecord] {
        try self.catalogueURL.map { try WidgetProviderCatalogue.read(from: $0) } ?? WidgetProviderCatalogue.read()
    }

    private func catalogue() -> [WidgetProviderRecord] {
        (try? self.readCatalogue()) ?? []
    }
}

// MARK: - Quota window entity

/// A quota window choice, like SiriKit `QuotaPaceWindowOption` (child of the
/// Quota pace provider). Ids are `QuotaPaceWindowChoice` identifiers.
@available(iOS 27.0, *)
struct QuotaPaceWindowOptionAppEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "Quota Window",
        table: "WidgetConfiguration"))
    static let defaultQuery = QuotaPaceWindowOptionAppEntityQuery()

    let id: String
    let displayString: String
    let subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        if let subtitle {
            DisplayRepresentation(title: "\(self.displayString)", subtitle: "\(subtitle)")
        } else {
            DisplayRepresentation(title: "\(self.displayString)")
        }
    }

    init(id: String, displayString: String, subtitle: String? = nil) {
        self.id = id
        self.displayString = displayString
        self.subtitle = subtitle
    }

    init(_ option: QuotaPaceWindowChoice.Option) {
        self.init(id: option.identifier, displayString: option.title, subtitle: option.subtitle)
    }

    static var defaultWindow: QuotaPaceWindowOptionAppEntity {
        QuotaPaceWindowOptionAppEntity(
            id: QuotaPaceWindowChoice.defaultIdentifier,
            displayString: QuotaPaceWindowChoice.defaultTitle)
    }
}

@available(iOS 27.0, *)
struct QuotaPaceWindowOptionAppEntityQuery: EntityQuery {
    /// The options follow the provider currently set on the widget being
    /// edited, as the SiriKit options handler does (Research/071).
    @IntentParameterDependency<QuotaPaceWidgetAppIntent>(\.$provider)
    var intent

    /// Test seams; nil reads the App Group catalogue and the edited widget.
    private var catalogueURL: URL?
    private var providerIDOverride: String??

    init() {}

    init(providerID: String?, catalogueURL: URL?) {
        self.providerIDOverride = .some(providerID)
        self.catalogueURL = catalogueURL
    }

    func entities(for identifiers: [String]) async throws -> [QuotaPaceWindowOptionAppEntity] {
        let catalogue = self.catalogue()
        return identifiers.map { id in
            if id == QuotaPaceWindowChoice.defaultIdentifier { return .defaultWindow }
            // A choice is `<providerID>|<windowID>`: title it like its own
            // provider's picker option; a window no longer offered there
            // (e.g. a single window that is now the default) takes its
            // catalogue title; a window that is gone keeps its id. The widget
            // then follows the default (Research/071).
            let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
            let providerID = parts.first
            if let option = self.options(providerID: providerID, catalogue: catalogue)
                .first(where: { $0.identifier == id })
            {
                return QuotaPaceWindowOptionAppEntity(option)
            }
            if parts.count == 2,
               let window = catalogue.first(where: { $0.id == providerID })?.windows?
                   .first(where: { $0.id == parts[1] })
            {
                return QuotaPaceWindowOptionAppEntity(
                    id: id,
                    displayString: window.title(preferredLocalizations: Bundle.main.preferredLocalizations),
                    subtitle: window.windowMinutes.flatMap(QuotaPaceWindowChoice.durationText))
            }
            return QuotaPaceWindowOptionAppEntity(id: id, displayString: Self.fallbackTitle(for: id))
        }
    }

    func suggestedEntities() async throws -> [QuotaPaceWindowOptionAppEntity] {
        let providerID = self.providerIDOverride ?? self.intent?.provider.id
        return self.options(providerID: providerID, catalogue: self.catalogue())
            .map(QuotaPaceWindowOptionAppEntity.init)
    }

    func defaultResult() async -> QuotaPaceWindowOptionAppEntity? {
        .defaultWindow
    }

    private func options(providerID: String?, catalogue: [WidgetProviderRecord]) -> [QuotaPaceWindowChoice.Option] {
        QuotaPaceWindowChoice.options(
            for: catalogue.first { $0.id == providerID },
            preferredLocalizations: Bundle.main.preferredLocalizations,
            defaultTitle: QuotaPaceWindowChoice.defaultTitle,
            durationText: QuotaPaceWindowChoice.durationText)
    }

    private func catalogue() -> [WidgetProviderRecord] {
        // An unreadable catalogue still offers the default window.
        (try? self.catalogueURL.map { try WidgetProviderCatalogue.read(from: $0) } ?? WidgetProviderCatalogue.read())
            ?? []
    }

    private static func fallbackTitle(for identifier: String) -> String {
        guard let separator = identifier.firstIndex(of: "|") else { return identifier }
        let windowID = identifier[identifier.index(after: separator)...]
        return windowID.isEmpty ? identifier : String(windowID)
    }
}

// MARK: - Intents

/// Configuration of the iOS 27 CodexBar widget (`WidgetKinds.statusAppIntent`).
@available(iOS 27.0, *)
struct StatusWidgetAppIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("CodexBar Widget", table: "WidgetConfiguration")
    static let description = IntentDescription(LocalizedStringResource(
        "View synced provider usage, cost, and sync health.",
        table: "WidgetConfiguration"))

    @Parameter(title: LocalizedStringResource("Widget Type", table: "WidgetConfiguration"), default: .overview)
    var mode: StatusWidgetModeAppEnum

    @Parameter(title: LocalizedStringResource("Color Style", table: "WidgetConfiguration"), default: .mono)
    var colorStyle: StatusWidgetColorStyleAppEnum

    @Parameter(title: LocalizedStringResource("Provider 1", table: "WidgetConfiguration"))
    var provider1: StatusWidgetProviderAppEntity?

    @Parameter(title: LocalizedStringResource("Provider 2", table: "WidgetConfiguration"))
    var provider2: StatusWidgetProviderAppEntity?

    @Parameter(title: LocalizedStringResource("Provider 3", table: "WidgetConfiguration"))
    var provider3: StatusWidgetProviderAppEntity?

    @Parameter(title: LocalizedStringResource("Provider 4", table: "WidgetConfiguration"))
    var provider4: StatusWidgetProviderAppEntity?

    /// The provider slots belong to the overview only, as their SiriKit
    /// parent relation (`mode` EnumHasExactValue `overview`).
    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, StatusWidgetModeAppEnum.overview) {
            Summary {
                \.$mode
                \.$colorStyle
                \.$provider1
                \.$provider2
                \.$provider3
                \.$provider4
            }
        } otherwise: {
            Summary {
                \.$mode
                \.$colorStyle
            }
        }
    }

    init() {}

    init(
        mode: StatusWidgetModeAppEnum,
        colorStyle: StatusWidgetColorStyleAppEnum = .mono,
        providers: [StatusWidgetProviderAppEntity?] = [])
    {
        self.mode = mode
        self.colorStyle = colorStyle
        let slots = providers + Array(repeating: nil, count: max(0, 4 - providers.count))
        self.provider1 = slots[0]
        self.provider2 = slots[1]
        self.provider3 = slots[2]
        self.provider4 = slots[3]
    }
}

/// Configuration of the iOS 27 Quota pace widget (`WidgetKinds.quotaPaceAppIntent`).
@available(iOS 27.0, *)
struct QuotaPaceWidgetAppIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Quota pace", table: "WidgetConfiguration")
    static let description = IntentDescription(LocalizedStringResource(
        "See whether a provider's quota lasts until it resets.",
        table: "WidgetConfiguration"))

    @Parameter(title: LocalizedStringResource("Color Style", table: "WidgetConfiguration"), default: .mono)
    var colorStyle: StatusWidgetColorStyleAppEnum

    @Parameter(title: LocalizedStringResource("Provider", table: "WidgetConfiguration"))
    var provider: StatusWidgetProviderAppEntity?

    @Parameter(title: LocalizedStringResource("Quota Window", table: "WidgetConfiguration"))
    var quotaWindow: QuotaPaceWindowOptionAppEntity?

    /// The window follows its SiriKit parent relation (`provider` HasAnyValue).
    static var parameterSummary: some ParameterSummary {
        When(\.$provider, .hasAnyValue) {
            Summary {
                \.$colorStyle
                \.$provider
                \.$quotaWindow
            }
        } otherwise: {
            Summary {
                \.$colorStyle
                \.$provider
            }
        }
    }

    init() {}

    init(
        colorStyle: StatusWidgetColorStyleAppEnum = .mono,
        provider: StatusWidgetProviderAppEntity? = nil,
        quotaWindow: QuotaPaceWindowOptionAppEntity? = nil)
    {
        self.colorStyle = colorStyle
        self.provider = provider
        self.quotaWindow = quotaWindow
    }
}

/// Configuration of the iOS 27 Token Activity widget (`WidgetActivityKind.singleAppIntent`).
@available(iOS 27.0, *)
struct TokenActivityWidgetAppIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Token Activity", table: "WidgetConfiguration")
    static let description = IntentDescription(LocalizedStringResource(
        "Choose the token history to show.",
        table: "WidgetConfiguration"))

    @Parameter(title: LocalizedStringResource("Source", table: "WidgetConfiguration"), default: .all)
    var source: TokenActivitySourceAppEnum

    init() {}

    init(source: TokenActivitySourceAppEnum) {
        self.source = source
    }
}

/// Configuration of the iOS 27 Token Activity Comparison widget (`WidgetActivityKind.comparisonAppIntent`).
@available(iOS 27.0, *)
struct TokenActivityComparisonAppIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Token Activity Comparison", table: "WidgetConfiguration")
    static let description = IntentDescription(LocalizedStringResource(
        "Choose two token histories to compare.",
        table: "WidgetConfiguration"))

    @Parameter(title: LocalizedStringResource("First Source", table: "WidgetConfiguration"), default: .all)
    var firstSource: TokenActivitySourceAppEnum

    @Parameter(title: LocalizedStringResource("Second Source", table: "WidgetConfiguration"), default: .claude)
    var secondSource: TokenActivitySourceAppEnum

    init() {}

    init(firstSource: TokenActivitySourceAppEnum, secondSource: TokenActivitySourceAppEnum) {
        self.firstSource = firstSource
        self.secondSource = secondSource
    }

    var sourceIDs: [String] {
        [self.firstSource.sourceID, self.secondSource.sourceID]
    }
}
