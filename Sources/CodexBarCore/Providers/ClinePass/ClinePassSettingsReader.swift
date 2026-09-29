import Foundation

public enum ClinePassSettingsReader {
    public static let alternateAPIKeyEnvironmentKey = ClinePassProviderDescriptor.spec.environmentAliases[0]

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ClinePassProviderDescriptor.spec.apiKey(environment: environment)
    }

    struct FileCredential: Equatable, Sendable {
        let token: String
        let isOAuth: Bool
    }

    static func fileCredential(
        environment: [String: String],
        authFileURL: URL? = nil) -> FileCredential?
    {
        // Ambient test contexts must never discover the user's real Cline session.
        let pathKeys = ["CLINE_PROVIDER_SETTINGS_PATH", "CLINE_DATA_DIR", "CLINE_DIR", "HOME"]
        guard !TestProcessSafety.isRunning || authFileURL != nil ||
            pathKeys.contains(where: { SettingsValue.cleaned(environment[$0]) != nil }) else { return nil }
        let file = authFileURL ?? self.providersFileURL(environment: environment)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return self.parseCredential(data)
    }

    static func providersFileURL(
        environment: [String: String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL
    {
        let home = SettingsValue.cleaned(environment["HOME"]).map { URL(fileURLWithPath: $0) } ?? homeDirectory
        func path(_ key: String) -> URL? {
            guard let value = SettingsValue.cleaned(environment[key]) else { return nil }
            if value == "~" { return home }
            if value.hasPrefix("~/") { return home.appendingPathComponent(String(value.dropFirst(2))) }
            return URL(fileURLWithPath: value)
        }
        if let file = path("CLINE_PROVIDER_SETTINGS_PATH") { return file }
        let directory = path("CLINE_DATA_DIR") ??
            (path("CLINE_DIR") ?? home.appendingPathComponent(".cline")).appendingPathComponent("data")
        return directory.appendingPathComponent("settings/providers.json")
    }

    static func parseCredential(_ data: Data) -> FileCredential? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [String: Any],
              let cline = providers["cline"] as? [String: Any],
              let settings = cline["settings"] as? [String: Any] else { return nil }
        let auth = settings["auth"] as? [String: Any]
        // Match Cline's getApiKey: OAuth wins over keys retained in the same settings entry.
        if let access = SettingsValue.cleaned(auth?["accessToken"] as? String) {
            let token = access.hasPrefix("workos:") ? access : "workos:\(access)"
            return FileCredential(token: token, isOAuth: true)
        }
        guard let key = SettingsValue.cleaned(settings["apiKey"] as? String) ??
            SettingsValue.cleaned(auth?["apiKey"] as? String) else { return nil }
        return FileCredential(token: key, isOAuth: false)
    }
}
