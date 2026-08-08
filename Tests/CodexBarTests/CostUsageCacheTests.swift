import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageCacheTests {
    @Test
    func `legacy codex token cache decodes without reasoning while current rows round trip it`() throws {
        let legacyTotals = try JSONDecoder().decode(
            CostUsageCodexTotals.self,
            from: Data(#"{"input":10,"cached":2,"output":4}"#.utf8))
        #expect(legacyTotals.reasoning == nil)

        let legacyRow = try JSONDecoder().decode(
            CostUsageScanner.CodexUsageRow.self,
            from: Data(#"{"day":"2026-07-17","model":"gpt-5.5","input":10,"cached":2,"output":4}"#.utf8))
        #expect(legacyRow.reasoning == nil)

        let currentRow = CostUsageScanner.CodexUsageRow(
            day: "2026-07-17",
            model: "gpt-5.5",
            turnID: "turn",
            eventIndex: 1,
            input: 10,
            cached: 2,
            output: 4,
            reasoning: 3)
        let roundTripped = try JSONDecoder().decode(
            CostUsageScanner.CodexUsageRow.self,
            from: JSONEncoder().encode(currentRow))
        #expect(roundTripped.reasoning == 3)
    }

    @Test
    func `cache file URL uses provider artifact versions`() {
        let root = URL(fileURLWithPath: "/tmp/codexbar-cost-cache", isDirectory: true)

        let codexURL = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        let claudeURL = CostUsageCacheIO.cacheFileURL(provider: .claude, cacheRoot: root)
        let vertexURL = CostUsageCacheIO.cacheFileURL(provider: .vertexai, cacheRoot: root)

        #expect(codexURL.lastPathComponent == "codex-v11.json")
        #expect(claudeURL.lastPathComponent == "claude-v6.json")
        #expect(vertexURL.lastPathComponent == "vertexai-v6.json")
    }

    @Test
    func `cost cache ignores predecessor artifact with persisted offset`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyURL = root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("codex-v9.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let producerKey = try #require(CostUsageCacheIO.currentProducerKey(provider: .codex))
        let legacy = """
        {
          "version": 1,
          "producerKey": "\(producerKey)",
          "lastScanUnixMs": 999,
          "files": {
            "/tmp/session.jsonl": {
              "mtimeUnixMs": 1,
              "size": 100,
              "days": {},
              "parsedBytes": 100
            }
          },
          "days": {}
        }
        """
        try legacy.write(to: legacyURL, atomically: false, encoding: .utf8)

        let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)

        #expect(loaded.lastScanUnixMs == 0)
        #expect(loaded.files.isEmpty)
    }

    @Test
    func `Pi session cache ignores predecessor artifact with persisted offset`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyURL = root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("pi-sessions-v7.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        var legacy = PiSessionCostCache(version: 7)
        legacy.lastScanUnixMs = 999
        legacy.files = [
            "/tmp/session.jsonl": PiSessionFileUsage(
                mtimeUnixMs: 1,
                size: 100,
                parsedBytes: 100,
                lastModelContext: nil,
                contributions: [:]),
        ]
        try JSONEncoder().encode(legacy).write(to: legacyURL)

        let loaded = PiSessionCostCacheIO.load(cacheRoot: root)

        #expect(loaded.version == 8)
        #expect(loaded.lastScanUnixMs == 0)
        #expect(loaded.files.isEmpty)
    }

    // MARK: - Pricing fingerprint mechanism

    @Test
    func `pricingFingerprint is stable across calls`() {
        let f1 = CostUsagePricing.pricingFingerprint
        let f2 = CostUsagePricing.pricingFingerprint
        #expect(f1 == f2, "Fingerprint must be deterministic — cache validation depends on it.")
        #expect(!f1.isEmpty, "Fingerprint must be non-empty.")
    }

    @Test
    func `pricingFingerprint includes parser logic version`() {
        // The string format is contract: it starts with `v{N}|` where N is
        // `parserLogicVersion`. Tests below rely on this prefix to detect
        // when the parser version was bumped.
        #expect(CostUsagePricing.pricingFingerprint.hasPrefix("v\(CostUsagePricing.parserLogicVersion)|"))
    }

    @Test
    func `pricingFingerprint mentions both codex and claude tables`() {
        let f = CostUsagePricing.pricingFingerprint
        #expect(f.contains("codex="), "Codex pricing keys must be in the fingerprint.")
        #expect(f.contains("claude="), "Claude pricing keys must be in the fingerprint.")
    }

    @Test
    func `pricingFingerprint includes known pricing keys`() {
        let f = CostUsagePricing.pricingFingerprint
        // Sanity: a few keys that MUST be in the table for this build.
        // 0.23.3 P1-2: fingerprint now includes price values, so each
        // key is followed by `:<numbers>` instead of just `,`. We assert
        // on the leading `<key>:` form so the test rolls naturally if
        // we ever swap separators.
        #expect(
            f.contains("gpt-5:"),
            "gpt-5 should be in codex pricing table.")
        #expect(
            f.contains("gpt-5.5:"),
            "gpt-5.5 should be in codex pricing table (added in fork 0.23).")
        #expect(
            f.contains("claude-opus-4-7:"),
            "claude-opus-4-7 should be in claude pricing table (added in fork 0.23).")
    }

    @Test
    func `pricingFingerprint rolls when a price changes (P1-2 contract)`() {
        // We can't actually mutate the pricing table at runtime, so this
        // test pins the *contract*: the current fingerprint must contain
        // numeric price values for each key, not just the key names.
        // 0.23.3 P1-2 fix: previously the fingerprint was keys-only, so
        // a same-name reprice (gpt-5 cost changes from $1.25/M → $1.0/M)
        // didn't roll → stale `costNanos` baked into PiSessionCostCache
        // survived the upgrade. The format now embeds prices so any
        // edit rolls.
        let f = CostUsagePricing.pricingFingerprint
        // The current gpt-5 price is 1.25e-6 input / 1e-5 output. We
        // assert the input-price digits show up adjacent to the key.
        #expect(
            f.contains("gpt-5:1.25e-06") || f.contains("gpt-5:0.00000125"),
            "gpt-5 input price (1.25e-6) should be in fingerprint.")
        // claude-opus-4-7 has input 5e-6, output 2.5e-5; the entry
        // starts with `claude-opus-4-7:5e-06:2.5e-05:...`
        #expect(
            f.contains("claude-opus-4-7:5e-06"),
            "claude-opus-4-7 input price (5e-6) should be in fingerprint.")
    }

    // MARK: - Cache load/save fingerprint validation

    @Test
    func `loading a cache with no fingerprint returns empty`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Simulate a pre-0.23.1 cache file: valid version=1 but no
        // fingerprint field. JSON decode succeeds, but load() rejects it
        // because pricingFingerprint==nil mismatches the current expected
        // value, forcing a fresh re-scan.
        let url = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let legacyJSON = #"{"version":1,"lastScanUnixMs":12345,"files":{},"days":{}}"#
        try Data(legacyJSON.utf8).write(to: url)

        let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(
            loaded.lastScanUnixMs == 0,
            "Cache from a build with no fingerprint must be invalidated on load.")
        #expect(
            loaded.pricingFingerprint == CostUsagePricing.pricingFingerprint,
            "Fresh cache must carry the current fingerprint so subsequent saves stamp it.")
    }

    @Test
    func `loading a cache with a stale fingerprint returns empty`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let staleJSON = """
        {"version":1,"lastScanUnixMs":99999,"pricingFingerprint":"v0|codex=stale|claude=stale","files":{},"days":{}}
        """
        try Data(staleJSON.utf8).write(to: url)

        let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(loaded.lastScanUnixMs == 0)
    }

    @Test
    func `saving a cache stamps the current fingerprint, even if caller forgot`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Caller synthesizes a CostUsageCache without going through load(),
        // forgetting to set the fingerprint. save() must still stamp it so
        // a future launch can validate.
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 42
        cache.pricingFingerprint = nil

        CostUsageCacheIO.save(provider: .codex, cache: cache, cacheRoot: root)

        let reloaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(
            reloaded.lastScanUnixMs == 42,
            "Save+load roundtrip should preserve data when fingerprint matches.")
        #expect(reloaded.pricingFingerprint == CostUsagePricing.pricingFingerprint)
    }

    @Test
    func `saving and reloading roundtrips lastScanUnixMs`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var fresh = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        fresh.lastScanUnixMs = 1_700_000_000
        CostUsageCacheIO.save(provider: .codex, cache: fresh, cacheRoot: root)

        let reloaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)
        #expect(reloaded.lastScanUnixMs == 1_700_000_000)
    }

    @Test
    func `saving a cache atomically replaces the existing artifact`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var cache = CostUsageCache()
        cache.lastScanUnixMs = 1
        CostUsageCacheIO.save(provider: .codex, cache: cache, cacheRoot: root)
        cache.lastScanUnixMs = 2
        CostUsageCacheIO.save(provider: .codex, cache: cache, cacheRoot: root)

        let url = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(CostUsageCacheIO.load(provider: .codex, cacheRoot: root).lastScanUnixMs == 2)
    }

    @Test
    func `cache load requires matching producer key`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var cache = CostUsageCache()
        cache.lastScanUnixMs = 123
        cache.days = ["2026-05-18": ["gpt-5.5": [1, 2, 3]]]

        CostUsageCacheIO.save(
            provider: .codex,
            cache: cache,
            cacheRoot: root,
            producerKey: "codex:cu:p1111111111111111")

        let loaded = CostUsageCacheIO.load(
            provider: .codex,
            cacheRoot: root,
            producerKey: "codex:cu:p1111111111111111")
        #expect(loaded.producerKey == "codex:cu:p1111111111111111")
        #expect(loaded.lastScanUnixMs == 123)
        #expect(loaded.days["2026-05-18"]?["gpt-5.5"] == [1, 2, 3])

        let stale = CostUsageCacheIO.load(
            provider: .codex,
            cacheRoot: root,
            producerKey: "codex:cu:p2222222222222222")
        #expect(stale.lastScanUnixMs == 0)
        #expect(stale.files.isEmpty)
        #expect(stale.days.isEmpty)

        let migration = CostUsageCacheIO.loadCodexForMigration(
            cacheRoot: root,
            producerKey: "codex:cu:p2222222222222222")
        #expect(migration.cache.days.isEmpty)
        #expect(migration.incompatibleCache?.producerKey == "codex:cu:p1111111111111111")
        #expect(migration.incompatibleCache?.days["2026-05-18"]?["gpt-5.5"] == [1, 2, 3])
    }

    @Test
    func `legacy cache without producer key is ignored`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = CostUsageCacheIO.cacheFileURL(provider: .codex, cacheRoot: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let legacy = """
        {
          "version": 1,
          "lastScanUnixMs": 999,
          "files": {},
          "days": {
            "2026-05-18": {
              "gpt-5": [1, 0, 0]
            }
          }
        }
        """
        try legacy.write(to: url, atomically: false, encoding: .utf8)

        let loaded = CostUsageCacheIO.load(
            provider: .codex,
            cacheRoot: root,
            producerKey: "codex:cu:p1111111111111111")

        #expect(loaded.lastScanUnixMs == 0)
        #expect(loaded.days.isEmpty)
    }

    @Test
    func `current codex cache rejects pre interleave containment producers`() throws {
        // Interleave containment (#2037) changed cumulative delta semantics, so caches from
        // previously compatible parser hashes must be rebuilt instead of reused.
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        for legacyProducerKey in ["codex:cu:p3c27f997569eb3c5", "codex:cu:pc54070a94f6419ea"] {
            var cache = CostUsageCache()
            cache.lastScanUnixMs = 123
            cache.days = ["2026-05-18": ["gpt-5.5": [1, 2, 3]]]
            CostUsageCacheIO.save(
                provider: .codex,
                cache: cache,
                cacheRoot: root,
                producerKey: legacyProducerKey)

            let loaded = CostUsageCacheIO.load(provider: .codex, cacheRoot: root)

            #expect(loaded.lastScanUnixMs == 0)
            #expect(loaded.days.isEmpty)
        }
    }

    @Test
    func `non codex cache does not require producer key`() throws {
        let root = try self.makeTemporaryCacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Non-codex providers have no producerKey (currentProducerKey is
        // codex-only), so the producerKey gate must not block their reload.
        // Save through the normal path so the cache carries the current
        // pricingFingerprint: the fork's fingerprint guard still applies to
        // every provider (a fingerprint-less *legacy* cache is correctly
        // invalidated — see `loading a cache with no fingerprint returns
        // empty`), so this test pins producerKey-independence, not a
        // fingerprint bypass.
        var cache = CostUsageCache()
        cache.lastScanUnixMs = 999
        cache.days = ["2026-05-18": ["claude-sonnet-4-5": [1, 0, 0]]]
        CostUsageCacheIO.save(provider: .claude, cache: cache, cacheRoot: root)

        let loaded = CostUsageCacheIO.load(provider: .claude, cacheRoot: root)

        #expect(loaded.lastScanUnixMs == 999)
        #expect(loaded.days["2026-05-18"]?["claude-sonnet-4-5"] == [1, 0, 0])
    }

    @Test
    func `current producer key uses generated parser hash for codex only`() {
        let codexKey = CostUsageCacheIO.currentProducerKey(
            provider: .codex,
            parserHash: "abc1234567890def")
        let standaloneKey = CostUsageCacheIO.currentProducerKey(
            provider: .claude,
            parserHash: "abc1234567890def")

        #expect(codexKey == "codex:cu:pabc1234567890def")
        #expect(standaloneKey == nil)
    }

    @Test
    func `generated parser hash is stable short lowercase hex`() {
        let hash = CodexParserHash.value

        #expect(hash.range(of: #"^[0-9a-f]{16}$"#, options: .regularExpression) != nil)
        #expect(CostUsageCacheIO.currentProducerKey(provider: .codex) == "codex:cu:p\(hash)")
    }

    private func makeTemporaryCacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cost-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
