import Foundation
import Testing
@testable import CodexBarCore

/// Pins the Codex (gpt-5*) resolver against the live `CostUsagePricing.codex`
/// table. Variants are heterogeneous (mini / pro / nano / codex / codex-max
/// / codex-mini / codex-spark), so the parser must keep them as separate
/// families — `mini` and `codex-mini` are NOT interchangeable for pricing.
@Suite("CodexFamilyResolver")
struct CodexFamilyResolverTests {
    private static let resolver = CodexFamilyResolver()

    // MARK: - Parser

    @Test
    func `Parses gpt-5 (no minor, no variant)`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5"))
        #expect(parsed.majorVersion == 5)
        #expect(parsed.minorVersion == nil)
        #expect(parsed.family.isEmpty)
    }

    @Test
    func `Parses gpt-5.4 (no variant)`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5.4"))
        #expect(parsed.majorVersion == 5)
        #expect(parsed.minorVersion == 4)
        #expect(parsed.family.isEmpty)
    }

    @Test
    func `Parses gpt-5.4-mini with family=mini`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5.4-mini"))
        #expect(parsed.minorVersion == 4)
        #expect(parsed.family == "mini")
    }

    @Test
    func `Parses gpt-5.1-codex-max with family=codex-max (multi-token variant)`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5.1-codex-max"))
        #expect(parsed.minorVersion == 1)
        #expect(parsed.family == "codex-max")
    }

    @Test
    func `Parses gpt-5.3-codex-spark (research-preview zero-priced variant)`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5.3-codex-spark"))
        #expect(parsed.minorVersion == 3)
        #expect(parsed.family == "codex-spark")
    }

    @Test
    func `Distinguishes mini and codex-mini as separate families`() throws {
        let mini = try #require(Self.resolver.parse("gpt-5.4-mini"))
        let codexMini = try #require(Self.resolver.parse("gpt-5.1-codex-mini"))
        #expect(mini.family == "mini")
        #expect(codexMini.family == "codex-mini")
        #expect(mini.family != codexMini.family)
    }

    @Test
    func `Rejects non-gpt prefixes`() {
        #expect(Self.resolver.parse("claude-opus-4-7") == nil)
        #expect(Self.resolver.parse("opus-4-7") == nil)
        #expect(Self.resolver.parse("") == nil)
        #expect(Self.resolver.parse("gpt-") == nil)
    }

    @Test
    func `Rejects unparseable major`() {
        #expect(Self.resolver.parse("gpt-foo") == nil)
        #expect(Self.resolver.parse("gpt-foo.5") == nil)
    }

    @Test
    func `Rejects unparseable minor`() {
        #expect(Self.resolver.parse("gpt-5.foo") == nil)
        #expect(Self.resolver.parse("gpt-5.5.5") == nil)
    }

    // MARK: - Fallback against the live table

    @Test
    func `Unknown gpt-5.6 (base) falls back to gpt-5.5 (Step 1)`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5.6"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: CodexFamilyResolverTests.liveCodexTable())
        #expect(fallback?.key == "gpt-5.5")
        #expect(fallback?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Unknown gpt-5.5-codex-spark walks back to gpt-5.3-codex-spark`() throws {
        // Spark is intentionally zero-priced upstream. Falling back from a
        // future 5.5-spark to the 5.3-spark row preserves the
        // "research-preview = free" behavior — strictly safer than $0
        // and avoids over-billing experimental traffic.
        let parsed = try #require(Self.resolver.parse("gpt-5.5-codex-spark"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: CodexFamilyResolverTests.liveCodexTable())
        #expect(fallback?.key == "gpt-5.3-codex-spark")
        #expect(fallback?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Unknown gpt-5.5-codex-mini falls back to gpt-5.1-codex-mini`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5.5-codex-mini"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: CodexFamilyResolverTests.liveCodexTable())
        #expect(fallback?.key == "gpt-5.1-codex-mini")
        #expect(fallback?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Unknown family gpt-5.5-turbo falls through to provider default gpt-5`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-5.5-turbo"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: CodexFamilyResolverTests.liveCodexTable())
        #expect(fallback?.key == "gpt-5")
        #expect(fallback?.strategy == .providerDefault)
    }

    @Test
    func `Unknown major gpt-6.0 falls back to highest GPT-5 of same family`() throws {
        let parsed = try #require(Self.resolver.parse("gpt-6.0"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: CodexFamilyResolverTests.liveCodexTable())
        // family="" → same family entries: gpt-5, gpt-5.1, gpt-5.2, 5.4, 5.5
        // Step 3 picks newest older major — major=5 — top minor → gpt-5.5
        #expect(fallback?.key == "gpt-5.5")
        #expect(fallback?.strategy == .sameFamilyOlderMajor)
    }

    // MARK: - End-to-end integration via CostUsagePricing

    @Test
    func `codexCostUSD returns non-nil for unknown gpt-5.6 (was $0 before)`() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.6",
            inputTokens: 1000,
            cachedInputTokens: 0,
            outputTokens: 100)
        // gpt-5.5 pricing: 5e-6 input, 3e-5 output → 1000*5e-6 + 100*3e-5 = 0.005 + 0.003 = 0.008
        #expect(cost == 0.008)
    }

    @Test
    func `codexCostUSD returns non-nil for new variant via provider default`() throws {
        let cost = try #require(CostUsagePricing.codexCostUSD(
            model: "gpt-5.5-turbo",
            inputTokens: 1000,
            cachedInputTokens: 0,
            outputTokens: 100))
        // Provider default = gpt-5: 1000 * 1.25e-6 + 100 * 1e-5. Compute
        // expected via the same formula so IEEE 754 rounding errors don't
        // false-flag the assertion.
        let expected = 1000.0 * 1.25e-6 + 100.0 * 1e-5
        #expect(cost == expected)
    }

    @Test
    func `codexCostUSD still returns nil for non-Codex prefix`() {
        // `claude-opus-4-7` doesn't match the gpt- grammar at all → resolver
        // returns nil → cost stays nil. Sanity guard so Claude traffic
        // never lands on Codex pricing.
        let cost = CostUsagePricing.codexCostUSD(
            model: "claude-opus-4-7",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 50)
        #expect(cost == nil)
    }

    @Test
    func `isCodexModelKnown reflects exact-vs-fallback lookup`() {
        #expect(CostUsagePricing.isCodexModelKnown("gpt-5"))
        #expect(CostUsagePricing.isCodexModelKnown("gpt-5.4-mini"))
        #expect(CostUsagePricing.isCodexModelKnown("gpt-5.3-codex-spark"))
        #expect(!CostUsagePricing.isCodexModelKnown("gpt-5.6"))
        #expect(!CostUsagePricing.isCodexModelKnown("gpt-5.5-turbo"))
        #expect(!CostUsagePricing.isCodexModelKnown("claude-opus-4-7"))
    }

    // MARK: - Helpers

    /// Snapshot of the live Codex pricing table — keep in sync with
    /// upstream `CostUsagePricing.swift` `codex` dictionary. We can't
    /// reach the private static let directly from a test target.
    private static func liveCodexTable() -> [String: CostUsagePricing.CodexPricing] {
        let placeholder = CostUsagePricing.CodexPricing(
            inputCostPerToken: 0,
            outputCostPerToken: 0,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil)
        return [
            "gpt-5": placeholder,
            "gpt-5-codex": placeholder,
            "gpt-5-mini": placeholder,
            "gpt-5-nano": placeholder,
            "gpt-5-pro": placeholder,
            "gpt-5.1": placeholder,
            "gpt-5.1-codex": placeholder,
            "gpt-5.1-codex-max": placeholder,
            "gpt-5.1-codex-mini": placeholder,
            "gpt-5.2": placeholder,
            "gpt-5.2-codex": placeholder,
            "gpt-5.2-pro": placeholder,
            "gpt-5.3-codex": placeholder,
            "gpt-5.3-codex-spark": placeholder,
            "gpt-5.4": placeholder,
            "gpt-5.4-mini": placeholder,
            "gpt-5.4-nano": placeholder,
            "gpt-5.4-pro": placeholder,
            "gpt-5.5": placeholder,
            "gpt-5.5-pro": placeholder,
        ]
    }
}
