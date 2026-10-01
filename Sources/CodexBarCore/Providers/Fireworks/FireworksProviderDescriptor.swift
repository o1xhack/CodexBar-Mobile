import Foundation

public enum FireworksProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor(
        credentials: Self.credentials,
        fetchPlan: ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [Self.scriptStrategy()] })))
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: FireworksSettingsReader.configAPIKeyEnvironmentKey,
        additionalProjections: [
            ProviderCredentialEnvironmentProjection(
                key: FireworksSettingsReader.configAccountSlugEnvironmentKey,
                value: { $0.sanitizedAccountSlug }),
        ],
        resolve: FireworksSettingsReader.apiKey)

    public static let spec = PluginProviderSpec(
        id: .fireworks,
        displayName: "Fireworks",
        sessionLabel: "Spend",
        weeklyLabel: "Spend",
        dashboardURL: "https://app.fireworks.ai",
        color: ProviderColor(hex: 0xF25B1C),
        confetti: [0xE65618, 0xFF9A3C, 0x2B2B2E],
        noDataMessage: "Fireworks spend comes from the billing summary API; cost history is not tracked.",
        settingsSection: .init(FireworksProviderSettingsKey.self),
        pluginResultPolicy: ProviderPluginResultPolicy(settings: ["ACCOUNT_SLUG": { value, config in
            guard value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
                  value != ".", value != ".."
            else { throw ProviderPluginError.invalidSnapshot("invalid discovered account slug") }
            config.accountSlug = value
        }]),
        presentation: ProviderUsagePresentation(
            costPresenter: { snapshot in
                let style: ProviderCostMenuCardStyle = (snapshot.providerCost?.limit ?? 1) <= 0
                    ? .apiSpend
                    : .generic
                return ProviderCostPresentation(menuCardStyle: style)
            },
            menuCard: ProviderMenuCardPresentation(providerCostIsRequiredUsage: true)),
        aliases: ["fw"])

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
