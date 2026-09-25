import CodexBarCore
import Foundation

struct DevPassProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .devpass

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .devpass, field: .apiKey]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "devpass-api-key",
            title: "DevPass API key",
            subtitle: "Saved in CodexBar's local config file. Or set DEVPASS_API_KEY.",
            kind: .secure,
            placeholder: "Regular LLM Gateway API key",
            binding: context.providerConfigBinding(.apiKey),
            actions: [.openURL(
                id: "devpass-dashboard",
                title: "Open DevPass",
                url: URL(string: "https://devpass.llmgateway.io/dashboard"))],
            isVisible: nil)]
    }
}
