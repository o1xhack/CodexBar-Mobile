import Foundation

public enum AtlasCloudProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    public static let apiKey = "ATLASCLOUD_API_KEY"
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: Self.apiKey,
        resolve: { SettingsValue.cleaned($0[Self.apiKey]) },
        missingCredentialMessage: { _ in "Set an Atlas Cloud API key in Settings or ATLASCLOUD_API_KEY." })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .atlascloud,
            menuBarMetrics: .automaticOnly,
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .atlascloud,
                displayName: "Atlas Cloud",
                sessionLabel: "Balance",
                weeklyLabel: "Balance",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Atlas Cloud balance",
                cliName: "atlascloud",
                defaultEnabled: false,
                widgetSelectable: false,
                balanceOnly: true,
                dashboardURL: "https://www.atlascloud.ai/console",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .atlascloud),
                iconResourceName: "ProviderIcon-atlascloud",
                color: ProviderColor(hex: 0x5975F5),
                confettiPalette: [ProviderColor(hex: 0x5975F5), ProviderColor(hex: 0xA7B8FF)]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Atlas Cloud cost history is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ScriptFetchStrategy(
                        id: "atlascloud.js",
                        provider: .atlascloud,
                        bundledPlugin: "atlascloud",
                        secretKey: self.apiKey,
                        sourceLabel: "api",
                        resolveSecret: { self.credentials.resolveToken(environment: $0)?.token },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(name: "atlascloud", versionDetector: nil))
    }
}
