import Foundation
import Testing
@testable import CodexBarCore

struct QuotaWeekProjectionScaleTests {
    @Test
    func `warm projection avoids the fifty thousand slice rebuild`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        let now = Date(timeIntervalSince1970: 1_762_340_400)
        let slices = (0..<50000).map { index in
            CostUsageTimedEntry(
                timestamp: now.addingTimeInterval(Double(index - 50000) * 50),
                totalTokens: 10,
                costUSD: 0.001)
        }
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: [],
            quotaSlices: slices,
            updatedAt: now)
        let start = ContinuousClock.now
        snapshot.warmQuotaProjection(calendar: calendar)
        let cold = ContinuousClock.now - start
        let copy = snapshot
        let warmStart = ContinuousClock.now
        for _ in 0..<10 {
            copy.warmQuotaProjection(calendar: calendar)
        }
        let warm = (ContinuousClock.now - warmStart) / 10
        print("[quota-projection-proof] slices=50000 cold=\(cold) warm=\(warm)")
        // Relative work, with ample margin for a loaded shared test host.
        #expect(warm * 8 < cold)
    }

    @Test
    func `dense exact slices land in the quota week that contains them`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        // Spans the 2025-10-26 fall-back day, so one local day is 25 hours long.
        let now = try #require(calendar.date(from: DateComponents(year: 2025, month: 11, day: 5, hour: 12)))
        let resetAt = try #require(calendar.date(from: DateComponents(year: 2025, month: 11, day: 7, hour: 9)))
        let historyStart = try #require(calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)))

        let sliceCount = 54000
        let step = now.timeIntervalSince(historyStart) / Double(sliceCount)
        let slices = (0..<sliceCount).map { index in
            CostUsageTimedEntry(
                timestamp: historyStart.addingTimeInterval(Double(index) * step),
                totalTokens: index % 7 + 1,
                costUSD: nil)
        }
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: [],
            quotaSlices: slices,
            updatedAt: now)

        let weeks = snapshot.quotaWeekSummaries(resetAt: resetAt, now: now, calendar: calendar)

        #expect(weeks.count == 4)
        #expect(snapshot.quotaWeekSummaries(resetAt: resetAt, now: now, calendar: calendar) == weeks)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let cold = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: [],
            quotaSlices: slices,
            updatedAt: now)
        #expect(
            snapshot.quotaWeekSummaries(resetAt: resetAt, now: now, calendar: utc)
                == cold.quotaWeekSummaries(resetAt: resetAt, now: now, calendar: utc))
        for week in weeks {
            let expected = slices
                .filter { $0.timestamp >= week.start && $0.timestamp < week.end }
                .reduce(0) { $0 + ($1.totalTokens ?? 0) }
            #expect(week.totalTokens == expected)
        }
    }
}

extension QuotaWeekProjectionScaleTests {
    @Test
    func `projection belongs to snapshot identity while resets remain live`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_762_340_400)
        func snapshot(tokens: Int) -> CostUsageTokenSnapshot {
            CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: nil,
                last30DaysCostUSD: nil,
                daily: [],
                quotaSlices: [CostUsageTimedEntry(timestamp: now, totalTokens: tokens, costUSD: 1)],
                updatedAt: now)
        }
        let first = snapshot(tokens: 10)
        first.warmQuotaProjection(calendar: calendar)
        let equal = snapshot(tokens: 10)
        #expect(first == equal)
        #expect(first.quotaProjectionMemo !== equal.quotaProjectionMemo)
        let changed = snapshot(tokens: 20)
        let reset = now.addingTimeInterval(86400)
        #expect(first.quotaWeekSummaries(resetAt: reset, now: now, calendar: calendar).first?.totalTokens == 10)
        #expect(changed.quotaWeekSummaries(resetAt: reset, now: now, calendar: calendar).first?.totalTokens == 20)
        let redeemed = now.addingTimeInterval(-3600)
        #expect(first.quotaWeekSummaries(
            resetAt: reset, observedResetInstants: [redeemed], now: now, calendar: calendar).isEmpty)
        let replacementReset = redeemed.addingTimeInterval(TimeInterval(CostUsageTokenSnapshot.quotaWeekMinutes * 60))
        let moved = first.quotaWeekSummaries(
            resetAt: replacementReset, observedResetInstants: [redeemed], now: now, calendar: calendar)
        #expect(moved.first?.start == redeemed)
        #expect(moved.first?.totalTokens == 10)
        let later = now.addingTimeInterval(8 * 86400)
        #expect(first.quotaWeekSummaries(resetAt: reset, now: later, calendar: calendar)
            == equal.quotaWeekSummaries(resetAt: reset, now: later, calendar: calendar))
    }
}
