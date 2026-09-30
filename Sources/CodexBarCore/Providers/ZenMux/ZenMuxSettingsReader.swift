import Foundation

public enum ZenMuxSettingsReader {
    public static let managementAPIKeyEnvironmentKey = ZenMuxProviderDescriptor.spec.environmentKey

    public static func managementAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ZenMuxProviderDescriptor.spec.apiKey(environment: environment)
    }
}
