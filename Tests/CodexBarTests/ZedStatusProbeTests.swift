import Foundation
import Testing
@testable import CodexBarCore

struct ZedStatusProbeTests {
    private struct StubCredentialsReader: ZedCredentialsReading {
        let credentials: ZedCredentials?

        func loadCredentials(serviceURL _: String) throws -> ZedCredentials? {
            self.credentials
        }
    }

    private static let subscriptionPeriod = """
    "subscription_period": {
      "started_at": "2026-05-13T00:00:00.000Z",
      "ended_at": "2026-06-13T00:00:00.000Z"
    }
    """

    static func fixture(plan: String, used: Int, limit: String, overdue: Bool = false) -> Data {
        Data(
            """
            {
              "user": {
                "id": 4242,
                "github_login": "octocat",
                "name": "The Octocat"
              },
              "feature_flags": [],
              "plan": {
                "plan_v3": "\(plan)",
                \(self.subscriptionPeriod),
                "usage": {
                  "edit_predictions": {
                    "used": \(used),
                    "limit": \(limit)
                  }
                },
                "has_overdue_invoices": \(overdue)
              }
            }
            """.utf8)
    }

    private static func httpResponse(data: Data, statusCode: Int) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://cloud.zed.dev/client/users/me")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil)!
        return (data, response)
    }

    @Test(arguments: ["zed_free", "zed_pro", "zed_pro_trial", "zed_student", "zed_business"])
    func `editor plans retain names and unlimited predictions`(plan: String) async throws {
        let runtime = try ProviderPluginRuntime(bundledPlugin: "zed", transport: ProviderHTTPTransportStub { _ in
            Self.httpResponse(data: Self.fixture(plan: plan, used: 3, limit: "\"unlimited\""), statusCode: 200)
        })
        let snapshot = try await runtime.fetchUsage(
            settings: ["API_URL": ZedStatusProbe.cloudAPIURL.absoluteString],
            secrets: ["EDITOR_AUTH": "4242 fixture-token"],
            sourceMode: .api)
        let label = plan.split(separator: "_").map(\.capitalized).joined(separator: " ")
        #expect(snapshot.identity?.loginMethod == label)
        #expect(snapshot.primary?.resetDescription == "Unlimited")
        #expect(snapshot.primary?.usedPercent == 0)
        #expect(snapshot.extraRateWindows == nil)
    }

    @Test
    func `reads credentials url from settings`() {
        let settings = ZedClientSettings(
            credentialsURL: "https://preview.zed.dev",
            serverURL: "https://zed.dev")
        #expect(settings.keychainServiceURL == "https://preview.zed.dev")

        let fallback = ZedClientSettings(credentialsURL: nil, serverURL: "https://custom.zed.dev")
        #expect(fallback.keychainServiceURL == "https://custom.zed.dev")

        let defaultSettings = ZedClientSettings(credentialsURL: nil, serverURL: nil)
        #expect(defaultSettings.keychainServiceURL == ZedStatusProbe.defaultKeychainServiceURL)
    }

    @Test
    func `uses documented zed settings path`() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/zed/settings.json")
        #expect(ZedStatusProbe.defaultSettingsURL == expected)
    }

    @Test
    func `loads client settings from json`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-ZedSettings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settingsURL = directory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "credentials_url": "zed-preview-key",
              "server_url": "https://staging.zed.dev"
            }
            """.utf8)
            .write(to: settingsURL)

        let settings = try #require(ZedClientSettings.load(from: settingsURL))
        #expect(settings.credentialsURL == "zed-preview-key")
        #expect(settings.serverURL == "https://staging.zed.dev")
    }

    @Test
    func `maps server url independently from keychain identifier`() {
        let production = ZedClientSettings(credentialsURL: "zed-preview-key", serverURL: "https://zed.dev")
        let staging = ZedClientSettings(credentialsURL: nil, serverURL: "https://staging.zed.dev")
        let localhost = ZedClientSettings(credentialsURL: nil, serverURL: "http://localhost:3000")
        let custom = ZedClientSettings(credentialsURL: nil, serverURL: "https://zed.example.com")
        let untrustedOverride = ZedClientSettings(
            credentialsURL: "https://zed.dev",
            serverURL: "https://zed.example.com")
        let invalid = ZedClientSettings(credentialsURL: nil, serverURL: "file:///tmp/zed")

        #expect(production.keychainServiceURL == "zed-preview-key")
        #expect(production.cloudAPIURL?.absoluteString == "https://cloud.zed.dev/client/users/me")
        #expect(staging.cloudAPIURL?.absoluteString == "https://cloud.zed.dev/client/users/me")
        #expect(localhost.cloudAPIURL == nil)
        #expect(custom.cloudAPIURL?.absoluteString == "https://zed.example.com/client/users/me")
        #expect(untrustedOverride.cloudAPIURL == nil)
        #expect(invalid.cloudAPIURL == nil)
    }

    @Test
    func `fetch uses authorization header from keychain credentials`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.url?.absoluteString == "https://cloud.zed.dev/client/users/me")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "4242 test-token")
            return Self.httpResponse(
                data: Self.fixture(plan: "zed_pro", used: 0, limit: "\"unlimited\""),
                statusCode: 200)
        }

        let probe = ZedStatusProbe(
            credentialsReader: StubCredentialsReader(
                credentials: ZedCredentials(userID: "4242", accessToken: "test-token")),
            transport: transport,
            settingsLoader: { ZedClientSettings(credentialsURL: nil, serverURL: nil) })

        let snapshot = try await probe.fetch()
        #expect(snapshot.identity?.loginMethod == "Zed Pro")
    }

    @Test
    func `fetch sends credentials only to configured server`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            #expect(request.url?.absoluteString == "https://zed.example.com/client/users/me")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "4242 custom-token")
            return Self.httpResponse(
                data: Self.fixture(plan: "zed_pro", used: 0, limit: "\"unlimited\""),
                statusCode: 200)
        }
        let probe = ZedStatusProbe(
            credentialsReader: StubCredentialsReader(
                credentials: ZedCredentials(userID: "4242", accessToken: "custom-token")),
            transport: transport,
            settingsLoader: {
                ZedClientSettings(
                    credentialsURL: "https://zed.example.com",
                    serverURL: "https://zed.example.com")
            })

        _ = try await probe.fetch()
    }

    @Test
    func `fetch rejects invalid server before reading credentials`() async {
        let probe = ZedStatusProbe(
            credentialsReader: StubCredentialsReader(
                credentials: ZedCredentials(userID: "4242", accessToken: "must-not-send")),
            transport: ProviderHTTPTransportStub { _ in
                Issue.record("Should not send credentials to an invalid server URL")
                return Self.httpResponse(data: Data(), statusCode: 500)
            },
            settingsLoader: {
                ZedClientSettings(credentialsURL: "custom-keychain-id", serverURL: "file:///tmp/zed")
            })

        await #expect(throws: ZedStatusProbeError.invalidServerURL("file:///tmp/zed")) {
            _ = try await probe.fetch()
        }
    }

    @Test
    func `fetch rejects cross-origin credential override`() async {
        let probe = ZedStatusProbe(
            credentialsReader: StubCredentialsReader(
                credentials: ZedCredentials(userID: "4242", accessToken: "must-not-send")),
            transport: ProviderHTTPTransportStub { _ in
                Issue.record("Should not send credentials to an untrusted custom server")
                return Self.httpResponse(data: Data(), statusCode: 500)
            },
            settingsLoader: {
                ZedClientSettings(
                    credentialsURL: "https://zed.dev",
                    serverURL: "https://attacker.example.com")
            })

        await #expect(throws: ZedStatusProbeError.untrustedServerConfiguration) {
            _ = try await probe.fetch()
        }
    }

    @Test
    func `fetch surfaces not signed in when keychain is empty`() async {
        let probe = ZedStatusProbe(
            credentialsReader: StubCredentialsReader(credentials: nil),
            transport: ProviderHTTPTransportStub { _ in
                Issue.record("Should not call cloud API without credentials")
                return Self.httpResponse(data: Data(), statusCode: 500)
            },
            settingsLoader: { nil })

        await #expect(throws: ZedStatusProbeError.notSignedIn) {
            _ = try await probe.fetch()
        }
    }

    @Test
    func `fetch surfaces unauthorized responses`() async {
        let probe = ZedStatusProbe(
            credentialsReader: StubCredentialsReader(
                credentials: ZedCredentials(userID: "1", accessToken: "bad")),
            transport: ProviderHTTPTransportStub { _ in
                Self.httpResponse(data: Data("{}".utf8), statusCode: 401)
            },
            settingsLoader: { nil })

        await ZedPluginTests.expectFailure(.authenticationExpired) {
            try await probe.fetch()
        }
    }

    @Test
    func `fetch preserves transport cancellation`() async {
        let probe = ZedStatusProbe(
            credentialsReader: StubCredentialsReader(
                credentials: ZedCredentials(userID: "1", accessToken: "cancelled")),
            transport: ProviderHTTPTransportStub { _ in
                throw URLError(.cancelled)
            },
            settingsLoader: { nil })

        await #expect(throws: CancellationError.self) {
            _ = try await probe.fetch()
        }
    }

    #if os(macOS)
    @Test
    func `keychain reader fails closed at the foreign item boundary`() {
        _ = KeychainAccessGate.withTaskOverrideForTesting(true) {
            #expect(throws: ZedStatusProbeError.keychainUnavailable) {
                try ZedKeychainCredentialsReader().loadCredentials(serviceURL: "https://zed.dev")
            }
        }
    }
    #endif
}
