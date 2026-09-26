import Foundation

public struct LLMProxyUsageSnapshot: Codable, Sendable, Equatable {
    public let providerCount: Int
    public let credentialCount: Int
    public let activeCredentialCount: Int
    public let exhaustedCredentialCount: Int
    public let totalRequests: Int
    public let totalTokens: Int
    public let approximateCostUSD: Double?
    public let minimumRemainingPercent: Double?
    public let nextResetAt: Date?
    public let topProviders: [ProviderSummary]
    public let updatedAt: Date

    public struct ProviderSummary: Codable, Sendable, Equatable {
        public let name: String
        public let requests: Int
        public let tokens: Int
        public let approximateCostUSD: Double?
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let used = self.minimumRemainingPercent.map { max(0, min(100, 100 - $0)) }
        let windows = self.topProviders.prefix(3).map { provider in
            NamedRateWindow(
                id: provider.name,
                title: provider.name,
                window: RateWindow(
                    usedPercent: 0,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: Self.providerSummaryText(provider)))
        }
        return UsageSnapshot(
            primary: used.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: nil,
                    resetsAt: self.nextResetAt,
                    resetDescription: nil)
            },
            secondary: RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "\(Self.formatInteger(self.totalRequests)) requests"),
            tertiary: RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "\(Self.formatInteger(self.totalTokens)) tokens"),
            extraRateWindows: windows.isEmpty ? nil : Array(windows),
            providerCost: self.approximateCostUSD.map {
                ProviderCostSnapshot(
                    used: $0,
                    limit: 0,
                    currencyCode: "USD",
                    period: "Approx. spend",
                    resetsAt: self.nextResetAt,
                    updatedAt: self.updatedAt)
            },
            llmProxyUsage: self,
            updatedAt: self.updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .llmproxy,
                accountEmail: nil,
                accountOrganization: "\(self.activeCredentialCount)/\(self.credentialCount) active keys",
                loginMethod: "quota-stats"))
    }

    private static func providerSummaryText(_ provider: ProviderSummary) -> String {
        var pieces = [
            "\(Self.formatInteger(provider.requests)) req",
            "\(Self.formatInteger(provider.tokens)) tok",
        ]
        if let cost = provider.approximateCostUSD {
            pieces.append(UsageFormatter.usdString(cost))
        }
        return pieces.joined(separator: " · ")
    }

    private static func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
