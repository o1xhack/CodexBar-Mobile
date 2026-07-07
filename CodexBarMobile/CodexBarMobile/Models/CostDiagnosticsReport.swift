import CodexBarSync
import Foundation

enum CostDiagnosticsDataSource: Equatable {
    case localLedger
    case syncedSnapshots
    case syncedSnapshotsAfterLedgerFailure
}

enum CostDiagnosticsMergeRule: Equatable {
    case sumActiveDevices
    case latestAccountDay
}

enum CostDiagnosticsStatus: Equatable {
    case pass
    case warning
    case unavailable
}

enum CostDiagnosticsCheckKind: String, Equatable {
    case providerShare
    case dailySpend
    case modelMix
    case serviceMix
    case shareCard
}

enum CostDiagnosticsCheckDetail: Equatable {
    case matchesOverviewTotal
    case difference(Double)
    case covers(Double)
    case noCostTotal
    case noBreakdownData
    case usesExactProviderDailyPoints
    case sevenDayProviderDifference(Double)
}

struct CostDiagnosticsProviderRule: Identifiable, Equatable {
    let ordinal: Int
    let providerID: String
    let providerName: String
    let accountEmail: String?
    let rule: CostDiagnosticsMergeRule

    var id: String {
        "\(self.providerID)|\(self.accountEmail ?? "_")|\(self.ordinal)"
    }
}

struct CostDiagnosticsCheck: Identifiable, Equatable {
    let kind: CostDiagnosticsCheckKind
    let detail: CostDiagnosticsCheckDetail
    let status: CostDiagnosticsStatus

    var id: String {
        self.kind.rawValue
    }
}

struct CostDiagnosticsReport: Equatable {
    let dataSource: CostDiagnosticsDataSource
    let windowDays: Int
    let totalCostUSD: Double
    let todayCostUSD: Double
    let totalTokens: Int
    let activeDayCount: Int
    let topDriverName: String?
    let topDriverCostUSD: Double?
    let rawDeviceCount: Int
    let activeDeviceCount: Int
    let excludedDeviceCount: Int
    let providerRules: [CostDiagnosticsProviderRule]
    let checks: [CostDiagnosticsCheck]

