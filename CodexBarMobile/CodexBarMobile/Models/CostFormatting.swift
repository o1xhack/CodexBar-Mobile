import CodexBarSync
import Foundation

/// Single source of truth for cost + token number formatting across the iOS app.
///
/// Before this file: `formatUSD` was duplicated in 5 views (ContentView,
/// ProviderDetailView, ProviderUsageView, CostShareCardView, CyberShareCardView)
/// and `formatTokens` in 4+ call sites with three subtly different signatures
/// (`Int`, `Int?`, with/without unit suffix). Agent B's cross-view audit
/// flagged this as a drift risk: any future locale / precision / unit-label
/// change would need coordinated edits to keep the views in lockstep, and
/// nothing was guarding that. Centralizing here collapses the risk into a
/// single function to test and review.
enum CostFormatting {
    /// Format a USD cost with two fractional digits, using the current
    /// locale's currency display style. Matches the `value.formatted(.currency(...))`
    /// API every pre-unified view was using.
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Optional variant so `LabeledContent(...)` call sites (which already pass
    /// `Int?`) don't each invent their own nil-guard.
    static func usd(_ value: Double?) -> String {
        value.map { Self.usd($0) } ?? "—"
    }

    /// Currency-aware cost formatter (upstream #1163). Uses the synced
    /// `currencyCode` so non-USD providers (Mistral EUR, DeepSeek CNY) render
    /// the correct symbol; falls back to USD when nil/empty.
    static func cost(_ value: Double, currencyCode: String?) -> String {
        let code = (currencyCode?.isEmpty == false) ? currencyCode! : "USD"
        return value.formatted(.currency(code: code).precision(.fractionLength(2)))
    }

    /// Format a raw token count into a compact labeled string:
    /// `1,234 tokens` · `45.6K tokens` · `12.3M tokens`.
    /// Labels pass through the app's localized `tokens` / `K tokens` / `M tokens`
    /// string keys (en / zh-Hans / zh-Hant / ja already defined in
    /// `Localizable.xcstrings`).
    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(Self.compactNumber(Double(count) / 1_000_000)) \(String(localized: "M tokens"))"
        } else if count >= 1000 {
            return "\(Self.compactNumber(Double(count) / 1000)) \(String(localized: "K tokens"))"
        }
        return "\(count.formatted()) \(String(localized: "tokens"))"
    }

    /// Optional variant for `LabeledContent`-style call sites.
    static func tokens(_ count: Int?) -> String {
        count.map { Self.tokens($0) } ?? "—"
    }

    private static func compactNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

/// Formats the Codex standard-vs-fast (priority) spend split sub-line
/// ("Std $X · Fast $Y", upstream v0.29.0 #1070) shown beneath a Codex
/// model/day's total cost — the iOS mirror of the Mac cost-history "Std /
/// Fast" detail. Returns nil when neither tier is present (non-Codex rows,
/// pre-0.29 Mac payloads) or both are zero, so other rows render unchanged.
/// Single source of truth shared by the Cost dashboard's Model Mix, the
/// Codex provider detail's daily-spend hover, and the Raw Sync Data inspector.
enum CodexCostSplit {
    static func subtitle(standardCostUSD: Double?, priorityCostUSD: Double?, totalCostUSD: Double) -> String? {
        guard totalCostUSD.isFinite else { return nil }
        guard standardCostUSD != nil || priorityCostUSD != nil else { return nil }
        let std = standardCostUSD ?? 0
        let fast = priorityCostUSD ?? 0
        guard std > 0 || fast > 0 else { return nil }
        let tolerance = max(1e-8, abs(totalCostUSD) * 1e-12)
        guard abs(std + fast - totalCostUSD) <= tolerance else { return nil }
        return String(
            format: String(localized: "Std %1$@ · Fast %2$@"),
            CostFormatting.usd(std),
            CostFormatting.usd(fast))
    }

    /// Window/day total split summed across a set of model breakdowns.
    /// Returns nil unless at least one breakdown carried a split field.
    static func subtitle(summing breakdowns: [SyncCostBreakdown]) -> String? {
        var std = 0.0
        var fast = 0.0
        var hasSplit = false
        for breakdown in breakdowns where breakdown.standardCostUSD != nil || breakdown.priorityCostUSD != nil {
            hasSplit = true
            std += breakdown.standardCostUSD ?? 0
            fast += breakdown.priorityCostUSD ?? 0
        }
        guard hasSplit else { return nil }
        return self.subtitle(
            standardCostUSD: std,
            priorityCostUSD: fast,
            totalCostUSD: breakdowns.reduce(0) { $0 + $1.costUSD })
    }
}
