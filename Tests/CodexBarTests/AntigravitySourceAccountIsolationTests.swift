import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct AntigravitySourceAccountIsolationTests {
    @Test
    func `local source keeps saved OAuth accounts passive without deleting them`() {
        let account = ProviderTokenAccount(
            id: UUID(), label: "selected@example.com", token: "synthetic-oauth-credentials", addedAt: 0, lastUsed: nil)
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: .antigravity,
            source: .oauth,
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))])
        let settings = testSettingsStore(
            suiteName: "AntigravitySourceAccountIsolationTests",
            userDefaults: InMemoryUserDefaults(),
            config: config)

        #expect(settings.effectiveSelectedTokenAccount(for: .antigravity)?.id == account.id)
        settings.antigravityUsageDataSource = .cli
        #expect(settings.effectiveSelectedTokenAccount(for: .antigravity) == nil)
        #expect(settings.selectedTokenAccount(for: .antigravity)?.id == account.id)
        #expect(settings.tokenAccounts(for: .antigravity).count == 1)
        let environment = ProviderRegistry.makeEnvironment(
            base: [:], provider: .antigravity, settings: settings, tokenOverride: nil)
        #expect(environment[AntigravityOAuthCredentialsStore.environmentCredentialsKey] == nil)

        settings.antigravityUsageDataSource = .auto
        #expect(settings.effectiveSelectedTokenAccount(for: .antigravity)?.id == account.id)
        settings.antigravityUsageDataSource = .oauth
        #expect(settings.effectiveSelectedTokenAccount(for: .antigravity)?.id == account.id)
    }
}
