import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct HyperPluginTests {
    #if canImport(JavaScriptCore)
    private static let engines: [ProviderPluginEngineKind] = [.quickJS, .javaScriptCore]
    #else
    private static let engines: [ProviderPluginEngineKind] = [.quickJS]
    #endif

    @Test(arguments: Self.engines)
    func `draft balance fixtures retain native HC without fabricated limits`(
        engine: ProviderPluginEngineKind) async throws
    {
        for balance in [0, 12, 18.5, 42.5] {
            let snapshot = try await Self.fetch(engine: engine, body: "{\"balance\":\(balance)}")
            #expect(snapshot.providerCost == nil)
            #expect(snapshot.details.first?.rows.first?.usageValue == balance)
            #expect(snapshot.primary == nil)
            #expect(snapshot.secondary == nil)
            #expect(snapshot.identity?.providerID == .hyper)
            #expect(snapshot.identity?.loginMethod == "API key")
            #expect(snapshot.dataConfidence == .exact)
            #expect(snapshot.details.first?.rows.first?.value.hasSuffix(" HC") == true)
        }
    }

    @Test(arguments: Self.engines)
    func `session wins over key and sends only cookies`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(engine: engine, cookie: "session=fixture-session")
        #expect(snapshot.details.first?.rows.first?.usageValue == 42.5)
        #expect(snapshot.identity?.loginMethod == "Browser session")
    }

    @Test(arguments: Self.engines)
    func `API source bypasses cookie resolver`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(engine: engine, cookie: "session=unused", mode: .api)
        #expect(snapshot.identity?.loginMethod == "API key")
    }

    @Test(arguments: Self.engines)
    func `missing session falls back to key`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(engine: engine, cookie: "")
        #expect(snapshot.identity?.loginMethod == "API key")
    }

    @Test(arguments: [401, 403, 302, 200], Self.engines)
    func `expired session is rejected before API fallback`(
        statusCode: Int,
        engine: ProviderPluginEngineKind) async throws
    {
        let snapshot = try await Self.fetch(
            engine: engine, cookie: "session=fixture-rejected-session", sessionStatus: statusCode,
            sessionHTML: statusCode == 200)
        #expect(snapshot.identity?.loginMethod == "API key")
    }

    @Test(arguments: [401, 403, 302, 200], Self.engines)
    func `web only never falls back to configured key`(statusCode: Int, engine: ProviderPluginEngineKind) async {
        do {
            _ = try await Self.fetch(
                engine: engine, cookie: "session=fixture-rejected-session", mode: .web,
                sessionStatus: statusCode, sessionHTML: statusCode == 200)
            Issue.record("Expected expired session")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .authenticationExpired)
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test(arguments: [
        "",
        "{}",
        #"{"balance":"#,
        #"{"balance":-1}"#,
        #"{"balance":"invalid"}"#,
        #"{"balance":null}"#,
        #"{"balance":true}"#,
        #"{"balance":1e400}"#,
        "null",
        "[]"
    ], Self.engines)
    func `invalid draft and extended fixtures fail closed without key fallback`(
        body: String, engine: ProviderPluginEngineKind) async
    {
        for cookie in [nil, "session=fixture"] {
            do {
                _ = try await Self.fetch(engine: engine, body: body, cookie: cookie)
                Issue.record("Expected parse failure")
            } catch let error as ProviderFetchClassifiedError {
                #expect(error.kind == .parseFailure)
            } catch { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired),
        (403, .permissionDenied),
        (429, .rateLimited),
        (503, .providerUnavailable),
        (404, .apiFailure)
    ], Self.engines)
    func `HTTP errors are classified without exposing response or key`(
        fixture: (Int, ProviderFetchClassifiedError.Kind), engine: ProviderPluginEngineKind) async
    {
        do {
            _ = try await Self.fetch(engine: engine, body: "private upstream body fixture-key", apiStatus: fixture.0)
            Issue.record("Expected HTTP failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == fixture.1)
            #expect(!error.message.contains("private upstream body"))
            #expect(!error.message.contains("fixture-key"))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test(arguments: Self.engines)
    func `no credentials produce guidance without HTTP`(engine: ProviderPluginEngineKind) async {
        do {
            _ = try await Self.fetch(engine: engine, key: "")
            Issue.record("Expected missing credential")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .missingCredential)
            #expect(error.message.contains("Sign in"))
            #expect(error.message.contains("API key"))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test
    func `registry projects config and keeps balance provider opt in`() throws {
        let descriptor = HyperProviderDescriptor.descriptor
        let credentials = try #require(descriptor.credentials)
        let environment = credentials.applyConfig(
            base: ["HYPER_API_KEY": "old-key", "OTHER": "preserved"],
            config: ProviderConfig(id: .hyper, apiKey: " 'fixture-key' "))
        #expect(credentials.resolveToken(environment: environment)?.token == "fixture-key")
        #expect(environment["OTHER"] == "preserved")
        #expect(HyperProviderDescriptor.apiKey(environment: ["HYPER_API_KEY": "  "]) == nil)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .web, .api])
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(!descriptor.metadata.widgetSelectable)
        #expect(descriptor.metadata.balanceOnly)
        if case let .environment(key) = credentials.tokenAccountSupport?.injection {
            #expect(key == "HYPER_API_KEY")
        } else {
            Issue.record("Expected API-key token accounts")
        }
    }

    private static func fetch(
        engine: ProviderPluginEngineKind,
        body: String = #"{"balance":42.5}"#,
        key: String = "fixture-key",
        cookie: String? = nil,
        mode: ProviderSourceMode = .auto,
        sessionStatus: Int = 200,
        sessionHTML: Bool = false,
        apiStatus: Int = 200) async throws -> UsageSnapshot
    {
        let rejected = HyperRejectionRecorder()
        let expectsSession = cookie?.isEmpty == false && mode != .api
        let transport = ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://hyper.charm.land/v1/credits")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            let isSession = request.value(forHTTPHeaderField: "Cookie") != nil
            if isSession {
                #expect(expectsSession)
                #expect(request.value(forHTTPHeaderField: "Cookie") == cookie)
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            } else {
                #expect(!key.isEmpty)
                #expect(mode != .web)
                #expect(!expectsSession || sessionStatus != 200 || sessionHTML)
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
            }
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: isSession ? sessionStatus : apiStatus, httpVersion: nil,
                headerFields: ["Content-Type": isSession && sessionHTML ? "text/html; charset=utf-8" :
                    "application/json"]))
            return (Data((isSession && sessionHTML ? "<html>Log in</html>" : body).utf8), response)
        }
        let url = try #require(CodexBarCoreResources.bundle?.url(forResource: "hyper", withExtension: "js"))
        let runtime = try ProviderPluginRuntime(
            source: String(contentsOf: url, encoding: .utf8), transport: transport, engine: engine)
        let snapshot = try await runtime.fetchUsage(
            settings: ["SOURCE_MODE": mode.rawValue], secrets: ["HYPER_API_KEY": key],
            sourceMode: mode, cookieSource: cookie == nil ? .off : .manual,
            cookieInvalidator: { domain in
                #expect(domain == "hyper.charm.land")
                rejected.record()
            },
            cookieResolver: { provider, domain in
                #expect(mode != .api)
                #expect(provider == .hyper)
                #expect(domain == "hyper.charm.land")
                guard let cookie, !cookie.isEmpty else { throw ProviderPluginError.secretAccess("fixture missing") }
                return cookie
            })
        #expect(rejected.count == (expectsSession && (sessionStatus != 200 || sessionHTML) ? 1 : 0))
        return snapshot
    }
}

private final class HyperRejectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        self.lock.withLock { self.value }
    }

    func record() { self.lock.withLock { self.value += 1 } }
}
