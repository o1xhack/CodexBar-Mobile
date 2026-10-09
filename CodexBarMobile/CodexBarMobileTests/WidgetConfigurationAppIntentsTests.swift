import AppIntents
import Foundation
import Intents
import Testing
@testable import CodexBarMobile

/// Research/072 — App Intents widgets next to the SiriKit widgets (iOS 27+).
///
/// The App Intents widgets configure exactly like the SiriKit ones, so these
/// tests read the shipped `.intentdefinition` files and compare them with the
/// App Intent types. Nothing may tie an App Intent to a SiriKit intent class:
/// iOS 26 would then edit the SiriKit widgets through it and break them.
@Suite("Widget configuration App Intents")
struct WidgetConfigurationAppIntentsTests {
    // MARK: Intent definition parity

    private struct DefinitionParameter {
        let name: String
        let type: String
        let enumType: String?
        let objectType: String?
    }

    private static func definition(_ resource: String) throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: "intentdefinition"))
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private static func parameters(intent: String, in definition: [String: Any]) throws -> [DefinitionParameter] {
        let intents = try #require(definition["INIntents"] as? [[String: Any]])
        let entry = try #require(intents.first { $0["INIntentName"] as? String == intent })
        let parameters = try #require(entry["INIntentParameters"] as? [[String: Any]])
        return parameters.compactMap { parameter in
            guard let name = parameter["INIntentParameterName"] as? String,
                  let type = parameter["INIntentParameterType"] as? String
            else { return nil }
            return DefinitionParameter(
                name: name,
                type: type,
                enumType: parameter["INIntentParameterEnumType"] as? String,
                objectType: parameter["INIntentParameterObjectType"] as? String)
        }
    }

    /// SiriKit enum value names, without the generated `unknown` (0).
    private static func enumValueNames(_ enumName: String, in definition: [String: Any]) throws -> [String] {
        let enums = try #require(definition["INEnums"] as? [[String: Any]])
        let entry = try #require(enums.first { $0["INEnumName"] as? String == enumName })
        let values = try #require(entry["INEnumValues"] as? [[String: Any]])
        return values.compactMap { $0["INEnumValueName"] as? String }.filter { $0 != "unknown" }
    }

    /// `@Parameter` storage of an App Intent: parameter name -> value type name.
    private static func appIntentParameters(_ intent: some AppIntent) -> [String: String] {
        var result: [String: String] = [:]
        for child in Mirror(reflecting: intent).children {
            guard let label = child.label, label.hasPrefix("_") else { continue }
            result[String(label.dropFirst())] = String(describing: type(of: child.value))
        }
        return result
    }

    @available(iOS 27.0, *)
    private static let enumCases: [String: [String]] = [
        "StatusWidgetModeAppEnum": StatusWidgetModeAppEnum.allCases.map(\.rawValue),
        "StatusWidgetColorStyleAppEnum": StatusWidgetColorStyleAppEnum.allCases.map(\.rawValue),
        "TokenActivitySourceAppEnum": TokenActivitySourceAppEnum.allCases.map(\.rawValue),
    ]

    /// Every SiriKit parameter exists on the App Intent under the same name;
    /// Integer enums map to an `AppEnum` whose cases carry the SiriKit value
    /// names, custom objects to an optional `AppEntity`.
    @available(iOS 27.0, *)
    private static func expectParity(
        intent: String,
        definition: String,
        appIntent: some AppIntent,
        enumTypes: [String: String],
        entityTypes: [String: String]) throws
    {
        let siriParameters = try self.parameters(intent: intent, in: self.definition(definition))
        let appParameters = self.appIntentParameters(appIntent)
        #expect(Set(appParameters.keys) == Set(siriParameters.map(\.name)))
        for parameter in siriParameters {
            let typeName = try #require(appParameters[parameter.name])
            switch parameter.type {
            case "Integer":
                let siriEnum = try #require(parameter.enumType)
                let appEnum = try #require(enumTypes[siriEnum])
                #expect(typeName == "IntentParameter<\(appEnum)>", "\(intent).\(parameter.name)")
                let names = try self.enumValueNames(siriEnum, in: self.definition(definition))
                #expect(self.enumCases[appEnum] == names, "\(siriEnum) cases")
            case "Object":
                let siriType = try #require(parameter.objectType)
                let entity = try #require(entityTypes[siriType])
                #expect(typeName == "IntentParameter<Optional<\(entity)>>", "\(intent).\(parameter.name)")
            default:
                Issue.record("Unexpected SiriKit parameter type \(parameter.type) for \(parameter.name)")
            }
        }
    }

    @available(iOS 27.0, *)
    @Test func `No App Intent maps to a SiriKit intent class`() throws {
        let appIntents: [Any.Type] = [
            StatusWidgetAppIntent.self,
            QuotaPaceWidgetAppIntent.self,
            TokenActivityWidgetAppIntent.self,
            TokenActivityComparisonAppIntent.self,
        ]
        let sirikitClasses = [
            SelectStatusWidgetIntent.self,
            SelectQuotaPaceWidgetIntent.self,
            SelectTokenActivityIntent.self,
            CompareTokenActivityIntent.self,
        ].map { NSStringFromClass($0) }
        for type in appIntents {
            #expect(!(type is any CustomIntentMigratedAppIntent.Type), "\(type)")
            #expect(!sirikitClasses.contains(String(describing: type)), "\(type)")
        }

        // The App Intents metadata the system reads must not name a SiriKit
        // intent class either (no `customIntentClassName`, no action id equal
        // to one).
        let url = try #require(Bundle.main.url(
            forResource: "extract",
            withExtension: "actionsdata",
            subdirectory: "Metadata.appintents"))
        let metadata = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = try #require(metadata["actions"] as? [String: [String: Any]])
        #expect(actions.keys.contains("StatusWidgetAppIntent"))
        for (identifier, action) in actions {
            #expect(!sirikitClasses.contains(identifier), "\(identifier)")
            #expect(
                action["customIntentClassName"] == nil || action["customIntentClassName"] is NSNull,
                "\(identifier)")
        }
    }

    @Test func `App Intents widgets use their own kinds`() {
        let sirikit = [
            WidgetKinds.status,
            WidgetKinds.quotaPace,
            WidgetActivityKind.single,
            WidgetActivityKind.comparison,
        ]
        let appIntents = [
            WidgetKinds.statusAppIntent,
            WidgetKinds.quotaPaceAppIntent,
            WidgetActivityKind.singleAppIntent,
            WidgetActivityKind.comparisonAppIntent,
        ]
        #expect(Set(sirikit + appIntents).count == 8)
        // The shipped SiriKit kinds never change: placed widgets depend on them.
        #expect(sirikit == [
            "CodexBarStatusWidgetV2",
            "CodexBarQuotaPaceWidget",
            "CodexBarTokenActivitySingleV2",
            "CodexBarTokenActivityComparisonV2",
        ])
        #expect(Set(WidgetActivityKind.all) == Set([
            WidgetActivityKind.single,
            WidgetActivityKind.comparison,
            WidgetActivityKind.singleAppIntent,
            WidgetActivityKind.comparisonAppIntent,
        ]))
    }

    @available(iOS 27.0, *)
    @Test func `Status widget parameters mirror the SiriKit definition`() throws {
        try Self.expectParity(
            intent: "SelectStatusWidget",
            definition: "WidgetStatus",
            appIntent: StatusWidgetAppIntent(),
            enumTypes: [
                "StatusWidgetMode": "StatusWidgetModeAppEnum",
                "StatusWidgetColorStyle": "StatusWidgetColorStyleAppEnum",
            ],
            entityTypes: ["StatusWidgetProvider": "StatusWidgetProviderAppEntity"])
    }

    @available(iOS 27.0, *)
    @Test func `Quota pace widget parameters mirror the SiriKit definition`() throws {
        try Self.expectParity(
            intent: "SelectQuotaPaceWidget",
            definition: "WidgetStatus",
            appIntent: QuotaPaceWidgetAppIntent(),
            enumTypes: ["StatusWidgetColorStyle": "StatusWidgetColorStyleAppEnum"],
            entityTypes: [
                "StatusWidgetProvider": "StatusWidgetProviderAppEntity",
                "QuotaPaceWindowOption": "QuotaPaceWindowOptionAppEntity",
            ])
    }

    @available(iOS 27.0, *)
    @Test func `Token Activity widget parameters mirror the SiriKit definitions`() throws {
        try Self.expectParity(
            intent: "SelectTokenActivity",
            definition: "WidgetActivity",
            appIntent: TokenActivityWidgetAppIntent(),
            enumTypes: ["TokenActivitySource": "TokenActivitySourceAppEnum"],
            entityTypes: [:])
        try Self.expectParity(
            intent: "CompareTokenActivity",
            definition: "WidgetActivity",
            appIntent: TokenActivityComparisonAppIntent(),
            enumTypes: ["TokenActivitySource": "TokenActivitySourceAppEnum"],
            entityTypes: [:])
    }

    @available(iOS 27.0, *)
    @Test func `Defaults match the SiriKit defaults`() {
        let status = StatusWidgetAppIntent()
        #expect(status.mode == .overview)
        #expect(status.colorStyle == .mono)
        #expect(status.provider1 == nil)
        let pace = QuotaPaceWidgetAppIntent()
        #expect(pace.colorStyle == .mono)
        #expect(pace.provider == nil)
        #expect(pace.quotaWindow == nil)
        #expect(TokenActivityWidgetAppIntent().source == .all)
        let comparison = TokenActivityComparisonAppIntent()
        #expect(comparison.firstSource == .all)
        #expect(comparison.secondSource == .claude)
    }

    // MARK: Conversion to the rendering configuration

    @available(iOS 27.0, *)
    @Test func `Status modes and color styles map like the SiriKit adapter`() {
        let pairs: [(StatusWidgetModeAppEnum, StatusWidgetMode, CodexBarWidgetMode)] = [
            (.overview, .overview, .overview),
            (.providerFocus, .providerFocus, .providerFocus),
            (.todayCost, .todayCost, .todayCost),
            (.syncHealth, .syncHealth, .syncHealth),
        ]
        for (appMode, siriMode, expected) in pairs {
            for (appStyle, siriStyle) in [
                (StatusWidgetColorStyleAppEnum.mono, StatusWidgetColorStyle.mono),
                (.colorful, .colorful),
            ] {
                let app = StatusWidgetConfigurationAdapter.configuration(
                    from: StatusWidgetAppIntent(mode: appMode, colorStyle: appStyle))
                let siri = SelectStatusWidgetIntent()
                siri.mode = siriMode
                siri.colorStyle = siriStyle
                let reference = StatusWidgetConfigurationAdapter.configuration(from: siri)
                #expect(app.mode == expected)
                #expect(app.mode == reference.mode)
                #expect(app.colorStyle == reference.colorStyle)
            }
        }
    }

    @available(iOS 27.0, *)
    @Test func `Status provider slots keep order, drop duplicates and unused slots`() {
        let intent = StatusWidgetAppIntent(mode: .overview, providers: [
            .notSelected,
            StatusWidgetProviderAppEntity(id: "fictitious-b", displayString: "Fictitious B"),
            StatusWidgetProviderAppEntity(id: "fictitious-a", displayString: ""),
            StatusWidgetProviderAppEntity(id: "fictitious-b", displayString: "Duplicate"),
        ])
        let providers = StatusWidgetConfigurationAdapter.configuration(from: intent).providers ?? []
        #expect(providers.map(\.id) == ["fictitious-b", "fictitious-a"])
        // An empty display name falls back to the stable id, as for SiriKit.
        #expect(providers.map(\.name) == ["Fictitious B", "fictitious-a"])
    }

    @available(iOS 27.0, *)
    @Test func `Not selected or unset providers select automatically`() {
        let unset = StatusWidgetAppIntent(mode: .overview)
        #expect(StatusWidgetConfigurationAdapter.configuration(from: unset).providers?.isEmpty == true)
        let cleared = StatusWidgetAppIntent(mode: .overview, providers: Array(repeating: .notSelected, count: 4))
        #expect(StatusWidgetConfigurationAdapter.configuration(from: cleared).providers?.isEmpty == true)
        let pace = QuotaPaceWidgetAppIntent(provider: .notSelected)
        #expect(StatusWidgetConfigurationAdapter.configuration(from: pace).providers?.isEmpty == true)
    }

    @available(iOS 27.0, *)
    @Test func `Quota pace reads its own provider, style and window`() {
        let claude = StatusWidgetProviderAppEntity(id: "claude", displayString: "Claude")
        let window = QuotaPaceWindowOptionAppEntity(
            id: "claude|claude-weekly-scoped-fable",
            displayString: "Fable only")
        let intent = QuotaPaceWidgetAppIntent(colorStyle: .colorful, provider: claude, quotaWindow: window)
        let configuration = StatusWidgetConfigurationAdapter.configuration(from: intent)
        #expect(configuration.mode == .quotaPace)
        #expect(configuration.colorStyle == .colorful)
        #expect(configuration.providers?.map(\.id) == ["claude"])
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(from: intent) == "claude|claude-weekly-scoped-fable")

        // The same values through SiriKit give the same rendering inputs.
        let siri = SelectQuotaPaceWidgetIntent()
        siri.colorStyle = .colorful
        siri.provider = StatusWidgetProvider(identifier: "claude", display: "Claude")
        siri.quotaWindow = QuotaPaceWindowOption(identifier: window.id, display: "Fable only")
        #expect(StatusWidgetConfigurationAdapter.configuration(from: siri).providers?.map(\.id) == ["claude"])
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(from: siri)
            == StatusWidgetConfigurationAdapter.paceWindowChoice(from: intent))
    }

    @available(iOS 27.0, *)
    @Test func `The default or an unset window follows the weekly default`() {
        let claude = StatusWidgetProviderAppEntity(id: "claude", displayString: "Claude")
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(
            from: QuotaPaceWidgetAppIntent(provider: claude)) == nil)
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(
            from: QuotaPaceWidgetAppIntent(provider: claude, quotaWindow: .defaultWindow)) == nil)
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(
            from: QuotaPaceWidgetAppIntent(
                provider: claude,
                quotaWindow: QuotaPaceWindowOptionAppEntity(id: "", displayString: ""))) == nil)
    }

    @available(iOS 27.0, *)
    @Test func `Token sources map to the projection source ids`() {
        #expect(TokenActivitySourceAppEnum.all.sourceID == WidgetActivityProjection.allSourceID)
        #expect(TokenActivitySourceAppEnum.claude.sourceID == "claude")
        #expect(TokenActivitySourceAppEnum.codex.sourceID == "codex")
        #expect(TokenActivityComparisonAppIntent(firstSource: .claude, secondSource: .codex).sourceIDs == [
            "claude",
            "codex",
        ])
        #expect(TokenActivityWidgetAppIntent(source: .codex).source.sourceID == "codex")
    }

    // MARK: Entity queries

    private static func catalogueURL(_ records: [WidgetProviderRecord]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-appintent-catalogue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("catalogue.json")
        try WidgetProviderCatalogue.write(records, to: url)
        return url
    }

    @available(iOS 27.0, *)
    private static let catalogue: [WidgetProviderRecord] = [
        WidgetProviderRecord(
            id: "claude",
            name: "Claude",
            windows: [
                .init(id: "primary", label: "Session", windowMinutes: 300, titles: ["en": "Session"]),
                .init(id: "secondary", label: "Weekly", windowMinutes: 10080, titles: ["en": "Weekly"]),
                .init(
                    id: "claude-weekly-scoped-fable",
                    label: "Fable only",
                    windowMinutes: 10080,
                    titles: ["en": "Fable only"]),
            ],
            defaultWindowID: "secondary"),
        WidgetProviderRecord(
            id: "codex",
            name: "Codex",
            windows: [.init(id: "secondary", label: "Weekly", windowMinutes: 10080, titles: ["en": "Weekly"])],
            defaultWindowID: "secondary"),
    ]

    @available(iOS 27.0, *)
    @Test func `Provider options list Not selected first, then the catalogue`() async throws {
        let url = try Self.catalogueURL(Self.catalogue)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let query = StatusWidgetProviderAppEntityQuery(catalogueURL: url)
        let suggested = try await query.suggestedEntities()
        #expect(suggested.map(\.id) == [StatusWidgetProviderChoice.emptyIdentifier, "claude", "codex"])
        #expect(suggested.first?.displayString == StatusWidgetProviderChoice.emptyTitle)
        #expect(await query.defaultResult()?.id == StatusWidgetProviderChoice.emptyIdentifier)
    }

    @available(iOS 27.0, *)
    @Test func `Provider ids resolve by catalogue and keep unknown providers`() async throws {
        let url = try Self.catalogueURL(Self.catalogue)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let query = StatusWidgetProviderAppEntityQuery(catalogueURL: url)
        let resolved = try await query.entities(for: [
            "codex",
            StatusWidgetProviderChoice.emptyIdentifier,
            "fictitious-retired",
        ])
        #expect(resolved.map(\.id) == ["codex", StatusWidgetProviderChoice.emptyIdentifier, "fictitious-retired"])
        #expect(resolved.map(\.displayString) == ["Codex", StatusWidgetProviderChoice.emptyTitle, "fictitious-retired"])
    }

    @available(iOS 27.0, *)
    @Test func `An unreadable catalogue still offers Not selected and the default window`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-appintent-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("catalogue.json")
        try Data("not json".utf8).write(to: url)
        let providers = try await StatusWidgetProviderAppEntityQuery(catalogueURL: url).suggestedEntities()
        #expect(providers.map(\.id) == [StatusWidgetProviderChoice.emptyIdentifier])
        let windows = try await QuotaPaceWindowOptionAppEntityQuery(providerID: "claude", catalogueURL: url)
            .suggestedEntities()
        #expect(windows.map(\.id) == [QuotaPaceWindowChoice.defaultIdentifier])
    }

    @available(iOS 27.0, *)
    @Test func `Window options follow the provider being edited`() async throws {
        let url = try Self.catalogueURL(Self.catalogue)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let claude = try await QuotaPaceWindowOptionAppEntityQuery(providerID: "claude", catalogueURL: url)
            .suggestedEntities()
        #expect(claude.map(\.id) == [
            QuotaPaceWindowChoice.defaultIdentifier,
            "claude|primary",
            "claude|secondary",
            "claude|claude-weekly-scoped-fable",
        ])
        #expect(claude.first?.displayString == QuotaPaceWindowChoice.defaultTitle)
        #expect(claude.dropFirst().allSatisfy { $0.subtitle != nil })
        // Codex's single weekly window is its default: nothing to choose.
        let codex = try await QuotaPaceWindowOptionAppEntityQuery(providerID: "codex", catalogueURL: url)
            .suggestedEntities()
        #expect(codex.map(\.id) == [QuotaPaceWindowChoice.defaultIdentifier])
        for providerID in [nil, StatusWidgetProviderChoice.emptyIdentifier, "fictitious-unknown"] {
            let options = try await QuotaPaceWindowOptionAppEntityQuery(providerID: providerID, catalogueURL: url)
                .suggestedEntities()
            #expect(options.map(\.id) == [QuotaPaceWindowChoice.defaultIdentifier])
        }
    }

    @available(iOS 27.0, *)
    @Test func `Window ids resolve from their own provider, whatever is being edited`() async throws {
        let url = try Self.catalogueURL(Self.catalogue)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let query = QuotaPaceWindowOptionAppEntityQuery(providerID: "codex", catalogueURL: url)
        let resolved = try await query.entities(for: [
            "claude|claude-weekly-scoped-fable",
            QuotaPaceWindowChoice.defaultIdentifier,
            "claude|gone-window",
            "no-separator",
        ])
        #expect(resolved.map(\.id) == [
            "claude|claude-weekly-scoped-fable",
            QuotaPaceWindowChoice.defaultIdentifier,
            "claude|gone-window",
            "no-separator",
        ])
        #expect(resolved.map(\.displayString) == [
            "Fable only",
            QuotaPaceWindowChoice.defaultTitle,
            "gone-window",
            "no-separator",
        ])
        #expect(await query.defaultResult()?.id == QuotaPaceWindowChoice.defaultIdentifier)
    }
}
