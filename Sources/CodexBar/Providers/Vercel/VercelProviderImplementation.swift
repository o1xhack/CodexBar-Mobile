import CodexBarCore

struct VercelProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .vercel

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .vercel, field: .apiKey]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "vercel-api-key",
            title: "Vercel AI Gateway API key",
            subtitle: "Saved in CodexBar's local config file. Or set AI_GATEWAY_API_KEY.",
            kind: .secure,
            placeholder: "Paste API key…",
            binding: context.providerConfigBinding(.apiKey),
            actions: [],
            isVisible: nil)]
    }
}
