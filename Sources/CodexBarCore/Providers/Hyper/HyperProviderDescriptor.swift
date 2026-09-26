import Foundation
import SweetCookieKit

public enum HyperProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    public static let apiKeyEnvironmentKey = "HYPER_API_KEY"
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: apiKeyEnvironmentKey,
        resolve: Self.apiKey,
        tokenAccountSupport: TokenAccountSupport(
            title: "API keys",
            subtitle: "Store multiple Charm Hyper API keys.",
            placeholder: "Paste API key…",
            injection: .environment(key: apiKeyEnvironmentKey),
            requiresManualCookieSource: false,
            cookieName: nil),
        missingCredentialMessage: { _ in "Sign in to hyper.charm.land or configure a Charm Hyper API key." },
        selectedAccountSourceModeResolver: { base, account, _ in
            base == .auto && account != nil ? .api : base
        })

    public static func apiKey(environment: [String: String]) -> String? {
        SettingsValue.cleaned(environment[self.apiKeyEnvironmentKey])
    }

    private static var browserCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        [.chrome]
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .hyper,
            menuBarMetrics: .automaticOnly,
            settingsSection: .init(HyperProviderSettingsKey.self, cookieSettings: CookieProviderSettings.self),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .hyper,
                displayName: "Charm Hyper",
                sessionLabel: "Balance",
                weeklyLabel: "Balance",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Charm Hyper usage",
                cliName: "hyper",
                defaultEnabled: false,
                widgetSelectable: false,
                balanceOnly: true,
                browserCookieOrder: self.browserCookieOrder,
                dashboardURL: "https://hyper.charm.land",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .hyper),
                iconResourceName: "ProviderIcon-hyper",
                color: ProviderColor(hex: 0xFF60FF),
                confettiPalette: [ProviderColor(hex: 0xFF60FF), ProviderColor(hex: 0xFFFFFF)]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Charm Hyper cost history is not available via API." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { _ in ProviderCostPresentation(showsGenericFallback: false, menuCardStyle: .hidden) }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    [ScriptFetchStrategy(
                        id: "hyper.js",
                        provider: .hyper,
                        bundledPlugin: "hyper",
                        sourceLabel: context.sourceMode.rawValue,
                        kind: context.sourceMode == .web ? .web : .apiToken,
                        resolveValues: { context in
                            .init(
                                settings: ["SOURCE_MODE": context.sourceMode.rawValue],
                                secrets: Self.apiKey(environment: context.env)
                                    .map { [apiKeyEnvironmentKey: $0] } ?? [:])
                        },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(
                name: "hyper",
                versionDetector: nil,
                browserSupportExemption: { _, _, settings in
                    settings?[HyperProviderSettingsKey.self]?.cookieSource == .manual
                }))
    }
}

public enum HyperProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.hyper
    public typealias Section = CookieProviderSettings
}
