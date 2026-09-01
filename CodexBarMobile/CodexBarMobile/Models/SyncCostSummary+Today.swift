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
        let costUSD: Double?
        let tokens: Int?
        /// `true` when today's cost row was computed via the Mac-side
        /// fallback resolver (model name not in the local pricing
        /// table). `nil` for old payloads from Mac < 0.23 and for the
        /// `sessionCostUSD` fallback path (session totals don't carry
        /// per-model estimation flags).
        let isEstimated: Bool?
        /// `false` means a zero cost is only a token-only wire placeholder.
        /// `nil` is a legacy payload and retains its historical display.
        let costIsKnown: Bool?
        /// `true` means the priced rows seen so far are displayable only as a
        /// lower bound because the producer has not finished establishing the
        /// configured scan window.
        let isLowerBound: Bool

        var displayCostUSD: Double? {
            self.costIsKnown == false ? nil : self.costUSD
        }
    }

    /// Returns the cost/tokens for today in the producer's bucket timezone,
    /// resolved from a single `now` timestamp (both fields share the same
    /// day key). Prefers the `daily` point for today; falls back to the
    /// current session's cost/tokens when no daily point exists yet (fresh
    /// start of day, before the Mac has written a 2026-04-23 entry).
    ///
    /// `now` is injectable so tests can pin a specific date and stay
    /// deterministic across wall-clock midnight crossings.
    func todayTotals(now: Date = Date()) -> TodayTotals {
        let todayKey = self.costDayKey(for: now)
        let sourceDayKey = self.sourceDayKey ?? self.sourceUpdatedAt.map(self.costDayKey)
        let sessionDayKey = self.sessionDayKey ?? sourceDayKey
        let sourceIsStale = sourceDayKey.map { $0 != todayKey } ?? false
        let sessionSourceIsStale = sessionDayKey.map { $0 != todayKey } ?? false
        // Historical coverage and gap counters describe the whole configured
        // scan window, not this dated row. Keep the history warning visible,
        // but do not erase an independently known, current-day amount. An
        // undated session fallback is not independently qualified, so it keeps
        // the aggregate coverage guard used by older payloads.
        let todayCalendarIsInvalid = self.hasInvalidBucketTimeZoneIdentifier
        let historicalCoverageIsIncomplete = self.historyCoverageIsEstablished == false ||
            self.coverage.map { $0.unpriced > 0 || $0.unmetered > 0 } == true
        if let todayPoint = self.daily.first(where: { $0.dayKey == todayKey }) {
            let costIsKnown = todayCalendarIsInvalid || sourceIsStale ? false : todayPoint.costIsKnown
            return TodayTotals(
                costUSD: todayPoint.costUSD,
                tokens: todayPoint.totalTokens,
                isEstimated: todayPoint.isEstimated,
                costIsKnown: costIsKnown,
                isLowerBound: costIsKnown != false && historicalCoverageIsIncomplete)
        }
        if sessionSourceIsStale {
            return TodayTotals(
                costUSD: nil,
                tokens: nil,
                isEstimated: nil,
                costIsKnown: false,
                isLowerBound: false)
        }
        let hasQualifiedCurrentSession = sessionDayKey == todayKey && self.sessionCostIsKnown == true
        let sessionCostIsKnown: Bool? = todayCalendarIsInvalid ||
            (historicalCoverageIsIncomplete && !hasQualifiedCurrentSession)
            ? false
            : self.sessionCostIsKnown ?? (self.sessionCostUSD == nil ? nil : true)
        return TodayTotals(
            costUSD: self.sessionCostUSD,
            tokens: self.sessionTokens,
            isEstimated: nil,
            costIsKnown: sessionCostIsKnown,
            isLowerBound: sessionCostIsKnown != false &&
                self.sessionCostUSD != nil && historicalCoverageIsIncomplete)
    }

    /// Logical day distance from the producer's current cost bucket.
    ///
    /// Day keys are parsed in UTC only as date-only Gregorian values; UTC is
    /// not used to reinterpret the producer timestamp. This lets a phone map
    /// `2026-08-22` from a UTC-pinned producer to "day 0" even while the phone
    /// itself is still on `2026-08-21`, keeping Today/7d/30d consumers aligned.
    func costDayOffset(for dayKey: String, from now: Date = Date()) -> Int? {
        var logicalCalendar = Calendar(identifier: .gregorian)
        logicalCalendar.timeZone = .gmt
        guard let pointDay = Self.logicalDay(from: dayKey, calendar: logicalCalendar) else {
            return nil
        }

        var producerCalendar = Calendar(identifier: .gregorian)
        producerCalendar.timeZone = self.bucketTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:)) ?? .current
        let producerComponents = producerCalendar.dateComponents([.year, .month, .day], from: now)
        guard let producerToday = logicalCalendar.date(from: producerComponents) else {
            return nil
        }
        return logicalCalendar.dateComponents([.day], from: producerToday, to: pointDay).day
    }

    /// Maps a producer-local logical day onto the reader's relative calendar
    /// axis. For example, a UTC producer's day 0 is the phone's local day 0 even
    /// when their `yyyy-MM-dd` strings differ around midnight.
    func readerRelativeDate(
        for dayKey: String,
        from now: Date = Date(),
        calendar: Calendar = .current) -> Date?
    {
        guard let offset = self.costDayOffset(for: dayKey, from: now) else { return nil }
        return calendar.date(
            byAdding: .day,
            value: offset,
            to: calendar.startOfDay(for: now))
    }

    /// Parses the fixed-width wire day without allocating `DateFormatter`.
    /// This path runs once per cost-history row on the main thread.
    private static func logicalDay(from dayKey: String, calendar: Calendar) -> Date? {
        let bytes = Array(dayKey.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45
        else { return nil }

        func digit(_ index: Int) -> Int? {
            let value = bytes[index]
            guard value >= 48, value <= 57 else { return nil }
            return Int(value - 48)
        }

        guard let y0 = digit(0), let y1 = digit(1), let y2 = digit(2), let y3 = digit(3),
              let m0 = digit(5), let m1 = digit(6),
              let d0 = digit(8), let d1 = digit(9)
        else { return nil }
        let components = DateComponents(
            calendar: calendar,
            timeZone: .gmt,
            year: y0 * 1000 + y1 * 100 + y2 * 10 + y3,
            month: m0 * 10 + m1,
            day: d0 * 10 + d1)
        guard let date = calendar.date(from: components) else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == components.year,
              verified.month == components.month,
              verified.day == components.day
        else { return nil }
        return date
    }

    /// Thread-safe ISO 8601 `yyyy-MM-dd` day key in the reader's current
    /// timezone. Modern summaries use `costDayKey(for:)` instead, which honors
    /// the producer's explicit bucket timezone; this helper remains the
    /// legacy/default formatter and is also used for reader-local UI dates.
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
        self.iso8601DayKeyFormatter().string(from: date)
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
