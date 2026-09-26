import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct BifrostPluginTests {
    static let now = Date(timeIntervalSince1970: 1_790_020_800)
    static let quota = #"""
    {"virtual_key_name":"fixture-team","budgets":[
      {"id":"year","max_limit":1000,"current_usage":100,"reset_duration":"1Y"},
      {"id":"month","max_limit":125,"current_usage":42.17,"reset_duration":"1M",
       "last_reset":"2026-09-01T00:00:00Z","source_name":"Engineering",
       "per_model_usage":[
         {"model":"gpt-4o","provider":"openai","total_cost":5,"total_tokens":1200000},
         {"model":"fixture-empty","provider":"openai","total_cost":0,"total_tokens":0}]}],
     "rate_limit":{"id":"rl_1","token_max_limit":1000000,"token_current_usage":345678,
                   "token_reset_duration":"1d","request_max_limit":5000,"request_current_usage":120},
     "rate_limits":[{"id":"rl_1","token_max_limit":1000000,"token_current_usage":345678,
                     "token_reset_duration":"1d","request_max_limit":5000,"request_current_usage":120},
                    {"id":"rl_2","source_name":"Team pool","token_max_limit":200000,
                     "token_current_usage":100,"request_reset_duration":"1h"}]}
    """#

    @Test(arguments: BundledPluginTestSupport.engines)
    func `contributor quota fixture preserves budget and detail goldens`(
        engine: ProviderPluginEngineKind) async throws
    {
        let usage = try await Self.fetch(Self.quota, engine: engine)
        #expect(usage.primary?.usedPercent == 33.736)
        #expect(usage.primary?.windowMinutes == nil)
        #expect(usage.primary?.resetsAt == nil)
        #expect(usage.primary?.resetDescription == "Engineering · Monthly · $42.17 / $125.00")
        #expect(usage.secondary?.usedPercent == 10)
        #expect(usage.secondary?.windowMinutes == nil)
        #expect(usage.providerCost?.used == 42.17)
        #expect(usage.providerCost?.limit == 125)
        #expect(usage.providerCost?.period == "Monthly")
        #expect(usage.identity?.providerID == .bifrost)
        #expect(usage.identity?.accountEmail == "fixture-team")
        #expect(usage.identity?.accountOrganization == "Engineering")
        #expect(usage.details.map(\.title) == ["Models", "Budgets"])
        #expect(usage.details[0].rows.map(\.label) == ["gpt-4o"])
        #expect(usage.details[0].rows[0].secondaryValue == "1.2M tokens")
        #expect(usage.details[0].rows[0].usageValue == 5)
        #expect(usage.details[1].rows.map(\.usageValue) == [42.17, 100])
        #expect(try abs(#require(usage.details[1].rows[0].progress?.usedPercent) - 33.736) < 0.000001)
        let windows = try #require(usage.extraRateWindows)
        #expect(windows.map(\.id) == [
            "bifrost-tokens-0",
            "bifrost-requests-0",
            "bifrost-tokens-1",
            "bifrost-requests-1",
        ])
        #expect(windows.map(\.usageKnown) == [true, true, true, false])
        #expect(windows.map(\.window.usedPercent) == [34.5678, 2.4, 0.05, 0])
        #expect(windows.last?.title == "Team pool Requests")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `override modes apply only while active and retain overage spend`(
        engine: ProviderPluginEngineKind) async throws
    {
        for (mode, cycles, limit) in [("forever", 0, 150), ("cycles", 2, 150), ("cycles", 0, 100), ("paused", 2, 100)] {
            let body = """
            {"budgets":[{"id":"b1","max_limit":100,"current_usage":200,
            "override_amount":50,"override_mode":"\(mode)","override_cycles_remaining":\(cycles)}]}
            """
            let usage = try await Self.fetch(body, engine: engine)
            #expect(usage.primary?.usedPercent == 100)
            #expect(usage.providerCost?.used == 200)
            #expect(usage.providerCost?.limit == Double(limit))
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `unlimited budget preserves spend without inventing a window`(engine: ProviderPluginEngineKind) async throws {
        let usage = try await Self.fetch(
            #"{"budgets":[{"id":"unlimited","max_limit":0,"current_usage":5}]}"#,
            engine: engine)
        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.providerCost?.used == 5)
        #expect(usage.providerCost?.limit == 0)
        #expect(usage.providerCost?.period == "Spend")
        let empty = try await Self.fetch(#"{"virtual_key_name":"svc","budgets":null}"#, engine: engine)
        #expect(empty.primary == nil)
        #expect(empty.providerCost == nil)
        #expect(empty.identity?.accountEmail == "svc")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `disabled keys preserve quotas with an unknown usage marker`(engine: ProviderPluginEngineKind) async throws {
        let body = Self.quota.replacingOccurrences(
            of: "\"virtual_key_name\"",
            with: "\"is_active\":false,\"virtual_key_name\"")
        let usage = try await Self.fetch(body, engine: engine)
        #expect(usage.primary != nil)
        #expect(usage.extraRateWindows?.first?.id == "bifrost-key-inactive")
        #expect(usage.extraRateWindows?.first?.usageKnown == false)
        let unlimited = try await Self.fetch(
            #"{"is_active":false,"budgets":[{"id":"unlimited","max_limit":0,"current_usage":5}]}"#,
            engine: engine)
        #expect(unlimited.providerCost?.used == 5)
        #expect(unlimited.extraRateWindows?.first?.usageKnown == false)
        await Self.expectFailure(.permissionDenied) {
            try await Self.fetch(#"{"is_active":false,"budgets":null}"#, engine: engine)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `duration grammar and stale resets retain deterministic next cycles`(
        engine: ProviderPluginEngineKind) async throws
    {
        for (duration, minutes) in [
            ("1h30m", 90),
            ("1d", 1440),
            ("1w", 10080),
            ("1M", 43200),
            ("1Q", 129_600),
            ("1Y", 525_600),
        ] {
            let body = """
            {"budgets":[{"id":"b1","max_limit":100,"current_usage":1,
            "reset_duration":"\(duration)","last_reset":"2026-09-01T00:00:00Z"}]}
            """
            let window = try #require(try await Self.fetch(body, engine: engine).primary)
            if duration == "1h30m" {
                #expect(window.windowMinutes == minutes)
                #expect(try #require(window.resetsAt) > Self.now)
            } else {
                #expect(window.windowMinutes == nil)
                #expect(window.resetsAt == nil)
            }
        }
        for duration in ["0s", "-1h", "invalid", "1e300Y", "1d2h", "constructor", "__proto__"] {
            let body = """
            {"budgets":[{"id":"b1","max_limit":100,"reset_duration":"\(duration)"}]}
            """
            let window = try #require(try await Self.fetch(body, engine: engine).primary)
            #expect(window.windowMinutes == nil)
            #expect(window.resetsAt == nil)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `scoped governance remains visible without claiming key wide spend`(
        engine: ProviderPluginEngineKind) async throws
    {
        let body = #"""
        {"is_active":false,"provider_configs":[{"provider":"openai",
          "budgets":[{"id":"provider-budget","max_limit":100,"current_usage":25,"reset_duration":"1M"}],
          "rate_limit":{"id":"provider-rate","request_max_limit":100,"request_current_usage":10}}],
         "model_configs":[{"model_name":"gpt-4o","provider":"openai",
          "budgets":[{"id":"model-budget","max_limit":20,"current_usage":10,"reset_duration":"1Q",
                      "reset_config":{"quarter_start_month":4},"last_reset":"2026-10-01T00:00:00Z"}],
          "rate_limit":{"id":"model-rate","token_reset_duration":"1h"}}]}
        """#
        let usage = try await Self.fetch(body, engine: engine)
        #expect(usage.primary == nil)
        #expect(usage.providerCost == nil)
        let windows = try #require(usage.extraRateWindows)
        #expect(windows.count == 5)
        #expect(windows[0].usageKnown == false)
        #expect(windows[1].title == "Provider openai · Budget")
        #expect(windows[1].window.usedPercent == 25)
        #expect(windows[2].title == "Model openai · gpt-4o · Budget")
        #expect(windows[2].window.resetsAt == nil)
        #expect(windows[3].window.usedPercent == 10)
        #expect(windows[4].usageKnown == false)
        #expect(usage.details[0].rows.map(\.usageValue) == [25, 10])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `model labels normalize routing prefixes without losing collisions or dotted versions`(
        engine: ProviderPluginEngineKind) async throws
    {
        let entries = #"""
        {"model":"us.anthropic.claude-3-5-sonnet-20241022-v2:0","provider":"bedrock","total_cost":5},
        {"model":"eu.anthropic.claude-3-5-sonnet-20241022-v2:0","provider":"bedrock","total_cost":4},
        {"model":"amazon.nova-pro-v1:0","provider":"bedrock","total_cost":3},
        {"model":"gpt-4.1","provider":"openai","total_cost":2},
        {"model":"gpt-4o","provider":"openai","total_cost":0,"total_tokens":500}
        """#
        let usage = try await Self.models(entries, engine: engine)
        #expect(usage.details[0].rows.map(\.label) == [
            "bedrock · us.anthropic.claude-3-5-sonnet-20241022-v2:0",
            "bedrock · eu.anthropic.claude-3-5-sonnet-20241022-v2:0",
            "bedrock · nova-pro", "openai · gpt-4.1", "openai · gpt-4o",
        ])
        #expect(usage.details[0].rows.last?.secondaryValue == "500 tokens")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `model rows rank and cap meaningful usage without hidden provider prefixes`(
        engine: ProviderPluginEngineKind) async throws
    {
        let entries = (0..<6).map {
            #"{"model":"fixture-\#($0)","provider":"\#($0 == 5 ? "hidden" : "visible")","total_cost":\#(6 - $0)}"#
        }.joined(separator: ",")
        let rows = try await Self.models(entries, engine: engine).details[0].rows
        #expect(rows.map(\.label) == ["fixture-0", "fixture-1", "fixture-2", "fixture-3", "fixture-4", "Other models"])
        #expect(rows.last?.value == "1")
        let empty = try await Self.models(#"{"model":"fixture-empty","total_cost":0,"total_tokens":0}"#, engine: engine)
        #expect(empty.details.isEmpty)
        let oversized = try await Self.models(#"{"model":"gpt-4o","total_cost":5,"total_tokens":1e20}"#, engine: engine)
        #expect(oversized.details[0].rows[0].secondaryValue == nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `HTTP statuses are classified without disclosing response bodies`(engine: ProviderPluginEngineKind) async {
        for (status, kind) in [
            (401, ProviderFetchClassifiedError.Kind.authenticationExpired),
            (403, .permissionDenied),
            (429, .rateLimited),
            (500, .providerUnavailable),
            (404, .apiFailure),
        ] {
            await Self.expectFailure(kind) {
                try await Self.fetch("private upstream body", engine: engine, status: status)
            }
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `malformed quota fields fail instead of coercing strings or flags`(engine: ProviderPluginEngineKind) async {
        for body in [
            "not JSON",
            "[]",
            #"{"is_active":"false"}"#,
            #"{"budgets":{}}"#,
            #"{"budgets":[{"id":"b1","max_limit":"100"}]}"#,
            #"{"rate_limit":{"request_max_limit":true}}"#,
        ] {
            await Self.expectFailure(.parseFailure) { try await Self.fetch(body, engine: engine) }
        }
    }

    static func fetch(
        _ body: String,
        engine: ProviderPluginEngineKind,
        status: Int = 200,
        base: String = "https://bifrost.example.com/gateway/") async throws -> UsageSnapshot
    {
        let runtime = try BundledPluginTestSupport.runtime(
            "bifrost",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.httpMethod == "GET")
                #expect(request.url?.absoluteString == base
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/governance/virtual-keys/quota")
                #expect(request.value(forHTTPHeaderField: "x-bf-vk") == "fixture-vk")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.timeoutInterval == 15)
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
        return try await runtime.fetchUsage(
            settings: ["BIFROST_BASE_URL": base],
            secrets: ["BIFROST_API_KEY": "fixture-vk"],
            now: Self.now)
    }

    private static func models(_ entries: String, engine: ProviderPluginEngineKind) async throws -> UsageSnapshot {
        try await self.fetch(
            "{\"budgets\":[{\"id\":\"b1\",\"max_limit\":100,\"current_usage\":10,\"per_model_usage\":[\(entries)]}]}",
            engine: engine)
    }

    private static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind,
        operation: () async throws -> UsageSnapshot) async
    {
        do {
            _ = try await operation()
            Issue.record("Expected \(kind)")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == kind)
            #expect(!error.localizedDescription.contains("private upstream body"))
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}
