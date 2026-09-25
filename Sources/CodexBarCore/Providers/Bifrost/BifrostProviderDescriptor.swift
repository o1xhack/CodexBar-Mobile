import Foundation

public enum BifrostProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: BifrostSettingsReader.apiKeyEnvironmentKey,
        additionalProjections: [.enterpriseHost(BifrostSettingsReader.baseURLEnvironmentKey)],
        resolve: BifrostSettingsReader.apiKey,
        tokenAccountSupport: TokenAccountSupport(
            title: "Virtual keys",
            subtitle: "Store multiple Bifrost virtual keys.",
            placeholder: "Paste Bifrost virtual key…",
            injection: .environment(key: BifrostSettingsReader.apiKeyEnvironmentKey),
            requiresManualCookieSource: false,
            cookieName: nil))

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .bifrost,
            credentials: self.credentials,
            config: ProviderConfigCapabilities(supportsEnterpriseHost: true),
            metadata: ProviderMetadata(
                id: .bifrost,
                displayName: "Bifrost",
                sessionLabel: "Budget",
                weeklyLabel: "Secondary budget",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "Reads governance budgets and rate limits from the Bifrost virtual key quota endpoint.",
                toggleTitle: "Show Bifrost usage",
                cliName: "bifrost",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                debugLogUnavailableMessage: "Bifrost debug log not yet implemented",
                usesDetailBackedWindow: true,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .bifrost),
                iconResourceName: "ProviderIcon-bifrost",
                color: ProviderColor(hex: 0x33C09E),
                confettiPalette: [
                    ProviderColor(hex: 0x33C09E),
                    ProviderColor(hex: 0x1F7A63),
                    ProviderColor(hex: 0x8FE0C7),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Bifrost spend is reported by the provider API." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { snapshot in
                    let style: ProviderCostMenuCardStyle = (snapshot.providerCost?.limit ?? 1) <= 0
                        ? .apiSpend
                        : .hidden
                    return ProviderCostPresentation(menuCardStyle: style)
                },
                menuBarWindowResolver: { context in
                    guard context.metric == .automatic else { return .unhandled }
                    return .resolved(
                        ProviderUsagePresentation.exhausted(context.snapshot.primary, context.snapshot.secondary)
                            ?? context.snapshot.secondary
                            ?? context.snapshot.primary)
                },
                menuCard: ProviderMenuCardPresentation(
                    showsPrimaryBalanceDescription: true,
                    showsSecondaryBalanceDescription: true,
                    hidesPrimaryResetWithoutDate: true),
                menu: ProviderMenuDescriptorPresentation(
                    primaryDescriptionIsDetail: { _ in true },
                    secondaryDescriptionMode: .detailWhenResetDatePresent)),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [ScriptFetchStrategy(
                        id: "bifrost.js",
                        provider: .bifrost,
                        bundledPlugin: "bifrost",
                        secretKey: BifrostSettingsReader.apiKeyEnvironmentKey,
                        sourceLabel: "api",
                        validateContext: { context in
                            guard BifrostSettingsReader.baseURL(environment: context.env) != nil else {
                                throw ProviderFetchClassifiedError(
                                    kind: .apiFailure,
                                    message:
                                    "Set BIFROST_BASE_URL to an HTTPS URL, or HTTP on loopback/private networks, " +
                                        "without embedded credentials.")
                            }
                        },
                        resolveValues: { context in
                            guard let key = self.credentials.resolveToken(environment: context.env)?.token,
                                  BifrostSettingsReader.hasBaseURLOverride(environment: context.env)
                            else { return nil }
                            return ScriptFetchStrategy.Values(
                                settings: [BifrostSettingsReader.baseURLEnvironmentKey:
                                    BifrostSettingsReader.baseURL(environment: context.env)?.absoluteString ?? ""],
                                secrets: [BifrostSettingsReader.apiKeyEnvironmentKey: key])
                        },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(
                name: "bifrost",
                aliases: [],
                versionDetector: nil))
    }
}
