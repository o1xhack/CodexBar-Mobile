import Foundation

public enum ChutesProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: ChutesSettingsReader.apiKeyEnvironmentKey,
        resolve: ChutesSettingsReader.apiKey)

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .chutes,
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .chutes,
                displayName: "Chutes",
                sessionLabel: "4-hour quota",
                weeklyLabel: "Monthly quota",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "Subscription usage from the Chutes API.",
                toggleTitle: "Show Chutes usage",
                cliName: "chutes",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                debugLogUnavailableMessage: "Chutes debug log not yet implemented",
                usesDetailBackedWindow: true,
                browserCookieOrder: nil,
                dashboardURL: "https://chutes.ai",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .chutes),
                iconResourceName: "ProviderIcon-chutes",
                color: ProviderColor(red: 49 / 255, green: 132 / 255, blue: 255 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x121212),
                    ProviderColor(hex: 0xFFFFFF),
                    ProviderColor(hex: 0x63D297),
                ],
                widgetColor: ProviderColor(red: 24 / 255, green: 160 / 255, blue: 88 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Chutes cost history is not available from CodexBar." }),
            presentation: ProviderUsagePresentation(
                primaryBindingQuotaLanes: [.secondary],
                menuCard: ProviderMenuCardPresentation(
                    showsPrimaryBalanceDescription: true,
                    showsSecondaryBalanceDescription: true,
                    hidesPrimaryResetWithoutDate: true),
                menu: ProviderMenuDescriptorPresentation(
                    primaryDescriptionIsDetail: { _ in true },
                    secondaryDescriptionMode: .detailWhenResetDatePresent)),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [Self.scriptStrategy()] })),
            cli: ProviderCLIConfig(
                name: "chutes",
                aliases: ["chutes.ai"],
                versionDetector: nil))
    }

    static func scriptStrategy(
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) -> ScriptFetchStrategy
    {
        ScriptFetchStrategy(
            id: "chutes.js",
            provider: .chutes,
            bundledPlugin: "chutes",
            secretKey: ChutesSettingsReader.apiKeyEnvironmentKey,
            sourceLabel: "api",
            transport: transport,
            validateContext: { context in
                guard ChutesSettingsReader.apiKey(environment: context.env) != nil else {
                    throw ProviderFetchClassifiedError(
                        kind: .missingCredential,
                        message: ChutesSettingsError.missingToken.localizedDescription)
                }
                try ChutesSettingsReader.validateEndpointOverrides(environment: context.env)
            },
            resolveValues: { context in
                guard let token = ChutesSettingsReader.apiKey(environment: context.env) else { return nil }
                return .init(
                    settings: ["BASE_URL": ChutesSettingsReader.apiURL(environment: context.env).absoluteString],
                    secrets: [ChutesSettingsReader.apiKeyEnvironmentKey: token])
            },
            isEnabled: { _ in true })
    }
}
