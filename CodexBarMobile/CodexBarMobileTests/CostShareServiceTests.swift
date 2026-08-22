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

    private func day(
        daysAgo: Int,
        cost: Double,
        tokens: Int,
        costIsKnown: Bool? = nil,
        models: [SyncCostBreakdown] = [],
        services: [SyncCostBreakdown] = []) -> CostDashboardInsights.DailyPoint
    {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        let formatter = SyncCostSummary.iso8601DayKeyFormatter()
        return CostDashboardInsights.DailyPoint(
            dayKey: formatter.string(from: date),
            date: date,
            costUSD: cost,
            costIsKnown: costIsKnown,
            totalTokens: tokens,
            modelBreakdowns: models,
            serviceBreakdowns: services)
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
        #expect(monthly.dailyBars.count == 30)
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
                self.day(daysAgo: 0, cost: 3, tokens: 300, models: [recentModel]),
                self.day(daysAgo: 45, cost: 9, tokens: 900, models: [oldModel]),
            ])
        let insights = CostDashboardInsights(
            providerRows: [codex],
            dailyPoints: [
                self.day(daysAgo: 0, cost: 3, tokens: 300, models: [recentModel]),
                self.day(daysAgo: 45, cost: 9, tokens: 900, models: [oldModel]),
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

    @Test("Share card preserves ledger model mix when provider summaries are missing")
    func shareCardUsesLedgerModelRowsWhenSummaryBreakdownsAreMissing() {
        let ledgerDay = self.day(
            daysAgo: 0,
            cost: 10,
            tokens: 1_000,
            models: [
                SyncCostBreakdown(label: "gpt-5", costUSD: 7),
                SyncCostBreakdown(label: "gpt-5-mini", costUSD: 3),
            ])
        let codex = CostDashboardInsights.ProviderRow(
            provider: ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(),
                costSummary: nil),
            thirtyDayCost: 10,
            todayCost: 2,
            thirtyDayTokens: 1_000,
            todayTokens: 200,
            dailyPoints: [ledgerDay])
        let insights = CostDashboardInsights(
            providerRows: [codex],
            dailyPoints: [ledgerDay],
            modelRows: [
                CostBreakdownRow(label: "gpt-5", amountUSD: 7, subtitle: nil, color: .blue),
                CostBreakdownRow(label: "gpt-5-mini", amountUSD: 3, subtitle: nil, color: .green),
            ],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 90)

        let monthly = ShareCardData(insights: insights, period: .month)

        #expect(monthly.topModels.map(\.label) == ["gpt-5", "gpt-5-mini"])
        #expect(abs((monthly.topModels.first?.share ?? 0) - 0.7) < Self.tolerance)
    }

    @Test("Share card preserves ledger model mix when summary and ledger-only providers are mixed")
    func shareCardUsesLedgerModelRowsForMixedSummaryAndLedgerProviders() {
        let summaryDay = self.summaryDay(
            daysAgo: 0,
            cost: 4,
            tokens: 400,
            models: [SyncCostBreakdown(label: "summary-model", costUSD: 4)])
        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "codex",
                name: "Codex",
                daily: [summaryDay]),
            thirtyDayCost: 4,
            todayCost: 4,
            thirtyDayTokens: 400,
            todayTokens: 400,
            dailyPoints: [self.day(
                daysAgo: 0,
                cost: 4,
                tokens: 400,
                models: [SyncCostBreakdown(label: "summary-model", costUSD: 4)])])
        let claude = CostDashboardInsights.ProviderRow(
            provider: ProviderUsageSnapshot(
                providerID: "claude",
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(),
                costSummary: nil),
            thirtyDayCost: 6,
            todayCost: 0,
            thirtyDayTokens: 600,
            todayTokens: 0,
            dailyPoints: [self.day(
                daysAgo: 1,
                cost: 6,
                tokens: 600,
                models: [SyncCostBreakdown(label: "ledger-only-model", costUSD: 6)])])
        let insights = CostDashboardInsights(
            providerRows: [codex, claude],
            dailyPoints: [
                self.day(
                    daysAgo: 0,
                    cost: 4,
                    tokens: 400,
                    models: [SyncCostBreakdown(label: "summary-model", costUSD: 4)]),
                self.day(
                    daysAgo: 1,
                    cost: 6,
                    tokens: 600,
                    models: [SyncCostBreakdown(label: "ledger-only-model", costUSD: 6)]),
            ],
            modelRows: [
                CostBreakdownRow(label: "ledger-only-model", amountUSD: 6, subtitle: nil, color: .blue),
                CostBreakdownRow(label: "summary-model", amountUSD: 4, subtitle: nil, color: .green),
            ],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 90)

        let monthly = ShareCardData(insights: insights, period: .month)

        #expect(monthly.topModels.map(\.label) == ["ledger-only-model", "summary-model"])
        #expect(abs((monthly.topModels.first?.cost ?? 0) - 6) < Self.tolerance)
        #expect(abs((monthly.topModels.first?.share ?? 0) - 0.6) < Self.tolerance)
    }

    @Test("Share card model mix stays inside the selected period")
    func shareCardModelMixUsesPeriodScopedDailyBreakdowns() {
        let recentDay = self.day(
            daysAgo: 2,
            cost: 3,
            tokens: 300,
            models: [SyncCostBreakdown(label: "recent-model", costUSD: 3)])
        let oldDay = self.day(
            daysAgo: 45,
            cost: 9,
            tokens: 900,
            models: [SyncCostBreakdown(label: "old-model", costUSD: 9)])
        let codex = CostDashboardInsights.ProviderRow(
            provider: ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(),
                costSummary: nil),
            thirtyDayCost: 12,
            todayCost: 0,
            thirtyDayTokens: 1_200,
            todayTokens: 0,
            dailyPoints: [recentDay, oldDay])
        let insights = CostDashboardInsights(
            providerRows: [codex],
            dailyPoints: [recentDay, oldDay],
            modelRows: [
                CostBreakdownRow(label: "old-model", amountUSD: 9, subtitle: nil, color: .blue),
                CostBreakdownRow(label: "recent-model", amountUSD: 3, subtitle: nil, color: .green),
            ],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 90)

        let weekly = ShareCardData(insights: insights, period: .week)
        let monthly = ShareCardData(insights: insights, period: .month)

        #expect(weekly.topModels.map(\.label) == ["recent-model"])
        #expect(monthly.topModels.map(\.label) == ["recent-model"])
        #expect(abs((monthly.topModels.first?.cost ?? 0) - 3) < Self.tolerance)
    }

    @Test("Share card summary daily bars include ledger-only provider days")
    func shareCardSummaryDailyBarsIncludeLedgerOnlyProviderDays() {
        let summaryDay = self.summaryDay(
            daysAgo: 0,
            cost: 30,
            tokens: 3_000,
            models: [])
        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "codex",
                name: "Codex",
                thirtyDayCost: 30,
                thirtyDayTokens: 3_000,
                historyDays: 30,
                daily: [summaryDay]),
            thirtyDayCost: 1,
            todayCost: 1,
            thirtyDayTokens: 100,
            todayTokens: 100,
            dailyPoints: [self.day(daysAgo: 0, cost: 1, tokens: 100)])
        let claude = CostDashboardInsights.ProviderRow(
            provider: ProviderUsageSnapshot(
                providerID: "claude",
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(),
                costSummary: nil),
            thirtyDayCost: 6,
            todayCost: 0,
            thirtyDayTokens: 600,
            todayTokens: 0,
            dailyPoints: [self.day(daysAgo: 1, cost: 6, tokens: 600)])
        let insights = CostDashboardInsights(
            providerRows: [codex, claude],
            dailyPoints: [
                self.day(daysAgo: 0, cost: 1, tokens: 100),
                self.day(daysAgo: 1, cost: 6, tokens: 600),
            ],
            modelRows: [],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 90)

        let monthly = ShareCardData(insights: insights, period: .month)

        #expect(abs(monthly.totalCost - 36) < Self.tolerance)
        #expect(monthly.activeDays == 2)
        #expect(monthly.dailyBars.count == 30)
        #expect(abs(monthly.dailyBars.reduce(0) { $0 + $1.cost } - 36) < Self.tolerance)
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

    @Test("Share card 30-day period uses summary daily bars when local window is shorter")
    func shareCardMonthUsesSummaryDailyBarsForShorterLedgerWindow() {
        let summaryDays = (0..<30).map { day in
            let model = day < 7 ? "recent-model" : "older-month-model"
            return self.summaryDay(
                daysAgo: day,
                cost: 1,
                tokens: 100,
                models: [SyncCostBreakdown(label: model, costUSD: 1)])
        }
        let ledgerDays = (0..<7).map { day in
            self.day(
                daysAgo: day,
                cost: 1,
                tokens: 100,
                models: [SyncCostBreakdown(label: "recent-model", costUSD: 1)])
        }
        let codex = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "codex",
                name: "Codex",
                thirtyDayCost: 30,
                thirtyDayTokens: 3_000,
                historyDays: 30,
                daily: summaryDays),
            thirtyDayCost: 7,
            todayCost: 1,
            thirtyDayTokens: 700,
            todayTokens: 100,
            dailyPoints: ledgerDays)
        let insights = CostDashboardInsights(
            providerRows: [codex],
            dailyPoints: ledgerDays,
            modelRows: [
                CostBreakdownRow(label: "recent-model", amountUSD: 7, subtitle: nil, color: .blue),
            ],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 7)

        let monthly = ShareCardData(insights: insights, period: .month)

        #expect(abs(monthly.totalCost - 30) < Self.tolerance)
        #expect(monthly.totalTokens == 3_000)
        #expect(monthly.activeDays == 30)
        #expect(monthly.dailyBars.count == 30)
        #expect(abs(monthly.dailyBars.reduce(0) { $0 + $1.cost } - 30) < Self.tolerance)
        #expect(monthly.topModels.map(\.label) == ["older-month-model", "recent-model"])
        #expect(abs((monthly.topModels.first?.cost ?? 0) - 23) < Self.tolerance)
    }

    @Test("Share card uses monthly models when short-window and summary totals are equal")
    func shareCardMonthUsesSummaryModelsForEqualTotals() {
        let summaryDay = self.summaryDay(
            daysAgo: 10,
            cost: 7,
            tokens: 700,
            models: [SyncCostBreakdown(label: "monthly-model", costUSD: 7)])
        let ledgerDay = self.day(
            daysAgo: 0,
            cost: 7,
            tokens: 700,
            models: [SyncCostBreakdown(label: "ledger-model", costUSD: 7)])
        let codex = CostDashboardInsights.ProviderRow(
            provider: ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(),
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: 90,
                    last30DaysTokens: 9_000,
                    daily: [summaryDay],
                    historyDays: 90)),
            thirtyDayCost: 7,
            todayCost: 7,
            thirtyDayTokens: 700,
            todayTokens: 700,
            dailyPoints: [ledgerDay])
        let insights = CostDashboardInsights(
            providerRows: [codex],
            dailyPoints: [ledgerDay],
            modelRows: [
                CostBreakdownRow(label: "ledger-model", amountUSD: 7, subtitle: nil, color: .blue),
            ],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 7)

        let monthly = ShareCardData(insights: insights, period: .month)

        #expect(monthly.totalCost == 7)
        #expect(monthly.topModels.map(\.label) == ["monthly-model"])
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

    @Test("Token-only cost keeps share tokens without inventing zero spend")
    func tokenOnlyCostKeepsShareTokensWithoutInventingZeroSpend() {
        let dailyPoint = self.day(daysAgo: 0, cost: 0, tokens: 900, costIsKnown: false)
        let provider = ProviderUsageSnapshot(
            providerID: "grok", providerName: "Grok",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: 900,
                last30DaysCostUSD: nil, last30DaysTokens: 900,
                daily: [SyncDailyPoint(
                    dayKey: dailyPoint.dayKey,
                    costUSD: 0,
                    totalTokens: 900,
                    costIsKnown: false)],
                historyCoverageIsEstablished: false))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Mac"))

        #expect(insights.providerRows.count == 1)
        #expect(insights.providerRows.first?.thirtyDayCostIsKnown == false)
        #expect(insights.dailyPoints.first?.totalTokens == 900)
        #expect(insights.dailyPoints.first?.costIsKnown == false)
        #expect(insights.costDailyPoints.isEmpty)
        #expect(insights.hasIncompleteCostData)

        let week = ShareCardData(insights: insights, period: .week)
        #expect(week.totalTokens == 900)
        #expect(week.totalCost == 0)
        #expect(!week.totalCostIsKnown)
        #expect(week.dailyBars.isEmpty)
        #expect(week.providers.isEmpty)
        #expect(week.costCoverageIsIncomplete)
    }

    @Test("Weekly share totals use the same known provider contributions as provider shares")
    func weeklyShareTotalsAlignWithProviderShares() {
        let known = self.day(daysAgo: 0, cost: 2, tokens: 200, costIsKnown: true)
        let unavailable = self.day(daysAgo: 0, cost: 4, tokens: 400, costIsKnown: false)
        let knownProvider = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "openai", name: "OpenAI"),
            thirtyDayCost: 2,
            todayCost: 2,
            thirtyDayCostIsKnown: true,
            todayCostIsKnown: true,
            thirtyDayTokens: 200,
            todayTokens: 200,
            dailyPoints: [known])
        let unavailableProvider = CostDashboardInsights.ProviderRow(
            provider: self.provider(id: "codex", name: "Codex"),
            thirtyDayCost: 0,
            todayCost: 0,
            thirtyDayCostIsKnown: false,
            todayCostIsKnown: false,
            thirtyDayTokens: 400,
            todayTokens: 400,
            dailyPoints: [unavailable])
        let aggregateDay = self.day(daysAgo: 0, cost: 6, tokens: 600, costIsKnown: false)
        let insights = CostDashboardInsights(
            providerRows: [knownProvider, unavailableProvider],
            dailyPoints: [aggregateDay],
            modelRows: [],
            serviceRows: [],
            budgetRows: [])

        let week = ShareCardData(insights: insights, period: .week)

        #expect(week.totalCost == 2)
        #expect(week.totalCostIsKnown)
        #expect(week.providers.count == 1)
        #expect(week.providers.first?.name == "OpenAI")
        #expect(week.providers.first?.cost == 2)
        #expect(week.providers.first?.share == 1)
        #expect(week.activeDays == 1)
        #expect(week.avgDailyCost == 2)
        #expect(week.dailyBars.count == 1)
        #expect(week.dailyBars.first?.cost == 2)
        #expect(week.dailyBars.first?.costIsKnown == true)
        #expect(week.costCoverageIsIncomplete)
    }

    @Test("Unavailable Today cost suppresses partial model shares")
    func unavailableTodayCostSuppressesPartialModelShares() {
        let partialModel = SyncCostBreakdown(label: "partial-model", costUSD: 3)
        let point = self.day(
            daysAgo: 0,
            cost: 3,
            tokens: 900,
            costIsKnown: false,
            models: [partialModel])
        let provider = ProviderUsageSnapshot(
            providerID: "grok", providerName: "Grok",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: 900,
                last30DaysCostUSD: 3, last30DaysTokens: 900,
                daily: [SyncDailyPoint(
                    dayKey: point.dayKey,
                    costUSD: 3,
                    totalTokens: 900,
                    modelBreakdowns: [partialModel],
                    costIsKnown: false)]))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Mac"))

        let today = ShareCardData(insights: insights, period: .today)

        #expect(!today.todayCostIsKnown)
        #expect(today.providers.isEmpty)
        #expect(today.topModels.isEmpty)
        #expect(today.costCoverageIsIncomplete)
    }

    @Test("Mixed provider availability never revives unavailable model breakdowns")
    func mixedProviderAvailabilitySuppressesDashboardModelFallback() {
        let knownDay = self.day(daysAgo: 0, cost: 2, tokens: 200, costIsKnown: true)
        let partialModel = SyncCostBreakdown(label: "partial-model", costUSD: 4)
        let unavailableDay = self.day(
            daysAgo: 0,
            cost: 4,
            tokens: 400,
            costIsKnown: false,
            models: [partialModel])
        let knownProvider = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "openai", name: "OpenAI", historyDays: 7,
                daily: [SyncDailyPoint(
                    dayKey: knownDay.dayKey,
                    costUSD: 2,
                    totalTokens: 200,
                    costIsKnown: true)]),
            thirtyDayCost: 2,
            todayCost: 2,
            thirtyDayTokens: 200,
            todayTokens: 200,
            dailyPoints: [knownDay])
        let unavailableProvider = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "grok", name: "Grok", historyDays: 7,
                daily: [SyncDailyPoint(
                    dayKey: unavailableDay.dayKey,
                    costUSD: 4,
                    totalTokens: 400,
                    modelBreakdowns: [partialModel],
                    costIsKnown: false)]),
            thirtyDayCost: 0,
            todayCost: 0,
            thirtyDayCostIsKnown: false,
            todayCostIsKnown: false,
            thirtyDayTokens: 400,
            todayTokens: 400,
            dailyPoints: [unavailableDay])
        let insights = CostDashboardInsights(
            providerRows: [knownProvider, unavailableProvider],
            dailyPoints: [
                self.day(daysAgo: 0, cost: 6, tokens: 600, costIsKnown: false),
            ],
            modelRows: [
                CostBreakdownRow(
                    label: "partial-model",
                    amountUSD: 4,
                    subtitle: nil,
                    color: .blue),
            ],
            serviceRows: [],
            budgetRows: [])

        let week = ShareCardData(insights: insights, period: .week)

        #expect(week.totalCost == 2)
        #expect(week.totalCostIsKnown)
        #expect(week.costCoverageIsIncomplete)
        #expect(week.topModels.isEmpty)
    }

    @Test("30-day share chart preserves unavailable dates without showing their subtotal")
    func monthShareChartPreservesUnavailableDateSlots() {
        let known = self.day(daysAgo: 0, cost: 2, tokens: 200, costIsKnown: true)
        let unavailable = self.day(daysAgo: 15, cost: 4, tokens: 400, costIsKnown: false)
        let provider = CostDashboardInsights.ProviderRow(
            provider: ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
                statusMessage: nil, isError: false, lastUpdated: Date(),
                costSummary: nil),
            thirtyDayCost: 2,
            todayCost: 2,
            thirtyDayCostIsKnown: true,
            todayCostIsKnown: true,
            thirtyDayTokens: 600,
            todayTokens: 200,
            dailyPoints: [unavailable, known])
        let insights = CostDashboardInsights(
            providerRows: [provider],
            dailyPoints: [unavailable, known],
            modelRows: [],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 30)

        let month = ShareCardData(insights: insights, period: .month)

        #expect(month.dailyBars.count == 30)
        #expect(month.dailyBars[14].cost == 0)
        #expect(!month.dailyBars[14].costIsKnown)
        #expect(month.dailyBars[29].cost == 2)
        #expect(month.dailyBars[29].costIsKnown)
        #expect(month.costCoverageIsIncomplete)
    }

    @Test("Summary-backed monthly bars retain known spend beside an unavailable provider")
    func summaryBackedMonthlyBarsRetainKnownProviderSpend() {
        let knownDay = self.day(daysAgo: 0, cost: 5, tokens: 500, costIsKnown: true)
        let unavailableDay = self.day(daysAgo: 0, cost: 7, tokens: 700, costIsKnown: false)
        let knownProvider = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "codex",
                name: "Codex",
                thirtyDayCost: 10,
                thirtyDayTokens: 500,
                historyDays: 30,
                daily: [SyncDailyPoint(
                    dayKey: knownDay.dayKey,
                    costUSD: 5,
                    totalTokens: 500,
                    costIsKnown: true)]),
            thirtyDayCost: 10,
            todayCost: 5,
            thirtyDayTokens: 500,
            todayTokens: 500,
            dailyPoints: [knownDay])
        let unavailableProvider = CostDashboardInsights.ProviderRow(
            provider: self.provider(
                id: "grok",
                name: "Grok",
                thirtyDayTokens: 700,
                historyDays: 30,
                daily: [SyncDailyPoint(
                    dayKey: unavailableDay.dayKey,
                    costUSD: 7,
                    totalTokens: 700,
                    costIsKnown: false)]),
            thirtyDayCost: 0,
            todayCost: 0,
            thirtyDayCostIsKnown: false,
            todayCostIsKnown: false,
            thirtyDayTokens: 700,
            todayTokens: 700,
            dailyPoints: [unavailableDay])
        let insights = CostDashboardInsights(
            providerRows: [knownProvider, unavailableProvider],
            dailyPoints: [knownDay],
            modelRows: [],
            serviceRows: [],
            budgetRows: [])

        let month = ShareCardData(insights: insights, period: .month)

        #expect(month.totalCost == 10)
        #expect(month.activeDays == 1)
        #expect(month.dailyBars.last?.cost == 5)
        #expect(month.dailyBars.last?.costIsKnown == true)
        #expect(month.costCoverageIsIncomplete)
    }

    @Test("A newly seeded 30-day CWL window does not certify missing dates as zero")
    func newlySeededLedgerKeepsUnobservedDatesUnknown() {
        let staleStartPoint = self.day(daysAgo: 29, cost: 1, tokens: 100, costIsKnown: true)
        let todayPoint = self.day(daysAgo: 0, cost: 5, tokens: 500, costIsKnown: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 5, sessionTokens: 500,
                last30DaysCostUSD: 5, last30DaysTokens: 500,
                daily: [SyncDailyPoint(
                    dayKey: todayPoint.dayKey,
                    costUSD: 5,
                    totalTokens: 500,
                    costIsKnown: true)],
                historyDays: 7,
                historyCoverageIsEstablished: true))
        let providerRow = CostDashboardInsights.ProviderRow(
            provider: provider,
            thirtyDayCost: 6,
            todayCost: 5,
            thirtyDayTokens: 600,
            todayTokens: 500,
            dailyPoints: [staleStartPoint, todayPoint])
        let insights = CostDashboardInsights(
            providerRows: [providerRow],
            dailyPoints: [staleStartPoint, todayPoint],
            modelRows: [],
            serviceRows: [],
            budgetRows: [],
            cwlWindowDays: 30)

        let month = ShareCardData(insights: insights, period: .month)

        #expect(month.dailyBars.count == 30)
        #expect(month.dailyBars.first?.cost == 1)
        #expect(month.dailyBars.first?.costIsKnown == true)
        #expect(month.dailyBars.dropFirst().dropLast().allSatisfy { !$0.costIsKnown })
        #expect(month.dailyBars.last?.cost == 5)
        #expect(month.dailyBars.last?.costIsKnown == true)
        #expect(month.costCoverageIsIncomplete)
        #expect(!month.avgDailyCostIsKnown)
    }

    @Test("Legacy summaries keep pre-0.53 monthly coverage semantics")
    func legacySummaryKeepsMonthlyCoverageSemantics() {
        let todayPoint = self.day(daysAgo: 0, cost: 5, tokens: 500)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 5, sessionTokens: 500,
                last30DaysCostUSD: 5, last30DaysTokens: 500,
                daily: [SyncDailyPoint(
                    dayKey: todayPoint.dayKey,
                    costUSD: 5,
                    totalTokens: 500)]))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Old Mac"))

        let month = ShareCardData(insights: insights, period: .month)

        #expect(insights.providerRows.count == 1)
        #expect(!insights.hasIncompleteCostData)
        #expect(month.dailyBars.count == 30)
        #expect(month.dailyBars.allSatisfy { $0.costIsKnown })
        #expect(!month.costCoverageIsIncomplete)
        #expect(month.avgDailyCostIsKnown)
    }

    @Test("Summary-backed monthly Top Models exclude explicitly unavailable days")
    func summaryBackedMonthlyModelsExcludeUnavailableDays() {
        let knownModel = SyncCostBreakdown(label: "known-model", costUSD: 2)
        let unavailableModel = SyncCostBreakdown(label: "unavailable-model", costUSD: 4)
        let known = self.day(daysAgo: 0, cost: 2, tokens: 200, costIsKnown: true)
        let unavailable = self.day(daysAgo: 1, cost: 4, tokens: 400, costIsKnown: false)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 2, sessionTokens: 200,
                last30DaysCostUSD: 2, last30DaysTokens: 1_200,
                daily: [
                    SyncDailyPoint(
                        dayKey: known.dayKey,
                        costUSD: 2,
                        totalTokens: 200,
                        modelBreakdowns: [knownModel],
                        costIsKnown: true),
                    SyncDailyPoint(
                        dayKey: unavailable.dayKey,
                        costUSD: 4,
                        totalTokens: 400,
                        modelBreakdowns: [unavailableModel],
                        costIsKnown: false),
                ],
                historyDays: 7,
                historyCoverageIsEstablished: false))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Mac"))

        let month = ShareCardData(insights: insights, period: .month)

        #expect(month.totalCost == 2)
        #expect(month.topModels.map(\.label) == ["known-model"])
        #expect(month.topModels.first?.cost == 2)
        #expect(month.costCoverageIsIncomplete)
    }

    @Test("Summary-only monthly spend does not invent known zero-cost days")
    func summaryOnlyMonthlySpendDoesNotInventKnownZeroDays() {
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: nil,
                last30DaysCostUSD: 12, last30DaysTokens: 1_200,
                daily: []))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Mac"))

        let month = ShareCardData(insights: insights, period: .month)

        #expect(month.totalCost == 12)
        #expect(month.totalCostIsKnown)
        #expect(month.dailyBars.count == 30)
        #expect(month.dailyBars.allSatisfy { !$0.costIsKnown && $0.cost == 0 })
    }

    @Test("Share chart scales sub-dollar values against their true maximum")
    func shareChartScalesSubDollarValuesAgainstTrueMaximum() {
        let data = ShareCardData(
            totalCost: 0.15,
            todayCost: 0.10,
            totalTokens: 100,
            activeDays: 2,
            avgDailyCost: 0.075,
            providers: [],
            topModels: [],
            dailyBars: [
                .init(label: "1", cost: 0.05),
                .init(label: "2", cost: 0.10),
                .init(label: "3", cost: 0, costIsKnown: true),
            ])

        #expect(data.chartMaximumCost == 0.10)
        #expect(data.chartBarHeight(for: data.dailyBars[1], chartHeight: 140) == 140)
        #expect(data.chartBarHeight(for: data.dailyBars[2], chartHeight: 140) == 0)
    }

    @Test("Partial window cost remains visible with incomplete coverage state")
    func partialWindowCostRemainsVisibleWithIncompleteCoverageState() {
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 1, sessionTokens: 100,
                last30DaysCostUSD: 5, last30DaysTokens: 500,
                daily: [],
                historyCoverageIsEstablished: false))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Mac"))
        let month = ShareCardData(insights: insights, period: .month)

        #expect(insights.total30DayCost == 5)
        #expect(insights.total30DayCostIsKnown)
        #expect(insights.hasIncompleteCostData)
        #expect(month.totalCost == 5)
        #expect(month.totalCostIsKnown)
        #expect(month.costCoverageIsIncomplete)
        #expect(!month.avgDailyCostIsKnown)
    }

    @Test("Authoritative zero summaries stay known on dashboard and share cards")
    func authoritativeZeroSummariesStayKnown() {
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 0, sessionTokens: 0,
                last30DaysCostUSD: 0, last30DaysTokens: 0,
                daily: [],
                historyDays: 30,
                historyCoverageIsEstablished: true))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Mac"))

        #expect(insights.providerRows.count == 1)
        #expect(insights.total30DayCost == 0)
        #expect(insights.totalTodayCost == 0)
        #expect(insights.total30DayCostIsKnown)
        #expect(insights.totalTodayCostIsKnown)
        #expect(!insights.hasIncompleteCostData)

        let today = ShareCardData(insights: insights, period: .today)
        let month = ShareCardData(insights: insights, period: .month)
        #expect(today.todayCostIsKnown)
        #expect(today.totalCostIsKnown)
        #expect(month.totalCostIsKnown)
        #expect(!month.costCoverageIsIncomplete)
    }

    @Test("Partial daily subtotal never produces a complete-looking average")
    func partialDailySubtotalSuppressesAverage() {
        let partialDay = self.day(daysAgo: 0, cost: 4, tokens: 400, costIsKnown: false)
        let provider = CostDashboardInsights.ProviderRow(
            provider: ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
                statusMessage: nil, isError: false, lastUpdated: Date(),
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil, sessionTokens: nil,
                    last30DaysCostUSD: 4, last30DaysTokens: 400,
                    daily: [SyncDailyPoint(
                        dayKey: partialDay.dayKey,
                        costUSD: 4,
                        totalTokens: 400,
                        costIsKnown: false)],
                    historyCoverageIsEstablished: false)),
            thirtyDayCost: 4,
            todayCost: 0,
            thirtyDayCostIsKnown: true,
            todayCostIsKnown: false,
            thirtyDayTokens: 400,
            todayTokens: 400,
            dailyPoints: [partialDay])
        let insights = CostDashboardInsights(
            providerRows: [provider],
            dailyPoints: [partialDay],
            modelRows: [],
            serviceRows: [],
            budgetRows: [])

        let month = ShareCardData(insights: insights, period: .month)

        #expect(month.totalCost == 4)
        #expect(month.totalCostIsKnown)
        #expect(insights.activeDayCount == 1)
        #expect(month.activeDays == 1)
        #expect(month.costCoverageIsIncomplete)
        #expect(!month.avgDailyCostIsKnown)
    }

    @Test("Coverage-only summaries keep the incomplete state visible")
    func coverageOnlySummariesKeepIncompleteStateVisible() {
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: nil,
                last30DaysCostUSD: nil, last30DaysTokens: nil,
                daily: [],
                coverage: SyncCostCoverage(priced: 0, unpriced: 0, unmetered: 1, estimated: 0),
                historyCoverageIsEstablished: false))
        let insights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: Date(), deviceName: "Mac"))

        #expect(insights.hasDisplayData)
        #expect(insights.providerRows.count == 1)
        #expect(insights.hasIncompleteCostData)
        #expect(!insights.total30DayCostIsKnown)
    }

    @Test("Historical coverage does not depend on whether today has a cost bucket")
    func historicalCoverageDoesNotDependOnTodayBucket() {
        let yesterday = self.summaryDay(daysAgo: 1, cost: 5, tokens: 500, models: [])
        let complete = ProviderUsageSnapshot(
            providerID: "mistral", providerName: "Mistral",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: nil,
                last30DaysCostUSD: 5, last30DaysTokens: 500,
                daily: [yesterday],
                coverage: SyncCostCoverage(priced: 1, unpriced: 0, unmetered: 0, estimated: 0),
                historyCoverageIsEstablished: true))
        let completeInsights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [complete], syncTimestamp: Date(), deviceName: "Mac"))

        #expect(!completeInsights.totalTodayCostIsKnown)
        #expect(!completeInsights.hasIncompleteCostData)

        let incomplete = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 1, sessionTokens: 100,
                last30DaysCostUSD: 5, last30DaysTokens: 500,
                daily: [],
                coverage: SyncCostCoverage(priced: 4, unpriced: 1, unmetered: 0, estimated: 0),
                historyCoverageIsEstablished: true))
        let incompleteInsights = CostDashboardInsights(snapshot: SyncedUsageSnapshot(
            providers: [incomplete], syncTimestamp: Date(), deviceName: "Mac"))

        #expect(incompleteInsights.totalTodayCostIsKnown)
        #expect(incompleteInsights.hasIncompleteCostData)
    }
}
