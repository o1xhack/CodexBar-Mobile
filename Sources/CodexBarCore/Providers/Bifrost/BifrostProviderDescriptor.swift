import Foundation

public enum BifrostProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .bifrost,
        displayName: "Bifrost",
        sessionLabel: "Budget",
        weeklyLabel: "Secondary budget",
        creditsHint: "Reads governance budgets and rate limits from the Bifrost virtual key quota endpoint.",
        debugLogUnavailableMessage: "Bifrost debug log not yet implemented",
        usesDetailBackedWindow: true,
        dashboardURL: nil,
        color: ProviderColor(hex: 0x33C09E),
        confetti: [0x33C09E, 0x1F7A63, 0x8FE0C7],
        noDataMessage: "Bifrost spend is reported by the provider API.",
        environmentKey: BifrostSettingsReader.apiKeyEnvironmentKey,
        tokenAccountSupport: TokenAccountSupport(
            title: "Virtual keys",
            subtitle: "Store multiple Bifrost virtual keys.",
            placeholder: "Paste Bifrost virtual key…",
            injection: .environment(key: BifrostSettingsReader.apiKeyEnvironmentKey),
            requiresManualCookieSource: false,
            cookieName: nil),
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
        validateContext: { context in
            guard BifrostSettingsReader.baseURL(environment: context.env) != nil else {
                throw ProviderFetchClassifiedError(
                    kind: .apiFailure,
                    message:
                    "Set BIFROST_BASE_URL to an HTTPS URL, or HTTP on loopback/private networks, " +
                        "without embedded credentials.")
            }
        },
        apiKeyField: .init(
            id: "bifrost-api-key",
            title: "Virtual key",
            subtitle: "Bifrost virtual key used to read its own budgets and rate limits.",
            placeholder: "Paste Bifrost virtual key…"),
        endpoint: .init(
            environmentKey: BifrostSettingsReader.baseURLEnvironmentKey,
            requirement: .required(.configured),
            resolve: BifrostSettingsReader.baseURL,
            field: .init(
                id: "bifrost-base-url",
                title: "Base URL",
                subtitle: "Bifrost gateway base URL, e.g. your company's self-hosted Bifrost host.",
                placeholder: "https://bifrost.example.com")),
        showsAPIDetail: true,
        availability: .environmentKey)
}
