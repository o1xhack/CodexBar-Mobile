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
