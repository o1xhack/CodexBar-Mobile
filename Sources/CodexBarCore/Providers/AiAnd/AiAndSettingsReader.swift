import Foundation

public enum AiAndSettingsReader {
    public static let apiKeyEnvironmentKey = AiAndProviderDescriptor.spec.environmentKey

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        AiAndProviderDescriptor.spec.apiKey(environment: environment)
    }
}
