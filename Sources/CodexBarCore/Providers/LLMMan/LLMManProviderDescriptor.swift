import Foundation

public enum LLMManProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .llmman,
        displayName: "llmman",
        sessionLabel: "Memory",
        weeklyLabel: "Models",
        usesDetailBackedWindow: true,
        dashboardURL: LLMManSettingsReader.defaultBaseURL.absoluteString,
        color: ProviderColor(hex: 0x6CC5B0),
        confetti: [0x6CC5B0, 0x2F7F74, 0xFFFFFF],
        noDataMessage: "llmman cost summary is not supported.",
        environmentKey: LLMManSettingsReader.apiKeyEnvironmentKey,
        // The memory bar describes loaded weights, not a quota that resets.
        presentation: ProviderUsagePresentation(
            menuCard: ProviderMenuCardPresentation(
                showsPrimaryBalanceDescription: true,
                hidesPrimaryResetWithoutDate: true),
            menu: ProviderMenuDescriptorPresentation(primaryDescriptionIsDetail: { _ in true })),
        validateContext: { context in
            guard LLMManSettingsReader.baseURL(environment: context.env) != nil else {
                throw LLMManUsageError.invalidEndpointOverride(LLMManSettingsReader.hostEnvironmentKey)
            }
        },
        apiKeyField: .init(
            id: "llmman-api-key",
            title: "API key",
            subtitle: "Stored in ~/.codexbar/config.json. Only needed when llmman serve requires API keys.",
            placeholder: "LLMMAN_API_KEY"),
        endpoint: .init(
            environmentKey: LLMManSettingsReader.hostEnvironmentKey,
            requirement: .optional(defaultURL: LLMManSettingsReader.defaultBaseURL),
            resolve: LLMManSettingsReader.baseURL,
            field: .init(
                id: "llmman-base-url",
                title: "Base URL",
                subtitle: "Address of llmman serve. Defaults to http://127.0.0.1:17434.",
                placeholder: LLMManSettingsReader.defaultBaseURL.absoluteString),
            action: (id: "llmman-open-web-ui", title: "Open llmman")),
        requiresAPIKeyForFetch: false,
        showsAPIDetail: true)
}
