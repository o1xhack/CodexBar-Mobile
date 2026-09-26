import Foundation
import Testing
@testable import CodexBarCore

struct CookieProviderCutoverTests {
    private static let perplexityBody = """
    {
      "balance_cents": 500,
      "renewal_date_ts": 1893456000,
      "current_period_purchased_cents": 0,
      "credit_grants": [
        {
          "type": "recurring",
          "amount_cents": 1000
        }
      ],
      "total_usage_cents": 500
    }
    """
    private static let qoderBody = #"{"totalQuota":{"quotaSummary":{"usedValue":25,"limitValue":100}}}"#

    @Test(arguments: BundledPluginTestSupport.engines)
    func `bare manual Perplexity token retries supported names without environment fallback`(
        engine: ProviderPluginEngineKind) async throws
    {
        let requests = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime(
            "perplexity", engine: engine, transport: ProviderHTTPTransportHandler { request in
                let cookie = try #require(request.value(forHTTPHeaderField: "Cookie"))
                requests.setValue(requests.value + [cookie])
                #expect(request.timeoutInterval == 15)
                #expect(request.value(forHTTPHeaderField: "Origin") == "https://www.perplexity.ai")
                return try CookiePluginFixtures.response(
                    request, body: Self.perplexityBody, status: cookie.hasPrefix("next-auth.") ? 200 : 401)
            })
        let broker = self.manualBroker(.perplexity, raw: "manual-fixture")
        let usage = try await runtime.fetchUsage(
            secrets: ["SESSION_COOKIE": "environment-fixture"],
            cookieSource: .manual,
            cookieSessionResolver: { try broker.nextSession(domain: $0, cachedOnly: $1) },
            cookieSessionInvalidator: { broker.rejectCookie(domain: $0, id: $1) })
        #expect(requests.value == PerplexityCookieHeader.supportedSessionCookieNames.map { "\($0)=manual-fixture" })
        #expect(usage.primary?.usedPercent == 50)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `Perplexity assembles ordered chunks and rejects gaps before HTTP`(
        engine: ProviderPluginEngineKind) async throws
    {
        let requests = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime(
            "perplexity", engine: engine, transport: ProviderHTTPTransportHandler { request in
                requests.setValue(requests.value + [request.value(forHTTPHeaderField: "Cookie") ?? ""])
                return try CookiePluginFixtures.response(request, body: Self.perplexityBody)
            })
        let complete = self.manualBroker(
            .perplexity, raw: "authjs.session-token.1=second; ignored=fixture; authjs.session-token.0=first")
        _ = try await runtime.fetchUsage(
            cookieSource: .manual, cookieSessionResolver: { try complete.nextSession(domain: $0, cachedOnly: $1) })
        #expect(requests.value == ["authjs.session-token=firstsecond"])
        let gap = self.manualBroker(.perplexity, raw: "authjs.session-token.0=first; authjs.session-token.2=third")
        await CookiePluginFixtures.expectFailure(.missingCredential) {
            try await runtime.fetchUsage(
                secrets: ["SESSION_COOKIE": "valid-environment-fixture"],
                cookieSource: .manual,
                cookieSessionResolver: { try gap.nextSession(domain: $0, cachedOnly: $1) })
        }
        #expect(requests.value.count == 1)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `Perplexity exhausts browser sessions before environment and never caches environment`(
        engine: ProviderPluginEngineKind) async throws
    {
        let service = "cookie-cutover-\(UUID().uuidString)"
        let broker = ProviderPluginCookieBroker(
            provider: .perplexity,
            domains: ["www.perplexity.ai"],
            settings: .init(cookieSource: .auto, manualCookieHeader: nil),
            importer: { _ in [
                ("authjs.session-token=browser-one", "Profile 1"),
                ("authjs.session-token=browser-two", "Profile 2"),
            ] })
        let requests = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime(
            "perplexity", engine: engine, transport: ProviderHTTPTransportHandler { request in
                let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
                requests.setValue(requests.value + [cookie])
                return try CookiePluginFixtures.response(
                    request, body: Self.perplexityBody, status: cookie.contains("environment") ? 200 : 403)
            })
        _ = try await runtime.fetchUsage(
            secrets: ["SESSION_COOKIE": "authjs.session-token=environment"],
            cookieSessionResolver: { domain, cachedOnly in
                try Self.isolated(service) { try broker.nextSession(domain: domain, cachedOnly: cachedOnly) }
            }, cookieSessionInvalidator: { domain, id in
                Self.isolated(service) { broker.rejectCookie(domain: domain, id: id) }
            })
        #expect(requests.value == [
            "authjs.session-token=browser-one",
            "authjs.session-token=browser-two",
            "authjs.session-token=environment",
        ])
        Self.isolated(service) { #expect(CookieHeaderCache.load(provider: .perplexity) == nil) }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `manual Qoder binds capture and legacy headers to exactly one origin`(
        engine: ProviderPluginEngineKind) async throws
    {
        for (raw, domain) in [
            ("curl https://qoder.com.cn -H 'Cookie: session=china'", "qoder.com.cn"),
            ("Cookie: session=global", "qoder.com"),
            ("session=qoder.com.cn-looking-value", "qoder.com"),
        ] {
            let hosts = LockIsolated<[String]>([])
            let runtime = try BundledPluginTestSupport.runtime(
                "qoder", engine: engine, transport: ProviderHTTPTransportHandler { request in
                    hosts.setValue(hosts.value + [request.url?.host ?? ""])
                    #expect(request.value(forHTTPHeaderField: "Origin") == "https://\(domain)")
                    #expect(request.value(forHTTPHeaderField: "Referer") == "https://\(domain)/account/usage")
                    #expect(request.value(forHTTPHeaderField: "Bx-V") == "2.5.35")
                    #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
                    #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en;q=0.9")
                    return try CookiePluginFixtures.response(request, body: Self.qoderBody)
                })
            let broker = self.manualBroker(.qoder, raw: raw)
            let usage = try await runtime.fetchUsage(
                cookieSource: .manual, cookieSessionResolver: { try broker.nextSession(domain: $0, cachedOnly: $1) })
            #expect(hosts.value == [domain])
            #expect(usage.identity?.loginMethod == "manual / \(domain)")
            #expect(QoderProviderDescriptor.dashboardURL(forSourceLabel: usage.identity?.loginMethod).host == domain)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `invalid captures never reach HTTP and manual rejection never crosses region`(
        engine: ProviderPluginEngineKind) async throws
    {
        let hosts = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime(
            "qoder", engine: engine, transport: ProviderHTTPTransportHandler { request in
                hosts.setValue(hosts.value + [request.url?.host ?? ""])
                return try CookiePluginFixtures.response(request, body: "expired", status: 403)
            })
        let invalid = self.manualBroker(
            .qoder,
            raw: "curl https://qoder.com -H 'Host: qoder.com.cn' -H 'Cookie: sid=fixture'")
        await CookiePluginFixtures.expectFailure(.missingCredential) {
            try await runtime.fetchUsage(
                cookieSource: .manual,
                cookieSessionResolver: { try invalid.nextSession(domain: $0, cachedOnly: $1) })
        }
        #expect(hosts.value.isEmpty)
        let plain = self.manualBroker(.qoder, raw: "sid=fixture")
        await CookiePluginFixtures.expectFailure(.authenticationExpired) {
            try await runtime.fetchUsage(
                cookieSource: .manual,
                cookieSessionResolver: { try plain.nextSession(domain: $0, cachedOnly: $1) })
        }
        #expect(hosts.value == ["qoder.com"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `Qoder tries domain candidates in order and retains successful region`(
        engine: ProviderPluginEngineKind) async throws
    {
        let service = "cookie-cutover-\(UUID().uuidString)"
        let broker = ProviderPluginCookieBroker(
            provider: .qoder,
            domains: ["qoder.com", "qoder.com.cn"],
            settings: .init(cookieSource: .auto, manualCookieHeader: nil),
            importer: { domain in [("session=\(domain)-one", "Profile 1"), ("session=\(domain)-two", "Profile 2")] })
        let requests = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime(
            "qoder", engine: engine, transport: ProviderHTTPTransportHandler { request in
                let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
                requests.setValue(requests.value + [cookie])
                return try CookiePluginFixtures.response(
                    request, body: Self.qoderBody, status: cookie == "session=qoder.com.cn-two" ? 200 : 401)
            })
        let usage = try await runtime.fetchUsage(
            cookieSessionResolver: { domain, cachedOnly in try Self.isolated(service) { try broker.nextSession(
                domain: domain,
                cachedOnly: cachedOnly) } },
            cookieSessionInvalidator: { domain, id in Self.isolated(service) { broker.rejectCookie(
                domain: domain,
                id: id) } })
        #expect(requests.value == [
            "session=qoder.com-one",
            "session=qoder.com-two",
            "session=qoder.com.cn-one",
            "session=qoder.com.cn-two",
        ])
        #expect(usage.identity?.loginMethod == "Profile 2 / qoder.com.cn")
        Self.isolated(service) {
            #expect(CookieHeaderCache.load(provider: .qoder, scope: .providerVariant("qoder.com")) == nil)
            #expect(CookieHeaderCache.load(provider: .qoder, scope: .providerVariant("qoder.com.cn"))?
                .cookieHeader == "session=qoder.com.cn-two")
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `session API enforces declared domain and off policy before resolving`(
        engine: ProviderPluginEngineKind) async throws
    {
        for (domain, policy) in [("undeclared.test", ProviderCookieSource.auto), ("allowed.test", .off)] {
            let runtime = try ProviderPluginRuntime(source: """
            defineProvider({id: "manus", name: "Fixture", endpoints: ["https://allowed.test"], settings: [],
              capabilities: ["browser-cookies"], cookieDomains: ["allowed.test"],
              async fetchUsage(ctx) {
                for await (const session of ctx.browser.sessions("\(domain)")) {
                  return {primary: {usedPercent: session.header.length}};
                }
                return {primary: {usedPercent: 0}};
              }
            });
            """, engine: engine)
            await #expect(throws: ProviderPluginError.self) {
                try await runtime.fetchUsage(cookieSource: policy, cookieSessionResolver: { _, _ in
                    Issue.record("Forbidden domain or disabled source must not invoke the resolver")
                    return nil
                })
            }
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `session bridge rejects mismatched origins and redacts headers and values`(
        engine: ProviderPluginEngineKind) async throws
    {
        let source = """
        defineProvider({id: "manus", name: "Fixture", endpoints: ["https://allowed.test"], settings: [],
          capabilities: ["browser-cookies"], cookieDomains: ["allowed.test", "other.test"],
          async fetchUsage(ctx) {
            for await (const session of ctx.browser.sessions("allowed.test")) {
              throw new Error(session.header + " cookie-value-fixture");
            }
            return {primary: {usedPercent: 0}};
          }
        });
        """
        for origin in ["https://allowed.test", "https://other.test"] {
            let runtime = try ProviderPluginRuntime(source: source, engine: engine)
            do {
                _ = try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
                    .init(header: "session=cookie-value-fixture", source: "Fixture", origin: origin)
                })
                Issue.record("Expected session bridge failure")
            } catch {
                #expect(!error.localizedDescription.contains("cookie-value-fixture"))
                if origin.hasSuffix("other.test") {
                    #expect(error.localizedDescription.contains("origin does not match"))
                }
            }
        }
    }

    private func manualBroker(_ provider: UsageProvider, raw: String) -> ProviderPluginCookieBroker {
        let settings: CookieProviderSettings
        let domains: Set<String>
        if provider == .qoder {
            let snapshot = ProviderSettingsSnapshot.make(qoder: .init(cookieSource: .manual, manualCookieHeader: raw))
            settings = QoderProviderDescriptor.descriptor.settingsSection.cookieSettings(from: snapshot)!
            domains = ["qoder.com", "qoder.com.cn"]
        } else {
            settings = .init(cookieSource: .manual, manualCookieHeader: raw)
            domains = ["www.perplexity.ai"]
        }
        return ProviderPluginCookieBroker(provider: provider, domains: domains, settings: settings, importer: { _ in
            Issue.record("Manual mode must never import a browser profile")
            return []
        })
    }

    private static func isolated<T>(_ service: String, operation: () throws -> T) rethrows -> T {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        return try KeychainCacheStore.withImplicitTestStoreForTesting {
            try KeychainCacheStore.withServiceOverrideForTesting(service) {
                try CookieHeaderCache.withLegacyBaseURLOverrideForTesting(base, operation: operation)
            }
        }
    }
}

