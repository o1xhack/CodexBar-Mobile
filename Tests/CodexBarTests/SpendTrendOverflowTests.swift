import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SpendTrendOverflowTests {
    @Test(arguments: [14, 90])
    func `chart aggregation keeps overflowing recorded spend unavailable`(days: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 18)))
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: 90,
            daily: ["2026-10-04", "2026-10-05"].map { date in
                CostUsageDailyReport.Entry(
                    date: date,
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    costUSD: 1e308,
                    modelsUsed: nil,
                    modelBreakdowns: nil)
            },
            updatedAt: now)
        let group = try #require(SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Synthetic source", snapshot: snapshot)],
            requestedDays: days,
            now: now,
            calendar: calendar).groups.first)
        #expect(group.totalCost == nil)
        #expect(group.dailyPoints.count == 2)
        let chart = SpendTrendChartModel(group: group, section: .daily, day: nil)
        let recordedTotal: Double? = chart.total
        #expect(recordedTotal == nil)
        #expect(chart.segments.allSatisfy { $0.cost.isFinite && $0.start.isFinite && $0.end.isFinite })
        #expect(chart.buckets.count == (days > 45 ? 0 : 2))
    }
}
