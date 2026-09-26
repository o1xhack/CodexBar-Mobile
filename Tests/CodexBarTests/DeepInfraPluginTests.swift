import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct DeepInfraPluginTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let checklist = #"{"stripe_balance":-99.75,"recent":3.94,"limit":20}"#
    private static let usage = #"{"months":[{"period":"2026.07","total_cost":394}]}"#

    @Test(arguments: BundledPluginTestSupport.engines)
    func `billing fixture preserves native projection`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(engine: engine)
        #expect(snapshot.primary == RateWindow(
            usedPercent: 0,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: "$95.81 available · $3.94 spent this month"))
        #expect(snapshot.providerCost == ProviderCostSnapshot(
            used: 3.94, limit: 20, currencyCode: "USD", period: "Billing cycle", updatedAt: Self.now))
        #expect(snapshot.identity?.providerID == .deepinfra)
        #expect(snapshot.dataConfidence == .exact)
        #expect(snapshot.updatedAt == Self.now)
    }

    @Test(arguments: [
        (#"{"stripe_balance":2.75,"recent":7,"limit":-1}"#, "$9.75 owed · $3.94 spent this month", 100.0),
        (
            #"{"stripe_balance":-5,"recent":1,"suspended":true,"suspend_reason":" Payment review "}"#,
            "Suspended: Payment review · $4.00 available · $3.94 spent this month",
            100.0),
        (#"{"stripe_balance":0,"recent":-1}"#, "$0.00 available · $3.94 spent this month", 100.0),
    ], BundledPluginTestSupport.engines)
    func `balances suspension and missing limits preserve goldens`(
        fixture: (String, String, Double), engine: ProviderPluginEngineKind) async throws
    {
        let snapshot = try await Self.fetch(checklist: fixture.0, engine: engine)
        #expect(snapshot.primary?.resetDescription == fixture.1)
        #expect(snapshot.primary?.usedPercent == fixture.2)
        #expect(snapshot.providerCost == nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `empty months fall back to recent spend`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(usage: #"{"months":[]}"#, engine: engine)
        #expect(snapshot.primary?.resetDescription == "$95.81 available · $3.94 spent this month")
    }

    @Test(arguments: [0.125, 1.375, 49.585, 1000.625, 1e21], BundledPluginTestSupport.engines)
    func `USD formatting preserves native rounding without grouping`(
        balance: Double, engine: ProviderPluginEngineKind) async throws
    {
        let checklist = "{\"stripe_balance\":\(-balance),\"recent\":0}"
        let snapshot = try await Self.fetch(checklist: checklist, engine: engine)
        #expect(snapshot.primary?.resetDescription == String(
            format: "$%.2f available · $3.94 spent this month",
            balance))
    }

    @Test(arguments: [
        "{}",
        #"{"stripe_balance":"5","recent":1}"#,
        #"{"stripe_balance":1e308,"recent":1e308}"#,
        #"{"stripe_balance":-5,"recent":1,"suspended":1}"#,
    ], BundledPluginTestSupport.engines)
    func `malformed checklist fails instead of fabricating balance`(
        checklist: String, engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(.parseFailure) { try await Self.fetch(checklist: checklist, engine: engine) }
    }

    @Test(
        arguments: [
            "{}",
            #"{"months":[{"period":"2026.07","total_cost":"394"}]}"#,
            #"{"months":[{}, {"period":"2026.07","total_cost":394}]}"#
        ],
        BundledPluginTestSupport.engines)
    func `all monthly rows must be valid`(usage: String, engine: ProviderPluginEngineKind) async {
        await Self.expectFailure(.parseFailure) { try await Self.fetch(usage: usage, engine: engine) }
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired), (403, .permissionDenied), (400, .apiFailure),
    ], BundledPluginTestSupport.engines)
    func `required usage endpoint failures stay visible`(
        failure: (Int, ProviderFetchClassifiedError.Kind), engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(failure.1) {
            try await Self.fetch(usageStatus: failure.0, engine: engine)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `both requests keep bearer origin deadline and ordering`(engine: ProviderPluginEngineKind) async throws {
        let recorder = DeepInfraRequestRecorder()
        let runtime = try BundledPluginTestSupport.runtime(
            "deepinfra", engine: engine, transport: ProviderHTTPTransportHandler { request in
                await recorder.append(request)
                return try Self.response(
                    request,
                    body: request.url?.path == "/payment/checklist"
                        ? Self.checklist : Self.usage)
            })
        _ = try await runtime.fetchUsage(secrets: ["DEEPINFRA_API_KEY": "fixture-token"])
        let requests = await recorder.values
        #expect(requests.map(\.url?.absoluteString) == [
            "https://api.deepinfra.com/payment/checklist?compute_owed=true",
            "https://api.deepinfra.com/payment/usage?from=current",
        ])
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.timeoutInterval == 30 })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Accept") == "application/json" })
    }

    @Test
    func `descriptor uses only the bundled script without a prototype flag`() async throws {
        let context = ProviderCutoverTestSupport.context(environment: ["DEEPINFRA_TOKEN": "fixture-token"])
        let strategies = await DeepInfraProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(context)
        #expect(strategies.map(\.id) == ["deepinfra.js"])
        let strategy = try #require(strategies.first)
        #expect(await strategy.isAvailable(context))
        #expect(await !strategy.isAvailable(ProviderCutoverTestSupport.context()))
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `transient usage failure retries only that request`(engine: ProviderPluginEngineKind) async throws {
        let recorder = DeepInfraRequestRecorder()
        let runtime = try BundledPluginTestSupport.runtime(
            "deepinfra", engine: engine, transport: ProviderHTTPTransportHandler { request in
                await recorder.append(request)
                let isChecklist = request.url?.path == "/payment/checklist"
                let count = await recorder.values.count
                return try Self.response(
                    request,
                    body: isChecklist ? Self.checklist : Self.usage,
                    status: count == 2 ? 503 : 200)
            })
        let snapshot = try await runtime.fetchUsage(secrets: ["DEEPINFRA_API_KEY": "fixture-token"])
        #expect(snapshot.primary?.usedPercent == 0)
        #expect(await recorder.values.map(\.url?.path) == ["/payment/checklist", "/payment/usage", "/payment/usage"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `transport cancellation remains cancellation`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "deepinfra", engine: engine, transport: ProviderHTTPTransportHandler { _ in throw URLError(.cancelled) })
        await #expect(throws: CancellationError.self) {
            try await runtime.fetchUsage(secrets: ["DEEPINFRA_API_KEY": "fixture-token"])
        }
    }

    private static func fetch(
        checklist: String = Self.checklist,
        usage: String = Self.usage,
        usageStatus: Int = 200,
        engine: ProviderPluginEngineKind) async throws -> UsageSnapshot
    {
        let runtime = try BundledPluginTestSupport.runtime(
            "deepinfra", engine: engine, transport: ProviderHTTPTransportHandler { request in
                let isChecklist = request.url?.path == "/payment/checklist"
                return try Self.response(
                    request,
                    body: isChecklist ? checklist : usage,
                    status: isChecklist ? 200 : usageStatus)
            })
        return try await runtime.fetchUsage(secrets: ["DEEPINFRA_API_KEY": "fixture-token"], now: Self.now)
    }

    private static func response(_ request: URLRequest, body: String, status: Int = 200) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        return try (Data(body.utf8), #require(HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "0"])))
    }

    private static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind, operation: () async throws -> UsageSnapshot) async
    {
        await #expect { try await operation() } throws: { error in
            (error as? ProviderFetchClassifiedError)?.kind == kind
        }
    }
}

private actor DeepInfraRequestRecorder {
    private(set) var values: [URLRequest] = []
    func append(_ request: URLRequest) { self.values.append(request) }
}
