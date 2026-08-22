import CodexBarSync
import Foundation

/// iOS-only cost-resolution helpers for `SyncCostSummary`.
///
/// The Cost tab and each provider detail page both display a "Today" number,
/// but historically they sourced it from two different fields:
///   - Cost-tab summary cards (via `CostDashboardInsights`) preferred
///     `daily.first(where: dayKey == todayKey).costUSD` and fell back to
///     `sessionCostUSD` only when today had no daily entry.
///   - `ProviderDetailView.costSummarySection` used `sessionCostUSD` directly.
///
/// `sessionCostUSD` is the most recent session's cost on the reporting Mac; on
/// local-cost providers with multi-device sync it gets *summed* across Macs
/// during merge. `daily[today].costUSD` is the accurate sum-per-calendar-day
/// reading. Right after a fresh midnight sample both numbers agree; mid-day
/// they can diverge (session is stale relative to the accumulated daily point,
/// or vice versa when the daily point hasn't been written yet).
///
/// This extension centralizes the preference order so every view renders the
/// same number. Reported as the same class of bug as the Subscription
/// Utilization aggregate/detail mismatch fixed in Build 77.
extension SyncCostSummary {
    /// The pair of cost + tokens for today's calendar day, resolved together.
    ///
    /// Held as a pair (not two independent accessors) because separate
    /// accessors each calling `Date()` would drift across the midnight
    /// boundary: cost could use yesterday's key while tokens used today's,
    /// yielding an inconsistent `CostMetricCard`. Codex-reviewer caught this
    /// P3 issue in the initial Build 78 patch.
    struct TodayTotals: Equatable, Sendable {
        public let costUSD: Double?
        public let tokens: Int?
        /// `true` when today's cost row was computed via the Mac-side
        /// fallback resolver (model name not in the local pricing
        /// table). `nil` for old payloads from Mac < 0.23 and for the
        /// `sessionCostUSD` fallback path (session totals don't carry
        /// per-model estimation flags).
        public let isEstimated: Bool?
        /// `false` means a zero cost is only a token-only wire placeholder.
        /// `nil` is a legacy payload and retains its historical display.
        public let costIsKnown: Bool?

        public var displayCostUSD: Double? {
            self.costIsKnown == false ? nil : self.costUSD
        }
    }

    /// Returns the cost/tokens for today in the user's current timezone,
    /// resolved from a single `now` timestamp (both fields share the same
    /// day key). Prefers the `daily` point for today; falls back to the
    /// current session's cost/tokens when no daily point exists yet (fresh
    /// start of day, before the Mac has written a 2026-04-23 entry).
    ///
    /// `now` is injectable so tests can pin a specific date and stay
    /// deterministic across wall-clock midnight crossings.
    func todayTotals(now: Date = Date()) -> TodayTotals {
        let todayKey = Self.iso8601DayKey(for: now)
        if let todayPoint = self.daily.first(where: { $0.dayKey == todayKey }) {
            return TodayTotals(
                costUSD: todayPoint.costUSD,
                tokens: todayPoint.totalTokens,
                isEstimated: todayPoint.isEstimated,
                costIsKnown: todayPoint.costIsKnown)
        }
        return TodayTotals(
            costUSD: self.sessionCostUSD,
            tokens: self.sessionTokens,
            isEstimated: nil,
            costIsKnown: self.sessionCostUSD == nil ? nil : true)
    }

    /// Thread-safe ISO 8601 `yyyy-MM-dd` day key, in the user's current
    /// timezone (matches Mac-side `SyncCoordinator.daily[].dayKey`
    /// generation — both sides use `.current` timezone so a user's Mac and
    /// iPhone agree on "today" as long as they're in the same timezone).
    ///
    /// Creates a fresh `DateFormatter` per call rather than sharing a
    /// `static let` instance. Codex-reviewer flagged the shared formatter as
    /// P0: `DateFormatter` is documented NOT thread-safe on iOS and can
    /// crash under concurrent `string(from:)` calls, and `todayTotals(now:)`
    /// is reachable from both view-body rendering (main actor) and
    /// CloudSync background observers.
    ///
    /// The per-call allocation is cheap (formatter init is ~microseconds)
    /// and sync costs aren't on the per-frame hot path — callers that need
    /// to resolve many dates at once should batch through
    /// `iso8601DayKeyFormatter()` once, not via this helper.
    static func iso8601DayKey(for date: Date) -> String {
        Self.iso8601DayKeyFormatter().string(from: date)
    }

    /// Returns a fresh `DateFormatter` configured for the day-key wire
    /// format. Use when you need to reuse a formatter for multiple dates
    /// within a **single call site / thread**; do not store in shared state.
    static func iso8601DayKeyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
