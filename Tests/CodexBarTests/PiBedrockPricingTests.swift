import Foundation
import Testing
@testable import CodexBarCore

struct PiBedrockPricingTests {
    @Test
    func `bedrock keeps regional prices and stays out of native provider mirrors`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 29)
        let global = "global.anthropic.claude-sonnet-4-6"
        let regional = "us.anthropic.claude-sonnet-4-6"
        let unknownRegion = "eu.anthropic.claude-sonnet-4-6"
        let other = "global.openai.gpt-5.4"
        let catalog = try self.catalog(models: [global: 3, regional: 3.3, other: 2, "claude-sonnet-4-6": 3])
        #expect(ModelsDevCache.save(catalog: catalog, fetchedAt: day, cacheRoot: env.cacheRoot))
        let rows = [global, regional, other, unknownRegion].map {
            self.row(env: env, day: day, provider: "amazon-bedrock", model: $0)
        }
        _ = try env.writePiSessionFile(relativePath: "bedrock.jsonl", contents: env.jsonl(rows))
        let result = try self.scan(env: env, day: day)
        #expect(result.isComplete)
        #expect(result.report.summary?.totalTokens == 4 * 140)
        let models = try #require(result.report.data.first?.modelBreakdowns)
        #expect(models.first { $0.modelName == global }?.costUSD == 0.000435)
        #expect(models.first { $0.modelName == regional }?.costUSD == 0.000465)
        #expect(models.first { $0.modelName == other }?.costUSD == 0.000335)
        #expect(models.first { $0.modelName == unknownRegion }?.costUSD == nil)
        #expect(result.report.data.first?.unpricedRequestCount == 1)
        for provider in [UsageProvider.codex, .claude] {
            #expect(try self.scan(env: env, day: day, provider: provider).report.data.isEmpty)
        }
        let cached = PiSessionCostScanner.loadCachedDailyReport(
            provider: .pi, since: day, until: day, now: day, cacheRoot: env.cacheRoot)
        #expect(cached?.summary?.totalTokens == 560)

        #expect(try ModelsDevCache.save(
            catalog: self.catalog(models: [global: 6, regional: 3.3, other: 2]),
            fetchedAt: day,
            cacheRoot: env.cacheRoot))
        let repriced = try self.scan(env: env, day: day)
        #expect(repriced.report.data.first?.modelBreakdowns?.first { $0.modelName == global }?.costUSD == 0.000735)
    }

    @Test
    func `one hour cache writes are a subset of total writes for anthropic and bedrock`() throws {
        for provider in ["anthropic", "amazon-bedrock"] {
            let env = try CostUsageTestEnvironment()
            defer { env.cleanup() }
            let day = try env.makeLocalNoon(year: 2026, month: 9, day: 29)
            let model = provider == "anthropic" ? "claude-sonnet-4-6" : "us.anthropic.claude-sonnet-4-6"
            #expect(try ModelsDevCache.save(
                catalog: self.catalog(models: [model: 3.3]), fetchedAt: day, cacheRoot: env.cacheRoot))
            let row = self.row(env: env, day: day, provider: provider, model: model, oneHour: 6)
            _ = try env.writePiSessionFile(relativePath: "cache.jsonl", contents: env.jsonl([row]))
            let result = try self.scan(env: env, day: day)
            #expect(result.isComplete)
            #expect(result.report.summary?.totalTokens == 140)
            let expected = provider == "anthropic" ? 0.000654 : 0.0004866
            #expect(abs((result.report.summary?.totalCostUSD ?? 0) - expected) < 0.000000001)

            var releasedCache = PiSessionCostCacheIO.load(cacheRoot: env.cacheRoot)
            releasedCache.pricingKey = CostUsagePricingKey.codex(
                modelsDevArtifact: ModelsDevCache.load(now: day, cacheRoot: env.cacheRoot).artifact,
                formulaVersion: 2,
                parserHash: CodexParserHash.value,
                modelsDevProviderIDs: CostUsagePricing.codexModelsDevProviderIDs.union(
                    Set(CostUsagePricing.claudeFirstPartyModelsDevProviderIDs)),
                customPricingFingerprint: CostUsageCustomPricing.load().fingerprint)
            releasedCache.daysByProvider = [:]
            PiSessionCostCacheIO.save(cache: releasedCache, cacheRoot: env.cacheRoot)
            let upgraded = try self.scan(env: env, day: day)
            #expect(abs((upgraded.report.summary?.totalCostUSD ?? 0) - expected) < 0.000000001)
        }
    }

    @Test
    func `invalid one hour cache counters cannot publish complete history`() throws {
        for counter: Any in [-1, true, "invalid", 11] {
            let env = try CostUsageTestEnvironment()
            defer { env.cleanup() }
            let day = try env.makeLocalNoon(year: 2026, month: 9, day: 29)
            let row = self.row(
                env: env, day: day, provider: "anthropic", model: "claude-sonnet-4-6", oneHour: counter)
            _ = try env.writePiSessionFile(relativePath: "invalid.jsonl", contents: env.jsonl([row]))
            let result = try self.scan(env: env, day: day)
            #expect(!result.isComplete)
            #expect(result.report.data.isEmpty)
        }
    }

    private func row(
        env: CostUsageTestEnvironment, day: Date, provider: String, model: String, oneHour: Any = 0) -> [String: Any]
    {
        [
            "type": "message", "timestamp": env.isoString(for: day),
            "message": [
                "role": "assistant", "provider": provider, "model": model,
                "usage": [
                    "input": 100,
                    "output": 20,
                    "cacheRead": 10,
                    "cacheWrite": 10,
                    "cacheWrite1h": oneHour,
                    "totalTokens": 140,
                    "cost": ["total": 99],
                ],
            ],
        ]
    }

    private func catalog(models: [String: Double]) throws -> ModelsDevCatalog {
        let rows: [String: Any] = models.reduce(into: [:]) { result, model in
            result[model.key] = [
                "id": model.key, "cost": ["input": model.value, "output": 5, "cache_read": 0.5, "cache_write": 3],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["amazon-bedrock": ["models": rows]])
        return try JSONDecoder().decode(ModelsDevCatalog.self, from: data)
    }

    private func scan(
        env: CostUsageTestEnvironment, day: Date, provider: UsageProvider = .pi)
        throws -> PiSessionCostScanner.DailyReportResult
    {
        try PiSessionCostScanner.loadDailyReportResultCancellable(
            provider: provider,
            since: day,
            until: day,
            now: day,
            options: .init(
                piSessionsRoot: env.piSessionsRoot, cacheRoot: env.cacheRoot, refreshMinIntervalSeconds: 3600),
            checkCancellation: nil)
    }
}
