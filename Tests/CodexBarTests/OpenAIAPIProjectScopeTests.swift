import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@Suite(.serialized)
struct OpenAIAPIProjectScopeTests {
    @Test
    @MainActor
    func `token account strips configured project in app environment builder`() {
        let settings = Self.makeSettingsStore(suite: "OpenAIAPIProjectScopeTests-app")
        settings[providerConfig: .openai, field: .apiKey] = "config-token"
        settings[providerConfig: .openai, field: .secretWorkspace(logField: "projectID")] = "proj_config"
        settings.addTokenAccount(provider: .openai, label: "Configured account", token: "first-account-token")
        settings.addTokenAccount(provider: .openai, label: "Selected account", token: "selected-account-token")
        let selectedAccount = settings.tokenAccounts(for: .openai)[1]

        let env = ProviderRegistry.makeEnvironment(
            base: [OpenAIAPISettingsReader.projectIDEnvironmentKey: "proj_env"],
            provider: .openai,
            settings: settings,
            tokenOverride: TokenAccountOverride(provider: .openai, account: selectedAccount))

        #expect(env[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] == "selected-account-token")
        #expect(env[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] != "config-token")
        #expect(env[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] != "first-account-token")
        #expect(env[OpenAIAPISettingsReader.projectIDEnvironmentKey] == nil)
    }

    @Test
    func `token account strips configured project in CLI environment builder`() throws {
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Project account",
            token: "account-token",
            addedAt: Date().timeIntervalSince1970,
            lastUsed: nil)
        let accounts = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .openai,
                    apiKey: "config-token",
                    workspaceID: "proj_config",
                    tokenAccounts: accounts),
            ])
        let selection = TokenAccountCLISelection(label: nil, index: nil, allAccounts: false)
        let tokenContext = try TokenAccountCLIContext(selection: selection, config: config, verbose: false)

        let env = tokenContext.environment(
            base: [OpenAIAPISettingsReader.projectIDEnvironmentKey: "proj_env"],
            provider: .openai,
            account: account)

        #expect(env[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] == "account-token")
        #expect(env[OpenAIAPISettingsReader.adminAPIKeyEnvironmentKey] != "config-token")
        #expect(env[OpenAIAPISettingsReader.projectIDEnvironmentKey] == nil)
    }

    @MainActor
    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }
}
