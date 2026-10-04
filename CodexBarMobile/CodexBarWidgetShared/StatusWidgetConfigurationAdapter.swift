import Intents

/// Converts the per-widget framework value into the existing rendering configuration.
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
            colorStyle: self.colorStyle(intent.colorStyle),
            providers: self.providers([intent.provider1, intent.provider2, intent.provider3, intent.provider4]))
    }

    /// Quota pace is its own widget kind rather than a status widget mode:
    /// SiriKit keeps the configuration schema a widget was added with, so a
    /// new mode never reaches status widgets placed before the update.
    static func configuration(from intent: SelectQuotaPaceWidgetIntent) -> CodexBarWidgetConfigurationIntent {
        CodexBarWidgetConfigurationIntent(
            mode: .quotaPace,
            colorStyle: self.colorStyle(intent.colorStyle),
            providers: self.providers([intent.provider]))
    }

    private static func colorStyle(_ style: StatusWidgetColorStyle) -> CodexBarWidgetColorStyle {
        style == .colorful ? .colorful : .mono
    }

    private static func providers(_ slots: [StatusWidgetProvider?]) -> [WidgetProviderEntity] {
        var seen = Set<String>()
        return slots.compactMap { provider -> WidgetProviderEntity? in
            guard let provider, let id = provider.identifier, !id.isEmpty,
                  id != StatusWidgetProviderChoice.emptyIdentifier, seen.insert(id).inserted
            else { return nil }
            return WidgetProviderEntity(id: id, name: provider.displayString.isEmpty ? id : provider.displayString)
        }
    }
}
