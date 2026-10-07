import Foundation

public struct AntigravityOAuthCredentials: Codable, Sendable, Equatable {
    public var accessToken: String?
    public var refreshToken: String?
    public var expiryDateMilliseconds: Double?
    public var idToken: String?
    public var email: String?
    public var projectID: String?
    public var clientID: String?
    public var clientSecret: String?

    public init(
        accessToken: String?,
        refreshToken: String?,
        expiryDate: Date?,
        idToken: String? = nil,
        email: String? = nil,
        projectID: String? = nil,
        clientID: String? = nil,
        clientSecret: String? = nil)
    {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiryDateMilliseconds = expiryDate.map { $0.timeIntervalSince1970 * 1000 }
        self.idToken = idToken
        self.email = email
        self.projectID = projectID
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public var expiryDate: Date? {
        guard let expiryDateMilliseconds else { return nil }
        return Date(timeIntervalSince1970: expiryDateMilliseconds / 1000)
    }

    /// Email of the Google account these credentials authenticate, preferring the
    /// signed `id_token` claim (what the remote OAuth fetcher reports) and falling
    /// back to the stored `email` field. Used to verify that an ambient local/CLI
    /// Antigravity snapshot belongs to the account the user explicitly selected.
    public var resolvedAccountEmail: String? {
        Self.email(fromIDToken: self.idToken) ?? self.email?.trimmedNonEmpty
    }

    static func email(fromIDToken idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return (json["email"] as? String)?.trimmedNonEmpty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken =
            try container.decodeIfPresent(String.self, forKey: .accessTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .accessTokenCamel)
        self.refreshToken =
            try container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenCamel)
        self.idToken =
            try container.decodeIfPresent(String.self, forKey: .idTokenSnake)
            ?? container.decodeIfPresent(String.self, forKey: .idTokenCamel)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.projectID =
            try container.decodeIfPresent(String.self, forKey: .projectIDSnake)
            ?? container.decodeIfPresent(String.self, forKey: .projectIDCamel)
        self.clientID =
            try container.decodeIfPresent(String.self, forKey: .clientIDSnake)
            ?? container.decodeIfPresent(String.self, forKey: .clientIDCamel)
        self.clientSecret =
            try container.decodeIfPresent(String.self, forKey: .clientSecretSnake)
            ?? container.decodeIfPresent(String.self, forKey: .clientSecretCamel)

        if let expiryDateMilliseconds = try container.decodeIfPresent(Double.self, forKey: .expiryDateSnake)
            ?? container.decodeIfPresent(Double.self, forKey: .expiresAtCamel)
        {
            self.expiryDateMilliseconds = expiryDateMilliseconds
        } else if let expiryDateMilliseconds = try container.decodeIfPresent(Int.self, forKey: .expiryDateSnake)
            ?? container.decodeIfPresent(Int.self, forKey: .expiresAtCamel)
        {
            self.expiryDateMilliseconds = Double(expiryDateMilliseconds)
        } else {
            self.expiryDateMilliseconds = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.accessToken, forKey: .accessTokenSnake)
        try container.encodeIfPresent(self.refreshToken, forKey: .refreshTokenSnake)
        try container.encodeIfPresent(self.expiryDateMilliseconds, forKey: .expiryDateSnake)
        try container.encodeIfPresent(self.idToken, forKey: .idTokenSnake)
        try container.encodeIfPresent(self.email, forKey: .email)
        try container.encodeIfPresent(self.projectID, forKey: .projectIDSnake)
        try container.encodeIfPresent(self.clientID, forKey: .clientIDSnake)
        try container.encodeIfPresent(self.clientSecret, forKey: .clientSecretSnake)
    }

    enum CodingKeys: String, CodingKey {
        case accessTokenSnake = "access_token"
        case accessTokenCamel = "accessToken"
        case refreshTokenSnake = "refresh_token"
        case refreshTokenCamel = "refreshToken"
        case expiryDateSnake = "expiry_date"
        case expiresAtCamel = "expiresAt"
        case idTokenSnake = "id_token"
        case idTokenCamel = "idToken"
        case email
        case projectIDSnake = "project_id"
        case projectIDCamel = "projectId"
        case clientIDSnake = "client_id"
        case clientIDCamel = "clientId"
        case clientSecretSnake = "client_secret"
        case clientSecretCamel = "clientSecret"
    }
}

