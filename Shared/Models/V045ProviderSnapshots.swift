import Foundation

/// A monetary value that is deliberately not a budget. Upstream providers
/// use `ProviderCostSnapshot(limit: 0)` for prepaid balances and uncapped
/// spend; representing those values as `SyncBudgetSnapshot` would render an
/// impossible "$X / $0" progress bar on iOS.
public struct SyncProviderAmount: Codable, Sendable, Equatable {
    /// Canonical semantic kind (`"balance"` or `"spend"`). Kept as a String
    /// so a newer Mac can add a kind without making an older iOS decoder fail.
    public let kind: String
    public let amount: Double
    public let currencyCode: String
    public let period: String?
    public let isEstimated: Bool

    public init(
        kind: String,
        amount: Double,
        currencyCode: String,
        period: String?,
        isEstimated: Bool)
    {
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.period = period
        self.isEstimated = isEstimated
    }
}

/// sub2api account mode, wallet, and request/token totals that do not fit the
/// generic quota-window or cost-summary envelopes.
public struct SyncSub2APIUsage: Codable, Sendable, Equatable {
    public struct Totals: Codable, Sendable, Equatable {
        public let requests: Int
        public let totalTokens: Int
        public let actualCostUSD: Double

        public init(requests: Int, totalTokens: Int, actualCostUSD: Double) {
            self.requests = requests
            self.totalTokens = totalTokens
            self.actualCostUSD = actualCostUSD
        }
    }

    public let kind: String
    public let balance: Double?
    public let unit: String
    public let today: Totals?
    public let total: Totals?

    public init(kind: String, balance: Double?, unit: String, today: Totals?, total: Totals?) {
        self.kind = kind
        self.balance = balance
        self.unit = unit
        self.today = today
        self.total = total
    }
}

/// Wayfinder local-gateway routing evidence for iOS. Additive and optional in
/// `ProviderUsageSnapshot`; old iOS builds ignore it and new iOS builds decode
/// old Mac payloads as nil.
public struct SyncWayfinderUsage: Codable, Sendable, Equatable {
    public struct Route: Codable, Sendable, Equatable {
        public let name: String
        public let requests: Int
        public let saved: Double
        public let tokens: Int

        public init(name: String, requests: Int, saved: Double, tokens: Int) {
            self.name = name
            self.requests = requests
            self.saved = saved
            self.tokens = tokens
        }
    }

    public let gatewayStatus: String
    public let offline: Bool
    public let dryRun: Bool
    public let missingKeyCount: Int
    public let modelCount: Int
    public let requests: Int
    public let tokens: Int
    public let realized: Double
    public let baseline: Double
    public let saved: Double
    public let savedPercent: Double
    public let priced: Bool
    public let routes: [Route]
    public let averageDecisionMilliseconds: Double?
    public let updatedAt: Date

    public init(
        gatewayStatus: String,
        offline: Bool,
        dryRun: Bool,
        missingKeyCount: Int,
        modelCount: Int,
        requests: Int,
        tokens: Int,
        realized: Double,
        baseline: Double,
        saved: Double,
        savedPercent: Double,
        priced: Bool,
        routes: [Route],
        averageDecisionMilliseconds: Double?,
        updatedAt: Date)
    {
        self.gatewayStatus = gatewayStatus
        self.offline = offline
        self.dryRun = dryRun
        self.missingKeyCount = missingKeyCount
        self.modelCount = modelCount
        self.requests = requests
        self.tokens = tokens
        self.realized = realized
        self.baseline = baseline
        self.saved = saved
        self.savedPercent = savedPercent
        self.priced = priced
        self.routes = routes
        self.averageDecisionMilliseconds = averageDecisionMilliseconds
        self.updatedAt = updatedAt
    }
}
