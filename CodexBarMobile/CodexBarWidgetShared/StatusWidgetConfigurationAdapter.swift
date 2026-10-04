import Intents

/// Converts the per-widget framework value into the existing rendering configuration.
enum StatusWidgetConfigurationAdapter {
    static func configuration(from intent: SelectStatusWidgetIntent) -> CodexBarWidgetConfigurationIntent {
        let mode: CodexBarWidgetMode = switch intent.mode {
        case .providerFocus: .providerFocus
        case .todayCost: .todayCost
        case .syncHealth: .syncHealth
        case .quotaPace: .quotaPace
        default: .overview
        }
        let colorStyle: CodexBarWidgetColorStyle = intent.colorStyle == .colorful ? .colorful : .mono
        var seen = Set<String>()
        // Quota pace has its own single provider parameter: a parameter can
        // only be shown for one mode value in an intent definition.
        let slots = mode == .quotaPace
            ? [intent.paceProvider]
            : [intent.provider1, intent.provider2, intent.provider3, intent.provider4]
        let providers = slots.compactMap { provider -> WidgetProviderEntity? in
            guard let provider, let id = provider.identifier, !id.isEmpty,
                  id != StatusWidgetProviderChoice.emptyIdentifier, seen.insert(id).inserted
            else { return nil }
            return WidgetProviderEntity(id: id, name: provider.displayString.isEmpty ? id : provider.displayString)
        }
        return CodexBarWidgetConfigurationIntent(
            mode: mode,
            colorStyle: colorStyle,
            providers: providers)
    }
}
