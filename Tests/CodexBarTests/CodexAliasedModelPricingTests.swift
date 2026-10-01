import Foundation
import Testing
@testable import CodexBarCore

struct CodexAliasedModelPricingTests {
    @Test
    func `codex cost prices daybreak aliases and cyber bundled fallback`() throws {
        // Empty models.dev cache root forces the built-in table.
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let root = env.cacheRoot

        func cost(_ model: String, writes: Int = 0) -> Double? {
            CostUsagePricing.codexCostUSD(
                model: model,
                inputTokens: 100,
                cachedInputTokens: 10,
                outputTokens: 5,
                cacheWriteInputTokens: writes,
                modelsDevCacheRoot: root)
        }

        // Cyber rates per token: $12.50 input, $1.25 cached input, $75 output per 1M.
        let cyber = (90.0 * 1.25e-5) + (10.0 * 1.25e-6) + (5.0 * 7.5e-5)
        #expect(cost("gpt-5.6-cyber") == cyber)
        #expect(cost("gpt-5.5-cyber") == cyber)
        let writeCost = try #require(cost("gpt-5.6-cyber", writes: 20))
        let expectedWriteCost = (70.0 * 1.25e-5) + (10.0 * 1.25e-6) + (20.0 * 1.5625e-5) + (5.0 * 7.5e-5)
        #expect(abs(writeCost - expectedWriteCost) < 1e-12)
        let legacyWriteCost = try #require(cost("gpt-5.5-cyber", writes: 20))
        #expect(abs(legacyWriteCost - cyber) < 1e-12)
        #expect(cost("gpt-daybreak-blue-latest") == cost("gpt-5.6-sol"))
        #expect(cost("gpt-daybreak-red-latest") == cyber)
    }
}
