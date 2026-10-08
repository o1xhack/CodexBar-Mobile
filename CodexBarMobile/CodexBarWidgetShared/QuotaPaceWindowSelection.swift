import CodexBarSync
import Foundation

/// Which quota window the Quota pace widget follows (Research/071).
///
/// Every window a provider reports is selectable by its stable id. Without a
/// choice, or when the chosen window is gone, the widget follows the weekly
/// window and otherwise keeps the Research/065 behavior (the native pace
/// window, then the charted lane).
enum QuotaPaceWindowSelection {
    struct Candidate: Equatable, Sendable {
        let id: String
        let window: SyncRateWindow
    }

    /// Shipped localizations, for catalogue titles.
    static let localizations = ["en", "zh-Hans", "zh-Hant", "ja"]

    /// The provider's windows in card order (native slots, then extra
    /// windows), each with a stable id. Windows from Macs that sent no id
    /// use their legacy slot name.
    static func candidates(for provider: ProviderUsageSnapshot) -> [Candidate] {
        let windows: [SyncRateWindow] = provider.rateWindows.isEmpty
            ? [provider.primary, provider.secondary].compactMap(\.self)
            : provider.rateWindows
        let legacySlots = ["primary", "secondary", "tertiary"]
        var seen = Set<String>()
        return windows.enumerated().compactMap { index, window in
            guard !window.isSyntheticPlaceholder else { return nil }
            let id = window.id ?? (index < legacySlots.count ? legacySlots[index] : "window-\(index)")
            guard seen.insert(id).inserted else { return nil }
            return Candidate(id: id, window: window)
        }
    }

    /// Windows offered in the widget configuration: those with known usage
    /// in the latest snapshot.
    static func selectableCandidates(for provider: ProviderUsageSnapshot) -> [Candidate] {
        self.candidates(for: provider).filter { $0.window.usageKnown && $0.window.usedPercent.isFinite }
    }

    /// A weekly window: seven days long, or declared weekly without a length.
    static func isWeekly(_ window: SyncRateWindow) -> Bool {
        if let minutes = window.windowMinutes { return minutes == 10080 }
        return window.period == .weekly
    }

    /// Remaining percent while the window's observation is current: known
    /// usage whose reset is still ahead of `now`.
    static func remainingPercent(of window: SyncRateWindow, now: Date) -> Double? {
        guard window.usageKnown, !window.isSyntheticPlaceholder, window.usedPercent.isFinite else { return nil }
        if let reset = window.resetsAt, reset <= now { return nil }
        return max(0, 100 - min(100, window.usedPercent))
    }

    /// The default window id: the weekly window with current usage (the
    /// native pace window first, then native slots, then extra windows),
    /// else the native pace window when it has a pace (Research/065), else
    /// nil so the widget keeps its charted-lane fallback.
    static func defaultWindowID(for provider: ProviderUsageSnapshot, now: Date) -> String? {
        let candidates = self.candidates(for: provider)
        let current = candidates.filter { self.remainingPercent(of: $0.window, now: now) != nil }
        let paceWindow = QuotaPace.window(for: provider)
        if let paceWindow, self.isWeekly(paceWindow),
           let match = current.first(where: { $0.window == paceWindow })
        {
            return match.id
        }
        let nativeOrder = ["secondary", "tertiary", "primary"]
        let weekly = current.filter { self.isWeekly($0.window) }
        if let native = nativeOrder.lazy.compactMap({ id in weekly.first { $0.id == id } }).first {
            return native.id
        }
        if let first = weekly.first { return first.id }
        if let paceWindow, QuotaPace(provider: provider, referenceDate: now) != nil,
           let match = candidates.first(where: { $0.window == paceWindow })
        {
            return match.id
        }
        return nil
    }

    /// Catalogue entries for the configuration picker, titled like the
    /// provider cards in every shipped localization.
    static func catalogueWindows(for provider: ProviderUsageSnapshot) -> [WidgetProviderWindowRecord] {
        self.selectableCandidates(for: provider).map { candidate in
            var titles: [String: String] = [:]
            for localization in self.localizations {
                titles[localization] = self.title(
                    of: candidate,
                    providerID: provider.providerID,
                    locale: Locale(identifier: localization))
            }
            return WidgetProviderWindowRecord(
                id: candidate.id,
                label: candidate.window.label,
                windowMinutes: candidate.window.windowMinutes,
                titles: titles)
        }
    }

    /// The card title of a window, with the cards' slot fallbacks.
    static func title(of candidate: Candidate, providerID: String, locale: Locale = .current) -> String {
        self.title(
            label: candidate.window.label,
            windowID: candidate.id,
            windowMinutes: candidate.window.windowMinutes,
            period: candidate.window.period,
            providerID: providerID,
            locale: locale)
    }

    static func title(
        label: String?,
        windowID: String,
        windowMinutes: Int?,
        period: SyncRateWindowPeriod?,
        providerID: String,
        locale: Locale = .current) -> String
    {
        // An unlabeled window is named by its length first (as the card's
        // "Weekly"), then by its slot.
        let isWeekly = windowMinutes == 10080 || (windowMinutes == nil && period == .weekly)
        let slotLabel: String? = isWeekly || windowID == "secondary" ? "Weekly" : windowID == "primary" ? "Session" :
            nil
        if label == nil, let slotLabel {
            let localized = ProviderWindowLabel.localized(
                slotLabel,
                fallback: slotLabel,
                providerID: providerID,
                period: period,
                locale: locale)
            return localized != slotLabel
                ? localized
                : MobileLocalizedString.value(slotLabel, defaultValue: slotLabel, locale: locale)
        }
        let fallback = MobileLocalizedString.value("Limit", defaultValue: "Limit", locale: locale)
        let title = ProviderWindowLabel.localized(
            label,
            fallback: fallback,
            providerID: providerID,
            period: period,
            locale: locale)
        // Plain slot labels ("Session", "Weekly") use the same first-party
        // translation as the widget's chart lanes.
        guard let label, title == label else { return title }
        return ProviderDetailLocalization.localized(label, providerID: providerID, locale: locale)
    }
}
