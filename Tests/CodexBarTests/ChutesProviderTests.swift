import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ChutesProviderTests {
    @Test
    func `descriptor uses the bundled plugin without an opt-in flag`() async throws {
        let context = Self.context(environment: ["CHUTES_API_KEY": "fixture-key"])
        let strategies = await ChutesProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(context)
        #expect(strategies.count == 1)
        let strategy = try #require(strategies.first)
        #expect(strategy is ScriptFetchStrategy)
        #expect(strategy.id == "chutes.js")
        #expect(await strategy.isAvailable(context))
    }

    @Test
    func `settings reader trims quoted API key`() {
        let token = ChutesSettingsReader.apiKey(environment: [
            ChutesSettingsReader.apiKeyEnvironmentKey: " 'chutes-test' ",
        ])

        #expect(token == "chutes-test")
    }

    @Test
    func `config API key projects into Chutes environment`() {
        let config = ProviderConfig(id: .chutes, apiKey: "chutes-config-token")
        let env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: [:],
            provider: .chutes,
            config: config)

        #expect(env[ChutesSettingsReader.apiKeyEnvironmentKey] == "chutes-config-token")
        #expect(ChutesSettingsReader.apiKey(environment: env) == "chutes-config-token")
        #expect(ProviderConfigEnvironment.supportsAPIKeyOverride(for: .chutes))
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `fetch usage maps active subscription monthly and rolling windows`(
        engine: ProviderPluginEngineKind) async throws
    {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rollingReset = try Self.date("2026-06-13T18:00:00Z")
        let monthlyReset = try Self.date("2026-07-01T00:00:00Z")
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            #expect(url.path == "/users/me/subscription_usage")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer chutes-key")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.timeoutInterval == 15)

            let body = #"""
            {
              "subscription": {
                "active": true,
                "plan_name": "Pro",
                "current_period_end": "2026-07-01T00:00:00Z"
              },
              "monthly": {
                "used": 250,
                "limit": 1000,
                "resets_at": "2026-07-01T00:00:00Z",
                "unit": "credits"
              },
              "rolling_window": {
                "requests": 40,
                "limit": 100,
                "window_minutes": 240,
                "reset_at": "2026-06-13T18:00:00Z",
                "unit": "requests"
              }
            }
            """#
            return Self.makeResponse(url: url, body: body)
        }

        let snapshot = try await Self.fetch(
            engine: engine,
            apiKey: " chutes-key ",
            environment: [ChutesSettingsReader
                .apiURLEnvironmentKey: "https://chutes.test"],
            transport: transport,
            now: now)
        let usage = snapshot

        #expect(usage.primary?.usedPercent == 40)
        #expect(usage.primary?.windowMinutes == 240)
        #expect(usage.primary?.resetsAt == rollingReset)
        #expect(usage.primary?.resetDescription == "40/100 requests")
        #expect(usage.secondary?.usedPercent == 25)
        #expect(usage.secondary?.resetsAt == monthlyReset)
        #expect(usage.secondary?.resetDescription == "250/1000 credits")
        #expect(usage.subscriptionRenewsAt == monthlyReset)
        #expect(usage.loginMethod(for: .chutes) == "Pro")

        let requests = await transport.requests()
        #expect(requests.count == 1)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `no active subscription falls back to quotas endpoint`(engine: ProviderPluginEngineKind) async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            switch url.path {
            case "/users/me/subscription_usage":
                return Self.makeResponse(url: url, body: #"""
                {
                  "subscription": {
                    "active": false,
                    "status": "free"
                  }
                }
                """#)
            case "/users/me/quotas":
                return Self.makeResponse(url: url, body: #"""
                [
                  {
                    "chute_id": "0",
                    "is_default": true,
                    "quota": 100
                  }
                ]
                """#)
            case "/users/me/quota_usage/0":
                return Self.makeResponse(url: url, body: #"""
                {
                  "quota": 100,
                  "used": 10
                }
                """#)
            default:
                throw URLError(.badURL)
            }
        }

        let snapshot = try await Self.fetch(
            engine: engine,
            apiKey: "chutes-key",
            environment: [ChutesSettingsReader
                .apiURLEnvironmentKey: "https://chutes.test"],
            transport: transport,
            now: now)
        let usage = snapshot

        #expect(usage.primary?.usedPercent == 10)
        #expect(usage.primary?.resetDescription == "10/100 credits")
        #expect(usage.secondary == nil)
        #expect(usage.loginMethod(for: .chutes) == "No active subscription")

        let requests = await transport.requests()
        let paths = requests.compactMap { $0.url?.path }
        #expect(paths == [
            "/users/me/subscription_usage",
            "/users/me/quotas",
            "/users/me/quota_usage/0",
        ])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `wrapped quota list fetches per quota usage`(engine: ProviderPluginEngineKind) async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            switch url.path {
            case "/users/me/subscription_usage":
                return Self.makeResponse(url: url, body: #"{"subscription":{"active":false}}"#)
            case "/users/me/quotas":
                return Self.makeResponse(url: url, body: #"""
                {
                  "quotas": {"metadata": true},
                  "data": [
                    {
                      "chute_id": "wrapped",
                      "quota": 200
                    }
                  ]
                }
                """#)
            case "/users/me/quota_usage/wrapped":
                return Self.makeResponse(url: url, body: #"{"quota":200,"used":50}"#)
            default:
                throw URLError(.badURL)
            }
        }

        let snapshot = try await Self.fetch(
            engine: engine,
            apiKey: "chutes-key",
            environment: [ChutesSettingsReader
                .apiURLEnvironmentKey: "https://chutes.test"],
            transport: transport)

        #expect(snapshot.primary?.usedPercent == 25)
        let requests = await transport.requests()
        #expect(requests.compactMap { $0.url?.path } == [
            "/users/me/subscription_usage",
            "/users/me/quotas",
            "/users/me/quota_usage/wrapped",
        ])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `partial subscription usage fills missing rolling window from quotas`(
        engine: ProviderPluginEngineKind) async throws
    {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            switch url.path {
            case "/users/me/subscription_usage":
                return Self.makeResponse(url: url, body: #"""
                {
                  "subscription": {
                    "active": true,
                    "plan_name": "Pro",
                    "current_period_end": "2026-07-01T00:00:00Z"
                  },
                  "monthly": {
                    "used": 250,
                    "limit": 1000,
                    "unit": "credits"
                  }
                }
                """#)
            case "/users/me/quotas":
                return Self.makeResponse(url: url, body: #"""
                {
                  "rolling_window": {
                    "requests": 40,
                    "limit": 100,
                    "window_minutes": 240,
                    "unit": "requests"
                  }
                }
                """#)
            default:
                throw URLError(.badURL)
            }
        }

        let snapshot = try await Self.fetch(
            engine: engine,
            apiKey: "chutes-key",
            environment: [ChutesSettingsReader
                .apiURLEnvironmentKey: "https://chutes.test"],
            transport: transport,
            now: now)
        let usage = snapshot

        #expect(usage.primary?.usedPercent == 40)
        #expect(usage.primary?.windowMinutes == 240)
        #expect(usage.primary?.resetDescription == "40/100 requests")
        #expect(usage.secondary?.usedPercent == 25)
        #expect(usage.secondary?.resetDescription == "250/1000 credits")
        #expect(usage.loginMethod(for: .chutes) == "Pro")

        let requests = await transport.requests()
        let paths = requests.compactMap { $0.url?.path }
        #expect(paths == ["/users/me/subscription_usage", "/users/me/quotas"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `missing usage fields returns no data snapshot without decode failure`(
        engine: ProviderPluginEngineKind) async throws
    {
        let data = Data(#"{"subscription":{"active":true},"unexpected":{"nested":true}}"#.utf8)
        let snapshot = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        let usage = snapshot

        #expect(!usage.hasRateLimitWindows)
        #expect(usage.primary == nil)
        #expect(usage.secondary == nil)
        #expect(usage.loginMethod(for: .chutes) == nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `identical usage values keep distinct quota windows`(engine: ProviderPluginEngineKind) async throws {
        let data = Data(#"""
        {
          "quotas": [
            {
              "used": 0,
              "limit": 100,
              "window_minutes": 240
            },
            {
              "used": 0,
              "limit": 100,
              "window_minutes": 43200
            }
          ]
        }
        """#.utf8)

        let snapshot = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        let usage = snapshot

        #expect(usage.primary?.usedPercent == 0)
        #expect(usage.primary?.windowMinutes == 240)
        #expect(usage.secondary?.usedPercent == 0)
        #expect(usage.secondary?.windowMinutes == 43200)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `large quota amounts retain their percentage and description`(engine: ProviderPluginEngineKind) async throws {
        let data = Data(#"""
        {"rolling_window":{"used":1e20,"limit":2e20,"unit":"credits"}}
        """#.utf8)

        let snapshot = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        let usage = snapshot

        #expect(usage.primary?.usedPercent == 50)
        #expect(usage.primary?.resetDescription == "100000000000000000000/200000000000000000000 credits")
    }

    @Test(arguments: BundledPluginTestSupport.engines, [
        ("window_minutes", "9223372036854775808"),
        ("window_hours", "1e308"),
        ("window_days", "1e308"),
        ("window_seconds", "1e308"),
        ("window", #""1e308 minutes""#),
        ("window", #""1e308 hours""#),
        ("window", #""1e308 days""#),
        ("window", #""1e308 months""#),
    ])
    func `unrepresentable durations preserve usage with the known window default`(
        engine: ProviderPluginEngineKind, duration: (String, String)) async throws
    {
        let (key, value) = duration
        let data = Data("""
        {"rolling_window":{"used":25,"limit":100,"\(key)":\(value)}}
        """.utf8)

        let snapshot = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        let usage = snapshot

        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.windowMinutes == 240)
        #expect(usage.primary?.resetDescription == "25/100 credits")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `unrepresentable generic quota duration remains unknown`(engine: ProviderPluginEngineKind) async throws {
        let data = Data(#"""
        {"quotas":[{"used":25,"limit":100,"window_minutes":9223372036854775808}]}
        """#.utf8)

        let snapshot = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        let usage = snapshot

        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.windowMinutes == nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `exact percent value of one stays one percent`(engine: ProviderPluginEngineKind) async throws {
        let usedData = Data(#"""
        {
          "rolling_window": {
            "usage_percent": 1
          }
        }
        """#.utf8)
        let remainingData = Data(#"""
        {
          "rolling_window": {
            "percent_remaining": 1
          }
        }
        """#.utf8)

        let usedSnapshot = try await Self.parse(
            engine: engine,
            data: usedData,
            now: Date(timeIntervalSince1970: 123))
        let remainingSnapshot = try await Self.parse(
            engine: engine,
            data: remainingData,
            now: Date(timeIntervalSince1970: 123))

        #expect(usedSnapshot.primary?.usedPercent == 1)
        #expect(remainingSnapshot.primary?.usedPercent == 99)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `auth failure surfaces invalid credentials`(engine: ProviderPluginEngineKind) async {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.makeResponse(url: url, body: #"{"detail":"unauthorized"}"#, statusCode: 401)
        }

        await #expect {
            _ = try await Self.fetch(
                engine: engine,
                apiKey: "bad-key",
                environment: [ChutesSettingsReader.apiURLEnvironmentKey: "https://chutes.test"],
                transport: transport)
        } throws: { error in
            (error as? ProviderFetchClassifiedError)?.kind == .authenticationExpired
        }
    }

    @Test
    func `descriptor and app implementation registry include Chutes`() throws {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .chutes)
        #expect(descriptor.metadata.displayName == "Chutes")
        #expect(ProviderDescriptorRegistry.all.contains { $0.id == .chutes })

        let implementation = try #require(ProviderCatalog.implementation(for: .chutes))
        #expect(implementation is ChutesProviderImplementation)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `quota enrichment is best effort except for rejected credentials`(
        engine: ProviderPluginEngineKind) async throws
    {
        for failingPath in ["quotas", "quota_usage/fixture"] {
            for code in [403, 500] {
                let transport = ProviderHTTPTransportStub { request in
                    let url = try #require(request.url)
                    if url.path.hasSuffix(failingPath) {
                        return Self.makeResponse(url: url, body: "upstream error", statusCode: code)
                    }
                    let body = url.path.hasSuffix("subscription_usage")
                        ? #"{"subscription":{"active":false}}"#
                        : #"{"quotas":[{"chute_id":"fixture","limit":100}]}"#
                    return Self.makeResponse(url: url, body: body)
                }
                if code == 403 {
                    await #expect {
                        _ = try await Self.fetch(
                            engine: engine,
                            apiKey: "fixture-key",
                            environment: [:],
                            transport: transport)
                    } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .authenticationExpired }
                } else {
                    let usage = try await Self.fetch(
                        engine: engine,
                        apiKey: "fixture-key",
                        environment: [:],
                        transport: transport)
                    #expect(!usage.hasRateLimitWindows)
                    #expect(usage.loginMethod(for: .chutes) == "No active subscription")
                    #expect(await transport.requests().count == (failingPath == "quotas" ? 2 : 3))
                }
            }
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `configured base path and query survive endpoint construction`(engine: ProviderPluginEngineKind) async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            #expect(url.host == "chutes.test")
            #expect(url.path.hasPrefix("/proxy/users/me/"))
            #expect(url.query == "tenant=fixture")
            return Self.makeResponse(url: url, body: "{}")
        }
        let usage = try await Self.fetch(
            engine: engine,
            apiKey: "fixture-key",
            environment: ["CHUTES_API_URL": "https://chutes.test/proxy?tenant=fixture"],
            transport: transport)
        #expect(usage.loginMethod(for: .chutes) == "No usage data")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `invalid subscription JSON fails but optional invalid JSON does not`(
        engine: ProviderPluginEngineKind) async throws
    {
        for required in [true, false] {
            let transport = ProviderHTTPTransportStub { request in
                let url = try #require(request.url)
                return Self.makeResponse(url: url, body: required || url.path.hasSuffix("quotas") ? "not JSON" : "{}")
            }
            if required {
                await #expect {
                    _ = try await Self.fetch(
                        engine: engine,
                        apiKey: "fixture-key",
                        environment: [:],
                        transport: transport)
                } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .parseFailure }
            } else {
                let usage = try await Self.fetch(
                    engine: engine,
                    apiKey: "fixture-key",
                    environment: [:],
                    transport: transport)
                #expect(!usage.hasRateLimitWindows)
            }
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `very large amounts keep the represented integer digits`(engine: ProviderPluginEngineKind) async throws {
        let data = Data(#"""
        {"rolling":{"used":1e25,"limit":2e25}}
        """#.utf8)
        let usage = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        let expected = String(format: "%.0f/%.0f credits", 1e25, 2e25)
        #expect(usage.primary?.usedPercent == 50)
        #expect(usage.primary?.resetDescription == expected)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `normalized aliases fractions and epoch resets preserve quota projection`(
        engine: ProviderPluginEngineKind) async throws
    {
        let data = Data(#"""
        {"result":{"plan_name":"Fixture","rolling_4h":{"used_percent":"0.25","reset_at":"1800000000000"},
        "billing_period":{"remaining":"$1,500","cap":"2,000","duration":"1 month"}}}
        """#.utf8)
        let usage = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(usage.secondary?.usedPercent == 25)
        #expect(usage.secondary?.resetDescription == "500/2000 credits")
        #expect(usage.secondary?.windowMinutes == 43200)
        #expect(usage.loginMethod(for: .chutes) == "Fixture")
    }

    @Test
    func `missing credentials fail before transport`() async {
        let context = Self.context(environment: [:])
        let transport = ProviderHTTPTransportStub { _ in throw ProviderPluginError.script("unexpected request") }
        let strategy = ChutesProviderDescriptor.scriptStrategy(transport: transport)
        #expect(await strategy.isAvailable(context) == false)
        await #expect {
            _ = try await strategy.fetch(context)
        } throws: { ($0 as? ProviderFetchClassifiedError)?.kind == .missingCredential }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `large integer amounts preserve native digits`(engine: ProviderPluginEngineKind) async throws {
        let data = Data(#"""
        {"rolling":{"used":1234567890123456789,"limit":2469135780246913578}}
        """#.utf8)
        let usage = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        #expect(usage.primary?.resetDescription == "1234567890123456768/2469135780246913536 credits")
    }

    @Test
    func `insecure endpoint override fails before transport`() async {
        let context = Self.context(environment: [
            "CHUTES_API_KEY": "fixture-key",
            "CHUTES_API_URL": "http://chutes.test",
        ])
        let transport = ProviderHTTPTransportStub { _ in throw ProviderPluginError.script("unexpected request") }
        let strategy = ChutesProviderDescriptor.scriptStrategy(transport: transport)
        await #expect {
            _ = try await strategy.fetch(context)
        } throws: { $0 as? ChutesSettingsError == .invalidEndpointOverride("CHUTES_API_URL") }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `distinct raw quotas with equal percentages remain separate`(engine: ProviderPluginEngineKind) async throws {
        let data = Data(#"""
        {"quotas":[{"used":25,"remaining":75,"window_minutes":240},
        {"used":50,"remaining":150,"window_minutes":240}]}
        """#.utf8)
        let usage = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.secondary?.usedPercent == 25)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `fractional amounts round like native printf`(engine: ProviderPluginEngineKind) async throws {
        for (value, expected) in [
            (1.125, "1.12"),
            (1.375, "1.38"),
            (1.625, "1.62"),
            (-1.125, "-1.12"),
            (49.585, "49.59"),
        ] {
            let data = Data("""
            {"rolling":{"used":\(value),"limit":100}}
            """.utf8)
            let usage = try await Self.parse(engine: engine, data: data, now: Date(timeIntervalSince1970: 123))
            #expect(usage.primary?.resetDescription == "\(expected)/100 credits")
        }
    }

    private static func context(environment: [String: String]) -> ProviderFetchContext {
        let browser = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: .api,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browser, environment: [:]),
            browserDetection: browser)
    }

    private static func fetch(
        engine: ProviderPluginEngineKind,
        apiKey: String,
        environment: [String: String],
        transport: any ProviderHTTPTransport,
        now: Date = Date()) async throws -> UsageSnapshot
    {
        let runtime = try BundledPluginTestSupport.runtime("chutes", engine: engine, transport: transport)
        return try await runtime.fetchUsage(
            settings: ["BASE_URL": ChutesSettingsReader.apiURL(environment: environment).absoluteString],
            secrets: ["CHUTES_API_KEY": apiKey.trimmingCharacters(in: .whitespacesAndNewlines)],
            now: now)
    }

    private static func parse(
        engine: ProviderPluginEngineKind,
        data: Data,
        now: Date) async throws -> UsageSnapshot
    {
        let body = try #require(String(data: data, encoding: .utf8))
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            return Self.makeResponse(
                url: url,
                body: url.path.hasSuffix("subscription_usage")
                    ? body : "{}")
        }
        return try await Self.fetch(
            engine: engine, apiKey: "fixture-key", environment: [:], transport: transport, now: now)
    }

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int = 200) -> (Data, URLResponse)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }

    private static func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try #require(formatter.date(from: text))
    }
}
