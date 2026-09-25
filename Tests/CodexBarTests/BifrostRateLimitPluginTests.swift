import Foundation
import Testing
@testable import CodexBarCore

struct BifrostRateLimitPluginTests {
    static let components = #"""
    [{"id":"profile-a","source_name":"Profile A","token_max_limit":100,"token_current_usage":10,
      "request_max_limit":500,"request_current_usage":20},
     {"id":"profile-b","source_name":"Profile B","token_max_limit":500,"token_current_usage":10,
      "request_max_limit":200,"request_current_usage":20}]
    """#

    static func aggregate(_ id: String = "merged") -> String {
        """
        {"id":"\(id)","token_max_limit":100,"token_current_usage":10,
         "request_max_limit":200,"request_current_usage":20}
        """
    }

    @Test(arguments: ["merged", "profile-a"], BundledPluginTestSupport.engines)
    func `components replace the compatibility aggregate even when IDs overlap`(
        aggregateID: String, engine: ProviderPluginEngineKind) async throws
    {
        let windows = try await Self.windows(
            Self.body(aggregate: Self.aggregate(aggregateID), components: Self.components), engine: engine)
        #expect(windows.map(\.window.usedPercent) == [10, 4, 2, 10])
        #expect(windows.map(\.title) == [
            "Profile A Tokens",
            "Profile A Requests",
            "Profile B Tokens",
            "Profile B Requests",
        ])
        #expect(Set(windows.map(\.id)).count == windows.count)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `components alone report every source without requiring an aggregate`(
        engine: ProviderPluginEngineKind) async throws
    {
        let windows = try await Self.windows(Self.body(components: Self.components), engine: engine)
        #expect(windows.map(\.window.usedPercent) == [10, 4, 2, 10])
        #expect(Set(windows.map(\.id)).count == 4)
    }

    @Test(arguments: ["absent", "null", "[]"], BundledPluginTestSupport.engines)
    func `aggregate is the fallback for absent null or empty component lists`(
        components: String, engine: ProviderPluginEngineKind) async throws
    {
        let windows = try await Self.windows(Self.body(
            aggregate: Self.aggregate(), components: components == "absent" ? nil : components), engine: engine)
        #expect(windows.map(\.window.usedPercent) == [10, 10])
        #expect(windows.map(\.title) == ["Tokens", "Requests"])
        #expect(Set(windows.map(\.id)).count == 2)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `backend ID reuse and anonymous components never suppress usage or collide`(
        engine: ProviderPluginEngineKind) async throws
    {
        let components = #"""
        [{"id":"same","source_name":"First","token_max_limit":100,"token_current_usage":10},
         {"id":"same","source_name":"Second","token_max_limit":100,"token_current_usage":20},
         {"token_max_limit":100,"token_current_usage":30},
         {"id":"2","token_max_limit":100,"token_current_usage":40},
         {"token_max_limit":100,"token_current_usage":50}]
        """#
        let windows = try await Self.windows(Self.body(components: components), engine: engine)
        #expect(windows.map(\.window.usedPercent) == [10, 20, 30, 40, 50])
        #expect(Set(windows.map(\.id)).count == 5)
        #expect(windows[0].title == "First Tokens")
        #expect(windows[1].title == "Second Tokens")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `component precedence and unique IDs apply independently to every scope`(
        engine: ProviderPluginEngineKind) async throws
    {
        let fields = "\"rate_limit\":\(Self.aggregate()),\"rate_limits\":\(Self.components)"
        let body = """
        {\(fields),
         "provider_configs":[{"provider":"fixture-provider",\(fields)}],
         "model_configs":[{"model_name":"fixture-model",\(fields)}]}
        """
        let windows = try await Self.windows(body, engine: engine)
        #expect(windows.map(\.window.usedPercent) == Array(repeating: [10.0, 4, 2, 10], count: 3).flatMap(\.self))
        #expect(Set(windows.map(\.id)).count == 12)
        #expect(windows[4].title == "Provider fixture-provider Profile A Tokens")
        #expect(windows[8].title == "Model fixture-model Profile A Tokens")
    }

    @Test(arguments: ["token", "request"], BundledPluginTestSupport.engines)
    func `aggregate dimensions do not fill missing component dimensions`(
        dimension: String, engine: ProviderPluginEngineKind) async throws
    {
        let components = #"""
        [{"id":"single-dimension","\#(dimension)_max_limit":100,
          "token_current_usage":20,"request_current_usage":20,
          "token_last_reset":"2026-09-22T00:00:00Z","request_last_reset":"2026-09-22T00:00:00Z",
          "config_hash":null,"created_at":"2026-09-01T00:00:00Z","updated_at":"2026-09-22T00:00:00Z"}]
        """#
        let windows = try await Self.windows(
            Self.body(aggregate: Self.aggregate(), components: components),
            engine: engine)
        try #require(windows.count == 1)
        #expect(windows[0].window.usedPercent == 20)
        #expect(windows[0].title == (dimension == "token" ? "Tokens" : "Requests"))
    }

    @Test(arguments: ["null", "\"\"", "\"  \""], BundledPluginTestSupport.engines)
    func `unconditional reset timestamps do not create unconfigured quota windows`(
        reset: String, engine: ProviderPluginEngineKind) async throws
    {
        let components = """
        [{"id":"unconfigured","token_current_usage":0,"request_current_usage":0,
          "token_max_limit":null,"request_max_limit":null,
          "token_reset_duration":\(reset),"request_reset_duration":\(reset),
          "token_last_reset":"2026-09-22T00:00:00Z","request_last_reset":"2026-09-22T00:00:00Z",
          "config_hash":null,"created_at":"2026-09-01T00:00:00Z","updated_at":"2026-09-22T00:00:00Z"}]
        """
        #expect(try await Self.windows(Self.body(components: components), engine: engine).isEmpty)
    }

    private static func body(aggregate: String? = nil, components: String? = nil) -> String {
        var fields = [String]()
        if let aggregate { fields.append("\"rate_limit\":\(aggregate)") }
        if let components { fields.append("\"rate_limits\":\(components)") }
        return "{\(fields.joined(separator: ","))}"
    }

    private static func windows(_ body: String, engine: ProviderPluginEngineKind) async throws -> [NamedRateWindow] {
        try #require(try await BifrostPluginTests.fetch(body, engine: engine).extraRateWindows)
    }
}
