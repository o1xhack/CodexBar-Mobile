import CodexBarSync
import Foundation
import SwiftUI
import Testing
@testable import CodexBarMobile

@Suite("Cost share and provider contribution data")
struct CostShareServiceTests {
    private static let tolerance = 0.001

    private func provider(
        id: String,
        name: String,
        sessionTokens: Int? = nil,
        thirtyDayCost: Double? = nil,
        thirtyDayTokens: Int? = nil,
        historyDays: Int? = nil,
        daily: [SyncDailyPoint] = []
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: sessionTokens,
                last30DaysCostUSD: thirtyDayCost,
                last30DaysTokens: thirtyDayTokens,
                daily: daily,
                historyDays: historyDays))
    }

    private func day(daysAgo: Int, cost: Double, tokens: Int) -> CostDashboardInsights.DailyPoint {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        let formatter = SyncCostSummary.iso8601DayKeyFormatter()
        return CostDashboardInsights.DailyPoint(
            dayKey: formatter.string(from: date),
            date: date,
            costUSD: cost,
            totalTokens: tokens)
    }

    private func summaryDay(
        daysAgo: Int,
        cost: Double,
        tokens: Int,
        models: [SyncCostBreakdown]
    ) -> SyncDailyPoint {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        let formatter = SyncCostSummary.iso8601DayKeyFormatter()
        return SyncDailyPoint(
            dayKey: formatter.string(from: date),
            costUSD: cost,
            totalTokens: tokens,
            modelBreakdowns: models)
    }

    @Test("Provider Share filters zero-spend rows but keeps spend totals intact")
    func providerShareFiltersZeroSpendRows() {
        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "codex", name: "Codex"),
            thirtyDayCost: 10,
            todayCost: 1,
            thirtyDayTokens: 1_000,
            todayTokens: 100,
            dailyPoints: [])
        let openai = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "openai", name: "OpenAI"),
            thirtyDayCost: 0,
            todayCost: 0,
            thirtyDayTokens: 0,
            todayTokens: 0,
            dailyPoints: [])
        let insights = CostDashboardInsights(
            providerRows: [codex, openai],
            dailyPoints: [],
            modelRows: [],
            serviceRows: [],
            budgetRows: [])

        #expect(insights.providerRows.count == 2)
        #expect(insights.spendProviderRows.map(\.provider.providerID) == ["codex"])
        #expect(abs(insights.total30DayCost - 10) < Self.tolerance)
    }

    @Test("Share card uses provider daily points for exact 7-day shares")
    func shareCardUsesExactWeeklyProviderCosts() {
        let codexToday = self.day(daysAgo: 0, cost: 10, tokens: 100)
        let codexYesterday = self.day(daysAgo: 1, cost: 30, tokens: 300)
        let codexOlder = self.day(daysAgo: 8, cost: 60, tokens: 600)
        let claudeToday = self.day(daysAgo: 0, cost: 5, tokens: 50)
        let claudeYesterday = self.day(daysAgo: 1, cost: 5, tokens: 50)
        let claudeOlder = self.day(daysAgo: 8, cost: 90, tokens: 900)

        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "codex", name: "Codex"),
            thirtyDayCost: 100,
            todayCost: 10,
            thirtyDayTokens: 1_000,
            todayTokens: 100,
            dailyPoints: [codexToday, codexYesterday, codexOlder])
        let claude = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "claude", name: "Claude"),
            thirtyDayCost: 100,
            todayCost: 5,
            thirtyDayTokens: 1_000,
            todayTokens: 50,
            dailyPoints: [claudeToday, claudeYesterday, claudeOlder])
        let insights = CostDashboardInsights(
            providerRows: [codex, claude],
            dailyPoints: [
                self.day(daysAgo: 0, cost: 15, tokens: 150),
                self.day(daysAgo: 1, cost: 35, tokens: 350),
                self.day(daysAgo: 8, cost: 150, tokens: 1_500),
            ],
            modelRows: [],
            serviceRows: [],
            budgetRows: [])

        let weekly = ShareCardData(insights: insights, period: .week)
        let codexShare = weekly.providers.first { $0.name == "Codex" }
        let claudeShare = weekly.providers.first { $0.name == "Claude" }

        #expect(abs(weekly.totalCost - 50) < Self.tolerance)
        #expect(abs((codexShare?.cost ?? 0) - 40) < Self.tolerance)
        #expect(abs((claudeShare?.cost ?? 0) - 10) < Self.tolerance)
        #expect(abs((codexShare?.share ?? 0) - 0.8) < Self.tolerance)
        #expect(abs((claudeShare?.share ?? 0) - 0.2) < Self.tolerance)
    }

    @Test("Share card 30-day period caps wider CWL insights to the last 30 days")
    func shareCardMonthCapsWiderLedgerWindow() {
        let codexToday = self.day(daysAgo: 0, cost: 10, tokens: 100)
        let codexDay29 = self.day(daysAgo: 29, cost: 20, tokens: 200)
        let codexDay30 = self.day(daysAgo: 30, cost: 100, tokens: 1_000)
        let claudeDay30 = self.day(daysAgo: 30, cost: 50, tokens: 500)

        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "codex", name: "Codex"),
            thirtyDayCost: 130,
            todayCost: 10,
            thirtyDayTokens: 1_300,
            todayTokens: 100,
            dailyPoints: [codexToday, codexDay29, codexDay30])
        let claude = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "claude", name: "Claude"),
            thirtyDayCost: 50,
            todayCost: 0,
            thirtyDayTokens: 500,
            todayTokens: 0,
            dailyPoints: [claudeDay30])
        let insights = CostDashboardInsights(
            providerRows: [codex, claude],
            dailyPoints: [
                self.day(daysAgo: 0, cost: 10, tokens: 100),
                self.day(daysAgo: 29, cost: 20, tokens: 200),
                self.day(daysAgo: 30, cost: 150, tokens: 1_500),
            ],
            modelRows: [],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 90)

        let monthly = ShareCardData(insights: insights, period: .month)
        let codexShare = monthly.providers.first { $0.name == "Codex" }

        #expect(abs(monthly.totalCost - 30) < Self.tolerance)
        #expect(monthly.totalTokens == 300)
        #expect(monthly.activeDays == 2)
        #expect(monthly.providers.count == 1)
        #expect(abs((codexShare?.cost ?? 0) - 30) < Self.tolerance)
        #expect(monthly.dailyBars.count == 2)
    }

    @Test("Share card 30-day period caps top models to the same window")
    func shareCardMonthCapsTopModelsToThirtyDays() {
        let recentModel = SyncCostBreakdown(label: "recent-model", costUSD: 3)
        let oldModel = SyncCostBreakdown(label: "old-model", costUSD: 9)
        let recentSummaryDay = self.summaryDay(
            daysAgo: 0,
            cost: 3,
            tokens: 300,
            models: [recentModel])
        let oldSummaryDay = self.summaryDay(
            daysAgo: 45,
            cost: 9,
            tokens: 900,
            models: [oldModel])
        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "codex",
                name: "Codex",
                daily: [recentSummaryDay, oldSummaryDay]),
            thirtyDayCost: 12,
            todayCost: 3,
            thirtyDayTokens: 1_200,
            todayTokens: 300,
            dailyPoints: [
                self.day(daysAgo: 0, cost: 3, tokens: 300),
                self.day(daysAgo: 45, cost: 9, tokens: 900),
            ])
        let insights = CostDashboardInsights(
            providerRows: [codex],
            dailyPoints: [
                self.day(daysAgo: 0, cost: 3, tokens: 300),
                self.day(daysAgo: 45, cost: 9, tokens: 900),
            ],
            modelRows: [
                CostBreakdownRow(label: "old-model", amountUSD: 9, subtitle: nil, color: .blue),
                CostBreakdownRow(label: "recent-model", amountUSD: 3, subtitle: nil, color: .green),
            ],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 90)

        let monthly = ShareCardData(insights: insights, period: .month)

        #expect(monthly.topModels.map(\.label) == ["recent-model"])
        #expect(abs((monthly.topModels.first?.cost ?? 0) - 3) < Self.tolerance)
    }

    @Test("Share card 30-day period preserves summary-only provider costs")
    func shareCardMonthPreservesSummaryOnlyProviderCosts() {
        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "codex",
                name: "Codex",
                thirtyDayCost: 42,
                thirtyDayTokens: 4_200,
                historyDays: 30),
            thirtyDayCost: 42,
            todayCost: 0,
            thirtyDayTokens: 4_200,
            todayTokens: 0,
            dailyPoints: [])
        let claude = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "claude",
                name: "Claude",
                thirtyDayCost: 8,
                thirtyDayTokens: 800,
                historyDays: 30),
            thirtyDayCost: 8,
            todayCost: 0,
            thirtyDayTokens: 800,
            todayTokens: 0,
            dailyPoints: [])
        let insights = CostDashboardInsights(
            providerRows: [codex, claude],
            dailyPoints: [],
            modelRows: [],
            serviceRows: [],
            budgetRows: [])

        let monthly = ShareCardData(insights: insights, period: .month)
        let codexShare = monthly.providers.first { $0.name == "Codex" }
        let claudeShare = monthly.providers.first { $0.name == "Claude" }

        #expect(abs(monthly.totalCost - 50) < Self.tolerance)
        #expect(monthly.totalTokens == 5_000)
        #expect(monthly.providers.count == 2)
        #expect(abs((codexShare?.cost ?? 0) - 42) < Self.tolerance)
        #expect(abs((claudeShare?.cost ?? 0) - 8) < Self.tolerance)
        #expect(abs((codexShare?.share ?? 0) - 0.84) < Self.tolerance)
        #expect(abs((claudeShare?.share ?? 0) - 0.16) < Self.tolerance)
    }

    @Test("Share card Today tokens use resolved daily totals, not stale session tokens")
    func shareCardTodayTokensUseResolvedDailyTotals() {
        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "codex", name: "Codex", sessionTokens: 999_999),
            thirtyDayCost: 10,
            todayCost: 2,
            thirtyDayTokens: 1_000,
            todayTokens: 123,
            dailyPoints: [self.day(daysAgo: 0, cost: 2, tokens: 123)])
        let insights = CostDashboardInsights(
            providerRows: [codex],
            dailyPoints: [self.day(daysAgo: 0, cost: 2, tokens: 123)],
            modelRows: [],
            serviceRows: [],
            budgetRows: [])

        let today = ShareCardData(insights: insights, period: .today)

        #expect(today.totalTokens == 123)
    }
}
