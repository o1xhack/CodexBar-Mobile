import Foundation

public enum AixyProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .aixy,
        displayName: "Aixy",
        sessionLabel: "Budget",
        weeklyLabel: "Secondary budget",
        creditsHint: "Reads key-scoped usage and applicable budgets from Aixy.",
        debugLogUnavailableMessage: "Aixy debug log not yet implemented",
        usesDetailBackedWindow: true,
        dashboardURL: "https://dash.aixy-gateway.com",
        color: ProviderColor(hex: 0x123650),
        confetti: [0x123650, 0xEC744A, 0xF7F3E8],
        noDataMessage: "Aixy spend is reported by the provider API.",
        environmentKey: AixySettingsReader.apiKeyEnvironmentKey,
        tokenAccountSupport: TokenAccountSupport(
            title: "API keys",
            subtitle: "Store multiple Aixy API keys.",
            placeholder: "Paste Aixy API key…",
            injection: .environment(key: AixySettingsReader.apiKeyEnvironmentKey),
            requiresManualCookieSource: false,
            cookieName: nil),
        menuBarMetrics: .automaticOnly,
        presentation: ProviderUsagePresentation(
            costPresenter: { _ in ProviderCostPresentation(menuCardStyle: .apiSpend) },
            menuBarWindowResolver: { context in
                guard context.metric == .automatic else { return .unhandled }
                return .resolved(
                    context.snapshot.primary ?? context.snapshot.secondary)
            },
            menuCard: ProviderMenuCardPresentation(
                showsPrimaryBalanceDescription: true,
                showsSecondaryBalanceDescription: true,
                hidesPrimaryResetWithoutDate: true),
            menu: ProviderMenuDescriptorPresentation(
                primaryDescriptionIsDetail: { _ in true },
                secondaryDescriptionMode: .detailWhenResetDatePresent)),
        validateContext: { context in
            guard AixySettingsReader.baseURL(environment: context.env) != nil else {
                throw ProviderFetchClassifiedError(
                    kind: .apiFailure,
                    message:
                    "Set AIXY_BASE_URL to an HTTPS URL, or HTTP on loopback/private networks, " +
                        "without embedded credentials.")
            }
        },
        apiKeyField: .init(
            id: "aixy-api-key",
            title: "API key",
            subtitle: "Project-scoped Aixy key used to read its own usage and applicable budgets.",
            placeholder: "Paste Aixy API key…"),
        endpoint: .init(
            environmentKey: AixySettingsReader.baseURLEnvironmentKey,
            requirement: .optional(defaultURL: AixySettingsReader.defaultBaseURL),
            resolve: AixySettingsReader.baseURL,
            field: .init(
                id: "aixy-base-url",
                title: "Base URL",
                subtitle: "Optional Aixy gateway URL for a self-hosted or dedicated installation.",
                placeholder: "https://api.aixy-gateway.com")),
        showsAPIDetail: true,
        availability: .environmentKey)
}
