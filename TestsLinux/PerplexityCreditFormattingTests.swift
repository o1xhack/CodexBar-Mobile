import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct PerplexityCreditFormattingTests {
    @Test(arguments: [
        (0.0, 300.0, "0/300 credits"),
        (300.0, 300.0, "300/300 credits"),
        (1.6, 10.9, "2/10 credits"),
        (-0.25, 10.9, "0/10 credits"),
        (1e20, 2e20, "100000000000000000000/200000000000000000000 credits"),
    ])
    func `credit descriptions retain zero rounding and large counts on every platform`(
        used: Double,
        total: Double,
        expected: String) async throws
    {
        let data = Data("""
        {
          "balance_cents": 0,
          "renewal_date_ts": 1743000000,
          "current_period_purchased_cents": 0,
          "credit_grants": [{"type":"recurring","amount_cents":\(total)}],
          "total_usage_cents": \(used)
        }
        """.utf8)
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "perplexity", transport: ProviderHTTPTransportHandler { request in
                (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        let usage = try await runtime.fetchUsage(
            now: Date(timeIntervalSince1970: 1_740_000_000),
            cookieResolver: { _, _ in "authjs.session-token=fixture" })

        #expect(usage.primary?.resetDescription == expected)
        #expect(usage.secondary?.resetDescription == "0/0 bonus")
        #expect(usage.tertiary?.resetDescription == "0/0 credits")
    }
}
