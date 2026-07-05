import Foundation

/// CrossModel wallet balance plus usage windows for iCloud sync.
///
/// Added for iOS 1.17.0 / Mac 0.39.0.1 as an optional field on
/// `ProviderUsageSnapshot`. CrossModel upstream data does not map to the
/// generic rate-window or provider-budget shapes, so this preserves the
/// provider's actual balance and spend metrics without changing the wire
/// schema version.
public struct SyncCrossModelUsage: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public let cost: Double
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int
        public let requestCount: Int
        public let successCount: Int

        public init(
            cost: Double,
            promptTokens: Int,
            completionTokens: Int,
            totalTokens: Int,
            requestCount: Int,
            successCount: Int)
        {
            self.cost = cost
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
            self.requestCount = requestCount
            self.successCount = successCount
        }
    }

    public let currency: String
    public let balance: Double
    public let uncollected: Double
    public let daily: Window?
    public let weekly: Window?
    public let monthly: Window?
    public let updatedAt: Date

    public init(
        currency: String,
        balance: Double,
        uncollected: Double,
        daily: Window?,
        weekly: Window?,
        monthly: Window?,
        updatedAt: Date)
    {
        self.currency = currency
        self.balance = balance
        self.uncollected = uncollected
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
        self.updatedAt = updatedAt
    }
}
