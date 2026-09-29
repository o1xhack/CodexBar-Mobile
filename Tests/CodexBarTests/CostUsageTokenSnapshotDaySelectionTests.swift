import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageTokenSnapshotDaySelectionTests {
    @Test
    func `token snapshot reports zero today when latest history row is stale`() throws {
        let now = try Self.localNoon(year: 2026, month: 5, day: 18)
        let report = CostUsageDailyReport(
            data: [
                Self.entry("2026-05-15", input: 200, output: 100, tokens: 300, cost: 1.5),
            ],
            summary: nil)

        let snapshot = CostUsageFetcher.tokenSnapshot(from: report, now: now)

        #expect(snapshot.sessionCostUSD == 0)
        #expect(snapshot.sessionTokens == 0)
        #expect(snapshot.last30DaysCostUSD == 1.5)
        #expect(snapshot.last30DaysTokens == 300)
        #expect(snapshot.currentDayEntry() == nil)
    }

    @Test
    func `token snapshot uses current local day instead of newest historical row`() throws {
        let now = try Self.localNoon(year: 2026, month: 5, day: 18)
        let report = CostUsageDailyReport(
            data: [
                Self.entry("2026-05-17", input: 200, output: 100, tokens: 300, cost: 1.5),
                Self.entry("2026-05-18", input: 20, output: 10, tokens: 30, cost: 0.15),
            ],
            summary: nil)

        let snapshot = CostUsageFetcher.tokenSnapshot(from: report, now: now)

        #expect(snapshot.sessionCostUSD == 0.15)
        #expect(snapshot.sessionTokens == 30)
        #expect(snapshot.last30DaysCostUSD == 1.65)
        #expect(snapshot.last30DaysTokens == 330)
    }

    @Test
    func `token snapshot can preserve latest bucket semantics`() throws {
        let now = try Self.localNoon(year: 2026, month: 5, day: 18)
        let report = CostUsageDailyReport(
            data: [
                Self.entry("2026-05-15", input: 200, output: 100, tokens: 300, cost: 1.5),
            ],
            summary: nil)

        let snapshot = CostUsageFetcher.tokenSnapshot(
            from: report,
            now: now,
            useCurrentLocalDayForSession: false)

        #expect(snapshot.sessionCostUSD == 1.5)
        #expect(snapshot.sessionTokens == 300)
    }

    @Test
    func `cost window start uses the local day boundary`() throws {
        let calendar = Calendar.current

        // historyDays > 1: a midday instant several days back snaps to that day's 00:00.
        let midday = try Self.localNoon(year: 2026, month: 5, day: 15)
        let snapped = CostReportingPeriod.rolling(days: 1).bounds(now: midday, calendar: calendar).lowerBound
        #expect(snapped == calendar.startOfDay(for: midday))
        #expect(snapped <= midday)

        // historyDays == 1: `since` is `now`, so the window must still cover all of today (00:00 today),
        // not collapse to the current instant.
        let now = try Self.localNoon(year: 2026, month: 5, day: 18)
        let today = CostReportingPeriod.rolling(days: 1).bounds(now: now, calendar: calendar).lowerBound
        #expect(today == calendar.startOfDay(for: now))
        #expect(calendar.isDate(today, inSameDayAs: now))
        #expect(today <= now)
    }

    @Test
    func `token snapshot retains the calendar that produced its day keys`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-22T00:30:00Z"))

        let snapshot = CostUsageFetcher.tokenSnapshot(
            from: CostUsageDailyReport(data: [], summary: nil),
            now: now,
            calendar: calendar)

        #expect(snapshot.bucketTimeZoneIdentifier == "Pacific/Kiritimati")
    }

    @Test
    func `token snapshot distinguishes omitted and explicitly unknown currency`() {
        let omitted = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: [],
            updatedAt: Date())
        let blank = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            currencyCode: "  ",
            daily: [],
            updatedAt: Date())
        let euro = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            currencyCode: " eur ",
            daily: [],
            updatedAt: Date())

        #expect(omitted.currencyCode == "USD")
        #expect(blank.currencyCode == "XXX")
        #expect(euro.currencyCode == "EUR")
    }

    @Test
    func `latest entry ignores invalid calendar dates`() {
        let latest = CostUsageTokenSnapshot.latestEntry(in: [
            Self.entry("2026-06-31", tokens: 999, cost: 9.99),
            Self.entry("2026-06-30", tokens: 100, cost: 1),
        ])

        #expect(latest?.date == "2026-06-30")
    }

    @Test(arguments: [true, false])
    func `empty history is zero only after coverage is established`(established: Bool) throws {
        let now = try Self.localNoon(year: 2026, month: 5, day: 18)
        let snapshot = CostUsageFetcher.tokenSnapshot(
            from: CostUsageDailyReport(data: [], summary: nil),
            now: now,
            historyCoverageIsEstablished: established)

        #expect(snapshot.sessionCostUSD == (established ? 0 : nil))
        #expect(snapshot.sessionTokens == (established ? 0 : nil))
        #expect(snapshot.last30DaysCostUSD == (established ? 0 : nil))
        #expect(snapshot.last30DaysTokens == (established ? 0 : nil))
        #expect(snapshot.historyCoverageIsEstablished == established)
    }

    @Test(arguments: [
        ("explicit zeros", [
            Self.entry("2026-05-17", tokens: 0, cost: 0),
            Self.entry("2026-05-18", tokens: 0, cost: 0),
        ], 0.0, 0),
        ("missing cost", [
            Self.entry("2026-05-17", tokens: 10, cost: 1),
            Self.entry("2026-05-18", tokens: 20, cost: nil),
        ], nil, 30),
        ("missing tokens", [
            Self.entry("2026-05-17", tokens: 10, cost: 1),
            Self.entry("2026-05-18", tokens: nil, cost: 2),
        ], 3.0, nil),
        ("zero cost and unavailable tokens", [Self.entry("2026-05-18", tokens: nil, cost: 0)], 0.0, nil),
        ("unpriced entries", [
            Self.entry("2026-05-17", tokens: 10, cost: nil),
            Self.entry("2026-05-18", tokens: 0, cost: nil),
        ], nil, 10),
    ] as [(String, [CostUsageDailyReport.Entry], Double?, Int?)])
    func `totals preserve zero and unknown metrics`(
        scenario: String,
        entries: [CostUsageDailyReport.Entry],
        cost: Double?,
        tokens: Int?) throws
    {
        let now = try Self.localNoon(year: 2026, month: 5, day: 18)
        let report = CostUsageDailyReport(data: entries, summary: nil)
        let snapshot = CostUsageFetcher.tokenSnapshot(from: report, now: now)

        #expect(snapshot.last30DaysCostUSD == cost, "\(scenario)")
        #expect(snapshot.last30DaysTokens == tokens, "\(scenario)")
    }

    private static func entry(
        _ date: String,
        input: Int? = nil,
        output: Int? = nil,
        tokens: Int?,
        cost: Double?) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: date,
            inputTokens: input,
            outputTokens: output,
            totalTokens: tokens,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }

    private static func localNoon(year: Int, month: Int, day: Int) throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return try #require(components.date)
    }
}
