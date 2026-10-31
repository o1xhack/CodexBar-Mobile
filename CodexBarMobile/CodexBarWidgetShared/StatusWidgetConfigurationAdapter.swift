import Intents

/// Converts the per-widget framework value into the existing rendering configuration.
/// SiriKit intents (iOS 26 and earlier) and their App Intents counterparts
/// (iOS 27 and later, Research/072) go through the same rules.
enum StatusWidgetConfigurationAdapter {
    static func configuration(from intent: SelectStatusWidgetIntent) -> CodexBarWidgetConfigurationIntent {
        let mode: CodexBarWidgetMode = switch intent.mode {
        case .providerFocus: .providerFocus
        case .todayCost: .todayCost
        case .syncHealth: .syncHealth
        default: .overview
        }
        return CodexBarWidgetConfigurationIntent(
            mode: mode,
            colorStyle: self.colorStyle(colorful: intent.colorStyle == .colorful),
            providers: self.providers([intent.provider1, intent.provider2, intent.provider3, intent.provider4]
                .map { (id: $0?.identifier, name: $0?.displayString) }))
    }

    @available(iOS 27.0, *)
    static func configuration(from intent: StatusWidgetAppIntent) -> CodexBarWidgetConfigurationIntent {
        let mode: CodexBarWidgetMode = switch intent.mode {
        case .overview: .overview
        case .providerFocus: .providerFocus
        case .todayCost: .todayCost
        case .syncHealth: .syncHealth
        }
        return CodexBarWidgetConfigurationIntent(
            mode: mode,
            colorStyle: self.colorStyle(colorful: intent.colorStyle == .colorful),
            providers: self.providers([intent.provider1, intent.provider2, intent.provider3, intent.provider4]
                .map { (id: $0?.id, name: $0?.displayString) }))
    }

    /// The overview's provider selection (Research/073). Widgets added
    /// before the parameter existed read `unknown` and keep manual selection.
    static func overviewSelection(from intent: SelectStatusWidgetIntent) -> WidgetOverviewSelection {
        let count: Int? = switch intent.providerCount {
        case .two: 2
        case .three: 3
        case .four: 4
        default: nil
        }
        return self.overviewSelection(
            soonestWeeklyReset: intent.providerSelection == .soonestWeeklyReset,
            count: count)
    }

    @available(iOS 27.0, *)
    static func overviewSelection(from intent: StatusWidgetAppIntent) -> WidgetOverviewSelection {
        self.overviewSelection(
            soonestWeeklyReset: intent.providerSelection == .soonestWeeklyReset,
            count: intent.providerCount.count)
    }

    /// The overview's per-slot windows and display (issue #223). Widgets added
    /// before the parameters existed read nil / `unknown`: weekly usage, as before.
    static func overviewQuota(from intent: SelectStatusWidgetIntent) -> WidgetOverviewQuotaOptions {
        self.overviewQuota(
            slots: [
                (intent.provider1?.identifier, intent.window1?.identifier),
                (intent.provider2?.identifier, intent.window2?.identifier),
                (intent.provider3?.identifier, intent.window3?.identifier),
                (intent.provider4?.identifier, intent.window4?.identifier),
            ],
            remaining: intent.quotaDisplay == .remaining)
    }

    @available(iOS 27.0, *)
    static func overviewQuota(from intent: StatusWidgetAppIntent) -> WidgetOverviewQuotaOptions {
        self.overviewQuota(
            slots: [
                (intent.provider1?.id, intent.window1?.id),
                (intent.provider2?.id, intent.window2?.id),
                (intent.provider3?.id, intent.window3?.id),
                (intent.provider4?.id, intent.window4?.id),
            ],
            remaining: intent.quotaDisplay == .remaining)
    }

    /// A slot's window counts only while it names the slot's current provider:
    /// changing the provider leaves the old choice behind without applying it.
    private static func overviewQuota(
        slots: [(providerID: String?, window: String?)],
        remaining: Bool) -> WidgetOverviewQuotaOptions
    {
        let choices = slots.compactMap { slot -> String? in
            guard let providerID = slot.providerID, let window = self.paceWindowChoice(identifier: slot.window),
                  QuotaPaceWindowChoice.windowID(from: window, providerID: providerID) != nil
            else { return nil }
            return window
        }
        return WidgetOverviewQuotaOptions(windowChoices: choices, display: remaining ? .remaining : .used)
    }

    private static func overviewSelection(soonestWeeklyReset: Bool, count: Int?) -> WidgetOverviewSelection {
        guard soonestWeeklyReset else { return .manual }
        return .soonestWeeklyReset(count: WidgetOverviewSelection.clampedCount(
            count ?? WidgetOverviewSelection.defaultCount))
    }

    /// Quota pace is its own widget kind rather than a status widget mode:
    /// SiriKit keeps the configuration schema a widget was added with, so a
    /// new mode never reaches status widgets placed before the update.
    static func configuration(from intent: SelectQuotaPaceWidgetIntent) -> CodexBarWidgetConfigurationIntent {
        CodexBarWidgetConfigurationIntent(
            mode: .quotaPace,
            colorStyle: self.colorStyle(colorful: intent.colorStyle == .colorful),
            providers: self.providers([(id: intent.provider?.identifier, name: intent.provider?.displayString)]))
    }

    @available(iOS 27.0, *)
    static func configuration(from intent: QuotaPaceWidgetAppIntent) -> CodexBarWidgetConfigurationIntent {
        CodexBarWidgetConfigurationIntent(
            mode: .quotaPace,
            colorStyle: self.colorStyle(colorful: intent.colorStyle == .colorful),
            providers: self.providers([(id: intent.provider?.id, name: intent.provider?.displayString)]))
    }

    /// The Quota pace widget's window choice (Research/071); nil for the
    /// default (weekly) window and for widgets added before the parameter
    /// existed.
    static func paceWindowChoice(from intent: SelectQuotaPaceWidgetIntent) -> String? {
        self.paceWindowChoice(identifier: intent.quotaWindow?.identifier)
    }

    @available(iOS 27.0, *)
    static func paceWindowChoice(from intent: QuotaPaceWidgetAppIntent) -> String? {
        self.paceWindowChoice(identifier: intent.quotaWindow?.id)
    }

    private static func paceWindowChoice(identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty, identifier != QuotaPaceWindowChoice.defaultIdentifier
        else { return nil }
        return identifier
    }

    private static func colorStyle(colorful: Bool) -> CodexBarWidgetColorStyle {
        colorful ? .colorful : .mono
    }

    /// Chosen providers in slot order without duplicates; unused slots,
    /// "Not selected" and empty ids select nothing (automatic selection).
    private static func providers(_ slots: [(id: String?, name: String?)]) -> [WidgetProviderEntity] {
        var seen = Set<String>()
        return slots.compactMap { slot -> WidgetProviderEntity? in
            guard let id = slot.id, !id.isEmpty,
                  id != StatusWidgetProviderChoice.emptyIdentifier, seen.insert(id).inserted
            else { return nil }
            let name = slot.name ?? ""
            return WidgetProviderEntity(id: id, name: name.isEmpty ? id : name)
        }
    }
}
