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
