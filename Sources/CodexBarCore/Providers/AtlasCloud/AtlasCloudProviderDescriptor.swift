import Foundation

public enum AtlasCloudProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .atlascloud,
        displayName: "Atlas Cloud",
        sessionLabel: "Balance",
        weeklyLabel: "Balance",
        toggleTitle: "Show Atlas Cloud balance",
        balanceOnly: true,
        dashboardURL: "https://www.atlascloud.ai/console",
        color: .init(hex: 0x5975F5),
        confetti: [0x5975F5, 0xA7B8FF],
        noDataMessage: "Atlas Cloud cost history is not available.",
        environmentKey: "ATLASCLOUD_API_KEY",
        missingCredentialMessage: { _ in "Set an Atlas Cloud API key in Settings or ATLASCLOUD_API_KEY." },
        apiKeyField: .init(
            id: "atlascloud-api-key",
            title: "Atlas Cloud API key",
            subtitle: "Saved in CodexBar's local config file. Or set ATLASCLOUD_API_KEY."))
}
