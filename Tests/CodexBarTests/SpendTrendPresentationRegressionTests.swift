import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SpendTrendPresentationRegressionTests {
    @Test
    func `axis headroom remains finite for a valid very large cost`() throws {
        let group = try Self.group([Self.input(id: "large", cost: 1.7e308)])
        let chart = SpendTrendChartModel(group: group, section: .daily, day: nil)
        #expect(chart.yDomain.upperBound.isFinite)
        #expect(try chart.yDomain.upperBound >= #require(chart.peak).total)
    }

    @Test(arguments: [nil, "partial"] as [String?])
    func `incomplete requests mark both account inspectors and isolated totals as lower bounds`(
        selectedSource: String?) throws
    {
        let providers = [
            SpendDashboardModel.ProviderRow(
                id: "partial",
                rank: 0,
                provider: .codex,
                displayName: "Partial source",
                totalTokens: nil,
                totalCost: 4,
                coveredDayCount: 14,
                incompleteRequestCount: 1),
            SpendDashboardModel.ProviderRow(
                id: "complete",
                rank: 1,
                provider: .codex,
                displayName: "Complete source",
                totalTokens: 0,
                totalCost: 3,
                coveredDayCount: 14),
        ]
        let group = try SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: providers,
            models: [],
            dailyPoints: [],
            totalTokens: nil,
            totalCost: 7,
            coveredDayCount: 14,
            chartDomain: Self.day(1)...Self.day(15),
            modelHistoryCompleteness: .complete,
            timeZone: .gmt)
        #expect(group.hasPartialCost)
        #expect(!providers[0].costIsLowerBound)
        let view = SpendTrendChart(group: group, section: .daily, day: nil, sourceID: selectedSource)
        #expect(view.costText(4).hasPrefix("≥ "))
        #expect(view.costText(4, sourceID: "partial").hasPrefix("≥ "))
        #expect(!view.costText(3, sourceID: "complete").hasPrefix("≥ "))
    }

    @Test(arguments: ["idle", "week", "idle-week"])
    func `filtered empty charts preserve proven zero spend`(scope: String) throws {
        let group = try Self.group([Self.input(id: "busy", cost: 5), Self.input(id: "idle", cost: 0)])
        let sourceID = scope.contains("idle") ? "idle" : nil
        let interval = try scope.contains("week") ? DateInterval(start: Self.day(1), end: Self.day(8)) : nil
        let chart = SpendTrendChartModel(
            group: group, section: .daily, day: nil, sourceID: sourceID, overviewInterval: interval)
        #expect(group.totalCost == 5)
        #expect(chart.segments.isEmpty)
        #expect(chart.emptyStateTitle(group: group, sourceID: sourceID) == L("No usage yet"))
    }

    @Test
    func `a fully covered idle source does not inherit another sources missing coverage`() throws {
        let group = try Self.group([
            Self.input(id: "idle", cost: 0),
            Self.input(id: "unknown", cost: nil, historyDays: 1),
        ])
        #expect(group.dailySummaries.count < 14)
        let chart = SpendTrendChartModel(group: group, section: .daily, day: nil, sourceID: "idle")
        #expect(chart.segments.isEmpty)
        #expect(chart.emptyStateTitle(group: group, sourceID: "idle") == L("No usage yet"))
    }

    @Test(arguments: ["unknown", "absent"])
    func `an unknown or absent source does not inherit another sources proven zero`(sourceID: String) throws {
        let group = try Self.group([
            Self.input(id: "idle", cost: 0),
            Self.input(id: "unknown", cost: nil, historyDays: 1),
        ])
        let chart = SpendTrendChartModel(group: group, section: .daily, day: nil, sourceID: sourceID)
        #expect(chart.segments.isEmpty)
        #expect(chart.emptyStateTitle(group: group, sourceID: sourceID) == L("Spend unavailable"))
    }

    @Test
    func `daily zero spend does not invent missing hourly coverage`() throws {
        let group = try Self.group([Self.input(id: "busy", cost: 5), Self.input(id: "idle", cost: 0)])
        let chart = try SpendTrendChartModel(group: group, section: .hourly, day: Self.day(14), sourceID: "idle")
        #expect(!group.hourlyPoints.isEmpty)
        #expect(chart.segments.isEmpty)
        #expect(chart.emptyStateTitle(group: group, sourceID: "idle") == L("Spend unavailable"))
    }

    @Test
    func `zero spend in the reporting window does not prove earlier history idle`() throws {
        let group = try Self.group([Self.input(id: "idle", cost: 0)])
        let start = try #require(Self.calendar.date(byAdding: .day, value: -7, to: group.chartDomain.lowerBound))
        let chart = SpendTrendChartModel(
            group: group,
            section: .daily,
            day: nil,
            overviewInterval: DateInterval(start: start, end: group.chartDomain.lowerBound))
        #expect(chart.segments.isEmpty)
        #expect(chart.emptyStateTitle(group: group, sourceID: nil) == L("Spend unavailable"))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func day(_ day: Int) throws -> Date {
        try #require(self.calendar.date(from: DateComponents(year: 2026, month: 10, day: day)))
    }

    private static func input(id: String, cost: Double?, historyDays: Int = 14) throws
        -> SpendDashboardModel.ProviderInput
    {
        let day = try self.day(14)
        let daily: [CostUsageDailyReport.Entry] = cost.map { value in
            value == 0 ? [] : [CostUsageDailyReport.Entry(
                date: "2026-10-14",
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: 0,
                costUSD: value,
                modelsUsed: nil,
                modelBreakdowns: nil)]
        } ?? []
        let hourly: [CostUsageHourlyEntry] = cost.map { value in
            value == 0 ? [] : [CostUsageHourlyEntry(
                hour: day.addingTimeInterval(9 * 3600), totalTokens: 0, costUSD: value)]
        } ?? []
        return SpendDashboardModel.ProviderInput(
            id: id,
            provider: .codex,
            displayName: "Synthetic \(id)",
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: cost == nil ? nil : 0,
                last30DaysCostUSD: cost,
                historyDays: historyDays,
                historyCoverageIsEstablished: cost != nil,
                daily: daily,
                hourly: hourly,
                updatedAt: day.addingTimeInterval(18 * 3600)))
    }

    private static func group(_ inputs: [SpendDashboardModel.ProviderInput]) throws
        -> SpendDashboardModel.CurrencyGroup
    {
        try #require(SpendDashboardModel.build(
            inputs: inputs,
            requestedDays: 14,
            now: self.day(14).addingTimeInterval(18 * 3600),
            calendar: self.calendar).groups.first)
    }
}
