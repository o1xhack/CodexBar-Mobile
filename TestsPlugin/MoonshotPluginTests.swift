import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct MoonshotPluginTests {
    struct Golden: Sendable {
        let balance: String
        let cash: String
        let usd: String
        let cny: String
    }

    static let goldens = [
        Golden(balance: "49.58", cash: "12.34", usd: "$49.58", cny: "CN¥49.58"),
        Golden(balance: "49.58", cash: "-0.42", usd: "$49.58 · $0.42 in deficit", cny: "CN¥49.58 · CN¥0.42 in deficit"),
        Golden(balance: "0", cash: "0", usd: "$0.00", cny: "CN¥0.00"),
        Golden(balance: "49.585", cash: "0", usd: "$49.58", cny: "CN¥49.58"),
        Golden(balance: "49.595", cash: "0", usd: "$49.60", cny: "CN¥49.60"),
        Golden(balance: "-0.0", cash: "-0.0", usd: "-$0.00", cny: "-CN¥0.00"),
        Golden(balance: "1e-7", cash: "-1e-7", usd: "$0.00 · $0.00 in deficit", cny: "CN¥0.00 · CN¥0.00 in deficit"),
        Golden(
            balance: "-12.345",
            cash: "-12.345",
            usd: "-$12.34 · $12.34 in deficit",
            cny: "-CN¥12.34 · CN¥12.34 in deficit"),
    ]

    @Test(arguments: Self.goldens, ProviderPluginTransportTests.engines)
    func `balance goldens match native on both engines`(golden: Golden, engine: ProviderPluginEngineKind) async throws {
        for region in MoonshotRegion.allCases {
            let snapshot = try await Self.fetch(
                Self.body(balance: golden.balance, cash: golden.cash),
                region: region,
                engine: engine)
            let expected = "Balance: \(region == .china ? golden.cny : golden.usd)"
            #expect(snapshot.loginMethod(for: .moonshot) == expected)
            #expect(snapshot.primary == nil)
            #expect(snapshot.secondary == nil)
            #expect(snapshot.tertiary == nil)
            #expect(snapshot.providerCost == nil)
            #expect(snapshot.details.isEmpty)
            #expect(snapshot.identity?.providerID == .moonshot)
            #expect(snapshot.identity?.accountEmail == nil)
            #expect(snapshot.identity?.accountOrganization == nil)
            #expect(snapshot.identity?.accountID == nil)
            #expect(snapshot.dataConfidence == .unknown)
            #expect(snapshot.updatedAt == Self.now)
            let identity = MoonshotProviderDescriptor.descriptor.presentation.identity(
                provider: .moonshot,
                snapshot: snapshot)
            #expect(identity.badge == expected)
            #expect(identity.plan == expected)
        }
    }

    @Test(arguments: [
        "[]", "{}", "null", "<html>not JSON</html>",
        Self.body().replacingOccurrences(of: "\"code\":0", with: "\"code\":false"),
        Self.body().replacingOccurrences(of: "\"code\":0", with: "\"code\":0.5"),
        Self.body().replacingOccurrences(of: "\"scode\":\"0x0\"", with: "\"scode\":0"),
        Self.body().replacingOccurrences(of: "\"status\":true", with: "\"status\":1"),
        Self.body().replacingOccurrences(of: "\"voucher_balance\":50,", with: ""),
        Self.body().replacingOccurrences(of: "\"voucher_balance\":50", with: "\"voucher_balance\":\"50\""),
        Self.body(balance: "\"49.58\""), Self.body(balance: "true"), Self.body(balance: "null"),
        Self.body(balance: "1e999"), Self.body(cash: "false"), Self.body(cash: "null"),
    ], ProviderPluginTransportTests.engines)
    func `malformed payloads remain parse failures`(body: String, engine: ProviderPluginEngineKind) async {
        await Self.expectFailure(.parseFailure, prefix: "Failed to parse Moonshot response:") {
            try await Self.fetch(body, engine: engine)
        }
    }

    @Test(arguments: ProviderPluginTransportTests.engines)
    func `API envelope errors preserve their diagnostic`(engine: ProviderPluginEngineKind) async {
        let body = Self.body().replacingOccurrences(of: "\"code\":0", with: "\"code\":401")
            .replacingOccurrences(of: "0x0", with: "unauthorized")
            .replacingOccurrences(of: "true", with: "false")
        await Self.expectFailure(.apiFailure, prefix: "Moonshot API error: code 401, scode unauthorized") {
            try await Self.fetch(body, engine: engine)
        }
        await Self.expectFailure(.apiFailure, prefix: "Moonshot API error: code 0, scode 0x0") {
            try await Self.fetch(Self.body().replacingOccurrences(of: "true", with: "false"), engine: engine)
        }
    }

    @Test(arguments: [201, 401, 403, 429, 500], ProviderPluginTransportTests.engines)
    func `HTTP failures do not parse bodies or retry`(status: Int, engine: ProviderPluginEngineKind) async throws {
        let calls = MoonshotRequestCount()
        let runtime = try Self.runtime(engine: engine, transport: ProviderHTTPTransportHandler { request in
            await calls.increment()
            return try Self.response(request, body: "private provider error body", status: status)
        })
        await Self.expectFailure(.apiFailure, prefix: "Moonshot API error: HTTP \(status)") {
            try await runtime.fetchUsage(
                settings: ["BASE_URL": MoonshotRegion.international.apiBaseURLString],
                secrets: ["MOONSHOT_API_KEY": "fixture-token"])
        }
        #expect(await calls.value == 1)
    }

    @Test(arguments: ProviderPluginTransportTests.engines)
    func `unknown origins cannot receive credentials`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine: engine, transport: ProviderHTTPTransportHandler { request in
            Issue.record("Unexpected request to \(request.url!)")
            throw URLError(.unsupportedURL)
        })
        await Self.expectFailure(.apiFailure, prefix: "Invalid Moonshot API region.") {
            try await runtime.fetchUsage(
                settings: ["BASE_URL": "https://untrusted.example"],
                secrets: ["MOONSHOT_API_KEY": "fixture-token"])
        }
    }

    @Test(arguments: ProviderPluginTransportTests.engines)
    func `invalid transport response retains network diagnostic`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine: engine, transport: ProviderHTTPTransportHandler { _ in
            throw URLError(.badServerResponse)
        })
        await Self.expectFailure(.networkFailure, prefix: "Moonshot network error: Invalid response") {
            try await runtime.fetchUsage(
                settings: ["BASE_URL": MoonshotRegion.international.apiBaseURLString],
                secrets: ["MOONSHOT_API_KEY": "fixture-token"])
        }
    }

    @Test(arguments: ProviderPluginTransportTests.engines)
    func `transport cancellation remains cancellation`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine: engine, transport: ProviderHTTPTransportHandler { _ in
            throw CancellationError()
        })
        await #expect(throws: CancellationError.self) {
            try await runtime.fetchUsage(
                settings: ["BASE_URL": MoonshotRegion.international.apiBaseURLString],
                secrets: ["MOONSHOT_API_KEY": "fixture-token"])
        }
    }

    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func fetch(
        _ body: String,
        region: MoonshotRegion = .international,
        engine: ProviderPluginEngineKind) async throws -> UsageSnapshot
    {
        let runtime = try Self.runtime(engine: engine, transport: ProviderHTTPTransportHandler { request in
            let expectedOrigin = region == .china ? "https://api.moonshot.cn" : "https://api.moonshot.ai"
            #expect(request.url?.absoluteString == "\(expectedOrigin)/v1/users/me/balance")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.timeoutInterval == 15)
            return try Self.response(request, body: body)
        })
        return try await runtime.fetchUsage(
            settings: ["BASE_URL": region.apiBaseURLString],
            secrets: ["MOONSHOT_API_KEY": "fixture-token"],
            now: Self.now)
    }

    private static func response(_ request: URLRequest, body: String, status: Int = 200) throws -> (Data, URLResponse) {
        let response = try #require(HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]))
        return (Data(body.utf8), response)
    }

    private static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind,
        prefix: String,
        operation: () async throws -> UsageSnapshot) async
    {
        do {
            _ = try await operation()
            Issue.record("Expected \(kind.rawValue)")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == kind)
            #expect(error.localizedDescription == prefix || error.localizedDescription.hasPrefix(prefix + " "))
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }
    }

    private static func runtime(
        engine: ProviderPluginEngineKind, transport: any ProviderHTTPTransport) throws -> ProviderPluginRuntime
    {
        let bundle = try #require(CodexBarCoreResources.bundle)
        let url = try #require(bundle.url(forResource: "moonshot", withExtension: "js"))
        return try ProviderPluginRuntime(
            source: String(contentsOf: url, encoding: .utf8), transport: transport, engine: engine)
    }

    static func body(balance: String = "49.58", cash: String = "12.34") -> String {
        """
        {"code":0,"data":{"available_balance":\(balance),"voucher_balance":50,"cash_balance":\(cash)},
        "scode":"0x0","status":true}
        """
    }
}

private actor MoonshotRequestCount {
    var value = 0

    func increment() {
        self.value += 1
    }
}
