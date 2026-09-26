import CodexBarCore
import Foundation

struct HyperProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .hyper

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation(showsVersionInSettings: false) { _ in "Session or API key" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.hyperCookieSource
        _ = settings[providerConfig: .hyper, field: .cookieHeader]
        _ = settings[providerConfig: .hyper, field: .apiKey]
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        [ProviderCookieSourceUI.picker(
            id: "hyper-cookie-source",
            context: context,
            source: \.hyperCookieSource,
            allowsOff: true,
            subtitles: {
                .init(
                    auto: "Prefer a signed-in Hyper session from Chrome, then fall back to an API key.",
                    manual: "Paste a Cookie header from hyper.charm.land.",
                    off: "Use only the configured API key.")
            },
            trailingText: {
                ProviderCookieRefreshAction.trailingText(
                    provider: .hyper, cookieSource: context.settings.hyperCookieSource, context: context)
            },
            trailingActions: [ProviderCookieRefreshAction.descriptor(
                provider: .hyper, cookieSource: { context.settings.hyperCookieSource }, context: context)])]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "hyper-cookie",
                title: "Hyper cookie",
                subtitle: "Paste a Cookie header copied from a signed-in hyper.charm.land request.",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.providerConfigBinding(.cookieHeader),
                actions: [.openURL(
                    id: "hyper-open-dashboard",
                    title: "Open Charm Hyper",
                    url: URL(string: "https://hyper.charm.land"))],
                isVisible: { context.settings.hyperCookieSource == .manual }),
            ProviderSettingsFieldDescriptor(
                id: "hyper-api-key",
                title: "API key",
                subtitle: "Fallback when no session is available. Saved in the config file, or set HYPER_API_KEY.",
                kind: .secure,
                placeholder: "Paste API key…",
                binding: context.providerConfigBinding(.apiKey),
                actions: [],
                isVisible: nil),
        ]
    }
}

extension SettingsStore {
    var hyperCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .hyper, fallback: .auto) }
        set { self.setCookieSource(newValue, provider: .hyper) }
    }
}
