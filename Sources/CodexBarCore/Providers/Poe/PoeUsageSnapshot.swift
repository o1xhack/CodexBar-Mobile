import Foundation

public struct PoeUsageSnapshot: Sendable {
    public let currentPointBalance: Double?
    public let history: PoeUsageHistorySnapshot?
    public let updatedAt: Date

    public init(
        currentPointBalance: Double? = nil,
        history: PoeUsageHistorySnapshot? = nil,
        updatedAt: Date = Date())
    {
        self.currentPointBalance = currentPointBalance
        self.history = history
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let identity = ProviderIdentitySnapshot(
            providerID: .poe,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: self.balanceLabel)

        let windows = self.genericPointWindows()

        return UsageSnapshot(
            primary: windows.primary,
            secondary: windows.secondary,
            tertiary: nil,
            extraRateWindows: windows.extraRateWindows.isEmpty ? nil : windows.extraRateWindows,
            providerCost: nil,
            poeUsage: self.history,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private var balanceLabel: String? {
        guard let balance = self.currentPointBalance, balance.isFinite else { return nil }
        return "Balance: \(Self.compactNumber(balance)) points"
    }

    private func genericPointWindows() -> (
        primary: RateWindow?,
        secondary: RateWindow?,
        extraRateWindows: [NamedRateWindow])
    {
        var primary = self.currentPointBalance.flatMap { balance -> RateWindow? in
            guard balance.isFinite else { return nil }
            return RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Balance: \(Self.compactNumber(balance)) points")
        }

        var secondary: RateWindow?
        var extraRateWindows: [NamedRateWindow] = []

        if let history, !history.daily.isEmpty {
            let last30 = Self.historyWindow(summary: history.last30Days, label: "30d", windowMinutes: 43200)
            if primary == nil {
                primary = last30
            } else {
                secondary = last30
            }
            extraRateWindows.append(NamedRateWindow(
                id: "poe.today",
                title: "Today",
                window: Self.historyWindow(summary: history.latestDay, label: "Today", windowMinutes: 1440),
                usageKnown: false))
            extraRateWindows.append(NamedRateWindow(
                id: "poe.7d",
                title: "7d",
                window: Self.historyWindow(summary: history.last7Days, label: "7d", windowMinutes: 10080),
                usageKnown: false))
        }

        return (primary, secondary, extraRateWindows)
    }

    private static func historyWindow(
        summary: PoeUsageHistorySnapshot.Summary,
        label: String,
        windowMinutes: Int) -> RateWindow
    {
        let requests = summary.requests == 1 ? "1 request" : "\(summary.requests) requests"
        let resetDescription = "\(label): \(Self.compactNumber(summary.points)) points · \(requests)"
        return RateWindow(
            usedPercent: 0,
            windowMinutes: windowMinutes,
            resetsAt: nil,
            resetDescription: resetDescription)
    }

    static func compactNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = value >= 1000 ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}
