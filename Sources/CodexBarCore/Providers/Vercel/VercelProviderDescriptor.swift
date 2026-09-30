import Foundation

public enum VercelProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .vercel,
        displayName: "Vercel AI Gateway",
        sessionLabel: "Balance",
        weeklyLabel: "Balance",
        toggleTitle: "Show Vercel AI Gateway balance",
        balanceOnly: true,
        dashboardURL: "https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai-gateway",
        color: .init(hex: 0xFFFFFF),
        confetti: [0xFFFFFF, 0xA3A3A3],
        noDataMessage: "Vercel AI Gateway cost history is not available.",
        environmentKey: "AI_GATEWAY_API_KEY",
        missingCredentialMessage: { _ in "Set a Vercel AI Gateway API key in Settings or AI_GATEWAY_API_KEY." },
        apiKeyField: .init(
            id: "vercel-api-key",
            title: "Vercel AI Gateway API key",
            subtitle: "Saved in CodexBar's local config file. Or set AI_GATEWAY_API_KEY."))
}
