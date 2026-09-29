import Foundation

public enum XKiroProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .xkiro,
        displayName: "xKiro",
        sessionLabel: "Daily free tokens",
        weeklyLabel: "Weekly",
        dashboardURL: "https://xkiro.com",
        color: .init(hex: 0x52C99B),
        confetti: [0x52C99B, 0xB7F2D7],
        noDataMessage: "xKiro cost history is not available.",
        environmentKey: "XKIRO_API_KEY",
        missingCredentialMessage: { _ in "Set an xKiro API key in Settings or XKIRO_API_KEY." },
        menuBarMetrics: .init(supported: [.automatic, .primary]),
        apiKeyField: .init(
            id: "xkiro-api-key",
            title: "xKiro API key",
            subtitle: "Saved in CodexBar's local config file. Or set XKIRO_API_KEY. Reads free-token usage only."))
}
