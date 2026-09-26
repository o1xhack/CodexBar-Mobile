import Foundation

public enum ZenMuxProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: ZenMuxSettingsReader.managementAPIKeyEnvironmentKey,
        resolve: ZenMuxSettingsReader.managementAPIKey)

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .zenmux,
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .zenmux,
                displayName: "ZenMux",
                sessionLabel: "5-hour quota",
                weeklyLabel: "Weekly quota",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show ZenMux usage",
                cliName: "zenmux",
                defaultEnabled: false,
                widgetSelectable: false,
                debugLogUnavailableMessage: "ZenMux debug log not yet implemented",
                dashboardURL: "https://zenmux.ai/platform/management",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .zenmux),
                iconResourceName: "ProviderIcon-zenmux",
                color: ProviderColor(red: 108 / 255, green: 92 / 255, blue: 231 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x6C5CE7),
                    ProviderColor(hex: 0xA29BFE),
                    ProviderColor(hex: 0xFFFFFF),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "ZenMux cost history is not exposed by the Management API." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { _ in ProviderCostPresentation(menuCardStyle: .payAsYouGoBalance) },
                primaryBindingQuotaLanes: [.secondary],
                menuCard: ProviderMenuCardPresentation(
                    primaryDescriptionPlacement: .detailLeft,
                    hidesPrimaryResetWithoutDate: true)),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ScriptFetchStrategy(
                        id: "zenmux.js",
                        provider: .zenmux,
                        bundledPlugin: "zenmux",
                        secretKey: ZenMuxSettingsReader.managementAPIKeyEnvironmentKey,
                        sourceLabel: "api",
                        timeout: 35,
                        resolveValues: Self.scriptValues,
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(
                name: "zenmux",
                aliases: ["zen-mux"],
                versionDetector: nil))
    }

    static func scriptValues(_ context: ProviderFetchContext) -> ScriptFetchStrategy.Values? {
        guard let key = ZenMuxSettingsReader.managementAPIKey(environment: context.env) else { return nil }
        let includePayg = context.runtime == .app ? context.includeOptionalUsage : context.includeCredits
        return .init(
            settings: ["INCLUDE_PAYG": includePayg ? "1" : "0"],
            secrets: [ZenMuxSettingsReader.managementAPIKeyEnvironmentKey: key])
    }
}
