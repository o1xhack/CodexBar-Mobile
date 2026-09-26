import Foundation
import Testing
@testable import CodexBarCore

struct ProviderPluginCookieResultTests {
    @Test(arguments: BundledPluginTestSupport.engines, [false, true])
    func `both result entry points preserve cookie iteration and rejection`(
        engine: ProviderPluginEngineKind,
        usageOnly: Bool) async throws
    {
        let requests = LockIsolated<[Bool]>([])
        let rejections = LockIsolated<[String]>([])
        let runtime = try ProviderPluginRuntime(source: """
        defineProvider({id: 'fireworks', name: 'Fixture', endpoints: ['https://cookies.example.test'], settings: [],
          capabilities: ['browser-cookies'], cookieDomains: ['cookies.example.test'],
          async fetchUsage(ctx) {
            if (ctx.browser.availability('cookies.example.test') !== 'available') {
              throw new Error('Session resolver is unavailable');
            }
            for await (const session of ctx.browser.sessions('cookies.example.test', {cachedOnly: true})) {
              ctx.browser.rejectCookie('cookies.example.test', session);
            }
            for await (const session of ctx.browser.sessions('cookies.example.test')) {
              return {usage: {primary: {usedPercent: 42}}, sourceLabel: session.source,
                persist: {ACCOUNT_SLUG: 'fixture-team'}};
            }
            throw new Error('No session candidates');
          }
        });
        """, engine: engine)
        let resolve: ProviderPluginRuntime.CookieSessionResolver = { domain, cachedOnly in
            #expect(domain == "cookies.example.test")
            requests.setValue(requests.value + [cachedOnly])
            if requests.value.count == 2 { return nil }
            return ProviderPluginCookieSession(
                header: "session=fixture",
                source: cachedOnly ? "Cache" : "Profile",
                origin: "https://cookies.example.test",
                id: cachedOnly ? "rejected-candidate" : "accepted-candidate")
        }
        let reject: ProviderPluginRuntime.CookieSessionInvalidator = { domain, id in
            rejections.setValue(rejections.value + ["\(domain):\(id)"])
        }
        let usage: UsageSnapshot
        if usageOnly {
            usage = try await runtime.fetchUsage(cookieSessionResolver: resolve, cookieSessionInvalidator: reject)
        } else {
            let result = try await runtime.fetchResult(cookieSessionResolver: resolve, cookieSessionInvalidator: reject)
            #expect(result.sourceLabel == "Profile")
            #expect(result.persist == ["ACCOUNT_SLUG": "fixture-team"])
            usage = result.usage
        }
        #expect(usage.primary?.usedPercent == 42)
        #expect(requests.value == [true, true, false])
        #expect(rejections.value == ["cookies.example.test:rejected-candidate"])
    }
}
