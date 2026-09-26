import AppIntents
import Foundation

// Keep these entities in the widget target so App Intents registers one owner.

struct WidgetActivitySourceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Token Source"
    static let defaultQuery = WidgetActivitySourceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: self.name))
    }

    static let all = WidgetActivitySourceEntity(
        id: WidgetActivityProjection.allSourceID,
        name: "All")
}

struct WidgetActivitySourceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetActivitySourceEntity] {
        let available = Self.available()
        return identifiers.map { id in
            available.first { $0.id == id } ?? WidgetActivitySourceEntity(
                id: id,
                name: id == WidgetActivityProjection.allSourceID ? "All" : "Unavailable source")
        }
    }

    func suggestedEntities() async throws -> [WidgetActivitySourceEntity] {
        Self.available()
    }

    func defaultResult() async -> WidgetActivitySourceEntity? {
        .all
    }

    static func available() -> [WidgetActivitySourceEntity] {
        let standard = [
            WidgetActivitySourceEntity.all,
            WidgetActivitySourceEntity(id: "claude", name: "Claude Code"),
            WidgetActivitySourceEntity(id: "codex", name: "Codex"),
        ]
        guard let projection = try? WidgetActivityStore.read() else { return standard }
        let projected = projection.sources.map { WidgetActivitySourceEntity(id: $0.id, name: $0.name) }
        let projectedByID = Dictionary(projected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let extra = projectedByID.values
            .filter { entity in !standard.contains { $0.id == entity.id } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return standard.map { projectedByID[$0.id] ?? $0 } + extra
    }

    static func firstProvider() -> WidgetActivitySourceEntity? {
        Self.available().first { $0.id != WidgetActivityProjection.allSourceID }
    }
}

/// The comparison's second picker shares the same choices, but defaults to
/// the first available provider instead of selecting All twice.
struct WidgetActivitySecondSourceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Token Source"
    static let defaultQuery = WidgetActivitySecondSourceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: self.name))
    }
}

struct WidgetActivitySecondSourceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetActivitySecondSourceEntity] {
        let available = WidgetActivitySourceQuery.available()
        return identifiers.map { id in
            let selected = available.first { $0.id == id }
            return WidgetActivitySecondSourceEntity(
                id: id,
                name: selected?.name ?? "Unavailable source")
        }
    }

    func suggestedEntities() async throws -> [WidgetActivitySecondSourceEntity] {
        let available = WidgetActivitySourceQuery.available()
        let providers = available.filter { $0.id != WidgetActivityProjection.allSourceID }
        let all = available.filter { $0.id == WidgetActivityProjection.allSourceID }
        return (providers + all).map {
            WidgetActivitySecondSourceEntity(id: $0.id, name: $0.name)
        }
    }

    func defaultResult() async -> WidgetActivitySecondSourceEntity? {
        let provider = WidgetActivitySourceQuery.firstProvider()
        return provider.map { WidgetActivitySecondSourceEntity(id: $0.id, name: $0.name) }
    }
}

struct WidgetActivitySingleIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Token Activity"
    static let description = IntentDescription("Choose the token history to show.")
    static let openAppWhenRun = false

    @Parameter(title: "Source")
    var source: WidgetActivitySourceEntity?

    init() {
        self.source = .all
    }

    init(source: WidgetActivitySourceEntity) {
        self.source = source
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct WidgetActivityComparisonIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Token Activity Comparison"
    static let description = IntentDescription("Choose two token histories to compare.")
    static let openAppWhenRun = false

    @Parameter(title: "First Source")
    var firstSource: WidgetActivitySourceEntity?

    @Parameter(title: "Second Source")
    var secondSource: WidgetActivitySecondSourceEntity?

    init() {
        self.firstSource = .all
        self.secondSource = WidgetActivitySourceQuery.firstProvider().map {
            WidgetActivitySecondSourceEntity(id: $0.id, name: $0.name)
        }
    }

    init(firstSource: WidgetActivitySourceEntity, secondSource: WidgetActivitySecondSourceEntity) {
        self.firstSource = firstSource
        self.secondSource = secondSource
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
