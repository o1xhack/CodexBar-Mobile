import Foundation
import Testing
@testable import CodexBarCore

struct PerplexityProviderTests {
    @Test(arguments: [UsageProvider.perplexity, .qoder])
    func `cookie cutovers are authoritative without prototype flag and availability never imports`(
        provider: UsageProvider) async
    {
        for source in [ProviderCookieSource.auto, .manual, .off] {
            let settings: ProviderSettingsSnapshot = provider == .qoder
                ? .make(qoder: .init(cookieSource: source, manualCookieHeader: "session=fixture"))
                : .make(perplexity: .init(cookieSource: source, manualCookieHeader: "fixture"))
            let context = Self.context(settings: settings)
            let strategies = await ProviderDescriptorRegistry.descriptor(for: provider).fetchPlan.pipeline
                .resolveStrategies(context)
            #expect(strategies.map(\.id) == ["\(provider.rawValue).js"])
            #expect(await strategies[0].isAvailable(context) == (source != .off))
        }
    }

    @Test
    func `Qoder strategy keeps successful regional source label`() async throws {
        let strategy = QoderPluginFetchStrategy(transport: ProviderHTTPTransportHandler { request in
            #expect(request.url?.host == "qoder.com.cn")
            return try CookiePluginFixtures.response(
                request, body: #"{"totalQuota":{"quotaSummary":{"usedValue":25,"limitValue":100}}}"#)
        })
        let context = Self.context(settings: .make(qoder: .init(
            cookieSource: .manual, manualCookieHeader: "curl https://qoder.com.cn -H 'Cookie: session=fixture'")))
        let result = try await strategy.fetch(context)
        #expect(result.sourceLabel == "manual / qoder.com.cn")
        #expect(result.strategyID == "qoder.js")
        #expect(result.usage.identity?.loginMethod == nil)
        #expect(result.usage.primary?.usedPercent == 25)
    }

    private static func context(settings: ProviderSettingsSnapshot) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 15,
            webDebugDumpHTML: false,
            verbose: false,
            env: ["PERPLEXITY_SESSION_TOKEN": "environment-fixture"],
            settings: settings,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot { throw URLError(.unknown) }
        func debugRawProbe(model _: String) async -> String { "fixture" }
        func detectVersion() -> String? { nil }
    }
}
