import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Cost tab insight resolver")
struct CostTabInsightsResolverTests {
    private let now = Date()

    @Test("Empty ledger after clear does not fall back to stale synced cost summary")
    func emptyClearedLedgerStaysEmpty() {
        let snapshot = SyncedUsageSnapshot(
            providers: [self.provider(cost: 12, tokens: 1_200)],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            clearedLocalHistory: true)

        #expect(insights == nil)
    }

    @Test("Empty ledger without clear falls back to synced snapshot")
    func emptyUnclearedLedgerFallsBackToSnapshot() {
        let snapshot = SyncedUsageSnapshot(
            providers: [self.provider(cost: 12, tokens: 1_200)],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            clearedLocalHistory: false)

        #expect(insights?.total30DayCost == 12)
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

    private func provider(cost: Double, tokens: Int) -> ProviderUsageSnapshot {
        let daily = SyncDailyPoint(
            dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
            costUSD: cost,
            totalTokens: tokens,
            modelBreakdowns: [],
            serviceBreakdowns: [],
            isEstimated: false)
        return ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
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
