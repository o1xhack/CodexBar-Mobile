import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct APIBalancePluginTests {
    static let providers = ["vercel", "atlascloud"]

    @Test(arguments: Self.providers)
    func `API credentials are explicit and providers default off`(provider: String) throws {
        let id = try #require(UsageProvider(rawValue: provider))
        let descriptor = ProviderDescriptorRegistry.descriptor(for: id)
        let credentials = try #require(descriptor.credentials)
        let key = provider == "vercel" ? "AI_GATEWAY_API_KEY" : "ATLASCLOUD_API_KEY"
        #expect(credentials.resolveToken(environment: [key: "fixture-key"])?.token == "fixture-key")
        #expect(credentials.resolveToken(environment: [key: " \n"])?.token == nil)
        #expect(credentials.resolveToken(environment: ["OTHER_API_KEY": "fixture-key"])?.token == nil)
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(!descriptor.metadata.widgetSelectable)
    }

    static func fixture(_ provider: String, value: String = "95.50") -> String {
        provider == "vercel"
            ? #"{"balance":"\#(value)","total_used":"4.50"}"#
            : #"{"object":"balance","scope":"account","available":{"value":"\#(value)","currency":"usd"}}"#
    }

    @Test(arguments: Self.providers, BundledPluginTestSupport.engines)
    func `documented balances have no invented quota or billing period`(
        provider: String, engine: ProviderPluginEngineKind) async throws
    {
        let snapshot = try await Self.fetch(provider, engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.details.first?.rows.first?.value == "$95.50")
        #expect(snapshot.details.first?.rows.count == (provider == "vercel" ? 2 : 1))
        if provider == "vercel" {
            #expect(snapshot.details.first?.rows.last?.label == "Lifetime spend")
            #expect(snapshot.details.first?.rows.last?.value == "$4.50")
        }
        #expect(snapshot.identity?.providerID?.rawValue == provider)
        #expect(snapshot.dataConfidence == .exact)
    }

    @Test(arguments: Self.providers, BundledPluginTestSupport.engines)
    func `zero and negative balances are preserved`(provider: String, engine: ProviderPluginEngineKind) async throws {
        for (value, expected) in [("0.00", "$0.00"), ("-1.250000", "-$1.25")] {
            let snapshot = try await Self.fetch(provider, engine: engine, body: Self.fixture(provider, value: value))
            #expect(snapshot.details.first?.rows.first?.value == expected)
        }
    }

    @Test(arguments: Self.providers, BundledPluginTestSupport.engines)
    func `malformed payloads fail closed without echoing response data`(
        provider: String, engine: ProviderPluginEngineKind) async throws
    {
        let invalid = ["", " ", "NaN", "1e999", "0x10", "private-response"].map {
            Self.fixture(provider, value: $0)
        } + ["private-response", "{}", "null", #"{"balance":12,"total_used":"0"}"#]
        for body in invalid {
            do {
                _ = try await Self.fetch(provider, engine: engine, body: body)
                Issue.record("Expected parse failure")
            } catch let error as ProviderFetchClassifiedError {
                #expect(error.kind == .parseFailure)
                #expect(!error.message.contains("private-response"))
            }
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `currency scope and lifetime spend are validated`(engine: ProviderPluginEngineKind) async throws {
        for (provider, body) in [
            ("atlascloud", Self.fixture("atlascloud").replacingOccurrences(of: "usd", with: "eur")),
            ("atlascloud", Self.fixture("atlascloud").replacingOccurrences(of: "account", with: "key")),
            ("vercel", #"{"balance":"1.00","total_used":"-1.00"}"#),
            ("vercel", #"{"balance":"1.00"}"#),
        ] {
            await #expect(throws: ProviderFetchClassifiedError.self) {
                try await Self.fetch(provider, engine: engine, body: body)
            }
        }
    }

    @Test(arguments: Self.providers, BundledPluginTestSupport.engines)
    func `HTTP failures expose status without response bodies`(
        provider: String, engine: ProviderPluginEngineKind) async throws
    {
        for (code, kind) in [
            (401, ProviderFetchClassifiedError.Kind.authenticationExpired), (403, .permissionDenied),
            (429, .rateLimited), (503, .providerUnavailable), (400, .apiFailure),
        ] {
            do {
                _ = try await Self.fetch(provider, engine: engine, code: code, body: "private-response")
                Issue.record("Expected HTTP failure")
            } catch let error as ProviderFetchClassifiedError {
                #expect(error.kind == kind)
                #expect(error.localizedDescription.contains(String(code)))
                #expect(!error.localizedDescription.contains("private-response"))
            }
        }
    }

    static func fetch(
        _ provider: String, engine: ProviderPluginEngineKind, code: Int = 200, body: String? = nil) async throws
        -> UsageSnapshot
    {
        let vercel = provider == "vercel"
        let runtime = try BundledPluginTestSupport.runtime(
            provider,
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.url?.absoluteString == (vercel
                        ? "https://ai-gateway.vercel.sh/v1/credits" : "https://api.atlascloud.ai/public/v1/balance"))
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
                #expect(request.timeoutInterval == 15)
                let response = try #require(HTTPURLResponse(
                    url: request.url!,
                    statusCode: code,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "Retry-After": "0"]))
                return (Data((body ?? Self.fixture(provider)).utf8), response)
            })
        return try await runtime
            .fetchUsage(secrets: [vercel ? "AI_GATEWAY_API_KEY" : "ATLASCLOUD_API_KEY": "fixture-key"])
    }
}
