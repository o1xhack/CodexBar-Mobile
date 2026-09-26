import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CompactAccountMenuPersistenceTests {
    private func settings(defaults: UserDefaults) -> SettingsStore {
        testSettingsStore(
            suiteName: "CompactAccountMenuPersistenceTests",
            userDefaults: defaults,
            config: testConfigWithAllProvidersDisabled())
    }

    @Test
    func `expanded and collapsed choices survive new settings instances`() {
        let defaults = InMemoryUserDefaults()
        let first = self.settings(defaults: defaults)
        let claude = ProviderAccountIdentity(source: "claude-swap", opaqueID: "2")
        let codex = ProviderAccountIdentity(source: "codex-account", opaqueID: "2")
        #expect(first.compactAccountExpandedIDs.isEmpty)

        first.compactAccountExpandedIDs.insert(claude)
        first.compactAccountExpandedIDs.insert(codex)

        let reopened = self.settings(defaults: defaults)
        #expect(reopened.compactAccountExpandedIDs == [claude, codex])
        reopened.compactAccountExpandedIDs.remove(claude)

        let relaunched = self.settings(defaults: defaults)
        #expect(relaunched.compactAccountExpandedIDs == [codex])
        relaunched.compactAccountExpandedIDs.remove(codex)
        #expect(self.settings(defaults: defaults).compactAccountExpandedIDs.isEmpty)
    }

    @Test
    func `malformed entries are ignored without discarding valid identities`() {
        let defaults = InMemoryUserDefaults(values: ["compactAccountExpandedIDs": "invalid"])
        let settings = self.settings(defaults: defaults)
        #expect(settings.compactAccountExpandedIDs.isEmpty)

        defaults.set([
            ["source": "claude-swap", "opaqueID": "2"],
            ["source": "claude-swap"],
            ["source": "", "opaqueID": "3"],
            ["source": "codex-account", "opaqueID": ""],
            42,
        ] as [Any], forKey: "compactAccountExpandedIDs")
        #expect(settings.compactAccountExpandedIDs == [
            ProviderAccountIdentity(source: "claude-swap", opaqueID: "2"),
        ])
    }

    @Test
    func `restored expansion follows identity after reorder rename and active account changes`() {
        let defaults = InMemoryUserDefaults()
        let expanded = ProviderAccountIdentity(source: "claude-swap", opaqueID: "2")
        self.settings(defaults: defaults).compactAccountExpandedIDs = [expanded]

        let relaunched = self.settings(defaults: defaults)
        for activeSlot in [1, 2, 3] {
            let accounts = [4, 2, 1, 3].map { slot in
                ProviderAccountUsageSnapshot(
                    id: ProviderAccountIdentity(source: "claude-swap", opaqueID: String(slot)),
                    provider: .claude,
                    displayLabel: "Renamed account \(slot)",
                    isActive: slot == activeSlot,
                    snapshot: UsageSnapshot(
                        primary: RateWindow(
                            usedPercent: 95,
                            windowMinutes: 300,
                            resetsAt: nil,
                            resetDescription: nil),
                        secondary: nil,
                        updatedAt: Date()),
                    error: nil,
                    sourceLabel: "test")
            }
            let plan = AccountMenuLayoutPlanner.plan(
                accounts: accounts,
                expandedAccountIDs: relaunched.compactAccountExpandedIDs)
            let cards = plan.rows.compactMap { row -> ProviderAccountIdentity? in
                guard case let .card(id) = row else { return nil }
                return id
            }
            #expect(cards.contains(expanded))
            #expect(cards.count == (activeSlot == 2 ? 1 : 2))
        }
    }
}
