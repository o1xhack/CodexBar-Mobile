import AppIntents
import Foundation
import WidgetKit

struct WidgetProviderEntity: AppEntity, Codable, Hashable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static let defaultQuery = WidgetProviderQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(self.name)")
    }
}

struct WidgetProviderQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetProviderEntity] {
        let catalogue = try await self.suggestedEntities()
        return identifiers.map { id in
            catalogue.first { $0.id == id } ?? WidgetProviderEntity(id: id, name: id)
        }
    }

    func suggestedEntities() async throws -> [WidgetProviderEntity] {
        let catalogue = try WidgetProviderCatalogue.read()
        #if targetEnvironment(simulator)
        if catalogue.isEmpty, ProcessInfo.processInfo.environment["CODEXBAR_WIDGET_DISABLE_SIMULATOR_MOCK"] != "1" {
            return CodexBarWidgetSnapshot.placeholder().topProviders.map {
                WidgetProviderEntity(id: $0.providerID, name: $0.providerName)
            }
        }
        #endif
        return catalogue.map { WidgetProviderEntity(id: $0.id, name: $0.name) }
    }
}

enum WidgetProviderResetText {
    static func days(_ resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt else { return nil }
        let days = resetsAt.timeIntervalSince(now) / 86400
        guard days > 0 else { return String(localized: "Now") }
        if days < 0.1 { return String(localized: "<0.1d") }
        let number = days.formatted(.number.precision(.fractionLength(0...1)))
        return String(format: String(localized: "%@d"), number)
    }
}

extension WidgetProviderResetText {
    /// Hours until reset for windows shorter than a day (Research/071).
    static func hours(_ resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt else { return nil }
        let hours = resetsAt.timeIntervalSince(now) / 3600
        guard hours > 0 else { return String(localized: "Now") }
        if hours < 0.1 { return String(localized: "<0.1h") }
        let number = hours.formatted(.number.precision(.fractionLength(0...1)))
        return String(format: String(localized: "%@h"), number)
    }
}

/// How the CodexBar widget's overview picks its providers (Research/073).
/// Configured by the overview's "Provider Selection" parameter in both widget
/// generations and kept outside `CodexBarWidgetConfigurationIntent`, whose
/// schema belongs to the legacy widget kind.
enum WidgetOverviewSelection: Equatable, Sendable {
    /// The provider slots, or automatic selection when none is set: the
    /// behavior of every widget placed before this option existed.
    case manual
    /// The `count` providers whose weekly reset comes soonest, whatever order
    /// the app's Usage cards use.
    case soonestWeeklyReset(count: Int)

    static let counts = 2...4
    /// Readable in every widget size, and the small widget's automatic count.
    static let defaultCount = 2

    /// `count` kept within `counts`.
    static func clampedCount(_ count: Int) -> Int {
        min(max(count, self.counts.lowerBound), self.counts.upperBound)
    }

    /// For the DEBUG timeline logs.
    var logDescription: String {
        switch self {
        case .manual: "manual"
        case let .soonestWeeklyReset(count): "soonestWeeklyReset(\(count))"
        }
    }
}

/// What an overview tile's percentage counts (issue #223).
enum WidgetOverviewQuotaDisplay: Equatable, Sendable {
    case used
    case remaining
}

/// Per-tile quota choices of the overview (issue #223), kept outside the
/// legacy App Intent like `WidgetOverviewSelection`.
struct WidgetOverviewQuotaOptions: Equatable, Sendable {
    /// `QuotaPaceWindowChoice` identifiers of manual provider slots. Each
    /// names its own provider, so a choice never applies to another one.
    var windowChoices: [String] = []
    var display: WidgetOverviewQuotaDisplay = .used

    /// The window chosen for `providerID`; nil follows the weekly default.
    func windowID(for providerID: String) -> String? {
        self.windowChoices.lazy
            .compactMap { QuotaPaceWindowChoice.windowID(from: $0, providerID: providerID) }
            .first
    }
}

enum WidgetProviderSelection {
    /// The overview's providers for the configured selection.
    static func overview(
        from providers: [CodexBarWidgetProviderSummary],
        selected: [WidgetProviderEntity]?,
        selection: WidgetOverviewSelection,
        family: WidgetFamily,
        now: Date) -> [CodexBarWidgetProviderSummary]
    {
        switch selection {
        case .manual:
            self.resolve(from: providers, selected: selected, family: family, now: now)
        case let .soonestWeeklyReset(count):
            self.soonestWeeklyReset(from: providers, count: count, now: now)
        }
    }

