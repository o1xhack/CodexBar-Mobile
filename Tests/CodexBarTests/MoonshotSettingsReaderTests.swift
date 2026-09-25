import Foundation
import Testing
@testable import CodexBarCore

private struct MoonshotStubClaudeFetcher: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw URLError(.userAuthenticationRequired)
    }

    func debugRawProbe(model _: String) async -> String {
        "stub"
    }

    func detectVersion() -> String? {
        nil
    }
}

struct MoonshotSettingsReaderTests {
    @Test
    func `api key prefers MOONSHOT API KEY`() {
        let env = [
            "MOONSHOT_API_KEY": "primary-token",
            "MOONSHOT_KEY": "fallback-token",
        ]

        #expect(MoonshotSettingsReader.apiKey(environment: env) == "primary-token")
    }

    @Test
    func `api key strips quotes`() {
        let env = ["MOONSHOT_KEY": "\"quoted-token\""]

        #expect(MoonshotSettingsReader.apiKey(environment: env) == "quoted-token")
    }

    @Test
    func `region parses china`() {
        let env = ["MOONSHOT_REGION": "china"]

        #expect(MoonshotSettingsReader.region(environment: env) == .china)
    }

    @Test
    func `default settings snapshot does not mask environment region`() {
        let settings = ProviderSettingsSnapshot.MoonshotProviderSettings()

        #expect(settings.region == nil)
    }

    @Test
    func `region defaults to international for unknown values`() {
        let env = ["MOONSHOT_REGION": "moon"]

        #expect(MoonshotSettingsReader.region(environment: env) == .international)
    }

    @Test
    func `region bound config key is unavailable to the other host`() {
        let env = [
            MoonshotSettingsReader.configAPIKeyEnvironmentKey: "china-token",
            MoonshotSettingsReader.configAPIKeyRegionEnvironmentKey: MoonshotRegion.china.rawValue,
        ]

        #expect(MoonshotSettingsReader.apiKey(for: .china, environment: env) == "china-token")
        #expect(MoonshotSettingsReader.apiKey(for: .international, environment: env) == nil)
    }

    @Test
    func `environment key requires a matching explicit China region`() {
        let unscoped = ["MOONSHOT_API_KEY": "china-token"]
        let china = [
            "MOONSHOT_API_KEY": "china-token",
            "MOONSHOT_REGION": "china",
        ]

        #expect(MoonshotSettingsReader.apiKey(for: .china, environment: unscoped) == nil)
        #expect(MoonshotSettingsReader.apiKey(for: .international, environment: unscoped) == "china-token")
        #expect(MoonshotSettingsReader.apiKey(for: .china, environment: china) == "china-token")
        #expect(MoonshotSettingsReader.apiKey(for: .international, environment: china) == nil)
    }

    @Test
    func `strategy rejects mismatched key before building a request`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            Issue.record("Unexpected Moonshot request to \(request.url?.absoluteString ?? "<nil>")")
            throw URLError(.userAuthenticationRequired)
        }
        let env = [
            MoonshotSettingsReader.configAPIKeyEnvironmentKey: "international-token",
            MoonshotSettingsReader.configAPIKeyRegionEnvironmentKey: MoonshotRegion.international.rawValue,
        ]
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: .make(moonshot: .init(region: .china)),
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: MoonshotStubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
        let strategies = await MoonshotProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(context)
        #expect(strategies.count == 1)
        #expect(strategies.first is ScriptFetchStrategy)
        let strategy = MoonshotProviderDescriptor.scriptStrategy(transport: transport)

        #expect(await strategy.isAvailable(context) == false)
        await #expect {
            try await strategy.fetch(context)
        } throws: { error in
            let classified = error as? ProviderFetchClassifiedError
            return classified?.kind == .missingCredential && classified?.message == "Missing Moonshot API key."
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: MoonshotRegion.allCases, [true, false])
    func `script strategy resolves regional settings and credentials without a feature flag`(
        region: MoonshotRegion, savedKey: Bool) async throws
    {
        let environment = savedKey
            ? [
                MoonshotSettingsReader.configAPIKeyEnvironmentKey: "saved-token",
                MoonshotSettingsReader.configAPIKeyRegionEnvironmentKey: region.rawValue,
                "MOONSHOT_API_KEY": "other-region-token",
                "MOONSHOT_REGION": region == .china ? "international" : "china",
                "CODEXBAR_JS_PROVIDERS": "0",
            ]
            : [
                "MOONSHOT_API_KEY": "environment-token",
                "MOONSHOT_REGION": region.rawValue,
                "CODEXBAR_JS_PROVIDERS": "0",
            ]
        let transport = ProviderHTTPTransportStub { request in
            let expectedOrigin = region == .china ? "https://api.moonshot.cn" : "https://api.moonshot.ai"
            #expect(request.url?.absoluteString == "\(expectedOrigin)/v1/users/me/balance")
            #expect(request.value(forHTTPHeaderField: "Authorization")
                == "Bearer \(savedKey ? "saved-token" : "environment-token")")
            let body = """
            {"code":0,"data":{"available_balance":49.58,"voucher_balance":50,"cash_balance":12.34},
            "scode":"0x0","status":true}
            """
            return (Data(body.utf8), HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: .make(moonshot: .init(region: savedKey ? region : nil)),
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: MoonshotStubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
        let strategy = MoonshotProviderDescriptor.scriptStrategy(transport: transport)
        #expect(await strategy.isAvailable(context))
        let result = try await strategy.fetch(context)
        #expect(result.sourceLabel == "api")
        #expect(result.strategyID == "moonshot.js")
        #expect(result.usage
            .loginMethod(for: .moonshot) == (region == .china ? "Balance: CN¥49.58" : "Balance: $49.58"))
        #expect(await transport.requests().count == 1)
    }
}

struct MoonshotProviderTokenResolverTests {
    @Test
    func `resolves from environment`() {
        let env = ["MOONSHOT_API_KEY": "env-token"]
        let resolution = ProviderTokenResolver.resolution(for: .moonshot, environment: env)

        #expect(resolution?.token == "env-token")
        #expect(resolution?.source == .environment)
    }

    @Test
    func `uses kimi branding icon`() {
        let branding = MoonshotProviderDescriptor.descriptor.branding

        #expect(branding.iconStyle == .kimi)
        #expect(branding.iconResourceName == "ProviderIcon-kimi")
    }

    @Test
    func `dashboard url opens account console`() {
        #expect(
            MoonshotProviderDescriptor.descriptor.metadata.dashboardURL
                == "https://platform.moonshot.ai/console/account")
    }
}
