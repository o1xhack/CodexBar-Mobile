import CodexBarSync
import Foundation

/// The phone's own quota readings for an identity-less provider singleton
/// (Grok read through browser cookies, Research/091), whose Mac publishes no
/// utilization history, so the Quota pace widget can chart it. The app writes
/// only streams it still attributes to that single account; the widget applies
/// them only while the merged snapshot still has exactly one account of that
/// provider. Local lanes never drive automatic provider selection.
struct WidgetLocalQuotaHistory: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    struct Stream: Codable, Equatable, Sendable {
        let providerID: String
        let windowID: String
        /// Length of the observed cycle, as recorded with the readings.
        let windowDuration: TimeInterval
        let entries: [SyncUtilizationEntry]
    }

    var version = Self.schemaVersion
    var streams: [Stream] = []

    func stream(providerID: String, windowID: String) -> Stream? {
        self.streams.first { $0.providerID == providerID && $0.windowID == windowID }
    }

    /// Providers with Mac-published lanes keep them; local readings never
    /// replace or mix into them.
    static func appliesTo(providerID: String) -> Bool {
        providerID != "codex" && providerID != "claude"
    }
}

enum WidgetLocalQuotaHistoryStore {
    static let groupID = "group.com.o1xhack.codexbar"
    static let filename = "widget-local-quota-history-v1.json"

    static func fileURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(filename)
    }

    /// Missing, unreadable or older files read as no history.
    static func read(from url: URL? = fileURL()) -> WidgetLocalQuotaHistory? {
        guard let url, let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(WidgetLocalQuotaHistory.self, from: data),
              history.version == WidgetLocalQuotaHistory.schemaVersion
        else { return nil }
        return history
    }

    static func write(_ history: WidgetLocalQuotaHistory, to url: URL? = fileURL()) throws {
        guard let url else { throw StoreError.groupUnavailable }
        try JSONEncoder().encode(history).write(to: url, options: .atomic)
    }

    enum StoreError: Error {
        case groupUnavailable
    }
}
