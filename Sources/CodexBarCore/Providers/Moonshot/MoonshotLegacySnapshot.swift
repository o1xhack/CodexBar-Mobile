import Foundation

public struct MoonshotUsageSnapshot: Sendable {
    public let summary: MoonshotUsageSummary

    public init(summary: MoonshotUsageSummary) {
        self.summary = summary
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        self.summary.toUsageSnapshot()
    }
}

public struct MoonshotUsageSummary: Sendable {
    public let availableBalance: Double
    public let voucherBalance: Double
    public let cashBalance: Double
    public let updatedAt: Date
    public let region: MoonshotRegion

    public init(
        availableBalance: Double,
        voucherBalance: Double,
        cashBalance: Double,
        updatedAt: Date,
        region: MoonshotRegion = .international)
    {
        self.availableBalance = availableBalance
        self.voucherBalance = voucherBalance
        self.cashBalance = cashBalance
        self.updatedAt = updatedAt
        self.region = region
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let balance = self.formatCurrency(self.availableBalance)
        let loginMethod: String
        if self.cashBalance < 0 {
            let deficit = self.formatCurrency(abs(self.cashBalance))
            loginMethod = "Balance: \(balance) · \(deficit) in deficit"
        } else {
            loginMethod = "Balance: \(balance)"
        }
        let identity = ProviderIdentitySnapshot(
            providerID: .moonshot,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: loginMethod)
        return UsageSnapshot(
            primary: nil,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private func formatCurrency(_ value: Double) -> String {
        self.region == .china
            ? UsageFormatter.currencyString(value, currencyCode: "CNY")
            : UsageFormatter.usdString(value)
    }
}
