import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct DevPassPluginTests {
    /// Public /v1/key example, with synthetic values and a fixed reset.
    static let fixture: [String: String?] = [
        "label": "Fixture key", "usage": "31.42", "limit": nil, "devPlan": "pro",
        "devPlanCreditsUsed": "25", "devPlanCreditsLimit": "237", "devPlanCreditsRemaining": "212.00",
        "devPlanPremiumWeeklyLimit": "35.55", "devPlanPremiumCreditsUsed": "5.00",
        "devPlanPremiumWeekResetsAt": "2026-10-01T12:00:00.000Z",
    ]

    @Test(arguments: BundledPluginTestSupport.engines)
    func `documented monthly and weekly credits preserve scope`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(engine: engine)
        #expect(try abs(#require(snapshot.primary?.usedPercent) - 25 / 237.0 * 100) < 0.0001)
        #expect(try abs(#require(snapshot.secondary?.usedPercent) - 5 / 35.55 * 100) < 0.0001)
        #expect(snapshot.primary?.resetsAt == nil)
        #expect(snapshot.primary?.windowMinutes == nil)
        #expect(snapshot.secondary?.windowMinutes == 10080)
        #expect(snapshot.secondary?.resetsAt == ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z"))
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.details.first?.rows.first?.value == "$25.00 / $237.00")
        #expect(snapshot.dataConfidence == .exact)
        #expect(snapshot.identity?.providerID == .devpass)
        #expect(snapshot.identity?.loginMethod == "DevPass Pro")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `inactive weekly window has full allowance without invented reset`(
        engine: ProviderPluginEngineKind) async throws
    {
        var data = Self.fixture
        data["devPlanPremiumCreditsUsed"] = "0.00"
        data["devPlanPremiumWeekResetsAt"] = .some(nil)
        let snapshot = try await Self.fetch(data, engine: engine)
        #expect(snapshot.secondary?.usedPercent == 0)
        #expect(snapshot.secondary?.resetsAt == nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `PAYG shows only key scoped all time spend`(engine: ProviderPluginEngineKind) async throws {
        var data = Self.fixture
        data["devPlan"] = "none"
        for key in data.keys where key.hasPrefix("devPlan") && key != "devPlan" {
            data[key] = key.hasSuffix("ResetsAt") ? .some(nil) : "0"
        }
        let snapshot = try await Self.fetch(data, engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.details.first?.title == "API key (all time)")
        #expect(snapshot.details.first?.rows.first?.value == "$31.42")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `zero limits omit bars and overages keep actual spend`(engine: ProviderPluginEngineKind) async throws {
        var data = Self.fixture
        data["devPlanCreditsUsed"] = "250"
        data["devPlanCreditsRemaining"] = "0"
        data["devPlanPremiumWeeklyLimit"] = "0"
        let snapshot = try await Self.fetch(data, engine: engine)
        #expect(snapshot.primary?.usedPercent == 100)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.details.first?.rows.first?.value == "$250.00 / $237.00")
    }

    @Test(arguments: ["", " ", "NaN", "1e999", "-1", "0x10"], BundledPluginTestSupport.engines)
    func `invalid monetary strings fail closed`(value: String, engine: ProviderPluginEngineKind) async throws {
        var data = Self.fixture
        data["devPlanCreditsUsed"] = value
        await #expect(throws: ProviderFetchClassifiedError.self) { try await Self.fetch(data, engine: engine) }
    }

    @Test(arguments: ["devPlan", "devPlanPremiumWeekResetsAt"], BundledPluginTestSupport.engines)
    func `unknown plans and invalid reset dates fail closed`(
        key: String,
        engine: ProviderPluginEngineKind) async throws
    {
        var data = Self.fixture
        data[key] = "unexpected"
        await #expect(throws: ProviderFetchClassifiedError.self) { try await Self.fetch(data, engine: engine) }
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired), (403, .permissionDenied),
        (429, .rateLimited), (503, .providerUnavailable), (400, .apiFailure),
    ], BundledPluginTestSupport.engines)
    func `HTTP failures are classified without exposing bodies`(
        argument: (Int, ProviderFetchClassifiedError.Kind), engine: ProviderPluginEngineKind) async throws
    {
        do {
            _ = try await Self.fetch(engine: engine, status: argument.0)
            Issue.record("Expected HTTP failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == argument.1)
            #expect(!error.message.contains("private-response"))
        }
    }

    @Test(arguments: ["not-json", "{}", #"{"data":null}"#], BundledPluginTestSupport.engines)
    func `malformed responses are parse failures`(body: String, engine: ProviderPluginEngineKind) async throws {
        await #expect(throws: ProviderFetchClassifiedError.self) {
            try await Self.fetch(engine: engine, body: body)
        }
    }

    static func fetch(
        _ data: [String: String?] = Self.fixture,
        engine: ProviderPluginEngineKind,
        status: Int = 200,
        body: String? = nil) async throws -> UsageSnapshot
    {
        let payload = try JSONSerialization.data(withJSONObject: ["data": data.mapValues { $0 as Any? ?? NSNull() }])
        let runtime = try BundledPluginTestSupport.runtime(
            "devpass",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.url?.absoluteString == "https://api.llmgateway.io/v1/key")
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
                #expect(request.timeoutInterval == 15)
                let response = try #require(HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "Retry-After": "0"]))
                return (status == 200 ? body.map { Data($0.utf8) } ?? payload : Data("private-response".utf8), response)
            })
        return try await runtime.fetchUsage(secrets: ["DEVPASS_API_KEY": "fixture-key"])
    }
}
