import Foundation
import Testing
@testable import CodexBarCore

/// Pins the Claude resolver against the live `CostUsagePricing.claude`
/// table — these tests serve as the upgrade radar for future Anthropic
/// model launches. If a future `claude-opus-4-9` ships and the resolver
/// silently regresses (no fallback, $0 row), the integration tests here
/// flip first.
@Suite("ClaudeFamilyResolver")
struct ClaudeFamilyResolverTests {
    private static let resolver = ClaudeFamilyResolver()

    // MARK: - Parser: happy path

    @Test
    func `Parses claude-opus-4-7 into family/major/minor`() throws {
        let parsed = try #require(Self.resolver.parse("claude-opus-4-7"))
        #expect(parsed.family == "opus")
        #expect(parsed.majorVersion == 4)
        #expect(parsed.minorVersion == 7)
        #expect(parsed.dateSuffix == nil)
        #expect(parsed.providerKey == "claude")
    }

    @Test
    func `Parses claude-opus-4 (no minor — base of major)`() throws {
        let parsed = try #require(Self.resolver.parse("claude-opus-4"))
        #expect(parsed.family == "opus")
        #expect(parsed.majorVersion == 4)
        #expect(parsed.minorVersion == nil)
    }

    @Test
    func `Parses dated form claude-opus-4-7-20260101`() throws {
        let parsed = try #require(Self.resolver.parse("claude-opus-4-7-20260101"))
        #expect(parsed.minorVersion == 7)
        #expect(parsed.dateSuffix == "20260101")
    }

    @Test
    func `Parses dated-no-minor form claude-opus-4-20260101`() throws {
        let parsed = try #require(Self.resolver.parse("claude-opus-4-20260101"))
        #expect(parsed.minorVersion == nil)
        #expect(parsed.dateSuffix == "20260101")
    }

    @Test
    func `Parses haiku and sonnet families`() throws {
        let haiku = try #require(Self.resolver.parse("claude-haiku-4-5"))
        let sonnet = try #require(Self.resolver.parse("claude-sonnet-4-6"))
        #expect(haiku.family == "haiku")
        #expect(sonnet.family == "sonnet")
    }

    // MARK: - Parser: rejection

    @Test
    func `Rejects gate IDs like claude-design and claude-routines`() {
        // These appear as Anthropic feature gate identifiers in our codebase
        // and must NEVER fall back to opus pricing — that would silently
        // bill flag traffic at the highest model rate.
        #expect(Self.resolver.parse("claude-design") == nil)
        #expect(Self.resolver.parse("claude-design-1-0") == nil)
        #expect(Self.resolver.parse("claude-routines") == nil)
        #expect(Self.resolver.parse("claude-routines-2-0") == nil)
    }

    @Test
    func `Rejects non-claude prefixes`() {
        #expect(Self.resolver.parse("gpt-5.5") == nil)
        #expect(Self.resolver.parse("opus-4-7") == nil)
        #expect(Self.resolver.parse("") == nil)
    }

    @Test
    func `Rejects unparseable major version`() {
        #expect(Self.resolver.parse("claude-opus-foo") == nil)
        #expect(Self.resolver.parse("claude-opus-foo-bar") == nil)
    }

    // MARK: - Fallback against the live table

    @Test
    func `Unknown claude-opus-4-8 falls back to claude-opus-4-7 (Step 1)`() throws {
        // The exact bug from Research/018: Mac 0.20.3 saw `claude-opus-4-7`
        // traffic, no row → $0. With the resolver, an unseen 4-8 walks
        // back to the highest known opus-4 row.
        let parsed = try #require(Self.resolver.parse("claude-opus-4-8"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: ClaudeFamilyResolverTests.liveClaudeTable())
        #expect(fallback?.key == "claude-opus-4-7")
        #expect(fallback?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Unknown claude-opus-5-0 walks back to opus-4 (Step 3 — older major)`() throws {
        let parsed = try #require(Self.resolver.parse("claude-opus-5-0"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: ClaudeFamilyResolverTests.liveClaudeTable())
        // Should pick highest minor of major=4 (i.e. 4-7), strategy = older major.
        #expect(fallback?.key == "claude-opus-4-7")
        #expect(fallback?.strategy == .sameFamilyOlderMajor)
    }

