import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
struct CursorCostRequestDateTests {
    @Test(arguments: [
        (nil, nil),
        (Date.distantPast, "0"),
        (Date(timeIntervalSince1970: -1), "0"),
        (Date(timeIntervalSince1970: 0), "0"),
        (Date(timeIntervalSince1970: 1_700_000_000), "1700000000000"),
    ] as [(Date?, String?)])
    func `cost requests use a supported lower bound without narrowing modern history`(
        since: Date?, expectedStart: String?) async throws
    {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = ProviderHTTPTransportStub { request in
            let body = try #require(request.httpBody)
            let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(fields["startDate"] as? String == expectedStart)
            #expect(fields["endDate"] as? String == "1800000000000")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(#"{"totalUsageEventsCount":0,"usageEventsDisplay":[]}"#.utf8), response)
        }
        let fetcher = CursorUsageEventsFetcher(transport: transport)
        _ = try await fetcher.fetchUsage(cookieHeader: "synthetic", since: since, until: until)
        #expect(await transport.requests().count == 1)
    }

    @Test(arguments: ["UTC", "America/Los_Angeles", "Asia/Tokyo"], [
        CostReportingPeriod.allTime, .monthToDate, .rolling(days: 30),
    ])
    func `shared reporting periods retain their selected calendar at the request boundary`(
        zone: String, period: CostReportingPeriod) async throws
    {
        let calendar = CostUsageBucketTimeZone.calendar(identifier: zone)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-03-09T07:30:00Z"))
        let historyDays = period.days(now: now, calendar: calendar)
        let since = CostReportingPeriod.rolling(days: historyDays).bounds(now: now, calendar: calendar).lowerBound
        let expected = period == .allTime ? "0" : String(Int64(
            period.bounds(now: now, calendar: calendar).lowerBound.timeIntervalSince1970 * 1000))
        let transport = ProviderHTTPTransportStub { request in
            let body = try #require(request.httpBody)
            let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(fields["startDate"] as? String == expected)
            #expect(fields["endDate"] as? String == String(Int64(now.timeIntervalSince1970 * 1000)))
            let url = try #require(request.url)
            return try (Data("{}".utf8), #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
        _ = try await CursorUsageEventsFetcher(transport: transport).fetchUsage(
            cookieHeader: "synthetic", since: since, until: now, calendar: calendar)
        #expect(await transport.requests().count == 1)
    }
}
#endif
