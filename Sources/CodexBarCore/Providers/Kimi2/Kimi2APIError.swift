import Foundation

public enum Kimi2APIError: LocalizedError, Sendable, Equatable {
    case missingToken
    case invalidToken
    case missingAPIKey
    case invalidAPIKey
    case invalidRequest(String)
    case networkError(String)
    case apiError(String)
    case parseFailed(String)
    case expiredCodeCredential
    case invalidCodeCredential

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "Kimi2 auth token is missing. Please add your JWT token from the Kimi2 console."
        case .invalidToken:
            "Kimi2 auth token is invalid or expired. Please refresh your token."
        case .missingAPIKey:
            "Kimi2 Code API key is missing. Add it in Settings > Providers > Kimi2 or set KIMI2_CODE_API_KEY."
        case .invalidAPIKey:
            "Kimi2 Code API key is invalid or expired. Please refresh your API key."
        case let .invalidRequest(message):
            "Invalid request: \(message)"
        case let .networkError(message):
            "Kimi2 network error: \(message)"
        case let .apiError(message):
            "Kimi2 API error: \(message)"
        case let .parseFailed(message):
            "Failed to parse Kimi2 usage data: \(message)"
        case .expiredCodeCredential:
            "Kimi2 Code CLI credential is expired. Sign in again with Kimi2 Code CLI or set KIMI2_CODE_API_KEY; " +
                "CodexBar does not refresh CLI-owned credentials."
        case .invalidCodeCredential:
            "Kimi2 Code CLI credential is invalid or expired. Sign in again with Kimi2 Code CLI or set " +
                "KIMI2_CODE_API_KEY; CodexBar does not refresh CLI-owned credentials."
        }
    }
}
