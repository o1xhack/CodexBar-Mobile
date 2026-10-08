import AppKit
import Commander
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

private actor ClinePassAccountFetchRecorder {
    struct Request: Sendable {
        let accountID: UUID?
        let token: String?
        let alias: String?
    }

    private(set) var requests: [Request] = []

    func record(context: ProviderFetchContext) {
        self.requests.append(Request(
            accountID: context.selectedTokenAccountID,
            token: context.env[ClinePassProviderDescriptor.spec.environmentKey],
            alias: context.env[ClinePassSettingsReader.alternateAPIKeyEnvironmentKey]))
    }
}

private struct ClinePassAccountFetchStrategy: ProviderFetchStrategy {
    let recorder: ClinePassAccountFetchRecorder

    let id = "clinepass-account-test"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        await self.recorder.record(context: context)
        let token = context.env[ClinePassProviderDescriptor.spec.environmentKey] ?? ""
        let weeklyPercent = token == "test-key" ? 12.0 : 34.0
        let usage = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: weeklyPercent,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: weeklyPercent))
        return self.makeResult(usage: usage, sourceLabel: self.id)
    }

    func shouldFallback(on _: any Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

@MainActor
@Suite(.serialized)
struct ClinePassMultiAccountTests {
    @Test
    func `catalog entry exposes ClinePass API keys in provider settings`() throws {
        let support = try #require(TokenAccountSupportCatalog.support(for: .clinepass))
        #expect(support.title == "API keys")
        #expect(support.placeholder == "ClinePass API key...")
        #expect(!support.requiresManualCookieSource)
        #expect(support.cookieName == nil)
        guard case let .environment(key) = support.injection else {
            Issue.record("Expected ClinePass token accounts to use environment injection")
            return
        }
        #expect(key == ClinePassProviderDescriptor.spec.environmentKey)

        let settings = Self.makeSettings(suite: "ClinePassMultiAccountTests-settings")
        let store = Self.makeStore(settings: settings)
        let descriptor = try #require(
            ProvidersPane(settings: settings, store: store)._test_tokenAccountDescriptor(for: .clinepass))
        #expect(descriptor.provider == .clinepass)
        #expect(descriptor.title == support.title)
        #expect(descriptor.isVisible?() == true)
    }

    @Test
    func `account-only configuration keeps the provider available`() throws {
        let settings = Self.makeSettings(suite: "ClinePassMultiAccountTests-availability")
        let implementation = try #require(ProviderCatalog.implementation(for: .clinepass))
        let context = ProviderAvailabilityContext(provider: .clinepass, settings: settings, environment: [:])

        #expect(!implementation.isAvailable(context: context))

        settings.addTokenAccount(provider: .clinepass, label: "Personal", token: "account-a")

        #expect(implementation.isAvailable(context: context))
    }

    @Test
    func `selected account overrides configured and ambient credentials`() {
        let account = ProviderTokenAccount(
            id: UUID(), label: "Work", token: "account-token", addedAt: 0, lastUsed: nil)
        let environment = ProviderEnvironmentResolver.resolve(
            base: [
                ClinePassProviderDescriptor.spec.environmentKey: "ambient-token",
                ClinePassSettingsReader.alternateAPIKeyEnvironmentKey: "alias-token",
            ],
            provider: .clinepass,
            config: ProviderConfig(id: .clinepass, apiKey: "config-token"),
            selectedAccount: account)

        #expect(environment[ClinePassProviderDescriptor.spec.environmentKey] == "account-token")
        #expect(environment[ClinePassSettingsReader.alternateAPIKeyEnvironmentKey] == nil)
        #expect(
            ProviderDescriptorRegistry.descriptor(for: .clinepass).credentials?
                .resolveToken(environment: environment)?.token == "account-token")
    }

    @Test
    func `selected account key reaches the bundled plugin as bearer auth`() async throws {
        let strategy = ClinePassProviderDescriptor.makeStrategy(
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.url?.absoluteString == "https://api.cline.bot/api/v1/users/me/plan/usage-limits")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer account-b")
                let response = try #require(HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]))
                return (
                    Data(#"{"success":true,"data":{"limits":[{"type":"weekly","percentUsed":25}]}}"#.utf8),
                    response)
            })
        let account = ProviderTokenAccount(
            id: UUID(), label: "Work", token: "account-b", addedAt: 0, lastUsed: nil)
        let environment = ProviderEnvironmentResolver.resolve(
            base: [ClinePassProviderDescriptor.spec.environmentKey: "ambient-token"],
            provider: .clinepass,
            config: ProviderConfig(id: .clinepass, apiKey: "config-token"),
            selectedAccount: account)

        let result = try await strategy.fetch(ProviderCutoverTestSupport.context(environment: environment))

        #expect(result.usage.secondary?.usedPercent == 25)
        #expect(result.usage.identity?.loginMethod == "API key")
    }

    @Test
    func `no selected account preserves configured key and environment precedence`() {
        let key = ClinePassProviderDescriptor.spec.environmentKey
        let alias = ClinePassSettingsReader.alternateAPIKeyEnvironmentKey
        for configuredKey in [nil, "config-token"] as [String?] {
            let environment = ProviderEnvironmentResolver.resolve(
                base: [key: "ambient-token", alias: "alias-token", "UNRELATED": "kept"],
                provider: .clinepass,
                config: ProviderConfig(id: .clinepass, apiKey: configuredKey),
                selectedAccount: nil)
            #expect(environment == [
                key: configuredKey ?? "ambient-token", alias: "alias-token", "UNRELATED": "kept",
            ])
            #expect(ClinePassSettingsReader.apiKey(environment: environment) == (configuredKey ?? "ambient-token"))
        }
        let environment = ProviderEnvironmentResolver.resolve(
            base: [alias: "alias-token"], provider: .clinepass, config: nil, selectedAccount: nil)
        #expect(ClinePassSettingsReader.apiKey(environment: environment) == "alias-token")
    }

    @Test(arguments: [401, 403])
    func `rejected selected key never falls back to a Cline session`(statusCode: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("providers.json")
        let content = #"{"providers":{"cline":{"settings":{"auth":{"accessToken":"fixture-session"}}}}}"#
        try content.write(to: file, atomically: true, encoding: .utf8)
        let base = ["CLINE_PROVIDER_SETTINGS_PATH": file.path, "HOME": directory.path]
        let credentials = ClinePassProviderDescriptor.descriptor.credentials
        let legacy = ProviderEnvironmentResolver.resolve(
            base: base, provider: .clinepass, config: nil, selectedAccount: nil)
        #expect(credentials?.resolveToken(environment: legacy)?.token == "workos:fixture-session")
        let environment = ProviderEnvironmentResolver.resolve(
            base: base
                .merging(["CLINE_API_KEY": "ambient-token", "CLINEPASS_API_KEY": "alias-token"]) { _, new in new },
            provider: .clinepass,
            config: ProviderConfig(id: .clinepass, apiKey: "config-token"),
            selectedAccount: Self.account(label: "Rejected", token: "invalid-account-key", seed: 3))
        let strategy = ClinePassProviderDescriptor.makeStrategy(transport: ProviderHTTPTransportHandler { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer invalid-account-key")
            let response = try #require(HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil))
            return (Data("{}".utf8), response)
        })
        let context = ProviderCutoverTestSupport.context(environment: environment)
        do {
            _ = try await strategy.fetch(context)
            Issue.record("Expected selected account authentication failure")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .authenticationExpired)
            #expect(!strategy.shouldFallback(on: error, context: context))
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
    }

    @Test
    func `two accounts fetch with isolated keys and caches`() async throws {
        let settings = Self.makeSettings(suite: "ClinePassMultiAccountTests-fetch")
        settings[providerConfig: .clinepass, field: .apiKey] = "decoy-token"
        settings.addTokenAccount(provider: .clinepass, label: "Personal", token: "test-key")
        settings.addTokenAccount(provider: .clinepass, label: "Work", token: "test-auth-token")
        let accounts = settings.tokenAccounts(for: .clinepass)
        let recorder = ClinePassAccountFetchRecorder()
        let store = Self.makeStore(settings: settings, recorder: recorder)

        await store.refreshTokenAccounts(provider: .clinepass, accounts: accounts)

        let requests = await recorder.requests
        #expect(Set(requests.compactMap(\.token)) == ["test-key", "test-auth-token"])
        #expect(Set(requests.compactMap(\.accountID)) == Set(accounts.map(\.id)))
        #expect(requests.allSatisfy { $0.token != "decoy-token" && $0.alias == nil })

        let snapshots = try #require(store.accountSnapshots[.clinepass])
        #expect(snapshots.map(\.account.id) == accounts.map(\.id))
        #expect(snapshots.map { $0.snapshot?.accountEmail(for: .clinepass) } == ["Personal", "Work"])
        #expect(snapshots.map { $0.snapshot?.secondary?.usedPercent } == [12, 34])
        #expect(Set(snapshots.map(\.cacheKey)).count == 2)

        settings.setActiveTokenAccountIndex(0, for: .clinepass)
        store.activateCachedTokenAccountSnapshot(provider: .clinepass, accountID: accounts[0].id)
        #expect(store.snapshot(for: .clinepass)?.secondary?.usedPercent == 12)
        settings.setActiveTokenAccountIndex(1, for: .clinepass)
        store.activateCachedTokenAccountSnapshot(provider: .clinepass, accountID: accounts[1].id)
        #expect(store.snapshot(for: .clinepass)?.secondary?.usedPercent == 34)
        #expect(store.snapshot(for: .clinepass)?.accountEmail(for: .clinepass) == "Work")
    }

    @Test
    func `CLI routes selected and all accounts`() throws {
        let accounts = [
            Self.account(label: "Personal", token: "test-key", seed: 1),
            Self.account(label: "Work", token: "test-auth-token", seed: 2),
        ]
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .clinepass,
                apiKey: "decoy-token",
                tokenAccounts: ProviderTokenAccountData(version: 1, accounts: accounts, activeIndex: 0)),
        ])
        let parser = CommandParser(signature: CodexBarCLI._usageSignatureForTesting())
        let selectedValues = try parser.parse(arguments: [
            "--provider", "clinepass",
            "--account", "Work",
        ])
        let allValues = try parser.parse(arguments: [
            "--provider", "clinepass",
            "--all-accounts",
        ])
        let key = ClinePassProviderDescriptor.spec.environmentKey

        let selectedContext = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(
                label: selectedValues.options["account"]?.last,
                index: nil,
                allAccounts: false),
            config: config,
            verbose: false,
            baseEnvironment: [key: "test-token-placeholder"])
        let selected = try selectedContext.resolvedAccounts(for: .clinepass)
        #expect(selected.map(\.label) == ["Work"])
        let selectedAccount = try #require(selected.first)
        #expect(selectedContext.environment(
            base: [key: "test-token-placeholder"],
            provider: .clinepass,
            account: selectedAccount)[key] == "test-auth-token")

        let allContext = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(
                label: nil,
                index: nil,
                allAccounts: allValues.flags.contains("allAccounts")),
            config: config,
            verbose: false,
            baseEnvironment: [key: "test-token-placeholder"])
        let all = try allContext.resolvedAccounts(for: .clinepass)
        #expect(all.map(\.label) == ["Personal", "Work"])
        #expect(all.map {
            allContext.environment(base: [:], provider: .clinepass, account: $0)[key]
        } == ["test-key", "test-auth-token"])
    }

    @Test
    func `render synthetic account settings when requested`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_CLINEPASS_ACCOUNTS_PROOF"] else { return }
        let settings = Self.makeSettings(suite: "ClinePassMultiAccountTests-render")
        settings.addTokenAccount(provider: .clinepass, label: "Personal", token: "fixture-personal-key")
        settings.addTokenAccount(provider: .clinepass, label: "Work", token: "fixture-work-key")
        let store = Self.makeStore(settings: settings)
        let descriptor = ProvidersPane(settings: settings, store: store).tokenAccountDescriptor(for: .clinepass)
        let hosting = NSHostingView(rootView: VStack(alignment: .leading, spacing: 18) {
            Text("ClinePass").font(.title2.bold())
            Text("Synthetic account settings").foregroundStyle(.secondary)
            if let descriptor, descriptor.isVisible?() ?? true {
                ProviderSettingsTokenAccountsRowView(descriptor: descriptor)
            } else {
                Text("Account editor unavailable")
            }
        }.padding(24).frame(width: 740).background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }

    private static func makeSettings(suite: String) -> SettingsStore {
        testSettingsStore(
            suiteName: "\(suite)-\(UUID().uuidString)",
            userDefaults: InMemoryUserDefaults(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }

    private static func makeStore(
        settings: SettingsStore,
        recorder: ClinePassAccountFetchRecorder? = nil) -> UsageStore
    {
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [ClinePassProviderDescriptor.spec.environmentKey: "test-token-placeholder"])
        guard let recorder else { return store }
        guard let baseSpec = store.providerSpecs[.clinepass] else { return store }
        let baseDescriptor = baseSpec.descriptor
        let strategy = ClinePassAccountFetchStrategy(recorder: recorder)
        store.providerSpecs[.clinepass] = ProviderSpec(
            style: baseSpec.style,
            isEnabled: { true },
            descriptor: ProviderDescriptor(
                id: .clinepass,
                metadata: baseDescriptor.metadata,
                branding: baseDescriptor.branding,
                tokenCost: baseDescriptor.tokenCost,
                fetchPlan: ProviderFetchPlan(
                    sourceModes: [.auto, .api],
                    pipeline: ProviderFetchPipeline { _ in [strategy] }),
                cli: baseDescriptor.cli),
            makeFetchContext: baseSpec.makeFetchContext)
        return store
    }

    private static func account(label: String, token: String, seed: UInt8) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(uuid: (seed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, seed)),
            label: label,
            token: token,
            addedAt: TimeInterval(seed),
            lastUsed: nil)
    }
}
