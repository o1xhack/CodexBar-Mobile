import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ZenMuxPluginTests {
    static let subscription = #"""
    {"success":true,"data":{"plan":{"tier":"ultra","expires_at":"2026-04-12T08:26:56Z"},
    "account_status":"healthy",
    "quota_5_hour":{"usage_percentage":0.0715,"resets_at":"2026-03-24T08:35:09Z",
    "max_flows":800,"used_flows":57.2,"remaining_flows":742.8},
    "quota_7_day":{"usage_percentage":0.0673,"max_flows":6182,"used_flows":416.11,"remaining_flows":5765.89}}}
    """#

    @Test(arguments: BundledPluginTestSupport.engines)
    func `subscription and PAYG match native projection`(engine: ProviderPluginEngineKind) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = ProviderHTTPTransportHandler { request in
            let body = request.url?.path.hasSuffix("/payg/balance") == true
                ? #"{"success":true,"data":{"currency":"usd","total_credits":-12.34}}"# : Self.subscription
            let url = try #require(request.url)
            return try (Data(body.utf8), #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
        let runtime = try BundledPluginTestSupport.runtime("zenmux", engine: engine, transport: transport)
        let snapshot = try await runtime.fetchUsage(
            settings: ["INCLUDE_PAYG": "1"], secrets: ["ZENMUX_MANAGEMENT_API_KEY": "fixture-key"], now: now)
        #expect(abs((snapshot.primary?.usedPercent ?? -1) - 7.15) < 0.000001)
        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.primary?.resetDescription == "57.20 / 800 flows")
        #expect(snapshot.primary?.resetsAt == ISO8601DateFormatter().date(from: "2026-03-24T08:35:09Z"))
        #expect(abs((snapshot.secondary?.usedPercent ?? -1) - 6.73) < 0.000001)
        #expect(snapshot.secondary?.windowMinutes == 10080)
        #expect(snapshot.secondary?.resetDescription == "416.11 / 6182 flows")
        #expect(snapshot.secondary?.resetsAt == nil)
        #expect(snapshot.identity?.providerID == .zenmux)
        #expect(snapshot.identity?.loginMethod == "Ultra plan")
        #expect(snapshot.subscriptionExpiresAt == ISO8601DateFormatter().date(from: "2026-04-12T08:26:56Z"))
        #expect(snapshot.providerCost == ProviderCostSnapshot(
            used: -12.34, limit: 0, currencyCode: "USD", period: "ZenMux PAYG balance", updatedAt: now))
        #expect(snapshot.dataConfidence == .exact)
    }

    @Test
    func `descriptor uses only the script without a prototype flag`() async throws {
        let context = ProviderCutoverTestSupport.context(environment: ["ZENMUX_MANAGEMENT_API_KEY": "fixture-key"])
        let strategies = await ZenMuxProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(context)
        #expect(strategies.map(\.id) == ["zenmux.js"])
        let strategy = try #require(strategies.first)
        #expect(await strategy.isAvailable(context))
        #expect(await !strategy.isAvailable(ProviderCutoverTestSupport.context()))
    }

    @Test(arguments: [
        (ProviderRuntime.app, false, true, "1"), (.app, true, false, "0"),
        (.cli, true, false, "1"), (.cli, false, true, "0"),
    ])
    func `PAYG follows the runtime preference`(input: (ProviderRuntime, Bool, Bool, String)) throws {
        let values = try #require(ZenMuxProviderDescriptor.scriptValues(ProviderCutoverTestSupport.context(
            environment: ["ZENMUX_MANAGEMENT_API_KEY": "fixture-key"],
            runtime: input.0,
            includeCredits: input.1,
            includeOptionalUsage: input.2)))
        #expect(values.settings["INCLUDE_PAYG"] == input.3)
    }

    @Test(arguments: [0.125, 1.375, -0.125, -0.0, 1e21], BundledPluginTestSupport.engines)
    func `flow labels preserve native rounding and negative zero`(
        flows: Double, engine: ProviderPluginEngineKind) async throws
    {
        let body = Self.subscription.replacingOccurrences(of: "\"used_flows\":57.2", with: "\"used_flows\":\(flows)")
        let snapshot = try await Self.fetch(body, engine: engine)
        let amount = String(format: flows.rounded() == flows ? "%.0f" : "%.2f", flows)
        #expect(snapshot.primary?.resetDescription == "\(amount) / 800 flows")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `invalid optional ISO date is omitted`(engine: ProviderPluginEngineKind) async throws {
        let body = Self.subscription.replacingOccurrences(of: "2026-04-12T08:26:56Z", with: "not-a-date")
        #expect(try await Self.fetch(body, engine: engine).subscriptionExpiresAt == nil)
    }

    @Test(arguments: ["\"0.0715\"", "null", "true"], BundledPluginTestSupport.engines)
    func `quota fractions require JSON numbers`(value: String, engine: ProviderPluginEngineKind) async {
        let body = Self.subscription.replacingOccurrences(of: "0.0715", with: value)
        await #expect { try await Self.fetch(body, engine: engine) } throws: { error in
            (error as? ProviderFetchClassifiedError)?.kind == .parseFailure
        }
    }

    private static func fetch(_ body: String, engine: ProviderPluginEngineKind) async throws -> UsageSnapshot {
        let runtime = try BundledPluginTestSupport.runtime(
            "zenmux", engine: engine, transport: ProviderHTTPTransportHandler { request in
                let url = try #require(request.url)
                return try (Data(body.utf8), #require(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            })
        return try await runtime.fetchUsage(secrets: ["ZENMUX_MANAGEMENT_API_KEY": "fixture-key"])
    }
}
