import CodexBarSync
import Foundation

/// Reader-local linear quota pace (Research/065), shared by the provider
/// detail view and the Quota Pace widget.
///
/// The iPhone never observes provider usage itself; every number comes from
/// the Mac's latest refresh. Pace is therefore evaluated at the Mac's
/// observation time (`capturedAt`), never at the reader's clock: time passing
/// without a new observation must not look like slower use. The formula
/// matches the Mac's synced Codex value (`UsagePace.weekly`, linear): used
/// percent minus the share of the window that had elapsed, in percentage
/// points.
struct QuotaPace: Equatable, Codable, Sendable {
    enum Forecast: Equatable, Codable, Sendable {
        case lastsUntilReset(headroom: Bool)
        case emptyAt(Date)
    }

    /// Positive: using faster than even pace. Negative: slower.
    let deltaPercentagePoints: Double
    let forecast: Forecast?
    let capturedAt: Date

    /// Pace for a single window. Requires a window of at least one day with
    /// known, unblocked usage whose reset is still ahead of `referenceDate`.
    init?(window: SyncRateWindow?, capturedAt: Date, referenceDate: Date = .now, providerID: String? = nil) {
        guard let window, window.usageKnown, !window.isSyntheticPlaceholder, window.blockingQuota == nil,
              window.usedPercent.isFinite, window.usedPercent >= 0,
              let reset = window.resetsAt, reset.timeIntervalSince1970.isFinite,
              capturedAt.timeIntervalSince1970.isFinite, referenceDate.timeIntervalSince1970.isFinite,
              capturedAt <= referenceDate, referenceDate < reset,
              let duration = Self.duration(of: window, providerID: providerID, capturedAt: capturedAt)
        else { return nil }
        let remainingTime = reset.timeIntervalSince(capturedAt)
        guard remainingTime > 0, remainingTime <= duration else { return nil }
        let elapsed = duration - remainingTime
        // The Mac clamps over-limit usage to 100% (empty now).
        let used = min(100, window.usedPercent)
        // Same guard as the Mac: a fresh window with usage has no pace yet.
        if elapsed == 0, used > 0 { return nil }
        let expected = (elapsed / duration) * 100
        let delta = used - expected
        self.deltaPercentagePoints = delta
        self.capturedAt = capturedAt
        self.forecast = Self.forecast(
            used: used,
            elapsed: elapsed,
            remainingTime: remainingTime,
            delta: delta,
            capturedAt: capturedAt)
    }

    /// Pace of a provider's pace window at its latest Mac observation.
    init?(provider: ProviderUsageSnapshot, referenceDate: Date = .now) {
        // Mirrors the Mac's only `allowsEstimatedUsage: false` pace capability.
        if provider.providerID == "opencodego", provider.usageDataConfidence == "estimated" { return nil }
        self.init(
            window: Self.window(for: provider),
            capturedAt: provider.lastUpdated,
            referenceDate: referenceDate,
            providerID: provider.providerID)
    }

    /// The window pace describes, matching the Mac (`codexWeeklyWindow`):
    /// the native secondary, tertiary, then primary slot of at least one day.
    ///
    /// The Mac writes native slots first (primary, secondary, tertiary) and
    /// extra named windows after them. Native primary/secondary may keep a
    /// provider-defined id (Aixy budgets), so every window up to the last one
    /// with a standard slot id is native; extra windows after it (Codex Spark,
    /// Claude model lanes) never carry the provider's pace. Payloads whose
    /// windows carry ids but no standard one hold only extra windows (Kimi
    /// with just its monthly/Code lanes) and have no pace, except for
    /// providers whose plugin gives every native slot its own id: Aixy
    /// promotes its first two known budgets to primary/secondary
    /// (`aixy.js`), so its leading known windows are native. Only id-less
    /// payloads from older Macs fall back to the legacy secondary/primary.
    static func window(for provider: ProviderUsageSnapshot) -> SyncRateWindow? {
        let standard = ["secondary", "tertiary", "primary"]
        let windows = provider.rateWindows
        let candidates: [SyncRateWindow]
        if let lastNative = windows.lastIndex(where: { $0.id.map(standard.contains) == true }) {
            let native = windows[...lastNative]
            let bySlot = standard.compactMap { id in native.first { $0.id == id } }
            let customIDs = native.filter { $0.id.map(standard.contains) != true }
            candidates = bySlot + customIDs
        } else if windows.allSatisfy({ $0.id == nil }) {
            candidates = [provider.secondary, provider.primary].compactMap(\.self)
        } else if let slots = Self.customIDNativeSlotCounts[provider.providerID] {
            let native = windows.prefix(while: \.usageKnown).prefix(slots)
            candidates = native.reversed()
        } else {
            return nil
        }
        return candidates.first {
            !$0.isSyntheticPlaceholder
                && Self.duration(of: $0, providerID: provider.providerID, capturedAt: provider.lastUpdated) != nil
        }
    }

