import Foundation

enum CostUsageCacheIO {
    private static let compatibleCodexProducerKeys: Set<String> = [
        "codex:cu:p3c27f997569eb3c5",
        "codex:cu:pc54070a94f6419ea",
    ]

    private static func artifactVersion(for provider: UsageProvider) -> Int {
        switch provider {
        case .codex:
            // Upstream bumped to 8 in v0.27.0 (further pricing/parser
            // changes: Codex JSONL shape benchmark, per-event token usage
            // preference, long turn-context attribution). Supersedes
            // fork's prior 4 → 5 → 6 history.
            8
        case .claude, .vertexai:
            // Upstream bumped these to v4; the fork still validates the
            // pricing fingerprint below so pricing/table edits force re-scan.
            4
        default:
            1
        }
    }

    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CodexBar", isDirectory: true)
    }

    static func cacheFileURL(provider: UsageProvider, cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? self.defaultCacheRoot()
        let artifactVersion = self.artifactVersion(for: provider)
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("\(provider.rawValue)-v\(artifactVersion).json", isDirectory: false)
    }

    static func load(
        provider: UsageProvider,
        cacheRoot: URL? = nil,
        producerKey: String? = nil) -> CostUsageCache
    {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        let expectedFingerprint = CostUsagePricing.pricingFingerprint
        let expectedProducerKey = producerKey ?? self.currentProducerKey(provider: provider)
        let compatibleProducerKeys = producerKey == nil && provider == .codex
            ? self.compatibleCodexProducerKeys
            : []
        if let decoded = self.loadCache(
            at: url,
            expectedFingerprint: expectedFingerprint,
            expectedProducerKey: expectedProducerKey,
            compatibleProducerKeys: compatibleProducerKeys)
        {
            return decoded
        }
        // Fresh cache stamps the current fingerprint so subsequent saves
        // carry it forward — no separate "first save" path needed.
        var fresh = CostUsageCache()
        fresh.pricingFingerprint = expectedFingerprint
        return fresh
    }

    private static func loadCache(
        at url: URL,
        expectedFingerprint: String,
        expectedProducerKey: String?,
        compatibleProducerKeys: Set<String>) -> CostUsageCache?
    {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(CostUsageCache.self, from: data)
        else { return nil }
        guard decoded.version == 1 else { return nil }
        // Fingerprint mismatch means the pricing tables OR parser logic
        // changed since this cache was written. Token attributions are
        // baked in at parse time and can't be retroactively fixed —
        // safest action is to discard and force a fresh scan. See
        // `CostUsagePricing.pricingFingerprint` for the fingerprint
        // composition.
        guard decoded.pricingFingerprint == expectedFingerprint else { return nil }
        // Upstream's producerKey (scanner source hash, #1042) is a second,
        // independent invalidation axis: a parser-source change rolls the hash
        // even when the pricing fingerprint is unchanged. Validate both so a
        // stale cache is discarded if EITHER signal moves.
        if let expectedProducerKey {
            guard decoded.producerKey == expectedProducerKey
                || decoded.producerKey.map(compatibleProducerKeys.contains) == true
            else { return nil }
        }
        return decoded
    }

    static func save(
        provider: UsageProvider,
        cache: CostUsageCache,
        cacheRoot: URL? = nil,
        producerKey: String? = nil)
    {
        let url = self.cacheFileURL(provider: provider, cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Always stamp the current fingerprint on save so a subsequent
        // app launch will validate the match. Callers building a cache
        // from scratch via `load(...)` already get the right fingerprint;
        // this guard catches paths that synthesize a `CostUsageCache()`
        // directly without going through `load`.
        var stamped = cache
        stamped.pricingFingerprint = CostUsagePricing.pricingFingerprint
        // Also stamp upstream's producerKey so the scanner-hash invalidation
        // axis (#1042) is carried forward on every save, not just on caches
        // built through `load(...)`.
        stamped.producerKey = producerKey ?? self.currentProducerKey(provider: provider)

        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        let data = (try? JSONEncoder().encode(stamped)) ?? Data()
        do {
            try data.write(to: tmp, options: [.atomic])
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    static func currentProducerKey(
        provider: UsageProvider,
        parserHash: String = CodexParserHash.value) -> String?
    {
        guard provider == .codex else { return nil }
        return "\(provider.rawValue):cu:p\(parserHash)"
    }
}

struct CostUsageCache: Codable {
    var version: Int = 1
    var producerKey: String?
    var lastScanUnixMs: Int64 = 0
    var scanSinceKey: String?
    var scanUntilKey: String?
    var codexPricingKey: String?
    var codexPriorityMetadataKey: String?
    var codexProjectMetadataVersion: Int?
    var codexPriorityTurnKeys: [String: String]?
    var codexPriorityTurnIDsByDay: [String: [String]]?

    /// Pricing-table + parser fingerprint at the moment this cache was
    /// written. `CostUsageCacheIO.load` invalidates any cache whose
    /// fingerprint doesn't match the current `CostUsagePricing.pricingFingerprint`.
    /// **Optional** so old caches without the field still decode (they
    /// then mismatch nil ≠ current → invalidated, re-scan, win-win).
    var pricingFingerprint: String?

    /// filePath -> file usage
    var files: [String: CostUsageFileUsage] = [:]

    /// dayKey -> model -> packed usage
    var days: [String: [String: [Int]]] = [:]

    /// rootPath -> mtime (for Claude roots)
    var roots: [String: Int64]?
}

struct CostUsageFileUsage: Codable {
    var mtimeUnixMs: Int64
    var size: Int64
    var days: [String: [String: [Int]]]
    var parsedBytes: Int64?
    var lastModel: String?
    var lastTotals: CostUsageCodexTotals?
    var lastCountedTotals: CostUsageCodexTotals?
    var lastRawTotalsBaseline: CostUsageCodexTotals?
    var hasDivergentTotals: Bool?
    var lastCodexTurnID: String?
    var sessionId: String?
    var forkedFromId: String?
    var projectPath: String?
    var canonicalProjectPath: String?
    var codexCostCacheComplete: Bool?
    var codexCostNanos: [String: [String: Int64]]?
    var codexPrioritySurchargeNanos: [String: [String: Int64]]?
    var codexStandardCostNanos: [String: [String: Int64]]?
    var codexPriorityCostNanos: [String: [String: Int64]]?
    var codexStandardTokens: [String: [String: Int]]?
    var codexPriorityTokens: [String: [String: Int]]?
    var codexTurnIDs: [String]?
    var codexRows: [CostUsageScanner.CodexUsageRow]?
    var claudeRows: [CostUsageScanner.ClaudeUsageRow]?
}

struct CostUsageCodexTotals: Codable {
    var input: Int
    var cached: Int
    var output: Int
}
