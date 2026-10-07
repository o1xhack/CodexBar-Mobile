import Foundation
import Testing
@testable import CodexBarCore

struct PiSessionCostScannerCacheWriteTests {
    private static let spellings = ["cacheWrite1h", "cache_write_1h", "ephemeral1h", "ephemeral_1h"]

    @Test(arguments: Self.spellings)
    func `an explicit zero counter remains measured usage`(spelling: String) throws {
        let fixture = try Fixture()
        defer { fixture.env.cleanup() }
        try fixture.write(extras: Self.counter(spelling, value: 0), includeStandardCounters: false)
        let result = try fixture.scan()
        #expect(result.isComplete)
        #expect(result.report.summary?.totalTokens == 0)
    }

    @Test(arguments: Self.spellings)
    func `one hour spellings preserve tokens and use the higher tariff`(spelling: String) throws {
        let fixture = try Fixture()
        defer { fixture.env.cleanup() }
        try fixture.write(extras: Self.counter(spelling, value: 40))
        let result = try fixture.scan()
        #expect(result.isComplete)
        #expect(result.report.summary?.totalTokens == 204)
        let cost = try #require(result.report.summary?.totalCostUSD)
        // Sonnet: 80 input, 20 output, 4 reads, 60 five-minute writes, 40 one-hour writes.
        #expect(abs(cost - 0.0010062) < 1e-12)
    }

    @Test(arguments: Self.spellings, ["null", "true", "\"junk\"", "-5", "1e19", "101"])
    func `invalid one hour counters drop the row and leave history incomplete`(
        spelling: String, json: String) throws
    {
        let fixture = try Fixture()
        defer { fixture.env.cleanup() }
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
        try fixture.write(extras: Self.counter(spelling, value: value))
        let result = try fixture.scan()
        #expect(!result.isComplete)
        #expect(result.report.data.isEmpty)
    }

    @Test
    func `first present spelling wins without masking malformed counters`() throws {
        let cases: [(extras: [String: Any], oneHour: Int?)] = [
            (["cacheWrite1h": 10, "cache_write_1h": 20, "cttl": ["ephemeral1h": 40]], 10),
            (["cache_write_1h": 20, "cttl": ["ephemeral1h": 40]], 20),
            (["cttl": ["ephemeral1h": 40, "ephemeral_1h": 50]], 40),
            (["cacheWrite1h": NSNull(), "cttl": ["ephemeral1h": 40]], nil),
            (["cache_write_1h": "junk", "cttl": ["ephemeral1h": 40]], nil),
            (["cttl": ["ephemeral1h": true, "ephemeral_1h": 40]], nil),
            (["cacheWrite1h": "40"], 40),
            (["cttl": ["ephemeral1h": 40.7]], 41),
            (["cttl": ["ephemeral5m": 100]], 0),
            (["cttl": "not-an-object"], 0),
            ([:], 0),
        ]
        for (extras, oneHour) in cases {
            let fixture = try Fixture()
            defer { fixture.env.cleanup() }
            try fixture.write(extras: extras)
            let result = try fixture.scan()
            #expect(result.isComplete == (oneHour != nil))
            if let oneHour {
                let cost = try #require(result.report.summary?.totalCostUSD)
                #expect(abs(cost - (0.0009162 + Double(oneHour) * 0.00000225)) < 1e-12)
                #expect(result.report.summary?.totalTokens == 204)
            } else {
                #expect(result.report.data.isEmpty)
            }
        }
    }

