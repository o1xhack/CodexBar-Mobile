import CodexBarSync
import Foundation

/// A metric binding always uses provider/account/window identity, never its editable label.
enum SummaryCardMetric: Codable, Equatable, Hashable, Sendable {
    case quota(windowID: String)
    case depletion(windowID: String)
    case balance
    case extraUsage

    var windowID: String? {
        switch self {
        case let .quota(windowID), let .depletion(windowID): windowID
        case .balance, .extraUsage: nil
        }
    }
}

enum SummaryCardColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case white, blue, green, orange, purple, pink
    var id: String {
        self.rawValue
    }
}

enum SummaryCardEmphasis: String, Codable, CaseIterable, Identifiable, Sendable {
    case percent, countdown
    var id: String {
        self.rawValue
    }
}

struct SummaryCardConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = .init()
    let accountAnchorID: String
    let providerID: String
    let metric: SummaryCardMetric
    var title: String?
    var color: SummaryCardColor = .white
    var emphasis: SummaryCardEmphasis = .percent
    /// Display fallbacks survive an account/window disappearing. They never identify it.
    var accountTitle: String = ""
    var metricTitle: String = ""
}

/// A module is independent of provider metrics and reuses the existing quota preferences store.
struct SummaryQuotaModule: Codable, Equatable, Sendable {
    var id: UUID = .init()
    var position: Int
}

struct SummaryPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    var schemaVersion = Self.currentSchemaVersion
    var hasInitialized = false
    var cards: [SummaryCardConfiguration] = []
    /// Optional keeps existing v1 archives compatible and never pins a module automatically.
    var quotaModule: SummaryQuotaModule?

    var orderedItemIDs: [UUID] {
        var ids = self.cards.map(\.id)
        if let module = self.quotaModule {
            ids.insert(module.id, at: min(ids.count, max(0, module.position)))
        }
        return ids
    }

    var accountAliases: [String: String] = [:]
    var accountAnchors: [UsageAccountAnchor] = []
}

struct SummaryMetricCandidate: Identifiable, Equatable, Sendable {
    let accountAnchorID: String
    let providerID: String
    let providerName: String
    let accountTitle: String
    let metric: SummaryCardMetric
    let metricTitle: String
    let supportsCountdown: Bool

    struct ID: Hashable, Sendable {
        let accountAnchorID: String
        let providerID: String
        let metric: SummaryCardMetric
    }

    var id: ID {
        ID(accountAnchorID: self.accountAnchorID, providerID: self.providerID, metric: self.metric)
    }

    func configuration() -> SummaryCardConfiguration {
        SummaryCardConfiguration(
            accountAnchorID: self.accountAnchorID,
            providerID: self.providerID,
            metric: self.metric,
            accountTitle: self.accountTitle,
            metricTitle: self.metricTitle)
    }
}

enum SummaryCardState: Equatable, Sendable {
    case available, unknown, stale, resetPassed, blocked, missingAccount, missingMetric, unavailable, disabled
}

struct SummaryCardAmount: Equatable, Sendable {
    let value: Double
    let currencyCode: String?
    let observedAt: Date
    let isEstimated: Bool
}

struct SummaryResolvedCard: Identifiable, Equatable, Sendable {
    let configuration: SummaryCardConfiguration
    let provider: ProviderUsageSnapshot?
    let accountTitle: String
    let metricTitle: String
    let state: SummaryCardState
    let isStale: Bool
    let observedAt: Date?
    let window: SyncRateWindow?
    let usedPercent: Double?
    let resetDate: Date?
    let forecast: QuotaPace.Forecast?
    let amount: SummaryCardAmount?
    var compactAccountTitle: String?
    var privateAccountTitle: String?

    var id: UUID {
        self.configuration.id
    }

    var title: String {
        self.configuration.title ?? self.accountTitle
    }

    var compactTitle: String {
        self.configuration.title ?? self.compactAccountTitle ?? self.accountTitle
    }

    var privateTitle: String {
        self.configuration.title ?? self.privateAccountTitle ?? self.compactTitle
    }

    var supportsCountdown: Bool {
        if case .quota = self.configuration.metric { return self.resetDate != nil }
        return false
    }

    var effectiveEmphasis: SummaryCardEmphasis {
        self.supportsCountdown ? self.configuration.emphasis : .percent
    }
}
