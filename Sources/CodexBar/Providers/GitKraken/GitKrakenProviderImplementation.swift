import CodexBarCore
import Foundation

struct GitKrakenProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .gitkraken

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .gitkraken, field: .apiKey]
        _ = settings[providerConfig: .gitkraken, field: .workspace]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "gitkraken-api-token",
                title: "GitKraken access token",
                subtitle: "Saved in CodexBar's local config file. Or set GITKRAKEN_API_TOKEN.",
                kind: .secure,
                placeholder: "Token value only (without Bearer)",
                binding: context.providerConfigBinding(.apiKey),
                actions: [.openURL(
                    id: "gitkraken-open-account",
                    title: "Open GitKraken Account",
                    url: URL(string: "https://gitkraken.dev/account#ai-usage"))],
                isVisible: nil),
            ProviderSettingsFieldDescriptor(
                id: "gitkraken-organization",
                title: "API organization ID",
                subtitle: "Optional gk-org-id header value. Or set GITKRAKEN_ORG_ID.",
                kind: .plain,
                placeholder: "Organization ID (optional)",
                binding: context.providerConfigBinding(.workspace),
                actions: [],
                isVisible: nil),
        ]
    }
}
