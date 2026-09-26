import Foundation

public enum OpenCodeGoSettingsReader {
    public static let apiKeyEnvironmentKey = "OPENCODE_API_KEY"

    public static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        SettingsValue.cleaned(environment[self.apiKeyEnvironmentKey])
    }

    static func tokenAccountAPIKey(_ raw: String) -> String? {
        guard let value = SettingsValue.cleaned(raw),
              !value.contains(where: { $0.isWhitespace || $0 == "=" || $0 == ":" })
        else { return nil }
        return value
    }
}
