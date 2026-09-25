import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct TokenAccountCLISelectionTests {
    @Test
    func `usage and cards share provider selection constraints`() {
        let all = TokenAccountCLISelection(label: nil, index: nil, allAccounts: true)
        #expect(all.providerSelectionError([.codex]) == nil)
        #expect(all.providerSelectionError([.claude]) == nil)
        #expect(all.providerSelectionError([.codex, .claude]) == "account selection requires a single provider.")
        #expect(all.providerSelectionError([]) == "account selection requires a single provider.")
        #expect(all.providerSelectionError([.jetbrains]) == "jetbrains does not support token accounts.")
        let automatic = TokenAccountCLISelection(label: nil, index: nil, allAccounts: false)
        #expect(automatic.providerSelectionError([.jetbrains, .claude]) == nil)
    }

    @Test
    func `antigravity CLI leaves saved OAuth accounts passive`() throws {
        let context = try Self.context(provider: .antigravity, source: .auto)
        #expect(try context.resolvedAccounts(for: .antigravity, sourceMode: .cli).isEmpty)
        let configuredCLI = try Self.context(provider: .antigravity, source: .cli)
        #expect(try configuredCLI.resolvedAccounts(for: .antigravity).isEmpty)
    }

    @Test
    func `antigravity explicit CLI rejects every saved account override`() throws {
        for selection in Self.accountOverrides {
            let context = try Self.context(provider: .antigravity, source: .auto, selection: selection)
            Self.expectCLIAccountConflict {
                try context.resolvedAccounts(for: .antigravity, sourceMode: .cli)
            }
        }
    }

    @Test
    func `antigravity configured CLI rejects every saved account override`() throws {
        for selection in Self.accountOverrides {
            let context = try Self.context(provider: .antigravity, source: .cli, selection: selection)
            Self.expectCLIAccountConflict {
                try context.resolvedAccounts(for: .antigravity)
            }
        }
    }

    @Test
    func `antigravity auto and OAuth retain saved account selection`() throws {
        let selections = Self.accountOverrides + [TokenAccountCLISelection(label: nil, index: nil, allAccounts: false)]
        for source in [ProviderSourceMode.auto, .oauth] {
            for selection in selections {
                let context = try Self.context(provider: .antigravity, source: .cli, selection: selection)
                let accounts = try context.resolvedAccounts(for: .antigravity, sourceMode: source)
                #expect(accounts.map(\.label) == ["Primary"])
                let configured = try Self.context(provider: .antigravity, source: source, selection: selection)
                #expect(try configured.resolvedAccounts(for: .antigravity).map(\.label) == ["Primary"])
            }
        }
    }

    @Test
    func `other providers retain saved account overrides with CLI source`() throws {
        for selection in Self.accountOverrides {
            let context = try Self.context(provider: .claude, source: .cli, selection: selection)
            #expect(try context.resolvedAccounts(for: .claude).map(\.label) == ["Primary"])
        }
    }

    private static var accountOverrides: [TokenAccountCLISelection] {
        [
            TokenAccountCLISelection(label: "Primary", index: nil, allAccounts: false),
            TokenAccountCLISelection(label: nil, index: 0, allAccounts: false),
            TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
        ]
    }

    private static func context(
        provider: UsageProvider,
        source: ProviderSourceMode,
        selection: TokenAccountCLISelection = TokenAccountCLISelection(label: nil, index: nil, allAccounts: false))
        throws -> TokenAccountCLIContext
    {
        let account = ProviderTokenAccount(
            id: UUID(), label: "Primary", token: "fixture-token", addedAt: 0, lastUsed: nil)
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: provider.instanceID,
            source: source,
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))])
        return try TokenAccountCLIContext(
            selection: selection, config: config, verbose: false, baseEnvironment: [:])
    }

    private static func expectCLIAccountConflict(_ resolve: () throws -> [ProviderTokenAccount]) {
        do {
            _ = try resolve()
            Issue.record("Antigravity CLI must reject saved OAuth account overrides")
        } catch {
            #expect(error.localizedDescription ==
                "Antigravity CLI uses its local login and cannot select saved Google accounts. " +
                "Use --source auto or --source oauth with account selection.")
        }
    }
}
