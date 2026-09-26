import Foundation
import Testing
@testable import CodexBarCore

struct ZedPluginTests {
    static let billing = #"""
    {"plan":"zed_pro","current_usage":{
      "token_spend":{"spend_in_cents":250,"limit_in_cents":1000},
      "edit_predictions":{"used":12,"limit":100}}}
    """#

    @Test(arguments: BundledPluginTestSupport.engines)
    func `browser billing uses its session and reports dollar spend`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "zed",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.url?.absoluteString == "https://cloud.zed.dev/frontend/billing/usage")
                #expect(request.value(forHTTPHeaderField: "Cookie") == "zed.session=fixture-session")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                return try Self.response(request, body: Self.billing)
            })
        let snapshot = try await runtime.fetchUsage(
            settings: ["SOURCE": "web"],
            cookieResolver: { _, domain in
                #expect(domain == "zed.dev")
                return "zed.session=fixture-session"
            })
        #expect(snapshot.providerCost?.used == 2.5)
        #expect(snapshot.providerCost?.limit == 10)
        #expect(snapshot.details.first?.rows.last?.value == "$7.50")
        #expect(snapshot.providerCost?.balance == nil)
        #expect(snapshot.primary?.usedPercent == 12)
        #expect(snapshot.identity?.loginMethod == "Zed Pro")
    }

    @Test(arguments: [0.0, 12.5, 250.0, 1500.0], BundledPluginTestSupport.engines)
    func `zero and overage spend keep exact amounts`(cents: Double, engine: ProviderPluginEngineKind) async throws {
        let body = Self.billing.replacingOccurrences(of: "250", with: String(cents))
        let snapshot = try await Self.fetch(body, engine: engine)
        #expect(snapshot.providerCost?.used == cents / 100)
        #expect(snapshot.details.first?.rows.last?.value == UsageFormatter.usdString(max(0, 10 - cents / 100)))
    }

    @Test(arguments: ["null", "missing"], BundledPluginTestSupport.engines)
    func `unlimited predictions and missing spend cap do not invent limits`(
        cap: String, engine: ProviderPluginEngineKind) async throws
    {
        let billing = cap == "missing"
            ? Self.billing.replacingOccurrences(of: ",\"limit_in_cents\":1000", with: "")
            : Self.billing.replacingOccurrences(of: "1000", with: "null")
        let body = billing.replacingOccurrences(of: "\"limit\":100", with: "\"limit\":null")
        let snapshot = try await Self.fetch(body, engine: engine)
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.details.first?.rows.first?.usageValue == 2.5)
        #expect(snapshot.details.first?.rows.last?.value == "Not reported")
        #expect(snapshot.providerCost?.balance == nil)
        #expect(snapshot.primary?.resetDescription == "Unlimited")
    }

    @Test(
        arguments: [
            "{}",
            "[]",
            "<html>login</html>",
            Self.billing.replacingOccurrences(of: "250", with: "-1"),
            Self.billing.replacingOccurrences(of: "250", with: "true"),
            Self.billing.replacingOccurrences(of: "250", with: "9007199254740992"),
            Self.billing.replacingOccurrences(of: "1000", with: "-1"),
            Self.billing.replacingOccurrences(of: "\"plan\":\"zed_pro\"", with: "\"plan\":{}"),
        ],
        BundledPluginTestSupport.engines)
    func `drifted and unsafe billing values fail without publishing totals`(
        body: String, engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(.parseFailure) { try await Self.fetch(body, engine: engine) }
    }

    @Test(arguments: [401, 403], BundledPluginTestSupport.engines)
    func `expired sessions invalidate only the declared Zed cookie`(
        status: Int, engine: ProviderPluginEngineKind) async throws
    {
        let invalidated = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime(
            "zed",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                try Self.response(
                    request,
                    body: "<html>login</html>",
                    status: status)
            })
        await Self.expectFailure(.authenticationExpired) {
            try await runtime.fetchUsage(
                settings: ["SOURCE": "web"],
                cookieInvalidator: { domain in invalidated.setValue(invalidated.value + [domain]) },
                cookieResolver: { _, _ in "zed.session=fixture-session" })
        }
        #expect(invalidated.value == ["zed.dev"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `disabled browser source never imports cookies or sends a request`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try BundledPluginTestSupport.runtime(
            "zed",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                Issue.record("Unexpected request")
                return try Self.response(request, body: Self.billing)
            })
        await Self.expectFailure(.missingCredential) {
            try await runtime.fetchUsage(
                settings: ["SOURCE": "web"],
                cookieSource: .off,
                cookieResolver: { _, _ in
                    Issue.record("Unexpected cookie import")
                    return "zed.session=fixture-session"
                })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `editor payload retains identity quota billing dates and overdue warning`(
        engine: ProviderPluginEngineKind) async throws
    {
        let data = ZedStatusProbeTests.fixture(
            plan: "zed_pro_trial",
            used: 10,
            limit: "{\"limited\":20}",
            overdue: true)
        let body = try #require(String(data: data, encoding: .utf8))
        let runtime = try BundledPluginTestSupport.runtime(
            "zed",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.url?
                    .absoluteString ==
                    "https://zed.example.com/client/users/me")
                #expect(request
                    .value(forHTTPHeaderField: "Authorization") ==
                    "4242 fixture-token")
                #expect(request
                    .value(forHTTPHeaderField: "Cookie") == nil)
                return try Self.response(request, body: body)
            })
        let snapshot = try await runtime.fetchUsage(
            settings: ["API_URL": "https://zed.example.com/client/users/me"],
            secrets: ["EDITOR_AUTH": "4242 fixture-token"],
            sourceMode: .api,
            cookieResolver: { _, _ in
                Issue.record("Editor source imported cookies")
                return "zed.session=fixture-session"
            })
        #expect(snapshot.identity?.accountEmail == "octocat")
        #expect(snapshot.identity?.accountOrganization == "The Octocat")
        #expect(snapshot.identity?.loginMethod == "Zed Pro Trial")
        #expect(snapshot.primary?.usedPercent == 50)
        #expect(snapshot.primary?.resetDescription == "10 / 20 predictions")
        #expect(snapshot.secondary?.resetDescription == "Cycle ended")
        #expect(snapshot.subscriptionRenewsAt == snapshot.secondary?.resetsAt)
        #expect(snapshot.extraRateWindows?.first?.usageKnown == false)
        #expect(snapshot.providerCost == nil)
    }

    @Test
    func `CLI cookie settings require an explicit opt in`() throws {
        let registration = ZedProviderDescriptor.descriptor.settingsSection
        for (config, expected) in [
            (ProviderConfig(id: .zed), ProviderCookieSource.off),
            (ProviderConfig(id: .zed, cookieHeader: "zed.session=fixture"), .manual),
            (ProviderConfig(id: .zed, cookieHeader: "zed.session=fixture", cookieSource: .off), .off),
            (ProviderConfig(id: .zed, cookieSource: .auto), .auto),
        ] {
            let contribution = try #require(registration.credentialContribution(context: .init(
                config: config,
                account: nil)))
            let settings = ProviderSettingsSnapshot(contributions: [contribution])
            #expect(settings[ZedProviderSettingsKey.self]?.cookieSource == expected)
        }
    }

    static func fetch(_ body: String, engine: ProviderPluginEngineKind) async throws -> UsageSnapshot {
        let runtime = try BundledPluginTestSupport.runtime(
            "zed",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                try Self.response(
                    request,
                    body: body)
            })
        return try await runtime.fetchUsage(
            settings: ["SOURCE": "web"],
            cookieResolver: { _, _ in "zed.session=fixture-session" })
    }

    static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind,
        operation: () async throws -> UsageSnapshot) async
    {
        do {
            _ = try await operation()
            Issue.record("Expected \(kind)")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == kind)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    static func response(_ request: URLRequest, body: String, status: Int = 200) throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), response)
    }
}
