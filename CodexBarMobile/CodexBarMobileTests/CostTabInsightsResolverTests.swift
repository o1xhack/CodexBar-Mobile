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
            localHistoryClearedAt: self.now.addingTimeInterval(60))

        #expect(insights == nil)
    }

    @Test("Missing ledger after clear does not fall back to stale synced cost summary")
    func missingClearedLedgerStaysEmpty() {
        let snapshot = SyncedUsageSnapshot(
            providers: [self.provider(cost: 12, tokens: 1_200)],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: nil,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: self.now.addingTimeInterval(60),
            ledgerWindowDays: 90)

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
            localHistoryClearedAt: nil)

        #expect(insights?.total30DayCost == 12)
    }

    @Test("Empty ledger after clear preserves synced budget rows")
    func emptyClearedLedgerPreservesBudgets() {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(
                    cost: 12,
                    tokens: 1_200,
                    budget: SyncBudgetSnapshot(
                        usedAmount: 40,
                        limitAmount: 100,
                        currencyCode: "USD",
                        period: "Monthly",
                        resetsAt: nil)),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: self.now.addingTimeInterval(60))

        #expect(insights?.total30DayCost == 0)
        #expect(insights?.providerRows.isEmpty == true)
        #expect(insights?.budgetRows.count == 1)
    }

    @Test("Partial ledger after clear does not append missing providers from stale snapshots")
    func partialClearedLedgerDoesNotAppendMissingSnapshotProviders() {
        let refreshed = self.provider(id: "codex", name: "Codex", cost: 8, tokens: 800)
        let stale = self.provider(id: "claude", name: "Claude", cost: 12, tokens: 1_200)
        let snapshot = SyncedUsageSnapshot(
            providers: [refreshed, stale],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let aggregation = CostLedgerAggregation(
            windowDays: 90,
            totalCostUSD: 8,
            totalTokens: 800,
            activeDayCount: 1,
            providerRollups: [
                "codex|_": CostLedgerProviderRollup(
                    providerID: "codex",
                    accountEmail: nil,
                    totalCostUSD: 8,
                    totalTokens: 800,
                    dailyPoints: [
                        SyncDailyPoint(
                            dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
                            costUSD: 8,
                            totalTokens: 800,
                            modelBreakdowns: [],
                            serviceBreakdowns: [],
                            isEstimated: false),
                    ],
                    modelBreakdowns: [],
                    serviceBreakdowns: []),
            ],
            dailyPoints: [
                SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
                    costUSD: 8,
                    totalTokens: 800,
                    modelBreakdowns: [],
                    serviceBreakdowns: [],
                    isEstimated: false),
            ],
            modelMix: [],
            serviceMix: [])

        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: self.now.addingTimeInterval(60))

        #expect(insights?.total30DayCost == 8)
        #expect(insights?.providerRows.map(\.provider.providerID) == ["codex"])
    }

    @Test("Partial ledger fallback contributes to daily and breakdown aggregates")
    func partialLedgerFallbackContributesToAllAggregates() throws {
        let codexDay = self.syncDay(
            cost: 8,
            tokens: 800,
            models: [SyncCostBreakdown(label: "codex-model", costUSD: 8)],
            services: [SyncCostBreakdown(label: "codex-run", costUSD: 8)])
        let claude = self.provider(
            id: "claude",
            name: "Claude",
            cost: 12,
            tokens: 1_200,
            models: [SyncCostBreakdown(label: "claude-model", costUSD: 12)],
            services: [SyncCostBreakdown(label: "claude-api", costUSD: 12)])
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(id: "codex", name: "Codex", cost: 8, tokens: 800),
                claude,
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let aggregation = CostLedgerAggregation(
            windowDays: 90,
            totalCostUSD: 8,
            totalTokens: 800,
            activeDayCount: 1,
            providerRollups: [
                "codex|_": CostLedgerProviderRollup(
                    providerID: "codex",
                    accountEmail: nil,
                    totalCostUSD: 8,
                    totalTokens: 800,
                    dailyPoints: [codexDay],
                    modelBreakdowns: [SyncCostBreakdown(label: "codex-model", costUSD: 8)],
                    serviceBreakdowns: [SyncCostBreakdown(label: "codex-run", costUSD: 8)]),
            ],
            dailyPoints: [codexDay],
            modelMix: [SyncCostBreakdown(label: "codex-model", costUSD: 8)],
            serviceMix: [SyncCostBreakdown(label: "codex-run", costUSD: 8)])

        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: nil))

        #expect(insights.total30DayCost == 20)
        #expect(insights.dailyPoints.reduce(0) { $0 + $1.costUSD } == 20)
        #expect(Set(insights.modelRows.map(\.label)) == ["codex-model", "claude-model"])
        #expect(insights.modelRows.reduce(0) { $0 + $1.amountUSD } == 20)
        #expect(Set(insights.serviceRows.map(\.label)) == ["codex-run", "claude-api"])
        #expect(insights.serviceRows.reduce(0) { $0 + $1.amountUSD } == 20)
    }

    @Test("Summary-only snapshot after clear can still fill missing ledger provider")
    func freshSummaryOnlySnapshotAfterClearCanFallback() {
        let clearTime = self.now
        let freshSummaryOnly = self.provider(
            id: "claude",
            name: "Claude",
            cost: 14,
            tokens: 1_400,
            lastUpdated: clearTime.addingTimeInterval(60),
            includeDaily: false)
        let snapshot = SyncedUsageSnapshot(
            providers: [freshSummaryOnly],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: clearTime)

        #expect(insights?.total30DayCost == 14)
        #expect(insights?.providerRows.map(\.provider.providerID) == ["claude"])
        #expect(insights?.dailyPoints.isEmpty == true)
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

    private func provider(
        id: String = "codex",
        name: String = "Codex",
        cost: Double,
        tokens: Int,
        budget: SyncBudgetSnapshot? = nil,
        lastUpdated: Date? = nil,
        includeDaily: Bool = true) -> ProviderUsageSnapshot
    {
        self.provider(
            id: id,
            name: name,
            cost: cost,
            tokens: tokens,
            budget: budget,
            lastUpdated: lastUpdated,
            includeDaily: includeDaily,
            models: [],
            services: [])
    }

    private func provider(
        id: String,
        name: String,
        cost: Double,
        tokens: Int,
        budget: SyncBudgetSnapshot? = nil,
        lastUpdated: Date? = nil,
        includeDaily: Bool = true,
        models: [SyncCostBreakdown],
        services: [SyncCostBreakdown]) -> ProviderUsageSnapshot
    {
        let daily = self.syncDay(
            cost: cost,
            tokens: tokens,
            models: models,
            services: services)
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated ?? self.now,
            costSummary: SyncCostSummary(
                sessionCostUSD: cost,
                sessionTokens: tokens,
                last30DaysCostUSD: cost,
                last30DaysTokens: tokens,
                daily: includeDaily ? [daily] : [],
                isEstimated: false,
                historyDays: 30),
            budget: budget)
    }

    private func syncDay(
        cost: Double,
        tokens: Int,
        models: [SyncCostBreakdown],
        services: [SyncCostBreakdown]) -> SyncDailyPoint
    {
        SyncDailyPoint(
            dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
            costUSD: cost,
            totalTokens: tokens,
            modelBreakdowns: models,
            serviceBreakdowns: services,
            isEstimated: false)
    }
}
