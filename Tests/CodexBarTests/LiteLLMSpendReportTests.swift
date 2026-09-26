import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct LiteLLMSpendReportTests {
    /// Shape reported in #3834; all identifiers and amounts are synthetic.
    private static let report = #"""
    [{"api_key":"synthetic-key-identifier","total_cost":1.25,
      "total_input_tokens":1000,"total_output_tokens":100,
      "model_details":[{"model":"example-model","total_cost":1.25,
                        "total_input_tokens":1000,"total_output_tokens":100}]},
     {"api_key":"another-synthetic-identifier","total_cost":2.5}]
    """#
    private static let now = Date(timeIntervalSince1970: 1_790_006_400) // 2026-09-21 UTC

    private func fetch(
        engine: ProviderPluginEngineKind,
        managementStatus: Int = 403,
        keyStatus: Int = 200,
        userStatus: Int = 200,
        body: String = Self.report,
        now: Date = Self.now) async throws -> (UsageSnapshot, [String])
    {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
            #expect(url.host == "proxy.example.com")
            let statusCode: Int
            switch url.path {
            case "/proxy/key/info":
                #expect(url.query == nil)
                statusCode = managementStatus
            case "/proxy/key/spend/report", "/proxy/user/spend/report":
                let end = now.ISO8601Format().prefix(10)
                #expect(url.query == "start_date=\(end.prefix(7))-01&end_date=\(end)")
                statusCode = url.path.contains("/key/") ? keyStatus : userStatus
            default:
                Issue.record("Unexpected request: \(url.path)")
                statusCode = 500
            }
            return (Data(body.utf8), HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!)
        }
        let snapshot = try await BundledPluginTestSupport.runtime("litellm", engine: engine, transport: transport)
            .fetchUsage(
                settings: ["LITELLM_BASE_URL": "https://proxy.example.com/proxy/v1/"],
                secrets: ["LITELLM_API_KEY": "fixture-key"],
                now: now)
        return await (snapshot, transport.requests().compactMap { $0.url?.path })
    }

    @Test(arguments: BundledPluginTestSupport.engines, [401, 403, 404])
    func `management denial falls back to explicitly scoped key spend`(
        engine: ProviderPluginEngineKind, status: Int) async throws
    {
        let (snapshot, paths) = try await self.fetch(engine: engine, managementStatus: status)
        #expect(paths == ["/proxy/key/info", "/proxy/key/spend/report"])
        #expect(snapshot.providerCost?.used == 3.75)
        #expect(snapshot.providerCost?.currencyCode == "USD")
        #expect(snapshot.providerCost?.period == "Key spend only (2026-09-01–2026-09-21 UTC)")
        #expect(snapshot.providerCost?.limit == 0) // Host sentinel for absent limits, never a quota window.
        #expect(snapshot.providerCost?.resetsAt == nil)
        #expect(snapshot.providerCost?.balance == nil)
        #expect(snapshot.primary == nil && snapshot.secondary == nil && snapshot.tertiary == nil)
        #expect(snapshot.identity == nil)
        #expect(snapshot.subscriptionExpiresAt == nil)
        let output = CLIRenderer.renderText(
            provider: .litellm,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(header: "LiteLLM", status: nil, useColor: false, resetStyle: .countdown),
            now: Self.now)
        #expect(output.contains("Key spend only (2026-09-01–2026-09-21 UTC)"))
        #expect(output.contains("$3.75"))
        #expect(!output.contains("Cost:"))
        #expect(!output.contains("synthetic-key-identifier") && !output.contains("Resets"))
    }

    @Test(arguments: BundledPluginTestSupport.engines, [401, 403, 404])
    func `unavailable key report falls back to explicitly scoped user spend`(
        engine: ProviderPluginEngineKind, status: Int) async throws
    {
        let (snapshot, paths) = try await self.fetch(engine: engine, keyStatus: status)
        #expect(paths == ["/proxy/key/info", "/proxy/key/spend/report", "/proxy/user/spend/report"])
        #expect(snapshot.providerCost?.used == 3.75)
        #expect(snapshot.providerCost?.period == "User spend only (2026-09-01–2026-09-21 UTC)")
        #expect(snapshot.identity == nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `zero reported spend is valid and month boundaries use UTC`(engine: ProviderPluginEngineKind) async throws {
        let now = try #require(ISO8601DateParser.parse("2027-01-01T00:00:01Z"))
        let (snapshot, _) = try await self.fetch(engine: engine, body: #"[{"total_cost":0}]"#, now: now)
        #expect(snapshot.providerCost?.used == 0)
        #expect(snapshot.providerCost?.period == "Key spend only (2027-01-01–2027-01-01 UTC)")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `invalid or empty reports never fabricate zero spend`(engine: ProviderPluginEngineKind) async throws {
        for body in [
            "[]",
            "{}",
            "null",
            "not json",
            "[null]",
            "[{}]",
            #"[{"total_cost":"1.25"}]"#,
            #"[{"total_cost":-1}]"#,
            #"[{"total_cost":1e309}]"#,
            #"[{"total_cost":1e308},{"total_cost":1e308}]"#,
        ] {
            do {
                _ = try await self.fetch(engine: engine, body: body)
                Issue.record("Expected malformed report failure")
            } catch let error as ProviderFetchClassifiedError {
                #expect(error.kind == .parseFailure)
            }
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `transport failure does not switch report scopes`(engine: ProviderPluginEngineKind) async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path == "/key/info" {
                return (Data(), HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!)
            }
            throw URLError(.notConnectedToInternet)
        }
        do {
            _ = try await BundledPluginTestSupport.runtime("litellm", engine: engine, transport: transport)
                .fetchUsage(
                    settings: ["LITELLM_BASE_URL": "https://proxy.example.com"],
                    secrets: ["LITELLM_API_KEY": "fixture-key"])
            Issue.record("Expected network failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .networkFailure)
        }
        let paths = await transport.requests().compactMap { $0.url?.path }
        #expect(paths == ["/key/info", "/key/spend/report"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `nonavailability failures remain visible without leaking report bodies`(
        engine: ProviderPluginEngineKind) async throws
    {
        for (status, kind) in [
            (429, ProviderFetchClassifiedError.Kind.rateLimited),
            (500, .providerUnavailable),
            (400, .apiFailure),
        ] {
            for management in [true, false] {
                do {
                    _ = try await self.fetch(
                        engine: engine,
                        managementStatus: management ? status : 403,
                        keyStatus: management ? 200 : status)
                    Issue.record("Expected failure for HTTP \(status)")
                } catch let error as ProviderFetchClassifiedError {
                    #expect(error.kind == kind)
                    if !management { #expect(!error.message.contains("synthetic-key-identifier")) }
                }
            }
        }
        for (status, kind) in [
            (401, ProviderFetchClassifiedError.Kind.authenticationExpired),
            (403, .permissionDenied),
            (404, .apiFailure),
        ] {
            do {
                _ = try await self.fetch(engine: engine, keyStatus: 404, userStatus: status)
                Issue.record("Expected unavailable report failure")
            } catch let error as ProviderFetchClassifiedError {
                #expect(error.kind == kind)
                #expect(!error.message.contains("synthetic-key-identifier"))
            }
        }
    }
}