public struct AntigravityOAuthClient: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public enum AntigravityOAuthConfig {
    public static var configuredClientID: String? {
        ProcessInfo.processInfo.environment["ANTIGRAVITY_OAUTH_CLIENT_ID"]?.trimmedNonEmpty
    }

    public static var configuredClientSecret: String? {
        ProcessInfo.processInfo.environment["ANTIGRAVITY_OAUTH_CLIENT_SECRET"]?.trimmedNonEmpty
    }

    public static let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    public static let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
    public static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
    ]

    public static let missingCredentialsMessage =
        """
        Could not discover a matching Antigravity OAuth client. Update or install Antigravity.app, or set \
        ANTIGRAVITY_OAUTH_CLIENT_ID and ANTIGRAVITY_OAUTH_CLIENT_SECRET before logging in.
        """

    public static func resolvedClient() -> AntigravityOAuthClient? {
        if let clientID = configuredClientID, let clientSecret = configuredClientSecret {
            return AntigravityOAuthClient(clientID: clientID, clientSecret: clientSecret)
        }
        return self.discoverClientFromInstalledApp()
    }

    static func discoverClientFromInstalledApp(
        applicationRoots: [URL]? = nil,
        fileManager: FileManager = .default) -> AntigravityOAuthClient?
    {
        for url in self.candidateOAuthClientArtifactURLs(
            applicationRoots: applicationRoots,
            fileManager: fileManager)
            where fileManager.fileExists(atPath: url.path)
        {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  let client = Self.parseClient(fromInstalledArtifactData: data)
            else {
                continue
            }
            return client
        }
        return nil
    }

    static func candidateOAuthClientArtifactURLs(
        applicationRoots: [URL]? = nil,
        fileManager: FileManager = .default) -> [URL]
    {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        let applicationRoots = applicationRoots ?? roots
        let appBundleURLs = self.candidateAntigravityAppBundleURLs(
            applicationRoots: applicationRoots,
            fileManager: fileManager)
        let relativePaths = [
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_x64",
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos",
            "Contents/Resources/app/out/main.js",
            "Contents/Resources/bin/language_server",
            "Contents/Resources/bin/language_server_macos",
            // Gemini.app is a single native binary with no Electron artifacts.
            "Contents/MacOS/Gemini",
        ]
        return appBundleURLs.flatMap { bundleURL in
            relativePaths.map { bundleURL.appendingPathComponent($0) }
        }
    }

    private static func candidateAntigravityAppBundleURLs(
        applicationRoots: [URL],
        fileManager: FileManager) -> [URL]
    {
        var urls: [URL] = []

        for root in applicationRoots {
            urls.append(root.appendingPathComponent("Antigravity.app", isDirectory: true))

            // "Gemini.app" is a generic name, so unlike "Antigravity.app" it is
            // only accepted when the bundle identifier confirms the renamed app.
            let geminiURL = root.appendingPathComponent("Gemini.app", isDirectory: true)
            if self.isAntigravityAppBundle(geminiURL) {
                urls.append(geminiURL)
            }

            let appURLs = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for appURL in appURLs where appURL.pathExtension == "app" {
                guard self.isAntigravityAppBundle(appURL) else { continue }
                urls.append(appURL)
            }
        }

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func isAntigravityAppBundle(_ url: URL) -> Bool {
        switch Bundle(url: url)?.bundleIdentifier {
        case "com.google.antigravity", "com.google.antigravity-ide", "com.google.GeminiMacOS":
            true
        default:
            false
        }
    }

    static func parseClient(fromInstalledArtifactData artifact: Data) -> AntigravityOAuthClient? {
        let data = artifact.startIndex == 0 ? artifact : Data(artifact)
        if let content = String(data: data, encoding: .utf8),
           let client = self.parseClient(fromInstalledArtifactText: content)
        {
            return client
        }
        return self.binaryClient(in: data) ?? self.unambiguousClient(in: data)
    }

    static func parseClient(fromInstalledArtifactText content: String) -> AntigravityOAuthClient? {
        let marker = "vs/platform/cloudCode/common/oauthClient.js"
        let start = content.range(of: marker)?.lowerBound ?? content.startIndex
        let end = content.index(start, offsetBy: 4000, limitedBy: content.endIndex) ?? content.endIndex
        return self.unambiguousClient(in: Data(content[start..<end].utf8))
    }

    /// Older artifacts with exactly one identity need no instruction decoding. Multiple identities require a record.
    private static func unambiguousClient(in data: Data) -> AntigravityOAuthClient? {
        func value(marker: String, pattern: String, trailing: Int) -> String? {
            var search = data.startIndex..<data.endIndex
            var values = Set<String>()
            while let match = data.range(of: Data(marker.utf8), in: search) {
                search = match.upperBound..<data.endIndex
                var start = match.lowerBound
                let end = match.upperBound + trailing
                guard end <= data.endIndex else { continue }
                if trailing == 0 {
                    while start > max(data.startIndex, match.lowerBound - 256),
                          Self.isOAuthClientIDPrefixByte(data[start - 1])
                    {
                        start -= 1
                    }
                }
                guard let text = String(data: data[start..<end], encoding: .ascii),
                      let range = text.range(of: pattern, options: .regularExpression) else { continue }
                values.insert(String(text[range]))
                if values.count > 1 { return nil }
            }
            return values.first
        }
        guard let id = value(
            marker: ".apps.googleusercontent.com",
            pattern: #"[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#,
            trailing: 0),
            let secret = value(marker: "GOCSPX-", pattern: #"^GOCSPX-[A-Za-z0-9_-]{28}$"#, trailing: 28)
        else { return nil }
        return AntigravityOAuthClient(clientID: id, clientSecret: secret)
    }

    private static func isOAuthClientIDPrefixByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 45
            || byte == 95
    }

    /// Reads adjacent ClientID/ClientSecret Go string fields, never string-pool ordering.
    private static func binaryClient(in data: Data) -> AntigravityOAuthClient? {
        func word(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
        }
        guard data.count >= 32, word(0) == 0xFEED_FACF,
              [0x0100_000C, 0x0100_0007].contains(word(4)),
              Int(word(20)) <= data.count - 32 else { return nil }
        let commandsEnd = 32 + Int(word(20))
        var command = 32
        for _ in 0..<min(word(16), 4096) {
            guard command <= commandsEnd - 8 else { return nil }
            let size = Int(word(command + 4))
            guard size >= 8, size <= commandsEnd - command else { return nil }
            defer { command += size }
            guard word(command) == 0x19, size >= 72,
                  data[command + 8..<command + 24].starts(with: Data("__TEXT\0".utf8)),
                  word(command + 24) & 4095 == 0,
                  word(command + 40) == 0, word(command + 44) == 0,
                  word(command + 52) == 0,
                  Int(word(command + 48)) <= data.count else { continue }
            let textEnd = Int(word(command + 48))
            let sections = Int(word(command + 64))
            guard sections <= (size - 72) / 80 else { return nil }
            for index in 0..<sections {
                let section = command + 72 + index * 80
                guard data[section..<section + 16].starts(with: Data("__text\0".utf8)),
                      word(section + 44) == 0 else { continue }
                let start = Int(word(section + 48))
                let length = Int(word(section + 40))
                guard start >= commandsEnd, start <= textEnd, length <= textEnd - start else { return nil }
                let intel = word(4) == 0x0100_0007
                let marker = Data(intel ? [0x48, 0xC7, 0x40, 0x08] : [0x01, 0x08, 0x00, 0xA9])
                var range = start..<(start + length)
                while let match = data.range(of: marker, in: range) {
                    range = match.upperBound..<range.upperBound
                    let record = match.lowerBound - (intel ? 0 : 12)
                    guard record >= start, record <= start + length - (intel ? 37 : 32) else { continue }
                    /// __TEXT has an aligned VM base and file offset 0,
                    /// so PC-relative addresses map to file offsets.
                    func reference(_ offset: Int) -> (Int, Int)? {
                        if intel {
                            guard word(offset) & 0x00FF_FFFF == 0x000D_8D48 else { return nil }
                            return (offset + 7 + Int(Int32(bitPattern: word(offset + 3))), 0)
                        }
                        let page = word(offset)
                        let add = word(offset + 4)
                        let count = word(offset + 8)
                        guard offset % 4 == 0, page & 0x9F00_001F == 0x9000_0001,
                              add & 0xFFC0_03FF == 0x9100_0021,
                              count & 0xFFE0_001F == 0xD280_0002 else { return nil }
                        let immediate = ((page >> 5) & 0x7FFFF) << 2 | ((page >> 29) & 3)
                        let pages = Int(Int32(bitPattern: immediate << 11) >> 11)
                        return (
                            (offset & ~4095) + pages * 4096 + Int((add >> 10) & 4095),
                            Int((count >> 5) & 0xFFFF))
                    }
                    let id: (Int, Int)
                    let secret: (Int, Int)
                    if intel {
                        guard let idRef = reference(record + 8), let secretRef = reference(record + 26),
                              data[record + 15..<record + 22] == Data([0x48, 0x89, 0x08, 0x48, 0xC7, 0x40, 0x18]),
                              word(record + 33) == 0x1048_8948 else { continue }
                        id = (idRef.0, Int(word(record + 4)))
                        secret = (secretRef.0, Int(word(record + 22)))
                    } else {
                        guard let idRef = reference(record), let secretRef = reference(record + 16),
                              word(record + 28) == 0xA901_0801 else { continue }
                        id = idRef
                        secret = secretRef
                    }
                    guard (30...256).contains(id.1), secret.1 == 35,
                          id.0 >= commandsEnd, id.0 <= textEnd - id.1,
                          secret.0 >= commandsEnd, secret.0 <= textEnd - secret.1,
                          let clientID = String(data: data[id.0..<id.0 + id.1], encoding: .ascii),
                          let clientSecret = String(data: data[secret.0..<secret.0 + secret.1], encoding: .ascii),
                          clientID.range(
                              of: #"^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#,
                              options: .regularExpression) != nil,
                          clientSecret.range(
                              of: #"^GOCSPX-[A-Za-z0-9_-]{28}$"#,
                              options: .regularExpression) != nil else { continue }
                    return AntigravityOAuthClient(clientID: clientID, clientSecret: clientSecret)
                }
            }
        }
        return nil
    }
}