extension CookieProviderCutoverTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `Qoder retains last nonauth failure when other candidates reject credentials`(
        engine: ProviderPluginEngineKind) async throws
    {
        for statuses in [[500, 401], [401, 503], [500, 400]] {
            let requests = LockIsolated(0)
            let runtime = try BundledPluginTestSupport.runtime(
                "qoder", engine: engine, transport: ProviderHTTPTransportHandler { request in
                    let index = requests.value
                    requests.setValue(index + 1)
                    return try CookiePluginFixtures.response(request, body: "fixture", status: statuses[index])
                })
            do {
                _ = try await runtime.fetchUsage(cookieResolver: { _, domain in "session=\(domain)" })
                Issue.record("Expected failed candidates")
            } catch {
                let expected = try #require(statuses.last { $0 != 401 })
                #expect(error.localizedDescription.contains("HTTP \(expected)"))
            }
            #expect(requests.value == 2)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `Qoder cancellation stops before trying another candidate`(engine: ProviderPluginEngineKind) async throws {
        for urlCancellation in [false, true] {
            let requests = LockIsolated(0)
            let runtime = try BundledPluginTestSupport.runtime(
                "qoder", engine: engine, transport: ProviderHTTPTransportHandler { _ in
                    requests.setValue(requests.value + 1)
                    if urlCancellation { throw URLError(.cancelled) }
                    throw CancellationError()
                })
            await #expect(throws: CancellationError.self) {
                try await runtime.fetchUsage(cookieResolver: { _, domain in "session=\(domain)" })
            }
            #expect(requests.value == 1)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `Perplexity null response is a terminal parse error without credential fallback`(
        engine: ProviderPluginEngineKind) async throws
    {
        let requests = LockIsolated(0)
        let runtime = try BundledPluginTestSupport.runtime(
            "perplexity", engine: engine, transport: ProviderHTTPTransportHandler { request in
                requests.setValue(requests.value + 1)
                return try CookiePluginFixtures.response(request, body: "null")
            })
        do {
            _ = try await runtime.fetchUsage(
                secrets: ["SESSION_COOKIE": "authjs.session-token=environment"],
                cookieResolver: { _, _ in "authjs.session-token=browser" })
            Issue.record("Expected malformed response")
        } catch {
            #expect(error.localizedDescription.contains("parse"))
        }
        #expect(requests.value == 1)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `Qoder rejects malformed nested quota objects`(engine: ProviderPluginEngineKind) async throws {
        for suffix in [#", "sharedQuota":false"#, #", "sharedQuota":{"quotaSummary":false}"#] {
            let body = #"{"totalQuota":{"quotaSummary":{"usedValue":1,"limitValue":2}}"# + suffix + "}"
            let runtime = try BundledPluginTestSupport.runtime(
                "qoder", engine: engine, transport: ProviderHTTPTransportHandler { request in
                    try CookiePluginFixtures.response(request, body: body)
                })
            await CookiePluginFixtures.expectFailure(.parseFailure) {
                try await runtime.fetchUsage(cookieSource: .manual, cookieResolver: { _, _ in "session=fixture" })
            }
        }
    }
}

