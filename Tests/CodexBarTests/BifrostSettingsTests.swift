import Foundation
import Testing
@testable import CodexBarCore

struct BifrostSettingsTests {
    @Test
    func `settings preserve virtual key and configured origin boundaries`() {
        #expect(BifrostSettingsReader.apiKey(environment: ["BIFROST_API_KEY": " 'fixture-key' "]) == "fixture-key")
        #expect(BifrostSettingsReader.baseURL(environment: [:]) == nil)
        for endpoint in [
            "https://bifrost.example.com",
            "http://localhost:8080",
            "http://192.168.1.2:8080",
            "http://gateway.local:8080",
            "http://[fd00::1]:8080",
        ] {
            #expect(BifrostSettingsReader.baseURL(environment: ["BIFROST_BASE_URL": endpoint]) != nil)
        }
        for endpoint in ["http://bifrost.example.com", "https://user:password@bifrost.example.com", "file:///fixture"] {
            #expect(BifrostSettingsReader.baseURL(environment: ["BIFROST_BASE_URL": endpoint]) == nil)
            #expect(BifrostSettingsReader.hasBaseURLOverride(environment: ["BIFROST_BASE_URL": endpoint]))
        }
    }

    @Test
    func `script availability requires both a virtual key and a configured origin`() async {
        let descriptor = BifrostProviderDescriptor.descriptor
        for (environment, available) in [
            ([:], false), (["BIFROST_API_KEY": "fixture-key"], false),
            (["BIFROST_BASE_URL": "https://bifrost.example.com"], false),
            (["BIFROST_API_KEY": "fixture-key", "BIFROST_BASE_URL": "https://bifrost.example.com"], true),
            (["BIFROST_API_KEY": "fixture-key", "BIFROST_BASE_URL": "http://public.example.com"], true),
        ] {
            let context = ProviderFetchContext(
                runtime: .cli,
                sourceMode: .api,
                includeCredits: false,
                webTimeout: 1,
                webDebugDumpHTML: false,
                verbose: false,
                env: environment,
                settings: nil,
                fetcher: UsageFetcher(environment: environment),
                claudeFetcher: BifrostUnusedClaudeFetcher(),
                browserDetection: BrowserDetection(
                    homeDirectory: "/nonexistent/bifrost-fixture",
                    fileExists: { _ in false },
                    directoryContents: { _ in nil }))
            let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(context)
            #expect(strategies.map(\.id) == ["bifrost.js"])
            #expect(await strategies[0].isAvailable(context) == available)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `private network HTTP is supported and public HTTP is rejected before transport`(
        engine: ProviderPluginEngineKind) async throws
    {
        let usage = try await BifrostPluginTests.fetch(
            BifrostPluginTests.quota,
            engine: engine,
            base: "http://192.168.1.2:8080/")
        #expect(usage.primary != nil)
        let runtime = try BundledPluginTestSupport.runtime(
            "bifrost",
            engine: engine,
            transport: ProviderHTTPTransportHandler { _ in
                Issue.record("Invalid endpoint reached the transport")
                throw URLError(.badURL)
            })
        for base in ["http://public.example.com", "https://user:password@bifrost.example.com"] {
            await #expect(throws: (any Error).self) {
                try await runtime.fetchUsage(
                    settings: ["BIFROST_BASE_URL": base],
                    secrets: ["BIFROST_API_KEY": "fixture-key"])
            }
        }
    }
}

private struct BifrostUnusedClaudeFetcher: ClaudeUsageFetching {
    func detectVersion() -> String? { nil }
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot { throw CancellationError() }
    func debugRawProbe(model _: String) async -> String { "unused" }
}
