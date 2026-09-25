import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct GitKrakenPluginTests {
    #if canImport(JavaScriptCore)
    private static let engines: [ProviderPluginEngineKind] = [.quickJS, .javaScriptCore]
    #else
    private static let engines: [ProviderPluginEngineKind] = [.quickJS]
    #endif
    private static let reset = "2026-09-27T00:00:00Z"
    private static let personal = #"""
    {"used":12500,"limit":400000,"resetsOn":"2026-09-27T00:00:00Z"}
    """#

    @Test(arguments: Self.engines)
    func `weekly personal and shared pool match the golden without double counting`(
        engine: ProviderPluginEngineKind) async throws
    {
        let usage = try await Self.fetch(engine, payload: #"""
        {"used":12500,"limit":400000,"resetsOn":"2026-09-27T00:00:00Z",
        "organization":{"used":20000,"limit":100000},"sharedUsed":5000}
        """#, organization: "org-fixture")
        #expect(usage.primary?.usedPercent == 3.125)
        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.primary?.windowMinutes == 10080)
        #expect(usage.primary?.resetsAt == ISO8601DateFormatter().date(from: Self.reset))
        #expect(usage.secondary?.resetsAt == usage.primary?.resetsAt)
        #expect(usage.identity?.providerID?.rawValue == "gitkraken")
        #expect(usage.identity?.accountEmail == nil)
        #expect(usage.identity?.accountOrganization == nil)
        #expect(usage.details.first?.rows.map(\.value) == [
            "12,500 / 400,000 credits used", "20,000 / 100,000 credits used", "5,000 credits", "15,000 credits",
        ])
        #expect(usage.dataConfidence == .exact)
    }

    @Test(arguments: [0, -1], Self.engines)
    func `zero and unlimited allowance retain counts without invented percentages`(
        limit: Int, engine: ProviderPluginEngineKind) async throws
    {
        let usage = try await Self.fetch(engine, payload: Self.personal.replacingOccurrences(
            of: "400000", with: String(limit)))
        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.details.first?.rows.first?.value ==
            "12,500 credits used · \(limit == 0 ? "No allowance" : "Unlimited")")
    }

    @Test(arguments: ["null", "{}", Self.personal.replacingOccurrences(of: "12500", with: "-1")], Self.engines)
    func `invalid optional organization preserves personal usage`(
        organization: String, engine: ProviderPluginEngineKind) async throws
    {
        let payload = String(Self.personal.dropLast()) + ",\"organization\":\(organization),\"sharedUsed\":1}"
        let usage = try await Self.fetch(engine, payload: payload)
        #expect(usage.primary?.usedPercent == 3.125)
        #expect(usage.secondary == nil)
        #expect(usage.details.first?.rows.count == 1)
    }

    @Test(arguments: ["null", "true", "\"12\"", "-1", "201"], Self.engines)
    func `invalid shared slice does not corrupt the organization total`(
        shared: String, engine: ProviderPluginEngineKind) async throws
    {
        let payload = String(Self.personal.dropLast()) +
            ",\"organization\":{\"used\":200,\"limit\":1000},\"sharedUsed\":\(shared)}"
        let usage = try await Self.fetch(engine, payload: payload)
        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.details.first?.rows.count == 2)
    }

    @Test(arguments: [
        "{}", "null", "[]", Self.personal.replacingOccurrences(of: "12500", with: "true"),
        Self.personal.replacingOccurrences(of: "12500", with: "-1"), Self.personal.replacingOccurrences(
            of: "12500",
            with: "1e400"),
        Self.personal.replacingOccurrences(of: "400000", with: "-0.5"),
        "{\"used\":1,\"limit\":100,\"resetsOn\":\"2026-09-27\"}",
    ], Self.engines)
    func `malformed primary data fails closed`(payload: String, engine: ProviderPluginEngineKind) async {
        await Self.expectFailure(.parseFailure) { try await Self.fetch(engine, payload: payload) }
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired), (403, .permissionDenied),
        (429, .rateLimited), (503, .providerUnavailable), (404, .apiFailure),
    ], Self.engines)
    func `HTTP failures are classified before decoding private bodies`(
        failure: (Int, ProviderFetchClassifiedError.Kind), engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(failure.1) {
            try await Self.fetch(engine, body: "private-response-fixture", statusCode: failure.0)
        }
    }

    @Test(arguments: Self.engines)
    func `malformed JSON and error envelopes cannot publish data`(engine: ProviderPluginEngineKind) async {
        for body in ["private-response-fixture", "{\"data\":\(Self.personal),\"error\":\"private-response-fixture\"}"] {
            await Self.expectFailure(.parseFailure) { try await Self.fetch(engine, body: body) }
        }
    }

    @Test
    func `descriptor projects config credentials and scope for the API only provider`() throws {
        let descriptor = GitKrakenProviderDescriptor.descriptor
        let credentials = try #require(descriptor.credentials)
        let config = ProviderConfig(id: .gitkraken, apiKey: " fixture-token ", workspaceID: " org-fixture ")
        let env = credentials.applyConfig(base: ["UNCHANGED": "yes"], config: config)
        #expect(env == ["GITKRAKEN_API_TOKEN": "fixture-token", "GITKRAKEN_ORG_ID": "org-fixture", "UNCHANGED": "yes"])
        #expect(credentials.resolveToken(environment: env)?.token == "fixture-token")
        #expect(credentials.resolveToken(environment: [:]) == nil)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .api])
        #expect(descriptor.cli.aliases == ["gk"])
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(!descriptor.metadata.widgetSelectable)
        #expect(!CodexBarConfigValidator.validate(CodexBarConfig(providers: [config]))
            .contains { $0.code == "workspace_unused" || $0.code == "api_key_unused" })
    }

    private static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind,
        operation: () async throws -> UsageSnapshot) async
    {
        do {
            _ = try await operation()
            Issue.record("Expected classified failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == kind)
            #expect(!error.message.contains("private-response-fixture"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func fetch(
        _ engine: ProviderPluginEngineKind, payload: String = Self.personal,
        body: String? = nil, statusCode: Int = 200, organization: String = "") async throws -> UsageSnapshot
    {
        let transport = ProviderHTTPTransportHandler { request in
            #expect(request.url?.absoluteString == "https://api.gitkraken.dev/v1/ai-tasks/usage")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.value(forHTTPHeaderField: "gk-org-id") == (organization.isEmpty ? nil : organization))
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Client-Name") == "CodexBar")
            let response = try #require(HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Retry-After": "1"]))
            return (Data((body ?? "{\"data\":\(payload),\"error\":null}").utf8), response)
        }
        let url = try #require(CodexBarCoreResources.bundle?.url(forResource: "gitkraken", withExtension: "js"))
        let runtime = try ProviderPluginRuntime(
            source: String(contentsOf: url, encoding: .utf8), transport: transport, engine: engine)
        return try await runtime.fetchUsage(
            settings: ["GITKRAKEN_ORG_ID": organization], secrets: ["GITKRAKEN_API_TOKEN": "fixture-token"])
    }
}
