import Foundation

struct WidgetProviderRecord: Codable, Hashable, Sendable {
    let id: String
    let name: String
}

/// A configuration-only empty slot; never persisted in the provider catalogue.
enum StatusWidgetProviderChoice {
    static let emptyIdentifier = "codexbar-widget-choice:none"
}

enum WidgetProviderCatalogue {
    static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.o1xhack.codexbar")?
            .appendingPathComponent("widget-provider-catalogue-v1.json")
    }

    static func read(from url: URL? = fileURL()) throws -> [WidgetProviderRecord] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([WidgetProviderRecord].self, from: Data(contentsOf: url))
    }

    static func write(_ providers: [WidgetProviderRecord], to url: URL? = fileURL()) throws {
        guard let url else { return }
        var seen = Set<String>()
        let unique = providers.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try JSONEncoder().encode(unique).write(to: url, options: .atomic)
    }
}
