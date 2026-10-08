import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SpendTrendCalendarTests {
    @Test(arguments: [45, 46, 180, 181])
    func `overview grouping counts reporting days across fall back`(days: Int) throws {
        let group = try Self.group(days: days)
        let chart = SpendTrendChartModel(group: group, section: .daily, day: nil)
        let expected: Calendar.Component = days > 180 ? .month : days > 45 ? .weekOfYear : .day
        #expect(chart.unit == expected)
    }

    @Test(arguments: [31, 32, 33])
    func `daily scrolling preserves calendar day boundaries across fall back`(days: Int) throws {
        let group = try Self.group(days: days)
        let chart = SpendTrendChartModel(group: group, section: .daily, day: nil)
        let visibleStart = try #require(group.calendar.date(
            byAdding: .day, value: -31, to: group.chartDomain.upperBound))
        #expect(chart.needsScrolling == (days > 32))
        #expect(chart.visibleDuration == group.chartDomain.upperBound.timeIntervalSince(visibleStart))
    }

    @Test
    func `midnight daylight saving preserves reporting days and visible midnight boundaries`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let noon = try #require(calendar.date(from: DateComponents(year: 2018, month: 11, day: 4, hour: 12)))
        let boundary = calendar.startOfDay(for: noon)
        let start = try #require(calendar.date(from: DateComponents(year: 2018, month: 10, day: 3)))
        let visibleStart = try #require(calendar.date(from: DateComponents(year: 2018, month: 10, day: 4)))
        let before = Self.group(start: start, end: boundary, days: 32, calendar: calendar)
        let daily = SpendTrendChartModel(group: before, section: .daily, day: nil)
        #expect(daily.visibleDayCount == 31)
        #expect(!daily.needsScrolling)
        #expect(daily.domain.upperBound.addingTimeInterval(-daily.visibleDuration) == visibleStart)

        let end = try calendar.startOfDay(for: #require(calendar.date(byAdding: .day, value: 46, to: boundary)))
        let after = Self.group(start: boundary, end: end, days: 46, calendar: calendar)
        #expect(SpendTrendChartModel(group: after, section: .daily, day: nil).unit == .weekOfYear)
    }

    private static func group(days: Int) throws -> SpendDashboardModel.CurrencyGroup {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        let start = try #require(calendar.date(byAdding: .day, value: -days, to: end))
        return Self.group(start: start, end: end, days: days, calendar: calendar)
    }

    private static func group(start: Date, end: Date, days: Int, calendar: Calendar) -> SpendDashboardModel
    .CurrencyGroup {
        SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: [],
            models: [],
            dailyPoints: [],
            totalTokens: nil,
            totalCost: nil,
            coveredDayCount: days,
            chartDomain: start...end,
            modelHistoryCompleteness: .complete,
            timeZone: calendar.timeZone)
    }
}
