import Foundation
import Testing
@testable import CodexBarCore

struct PerplexityPromoExpiryLocaleTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `promo expiry remains English on both engines`(engine: ProviderPluginEngineKind) async throws {
        let body = """
        {
          "balance_cents": 200,
          "renewal_date_ts": 1893456000,
          "current_period_purchased_cents": 0,
          "credit_grants": [
            {
              "type": "promotional",
              "amount_cents": 200,
              "expires_at_ts": 1768478400
            }
          ],
          "total_usage_cents": 0
        }
        """
        let runtime = try BundledPluginTestSupport.runtime(
            "perplexity", engine: engine, transport: ProviderHTTPTransportHandler { request in
                try CookiePluginFixtures.response(request, body: body)
            })
        let usage = try await runtime.fetchUsage(
            now: Date(timeIntervalSince1970: 1_700_000_000),
            timeZone: #require(TimeZone(secondsFromGMT: 0)),
            cookieResolver: { _, _ in "authjs.session-token=fixture" })
        #expect(usage.secondary?.resetDescription == "0/200 bonus · exp. Jan 15")
    }
}
