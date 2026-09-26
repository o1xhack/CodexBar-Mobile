import Foundation

public struct FireworksSettingsReader: Sendable {
    public static let apiKeyEnvironmentKeys = [
        "FIREWORKS_API_KEY",
        "FIREWORKS_KEY",
    ]
    public static let accountSlugEnvironmentKey = "FIREWORKS_ACCOUNT_SLUG"
    public static let configAPIKeyEnvironmentKey = "CODEXBAR_FIREWORKS_API_KEY"
    public static let configAccountSlugEnvironmentKey = "CODEXBAR_FIREWORKS_ACCOUNT_SLUG"

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        SettingsValue.first(in: environment, keys: [self.configAPIKeyEnvironmentKey] + self.apiKeyEnvironmentKeys)
    }

    public static func accountSlug(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        SettingsValue.first(
            in: environment,
            keys: [self.configAccountSlugEnvironmentKey, self.accountSlugEnvironmentKey])
    }
}
