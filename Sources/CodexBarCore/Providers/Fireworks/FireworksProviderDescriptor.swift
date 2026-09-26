import Foundation

public enum FireworksProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: FireworksSettingsReader.configAPIKeyEnvironmentKey,
        additionalProjections: [
            ProviderCredentialEnvironmentProjection(
                key: FireworksSettingsReader.configAccountSlugEnvironmentKey,
                value: { $0.sanitizedAccountSlug }),
        ],
        resolve: FireworksSettingsReader.apiKey)

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .fireworks,
            settingsSection: .init(FireworksProviderSettingsKey.self),
            credentials: self.credentials,
            pluginResultPolicy: ProviderPluginResultPolicy(settings: ["ACCOUNT_SLUG": { value, config in
                guard value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
                      value != ".", value != ".."
                else { throw ProviderPluginError.invalidSnapshot("invalid discovered account slug") }
                config.accountSlug = value
            }]),
            metadata: ProviderMetadata(
                id: .fireworks,
                displayName: "Fireworks",
                sessionLabel: "Spend",
                weeklyLabel: "Spend",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Fireworks usage",
                cliName: "fireworks",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                balanceOnly: false,
                dashboardURL: "https://app.fireworks.ai",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .fireworks),
                iconResourceName: "ProviderIcon-fireworks",
                color: ProviderColor(red: 242 / 255, green: 91 / 255, blue: 28 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0xE65618),
                    ProviderColor(hex: 0xFF9A3C),
                    ProviderColor(hex: 0x2B2B2E),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Fireworks spend comes from the billing summary API; cost history is not tracked." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { snapshot in
                    let style: ProviderCostMenuCardStyle = (snapshot.providerCost?.limit ?? 1) <= 0
                        ? .apiSpend
                        : .generic
                    return ProviderCostPresentation(menuCardStyle: style)
                },
                menuCard: ProviderMenuCardPresentation(providerCostIsRequiredUsage: true)),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [Self.scriptStrategy()] })),
            cli: ProviderCLIConfig(
                name: "fireworks",
                aliases: ["fw"],
                versionDetector: nil))
    }

    static func scriptStrategy(transport: any ProviderHTTPTransport = ProviderHTTPClient
        .shared) -> ScriptFetchStrategy
    {
        ScriptFetchStrategy(
            id: "fireworks.js",
            provider: .fireworks,
            bundledPlugin: "fireworks",
            secretKey: "FIREWORKS_API_KEY",
            transport: transport,
            resolveValues: { context in
                guard let key = FireworksSettingsReader.apiKey(environment: context.env) else { return nil }
                var settings: [String: String] = [:]
                settings["ACCOUNT_SLUG"] = FireworksSettingsReader.accountSlug(environment: context.env)
                return .init(settings: settings, secrets: ["FIREWORKS_API_KEY": key])
            }, isEnabled: { _ in true })
    }
}