    @Test
    func `Unknown claude-haiku-5-0 falls back through haiku-4-5`() throws {
        let parsed = try #require(Self.resolver.parse("claude-haiku-5-0"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: ClaudeFamilyResolverTests.liveClaudeTable())
        #expect(fallback?.key == "claude-haiku-4-5")
        #expect(fallback?.strategy == .sameFamilyOlderMajor)
    }

    @Test
    func `Unknown claude-sonnet-4-7 falls back to sonnet-4-6 (Step 1)`() throws {
        let parsed = try #require(Self.resolver.parse("claude-sonnet-4-7"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: ClaudeFamilyResolverTests.liveClaudeTable())
        #expect(fallback?.key == "claude-sonnet-4-6")
        #expect(fallback?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Unknown claude-opus-3-0 (older than table) → family default kicks in`() throws {
        // No major=3 rows exist; lower-major lookup also empty (everything
        // in the table is major=4). Steps 1-3 all skip → Step 4 family
        // default for `opus` returns `claude-opus-4-7`.
        let parsed = try #require(Self.resolver.parse("claude-opus-3-0"))
        let fallback = Self.resolver.findFallback(
            for: parsed,
            in: ClaudeFamilyResolverTests.liveClaudeTable())
        #expect(fallback?.strategy == .familyDefault)
        #expect(fallback?.key == "claude-opus-4-7")
    }

    // MARK: - End-to-end integration via CostUsagePricing

    @Test
    func `claudeCostUSD returns non-nil for unknown opus minor (was $0 in Mac 0.20.3)`() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-99",
            inputTokens: 1000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 100)
        // 1000 * 5e-6 + 100 * 2.5e-5 = 0.005 + 0.0025 = 0.0075
        #expect(cost == 0.0075)
    }

    @Test
    func `claudeCostUSD still returns nil for non-Claude prefix`() {
        // Sanity: `glm-4.6` is not a Claude model — parser returns nil →
        // resolver returns nil → cost stays nil. Pinning so non-Claude
        // traffic doesn't accidentally start being priced as Claude.
        let cost = CostUsagePricing.claudeCostUSD(
            model: "glm-4.6",
            inputTokens: 100,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 40)
        #expect(cost == nil)
    }

    @Test
    func `isClaudeModelKnown returns true for exact rows, false for fallback`() {
        #expect(CostUsagePricing.isClaudeModelKnown("claude-opus-4-7"))
        #expect(CostUsagePricing.isClaudeModelKnown("claude-haiku-4-5"))
        // `claude-opus-4-99` flows through the fallback ladder — known
        // returns false, but the cost call still succeeds. This is the
        // signal SyncCoordinator uses in P4 to set isEstimated=true.
        #expect(!CostUsagePricing.isClaudeModelKnown("claude-opus-4-99"))
        #expect(!CostUsagePricing.isClaudeModelKnown("claude-opus-5-0"))
        #expect(!CostUsagePricing.isClaudeModelKnown("glm-4.6"))
    }

    // MARK: - Helpers

    /// Snapshot of the live Claude pricing table. We can't reach the
    /// `private static let claude` directly, so build a copy that
    /// matches the keys the resolver expects to see. Keep in sync if
    /// upstream `CostUsagePricing.swift` adds a new row.
    private static func liveClaudeTable() -> [String: CostUsagePricing.ClaudePricing] {
        let z: Double = 0
        let placeholder = CostUsagePricing.ClaudePricing(
            inputCostPerToken: z,
            outputCostPerToken: z,
            cacheCreationInputCostPerToken: z,
            cacheReadInputCostPerToken: z,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil)
        return [
            "claude-haiku-4-5-20251001": placeholder,
            "claude-haiku-4-5": placeholder,
            "claude-opus-4-5-20251101": placeholder,
            "claude-opus-4-5": placeholder,
            "claude-opus-4-6-20260205": placeholder,
            "claude-opus-4-6": placeholder,
            "claude-opus-4-7": placeholder,
            "claude-sonnet-4-5": placeholder,
            "claude-sonnet-4-6": placeholder,
            "claude-sonnet-4-5-20250929": placeholder,
            "claude-opus-4-20250514": placeholder,
            "claude-opus-4-1": placeholder,
            "claude-sonnet-4-20250514": placeholder,
        ]
    }
}
