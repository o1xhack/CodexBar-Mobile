import Foundation
import Testing
@testable import CodexBarCore

struct CostUsagePriorityDayKeysTests {
    private func range(since: Int, until: Int) throws -> CostUsageScanner.CostUsageDayRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return try CostUsageScanner.CostUsageDayRange(
            since: #require(calendar.date(from: DateComponents(year: since, month: 1, day: 1))),
            until: #require(calendar.date(from: DateComponents(year: until, month: 12, day: 31))),
            calendar: calendar)
    }

    @Test
    func `all history stores only populated priority days`() throws {
        let range = try self.range(since: 1, until: 2026)
        let start = ContinuousClock.now
        let ids = CostUsageScanner.mergePriorityDayValues(
            existing: ["2019-04-01": ["removed"], "2025-04-01": []],
            new: ["2018-04-01": ["old-but-valid"]],
            range: range,
            retainedSinceKey: "0001-01-01",
            retainedUntilKey: "2026-12-31")
        print("[priority-days] all-history duration=\(start.duration(to: .now)) entries=\(ids?.count ?? 0)")
        #expect(ids?.count == 1)
        #expect(ids?["2018-04-01"] == ["old-but-valid"])
    }

    @Test
    func `priority changes preserve old dates and ignore days outside the scan`() throws {
        let range = try self.range(since: 2018, until: 2019)
        let old = ["2018-04-01": "removed", "2019-05-01": "old", "2026-04-01": "outside"]
        let new = ["2019-05-01": "new", "2019-06-01": "added"]
        #expect(CostUsageScanner.codexPriorityTurnKeysChanged(old: old, new: new, range: range))
        #expect(!CostUsageScanner.codexPriorityTurnKeysChanged(
            old: ["2026-04-01": "outside"], new: [:], range: range))
        #expect(CostUsageScanner.changedPriorityTurnIDs(
            old: ["2018-04-01": ["removed"], "2019-05-01": ["same"]],
            new: ["2019-05-01": ["same"], "2019-06-01": ["added"], "2026-04-01": ["outside"]],
            oldKeys: old,
            newKeys: new,
            range: range) == ["removed", "same", "added"])
        let mergedKeys = CostUsageScanner.mergePriorityDayValues(
            existing: old,
            new: new,
            range: range,
            retainedSinceKey: "2018-01-01",
            retainedUntilKey: "2026-12-31")
        #expect(mergedKeys == ["2019-05-01": "new", "2019-06-01": "added", "2026-04-01": "outside"])
        #expect(CostUsageScanner.mergePriorityDayValues(
            existing: ["2018-04-01": ["removed"], "2026-04-01": ["outside"]],
            new: [:],
            range: range,
            retainedSinceKey: "2018-01-01",
            retainedUntilKey: "2026-12-31") == ["2026-04-01": ["outside"]])
    }
}
