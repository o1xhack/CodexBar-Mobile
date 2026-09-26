import Foundation

// MARK: - Credentials

public struct ZedCredentials: Equatable, Sendable {
    public let userID: String
    public let accessToken: String

    public init(userID: String, accessToken: String) {
        self.userID = userID
        self.accessToken = accessToken
    }

    public var authorizationHeader: String {
        "\(self.userID) \(self.accessToken)"
    }
}

// MARK: - Errors

public enum ZedStatusProbeError: LocalizedError, Sendable, Equatable {
    case notSupported
    case notSignedIn
    case keychainUnavailable
    case invalidServerURL(String)
    case untrustedServerConfiguration

    public var errorDescription: String? {
        switch self {
        case .notSupported:
            "Zed editor login requires macOS. Use a manual browser cookie for billing on other platforms."
        case .notSignedIn:
            "Not signed in to Zed. Sign in from the Zed editor app with GitHub."
        case .keychainUnavailable:
            "Could not read Zed credentials from the Keychain. Grant CodexBar Keychain access or sign in to Zed again."
        case let .invalidServerURL(value):
            "Zed server URL is invalid: \(value)"
        case .untrustedServerConfiguration:
            "Zed custom servers must use HTTPS and store credentials under the same server URL."
        }
    }
}

// MARK: - Settings

public struct ZedClientSettings: Sendable, Equatable {
    public let credentialsURL: String?
    public let serverURL: String?

    public init(credentialsURL: String?, serverURL: String?) {
        self.credentialsURL = credentialsURL
        self.serverURL = serverURL
    }

    public var keychainServiceURL: String {
        let trimmedCredentials = self.credentialsURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCredentials, !trimmedCredentials.isEmpty {
            return trimmedCredentials
        }
        let trimmedServer = self.serverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedServer, !trimmedServer.isEmpty {
            return trimmedServer
        }
        return ZedStatusProbe.defaultKeychainServiceURL
    }

    public var cloudAPIURL: URL? {
        let trimmedServer = self.serverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = if let trimmedServer, !trimmedServer.isEmpty {
            trimmedServer
        } else {
            ZedStatusProbe.defaultKeychainServiceURL
        }
        let isTrustedZedServer = server == "https://zed.dev" || server == "https://staging.zed.dev"
        let trimmedCredentials = self.credentialsURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isTrustedZedServer,
           let trimmedCredentials,
           !trimmedCredentials.isEmpty,
           trimmedCredentials != server
        {
            return nil
        }
        let cloudBase = switch server {
        case "https://zed.dev", "https://staging.zed.dev":
            "https://cloud.zed.dev"
        default:
            server
        }
        guard let baseURL = URL(string: cloudBase),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "https",
              baseURL.host != nil
        else {
            return nil
        }
        return baseURL.appendingPathComponent("client/users/me")
    }

    public static func load(from url: URL = ZedStatusProbe.defaultSettingsURL) -> ZedClientSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        struct Payload: Decodable {
            let credentialsURL: String?
            let serverURL: String?

            enum CodingKeys: String, CodingKey {
                case credentialsURL = "credentials_url"
                case serverURL = "server_url"
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return ZedClientSettings(
            credentialsURL: payload.credentialsURL,
            serverURL: payload.serverURL)
    }
}

// MARK: - Credentials

public protocol ZedCredentialsReading: Sendable {
    func loadCredentials(serviceURL: String) throws -> ZedCredentials?
}

#if os(macOS)
import Security

public struct ZedKeychainCredentialsReader: ZedCredentialsReading, Sendable {
    public init() {}

    public func loadCredentials(serviceURL: String) throws -> ZedCredentials? {
        guard !KeychainAccessGate.isDisabled else {
            throw ZedStatusProbeError.keychainUnavailable
        }
        if let credentials = try self.loadPasswordCredentials(
            secClass: kSecClassInternetPassword, attribute: kSecAttrServer, value: serviceURL)
        {
            return credentials
        }
        return try self.loadPasswordCredentials(
            secClass: kSecClassGenericPassword, attribute: kSecAttrService, value: serviceURL)
    }

    private func loadPasswordCredentials(
        secClass: CFString,
        attribute: CFString,
        value: String) throws -> ZedCredentials?
    {
        var query: [String: Any] = [
            kSecClass as String: secClass,
            attribute as String: value,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        KeychainNoUIQuery.apply(to: &query)
        return try self.credentials(from: query)
    }

    private func credentials(from query: [String: Any]) throws -> ZedCredentials? {
        var result: AnyObject?
        let status = KeychainSecurity.copyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return nil
        default:
            throw ZedStatusProbeError.keychainUnavailable
        }

        guard let item = result as? [String: Any],
              let account = item[kSecAttrAccount as String] as? String,
              !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        guard let tokenData = item[kSecValueData as String] as? Data,
              let accessToken = String(data: tokenData, encoding: .utf8),
              !accessToken.isEmpty
        else {
            return nil
        }

        return ZedCredentials(userID: account, accessToken: accessToken)
    }
}
#else
public struct ZedKeychainCredentialsReader: ZedCredentialsReading, Sendable {
    public init() {}

    public func loadCredentials(serviceURL _: String) throws -> ZedCredentials? {
        throw ZedStatusProbeError.notSupported
    }
}
#endif

// MARK: - Probe

public struct ZedStatusProbe: Sendable {
    public static let defaultKeychainServiceURL = "https://zed.dev"
    public static let cloudAPIURL = URL(string: "https://cloud.zed.dev/client/users/me")!

    public static var defaultSettingsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config/zed/settings.json")
    }

    private let credentialsReader: any ZedCredentialsReading
    private let transport: any ProviderHTTPTransport
    private let settingsLoader: @Sendable () -> ZedClientSettings?

    public init(
        credentialsReader: any ZedCredentialsReading = ZedKeychainCredentialsReader(),
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        settingsLoader: @escaping @Sendable () -> ZedClientSettings? = { ZedClientSettings.load() })
    {
        self.credentialsReader = credentialsReader
        self.transport = transport
        self.settingsLoader = settingsLoader
    }

    public func fetch() async throws -> UsageSnapshot {
        let settings = self.settingsLoader()
        let serviceURL = settings?.keychainServiceURL ?? Self.defaultKeychainServiceURL
        let cloudAPIURL: URL
        if let settings {
            guard let configuredURL = settings.cloudAPIURL else {
                let serverURL = settings.serverURL ?? ""
                guard URL(string: serverURL)?.scheme?.lowercased() == "https" else {
                    throw ZedStatusProbeError.invalidServerURL(serverURL)
                }
                throw ZedStatusProbeError.untrustedServerConfiguration
            }
            cloudAPIURL = configuredURL
        } else {
            cloudAPIURL = Self.cloudAPIURL
        }
        guard let credentials = try self.credentialsReader.loadCredentials(serviceURL: serviceURL) else {
            throw ZedStatusProbeError.notSignedIn
        }

        let runtime = try ProviderPluginRuntime(bundledPlugin: "zed", transport: self.transport)
        return try await runtime.fetchUsage(
            settings: ["API_URL": cloudAPIURL.absoluteString],
            secrets: ["EDITOR_AUTH": credentials.authorizationHeader],
            sourceMode: .api,
            cookieSource: .off)
    }
}
