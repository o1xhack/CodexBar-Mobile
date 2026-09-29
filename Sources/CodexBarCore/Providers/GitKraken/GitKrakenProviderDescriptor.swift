import Foundation

public enum GitKrakenProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor()
    private static let organizationKey = "GITKRAKEN_ORG_ID"
    public static let spec = PluginProviderSpec(
        id: .gitkraken,
        displayName: "GitKraken AI",
        sessionLabel: "Personal",
        weeklyLabel: "Shared pool",
        dashboardURL: "https://gitkraken.dev/account#ai-usage",
        color: .init(hex: 0x179287),
        confetti: [0x179287, 0x9DE5D2],
        noDataMessage: "GitKraken cost history is not available.",
        environmentKey: "GITKRAKEN_API_TOKEN",
        missingCredentialMessage: { _ in "Set a GitKraken access token in Settings or GITKRAKEN_API_TOKEN." },
        additionalProjections: [.workspaceID(Self.organizationKey)],
        config: ProviderConfigCapabilities(workspaceIDValidationOrder: 7),
        aliases: ["gk"],
        scriptSettings: { context in
            [
                Self.organizationKey: context.env[Self.organizationKey] ?? "",
                "CLIENT_VERSION": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "0.0.0",
            ]
        })
}
