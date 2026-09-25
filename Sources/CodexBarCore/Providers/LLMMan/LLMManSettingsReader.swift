import Foundation

public enum LLMManSettingsReader {
    /// The key the `llmman` CLI itself presents to `llmman serve`.
    public static let apiKeyEnvironmentKey = "LLMMAN_API_KEY"
    /// The address `llmman serve` listens on, as the daemon itself reads it.
    public static let hostEnvironmentKey = "LLMMAN_HOST"
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:17434")!

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        SettingsValue.cleaned(environment[self.apiKeyEnvironmentKey])
    }

    /// The daemon origin, or nil when an override is not a safe place to send the API key.
    ///
    /// Scheme-less hosts default to HTTP on port 17434; explicit schemes retain their standard ports.
    /// HTTP is limited to loopback/private networks, and credentials, queries, and fragments are forbidden.
    public static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = SettingsValue.cleaned(environment[self.hostEnvironmentKey]) else {
            return self.defaultBaseURL
        }
        let hasScheme = raw.contains("://")
        guard var components = URLComponents(string: hasScheme ? raw : "http://\(raw)"),
              components.query == nil,
              components.fragment == nil
        else { return nil }
        if components.host == "0.0.0.0" {
            components.host = "127.0.0.1"
        }
        if !hasScheme, components.port == nil {
            components.port = self.defaultBaseURL.port
        }
        while components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        return ProviderEndpointOverrideValidator().validatedURLAllowingPrivateNetworkHTTP(components.string)
    }
}

public enum LLMManUsageError: LocalizedError, Sendable {
    case invalidEndpointOverride(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpointOverride(key):
            "llmman address \(key) is invalid. Use an HTTPS URL, or plain HTTP for " +
                "loopback or private-network addresses and .local hosts, " +
                "without embedded credentials, queries, or fragments."
        }
    }
}
