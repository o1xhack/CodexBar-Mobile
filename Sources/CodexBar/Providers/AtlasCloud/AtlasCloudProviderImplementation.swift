import CodexBarCore

struct AtlasCloudProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .atlascloud

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .atlascloud, field: .apiKey]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "atlascloud-api-key",
            title: "Atlas Cloud API key",
            subtitle: "Saved in CodexBar's local config file. Or set ATLASCLOUD_API_KEY.",
            kind: .secure,
            placeholder: "Paste API key…",
            binding: context.providerConfigBinding(.apiKey),
            actions: [],
            isVisible: nil)]
    }
}