    /// The app's "Weekly Reset (Soonest First)" comparison
    /// (`WeeklyResetOrdering`) over one entry per provider, cut to `count`
    /// (2 to 4). The entry kept for a provider is the one the overview shows
    /// in every mode (its first in `providers`, the most-used account), and
    /// its reset sorts it; with one account per provider the order matches
    /// the app's, with several it can differ (the app's collapsed card uses
    /// its first account). Past resets roll forward by whole weeks; providers
    /// without a weekly reset, and providers in error, follow by name; full
    /// ties keep the snapshot order. Only the synced summaries are read.
    static func soonestWeeklyReset(
        from providers: [CodexBarWidgetProviderSummary],
        count: Int,
        now: Date) -> [CodexBarWidgetProviderSummary]
    {
        var seen = Set<String>()
        let unique = providers.filter { seen.insert($0.providerID).inserted }
        let limit = WidgetOverviewSelection.clampedCount(count)
        let keyed = unique.enumerated().map { index, provider in
            // A provider in error has no current reset to show, so it never
            // takes a slot ahead of a working one (the app still sorts it).
            let reset = provider.isError ? nil : provider.weeklyResetsAt
            return (index: index, provider: provider, key: WeeklyResetOrdering.Key(
                resetAt: reset.map { WeeklyResetWindow.nextOccurrence(of: $0, after: now) },
                name: provider.providerName))
        }
        return keyed
            .sorted { lhs, rhs in WeeklyResetOrdering.precedes(lhs.key, rhs.key) ?? (lhs.index < rhs.index) }
            .prefix(limit)
            .map(\.provider)
    }

    /// The usage and reset an overview tile shows (Research/076). Every
    /// overview mode shows the provider's weekly window: the account-level one
    /// when it exists (`WeeklyResetWindow.soonest` only falls back to Claude's
    /// model-only or routine carve-outs when the account has no weekly window
    /// of its own), so a tile no longer switches between the session, weekly
    /// and model-only windows depending on which one is fullest. A weekly
    /// window without a reset shows its usage without a countdown; a provider
    /// without any weekly window keeps its most-used window. The selection no
    /// longer changes the figures; the parameter stays so callers and tests
    /// keep naming the mode they render.
    ///
    /// A manual slot's chosen window (`windowID`, issue #223) replaces the
    /// weekly figures with that window's own usage and reset; a window the
    /// provider no longer reports falls back to the weekly figures.
    /// `windowTitle` names the window the figures describe, when known.
    static func overviewFigures(
        for provider: CodexBarWidgetProviderSummary,
        selection _: WidgetOverviewSelection,
        windowID: String? = nil,
        now: Date) -> (usagePercent: Double?, resetsAt: Date?, windowTitle: String?)
    {
        let windows = provider.quotaPace?.windows ?? []
        if let windowID, let window = windows.first(where: { $0.id == windowID }) {
            let title = window.widgetTitle(providerID: provider.providerID)
            // A window that reset after the data was built (a 5-hour session within the
            // widget's refresh interval) has no current usage until the next sync.
            let current = window.resetsAt.map { $0 > now } ?? true
            return (current ? window.remainingPercent.map { 100 - $0 } : nil, current ? window.resetsAt : nil, title)
        }
        guard let weeklyReset = provider.weeklyResetsAt else {
            if let weeklyUsed = provider.weeklyUsedPercent {
                return (weeklyUsed, nil, Self.weeklyTitle)
            }
            // Remaining is derived as 100 - used, so compare with a tolerance (12.3 vs 12.2999…).
            let fullest = provider.usagePercent.flatMap { used in
                windows.first { window in
                    window.resetsAt == provider.resetsAt
                        && window.remainingPercent.map { abs(100 - $0 - used) < 0.001 } == true
                }
            }
            return (provider.usagePercent, provider.resetsAt, fullest?.widgetTitle(providerID: provider.providerID))
        }
        let next = WeeklyResetWindow.nextOccurrence(of: weeklyReset, after: now)
        // A reset that has passed since the data was built leaves its usage stale.
        return (next == weeklyReset ? provider.weeklyUsedPercent : nil, next, Self.weeklyTitle)
    }

    private static var weeklyTitle: String {
        String(localized: "Weekly")
    }