extension CookieProviderCutoverTests {
    @Test(arguments: BundledPluginTestSupport.engines, [false, true])
    func `Qoder prioritizes regional cache before any browser import`(
        engine: ProviderPluginEngineKind,
        legacy: Bool) async throws
    {
        let service = "cookie-cutover-cache-\(UUID().uuidString)"
        Self.isolated(service) {
            if !legacy {
                CookieHeaderCache.store(
                    provider: .qoder,
                    scope: .providerVariant("qoder.com"),
                    cookieHeader: "session=older-global",
                    sourceLabel: "Profile 1",
                    now: Date().addingTimeInterval(-60))
            }
            CookieHeaderCache.store(
                provider: .qoder,
                scope: legacy ? nil : .providerVariant("qoder.com.cn"),
                cookieHeader: "session=china",
                sourceLabel: "Profile 2 / qoder.com.cn",
                now: Date())
        }
        let imports = LockIsolated(0)
        let broker = ProviderPluginCookieBroker(
            provider: .qoder,
            domains: ["qoder.com", "qoder.com.cn"],
            settings: .init(cookieSource: .auto, manualCookieHeader: nil),
            importer: { domain in
                imports.setValue(imports.value + 1)
                return [("session=\(domain)-fresh", "Profile 3")]
            })
        let hosts = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime(
            "qoder", engine: engine, transport: ProviderHTTPTransportHandler { request in
                hosts.setValue(hosts.value + [request.url!.host!])
                return try CookiePluginFixtures.response(request, body: Self.qoderBody)
            })
        let usage = try await runtime.fetchUsage(
            cookieSessionResolver: { domain, cachedOnly in
                try Self.isolated(service) { try broker.nextSession(domain: domain, cachedOnly: cachedOnly) }
            })
        #expect(hosts.value == ["qoder.com.cn"])
        #expect(imports.value == 0)
        #expect(usage.identity?.loginMethod == "Profile 2 / qoder.com.cn")
    }
}
