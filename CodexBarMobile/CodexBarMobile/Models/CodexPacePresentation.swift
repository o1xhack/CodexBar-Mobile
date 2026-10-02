import CodexBarSync
import Foundation

/// Reader-local copy from numeric observations, never the Mac's localized label.
struct CodexPacePresentation {
    enum Forecast: Equatable {
        case lastsUntilReset(headroom: Bool)
        case emptyAt(Date)
    }

    let deltaPercentagePoints: Double
    let forecast: Forecast?

    init?(
        context: SyncCodexWorkspaceContext,
        window: SyncRateWindow?,
        referenceDate: Date = .now)
    {
        guard let delta = context.weeklyPaceDelta, delta.isFinite, (-1...1).contains(delta),
              context.updatedAt.timeIntervalSince1970.isFinite, context.updatedAt <= referenceDate
        else { return nil }
        if let reset = window?.resetsAt, reset <= referenceDate { return nil }
        self.deltaPercentagePoints = delta * 100
        self.forecast = Self.forecast(window: window, capturedAt: context.updatedAt, delta: delta * 100)
    }

    func summary(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let key = if abs(self.deltaPercentagePoints) <= 2 {
            "On even pace"
        } else if self.deltaPercentagePoints < 0 {
            "%lld percentage points below even pace"
        } else {
            "%lld percentage points above even pace"
        }
        var parts = [String(
            format: MobileLocalizedString.value(key, defaultValue: key, locale: locale),
            locale: locale,
            Int64(abs(self.deltaPercentagePoints).rounded()))]
        switch self.forecast {
        case let .lastsUntilReset(headroom):
            parts.append(Self.localized("Estimated to last until reset", locale: locale))
            if headroom {
                parts.append(Self.localized("At least 1.5× pace headroom", locale: locale))
            }
        case let .emptyAt(date):
            let key = "Estimated empty at %@"
            parts.append(String(
                format: Self.localized(key, locale: locale),
                QuotaResetDateText.compact(date, timeZone: timeZone)))
        case nil:
            break
        }
        return parts.joined(separator: " · ")
    }

    /// Matches the producer's secondary/tertiary/primary weekly-window preference.
    static func window(for provider: ProviderUsageSnapshot) -> SyncRateWindow? {
        let windows = provider.allRateWindows
        let candidates = [
            provider.secondary,
            windows.first { $0.id == "secondary" },
            windows.first { $0.id == "tertiary" },
            provider.primary,
            windows.first { $0.id == "primary" },
        ].compactMap(\.self) + windows
        return candidates.first { !$0.isSyntheticPlaceholder && ($0.windowMinutes ?? 0) >= 1440 }
    }

    private static func forecast(window: SyncRateWindow?, capturedAt: Date, delta: Double) -> Forecast? {
        guard let window, window.usageKnown, !window.isSyntheticPlaceholder, window.blockingQuota == nil,
              window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
              let minutes = window.windowMinutes, minutes >= 1440,
              let reset = window.resetsAt, reset.timeIntervalSince1970.isFinite
        else { return nil }
        let duration = Double(minutes) * 60
        let remainingTime = reset.timeIntervalSince(capturedAt)
        guard remainingTime > 0, remainingTime < duration else { return nil }
        let elapsed = duration - remainingTime
        let used = window.usedPercent
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
