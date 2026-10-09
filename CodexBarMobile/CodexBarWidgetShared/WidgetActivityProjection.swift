import Foundation
import WidgetKit

enum WidgetActivityKind {
    /// SiriKit-configured widgets: every system; in the gallery before iOS 27.
    static let single = "CodexBarTokenActivitySingleV2"
    static let comparison = "CodexBarTokenActivityComparisonV2"
    /// App Intents widgets, iOS 27 and later (Research/072). Stable: a kind
    /// change drops every placed widget.
    static let singleAppIntent = "CodexBarTokenActivitySingleAppIntent"
    static let comparisonAppIntent = "CodexBarTokenActivityComparisonAppIntent"

    static let all = [single, comparison, singleAppIntent, comparisonAppIntent]
}

struct WidgetActivityEntry: TimelineEntry {
    let date: Date
    let sourceIDs: [String]
    let projection: WidgetActivityProjection
}

enum WidgetActivityState: String, Codable, Sendable {
    case loaded
    case syncing
    case noData
    case error
}

struct WidgetActivityDay: Codable, Equatable, Sendable {
    let key: String
    /// Nil means unknown. Zero is confirmed inactivity. Positive incomplete
    /// totals remain lower bounds, matching the in-app Token Activity grid.
    let tokens: Int?
    let isLowerBound: Bool
    let intensity: Double
}

struct WidgetActivitySource: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let days: [WidgetActivityDay]
    let tintHex: String?

    init(id: String, name: String, days: [WidgetActivityDay], tintHex: String? = nil) {
        self.id = id
        self.name = name
        self.days = days
        self.tintHex = tintHex
    }
}

struct WidgetActivityProjection: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let allSourceID = "all"

    let version: Int
    let state: WidgetActivityState
    let generatedAt: Date
    let latestSyncAt: Date?
    let sources: [WidgetActivitySource]

    var isStale: Bool {
        guard let latestSyncAt else { return true }
        return Date().timeIntervalSince(latestSyncAt) > 6 * 60 * 60
    }

    func source(id: String) -> WidgetActivitySource? {
        self.sources.first { $0.id == id }
    }

    static func state(_ state: WidgetActivityState, now: Date = .now) -> Self {
        Self(version: schemaVersion, state: state, generatedAt: now, latestSyncAt: nil, sources: [])
    }

    static func preview(now: Date = .now) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        let days = (0..<365).compactMap { offset -> WidgetActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset - 364, to: today) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            let count: Int? = offset.isMultiple(of: 11) ? nil : (offset.isMultiple(of: 5) ? 0 : (offset % 4 + 1) * 72_000)
            return WidgetActivityDay(
                key: key,
                tokens: count,
                isLowerBound: offset.isMultiple(of: 13) && count != nil,
                intensity: count.map { $0 == 0 ? 0 : Double(offset % 4 + 1) * 0.25 } ?? 0)
        }
        return Self(
            version: schemaVersion,
            state: .loaded,
            generatedAt: now,
            latestSyncAt: now.addingTimeInterval(-120),
            sources: [
                WidgetActivitySource(id: allSourceID, name: "All", days: days),
                WidgetActivitySource(id: "codex", name: "Codex", days: days),
                WidgetActivitySource(id: "claude", name: "Claude Code", days: days),
            ])
    }
}

enum WidgetActivityStore {
    static let groupID = "group.com.o1xhack.codexbar"
    static let filename = "widget-token-activity-v1.json"

    static func fileURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(filename)
    }

    static func read(from url: URL? = fileURL()) throws -> WidgetActivityProjection? {
        guard let url else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let projection = try JSONDecoder().decode(WidgetActivityProjection.self, from: Data(contentsOf: url))
        guard projection.version == WidgetActivityProjection.schemaVersion else { return nil }
        return projection
    }

    static func write(_ projection: WidgetActivityProjection, to url: URL? = fileURL()) throws {
        guard let url else { throw StoreError.groupUnavailable }
        let data = try JSONEncoder().encode(projection)
        try data.write(to: url, options: .atomic)
    }

    enum StoreError: Error {
        case groupUnavailable
    }
}
