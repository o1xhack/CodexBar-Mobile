import Foundation

public enum PoeSettingsReader {
    public static let apiKeyEnvironmentKey = PoeProviderDescriptor.spec.environmentKey

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        PoeProviderDescriptor.spec.apiKey(environment: environment)
    }
}
