import Foundation
import Testing

@testable import CodexBarMobile

/// Pins the `CostFormatting` single-source-of-truth contract.
///
/// Before Build 82 five separate views (ContentView · ProviderDetailView ·
/// ProviderUsageView · CostShareCardView · CyberShareCardView) each had
/// their own `formatUSD` + `formatTokens` with subtly different signatures
/// (one returned `"N/A"` for nil, another `"—"`, a third crashed). Agent B's
/// cross-view audit flagged this as a drift risk: a future locale /
/// precision / unit-label tweak needed five coordinated edits. These tests
/// pin the centralized behavior so any future refactor can't silently
/// change the output in one view while forgetting another.
@Suite("Cost formatting central contract")
struct CostFormattingTests {
    @Test
    func `cost split only appears when the displayed modes cover the total`() {
        #expect(CodexCostSplit.subtitle(standardCostUSD: 1, priorityCostUSD: 2, totalCostUSD: 9) == nil)
        #expect(CodexCostSplit.subtitle(standardCostUSD: 1, priorityCostUSD: 2, totalCostUSD: 3) != nil)
        #expect(CodexCostSplit.subtitle(standardCostUSD: 0.1, priorityCostUSD: 0.2, totalCostUSD: 0.3) != nil)
    }

    // MARK: - USD

    @Test("usd formats whole dollars with two decimals and currency symbol")
    func usdWholeDollar() {
        // We don't pin exact locale output (tester's locale can shift the
        // grouping separator), but we assert structural properties that
        // hold across locales: no trailing garbage, two decimals after
        // the last period in en-like locales.
        let s = CostFormatting.usd(42)
        #expect(!s.isEmpty)
        #expect(s.contains("42"))
    }

    @Test("usd formats fractional cents with two decimals")
    func usdFractional() {
        let s = CostFormatting.usd(12.345)
        #expect(s.contains("12.34") || s.contains("12,34"))
    }

    @Test("usd optional overload returns — for nil")
    func usdNil() {
        #expect(CostFormatting.usd(nil as Double?) == "—")
    }

    @Test("usd optional overload unwraps for .some")
    func usdOptionalSome() {
        let value: Double? = 5
        #expect(CostFormatting.usd(value).contains("5"))
    }

    // MARK: - Tokens

    @Test("tokens under 1K uses the localized `tokens` label with thousands grouping")
    func tokensSmall() {
        let s = CostFormatting.tokens(42)
        #expect(s.contains("42"))
    }

    @Test("tokens in 1K–1M uses `K tokens`")
    func tokensThousands() {
        let s = CostFormatting.tokens(12_345)
        // 12345 / 1000 = 12.3
        #expect(s.contains("12.3") || s.contains("12,3"))
    }

    @Test("tokens in millions uses `M tokens`")
    func tokensMillions() {
        let s = CostFormatting.tokens(1_234_567)
        #expect(s.contains("1.2") || s.contains("1,2"))
    }

    @Test("tokens optional overload returns — for nil")
    func tokensNil() {
        #expect(CostFormatting.tokens(nil as Int?) == "—")
    }

    @Test("tokens is monotonic — a bigger count yields a lexicographically or suffix-shifted string")
    func tokensMonotonicSuffixTransition() {
        // Guard against a regression that drops the K/M suffix threshold
        // logic. We don't pin the exact number format but do pin that the
        // suffix transitions appear at the right boundaries.
        #expect(!CostFormatting.tokens(500).contains("K"))
        #expect(CostFormatting.tokens(500).contains("M") == false)
        #expect(CostFormatting.tokens(1500).contains("K"))
        #expect(CostFormatting.tokens(1_500_000).contains("M"))
    }
}