    static func resolve(
        from providers: [CodexBarWidgetProviderSummary],
        selected: [WidgetProviderEntity]?,
        family: WidgetFamily,
        now: Date) -> [CodexBarWidgetProviderSummary]
    {
        var seen = Set<String>()
        let unique = providers.filter { seen.insert($0.providerID).inserted }
        guard let selected, !selected.isEmpty else {
            // Automatic picks follow the figures the tiles show (weekly usage,
            // Research/076), so the fullest weekly windows lead; providers in
            // error stay behind working ones as before, and ties keep the
            // snapshot order.
            let ranked = unique.enumerated().sorted { lhs, rhs in
                if lhs.element.isError != rhs.element.isError { return !lhs.element.isError }
                let left = self.overviewFigures(for: lhs.element, selection: .manual, now: now).usagePercent ?? -1
                let right = self.overviewFigures(for: rhs.element, selection: .manual, now: now).usagePercent ?? -1
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            return Array(ranked.map(\.element).prefix(family == .systemSmall ? 2 : 4))
        }
        seen.removeAll()
        return selected.filter { seen.insert($0.id).inserted }.prefix(4).map { entity in
            unique.first { $0.providerID == entity.id } ?? CodexBarWidgetProviderSummary(
                id: "unavailable|\(entity.id)",
                providerName: entity.name,
                providerID: entity.id,
                loginMethod: nil,
                usagePercent: nil,
                todayCostUSD: nil,
                thirtyDayCostUSD: nil,
                tokensToday: nil,
                isError: true,
                statusMessage: String(localized: "Unavailable"),
                lastUpdated: now)
        }
    }

    /// Providers for the Quota Pace widget. A configured provider is always
    /// honored: without data for its window it comes back without
    /// `quotaPace` (the view says so) instead of silently showing another
    /// provider. Automatic selection prefers providers with a pace, then a
    /// chart (Codex, Claude), then the least remaining quota.
    ///
    /// `windowChoice` (Research/071) points a configured provider at one of
    /// its windows; without a choice, or with a choice for another provider
    /// or a window that is gone, a configured provider follows its default
    /// (weekly) window. Automatic provider selection ignores the choice and
    /// keeps the Research/065 data and ranking.
    static func pace(
        from providers: [CodexBarWidgetProviderSummary],
        selected: [WidgetProviderEntity]?,
        limit: Int,
        windowChoice: String? = nil,
        now: Date = .now) -> [CodexBarWidgetProviderSummary]
    {
        if let selected, !selected.isEmpty {
            var seen = Set<String>()
            return selected.filter { seen.insert($0.id).inserted }.prefix(limit).map { entity in
                let windowID = QuotaPaceWindowChoice.windowID(from: windowChoice, providerID: entity.id)
                let accounts = providers.filter { !$0.isError && $0.providerID == entity.id }
                // With several accounts, a chosen window comes only from the
                // accounts that report it; without one, every account falls
                // back to its default window.
                let holders = windowID.map { id in
                    accounts.filter { $0.quotaPace?.windows.contains { $0.id == id } == true }
                } ?? []
                return (holders.isEmpty ? accounts : holders)
                    .compactMap { provider -> CodexBarWidgetProviderSummary? in
                        guard let pace = provider.quotaPace?.configured(windowID: windowID),
                              pace.hasDisplayableData
                        else { return nil }
                        return provider.withQuotaPace(pace)
                    }
                    .max { Self.paceRank($0) < Self.paceRank($1) }
                    ?? CodexBarWidgetProviderSummary(
                        id: "unavailable|\(entity.id)",
                        providerName: entity.name,
                        providerID: entity.id,
                        loginMethod: nil,
                        usagePercent: nil,
                        todayCostUSD: nil,
                        thirtyDayCostUSD: nil,
                        tokensToday: nil,
                        isError: false,
                        statusMessage: nil,
                        lastUpdated: now)
            }
        }
        let candidates = providers.filter { !$0.isError && $0.quotaPace?.isAutomaticCandidate == true }
        var seen = Set<String>()
        return candidates
            .sorted { lhs, rhs in
                let lhsRank = Self.paceRank(lhs)
                let rhsRank = Self.paceRank(rhs)
                if lhsRank != rhsRank { return lhsRank > rhsRank }
                let lhsRemaining = lhs.quotaPace?.paceRemainingPercent ?? 100
                let rhsRemaining = rhs.quotaPace?.paceRemainingPercent ?? 100
                if lhsRemaining != rhsRemaining { return lhsRemaining < rhsRemaining }
                return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
            }
            .filter { seen.insert($0.providerID).inserted }
            .prefix(limit)
            .map(\.self)
    }

    /// Pace outranks a chart; providers with both rank highest. A followed
    /// window only counts its own chart.
    private static func paceRank(_ provider: CodexBarWidgetProviderSummary) -> Int {
        let hasPace = provider.quotaPace?.pace != nil
        let hasChart = provider.quotaPace?.hasPublishedChart == true
        return (hasPace ? 2 : 0) + (hasChart ? 1 : 0)
    }

    static func columns(count: Int, family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: count >= 3 ? 2 : 1
        case .systemMedium: count == 4 ? 2 : max(1, count)
        case .systemLarge: count > 2 ? 2 : 1
        case .systemExtraLarge: max(1, count)
        default: max(1, min(count, 2))
        }
    }
}
