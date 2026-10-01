import Foundation
import Testing
@testable import CodexBarCore

struct CodexSolHistoricalPricingTests {
    @Test(arguments: ["gpt-5.6-sol", "gpt-5.6"], [100, 272_001])
    func `Sol keeps historical rates before its August repricing`(
        model: String, input: Int) throws
    {
        let catalog = try JSONDecoder().decode(ModelsDevCatalog.self, from: Data(#"""
        {"openai":{"id":"openai","models":{"gpt-5.6-sol":{
          "id":"gpt-5.6-sol","cost":{"input":4,"cache_read":0.4,"cache_write":5,"output":20}
        }}}}
        """#.utf8))
        let cutoff = try #require(ISO8601DateParser.parse("2026-08-21T00:00:00Z"))
        for sourceCatalog in [catalog, ModelsDevCatalog(providers: [:])] {
            let resolvers: [CostUsagePricing.CodexResolver?] = [nil, .init(catalog: sourceCatalog)]
            for resolver in resolvers {
                for (date, historical) in [(cutoff.addingTimeInterval(-1), true), (cutoff, false)] {
                    let longContext = input > 272_000
                    let inputRate = historical ? (longContext ? 10.0 : 5) : (longContext ? 8.0 : 4)
                    let outputRate = historical ? (longContext ? 45.0 : 30) : (longContext ? 30.0 : 20)
                    let expected = (Double(input - 30) * inputRate + inputRate + 25 * inputRate + 5 * outputRate)
                        / 1_000_000
                    let standard = try #require(CostUsagePricing.codexCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        outputTokens: 5,
                        cacheWriteInputTokens: 20,
                        pricingDate: date,
                        modelsDevCatalog: sourceCatalog,
                        pricingResolver: resolver))
                    #expect(abs(standard - expected) < 1e-12)
                    let fast = CostUsagePricing.codexPriorityCostUSD(
                        model: model,
                        inputTokens: input,
                        cachedInputTokens: 10,
                        cacheWriteInputTokens: 20,
                        outputTokens: 5,
                        pricingDate: date,
                        modelsDevCatalog: sourceCatalog,
                        pricingResolver: resolver)
                    if longContext {
                        #expect(fast == nil)
                    } else {
                        let fast = try #require(fast)
                        #expect(abs(fast - expected * 2) < 1e-12)
                    }
                }
            }
        }
        #expect(CostUsagePricing.codexCostUSD(
            model: "fixture-unknown-model",
            inputTokens: input,
            cachedInputTokens: 0,
            outputTokens: 5,
            modelsDevCatalog: catalog) == nil)
    }
}
