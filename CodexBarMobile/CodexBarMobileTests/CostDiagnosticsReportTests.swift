import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Cost Diagnostics report")
@MainActor
struct CostDiagnosticsReportTests {
    private let now = Date()

    @Test("Report identifies local-cost and account-level provider rules")
    func providerRulesUseCorrectMergeSemantics() throws {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(id: "codex", name: "Codex", cost: 4, tokens: 400),
                self.provider(id: "openai", name: "OpenAI", cost: 6, tokens: 600),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostDashboardInsights(snapshot: snapshot)

        let report = CostDiagnosticsReport.make(
            insights: insights,
            snapshot: snapshot,
            rawDeviceSnapshots: [snapshot],
            activeDeviceSnapshots: [snapshot],
            cwlEnabled: true,
            cwlWindowDays: 90,
            ledgerAvailable: true)

        let rules = Dictionary(uniqueKeysWithValues: report.providerRules.map { ($0.providerID, $0.rule) })
        #expect(rules["codex"] == .sumActiveDevices)
        #expect(rules["openai"] == .latestAccountDay)
        #expect(report.dataSource == .localLedger)
        #expect(report.windowDays == 30)
    }

    @Test("Report reconciles provider share and share cards against Overview")
    func reconciliationPassesForConsistentCostData() throws {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(id: "codex", name: "Codex", cost: 4, tokens: 400),
                self.provider(id: "claude", name: "Claude", cost: 6, tokens: 600),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostDashboardInsights(snapshot: snapshot)

        let report = CostDiagnosticsReport.make(
            insights: insights,
            snapshot: snapshot,
            rawDeviceSnapshots: [snapshot],
            activeDeviceSnapshots: [snapshot],
            cwlEnabled: false,
            cwlWindowDays: 90,
            ledgerAvailable: false)

        #expect(report.totalCostUSD == 10)
        #expect(report.todayCostUSD == 10)
        #expect(report.activeDeviceCount == 1)
        #expect(report.excludedDeviceCount == 0)
        #expect(report.checks.first(where: { $0.kind == .providerShare })?.status == .pass)
        #expect(report.checks.first(where: { $0.kind == .shareCard })?.status == .pass)
    }

    @Test("Report provider rules keep unique row IDs for duplicate provider rows")
    func providerRuleIDsStayUniqueForDuplicateProviderRows() throws {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(id: "openai", name: "OpenAI", cost: 1, tokens: 100),
                self.provider(id: "openai", name: "OpenAI", cost: 2, tokens: 200),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostDashboardInsights(snapshot: snapshot)

        let report = CostDiagnosticsReport.make(
            insights: insights,
            snapshot: snapshot,
            rawDeviceSnapshots: [snapshot],
            activeDeviceSnapshots: [snapshot],
            cwlEnabled: true,
            cwlWindowDays: 90,
            ledgerAvailable: true)

        #expect(report.providerRules.count == 2)
        #expect(Set(report.providerRules.map(\.id)).count == report.providerRules.count)
    }

    @Test("Report does not compare 90-day overview against 30-day share card")
    func shareCardCheckPassesForWiderLedgerWindow() throws {
        let oldPoint = self.day(daysAgo: 45, cost: 70, tokens: 7_000)
        let recentPoint = self.day(daysAgo: 3, cost: 30, tokens: 3_000)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.now,
            costSummary: nil)
        let insights = CostDashboardInsights(
            providerRows: [
                CostDashboardInsights.ProviderRow(
                    provider: provider,
                    thirtyDayCost: 100,
                    todayCost: 0,
                    thirtyDayTokens: 10_000,
                    todayTokens: 0,
                    dailyPoints: [oldPoint, recentPoint]),
            ],
            dailyPoints: [oldPoint, recentPoint],
            modelRows: [],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 90)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let report = CostDiagnosticsReport.make(
            insights: insights,
            snapshot: snapshot,
            rawDeviceSnapshots: [snapshot],
            activeDeviceSnapshots: [snapshot],
            cwlEnabled: true,
            cwlWindowDays: 90,
            ledgerAvailable: true)

        #expect(report.totalCostUSD == 100)
        #expect(report.checks.first(where: { $0.kind == .shareCard })?.status == .pass)
    }

    @Test("Diagnostics reuse Cost tab fallback when ledger is empty")
    func diagnosticsReuseCostTabFallbackForEmptyLedger() throws {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(id: "codex", name: "Codex", cost: 12, tokens: 1_200),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let report = try #require(CostDiagnosticsReportResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            rawDeviceSnapshots: [snapshot],
            activeDeviceSnapshots: [snapshot],
            cwlEnabled: true,
            cwlWindowDays: 90,
            localHistoryClearedAt: nil))

        #expect(report.totalCostUSD == 12)
        #expect(report.dataSource == .syncedSnapshotsAfterLedgerFailure)
        #expect(report.providerRules.map(\.providerID) == ["codex"])
    }

    private func day(daysAgo: Int, cost: Double, tokens: Int) -> CostDashboardInsights.DailyPoint {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: self.now) ?? self.now
        return CostDashboardInsights.DailyPoint(
            dayKey: SyncCostSummary.iso8601DayKey(for: date),
            date: date,
            costUSD: cost,
            totalTokens: tokens)
    }

    private func emptyAggregation(windowDays: Int) -> CostLedgerAggregation {
        CostLedgerAggregation(
            windowDays: windowDays,
            totalCostUSD: 0,
            totalTokens: 0,
            activeDayCount: 0,
            providerRollups: [:],
            dailyPoints: [],
            modelMix: [],
            serviceMix: [])
    }

    private func provider(id: String, name: String, cost: Double, tokens: Int) -> ProviderUsageSnapshot {
        let dayKey = SyncCostSummary.iso8601DayKey(for: self.now)
        let daily = SyncDailyPoint(
            dayKey: dayKey,
            costUSD: cost,
            totalTokens: tokens,
            modelBreakdowns: [SyncCostBreakdown(label: "\(name) Model", costUSD: cost)],
            serviceBreakdowns: id == "codex" ? [SyncCostBreakdown(label: "Codex Run", costUSD: cost)] : [],
            isEstimated: false)
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.now,
            costSummary: SyncCostSummary(
                sessionCostUSD: cost,
                sessionTokens: tokens,
                last30DaysCostUSD: cost,
                last30DaysTokens: tokens,
                daily: [daily],
                isEstimated: false,
                historyDays: 30))
    }
}
