import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ZedPluginLinuxTests {
    @Test
    func `Zed cycle at exactly 24h rolls over to a day through the portable plugin`() async throws {
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "zed",
            transport: ProviderHTTPTransportHandler { request in
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                let body = #"""
                {"user":{"id":42,"github_login":"fixture"},"plan":{
                  "plan_v3":"zed_pro","has_overdue_invoices":false,
                  "usage":{"edit_predictions":{"used":0,"limit":"unlimited"}},
                  "subscription_period":{"started_at":"2026-05-13T00:00:00Z",
                                         "ended_at":"2026-06-13T00:00:00Z"}}}
                """#
                return (Data(body.utf8), response)
            })
        let now = try #require(ISO8601DateParser.parse("2026-06-12T00:00:00Z"))
        let snapshot = try await runtime.fetchUsage(
            settings: ["API_URL": "https://cloud.zed.dev/client/users/me"],
            secrets: ["EDITOR_AUTH": "42 fixture-token"],
            now: now,
            sourceMode: .api)
        #expect(snapshot.secondary?.resetDescription == "Cycle ends in 1d 0h")
    }
}
