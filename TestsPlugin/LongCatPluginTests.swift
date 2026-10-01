import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct LongCatPluginTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `active token pack bypasses stale legacy usage and retains fuel`(engine: ProviderPluginEngineKind) async throws {
        let transport = Fixture([
            .init("/api/v1/user-current", body: #"{"data":{"name":"Fixture Account"}}"#),
            .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body:
                #"{"code":0,"data":{"currentLot":{"status":"ACTIVE","totalToken":50000000,"consumedToken":1212576}}}"#),
            .init("/api/lc-platform/v1/pending-fuel-packages", body:
                #"{"data":{"totalQuota":1000,"list":[{"availableToken":600,"expireTime":1750000000000},{"availableToken":150,"expireTime":1760000000000}]}}"#),
        ])
        let usage = try await Self.fetch(engine, transport: transport)
        #expect(abs((usage.primary?.usedPercent ?? 0) - 2.425152) < 0.000001)
        #expect(usage.primary?.resetDescription == "1212576/50000000")
        #expect(usage.secondary?.usedPercent == 25)
        #expect(usage.secondary?.resetDescription == "Fuel pack: 750/1000")
        #expect(usage.secondary?.resetsAt == Date(timeIntervalSince1970: 1_750_000_000))
        #expect(usage.identity?.accountOrganization == "Fixture Account")
        #expect(await transport.remaining == 0)
    }

    @Test(arguments: [401, 500], BundledPluginTestSupport.engines)
    func `optional summary and fuel errors preserve required legacy quota`(
        status: Int, engine: ProviderPluginEngineKind) async throws
    {
        let transport = Fixture([
            .init("/api/v1/user-current", body: #"{"data":{"nickName":"Fixture"}}"#),
            .init("/api/pay/quota/metering/token-packs/summary", method: "POST", status: status, body: "invalid"),
            .init("/api/lc-platform/v1/tokenUsage", body:
                #"{"data":{"usage":{"totalToken":500000,"usedToken":120000,"availableToken":380000}}}"#),
            .init("/api/lc-platform/v1/pending-fuel-packages", status: status, body: "invalid"),
        ])
        let usage = try await Self.fetch(engine, transport: transport)
        #expect(usage.primary?.usedPercent == 24)
        #expect(usage.secondary == nil)
        #expect(await transport.remaining == 0)
    }

    @Test(arguments: ["0", "200", "\"2e2\"", "200.9"], BundledPluginTestSupport.engines)
    func `supported envelope codes retain numeric boundaries`(code: String, engine: ProviderPluginEngineKind) async throws {
        let usage = try await Self.fetch(engine, transport: Fixture([
            .init("/api/v1/user-current", body: "{\"code\":\(code),\"data\":{}}"),
            .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body: "{}"),
            .init("/api/lc-platform/v1/tokenUsage", body:
                #"{"totalToken":200000000000000000000,"usedToken":100000000000000000000}"#),
            .init("/api/lc-platform/v1/pending-fuel-packages", body:
                #"{"totalQuota":10.9,"list":[{"availableToken":-0.25}]}"#),
        ]))
        #expect(usage.primary?.usedPercent == 50)
        #expect(usage.primary?.resetDescription == "100000000000000000000/200000000000000000000")
        #expect(usage.secondary?.resetDescription == "Fuel pack: 0/10")
    }

    @Test(arguments: ["1e100", "\"1e100\"", "\"Infinity\"", "\"NaN\"", "null", "{}"], BundledPluginTestSupport.engines)
    func `malformed envelope codes fail parsing`(code: String, engine: ProviderPluginEngineKind) async throws {
        await #expect {
            try await Self.fetch(engine, transport: Fixture([
                .init("/api/v1/user-current", body: "{\"code\":\(code),\"data\":{}}"),
            ]))
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .parseFailure }
    }

    @Test(arguments: [302, 401, 403], BundledPluginTestSupport.engines)
    func `required authentication failures advance profiles`(status: Int, engine: ProviderPluginEngineKind) async throws {
        let transport = Fixture([
            .init("/api/v1/user-current", status: status, body: "login"),
            .init("/api/v1/user-current", body: "{}"),
            .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body:
                #"{"currentLot":{"status":"ACTIVE","totalToken":100,"consumedToken":10}}"#),
            .init("/api/lc-platform/v1/pending-fuel-packages", body: "{}"),
        ])
        let usage = try await Self.fetch(engine, transport: transport, count: 2)
        #expect(usage.primary?.usedPercent == 10)
        #expect(await transport.remaining == 0)
    }

    @Test(arguments: [#"{"code":401}"#, #"{"code":"403"}"#], BundledPluginTestSupport.engines)
    func `HTTP success auth envelopes reject sessions`(body: String, engine: ProviderPluginEngineKind) async throws {
        await #expect {
            try await Self.fetch(engine, transport: Fixture([.init("/api/v1/user-current", body: body)]))
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .authenticationExpired }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `required server failures do not advance profiles`(engine: ProviderPluginEngineKind) async throws {
        await #expect {
            try await Self.fetch(engine, transport: Fixture([.init("/api/v1/user-current", status: 500)]), count: 2)
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .apiFailure }
    }

    @Test(arguments: ["2025-06-15T15:06:40.250Z", "2025-06-15T17:06:40.250+02:00"], BundledPluginTestSupport.engines)
    func `fractional fuel dates survive both engines`(date: String, engine: ProviderPluginEngineKind) async throws {
        let usage = try await Self.fetch(engine, transport: Fixture([
            .init("/api/v1/user-current", body: "{}"),
            .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body: "{}"),
            .init("/api/lc-platform/v1/tokenUsage", body: #"{"totalToken":0}"#),
            .init("/api/lc-platform/v1/pending-fuel-packages", body:
                "{\"totalQuota\":1000,\"list\":[{\"availableToken\":150,\"expireTime\":\"\(date)\"}]}"),
        ]))
        #expect(usage.secondary?.resetsAt == Date(timeIntervalSince1970: 1_750_000_000.250))
    }

    @Test(arguments: ["{}", #"{"currentLot":null}"#,
                      #"{"currentLot":{"status":"EXPIRED","totalToken":100}}"#,
                      #"{"currentLot":{"status":"ACTIVE","totalToken":0}}"#], BundledPluginTestSupport.engines)
    func `unusable token packs fall back and infer used from remaining`(
        summary: String, engine: ProviderPluginEngineKind) async throws
    {
        let usage = try await Self.fetch(engine, transport: Fixture([
            .init("/api/v1/user-current", body: "{}"),
            .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body: summary),
            .init("/api/lc-platform/v1/tokenUsage", body: #"{"totalToken":1000,"availableToken":400}"#),
            .init("/api/lc-platform/v1/pending-fuel-packages", body: "{}"),
        ]))
        #expect(usage.primary?.usedPercent == 60)
        #expect(usage.primary?.resetDescription == "600/1000")
    }

    @Test(arguments: [#"{"data":[]}"#, #"{"data":{}}"#, "malformed"], BundledPluginTestSupport.engines)
    func `required legacy quota must parse`(body: String, engine: ProviderPluginEngineKind) async throws {
        await #expect {
            try await Self.fetch(engine, transport: Fixture([
                .init("/api/v1/user-current", body: "{}"),
                .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body: "{}"),
                .init("/api/lc-platform/v1/tokenUsage", body: body),
            ]))
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .parseFailure }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `overflowing fuel totals preserve quota and huge expiry omits only the reset`(
        engine: ProviderPluginEngineKind) async throws
    {
        for fuel in [
            #"{"totalQuota":1e308,"list":[{"availableToken":1e308},{"availableToken":1e308}]}"#,
            #"{"totalQuota":1000,"list":[{"availableToken":500,"expireTime":1e24}]}"#,
        ] {
            let usage = try await Self.fetch(engine, transport: Fixture([
                .init("/api/v1/user-current", body: "{}"),
                .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body: "{}"),
                .init("/api/lc-platform/v1/tokenUsage", body: #"{"totalToken":100,"usedToken":25}"#),
                .init("/api/lc-platform/v1/pending-fuel-packages", body: fuel),
            ]))
            #expect(usage.primary?.usedPercent == 25)
            #expect(usage.secondary?.resetsAt == nil)
            if fuel.contains("1e308") { #expect(usage.secondary == nil) }
            else { #expect(usage.secondary?.resetDescription == "Fuel pack: 500/1000") }
        }
    }

    private static func fetch(
        _ engine: ProviderPluginEngineKind, transport: Fixture, count: Int = 1) async throws -> UsageSnapshot
    {
        let runtime = try BundledPluginTestSupport.runtime("longcat", engine: engine, transport: transport)
        let sessions = Sessions(count: count)
        return try await runtime.fetchUsage(cookieSessionResolver: { _, _ in await sessions.next() })
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `request URL misses advance the whole profile without flattening its cookies`(
        engine: ProviderPluginEngineKind) async throws
    {
        let transport = Fixture([
            .init("/api/v1/user-current", body: "{}"),
            .init("/api/v1/user-current", body: "{}"),
            .init("/api/pay/quota/metering/token-packs/summary", method: "POST", body:
                #"{"currentLot":{"status":"ACTIVE","totalToken":100,"consumedToken":10}}"#),
            .init("/api/lc-platform/v1/pending-fuel-packages", body: "{}"),
        ])
        let sessions = try JarSessions(values: ["/api/v1", "/"].map { path in
            let cookie = try #require(HTTPCookie(properties: [
                .name: "session", .value: "fixture", .domain: "longcat.chat", .path: path,
            ]))
            return .init(header: "", source: "Synthetic", origin: "https://longcat.chat",
                         records: [ProviderPluginCookieRecord(cookie: cookie)])
        })
        let runtime = try BundledPluginTestSupport.runtime("longcat", engine: engine, transport: transport)
        let usage = try await runtime.fetchUsage(cookieSessionResolver: { _, _ in await sessions.next() })
        #expect(usage.primary?.usedPercent == 10)
        #expect(await transport.remaining == 0)
    }

    private actor JarSessions {
        var values: [ProviderPluginCookieSession]
        init(values: [ProviderPluginCookieSession]) { self.values = values }
        func next() -> ProviderPluginCookieSession? { self.values.isEmpty ? nil : self.values.removeFirst() }
    }

    private actor Sessions {
        var count: Int
        init(count: Int) { self.count = count }
        func next() -> ProviderPluginCookieSession? {
            guard self.count > 0 else { return nil }
            self.count -= 1
            return .init(header: "session=fixture", source: "Fixture", origin: "https://longcat.chat")
        }
    }

    private actor Fixture: ProviderHTTPTransport {
        struct Step: Sendable {
            let path: String
            let method: String
            let status: Int
            let body: String
            init(_ path: String, method: String = "GET", status: Int = 200, body: String = "{}") {
                self.path = path
                self.method = method
                self.status = status
                self.body = body
            }
        }
        var steps: [Step]
        var remaining: Int { self.steps.count }
        init(_ steps: [Step]) { self.steps = steps }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let step = try #require(self.steps.first)
            self.steps.removeFirst()
            let url = try #require(request.url)
            #expect(url.path == step.path)
            #expect(request.httpMethod == step.method)
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=fixture")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://longcat.chat")
            if step.method == "POST" { #expect(request.httpBody == Data("{}".utf8)) }
            return try (Data(step.body.utf8), #require(HTTPURLResponse(
                url: url, statusCode: step.status, httpVersion: nil, headerFields: nil)))
        }
    }
}
