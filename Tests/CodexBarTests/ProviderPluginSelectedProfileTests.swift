import Foundation
import Testing
@testable import CodexBarCore

struct ProviderPluginSelectedProfileTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `selected profile policy is available on both engines`(engine: ProviderPluginEngineKind) throws {
        let runtime = try ProviderPluginRuntime(source: Self.source, engine: engine)
        #expect(runtime.manifest.cookiePolicy != nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines, [
        ("cache: 'nonpersistent'", "cache: 'validated-single-entry'"),
        ("imports: 'access-gated'", "imports: 'app-interactive'"),
        ("requiredCookies: ['auth_token']", "requiredCookies: []"),
        ("sessionURL: 'https://app.langdock.com/api/usage'", "sessionURL: 'https://other.example.test/api/usage'"),
    ])
    func `selected profile declarations reject caching widened origins and missing identity`(
        engine: ProviderPluginEngineKind, replacement: (String, String))
    {
        #expect(throws: ProviderPluginError.self) {
            try ProviderPluginRuntime(source: Self.source.replacingOccurrences(
                of: replacement.0, with: replacement.1), engine: engine)
        }
    }

    static let source = """
    defineProvider({id: 'langdock', name: 'Fixture', settings: [],
      endpoints: ['https://app.langdock.com'], capabilities: ['browser-cookies'],
      cookieDomains: ['langdock.com', 'app.langdock.com'],
      cookiePolicy: {selection: 'request-url', cache: 'nonpersistent', imports: 'access-gated',
        store: 'selected-profile', requiredCookies: ['auth_token'],
        sessionURL: 'https://app.langdock.com/api/usage'},
      async fetchUsage(ctx) {
        for await (const session of ctx.browser.sessions('app.langdock.com')) {
          const response = await ctx.http.getJSON('https://app.langdock.com/api/usage', {cookieSession: session.id});
          if (response.status >= 500) throw ctx.fail.providerUnavailable('Synthetic outage');
          return {primary: {usedPercent: response.json.percent}};
        }
        throw ctx.fail.missingCredential('No selected session');
      }
    });
    """
}