    @Test
    func `formula three cache is repriced once even inside the debounce window`() throws {
        let fixture = try Fixture()
        defer { fixture.env.cleanup() }
        try fixture.write(extras: ["cttl": ["ephemeral1h": 40]])
        _ = try fixture.scan()
        var predecessor = PiSessionCostCacheIO.load(cacheRoot: fixture.env.cacheRoot)
        predecessor.pricingKey = CostUsagePricingKey.codex(
            modelsDevArtifact: ModelsDevCache.load(now: fixture.day, cacheRoot: fixture.env.cacheRoot).artifact,
            formulaVersion: 3,
            parserHash: CodexParserHash.value,
            modelsDevProviderIDs: CostUsagePricing.codexModelsDevProviderIDs.union(
                Set(CostUsagePricing.claudeFirstPartyModelsDevProviderIDs + ["amazon-bedrock"])),
            customPricingFingerprint: CostUsageCustomPricing.load().fingerprint)
        predecessor.files = predecessor.files.mapValues { file in
            var file = file
            file.contributions = file.contributions.mapValues { days in
                days.mapValues { models in
                    models.mapValues { usage in
                        var usage = usage
                        usage.costNanos = 1
                        return usage
                    }
                }
            }
            return file
        }
        PiSessionCostCacheIO.save(cache: predecessor, cacheRoot: fixture.env.cacheRoot)
        #expect(PiSessionCostScanner.loadCachedDailyReport(
            provider: .pi,
            since: fixture.day,
            until: fixture.day,
            now: fixture.day,
            cacheRoot: fixture.env.cacheRoot) == nil)
        let repriced = try fixture.scan(now: fixture.day.addingTimeInterval(1))
        #expect(repriced.isComplete)
        let cost = try #require(repriced.report.summary?.totalCostUSD)
        #expect(abs(cost - 0.0010062) < 1e-12)
        #expect(repriced.report.summary?.totalTokens == 204)
        let observer: @Sendable () -> Void = {
            Issue.record("Unchanged sessions with the current pricing key must not be reparsed")
        }
        let cached = try PiSessionCostScanner.$sessionParseObserverForTesting.withValue(observer) {
            try fixture.scan(now: fixture.day.addingTimeInterval(2))
        }
        #expect(cached.report.data == repriced.report.data)
        #expect(cached.report.summary == repriced.report.summary)
        #expect(cached.lastScanAt == repriced.lastScanAt)
    }

    @Test
    func `codex pricing does not bill the one hour subset twice`() throws {
        let fixture = try Fixture()
        defer { fixture.env.cleanup() }
        try fixture.write(extras: ["cttl": ["ephemeral1h": 40]], provider: "openai-codex", model: "gpt-5.4")
        let result = try fixture.scan()
        #expect(result.isComplete)
        #expect(result.report.summary?.totalTokens == 204)
        let expected = try #require(CostUsagePricing.codexCostUSD(
            model: "gpt-5.4",
            inputTokens: 184,
            cachedInputTokens: 4,
            outputTokens: 20,
            cacheWriteInputTokens: 100,
            pricingDate: fixture.day,
            modelsDevCacheRoot: fixture.env.cacheRoot))
        let actual = try #require(result.report.summary?.totalCostUSD)
        #expect(abs(actual - expected) < 1e-9)
    }

    @Test
    func `numeric timestamp forms share seconds and milliseconds handling`() throws {
        let fixture = try Fixture()
        defer { fixture.env.cleanup() }
        let seconds = fixture.day.timeIntervalSince1970
        let timestamps: [Any] = [seconds, seconds * 1000, String(seconds), String(seconds * 1000)]
        for timestamp in timestamps {
            try fixture.write(extras: [:], timestamp: timestamp)
            let result = try fixture.scan(forceRescan: true)
            #expect(result.isComplete)
            #expect(result.report.summary?.totalTokens == 204)
        }
    }

    private static func counter(_ spelling: String, value: Any) -> [String: Any] {
        spelling.hasPrefix("ephemeral") ? ["cttl": [spelling: value]] : [spelling: value]
    }

    private struct Fixture {
        let env: CostUsageTestEnvironment
        let day: Date

        init() throws {
            self.env = try CostUsageTestEnvironment()
            self.day = try self.env.makeLocalNoon(year: 2026, month: 9, day: 30)
        }

        func write(
            extras: [String: Any],
            provider: String = "anthropic",
            model: String = "claude-sonnet-4-6",
            timestamp: Any? = nil,
            includeStandardCounters: Bool = true) throws
        {
            var usage: [String: Any] = includeStandardCounters ? [
                "input": 80, "output": 20, "cacheRead": 4, "cacheWrite": 100, "totalTokens": 204,
            ] : [:]
            usage.merge(extras) { _, value in value }
            let entry: [String: Any] = [
                "type": "message", "timestamp": self.env.isoString(for: self.day),
                "message": [
                    "role": "assistant", "provider": provider, "model": model, "usage": usage,
                    "timestamp": timestamp ?? self.env.isoString(for: self.day),
                ],
            ]
            _ = try self.env.writePiSessionFile(
                relativePath: "2026-09-30T12-00-00-000Z_cache-write.jsonl", contents: self.env.jsonl([entry]))
        }

        func scan(now: Date? = nil, forceRescan: Bool = false) throws -> PiSessionCostScanner.DailyReportResult {
            try PiSessionCostScanner.loadDailyReportResultCancellable(
                provider: .pi,
                since: self.day,
                until: self.day,
                now: now ?? self.day,
                options: .init(
                    piSessionsRoot: self.env.piSessionsRoot,
                    cacheRoot: self.env.cacheRoot,
                    refreshMinIntervalSeconds: 3600,
                    forceRescan: forceRescan),
                checkCancellation: nil)
        }
    }
}
