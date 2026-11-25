import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct AlibabaTokenPlanWebStrategyTests {
    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String {
            "stub"
        }

        func detectVersion() -> String? {
            nil
        }
    }

    @Test
    func `Auto tries the Bailian CLI first then falls back to Web while explicit modes stay strict`() async throws {
        let auto = await AlibabaTokenPlanProviderDescriptor.resolveStrategies(
            context: self.context(region: .chinaMainlandPersonal, sourceMode: .auto))
        let cli = await AlibabaTokenPlanProviderDescriptor.resolveStrategies(
            context: self.context(region: .chinaMainlandPersonal, sourceMode: .cli))
        let web = await AlibabaTokenPlanProviderDescriptor.resolveStrategies(
            context: self.context(region: .chinaMainlandPersonal, sourceMode: .web))

        #expect(auto.map(\.id) == ["alibaba-token-plan.cli", "alibaba-token-plan.web"])
        #expect(cli.map(\.id) == ["alibaba-token-plan.cli"])
        #expect(web.map(\.id) == ["alibaba-token-plan.web"])
        let cliStrategy = AlibabaTokenPlanCLIFetchStrategy { _, _ in
            throw AlibabaTokenPlanCLIUsageError.commandFailed
        }
        #expect(cliStrategy.shouldFallback(
            on: AlibabaTokenPlanCLIUsageError.commandFailed,
            context: self.context(region: .chinaMainlandPersonal, sourceMode: .auto)))
        #expect(!cliStrategy.shouldFallback(
            on: AlibabaTokenPlanCLIUsageError.commandFailed,
            context: self.context(region: .chinaMainlandPersonal, sourceMode: .cli)))
        let webStrategy = AlibabaTokenPlanWebFetchStrategy { _, _, _ in
            throw AlibabaTokenPlanUsageError.networkError("stub")
        }
        #expect(webStrategy.shouldFallback(
            on: AlibabaTokenPlanUsageError.networkError("stub"),
            context: self.context(region: .chinaMainlandPersonal, sourceMode: .auto)))
        #expect(!webStrategy.shouldFallback(
            on: AlibabaTokenPlanUsageError.networkError("stub"),
            context: self.context(region: .chinaMainlandPersonal, sourceMode: .web)))

        let success = AlibabaTokenPlanCLIFetchStrategy { region, _ in
            #expect(region == .chinaMainlandPersonal)
            return AlibabaTokenPlanUsageSnapshot(
                planName: "Token Plan",
                usedQuota: nil,
                totalQuota: nil,
                remainingQuota: nil,
                resetsAt: nil,
                weeklyUsedPercent: 70,
                updatedAt: Date(timeIntervalSince1970: 1_787_000_000))
        }
        let result = try await success.fetch(
            self.context(region: .chinaMainlandPersonal, sourceMode: .cli))
        #expect(result.sourceLabel == "cli")
        #expect(result.strategyID == "alibaba-token-plan.cli")
    }

    @MainActor
    @Test
    func `unset source defaults to CLI first Auto and explicit Web remains strict`() async {
        let suite = "AlibabaTokenPlanWebStrategyTests-legacy-\(UUID().uuidString)"
        let settings = testSettingsStore(
            suiteName: suite,
            config: CodexBarConfig(providers: [ProviderConfig(id: .alibabatokenplan)]))

        #expect(settings.alibabaTokenPlanUsageDataSource == .auto)
        #expect(settings.configSnapshot.providerConfig(for: .alibabatokenplan)?.source == nil)
        let legacy = await AlibabaTokenPlanProviderDescriptor.resolveStrategies(
            context: self.context(
                region: .chinaMainlandPersonal,
                sourceMode: settings.alibabaTokenPlanUsageDataSource))
        #expect(legacy.map(\.id) == ["alibaba-token-plan.cli", "alibaba-token-plan.web"])

        settings.alibabaTokenPlanUsageDataSource = .web
        #expect(settings.alibabaTokenPlanUsageDataSource == .web)
        #expect(settings.configSnapshot.providerConfig(for: .alibabatokenplan)?.source == .web)
        let web = await AlibabaTokenPlanProviderDescriptor.resolveStrategies(
            context: self.context(
                region: .chinaMainlandPersonal,
                sourceMode: settings.alibabaTokenPlanUsageDataSource))
        #expect(web.map(\.id) == ["alibaba-token-plan.web"])
    }

    @Test
    func `Auto pipeline falls back to account scoped manual cookies after unavailable CLI`() async throws {
        try await self.withIsolatedCookieCache {
            let region = AlibabaTokenPlanAPIRegion.chinaMainlandPersonal
            let cli = AlibabaTokenPlanCLIFetchStrategy { _, _ in
                throw AlibabaTokenPlanCLIUsageError.unavailable
            }
            let web = AlibabaTokenPlanWebFetchStrategy { headers, selectedRegion, _ in
                #expect(selectedRegion == region)
                #expect(headers.apiCookieHeader == "login_aliyunid_ticket=fixture")
                return AlibabaTokenPlanUsageSnapshot(
                    planName: "Token Plan",
                    usedQuota: nil,
                    totalQuota: nil,
                    remainingQuota: nil,
                    resetsAt: nil,
                    weeklyUsedPercent: 42,
                    updatedAt: Date(timeIntervalSince1970: 1_787_000_000))
            }
            let pipeline = ProviderFetchPipeline(resolveStrategies: { _ in [cli, web] })
            let context = self.context(
                region: region,
                sourceMode: .auto,
                cookieSource: .manual,
                manualCookieHeader: "login_aliyunid_ticket=fixture")

            let outcome = await pipeline.fetch(context: context, provider: .alibabatokenplan)
            let result = try outcome.result.get()

            #expect(outcome.attempts.map(\.strategyID) == ["alibaba-token-plan.cli", "alibaba-token-plan.web"])
            #expect(result.sourceLabel == "web")
            #expect(result.usage.secondary?.usedPercent == 42)
        }
    }

    private func clearCookieCaches() {
        CookieHeaderCache.clear(provider: .alibabatokenplan)
        for region in AlibabaTokenPlanAPIRegion.allCases {
            CookieHeaderCache.clear(provider: .alibabatokenplan, scope: region.cookieCacheScope)
        }
    }

    @Test
    func `Auto falls back to browser cookies when the Team CLI has no seats`() async throws {
        try await self.withIsolatedCookieCache {
            let region = AlibabaTokenPlanAPIRegion.chinaMainland
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let cli = AlibabaTokenPlanCLIFetchStrategy { _, _ in
                let page = try AlibabaTokenPlanCLIUsageParser.teamPage(Data(#"""
                {"Success":true,"Data":{"Items":[],"Total":0,"PageNo":1,"PageSize":10}}
                """#.utf8), pageNo: 1)
                return try AlibabaTokenPlanCLIUsageParser.teamUsage([page], now: now)
            }
            let web = AlibabaTokenPlanWebFetchStrategy { headers, selectedRegion, _ in
                #expect(selectedRegion == region)
                #expect(headers.apiCookieHeader == "login_aliyunid_ticket=fixture")
                return AlibabaTokenPlanUsageSnapshot(
                    planName: "Token Plan",
                    usedQuota: 30,
                    totalQuota: 100,
                    remainingQuota: 70,
                    resetsAt: nil,
                    updatedAt: now)
            }
            let pipeline = ProviderFetchPipeline(resolveStrategies: { _ in [cli, web] })
            let context = self.context(
                region: region,
                sourceMode: .auto,
                cookieSource: .manual,
                manualCookieHeader: "login_aliyunid_ticket=fixture")

            let outcome = await pipeline.fetch(context: context, provider: .alibabatokenplan)
            let result = try outcome.result.get()

            #expect(outcome.attempts.map(\.strategyID) == ["alibaba-token-plan.cli", "alibaba-token-plan.web"])
            #expect(result.sourceLabel == "web")
            #expect(result.usage.primary?.usedPercent == 30)
        }
    }

    @Test
    func `workspace permission failure preserves cached browser cookies`() async throws {
        try await self.withIsolatedCookieCache {
            self.clearCookieCaches()
            defer { self.clearCookieCaches() }

            let region = AlibabaTokenPlanAPIRegion.chinaMainlandPersonal
            let headers = AlibabaTokenPlanCookieHeaders(
                apiCookieHeader: "login_aliyunid_ticket=api-fixture",
                dashboardCookieHeader: "login_aliyunid_ticket=dashboard-fixture",
                rateLimitCookieHeader: "login_aliyunid_ticket=rate-limit-fixture")
            CookieHeaderCache.store(
                provider: .alibabatokenplan,
                scope: region.cookieCacheScope,
                cookieHeader: headers.cacheCookieHeader,
                sourceLabel: "Personal fixture")

            let strategy = AlibabaTokenPlanWebFetchStrategy { resolved, _, _ in
                #expect(resolved.apiCookieHeader == headers.apiCookieHeader)
                #expect(resolved.dashboardCookieHeader == headers.dashboardCookieHeader)
                #expect(resolved.rateLimitCookieHeader == headers.rateLimitCookieHeader)
                throw AlibabaTokenPlanUsageError.apiError("BailianGateway.Workspace.NotAuthorised")
            }

            let rejectImport: (BrowserDetection, ((String) -> Void)?) throws
                -> AlibabaCodingPlanCookieImporter.SessionInfo = { _, _ in
                    Issue.record("A workspace permission error must not trigger browser import")
                    throw AlibabaCodingPlanSettingsError.missingCookie(details: "unexpected import")
                }
            try await AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting(rejectImport) {
                await #expect(throws: AlibabaTokenPlanUsageError.apiError(
                    "BailianGateway.Workspace.NotAuthorised"))
                {
                    _ = try await strategy.fetch(self.context(region: region))
                }
            }
            #expect(CookieHeaderCache.load(
                provider: .alibabatokenplan,
                scope: region.cookieCacheScope)?.cookieHeader == headers.cacheCookieHeader)
        }
    }

    @Test
    func `auto web strategy surfaces cookie import errors`() async throws {
        try await self.withIsolatedCookieCache {
            let strategy = AlibabaTokenPlanWebFetchStrategy()
            let settings = ProviderSettingsSnapshot.make(
                alibabaTokenPlan: ProviderSettingsSnapshot.AlibabaTokenPlanProviderSettings(
                    cookieSource: .auto,
                    manualCookieHeader: nil))
            let context = ProviderFetchContext(
                runtime: .cli,
                sourceMode: .web,
                includeCredits: false,
                webTimeout: 1,
                webDebugDumpHTML: false,
                verbose: false,
                env: [:],
                settings: settings,
                fetcher: UsageFetcher(environment: [:]),
                claudeFetcher: StubClaudeFetcher(),
                browserDetection: BrowserDetection(cacheTTL: 0))

            self.clearCookieCaches()
            defer { self.clearCookieCaches() }

            try await AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
                throw AlibabaCodingPlanSettingsError.missingCookie(
                    details: "macOS Keychain denied access to Chrome Safe Storage.")
            } operation: {
                #expect(await strategy.isAvailable(context))

                do {
                    _ = try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeader(context: context, allowCached: false)
                    Issue.record("Expected cookie import failure to be surfaced")
                } catch let error as AlibabaTokenPlanSettingsError {
                    guard case let .missingCookie(details) = error else {
                        Issue.record("Expected missingCookie, got \(error)")
                        return
                    }
                    #expect(details == "macOS Keychain denied access to Chrome Safe Storage.")
                    #expect(error.localizedDescription.contains("Alibaba Token Plan"))
                    #expect(!error.localizedDescription.contains("Alibaba Coding Plan"))
                }
            }
        }
    }

    @Test
    func `auto web strategy imports subscription scoped token plan cookies`() throws {
        try self.withIsolatedCookieCache {
            let strategy = AlibabaTokenPlanWebFetchStrategy()
            let settings = ProviderSettingsSnapshot.make(
                alibabaTokenPlan: ProviderSettingsSnapshot.AlibabaTokenPlanProviderSettings(
                    cookieSource: .auto,
                    manualCookieHeader: nil))
            let context = ProviderFetchContext(
                runtime: .cli,
                sourceMode: .web,
                includeCredits: false,
                webTimeout: 1,
                webDebugDumpHTML: false,
                verbose: false,
                env: [:],
                settings: settings,
                fetcher: UsageFetcher(environment: [:]),
                claudeFetcher: StubClaudeFetcher(),
                browserDetection: BrowserDetection(cacheTTL: 0))

            self.clearCookieCaches()
            defer { self.clearCookieCaches() }

            let headers = try AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
                AlibabaCodingPlanCookieImporter.SessionInfo(
                    cookies: [
                        self.cookie(name: "login_aliyunid_ticket", value: "ticket", domain: ".alibabacloud.com"),
                        self.cookie(name: "login_current_pk", value: "account", domain: ".alibabacloud.com"),
                        self.cookie(
                            name: "dashboard_only",
                            value: "dashboard",
                            domain: "modelstudio.console.alibabacloud.com"),
                        self.cookie(
                            name: "bailian_only",
                            value: "bailian",
                            domain: "bailian.console.aliyun.com"),
                        self.cookie(name: "aliyun_only", value: "aliyun", domain: ".aliyun.com"),
                    ],
                    sourceLabel: "Chrome Default")
            } operation: {
                try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeaders(context: context, allowCached: false)
            }

            #expect(headers.apiCookieHeader == headers.dashboardCookieHeader)
            #expect(headers.apiCookieHeader.contains("dashboard_only=dashboard"))
            #expect(!headers.apiCookieHeader.contains("bailian_only=bailian"))
            #expect(!headers.apiCookieHeader.contains("aliyun_only=aliyun"))
            #expect(headers.dashboardCookieHeader.contains("dashboard_only=dashboard"))
            #expect(!headers.dashboardCookieHeader.contains("bailian_only=bailian"))
            #expect(!headers.dashboardCookieHeader.contains("aliyun_only=aliyun"))

            let cachedHeaders = try AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
                throw AlibabaCodingPlanSettingsError.missingCookie(details: "unexpected import")
            } operation: {
                try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeaders(
                    context: context,
                    allowCached: true)
            }
            #expect(cachedHeaders.apiCookieHeader == headers.apiCookieHeader)
            #expect(cachedHeaders.dashboardCookieHeader == headers.dashboardCookieHeader)
            #expect(strategy.id == "alibaba-token-plan.web")
        }
    }

    @Test
    func `auto web strategy scopes imported cookies to environment overrides`() throws {
        try self.withIsolatedCookieCache {
            let settings = ProviderSettingsSnapshot.make(
                alibabaTokenPlan: ProviderSettingsSnapshot.AlibabaTokenPlanProviderSettings(
                    cookieSource: .auto,
                    manualCookieHeader: nil))
            let environment = [
                AlibabaTokenPlanSettingsReader.quotaURLKey: "https://quota.token-plan.test/data/api.json",
                AlibabaTokenPlanSettingsReader.hostKey: "https://dashboard.token-plan.test",
            ]
            let context = ProviderFetchContext(
                runtime: .cli,
                sourceMode: .web,
                includeCredits: false,
                webTimeout: 1,
                webDebugDumpHTML: false,
                verbose: false,
                env: environment,
                settings: settings,
                fetcher: UsageFetcher(environment: environment),
                claudeFetcher: StubClaudeFetcher(),
                browserDetection: BrowserDetection(cacheTTL: 0))

            self.clearCookieCaches()
            defer { self.clearCookieCaches() }

            let headers = try AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
                AlibabaCodingPlanCookieImporter.SessionInfo(
                    cookies: [
                        self.cookie(name: "login_aliyunid_ticket", value: "ticket", domain: ".token-plan.test"),
                        self.cookie(name: "api_only", value: "api", domain: "quota.token-plan.test"),
                        self.cookie(name: "dashboard_only", value: "dashboard", domain: "dashboard.token-plan.test"),
                        self.cookie(name: "prod_api_only", value: "prod-api", domain: "bailian.console.aliyun.com"),
                        self.cookie(
                            name: "prod_dashboard_only",
                            value: "prod-dashboard",
                            domain: "bailian.console.aliyun.com"),
                    ],
                    sourceLabel: "Chrome Default")
            } operation: {
                try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeaders(context: context, allowCached: false)
            }

            #expect(headers.apiCookieHeader.contains("api_only=api"))
            #expect(!headers.apiCookieHeader.contains("prod_api_only=prod-api"))
            #expect(headers.dashboardCookieHeader.contains("dashboard_only=dashboard"))
            #expect(!headers.dashboardCookieHeader.contains("prod_dashboard_only=prod-dashboard"))
        }
    }

    @Test
    func `cached browser cookies stay isolated by gateway region`() throws {
        try self.withIsolatedCookieCache {
            self.clearCookieCaches()
            defer { self.clearCookieCaches() }
            CookieHeaderCache.store(
                provider: .alibabatokenplan,
                scope: AlibabaTokenPlanAPIRegion.international.cookieCacheScope,
                cookieHeader: AlibabaTokenPlanCookieHeaders(
                    apiCookieHeader: "login_aliyunid_ticket=intl-ticket; gateway=intl",
                    dashboardCookieHeader: "login_aliyunid_ticket=intl-ticket; gateway=intl",
                    rateLimitCookieHeader: "login_aliyunid_ticket=intl-ticket; rpc=intl").cacheCookieHeader,
                sourceLabel: "International fixture")
            CookieHeaderCache.store(
                provider: .alibabatokenplan,
                scope: AlibabaTokenPlanAPIRegion.chinaMainland.cookieCacheScope,
                cookieHeader: AlibabaTokenPlanCookieHeaders(
                    apiCookieHeader: "login_aliyunid_ticket=cn-ticket; gateway=cn",
                    dashboardCookieHeader: "login_aliyunid_ticket=cn-ticket; gateway=cn",
                    rateLimitCookieHeader: "login_aliyunid_ticket=cn-ticket; rpc=cn").cacheCookieHeader,
                sourceLabel: "China fixture")
            try AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
                throw AlibabaCodingPlanSettingsError.missingCookie(details: "unexpected import")
            } operation: {
                let context = self.context(region: .international)
                let international = try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeaders(
                    context: context,
                    allowCached: true,
                    region: .international)
                let china = try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeaders(
                    context: context,
                    allowCached: true,
                    region: .chinaMainland)

                #expect(international.apiCookieHeader.contains("gateway=intl"))
                #expect(!international.apiCookieHeader.contains("gateway=cn"))
                #expect(china.apiCookieHeader.contains("gateway=cn"))
                #expect(!china.apiCookieHeader.contains("gateway=intl"))
            }
        }
    }

    @Test
    func `legacy unscoped cache refreshes without crossing regions`() throws {
        try self.withIsolatedCookieCache {
            self.clearCookieCaches()
            defer { self.clearCookieCaches() }
            CookieHeaderCache.store(
                provider: .alibabatokenplan,
                cookieHeader: "login_aliyunid_ticket=legacy; gateway=legacy-cn",
                sourceLabel: "Legacy fixture")
            let context = self.context(region: .international)
            let international = try AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
                AlibabaCodingPlanCookieImporter.SessionInfo(
                    cookies: [
                        self.cookie(
                            name: "login_aliyunid_ticket",
                            value: "intl",
                            domain: ".alibabacloud.com"),
                        self.cookie(
                            name: "gateway",
                            value: "intl",
                            domain: "modelstudio.console.alibabacloud.com"),
                    ],
                    sourceLabel: "International fixture")
            } operation: {
                try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeaders(
                    context: context,
                    allowCached: true,
                    region: .international)
            }

            let china = try AlibabaCodingPlanCookieImporter.withImportSessionOverrideForTesting { _, _ in
                AlibabaCodingPlanCookieImporter.SessionInfo(
                    cookies: [
                        self.cookie(
                            name: "login_aliyunid_ticket",
                            value: "cn",
                            domain: ".aliyun.com"),
                        self.cookie(
                            name: "gateway",
                            value: "fresh-cn",
                            domain: "bailian.console.aliyun.com"),
                        self.cookie(
                            name: "rpc",
                            value: "fresh-cn",
                            domain: "bailian-cs.console.aliyun.com"),
                    ],
                    sourceLabel: "China fixture")
            } operation: {
                try AlibabaTokenPlanWebFetchStrategy.resolveCookieHeaders(
                    context: context,
                    allowCached: true,
                    region: .chinaMainland)
            }

            #expect(international.apiCookieHeader.contains("gateway=intl"))
            #expect(!international.apiCookieHeader.contains("gateway=legacy-cn"))
            #expect(china.apiCookieHeader.contains("gateway=fresh-cn"))
            #expect(!china.apiCookieHeader.contains("gateway=legacy-cn"))
            #expect(china.rateLimitCookieHeader?.contains("rpc=fresh-cn") == true)
            #expect(CookieHeaderCache.load(provider: .alibabatokenplan) == nil)
            #expect(CookieHeaderCache.load(
                provider: .alibabatokenplan,
                scope: AlibabaTokenPlanAPIRegion.chinaMainland.cookieCacheScope) != nil)
        }
    }

    private func withIsolatedCookieCache<T>(_ operation: () throws -> T) rethrows -> T {
        try KeychainCacheStore.withServiceOverrideForTesting(
            "alibaba-token-plan-web-strategy-tests-\(UUID().uuidString)",
            operation: {
                try KeychainCacheStore.withImplicitTestStoreForTesting(operation: operation)
            })
    }

    private func withIsolatedCookieCache<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await KeychainCacheStore.withServiceOverrideForTesting(
            "alibaba-token-plan-web-strategy-tests-\(UUID().uuidString)",
            operation: {
                try await KeychainCacheStore.withImplicitTestStoreForTesting(operation: operation)
            })
    }

    private func context(
        region: AlibabaTokenPlanAPIRegion,
        sourceMode: ProviderSourceMode = .web,
        cookieSource: ProviderCookieSource = .auto,
        manualCookieHeader: String? = nil) -> ProviderFetchContext
    {
        let settings = ProviderSettingsSnapshot.make(
            alibabaTokenPlan: ProviderSettingsSnapshot.AlibabaTokenPlanProviderSettings(
                cookieSource: cookieSource,
                manualCookieHeader: manualCookieHeader,
                apiRegion: region))
        return ProviderFetchContext(
            runtime: .cli,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: settings,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    private func cookie(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expires: Date = Date(timeIntervalSinceNow: 3600)) -> HTTPCookie
    {
        HTTPCookie(properties: [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value,
            .expires: expires,
            .secure: true,
        ])!
    }
}

final class AlibabaTokenPlanStubURLProtocol: URLProtocol {
    private static let _handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self._handlerBox.value }
        set { Self._handlerBox.setValue(newValue) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "bailian.console.aliyun.com" ||
            host == "bailian-cs.console.aliyun.com" ||
            host == "bailian-singapore-cs.alibabacloud.com" ||
            host == "alibaba-token-plan.test" ||
            host == "rate-limit.test" ||
            host == "session-token.test"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Dedicated protocol stub for Personal/Solo retry tests. Those requests use a
/// production-shaped gateway host, and isolating their handler prevents the
/// file's legacy Team/rate-limit suites from replacing it when suites run in
/// parallel.
final class AlibabaTokenPlanPersonalStubURLProtocol: URLProtocol {
    private static let handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self.handlerBox.value }
        set { Self.handlerBox.setValue(newValue) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "bailian.console.aliyun.com" ||
            host == "bailian-cs.console.aliyun.com"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
