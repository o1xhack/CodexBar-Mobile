import Foundation
import Testing
@testable import CodexBarCore

struct ClinePassSettingsReaderTests {
    @Test(arguments: [
        (#"{"auth":{"accessToken":" fixture-access "}}"#, "workos:fixture-access", true),
        (#"{"auth":{"accessToken":"workos:fixture-access"}}"#, "workos:fixture-access", true),
        (#"{"apiKey":" fixture-key "}"#, "fixture-key", false),
        (#"{"auth":{"apiKey":"nested-key"}}"#, "nested-key", false),
        (#"{"apiKey":"old-key","auth":{"accessToken":"new-session"}}"#, "workos:new-session", true),
        (#"{"apiKey":"fixture-key","auth":{"accessToken":"  "}}"#, "fixture-key", false),
    ])
    func `file parsing preserves credential kind`(fixture: (String, String, Bool)) {
        let (settings, token, isOAuth) = fixture
        let data = Data("{\"providers\":{\"cline\":{\"settings\":\(settings)},\"unrelated\":false}}".utf8)
        #expect(ClinePassSettingsReader.parseCredential(data) == .init(token: token, isOAuth: isOAuth))
    }

    @Test(arguments: [
        "{bad",
        "[]",
        "{}",
        #"{"providers":{"cline":{"settings":{}}}}"#,
        #"{"providers":{"cline-pass":{"settings":{"auth":{"accessToken":"other"}}}}}"#,
        #"{"providers":{"cline":{"settings":{"auth":{"accessToken":123}}}}}"#
    ])
    func `invalid and unrelated sessions stay unavailable`(json: String) {
        #expect(ClinePassSettingsReader.parseCredential(Data(json.utf8)) == nil)
    }

    @Test
    func `paths follow the Cline overrides and injected home`() {
        let home = URL(fileURLWithPath: "/synthetic/home")
        let cases: [([String: String], String)] = [
            ([:], "/synthetic/home/.cline/data/settings/providers.json"),
            (["HOME": "/synthetic/other"], "/synthetic/other/.cline/data/settings/providers.json"),
            (["CLINE_DIR": "~/cline"], "/synthetic/home/cline/data/settings/providers.json"),
            (["CLINE_DATA_DIR": "/data", "CLINE_DIR": "/unused"], "/data/settings/providers.json"),
            (
                ["CLINE_PROVIDER_SETTINGS_PATH": "~/session.json", "CLINE_DATA_DIR": "/unused"],
                "/synthetic/home/session.json"),
        ]
        for (environment, expected) in cases {
            #expect(ClinePassSettingsReader.providersFileURL(environment: environment, homeDirectory: home).path ==
                expected)
        }
    }

    @Test
    func `missing file stays unavailable and explicit aliases keep precedence`() {
        let environment = ["HOME": "/synthetic/missing-cline-home"]
        let credentials = ClinePassProviderDescriptor.descriptor.credentials
        #expect(credentials?.resolveToken(environment: environment) == nil)
        #expect(ClinePassSettingsReader.fileCredential(environment: [:]) == nil)
        #expect(credentials?.resolveToken(environment: environment.merging([
            "CLINE_API_KEY": " primary ", "CLINEPASS_API_KEY": "alternate",
        ]) { _, new in new })?.token == "primary")
        #expect(credentials?.resolveToken(environment: environment.merging([
            "CLINE_API_KEY": " ", "CLINEPASS_API_KEY": " alternate ",
        ]) { _, new in new })?.token == "alternate")
    }

    @Test
    func `API source does not require a configured key when file sessions are supported`() {
        let config = CodexBarConfig(providers: [ProviderConfig(id: .clinepass, source: .api)])
        #expect(!CodexBarConfigValidator.validate(config).contains { $0.code == "api_key_missing" })
    }

    @Test
    func `descriptor resolves the existing Cline browser session without persisting it`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("providers.json")
        let content = #"{"providers":{"cline":{"settings":{"auth":{"accessToken":"fixture-access"}}}}}"#
        try content.write(to: file, atomically: true, encoding: .utf8)
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .clinepass)
        let resolution = descriptor.credentials?.resolveToken(
            environment: ["HOME": directory.path], authFileURL: file)
        #expect(resolution?.token == "workos:fixture-access")
        #expect(resolution?.source == .authFile)
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["providers.json"])
    }

    @Test(arguments: [true, false])
    func `file credentials reach plugin auth and diagnostics without changing settings`(oauth: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("providers.json")
        let content = oauth
            ? #"{"providers":{"cline":{"settings":{"auth":{"accessToken":"fixture-access"}}}}}"#
            : #"{"providers":{"cline":{"settings":{"apiKey":"fixture-key"}}}}"#
        try content.write(to: file, atomically: true, encoding: .utf8)
        let environment = ["CLINE_PROVIDER_SETTINGS_PATH": file.path, "HOME": directory.path]
        for override in [false, true] {
            let env = override ? environment.merging(["CLINE_API_KEY": "override-key"]) { _, new in new } : environment
            let expected = override ? "override-key" : (oauth ? "workos:fixture-access" : "fixture-key")
            let strategy = ClinePassProviderDescriptor.makeStrategy(transport: ProviderHTTPTransportHandler { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expected)")
                #expect(request.url?.absoluteString == "https://api.cline.bot/api/v1/users/me/plan/usage-limits")
                let response = try #require(HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (
                    Data(#"{"success":true,"data":{"limits":[{"type":"weekly","percentUsed":25}]}}"#.utf8),
                    response)
            })
            let context = ProviderCutoverTestSupport.context(environment: env)
            #expect(await strategy.isAvailable(context))
            let result = try await strategy.fetch(context)
            #expect(result.usage.secondary?.usedPercent == 25)
            #expect(result.usage.identity?.loginMethod == (oauth && !override ? "Browser" : "API key"))
            let summary = ClinePassProviderDescriptor.descriptor.credentials?.diagnosticAuthSummary(
                account: nil, config: nil, environment: env, settings: nil)
            #expect(summary?.modes == [oauth && !override ? "oauth" : "api"])
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["providers.json"])
    }
}
