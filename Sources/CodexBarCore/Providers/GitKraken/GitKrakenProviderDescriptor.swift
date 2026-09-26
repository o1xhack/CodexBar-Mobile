import Foundation

public enum GitKrakenProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    public static let tokenKey = "GITKRAKEN_API_TOKEN"
    public static let organizationKey = "GITKRAKEN_ORG_ID"
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: Self.tokenKey,
        additionalProjections: [.workspaceID(Self.organizationKey)],
        resolve: { SettingsValue.cleaned($0[Self.tokenKey]) },
        missingCredentialMessage: { _ in "Set a GitKraken access token in Settings or GITKRAKEN_API_TOKEN." })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .gitkraken,
            credentials: self.credentials,
            config: ProviderConfigCapabilities(workspaceIDValidationOrder: 7),
            metadata: ProviderMetadata(
                id: .gitkraken,
                displayName: "GitKraken AI",
                sessionLabel: "Personal",
                weeklyLabel: "Shared pool",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show GitKraken AI usage",
                cliName: "gitkraken",
                defaultEnabled: false,
                widgetSelectable: false,
                dashboardURL: "https://gitkraken.dev/account#ai-usage",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .gitkraken),
                iconResourceName: "ProviderIcon-gitkraken",
                color: ProviderColor(hex: 0x179287),
                confettiPalette: [ProviderColor(hex: 0x179287), ProviderColor(hex: 0x9DE5D2)]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "GitKraken cost history is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ScriptFetchStrategy(
                        id: "gitkraken.js",
                        provider: .gitkraken,
                        bundledPlugin: "gitkraken",
                        secretKey: self.tokenKey,
                        sourceLabel: "api",
                        resolveValues: { context in
                            guard let token = self.credentials.resolveToken(environment: context.env)?.token else {
                                return nil
                            }
                            return ScriptFetchStrategy.Values(
                                settings: [
                                    self.organizationKey: context.env[self.organizationKey] ?? "",
                                    "CLIENT_VERSION": Bundle.main
                                        .object(forInfoDictionaryKey: "CFBundleShortVersionString")
                                        as? String ?? "0.0.0",
                                ],
                                secrets: [self.tokenKey: token])
                        },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(name: "gitkraken", aliases: ["gk"], versionDetector: nil))
    }
}
