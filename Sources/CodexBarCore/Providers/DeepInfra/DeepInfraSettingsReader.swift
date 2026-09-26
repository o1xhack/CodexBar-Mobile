import Foundation

public struct DeepInfraSettingsReader: Sendable {
    public static let apiKeyEnvironmentKey = "DEEPINFRA_API_KEY"
    public static let apiKeyEnvironmentKeys = [Self.apiKeyEnvironmentKey, "DEEPINFRA_TOKEN"]

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        SettingsValue.first(in: environment, keys: self.apiKeyEnvironmentKeys)
    }
}
