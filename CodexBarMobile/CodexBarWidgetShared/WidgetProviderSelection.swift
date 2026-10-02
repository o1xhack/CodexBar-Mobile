import AppIntents
import Foundation
import WidgetKit

struct WidgetProviderEntity: AppEntity, Codable, Hashable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static let defaultQuery = WidgetProviderQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(self.name)")
    }
}

struct WidgetProviderQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetProviderEntity] {
        let catalogue = try await self.suggestedEntities()
        return identifiers.map { id in
            catalogue.first { $0.id == id } ?? WidgetProviderEntity(id: id, name: id)
        }
    }

    func suggestedEntities() async throws -> [WidgetProviderEntity] {
        let catalogue = try WidgetProviderCatalogue.read()
        #if targetEnvironment(simulator)
        if catalogue.isEmpty, ProcessInfo.processInfo.environment["CODEXBAR_WIDGET_DISABLE_SIMULATOR_MOCK"] != "1" {
            return CodexBarWidgetSnapshot.placeholder().topProviders.map {
                WidgetProviderEntity(id: $0.providerID, name: $0.providerName)
            }
        }
        #endif
        return catalogue.map { WidgetProviderEntity(id: $0.id, name: $0.name) }
    }
}

enum WidgetProviderResetText {
    static func days(_ resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt else { return nil }
        let days = resetsAt.timeIntervalSince(now) / 86400
        guard days > 0 else { return String(localized: "Now") }
        if days < 0.1 { return String(localized: "<0.1d") }
        let number = days.formatted(.number.precision(.fractionLength(0...1)))
        return String(format: String(localized: "%@d"), number)
    }
}

enum WidgetProviderSelection {
    static func resolve(
        from providers: [CodexBarWidgetProviderSummary],
        selected: [WidgetProviderEntity]?,
        family: WidgetFamily,
        now: Date) -> [CodexBarWidgetProviderSummary]
    {
        var seen = Set<String>()
        let unique = providers.filter { seen.insert($0.providerID).inserted }
        guard let selected, !selected.isEmpty else {
            return Array(unique.prefix(family == .systemSmall ? 2 : 4))
        }
        seen.removeAll()
        return selected.filter { seen.insert($0.id).inserted }.prefix(4).map { entity in
            unique.first { $0.providerID == entity.id } ?? CodexBarWidgetProviderSummary(
                id: "unavailable|\(entity.id)",
                providerName: entity.name,
                providerID: entity.id,
                loginMethod: nil,
                usagePercent: nil,
                todayCostUSD: nil,
                thirtyDayCostUSD: nil,
                tokensToday: nil,
                isError: true,
                statusMessage: String(localized: "Unavailable"),
                lastUpdated: now)
        }
    }

    static func columns(count: Int, family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: count >= 3 ? 2 : 1
        case .systemMedium: count == 4 ? 2 : max(1, count)
        case .systemLarge: count > 2 ? 2 : 1
        case .systemExtraLarge: max(1, count)
        default: max(1, min(count, 2))
        }
    }
}