    /// Providers whose native slots all carry provider-defined ids, with how
    /// many leading known windows fill those slots.
    private static let customIDNativeSlotCounts: [String: Int] = ["aixy": 2]

    static let monthlySentinelMinutes = 30 * 24 * 60

    /// Providers whose Mac pace capability infers the real calendar month
    /// from the 30-day sentinel (`inferredMonthlyDuration`). Elsewhere, such
    /// as Codex's server-reported rolling 30-day window, 43200 minutes is the
    /// true length.
    private static let calendarMonthSentinelProviders: Set<String> = [
        "alibaba", "alibabatokenplan", "commandcode", "doubao", "mimo",
        "notion", "ollama", "opencodego", "stepfun",
    ]

    /// Pace window length, or nil when the window is shorter than one day or
    /// its length cannot be resolved. Mirrors the Mac's duration rules: the
    /// monthly sentinel becomes the UTC calendar month ending at the reset for
    /// the providers above, Zai's MCP window and Copilot windows without a
    /// length; an untyped Grok credits window is the weekly pool when its
    /// reset is 4–12 days away (`GrokProviderDescriptor.primaryLabel`); every
    /// other provider must carry its own length.
    static func duration(of window: SyncRateWindow, providerID: String?, capturedAt: Date? = nil) -> TimeInterval? {
        if providerID == "grok", window.windowMinutes == nil {
            guard let reset = window.resetsAt, let capturedAt else { return nil }
            let remaining = reset.timeIntervalSince(capturedAt)
            guard remaining > 3600 else { return nil }
            let days = Int((remaining / 86400).rounded(.toNearestOrAwayFromZero))
            return (4...12).contains(days) ? 7 * 86400 : nil
        }
        let infersCalendarMonth: Bool = switch providerID {
        case "copilot":
            window.windowMinutes == nil
        case "zai":
            window.windowMinutes == self.monthlySentinelMinutes && window.resetDescription == "MCP"
        case let id?:
            window.windowMinutes == self.monthlySentinelMinutes && self.calendarMonthSentinelProviders.contains(id)
        case nil:
            false
        }
        if infersCalendarMonth {
            guard let reset = window.resetsAt else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
            guard let start = calendar.date(byAdding: .month, value: -1, to: reset) else { return nil }
            let seconds = reset.timeIntervalSince(start)
            return seconds.isFinite && seconds >= 86400 ? seconds : nil
        }
        guard let minutes = window.windowMinutes, minutes >= 1440 else { return nil }
        return Double(minutes) * 60
    }

    enum Trend: Equatable, Sendable {
        case ahead
        case onPace
        case behind
    }

    /// Icon/color bucket: beyond five points either way reads as a trend.
    var trend: Trend {
        if self.deltaPercentagePoints > 5 { return .ahead }
        if self.deltaPercentagePoints < -5 { return .behind }
        return .onPace
    }

    /// Pace sentence only ("3 percentage points below even pace").
    func deltaText(locale: Locale = .current) -> String {
        let key = if abs(self.deltaPercentagePoints) <= 2 {
            "On even pace"
        } else if self.deltaPercentagePoints < 0 {
            "%lld percentage points below even pace"
        } else {
            "%lld percentage points above even pace"
        }
        return String(
            format: Self.localized(key, locale: locale),
            locale: locale,
            Int64(abs(self.deltaPercentagePoints).rounded()))
    }

    /// Forecast sentence only, nil when there is no forecast.
    func forecastText(locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        switch self.forecast {
        case let .lastsUntilReset(headroom):
            let lasts = Self.localized("Estimated to last until reset", locale: locale)
            guard headroom else { return lasts }
            return [lasts, Self.localized("At least 1.5× pace headroom", locale: locale)].joined(separator: " · ")
        case let .emptyAt(date):
            return String(
                format: Self.localized("Estimated empty at %@", locale: locale),
                QuotaResetDateText.compact(date, timeZone: timeZone))
        case nil:
            return nil
        }
    }

    func summary(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        [self.deltaText(locale: locale), self.forecastText(locale: locale, timeZone: timeZone)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    /// Assumes the average rate up to the observation continues.
    private static func forecast(
        used: Double,
        elapsed: TimeInterval,
        remainingTime: TimeInterval,
        delta: Double,
        capturedAt: Date) -> Forecast?
    {
        if used >= 100 { return .emptyAt(capturedAt) }
        // A window that has not started yet has no rate to extrapolate.
        guard elapsed > 0 else { return nil }
        if used == 0 { return .lastsUntilReset(headroom: false) }
        let projectedUsage = used * remainingTime / elapsed
        let remaining = 100 - used
        if projectedUsage <= remaining {
            let multiplier = projectedUsage > 0 ? remaining / projectedUsage : 0
            return .lastsUntilReset(headroom: delta < -15 && multiplier >= 1.5)
        }
        return .emptyAt(capturedAt.addingTimeInterval(remaining * elapsed / used))
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        MobileLocalizedString.value(key, defaultValue: key, locale: locale)
    }
}