    static func make(
        insights: CostDashboardInsights,
        snapshot: SyncedUsageSnapshot,
        rawDeviceSnapshots: [SyncedUsageSnapshot],
        activeDeviceSnapshots: [SyncedUsageSnapshot],
        cwlEnabled: Bool,
        cwlWindowDays: Int,
        ledgerAvailable: Bool) -> CostDiagnosticsReport
    {
        let dataSource: CostDiagnosticsDataSource = if cwlEnabled {
            ledgerAvailable ? .localLedger : .syncedSnapshotsAfterLedgerFailure
        } else {
            .syncedSnapshots
        }

        let providersWithCost = MockProviderDetector.filteredProviders(from: snapshot)
            .filter { $0.costSummary != nil }
            .sorted { lhs, rhs in
                if lhs.providerName == rhs.providerName {
                    return (lhs.accountEmail ?? "") < (rhs.accountEmail ?? "")
                }
                return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
            }
        let providerRules = providersWithCost
            .enumerated()
            .map { offset, provider in
                CostDiagnosticsProviderRule(
                    ordinal: offset,
                    providerID: provider.providerID,
                    providerName: provider.providerName,
                    accountEmail: provider.accountEmail,
                    rule: ProviderSnapshotMerger.usesLocalCostMerge(providerID: provider.providerID)
                        ? .sumActiveDevices
                        : .latestAccountDay)
            }

        let totalCost = insights.total30DayCost
        let providerShareTotal = insights.spendProviderRows.reduce(0) { $0 + $1.thirtyDayCost }
        let dailyTotal = insights.dailyPoints.reduce(0) { $0 + $1.costUSD }
        let modelTotal = insights.modelRows.reduce(0) { $0 + $1.amountUSD }
        let serviceTotal = insights.serviceRows.reduce(0) { $0 + $1.amountUSD }
        let weeklyShareCard = ShareCardData(insights: insights, period: .week)
        let monthlyShareCard = ShareCardData(insights: insights, period: .month)

        let checks = [
            Self.moneyCheck(
                kind: .providerShare,
                expected: totalCost,
                actual: providerShareTotal,
                passDetail: .matchesOverviewTotal),
            Self.moneyCheck(
                kind: .dailySpend,
                expected: totalCost,
                actual: dailyTotal,
                passDetail: .matchesOverviewTotal),
            Self.coverageCheck(
                kind: .modelMix,
                total: totalCost,
                covered: modelTotal),
            Self.coverageCheck(
                kind: .serviceMix,
                total: totalCost,
                covered: serviceTotal),
            Self.shareCardCheck(
                weekly: weeklyShareCard,
                monthly: monthlyShareCard,
                overviewTotal: totalCost),
        ]

        return CostDiagnosticsReport(
            dataSource: dataSource,
            windowDays: insights.historyDays ?? cwlWindowDays,
            totalCostUSD: totalCost,
            todayCostUSD: insights.totalTodayCost,
            totalTokens: insights.total30DayTokens,
            activeDayCount: insights.activeDayCount,
            topDriverName: insights.topProvider?.provider.providerName,
            topDriverCostUSD: insights.topProvider?.thirtyDayCost,
            rawDeviceCount: rawDeviceSnapshots.count,
            activeDeviceCount: activeDeviceSnapshots.count,
            excludedDeviceCount: max(0, rawDeviceSnapshots.count - activeDeviceSnapshots.count),
            providerRules: providerRules,
            checks: checks)
    }

    private static func moneyCheck(
        kind: CostDiagnosticsCheckKind,
        expected: Double,
        actual: Double,
        passDetail: CostDiagnosticsCheckDetail) -> CostDiagnosticsCheck
    {
        let delta = abs(expected - actual)
        if delta < 0.01 {
            return CostDiagnosticsCheck(kind: kind, detail: passDetail, status: .pass)
        }
        return CostDiagnosticsCheck(
            kind: kind,
            detail: .difference(delta),
            status: .warning)
    }

    private static func coverageCheck(
        kind: CostDiagnosticsCheckKind,
        total: Double,
        covered: Double) -> CostDiagnosticsCheck
    {
        guard total > 0 else {
            return CostDiagnosticsCheck(kind: kind, detail: .noCostTotal, status: .unavailable)
        }
        if covered <= 0 {
            return CostDiagnosticsCheck(kind: kind, detail: .noBreakdownData, status: .unavailable)
        }
        let clamped = min(max(covered / total, 0), 1)
        return CostDiagnosticsCheck(
            kind: kind,
            detail: .covers(clamped),
            status: covered <= total + 0.01 ? .pass : .warning)
    }

    private static func shareCardCheck(
        weekly: ShareCardData,
        monthly: ShareCardData,
        overviewTotal: Double) -> CostDiagnosticsCheck
    {
        guard abs(monthly.totalCost - overviewTotal) < 0.01 else {
            return CostDiagnosticsCheck(
                kind: .shareCard,
                detail: .difference(abs(monthly.totalCost - overviewTotal)),
                status: .warning)
        }
        let weeklyProviderTotal = weekly.providers.reduce(0) { $0 + $1.cost }
        guard abs(weeklyProviderTotal - weekly.totalCost) < 0.01 else {
            return CostDiagnosticsCheck(
                kind: .shareCard,
                detail: .sevenDayProviderDifference(abs(weeklyProviderTotal - weekly.totalCost)),
                status: .warning)
        }
        return CostDiagnosticsCheck(
            kind: .shareCard,
            detail: .usesExactProviderDailyPoints,
            status: .pass)
    }
}
