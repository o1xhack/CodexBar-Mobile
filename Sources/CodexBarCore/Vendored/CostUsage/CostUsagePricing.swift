// swiftlint:disable type_body_length
// The vendored pricing table is kept as one enum so parser-version and hash
// invalidation continue to cover a single auditable source of truth.
import Foundation

enum CostUsagePricing {
    private static let codexPriorityInputTokenLimit = 272_000
    static let codexUnattributedModel = "unknown"

    struct CodexPricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheReadInputCostPerToken: Double?
        /// Optional cache-write (cache creation) rate. When nil, write tokens are billed at the
        /// uncached input rate (legacy Codex folding behavior).
        let cacheWriteInputCostPerToken: Double?
        let displayLabel: String?

        let thresholdTokens: Int?
        let inputCostPerTokenAboveThreshold: Double?
        let outputCostPerTokenAboveThreshold: Double?
        let cacheReadInputCostPerTokenAboveThreshold: Double?
        let cacheWriteInputCostPerTokenAboveThreshold: Double?

        init(
            inputCostPerToken: Double,
            outputCostPerToken: Double,
            cacheReadInputCostPerToken: Double?,
            displayLabel: String?,
            cacheWriteInputCostPerToken: Double? = nil,
            thresholdTokens: Int? = nil,
            inputCostPerTokenAboveThreshold: Double? = nil,
            outputCostPerTokenAboveThreshold: Double? = nil,
            cacheReadInputCostPerTokenAboveThreshold: Double? = nil,
            cacheWriteInputCostPerTokenAboveThreshold: Double? = nil)
        {
            self.inputCostPerToken = inputCostPerToken
            self.outputCostPerToken = outputCostPerToken
            self.cacheReadInputCostPerToken = cacheReadInputCostPerToken
            self.cacheWriteInputCostPerToken = cacheWriteInputCostPerToken
            self.displayLabel = displayLabel
            self.thresholdTokens = thresholdTokens
            self.inputCostPerTokenAboveThreshold = inputCostPerTokenAboveThreshold
            self.outputCostPerTokenAboveThreshold = outputCostPerTokenAboveThreshold
            self.cacheReadInputCostPerTokenAboveThreshold = cacheReadInputCostPerTokenAboveThreshold
            self.cacheWriteInputCostPerTokenAboveThreshold = cacheWriteInputCostPerTokenAboveThreshold
        }
    }

    struct ClaudePricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheCreationInputCostPerToken: Double
        let cacheReadInputCostPerToken: Double

        let thresholdTokens: Int?
        let inputCostPerTokenAboveThreshold: Double?
        let outputCostPerTokenAboveThreshold: Double?
        let cacheCreationInputCostPerTokenAboveThreshold: Double?
        let cacheReadInputCostPerTokenAboveThreshold: Double?
    }

    private struct ClaudeCostTokens {
        let input: Int
        let cacheRead: Int
        let cacheCreation: Int
        let cacheCreation1h: Int
        let output: Int
    }

    private static let codex: [String: CodexPricing] = [
        "gpt-5": CodexPricing(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil),
        "gpt-5-codex": CodexPricing(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil),
        "gpt-5-mini": CodexPricing(
            inputCostPerToken: 2.5e-7,
            outputCostPerToken: 2e-6,
            cacheReadInputCostPerToken: 2.5e-8,
            displayLabel: nil),
        "gpt-5-nano": CodexPricing(
            inputCostPerToken: 5e-8,
            outputCostPerToken: 4e-7,
            cacheReadInputCostPerToken: 5e-9,
            displayLabel: nil),
        "gpt-5-pro": CodexPricing(
            inputCostPerToken: 1.5e-5,
            outputCostPerToken: 1.2e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil),
        "gpt-5.1": CodexPricing(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil),
        "gpt-5.1-codex": CodexPricing(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil),
        "gpt-5.1-codex-max": CodexPricing(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil),
        "gpt-5.1-codex-mini": CodexPricing(
            inputCostPerToken: 2.5e-7,
            outputCostPerToken: 2e-6,
            cacheReadInputCostPerToken: 2.5e-8,
            displayLabel: nil),
        "gpt-5.2": CodexPricing(
            inputCostPerToken: 1.75e-6,
            outputCostPerToken: 1.4e-5,
            cacheReadInputCostPerToken: 1.75e-7,
            displayLabel: nil),
        "gpt-5.2-codex": CodexPricing(
            inputCostPerToken: 1.75e-6,
            outputCostPerToken: 1.4e-5,
            cacheReadInputCostPerToken: 1.75e-7,
            displayLabel: nil),
        "gpt-5.2-pro": CodexPricing(
            inputCostPerToken: 2.1e-5,
            outputCostPerToken: 1.68e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil),
        "gpt-5.3-codex": CodexPricing(
            inputCostPerToken: 1.75e-6,
            outputCostPerToken: 1.4e-5,
            cacheReadInputCostPerToken: 1.75e-7,
            displayLabel: nil),
        "gpt-5.3-codex-spark": CodexPricing(
            inputCostPerToken: 0,
            outputCostPerToken: 0,
            cacheReadInputCostPerToken: 0,
            displayLabel: "Research Preview"),
        "gpt-5.4": CodexPricing(
            inputCostPerToken: 2.5e-6,
            outputCostPerToken: 1.5e-5,
            cacheReadInputCostPerToken: 2.5e-7,
            displayLabel: nil,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 5e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheReadInputCostPerTokenAboveThreshold: 5e-7),
        "gpt-5.4-mini": CodexPricing(
            inputCostPerToken: 7.5e-7,
            outputCostPerToken: 4.5e-6,
            cacheReadInputCostPerToken: 7.5e-8,
            displayLabel: nil),
        "gpt-5.4-nano": CodexPricing(
            inputCostPerToken: 2e-7,
            outputCostPerToken: 1.25e-6,
            cacheReadInputCostPerToken: 2e-8,
            displayLabel: nil),
        "gpt-5.4-pro": CodexPricing(
            inputCostPerToken: 3e-5,
            outputCostPerToken: 1.8e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil),
        "gpt-5.5": CodexPricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 3e-5,
            cacheReadInputCostPerToken: 5e-7,
            displayLabel: nil,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 1e-5,
            outputCostPerTokenAboveThreshold: 4.5e-5,
            cacheReadInputCostPerTokenAboveThreshold: 1e-6),
        "gpt-5.5-pro": CodexPricing(
            inputCostPerToken: 3e-5,
            outputCostPerToken: 1.8e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil),
        // GPT-5.6 Sol/Terra/Luna (OpenAI pricing page + model cards).
        // Long context: prompts with >272K input tokens are 2x input / 1.5x output for the full
        // request. Cache writes: 1.25x uncached input. API Fast support and multipliers are applied
        // separately after Standard pricing resolves from models.dev or this bundled fallback.
        "gpt-5.6-sol": CodexPricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 3e-5,
            cacheReadInputCostPerToken: 5e-7,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 6.25e-6,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 1e-5,
            outputCostPerTokenAboveThreshold: 4.5e-5,
            cacheReadInputCostPerTokenAboveThreshold: 1e-6,
            cacheWriteInputCostPerTokenAboveThreshold: 1.25e-5),
        "gpt-5.6-terra": CodexPricing(
            inputCostPerToken: 2e-6,
            outputCostPerToken: 1.2e-5,
            cacheReadInputCostPerToken: 2e-7,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 2.5e-6,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 4e-6,
            outputCostPerTokenAboveThreshold: 1.8e-5,
            cacheReadInputCostPerTokenAboveThreshold: 4e-7,
            cacheWriteInputCostPerTokenAboveThreshold: 5e-6),
        "gpt-5.6-luna": CodexPricing(
            inputCostPerToken: 2e-7,
            outputCostPerToken: 1.2e-6,
            cacheReadInputCostPerToken: 2e-8,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 2.5e-7,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 4e-7,
            outputCostPerTokenAboveThreshold: 1.8e-6,
            cacheReadInputCostPerTokenAboveThreshold: 4e-8,
            cacheWriteInputCostPerTokenAboveThreshold: 5e-7),
    ]

    static func codexBuiltInPricingFingerprint() -> String {
        var parts = [
            "priorityInputTokenLimit=\(self.codexPriorityInputTokenLimit)",
            "fastPricingDefinition=api-fast-usd-v1",
        ]
        for model in self.codex.keys.sorted() {
            guard let pricing = self.codex[model] else { continue }
            parts.append([
                "model=\(model)",
                self.optionalPricingFingerprint(pricing.inputCostPerToken),
                self.optionalPricingFingerprint(pricing.outputCostPerToken),
                self.optionalPricingFingerprint(pricing.cacheReadInputCostPerToken),
                self.optionalPricingFingerprint(pricing.cacheWriteInputCostPerToken),
                pricing.displayLabel ?? "nil",
                pricing.thresholdTokens.map(String.init) ?? "nil",
                self.optionalPricingFingerprint(pricing.inputCostPerTokenAboveThreshold),
                self.optionalPricingFingerprint(pricing.outputCostPerTokenAboveThreshold),
                self.optionalPricingFingerprint(pricing.cacheReadInputCostPerTokenAboveThreshold),
                self.optionalPricingFingerprint(pricing.cacheWriteInputCostPerTokenAboveThreshold),
                self.optionalPricingFingerprint(self.codexAPIFastMultiplier(model: model)),
            ].joined(separator: "|"))
        }
        return parts.joined(separator: "\n")
    }

    private static func optionalPricingFingerprint(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.17g", value)
    }

    private static let claude: [String: ClaudePricing] = [
        "claude-fable-5": ClaudePricing(
            inputCostPerToken: 1e-5,
            outputCostPerToken: 5e-5,
            cacheCreationInputCostPerToken: 1.25e-5,
            cacheReadInputCostPerToken: 1e-6,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-haiku-4-5-20251001": ClaudePricing(
            inputCostPerToken: 1e-6,
            outputCostPerToken: 5e-6,
            cacheCreationInputCostPerToken: 1.25e-6,
            cacheReadInputCostPerToken: 1e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-haiku-4-5": ClaudePricing(
            inputCostPerToken: 1e-6,
            outputCostPerToken: 5e-6,
            cacheCreationInputCostPerToken: 1.25e-6,
            cacheReadInputCostPerToken: 1e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-5-20251101": ClaudePricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-5": ClaudePricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-6-20260205": ClaudePricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-6": ClaudePricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-7": ClaudePricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-8": ClaudePricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-sonnet-4-5": ClaudePricing(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 6e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheCreationInputCostPerTokenAboveThreshold: 7.5e-6,
            cacheReadInputCostPerTokenAboveThreshold: 6e-7),
        "claude-sonnet-4-6": ClaudePricing(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-sonnet-4-5-20250929": ClaudePricing(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 6e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheCreationInputCostPerTokenAboveThreshold: 7.5e-6,
            cacheReadInputCostPerTokenAboveThreshold: 6e-7),
        "claude-opus-4-20250514": ClaudePricing(
            inputCostPerToken: 1.5e-5,
            outputCostPerToken: 7.5e-5,
            cacheCreationInputCostPerToken: 1.875e-5,
            cacheReadInputCostPerToken: 1.5e-6,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-1": ClaudePricing(
            inputCostPerToken: 1.5e-5,
            outputCostPerToken: 7.5e-5,
            cacheCreationInputCostPerToken: 1.875e-5,
            cacheReadInputCostPerToken: 1.5e-6,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-sonnet-4-20250514": ClaudePricing(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 6e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheCreationInputCostPerTokenAboveThreshold: 7.5e-6,
            cacheReadInputCostPerTokenAboveThreshold: 6e-7),
    ]

    private static let claudeFullContextStandardPricingCutoff = Date(timeIntervalSince1970: 1_773_360_000)
    private static let claudeHistoricalLongContext: [String: ClaudePricing] = [
        "claude-opus-4-6": ClaudePricing(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 1e-5,
            outputCostPerTokenAboveThreshold: 3.75e-5,
            cacheCreationInputCostPerTokenAboveThreshold: 1.25e-5,
            cacheReadInputCostPerTokenAboveThreshold: 1e-6),
        "claude-sonnet-4-6": ClaudePricing(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 6e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheCreationInputCostPerTokenAboveThreshold: 7.5e-6,
            cacheReadInputCostPerTokenAboveThreshold: 6e-7),
    ]

    private static let codexModelsDevProviderID = "openai"
    /// Provider IDs emitted by Codex-compatible clients that have matching entries in models.dev.
    ///
    /// The route prefix is part of the model identity for local usage estimates. Keep both the
    /// client-facing aliases and their models.dev provider IDs here so pricing-cache fingerprints
    /// invalidate when any supported route's rates change.
    static let codexModelsDevProviderIDs: Set<String> = [
        "deepseek",
        "kimi-coding",
        "kimi-for-coding",
        "openai",
        "opencode",
        "opencode-free",
        "opencode-go",
    ]
    private static let claudeModelsDevProviderID = "anthropic"

    /// Manual version constant for the parser logic (`parseCodexFile` /
    /// `parseClaudeFile` / `normalizeXxxModel`). Bump this when the parser
    /// semantics change (e.g., model normalization rules, fallback ladder,
    /// delta handling, line-size caps) — `pricingFingerprint` rolls
    /// automatically on pricing-table edits, but parser-only changes
    /// need this nudge so caches written by the old parser version are
    /// invalidated.
    ///
    /// `Scripts/lint.sh audit-parser-version` enforces a bump whenever
    /// `CostUsageScanner.swift`, `CostUsageScanner+Claude.swift`, or
    /// `CostUsageJsonl.swift` change vs origin/mobile-dev.
    ///
    /// History:
    /// - `12` (0.52.0.1): merged upstream v0.49.3-v0.52.0 parser, project/session
    ///   attribution, provider-qualified pricing, retention, and reconciliation changes.
    /// - `11` (0.49.2.1): merged upstream v0.48.0-v0.49.2 scanner and
    ///   pricing changes, including SQLite working-set migration, API Fast
    ///   token-class attribution, and Claude/Codex parser updates.
    /// - `10` (0.47.0.1): merged upstream v0.46.0-v0.47.0 scanner and
    ///   cache changes, including locally confirmed compact-subagent
    ///   boundaries and the corresponding persisted artifact revisions.
    /// - `9` (0.45.2.1): merged upstream v0.42.0-v0.45.2 scanner and
    ///   cache changes, including incomplete JSONL tail retention, OMP/Pi
    ///   attribution, copied-prefix and Ultra-lineage containment, explicit
    ///   unattributed-model handling, and pricing-key cache invalidation.
    /// - `7` (0.39.0.1): merged upstream v0.38.0+v0.39.0 Codex scanner
    ///   project-metadata attribution and cost formula changes. Roll the
    ///   pricing fingerprint so existing caches re-scan with the latest
    ///   session/project identity behavior.
    /// - `6` (0.36.1.1): merged upstream v0.36.0+v0.36.1 cost scanner
    ///   changes. Roll the pricing fingerprint so on-disk usage caches
    ///   re-scan with the latest parser behavior.
    /// - `5` (0.32.4.1): merged upstream v0.32.0→v0.32.4 Codex cost-scanner
    ///   rewrite (new `CostUsageScanner+CodexFastJSON.swift`, reworked truncated-prefix
    ///   handling, scan-perf changes). The regenerated parser hash rolls the Codex
    ///   producerKey axis; this parserLogicVersion bump rolls the pricingFingerprint so
    ///   the Claude axis (no producerKey) also invalidates caches written by the v0.31
    ///   parser and re-scans with the merged scanner.
    /// - `4` (0.31.0.2): merged upstream v0.29.1→v0.31.0 cost-scanner
    ///   changes — Codex `CostUsageScanner` rewrite (Spark model lane #1195,
    ///   reworked token attribution) and `CostUsageScanner+Claude` now threads
    ///   the models.dev catalog into Claude cost pricing. Upstream rolled its
    ///   producerKey hash for the Codex axis (so Codex caches invalidate on
    ///   the hash value change), but the fork's pricingFingerprint — the only
    ///   invalidation axis for Claude, which has no producerKey — did not move.
    ///   This bump rolls the fingerprint so Claude caches written by the v0.29
    ///   parser are invalidated and re-scanned with the merged parser.
    /// - `8` (0.41.0.1): upstream v0.40.0-v0.41.0 makes the persisted
    ///   Codex cost cache completeness explicit, migrates incomplete cost
    ///   maps before report generation, and expands Claude Desktop project
    ///   discovery. These changes affect attribution and cached report output.
    /// - `3` (0.29.0): merged upstream v0.28.0+v0.29.0 Codex cost-scanner
    ///   changes — standard vs fast spend/token splits in model breakdowns
    ///   (#1070) and no-recount of repeated local token snapshots when total
    ///   usage is unchanged (#1062). These change Codex token attribution, so
    ///   roll the fingerprint to invalidate caches written by the v0.27
    ///   scanner and re-scan with the merged parser.
    /// - `2` (0.23.3): parser scanner `prefixBytes` raised from 32 KB to
    ///   256 KB. Earlier 32 KB cap silently truncated every Codex CLI
    ///   0.125+ `turn_context` (~38–41 KB due to bundled AGENTS.md /
    ///   user_instructions), so `currentModel` never updated and ~93%+
    ///   of token_count events fell through to the `?? "gpt-5"` default
    ///   in `parseCodexFile`. Bumping rolls every previous version's
    ///   cache and re-scans with the fixed parser.
    /// - `1` (0.23.1): initial fingerprint contract.
    static let parserLogicVersion = 12

    /// Stable string fingerprint of the pricing tables + parser logic.
    /// `CostUsageCacheIO.load` compares this against the value stored
    /// inside the cache file; on mismatch it returns an empty cache and
    /// forces a full re-scan.
    ///
    /// **Why this exists:** Mac 0.20.3 → 0.23 added `gpt-5.5` to the
    /// pricing table, but `codex-v4.json` cache from 0.20.3 era kept
    /// stale per-(day, model) token attributions — tokens stored under
    /// `gpt-5` (the old fallback default) silently survived the upgrade
    /// and showed up at gpt-5 prices instead of gpt-5.5 prices. Bumping
    /// the artifact version manually closes this round; the fingerprint
    /// closes it for **every future round** without humans needing to
    /// remember.
    static var pricingFingerprint: String {
        /// Sorted (key, encoded-prices) pairs are deterministic across
        /// runs and machines. Identical pricing tables always yield the
        /// same fingerprint; ANY edit — adding a model, removing one,
        /// OR repricing an existing model — rolls the string and
        /// invalidates every user's cache on next launch.
        ///
        /// 0.23.3 P1-2 fix: previously the fingerprint included only
        /// model NAMES, so a same-name reprice (e.g., dropping gpt-5
        /// input from $1.25/M to $1.0/M) didn't roll. That left stale
        /// baked-in `costNanos` in PiSessionCostCache (which stores
        /// costs at parse time, not on read) for repricing-only updates.
        ///
        /// Each Double is rendered with %.12g so 1.25e-6 stringifies
        /// identically across runs — Swift's default String(Double)
        /// format is already deterministic, but pinning explicit
        /// formatting makes it robust to future libc / locale changes.
        func d(_ value: Double) -> String {
            String(format: "%.12g", value)
        }
        func dOpt(_ value: Double?) -> String {
            value.map(d) ?? "_"
        }
        func iOpt(_ value: Int?) -> String {
            value.map(String.init) ?? "_"
        }

        let codexEntries = self.codex.keys.sorted().map { key in
            let p = self.codex[key]!
            return "\(key):\(d(p.inputCostPerToken)):\(d(p.outputCostPerToken)):\(dOpt(p.cacheReadInputCostPerToken))"
        }.joined(separator: ",")

        let claudeEntries = self.claude.keys.sorted().map { key in
            let p = self.claude[key]!
            return [
                key,
                d(p.inputCostPerToken),
                d(p.outputCostPerToken),
                d(p.cacheCreationInputCostPerToken),
                d(p.cacheReadInputCostPerToken),
                iOpt(p.thresholdTokens),
                dOpt(p.inputCostPerTokenAboveThreshold),
                dOpt(p.outputCostPerTokenAboveThreshold),
                dOpt(p.cacheCreationInputCostPerTokenAboveThreshold),
                dOpt(p.cacheReadInputCostPerTokenAboveThreshold),
            ].joined(separator: ":")
        }.joined(separator: ",")

        return "v\(Self.parserLogicVersion)|codex=\(codexEntries)|claude=\(claudeEntries)"
    }

    /// Returns the provider/model identities that may price a Codex model. Keep this mapping
    /// shared by direct lookup and unknown-price refresh so a newly downloaded catalog is checked
    /// under the same identity that was used to resolve the model.
    static func codexModelsDevPricingTargets(for rawModel: String) -> [(providerID: String, modelID: String)] {
        let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let slash = trimmed.firstIndex(of: "/") {
            let routeID = String(trimmed[..<slash]).lowercased()
            let modelID = String(trimmed[trimmed.index(after: slash)...])
            guard !routeID.isEmpty, !modelID.isEmpty,
                  self.codexModelsDevProviderIDs.contains(routeID)
            else { return [] }

            var providerIDs = [routeID]
            switch routeID {
            case "kimi-coding":
                providerIDs.append("kimi-for-coding")
            case "opencode-free":
                providerIDs.append("opencode")
            default:
                break
            }
            var targets = providerIDs.map { ($0, modelID) }
            if routeID == self.codexModelsDevProviderID {
                let normalized = self.normalizeCodexModel(modelID)
                if normalized != modelID {
                    targets.append((self.codexModelsDevProviderID, normalized))
                }
            }
            return targets
        }

        let normalized = self.normalizeCodexModel(trimmed)
        var targets = [(self.codexModelsDevProviderID, trimmed)]
        if normalized != trimmed {
            targets.append((self.codexModelsDevProviderID, normalized))
        }
        return targets
    }

    static func normalizeCodexModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }

        // OpenAI routes the unsuffixed gpt-5.6 alias to Sol.
        if trimmed == "gpt-5.6" {
            return "gpt-5.6-sol"
        }

        if self.codex[trimmed] != nil {
            return trimmed
        }

        if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<datedSuffix.lowerBound])
            if self.codex[base] != nil {
                return base
            }
        }
        return trimmed
    }

    static func isCodexUnattributedModel(_ raw: String) -> Bool {
        self.normalizeCodexModel(raw) == self.codexUnattributedModel
    }

    static func codexDisplayLabel(model: String) -> String? {
        let key = self.normalizeCodexModel(model)
        return self.codex[key]?.displayLabel
    }

    static func normalizeClaudeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("anthropic.") {
            trimmed = String(trimmed.dropFirst("anthropic.".count))
        }

        if let lastDot = trimmed.lastIndex(of: "."),
           trimmed.contains("claude-")
        {
            let tail = String(trimmed[trimmed.index(after: lastDot)...])
            if tail.hasPrefix("claude-") {
                trimmed = tail
            }
        }

        if let vRange = trimmed.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
            trimmed.removeSubrange(vRange)
        }

        if let baseRange = trimmed.range(of: #"-\d{8}$"#, options: .regularExpression) {
            let base = String(trimmed[..<baseRange.lowerBound])
            if self.claude[base] != nil {
                return base
            }
        }

        return trimmed
    }

    static func codexCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        cacheWriteInputTokens: Int = 0,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> Double?
    {
        guard let pricing = self.resolvedCodexPricing(
            model: model,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot)
        else { return nil }
        return self.codexCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            outputTokens: outputTokens)
    }

    static func codexAggregateCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        cacheWriteInputTokens: Int = 0,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> Double?
    {
        guard let pricing = self.resolvedCodexPricing(
            model: model,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot)
        else { return nil }
        if let thresholdTokens = pricing.thresholdTokens,
           max(0, inputTokens) > thresholdTokens
        {
            return nil
        }
        return self.codexCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            outputTokens: outputTokens)
    }

    private static func resolvedCodexPricing(
        model: String,
        modelsDevCatalog: ModelsDevCatalog?,
        modelsDevCacheRoot: URL?) -> CodexPricing?
    {
        let key = self.normalizeCodexModel(model)
        guard key != self.codexUnattributedModel else { return nil }
        let modelsDevLookup = self.codexModelsDevLookup(
            model: model,
            catalog: modelsDevCatalog,
            cacheRoot: modelsDevCacheRoot)
        if let lookup = modelsDevLookup {
            let bundled = lookup.pricing.providerID == self.codexModelsDevProviderID ? self.codex[key] : nil
            // A missing catalog context block means models.dev has no long-context opinion, so use
            // the bundled tuple. Once the block exists, preserve its omissions and normal fallback
            // semantics instead of filling individual fields from a different pricing source.
            let bundledLongContext = lookup.pricing.thresholdTokens == nil ? bundled : nil
            let cacheReadAboveThreshold = lookup.pricing.cacheReadInputCostPerTokenAboveThreshold
                ?? (lookup.pricing.thresholdTokens != nil
                    ? lookup.pricing.cacheReadInputCostPerToken
                    ?? lookup.pricing.inputCostPerTokenAboveThreshold
                    ?? lookup.pricing.inputCostPerToken
                    : bundledLongContext?.cacheReadInputCostPerTokenAboveThreshold)
            let cacheWriteAboveThreshold = lookup.pricing.cacheCreationInputCostPerTokenAboveThreshold
                ?? (lookup.pricing.thresholdTokens != nil
                    ? lookup.pricing.cacheCreationInputCostPerToken
                    ?? lookup.pricing.inputCostPerTokenAboveThreshold
                    ?? lookup.pricing.inputCostPerToken
                    : bundledLongContext?.cacheWriteInputCostPerTokenAboveThreshold)
            return CodexPricing(
                inputCostPerToken: lookup.pricing.inputCostPerToken,
                outputCostPerToken: lookup.pricing.outputCostPerToken,
                cacheReadInputCostPerToken: lookup.pricing.cacheReadInputCostPerToken
                    ?? bundled?.cacheReadInputCostPerToken,
                displayLabel: nil,
                cacheWriteInputCostPerToken: lookup.pricing.cacheCreationInputCostPerToken
                    ?? bundled?.cacheWriteInputCostPerToken,
                thresholdTokens: bundled?.thresholdTokens ?? lookup.pricing.thresholdTokens,
                inputCostPerTokenAboveThreshold: lookup.pricing.inputCostPerTokenAboveThreshold
                    ?? bundledLongContext?.inputCostPerTokenAboveThreshold,
                outputCostPerTokenAboveThreshold: lookup.pricing.outputCostPerTokenAboveThreshold
                    ?? bundledLongContext?.outputCostPerTokenAboveThreshold,
                cacheReadInputCostPerTokenAboveThreshold: cacheReadAboveThreshold,
                cacheWriteInputCostPerTokenAboveThreshold: cacheWriteAboveThreshold)
        }

        if let pricing = self.codex[key] {
            return pricing
        }

        // Preserve the fork's family fallback for unqualified OpenAI models while keeping
        // upstream's provider-qualified pricing isolation. A routed DeepSeek/Kimi/OpenCode
        // model must never fall through to an OpenAI family rate.
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = trimmed.firstIndex(of: "/") {
            let routeID = String(trimmed[..<slash]).lowercased()
            guard routeID == self.codexModelsDevProviderID else { return nil }
        }
        return self.resolveCodexPricing(model: model)
    }

    /// Resolves the provider-qualified model IDs written by Codex-compatible clients without
    /// falling back to OpenAI pricing for an unrelated route. Unqualified model IDs retain the
    /// historical OpenAI behavior, including the gpt-5.6 alias lookup.
    private static func codexModelsDevLookup(
        model rawModel: String,
        catalog: ModelsDevCatalog?,
        cacheRoot: URL?) -> ModelsDevPricingLookup?
    {
        for target in self.codexModelsDevPricingTargets(for: rawModel) {
            if let lookup = self.modelsDevLookup(
                providerID: target.providerID,
                model: target.modelID,
                catalog: catalog,
                cacheRoot: cacheRoot)
            {
                return lookup
            }
        }
        return nil
    }

    static func codexPriorityCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> Double?
    {
        guard let multiplier = self.codexAPIFastMultiplier(model: model) else { return nil }
        // OpenAI does not support API Fast processing for long-context requests. Do not combine
        // the independent Standard long-context and Fast short-context rate tables.
        if max(0, inputTokens) > self.codexPriorityInputTokenLimit {
            return nil
        }

        return self.codexCostUSD(
            model: model,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot)
            .map { $0 * multiplier }
    }

    /// Current public API Fast rates normalized against Standard API pricing. These are deliberately
    /// distinct from ChatGPT/Codex Fast credit multipliers, which do not represent a USD charge.
    static func codexAPIFastMultiplier(model: String) -> Double? {
        switch self.normalizeCodexModel(model) {
        case "gpt-5.4", "gpt-5.4-mini", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna": 2
        case "gpt-5.5": 2.5
        default: nil
        }
    }

    private static func codexCostUSD(
        pricing: CodexPricing,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int) -> Double
    {
        // Codex/OpenAI reports `input_tokens` as the total prompt size, with cached reads as a
        // SUBSET of it. Cache writes (when tracked separately, e.g. Pi) are also a subset of the
        // non-cached remainder. Clamp so tokens are never invented or double-billed.
        let totalInput = max(0, inputTokens)
        let cached = min(max(0, cachedInputTokens), totalInput)
        let remainingAfterCache = totalInput - cached
        let cacheWrite = min(max(0, cacheWriteInputTokens), remainingAfterCache)
        let nonCached = remainingAfterCache - cacheWrite
        let cachedRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken

        let usesLongContextRates = pricing.thresholdTokens.map { totalInput > $0 } ?? false
        let inputRate = usesLongContextRates
            ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken
            : pricing.inputCostPerToken
        let cachedInputRate = usesLongContextRates
            ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken ?? inputRate
            : cachedRate
        let cacheWriteRate = usesLongContextRates
            ? pricing.cacheWriteInputCostPerTokenAboveThreshold
            ?? pricing.cacheWriteInputCostPerToken
            ?? inputRate
            : pricing.cacheWriteInputCostPerToken ?? inputRate
        let outputRate = usesLongContextRates
            ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken
            : pricing.outputCostPerToken

        return (Double(nonCached) * inputRate)
            + (Double(cached) * cachedInputRate)
            + (Double(cacheWrite) * cacheWriteRate)
            + (Double(max(0, outputTokens)) * outputRate)
    }

    static func isCodexModelKnown(_ raw: String) -> Bool {
        let key = self.normalizeCodexModel(raw)
        return self.codex[key] != nil
    }

    /// Returns true when the model resolves to a concrete pricing row in this immutable pricing
    /// snapshot without using the family-fallback ladder. Provider-qualified Codex-compatible
    /// routes are exact only when their own models.dev provider contains the model.
    static func hasExactCodexPricing(
        _ raw: String,
        modelsDevCatalog: ModelsDevCatalog?) -> Bool
    {
        let key = self.normalizeCodexModel(raw)
        guard key != self.codexUnattributedModel else { return false }
        let immutableCatalog = modelsDevCatalog ?? ModelsDevCatalog(providers: [:])
        if self.codexModelsDevLookup(
            model: raw,
            catalog: immutableCatalog,
            cacheRoot: nil) != nil
        {
            return true
        }
        return self.codex[key] != nil
    }

    private static func resolveCodexPricing(model: String) -> CodexPricing? {
        let key = self.normalizeCodexModel(model)
        if let exact = self.codex[key] { return exact }
        let resolver = CodexFamilyResolver()
        guard let parsed = resolver.parse(key),
              let fallback = resolver.findFallback(for: parsed, in: self.codex)
        else { return nil }
        let strategy = fallback.strategy.rawValue
        let fallbackKey = fallback.key
        Task { @Sendable in
            await UnknownModelDiagnostics.shared.record(
                providerKey: "codex",
                rawModel: key,
                fallbackKey: fallbackKey,
                strategyName: strategy)
        }
        return fallback.pricing
    }

    static func claudeCostUSD(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheCreationInputTokens1h: Int = 0,
        outputTokens: Int,
        pricingDate: Date? = nil,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> Double?
    {
        let tokens = ClaudeCostTokens(
            input: inputTokens,
            cacheRead: cacheReadInputTokens,
            cacheCreation: cacheCreationInputTokens,
            cacheCreation1h: cacheCreationInputTokens1h,
            output: outputTokens)
        let key = self.normalizeClaudeModel(model)
        if let pricingDate,
           let historicalPricing = self.claudeHistoricalLongContext[key],
           let currentPricing = self.claude[key]
        {
            return self.claudeCostUSD(
                pricing: pricingDate < self.claudeFullContextStandardPricingCutoff
                    ? historicalPricing
                    : currentPricing,
                tokens: tokens)
        }
        if let lookup = self.modelsDevLookup(
            providerID: self.claudeModelsDevProviderID,
            model: model,
            catalog: modelsDevCatalog,
            cacheRoot: modelsDevCacheRoot)
        {
            return self.claudeCostUSD(
                pricing: lookup.pricing,
                tokens: tokens)
        }

        if let pricing = self.claude[key] {
            return self.claudeCostUSD(pricing: pricing, tokens: tokens)
        }

        guard let pricing = self.resolveClaudePricing(model: model) else { return nil }
        return self.claudeCostUSD(pricing: pricing, tokens: tokens)
    }

    private static func claudeCostUSD(
        pricing: ClaudePricing,
        tokens: ClaudeCostTokens) -> Double
    {
        let input = max(0, tokens.input)
        let cacheRead = max(0, tokens.cacheRead)
        let cacheCreationTotal = max(0, tokens.cacheCreation)
        let cacheCreation1h = min(max(0, tokens.cacheCreation1h), cacheCreationTotal)
        let cacheCreation5m = cacheCreationTotal - cacheCreation1h
        let usesLongContextRates = pricing.thresholdTokens.map {
            input + cacheRead + cacheCreationTotal > $0
        } ?? false
        let inputRate = usesLongContextRates
            ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken
            : pricing.inputCostPerToken
        let cacheReadRate = usesLongContextRates
            ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken
            : pricing.cacheReadInputCostPerToken
        let cacheCreation5mRate = usesLongContextRates
            ? pricing.cacheCreationInputCostPerTokenAboveThreshold ?? pricing.cacheCreationInputCostPerToken
            : pricing.cacheCreationInputCostPerToken
        let outputRate = usesLongContextRates
            ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken
            : pricing.outputCostPerToken

        return Double(input) * inputRate
            + Double(cacheRead) * cacheReadRate
            + Double(cacheCreation5m) * cacheCreation5mRate
            + Double(cacheCreation1h) * inputRate * 2
            + Double(max(0, tokens.output)) * outputRate
    }

    private static func claudeCostUSD(
        pricing: ModelsDevPricingInfo,
        tokens: ClaudeCostTokens) -> Double
    {
        self.claudeCostUSD(
            pricing: ClaudePricing(
                inputCostPerToken: pricing.inputCostPerToken,
                outputCostPerToken: pricing.outputCostPerToken,
                cacheCreationInputCostPerToken: pricing.cacheCreationInputCostPerToken ?? pricing.inputCostPerToken,
                cacheReadInputCostPerToken: pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken,
                thresholdTokens: pricing.thresholdTokens,
                inputCostPerTokenAboveThreshold: pricing.inputCostPerTokenAboveThreshold,
                outputCostPerTokenAboveThreshold: pricing.outputCostPerTokenAboveThreshold,
                cacheCreationInputCostPerTokenAboveThreshold: pricing.cacheCreationInputCostPerTokenAboveThreshold,
                cacheReadInputCostPerTokenAboveThreshold: pricing.cacheReadInputCostPerTokenAboveThreshold),
            tokens: tokens)
    }

    static func isClaudeModelKnown(_ raw: String) -> Bool {
        let key = self.normalizeClaudeModel(raw)
        return self.claude[key] != nil
    }

    /// Returns true when Claude pricing resolves exactly in the same immutable catalog used to
    /// compute the amount. Family fallbacks remain estimates even if a newer cache later appears.
    static func hasExactClaudePricing(
        _ raw: String,
        modelsDevCatalog: ModelsDevCatalog?) -> Bool
    {
        let key = self.normalizeClaudeModel(raw)
        let immutableCatalog = modelsDevCatalog ?? ModelsDevCatalog(providers: [:])
        if self.modelsDevLookup(
            providerID: self.claudeModelsDevProviderID,
            model: raw,
            catalog: immutableCatalog,
            cacheRoot: nil) != nil
        {
            return true
        }
        return self.claude[key] != nil
    }

    private static func resolveClaudePricing(model: String) -> ClaudePricing? {
        let key = self.normalizeClaudeModel(model)
        if let exact = self.claude[key] { return exact }
        let resolver = ClaudeFamilyResolver()
        guard let parsed = resolver.parse(key),
              let fallback = resolver.findFallback(for: parsed, in: self.claude)
        else { return nil }
        let strategy = fallback.strategy.rawValue
        let fallbackKey = fallback.key
        Task { @Sendable in
            await UnknownModelDiagnostics.shared.record(
                providerKey: "claude",
                rawModel: key,
                fallbackKey: fallbackKey,
                strategyName: strategy)
        }
        return fallback.pricing
    }

    static func modelsDevCatalog(now: Date = Date(), cacheRoot: URL? = nil) -> ModelsDevCatalog? {
        ModelsDevCache.load(now: now, cacheRoot: cacheRoot).artifact?.catalog
    }

    private static func modelsDevLookup(
        providerID: String,
        model: String,
        catalog: ModelsDevCatalog?,
        cacheRoot: URL?) -> ModelsDevPricingLookup?
    {
        if let catalog {
            return catalog.pricing(providerID: providerID, modelID: model)
        }

        return ModelsDevPricingPipeline.lookup(
            providerID: providerID,
            modelID: model,
            cacheRoot: cacheRoot)
    }
}

// swiftlint:enable type_body_length
