import Foundation

public enum DevPassProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    public static let apiKey = "DEVPASS_API_KEY"
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: Self.apiKey,
        resolve: { SettingsValue.cleaned($0[Self.apiKey]) },
        missingCredentialMessage: { _ in "Set a DevPass API key in Settings or DEVPASS_API_KEY." })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .devpass,
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .devpass,
                displayName: "DevPass",
                sessionLabel: "Plan credits",
                weeklyLabel: "Premium weekly",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show DevPass usage",
                cliName: "devpass",
                defaultEnabled: false,
                widgetSelectable: false,
                dashboardURL: "https://devpass.llmgateway.io/dashboard",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .devpass),
                iconResourceName: "ProviderIcon-devpass",
                color: ProviderColor(hex: 0x2563EB),
                confettiPalette: [ProviderColor(hex: 0x2563EB), ProviderColor(hex: 0x93C5FD)]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "DevPass cost history is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ScriptFetchStrategy(
                        id: "devpass.js",
                        provider: .devpass,
                        bundledPlugin: "devpass",
                        secretKey: self.apiKey,
                        sourceLabel: "api",
                        resolveSecret: { self.credentials.resolveToken(environment: $0)?.token },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(name: "devpass", versionDetector: nil))
    }
}