public struct AntigravityOAuthCredentialsStore: @unchecked Sendable {
    public static let environmentCredentialsKey = "ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"
    private static let fileLock = NSLock()

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> AntigravityOAuthCredentials? {
        try Self.fileLock.withLock {
            try self.loadUnlocked()
        }
    }

    private func loadUnlocked() throws -> AntigravityOAuthCredentials? {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        let data = try Data(contentsOf: self.fileURL)
        return try JSONDecoder().decode(AntigravityOAuthCredentials.self, from: data)
    }

    public func save(_ credentials: AntigravityOAuthCredentials) throws {
        try Self.fileLock.withLock {
            let data = try JSONEncoder.antigravityCredentials.encode(credentials)
            try CredentialFileWriter.writePrivate(data, to: self.fileURL)
        }
    }

    public func deleteIfPresent() throws {
        try Self.fileLock.withLock {
            try self.deleteIfPresentUnlocked()
        }
    }

    public func deleteIfPresent(
        matching predicate: (AntigravityOAuthCredentials) -> Bool) throws
    {
        try Self.fileLock.withLock {
            guard let credentials = try self.loadUnlocked(), predicate(credentials) else { return }
            try self.deleteIfPresentUnlocked()
        }
    }

    private func deleteIfPresentUnlocked() throws {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return }
        try self.fileManager.removeItem(at: self.fileURL)
    }

    public static func defaultDirectoryURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".codexbar", isDirectory: true)
            .appendingPathComponent("antigravity", isDirectory: true)
    }

    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        self.defaultDirectoryURL(home: home)
            .appendingPathComponent("oauth_creds.json")
    }

    public static func tokenAccountValue(for credentials: AntigravityOAuthCredentials) throws -> String {
        let data = try JSONEncoder.antigravityCredentials.encode(credentials)
        guard let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return value
    }

    public static func credentials(fromTokenAccountValue value: String) -> AntigravityOAuthCredentials? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AntigravityOAuthCredentials.self, from: data)
    }
}

extension JSONEncoder {
    fileprivate static let antigravityCredentials: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension String {
    fileprivate var trimmedNonEmpty: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
