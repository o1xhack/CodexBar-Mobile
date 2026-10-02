import Foundation
import Testing
@testable import CodexBarCore

struct LongCatProviderTests {
    // MARK: - Settings reader

    @Test
    func `reads LONGCAT_MANUAL_COOKIE`() {
        let env = ["LONGCAT_MANUAL_COOKIE": "passport_token=abc; uid=42"]
        #expect(LongCatSettingsReader.cookieHeader(environment: env) == "passport_token=abc; uid=42")
    }

    @Test
    func `reads LONGCAT_API_KEY and trims quotes`() {
        #expect(LongCatSettingsReader.apiKey(environment: ["LONGCAT_API_KEY": "  \"ak_x\"  "]) == "ak_x")
    }

    @Test
    func `missing env returns nil`() {
        #expect(LongCatSettingsReader.cookieHeader(environment: [:]) == nil)
        #expect(LongCatSettingsReader.apiKey(environment: [:]) == nil)
    }

    @Test
    func `cookieHeader reads lowercase alias and trims quotes`() {
        // The env path routes through this reader, so the lower-case alias and
        // quote-trimming must apply (regression for the env-bypass fix).
        #expect(LongCatSettingsReader.cookieHeader(environment: ["longcat_manual_cookie": "'a=b; c=d'"]) == "a=b; c=d")
    }

    @Test(arguments: ["session=fixture", "curl 'https://longcat.chat/' -H 'Cookie: session=fixture'"])
    func `manual and environment headers share normalization`(raw: String) {
        let automatic = self.context(env: ["LONGCAT_MANUAL_COOKIE": raw], cookieSource: .auto)
        let settings = LongCatProviderDescriptor.cookieSettings(automatic)
        #expect(settings.cookieSource == .manual)
        #expect(settings.manualCookieHeader == "session=fixture")
    }

    @Test
    func `off disables environment cookies`() {
        let settings = LongCatProviderDescriptor.cookieSettings(self.context(
            env: ["LONGCAT_MANUAL_COOKIE": "session=fixture"], cookieSource: .off))
        #expect(settings.cookieSource == .off)
        #expect(settings.manualCookieHeader == nil)
    }

    @Test
    func `manual takes precedence over environment and invalid manual does not fall back`() {
        for header in ["session=manual", "not a cookie"] {
            var context = self.context(env: ["LONGCAT_MANUAL_COOKIE": "session=env"], cookieSource: .manual)
            context = ProviderFetchContext(
                runtime: context.runtime,
                sourceMode: context.sourceMode,
                includeCredits: false,
                webTimeout: 1,
                webDebugDumpHTML: false,
                verbose: false,
                env: context.env,
                settings: .make(longcat: .init(cookieSource: .manual, manualCookieHeader: header)),
                fetcher: context.fetcher,
                claudeFetcher: context.claudeFetcher,
                browserDetection: context.browserDetection)
            let settings = LongCatProviderDescriptor.cookieSettings(context)
            #expect(settings.cookieSource == .manual)
            #expect(settings.manualCookieHeader == (header.contains("=") ? header : nil))
        }
    }

    @Test
    func `background and CLI automatic sessions never import`() throws {
        for runtime in [ProviderRuntime.app, .cli] {
            let context = self.context(env: [:], cookieSource: .auto, runtime: runtime)
            let broker = ProviderPluginCookieBroker(
                provider: .longcat, domains: ["longcat.chat"], context: context, usesCookieJar: true)
            #expect(try broker.nextSession(domain: "longcat.chat") == nil)
            if runtime == .cli {
                try ProviderInteractionContext.$current.withValue(.userInitiated) { () throws in
                    let interactive = ProviderPluginCookieBroker(
                        provider: .longcat, domains: ["longcat.chat"], context: context, usesCookieJar: true)
                    #expect(try interactive.nextSession(domain: "longcat.chat") == nil)
                }
            }
        }
    }

    private func context(
        env: [String: String],
        cookieSource: ProviderCookieSource,
        runtime: ProviderRuntime = .app) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: runtime,
            sourceMode: .web,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: ProviderSettingsSnapshot.make(
                longcat: .init(cookieSource: cookieSource, manualCookieHeader: nil)),
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }
}
