import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct OpenCodeConsoleUsageFetcherTests {
    private static let now = Date(timeIntervalSince1970: 1_789_862_400)
    private static let workspaceID = "wrk_CONSOLE123"
    private static let consoleCookie = "__Host-console_session=synthetic-session"
    private static let bothCookies = Self.consoleCookie + "; auth=synthetic-legacy"
    private static let goPath = "/console/api/go/status"
    private static let orgPath = "/console/api/orgs/current"
    private static let summaryPath = "/console/api/usage/summary"
    private static let billingPath = "/console/api/billing/status"
    private static let quota = """
    {"access":{"endsAt":"2026-10-19T00:00:00Z","meters":{
      "fiveHour":{"limitMicroCents":"1200000000","usedMicroCents":"300000000",
        "resetsAt":"2026-09-20T03:00:00Z"},
      "week":{"limitMicroCents":"3000000000","usedMicroCents":"1200000000",
        "resetsAt":"2026-09-21T00:00:00Z"}}}}
    """
    private static let legacyQuota = """
    {"rollingUsage":{"usagePercent":17,"resetInSec":600},
     "weeklyUsage":{"usagePercent":75,"resetInSec":7200}}
    """

    @Test
    func `Console only session discovers its workspace and reads subscription quota`() async throws {
        let transport = ConsoleUsageTransport(replies: [
            "/console/api/orgs": .init(body: #"[{"id":"wrk_CONSOLE123"},{"id":"wrk_OTHER456"}]"#),
            Self.goPath: .init(body: Self.quota),
        ])

        let snapshot = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: Self.consoleCookie,
            timeout: 17,
            now: Self.now,
            session: transport)

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.weeklyUsagePercent == 40)
        #expect(snapshot.rollingResetInSec == 10800)
        #expect(snapshot.weeklyResetInSec == 86400)
        #expect(snapshot.updatedAt == Self.now)
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == ["/console/api/orgs", Self.goPath])
        #expect(requests.first?.value(forHTTPHeaderField: "x-org-id") == nil)
        #expect(requests.last?.value(forHTTPHeaderField: "x-org-id") == Self.workspaceID)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.timeoutInterval == 17 })
    }

    @Test(arguments: [#"{"access":null}"#, "null"])
    func `PAYG reads stay in the selected org and use thirty day microcent totals`(goStatus: String) async throws {
        let transport = ConsoleUsageTransport(replies: Self.payAsYouGoReplies(goStatus: goStatus))

        let snapshot = try await Self.fetch(transport: transport)

        let payAsYouGo = try #require(snapshot.payAsYouGo)
        #expect(payAsYouGo.monthlyUsageUSD == 3.25)
        #expect(payAsYouGo.balanceUSD == 12.5)
        #expect(payAsYouGo.monthlyLimitUSD == nil)
        #expect(payAsYouGo.period == .last30Days)
        #expect(payAsYouGo.usedPercent == nil)
        #expect(snapshot.toUsageSnapshot().providerCost?.period == "Last 30 days")
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath, Self.orgPath, Self.billingPath, Self.summaryPath])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-org-id") == Self.workspaceID })
        let summaryURL = try #require(requests.first { $0.url?.path == Self.summaryPath }?.url)
        let query = URLComponents(url: summaryURL, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "range", value: "30d")])
    }

    @Test
    func `explicit workspace override skips discovery and preserves missing quota windows`() async throws {
        let transport = ConsoleUsageTransport(replies: [
            Self.goPath: .init(body: """
            {"access":{"meters":{"fiveHour":{
              "limitMicroCents":"1200000000","usedMicroCents":"300000000"}}}}
            """),
        ])

        let snapshot = try await Self.fetch(transport: transport)

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.hasWeeklyUsage == false)
        #expect(snapshot.toUsageSnapshot().primary?.resetsAt == nil)
        #expect(snapshot.toUsageSnapshot().secondary == nil)
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath])
        #expect(requests.first?.value(forHTTPHeaderField: "x-org-id") == Self.workspaceID)
    }

    @Test
    func `subscribed org with null quota cannot be presented as PAYG spend`() async throws {
        let transport = ConsoleUsageTransport(replies: [
            Self.goPath: .init(body: #"{"access":null}"#),
            Self.orgPath: .init(body: #"{"hasGoSubscription":true}"#),
        ])

        do {
            _ = try await Self.fetch(transport: transport)
            Issue.record("Expected unavailable subscription quota to fail")
        } catch OpenCodeUsageError.parseFailed {
            // Valid credentials without quota must not publish spend as a subscription replacement.
        }
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath, Self.orgPath])
    }

    @Test(arguments: [
        #"{"billingMode":"prepaid","mode":"pay-as-you-go"}"#,
        #"{"billingMode":"prepaid","mode":"pay-as-you-go","balanceMicroCents":"invalid"}"#,
    ])
    func `missing or malformed balance keeps spend for confirmed PAYG`(billing: String) async throws {
        var replies = Self.payAsYouGoReplies()
        replies[Self.billingPath] = .init(body: billing)
        let transport = ConsoleUsageTransport(replies: replies)

        let snapshot = try await Self.fetch(transport: transport)

        #expect(snapshot.payAsYouGo?.monthlyUsageUSD == 3.25)
        #expect(snapshot.payAsYouGo?.balanceUSD == nil)
        #expect(snapshot.payAsYouGo?.monthlyLimitUSD == nil)
        #expect(snapshot.toUsageSnapshot().providerCost?.used == 3.25)
    }

    @Test
    func `invoiceable account is not rendered as PAYG spend`() async throws {
        var replies = Self.payAsYouGoReplies()
        replies[Self.billingPath] = .init(body: #"{"billingMode":"credit","mode":"invoiceable"}"#)
        let transport = ConsoleUsageTransport(replies: replies)

        do {
            _ = try await Self.fetch(transport: transport)
            Issue.record("Expected unsupported billing mode to fail")
        } catch OpenCodeUsageError.parseFailed {
            // The summary alone cannot establish a supported account type.
        }
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath, Self.orgPath, Self.billingPath])
    }

    @Test(arguments: ["true", "-1", "1.5", #""NaN""#, "null", #""-1""#, #""1.5""#])
    func `malformed microcent totals fail instead of becoming spend`(raw: String) throws {
        do {
            _ = try OpenCodeConsoleUsageFetcher.parseSummary(text: "{\"totalCostMicroCents\":\(raw)}")
            Issue.record("Expected invalid monetary total to fail")
        } catch OpenCodeUsageError.parseFailed {
            // Only nonnegative whole microcents can be a spend total.
        }
    }

    @Test(arguments: [("0", 0.0), ("5520922478", 55.20922478), (#""6653244286""#, 66.53244286)])
    func `numeric zero and reported Console totals preserve microcent scale`(raw: String, usd: Double) throws {
        let amount = try OpenCodeConsoleUsageFetcher.parseSummary(text: "{\"totalCostMicroCents\":\(raw)}")

        #expect(amount == usd)
    }

    @Test(arguments: ["org_SELECTED123", "https://opencode.ai/console/org_SELECTED123/billing"])
    func `organization IDs survive raw and Console URL overrides`(override: String) async throws {
        let transport = ConsoleUsageTransport(replies: [Self.goPath: .init(body: Self.quota)])

        _ = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: Self.consoleCookie,
            timeout: 17,
            now: Self.now,
            workspaceIDOverride: override,
            session: transport)

        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath])
        #expect(requests.first?.value(forHTTPHeaderField: "x-org-id") == "org_SELECTED123")
    }

    @Test
    func `Console unauthorized can fall back to valid legacy quota`() async throws {
        let transport = ConsoleUsageTransport(replies: [
            Self.goPath: .init(status: 401, body: #"{"error":"unauthorized"}"#),
            "/_server": .init(body: Self.legacyQuota),
        ])

        let snapshot = try await Self.fetch(transport: transport, cookieHeader: Self.bothCookies)

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath, "/_server"])
        #expect(requests.last?.value(forHTTPHeaderField: "Referer")?.contains(Self.workspaceID) == true)
    }

    @Test
    func `recoverable Console timeout can use valid legacy quota`() async throws {
        let transport = ConsoleUsageTransport(
            replies: ["/_server": .init(body: Self.legacyQuota)],
            failures: [Self.goPath: .timeout])

        let snapshot = try await Self.fetch(transport: transport, cookieHeader: Self.bothCookies)

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath, "/_server"])
    }

    @Test(arguments: [403, 500])
    func `Console API errors survive a signed out legacy fallback`(status: Int) async throws {
        let transport = ConsoleUsageTransport(replies: [
            Self.goPath: .init(status: status, body: #"{"error":"not associated with an account"}"#),
            "/_server": .init(body: "<html><body>Please sign in to continue</body></html>"),
        ])

        do {
            _ = try await Self.fetch(transport: transport, cookieHeader: Self.bothCookies)
            Issue.record("Expected Console permission error")
        } catch let OpenCodeUsageError.apiError(message) {
            #expect(message == "Console HTTP \(status)")
        }
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath, "/_server"])
    }

    @Test
    func `invalid explicit workspace never falls back to account discovery`() async throws {
        let transport = ConsoleUsageTransport(replies: [:])
        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: Self.consoleCookie,
                timeout: 17,
                workspaceIDOverride: "not-a-workspace",
                session: transport)
            Issue.record("Expected invalid workspace override")
        } catch let OpenCodeUsageError.apiError(message) {
            #expect(message == "Invalid workspace override.")
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test
    func `Console only credentials never trigger a legacy authentication request`() async throws {
        let transport = ConsoleUsageTransport(replies: [
            Self.goPath: .init(status: 401, body: #"{"error":"unauthorized"}"#),
        ])

        do {
            _ = try await Self.fetch(transport: transport)
            Issue.record("Expected invalid Console credentials")
        } catch OpenCodeUsageError.invalidCredentials {
            // The legacy endpoint has no applicable session cookie.
        }
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath])
    }

    @Test(arguments: [ConsoleUsageTransport.Failure.cancellation, .cancelledURL, .tls])
    func `cancellation and TLS failures never fall back to legacy`(
        failure: ConsoleUsageTransport.Failure) async throws
    {
        let transport = ConsoleUsageTransport(replies: [:], failures: [Self.goPath: failure])

        do {
            _ = try await Self.fetch(transport: transport, cookieHeader: Self.bothCookies)
            Issue.record("Expected transport failure")
        } catch {
            if failure == .tls {
                #expect((error as? URLError)?.code == .serverCertificateUntrusted)
            } else {
                #expect(error is CancellationError)
            }
        }
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [Self.goPath])
    }

    private static func fetch(
        transport: ConsoleUsageTransport,
        cookieHeader: String = Self.consoleCookie) async throws -> OpenCodeUsageSnapshot
    {
        try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: cookieHeader,
            timeout: 17,
            now: self.now,
            workspaceIDOverride: self.workspaceID,
            session: transport)
    }

    private static func payAsYouGoReplies(goStatus: String = "null") -> [String: ConsoleUsageTransport.Reply] {
        [
            goPath: .init(body: goStatus),
            orgPath: .init(body: #"{"id":"wrk_CONSOLE123","hasGoSubscription":false}"#),
            summaryPath: .init(body: #"{"totalCostMicroCents":"325000000","totalRequests":12}"#),
            billingPath: .init(body: """
            {"billingMode":"prepaid","mode":"pay-as-you-go","balanceMicroCents":"1250000000",
             "creditLimitMicroCents":"99900000000","dailyLimitMicroCents":"2000000000"}
            """),
        ]
    }
}

actor ConsoleUsageTransport: ProviderHTTPTransport {
    struct Reply: Sendable {
        var status = 200
        let body: String
    }

    enum Failure: Equatable, Sendable {
        case cancellation
        case cancelledURL
        case tls
        case timeout
    }

    private let replies: [String: Reply]
    private let failures: [String: Failure]
    private var recordedRequests: [URLRequest] = []

    init(replies: [String: Reply], failures: [String: Failure] = [:]) {
        self.replies = replies
        self.failures = failures
    }

    func requests() -> [URLRequest] {
        self.recordedRequests
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.recordedRequests.append(request)
        let url = try #require(request.url)
        switch self.failures[url.path] {
        case .cancellation: throw CancellationError()
        case .cancelledURL: throw URLError(.cancelled)
        case .tls: throw URLError(.serverCertificateUntrusted)
        case .timeout: throw URLError(.timedOut)
        case nil: break
        }
        let reply = try #require(self.replies[url.path], "Unexpected request to \(url.path)")
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]))
        return (Data(reply.body.utf8), response)
    }
}
