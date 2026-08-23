import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLICostCalendarTests {
    @Test
    func `cost JSON honors snapshot bucket timezone over pinned calendar`() throws {
        let now = Date(timeIntervalSince1970: 1_784_220_600) // July 17 in Tokyo, July 16 in Los Angeles.
        var pinnedCalendar = Calendar(identifier: .gregorian)
        pinnedCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 20,
            sessionCostUSD: 0.02,
            last30DaysTokens: 20,
            last30DaysCostUSD: 0.02,
            historyDays: 1,
            costProvenance: .listPriceEstimate,
            daily: [CostUsageDailyReport.Entry(
                date: "2026-07-17",
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: 20,
                costUSD: 0.02,
                modelsUsed: [],
                modelBreakdowns: nil,
                estimatedRequestCount: 1)],
            bucketTimeZoneIdentifier: "Asia/Tokyo",
            updatedAt: now)

        let payload = CodexBarCLI.makeCostPayload(
            provider: .cursor,
            snapshot: snapshot,
            error: nil,
            calendar: pinnedCalendar)

        #expect(payload.coverage == CostUsageCoverageCounts(estimated: 1))
        #expect(payload.totals?.coverage == payload.coverage)
        #expect(payload.provenance == CostProvenance.listPriceEstimate.rawValue)
    }
}
