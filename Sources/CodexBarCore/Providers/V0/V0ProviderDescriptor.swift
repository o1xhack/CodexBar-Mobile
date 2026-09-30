import Foundation

public enum V0ProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .v0,
        displayName: "v0",
        sessionLabel: "Billing",
        weeklyLabel: "Rate limit",
        creditsHint: "Billing and rate-limit data from the v0 Platform API",
        usesDetailBackedWindow: true,
        dashboardURL: "https://v0.app/settings/billing",
        color: ProviderColor(hex: 0x111111),
        confetti: [0x111111, 0xFFFFFF, 0x888888],
        widgetColor: ProviderColor(hex: 0x111111),
        noDataMessage: "v0 cost history is not available via the Platform API.",
        environmentKey: V0SettingsReader.apiKeyEnvironmentKey,
        apiKeyDebugLabel: V0SettingsReader.apiKeyEnvironmentKey,
        missingCredentialMessage: { _ in
            "v0 API key not configured. Create one at v0.app/settings/keys."
        },
        apiKeyField: .init(
            id: "v0-api-key",
            title: "API key",
            subtitle: "Stored in ~/.config/codexbar/config.json. Create one in v0 settings or set V0_API_KEY.",
            placeholder: "v0_...",
            action: (
                id: "v0-open-api-keys",
                title: "Open v0 API keys",
                url: "https://v0.app/settings/keys")),
        workspaceField: .init(
            environmentKey: V0SettingsReader.scopeEnvironmentKey,
            field: .init(
                id: "v0-scope",
                title: "Scope",
                subtitle: "Optional project ID or slug. Leave blank for the default v0 scope.",
                placeholder: "project-slug")),
        showsAPIDetail: true,
        availability: .configuredKey)
}
