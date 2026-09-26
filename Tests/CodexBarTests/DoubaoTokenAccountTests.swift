import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@Suite(.serialized)
struct DoubaoTokenAccountTests {
    private var ambient: [String: String] {
        var environment = Dictionary(uniqueKeysWithValues: (
            DoubaoSettingsReader.apiKeyEnvironmentKeys + DoubaoSettingsReader.accessKeyIDEnvironmentKeys
                + DoubaoSettingsReader.secretAccessKeyEnvironmentKeys).map { ($0, "ambient-fixture") })
        environment["UNRELATED"] = "kept"
        environment["ARKCLI_PATH"] = "/synthetic/arkcli"
        return environment
    }

    private let accounts = ["First", "Second"].map {
        ProviderTokenAccount(id: UUID(), label: $0, token: "ark-\($0)-fixture", addedAt: 0, lastUsed: nil)
    }

    @Test
    func `credential aliases preserve cleaning and ordered fallback`() {
        #expect(DoubaoSettingsReader.apiKey(environment: [
            "ARK_API_KEY": " ' ' ", "VOLCENGINE_API_KEY": " 'ark-fixture' ", "DOUBAO_API_KEY": "last",
        ]) == "ark-fixture")
        let credentials = DoubaoSettingsReader.codingPlanCredentials(environment: [
            "VOLCENGINE_ACCESS_KEY_ID": "''", "VOLC_ACCESSKEY": " 'AKLT-fixture' ",
            "VOLCENGINE_SECRET_ACCESS_KEY": "\" \"", "VOLC_SECRETKEY": " 'secret-fixture' ",
            "VOLCENGINE_REGION": "''", "VOLC_REGION": " 'cn-shanghai' ",
        ])
        #expect(credentials?.accessKeyID == "AKLT-fixture")
        #expect(credentials?.secretAccessKey == "secret-fixture")
        #expect(credentials?.region == "cn-shanghai")
        #expect(DoubaoSettingsReader.region(environment: [:]) == "cn-beijing")
    }

    @Test(arguments: [ProviderSourceMode.auto, .api, .cli])
    func `saved CLI accounts isolate keys and always use the API route`(source: ProviderSourceMode) async throws {
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: .doubao,
            source: source,
            apiKey: "AKLT-config-fixture",
            secretKey: "config-secret-fixture",
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: self.accounts, activeIndex: 1))])
        let all = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: config,
            verbose: false,
            baseEnvironment: [:])
        let selected = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: config,
            verbose: false,
            baseEnvironment: [:])
        #expect(all.selection.providerSelectionError([.doubao]) == nil)
        #expect(try all.resolvedAccounts(for: .doubao).map(\.id) == self.accounts.map(\.id))
        #expect(try selected.resolvedAccounts(for: .doubao).map(\.id) == [self.accounts[1].id])
        #expect(all.effectiveSourceMode(base: source, provider: .doubao, account: nil) == source)

        for (index, account) in self.accounts.enumerated() {
            let environment = all.environment(base: self.ambient, provider: .doubao, account: account)
            #expect(environment == [
                "ARK_API_KEY": account.token, "UNRELATED": "kept", "ARKCLI_PATH": "/synthetic/arkcli",
            ])
            let mode = all.effectiveSourceMode(base: source, provider: .doubao, account: account)
            #expect(mode == .api)
            let context = self.context(environment: environment, source: mode)
            let strategies = await DoubaoProviderDescriptor.resolveStrategies(context: context)
            #expect(strategies.map(\.id) == ["doubao.api"])
            let strategy = DoubaoAPIFetchStrategy(
                signedUsageLoader: { _ in
                    Issue.record("Selected Ark key must not use ambient AK/SK")
                    throw DoubaoUsageError.missingCredentials
                },
                arkUsageLoader: { token in
                    #expect(token == account.token)
                    return DoubaoUsageSnapshot(
                        remainingRequests: index == 0 ? 75 : 25,
                        limitRequests: 100,
                        resetTime: nil,
                        updatedAt: Date(timeIntervalSince1970: 0),
                        apiKeyValid: true)
                })
            let result = try await strategy.fetch(context)
            #expect(result.usage.primary?.usedPercent == (index == 0 ? 25 : 75))
        }
    }

    @Test
    func `invalid saved key fails without falling back to another account`() async throws {
        let environment = ProviderEnvironmentResolver.resolve(
            base: self.ambient,
            provider: .doubao,
            config: ProviderConfig(id: .doubao, apiKey: "ark-config-fixture"),
            selectedAccount: self.accounts[0])
        let strategy = DoubaoAPIFetchStrategy(
            signedUsageLoader: { _ in
                Issue.record("Unexpected signed credential fallback")
                throw DoubaoUsageError.missingCredentials
            },
            arkUsageLoader: { token in
                #expect(token == self.accounts[0].token)
                throw DoubaoUsageError.apiError(401, "fixture")
            })
        let context = self.context(environment: environment, source: .api)
        await #expect {
            try await strategy.fetch(context)
        } throws: { error in
            guard case DoubaoUsageError.apiError(401, "fixture") = error else { return false }
            return true
        }
        #expect(!strategy.shouldFallback(on: DoubaoUsageError.apiError(401, "fixture"), context: context))
    }

    @Test @MainActor
    func `app account editor stores and isolates keys without changing legacy settings`() throws {
        let settings = self.settings()
        settings.doubaoAPIToken = "AKLT-config-fixture"
        settings.doubaoSecretAccessKey = "secret-fixture"
        settings.doubaoRegion = "cn-beijing"
        settings.updateProviderConfig(provider: .doubao) { $0.source = .cli }
        let originalSource = ProviderRegistry.resolvedSourceMode(provider: .doubao, settings: settings, account: nil)
        let store = self.store(settings)
        let descriptor = try #require(ProvidersPane(settings: settings, store: store)
            .tokenAccountDescriptor(for: .doubao))
        #expect(descriptor.isVisible?() ?? true)
        #expect(descriptor.accounts().isEmpty)
        for account in self.accounts {
            settings.addTokenAccount(provider: .doubao, label: account.label, token: account.token)
        }
        #expect(descriptor.accounts().map(\.displayName) == ["First", "Second"])
        let first = try #require(settings.tokenAccounts(for: .doubao).first)
        settings.setActiveTokenAccountIndex(0, for: .doubao)
        #expect(settings.effectiveSelectedTokenAccount(for: .doubao)?.id == first.id)
        for account in settings.tokenAccounts(for: .doubao) {
            let environment = ProviderRegistry.makeEnvironment(
                base: self.ambient,
                provider: .doubao,
                settings: settings,
                tokenOverride: TokenAccountOverride(provider: .doubao, account: account))
            #expect(environment["ARK_API_KEY"] == account.token)
            #expect(DoubaoSettingsReader.codingPlanCredentials(environment: environment) == nil)
            #expect(ProviderRegistry
                .resolvedSourceMode(provider: .doubao, settings: settings, account: account) == .api)
        }
        settings.updateTokenAccount(provider: .doubao, accountID: first.id, label: "Renamed")
        #expect(descriptor.accounts().map(\.displayName) == ["Renamed", "Second"])
        for account in settings.tokenAccounts(for: .doubao) {
            settings.removeTokenAccount(provider: .doubao, accountID: account.id)
        }
        #expect(settings.effectiveSelectedTokenAccount(for: .doubao) == nil)
        #expect(settings.doubaoAPIToken == "AKLT-config-fixture")
        #expect(settings.doubaoSecretAccessKey == "secret-fixture")
        #expect(settings.doubaoRegion == "cn-beijing")
        #expect(ProviderRegistry
            .resolvedSourceMode(provider: .doubao, settings: settings, account: nil) == originalSource)
        #expect(settings.providerConfig(for: .doubao)?.source == .cli)
    }

    @Test @MainActor
    func `render synthetic account settings when requested`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_DOUBAO_ACCOUNTS_PROOF"] else { return }
        let settings = self.settings()
        for account in self.accounts {
            settings.addTokenAccount(provider: .doubao, label: account.label, token: account.token)
        }
        let store = self.store(settings)
        let descriptor = ProvidersPane(settings: settings, store: store).tokenAccountDescriptor(for: .doubao)
        let hosting = NSHostingView(rootView: VStack(alignment: .leading, spacing: 18) {
            Text("Doubao").font(.title2.bold())
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

    @MainActor private func settings() -> SettingsStore {
        let settings = testSettingsStore(
            suiteName: "DoubaoTokenAccountTests",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        settings.configFileWatcher?.stop()
        return settings
    }

    @MainActor private func store(_ settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [:])
    }

    private func context(environment: [String: String], source: ProviderSourceMode) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .cli,
            sourceMode: source,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: DoubaoAccountClaudeStub(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}

private struct DoubaoAccountClaudeStub: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw DoubaoUsageError.missingCredentials
    }

    func debugRawProbe(model _: String) async -> String { "fixture" }
    func detectVersion() -> String? { nil }
}
