import Foundation

/// Public facade over the internal `CostUsagePricing` model-name lookup
/// helpers. The `CodexBar` target (SyncCoordinator) uses these to decide
/// whether each `SyncCostBreakdown` had its cost computed from a fallback
/// pricing row — the signal flows up the wire as `isEstimated` so iOS
/// can render an "estimated" badge (P5).
///
/// Implementation lives on `CostUsagePricing` (vendored from upstream)
/// to keep the lookup co-located with the dictionaries; this facade
/// only exposes what other modules need without making the whole
/// upstream namespace public.
public enum ModelFallbackPricing {
    /// `true` iff the raw Claude model name resolves to an exact row in
    /// the local pricing table (after standard normalization). When
    /// `false`, the cost was either computed via the resolver fallback
    /// ladder (estimated) or the model isn't a Claude grammar match
    /// at all — callers should treat the breakdown as estimated only
    /// when this returns `false` AND a non-zero cost was produced.
    public static func isClaudeModelKnown(_ raw: String) -> Bool {
        CostUsagePricing.isClaudeModelKnown(raw)
    }

    /// `true` iff the raw Codex model name resolves to an exact row in
    /// the local pricing table (after standard normalization).
    public static func isCodexModelKnown(_ raw: String) -> Bool {
        CostUsagePricing.isCodexModelKnown(raw)
    }
}
