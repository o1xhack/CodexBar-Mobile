import Foundation

public struct FireworksUsageSnapshot: Sendable {
    public let summary: FireworksUsageSummary
    public let accountSlug: String
    public let accountSlugWasDiscovered: Bool

    public init(
        summary: FireworksUsageSummary,
        accountSlug: String = "",
        accountSlugWasDiscovered: Bool = false)
    {
        self.summary = summary
        self.accountSlug = accountSlug
        self.accountSlugWasDiscovered = accountSlugWasDiscovered
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        self.summary.toUsageSnapshot()
    }
}

public struct FireworksUsageSummary: Sendable {
    /// Sum of rated line items from `GET /v1/accounts/{slug}/billing/summary` for the
    /// last 30 days. Fireworks exposes no credit-balance API, so spend is the only
    /// usable usage signal.
    public let last30DaysSpend: Double?
    public let currencyCode: String?
    public let updatedAt: Date

    public init(
        last30DaysSpend: Double?,
        currencyCode: String?,
        updatedAt: Date)
    {
        self.last30DaysSpend = last30DaysSpend
        self.currencyCode = currencyCode
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        // Fireworks is prepaid with no quota windows, so no RateWindows are synthesized.
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            tertiary: nil,
            providerCost: self.last30DaysSpend.flatMap { spend in
                self.currencyCode.map { code in
                    ProviderCostSnapshot(
                        used: spend,
                        limit: 0,
                        currencyCode: code,
                        period: "Last 30 days",
                        updatedAt: self.updatedAt)
                }
            },
            updatedAt: self.updatedAt,
            identity: nil)
    }
}
