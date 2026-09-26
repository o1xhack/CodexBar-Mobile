import Foundation

public enum VercelProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    public static let apiKey = "AI_GATEWAY_API_KEY"
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: Self.apiKey,
        resolve: { SettingsValue.cleaned($0[Self.apiKey]) },
        missingCredentialMessage: { _ in "Set a Vercel AI Gateway API key in Settings or AI_GATEWAY_API_KEY." })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .vercel,
            menuBarMetrics: .automaticOnly,
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .vercel,
                displayName: "Vercel AI Gateway",
                sessionLabel: "Balance",
                weeklyLabel: "Balance",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Vercel AI Gateway balance",
                cliName: "vercel",
                defaultEnabled: false,
                widgetSelectable: false,
                balanceOnly: true,
                dashboardURL: "https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai-gateway",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .vercel),
                iconResourceName: "ProviderIcon-vercel",
                color: ProviderColor(hex: 0xFFFFFF),
                confettiPalette: [ProviderColor(hex: 0xFFFFFF), ProviderColor(hex: 0xA3A3A3)]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Vercel AI Gateway cost history is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ScriptFetchStrategy(
                        id: "vercel.js",
                        provider: .vercel,
                        bundledPlugin: "vercel",
                        secretKey: self.apiKey,
                        sourceLabel: "api",
                        resolveSecret: { self.credentials.resolveToken(environment: $0)?.token },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(name: "vercel", versionDetector: nil))
    }
}
