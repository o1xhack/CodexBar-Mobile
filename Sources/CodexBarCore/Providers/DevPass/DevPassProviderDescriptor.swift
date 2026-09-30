import Foundation

public enum DevPassProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .devpass,
        displayName: "DevPass",
        sessionLabel: "Plan credits",
        weeklyLabel: "Premium weekly",
        dashboardURL: "https://devpass.llmgateway.io/dashboard",
        color: .init(hex: 0x2563EB),
        confetti: [0x2563EB, 0x93C5FD],
        noDataMessage: "DevPass cost history is not available.",
        environmentKey: "DEVPASS_API_KEY",
        missingCredentialMessage: { _ in "Set a DevPass API key in Settings or DEVPASS_API_KEY." },
        apiKeyField: .init(
            id: "devpass-api-key",
            title: "DevPass API key",
            subtitle: "Saved in CodexBar's local config file. Or set DEVPASS_API_KEY.",
            placeholder: "Regular LLM Gateway API key",
            action: ("devpass-dashboard", "Open DevPass", "https://devpass.llmgateway.io/dashboard")))
}
