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
        /// Position among the provider card's windows, for its unlabeled
        /// "Session" / "Weekly" / "Limit N" names.
        let cardIndex: Int
    }

    /// Shipped localizations, for catalogue titles.
    static let localizations = ["en", "zh-Hans", "zh-Hant", "ja"]

    /// The provider's windows in card order (native slots, then extra
    /// windows), each with a stable id. Windows from Macs that sent no id
    /// keep the name of the slot they came from.
    static func candidates(for provider: ProviderUsageSnapshot) -> [Candidate] {
        let legacySlots = ["primary", "secondary", "tertiary"]
        let slotted: [(slot: String, window: SyncRateWindow)] = if provider.rateWindows.isEmpty {
            [("primary", provider.primary), ("secondary", provider.secondary)].compactMap { slot, window in
                window.map { (slot: slot, window: $0) }
            }
        } else {
            provider.rateWindows.enumerated().map { index, window in
                (slot: index < legacySlots.count ? legacySlots[index] : "window-\(index)", window: window)
            }
        }
        var seen = Set<String>()
        return slotted.filter { !$0.window.isSyntheticPlaceholder }.enumerated().compactMap { cardIndex, entry in
            let id = entry.window.id ?? entry.slot
            guard seen.insert(id).inserted else { return nil }
            return Candidate(id: id, window: entry.window, cardIndex: cardIndex)
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

    /// Windows that may stand for the account's allowance, as the
    /// Mac's weekly switcher (`mostConstrainedSwitcherWeeklyWindow`): Claude's
    /// Sonnet/Opus tertiary slot and its model-scoped and Routines extras are
    /// carve-outs, never the account's Weekly.
    static func isAccountWeeklyCandidate(_ candidate: Candidate, providerID: String) -> Bool {
        guard providerID == "claude" else { return true }
        let id = candidate.id
        return id != "tertiary" && !id.hasPrefix("claude-weekly-scoped-") && id != "claude-routines"
    }

    /// The default window id when the widget is configured for this
    /// provider: the native weekly pace window, else the most constrained
    /// current weekly window the Mac's weekly switcher would use, else the
    /// native pace window when it has a pace (Research/065), else nil so the
    /// widget keeps its charted-lane fallback.
    static func defaultWindowID(for provider: ProviderUsageSnapshot, now: Date) -> String? {
        let candidates = self.candidates(for: provider)
        let current = candidates.filter { self.remainingPercent(of: $0.window, now: now) != nil }
        let paceWindow = QuotaPace.window(for: provider)
        if let paceWindow, self.isWeekly(paceWindow),
           let match = current.first(where: { $0.window == paceWindow }),
           self.isAccountWeeklyCandidate(match, providerID: provider.providerID)
        {
            return match.id
        }
        let weekly = current.filter {
            self.isWeekly($0.window) && self.isAccountWeeklyCandidate($0, providerID: provider.providerID)
        }
        // Most constrained first; ties keep card order.
        if let mostConstrained = weekly.enumerated().max(by: { lhs, rhs in
            lhs.element.window.usedPercent == rhs.element.window.usedPercent
                ? lhs.offset > rhs.offset
                : lhs.element.window.usedPercent < rhs.element.window.usedPercent
        }) {
            return mostConstrained.element.id
        }
        if let paceWindow, QuotaPace(provider: provider, referenceDate: now) != nil,
           let match = candidates.first(where: { $0.window == paceWindow }),
           self.isAccountWeeklyCandidate(match, providerID: provider.providerID)
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

    /// The card title of a window, with the cards' fallbacks for windows
    /// without a label.
    static func title(of candidate: Candidate, providerID: String, locale: Locale = .current) -> String {
        self.title(
            label: candidate.window.label,
            cardIndex: candidate.cardIndex,
            period: candidate.window.period,
            providerID: providerID,
            locale: locale)
    }

    /// Same wording as the provider card (`ProviderDetailView.defaultLabel`
    /// plus `ProviderWindowLabel`); plain slot labels ("Session", "Weekly")
    /// also get the first-party translation the widget's chart lanes use.
    static func title(
        label: String?,
        cardIndex: Int?,
        period: SyncRateWindowPeriod?,
        providerID: String,
        locale: Locale = .current) -> String
    {
        let title = ProviderWindowLabel.localized(
            label,
            fallback: self.cardFallbackTitle(cardIndex: cardIndex ?? 0, providerID: providerID, locale: locale),
            providerID: providerID,
            period: period,
            locale: locale)
        guard let label, title == label else { return title }
        return ProviderDetailLocalization.localized(label, providerID: providerID, locale: locale)
    }

    /// The card's name for an unlabeled window at `cardIndex`.
    static func cardFallbackTitle(cardIndex: Int, providerID: String, locale: Locale) -> String {
        func localized(_ key: String) -> String {
            MobileLocalizedString.value(key, defaultValue: key, locale: locale)
        }
        if providerID == "xkiro", cardIndex == 0 { return localized("Daily free tokens") }
        if providerID == "aixy" { return localized(cardIndex == 0 ? "Budget" : "Secondary budget") }
        switch cardIndex {
        case 0: return localized("Session")
        case 1: return localized("Weekly")
        default: return "\(localized("Limit")) \(cardIndex + 1)"
        }
    }
}
