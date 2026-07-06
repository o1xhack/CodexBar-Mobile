import Foundation

enum CostUsagePricing {
    private static let codexPriorityInputTokenLimit = 272_000

    struct CodexPricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheReadInputCostPerToken: Double?
        let displayLabel: String?

        let thresholdTokens: Int?
        let inputCostPerTokenAboveThreshold: Double?
        let outputCostPerTokenAboveThreshold: Double?
        let cacheReadInputCostPerTokenAboveThreshold: Double?
        let priorityInputCostPerToken: Double?
        let priorityOutputCostPerToken: Double?
        let priorityCacheReadInputCostPerToken: Double?

        init(
            inputCostPerToken: Double,
            outputCostPerToken: Double,
            cacheReadInputCostPerToken: Double?,
            displayLabel: String?,
            thresholdTokens: Int? = nil,
            inputCostPerTokenAboveThreshold: Double? = nil,
            outputCostPerTokenAboveThreshold: Double? = nil,
            cacheReadInputCostPerTokenAboveThreshold: Double? = nil,
            priorityInputCostPerToken: Double? = nil,
            priorityOutputCostPerToken: Double? = nil,
            priorityCacheReadInputCostPerToken: Double? = nil)
        {
            self.inputCostPerToken = inputCostPerToken
            self.outputCostPerToken = outputCostPerToken
            self.cacheReadInputCostPerToken = cacheReadInputCostPerToken
            self.displayLabel = displayLabel
            self.thresholdTokens = thresholdTokens
            self.inputCostPerTokenAboveThreshold = inputCostPerTokenAboveThreshold
            self.outputCostPerTokenAboveThreshold = outputCostPerTokenAboveThreshold
            self.cacheReadInputCostPerTokenAboveThreshold = cacheReadInputCostPerTokenAboveThreshold
            self.priorityInputCostPerToken = priorityInputCostPerToken
            self.priorityOutputCostPerToken = priorityOutputCostPerToken
            self.priorityCacheReadInputCostPerToken = priorityCacheReadInputCostPerToken
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
            cacheReadInputCostPerTokenAboveThreshold: 5e-7,
            priorityInputCostPerToken: 5e-6,
            priorityOutputCostPerToken: 3e-5,
            priorityCacheReadInputCostPerToken: 5e-7),
        "gpt-5.4-mini": CodexPricing(
            inputCostPerToken: 7.5e-7,
            outputCostPerToken: 4.5e-6,
            cacheReadInputCostPerToken: 7.5e-8,
            displayLabel: nil,
            priorityInputCostPerToken: 1.5e-6,
            priorityOutputCostPerToken: 9e-6,
            priorityCacheReadInputCostPerToken: 1.5e-7),
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
            cacheReadInputCostPerTokenAboveThreshold: 1e-6,
            priorityInputCostPerToken: 1.25e-5,
            priorityOutputCostPerToken: 7.5e-5,
            priorityCacheReadInputCostPerToken: 1.25e-6),
        "gpt-5.5-pro": CodexPricing(
            inputCostPerToken: 3e-5,
            outputCostPerToken: 1.8e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil),
    ]

    static func codexBuiltInPricingFingerprint() -> String {
        var parts = ["priorityInputTokenLimit=\(self.codexPriorityInputTokenLimit)"]
        for model in self.codex.keys.sorted() {
            guard let pricing = self.codex[model] else { continue }
            parts.append([
                "model=\(model)",
                self.optionalPricingFingerprint(pricing.inputCostPerToken),
                self.optionalPricingFingerprint(pricing.outputCostPerToken),
                self.optionalPricingFingerprint(pricing.cacheReadInputCostPerToken),
                pricing.displayLabel ?? "nil",
                pricing.thresholdTokens.map(String.init) ?? "nil",
                self.optionalPricingFingerprint(pricing.inputCostPerTokenAboveThreshold),
                self.optionalPricingFingerprint(pricing.outputCostPerTokenAboveThreshold),
                self.optionalPricingFingerprint(pricing.cacheReadInputCostPerTokenAboveThreshold),
                self.optionalPricingFingerprint(pricing.priorityInputCostPerToken),
                self.optionalPricingFingerprint(pricing.priorityOutputCostPerToken),
                self.optionalPricingFingerprint(pricing.priorityCacheReadInputCostPerToken),
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
    static let parserLogicVersion = 7

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

    static func normalizeCodexModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
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
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> Double?
    {
        let key = self.normalizeCodexModel(model)
        // 1) Live models.dev catalog (upstream 0.25) takes precedence so
        //    fresh pricing edits land without an app update.
        if let lookup = self.modelsDevLookup(
            providerID: self.codexModelsDevProviderID,
            model: model,
            catalog: modelsDevCatalog,
            cacheRoot: modelsDevCacheRoot)
        {
            return self.codexCostUSD(
                pricing: lookup.pricing,
                thresholdTokens: self.codex[key]?.thresholdTokens,
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens)
        }

        // 2) Exact local-table hit.
        if let pricing = self.codex[key] {
            return self.codexCostUSD(
                pricing: pricing,
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens)
        }

        // 3) Fork's family-fallback ladder (Research/018 fix — keeps
        //    unknown gpt-X.Y names from collapsing to $0). Last-resort.
        guard let pricing = self.resolveCodexPricing(model: model) else { return nil }
        return self.codexCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens)
    }

    static func codexPriorityCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        outputTokens: Int) -> Double?
    {
        let key = self.normalizeCodexModel(model)
        guard let pricing = self.codex[key],
              let priorityInputCostPerToken = pricing.priorityInputCostPerToken,
              let priorityOutputCostPerToken = pricing.priorityOutputCostPerToken
        else { return nil }
        if max(0, inputTokens) > self.codexPriorityInputTokenLimit {
            return nil
        }

        let priorityPricing = CodexPricing(
            inputCostPerToken: priorityInputCostPerToken,
            outputCostPerToken: priorityOutputCostPerToken,
            cacheReadInputCostPerToken: pricing.priorityCacheReadInputCostPerToken,
            displayLabel: nil)
        return self.codexCostUSD(
            pricing: priorityPricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens)
    }

    private static func codexCostUSD(
        pricing: CodexPricing,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int) -> Double
    {
        // Codex/OpenAI reports `input_tokens` as the total prompt size, with cached reads as a
        // SUBSET of it. Clamp cached to input and price only the remainder at the input rate so
        // cached tokens are not billed twice (full input rate + cache rate).
        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let nonCached = max(0, inputTokens - cached)
        let cachedRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken

        let usesLongContextRates = pricing.thresholdTokens.map { max(0, inputTokens) > $0 } ?? false
        let inputRate = usesLongContextRates
            ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken
            : pricing.inputCostPerToken
        let cachedInputRate = usesLongContextRates
            ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken ?? inputRate
            : cachedRate
        let outputRate = usesLongContextRates
            ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken
            : pricing.outputCostPerToken

        return (Double(nonCached) * inputRate)
            + (Double(cached) * cachedInputRate)
            + (Double(max(0, outputTokens)) * outputRate)
    }

    private static func codexCostUSD(
        pricing: ModelsDevPricingInfo,
        thresholdTokens: Int? = nil,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int) -> Double
    {
        self.codexCostUSD(
            pricing: CodexPricing(
                inputCostPerToken: pricing.inputCostPerToken,
                outputCostPerToken: pricing.outputCostPerToken,
                cacheReadInputCostPerToken: pricing.cacheReadInputCostPerToken,
                displayLabel: nil,
                thresholdTokens: thresholdTokens ?? pricing.thresholdTokens,
                inputCostPerTokenAboveThreshold: pricing.inputCostPerTokenAboveThreshold,
                outputCostPerTokenAboveThreshold: pricing.outputCostPerTokenAboveThreshold,
                cacheReadInputCostPerTokenAboveThreshold: pricing.cacheReadInputCostPerTokenAboveThreshold),
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens)
    }

    /// Returns true iff the given raw Codex model name maps to an exact
    /// row in the local pricing table (after standard normalization).
    /// SyncCoordinator uses this in P4 to flag `isEstimated` on outbound
    /// per-model breakdowns when the cost came from a fallback row.
    static func isCodexModelKnown(_ raw: String) -> Bool {
        let key = self.normalizeCodexModel(raw)
        return self.codex[key] != nil
    }

    /// Resolve a Codex pricing row, walking the fallback ladder when the
    /// model name isn't in the local table. Returns nil only when the
    /// name doesn't even match the `gpt-X.Y` grammar — for any parseable
    /// Codex name we fall through to `gpt-5` rather than dropping the
    /// row to $0 (the bug Research/018 exists to fix).
    private static func resolveCodexPricing(model: String) -> CodexPricing? {
        let key = self.normalizeCodexModel(model)
        if let exact = self.codex[key] { return exact }
        let resolver = CodexFamilyResolver()
        guard let parsed = resolver.parse(key),
              let fallback = resolver.findFallback(for: parsed, in: self.codex)
        else { return nil }
        // Fire-and-forget diagnostic record. The actor handles dedup +
        // log rate-limiting; we don't wait so the per-row cost loop
        // stays sync.
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

        // 1) models.dev catalog (upstream 0.25).
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

        // 2) Exact local-table hit.
        if let pricing = self.claude[key] {
            return self.claudeCostUSD(pricing: pricing, tokens: tokens)
        }

        // 3) Fork's family-fallback ladder (Research/018).
        guard let pricing = self.resolveClaudePricing(model: model) else { return nil }
        return self.claudeCostUSD(
            pricing: pricing,
            tokens: tokens)
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

    /// Returns true iff the given raw Claude model name maps to an exact
    /// row in the local pricing table (after standard normalization).
    /// Used by SyncCoordinator to mark `isEstimated` on outbound model
    /// breakdowns when cost came from a fallback row.
    static func isClaudeModelKnown(_ raw: String) -> Bool {
        let key = self.normalizeClaudeModel(raw)
        return self.claude[key] != nil
    }

    /// Resolve a Claude pricing row, walking the fallback ladder when the
    /// model name isn't in the local table. Returns nil only when the
    /// name doesn't match the `claude-{family}-…` grammar — for any
    /// parseable Claude name we fall through to family flagship rather
    /// than dropping the row to $0 (the bug Research/018 exists to fix).
    private static func resolveClaudePricing(model: String) -> ClaudePricing? {
        let key = self.normalizeClaudeModel(model)
        if let exact = self.claude[key] { return exact }
        let resolver = ClaudeFamilyResolver()
        guard let parsed = resolver.parse(key),
              let fallback = resolver.findFallback(for: parsed, in: self.claude)
        else { return nil }
        // Fire-and-forget diagnostic record. The actor handles dedup +
        // log rate-limiting; we don't wait so the per-row cost loop
        // stays sync.
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
