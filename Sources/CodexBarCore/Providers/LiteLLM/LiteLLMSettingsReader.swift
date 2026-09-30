import Foundation

public enum LiteLLMSettingsReader {
    public static let modelUsageEnvironmentKey = "LITELLM_MODEL_USAGE_ENABLED"
    public static let apiKeyEnvironmentKey = "LITELLM_API_KEY"
    public static let baseURLEnvironmentKey = "LITELLM_BASE_URL"

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        SettingsValue.cleaned(environment[self.apiKeyEnvironmentKey])
    }

    public static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = SettingsValue.cleaned(environment[self.baseURLEnvironmentKey]) else { return nil }
        // The API key is sent to this URL as a bearer token, so validate it like every other
        // provider override. HTTP stays allowed for loopback and private-network proxies; public
        // hosts must use HTTPS, and no endpoint may carry embedded credentials.
        return ProviderEndpointOverrideValidator().validatedURLAllowingPrivateNetworkHTTP(raw)
    }
}

public enum LiteLLMUsageError: LocalizedError, Sendable {
    case invalidEndpointOverride(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpointOverride(key):
            "LiteLLM base URL override \(key) is invalid. Use an HTTPS URL, or plain HTTP for " +
                "loopback or private-network addresses and .local hosts, without embedded credentials."
        }
    }
}

extension ProviderConfig {
    public var litellmModelUsageEnabled: Bool? {
        get { self.extensionValue(forKey: "litellmModelUsageEnabled") }
        set { self.setExtensionValue(newValue, forKey: "litellmModelUsageEnabled") }
    }
}
