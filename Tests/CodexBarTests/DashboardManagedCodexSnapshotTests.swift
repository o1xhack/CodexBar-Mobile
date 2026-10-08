import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct DashboardManagedCodexSnapshotTests {
    private let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [DashboardIdentityMode.full, .redacted, .none])
    func `Codex accounts attach once with provider specific windows and identity policy`(
        mode: DashboardIdentityMode) throws
    {
        let account = ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "codex-managed", opaqueID: "test-account"),
            provider: .codex,
            displayLabel: "owner@example.com · Work admin@company.test",
            accountEmail: "owner@example.com",
            isActive: true,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 40,
                    windowMinutes: 300,
                    resetsAt: self.generatedAt.addingTimeInterval(3600),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 60,
                    windowMinutes: 10080,
                    resetsAt: self.generatedAt.addingTimeInterval(172_800),
                    resetDescription: nil),
                tertiary: nil,
                updatedAt: self.generatedAt,
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "owner@example.com",
                    accountOrganization: nil,
                    loginMethod: "plus")),
            error: nil,
            sourceLabel: nil)
        let snapshot = DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [self.ambient(.claude), self.ambient(.codex), self.ambient(.codex)],
            costPayloads: [],
            config: CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: true)]),
            identityMode: mode,
            generatedAt: self.generatedAt,
            refreshInterval: 0,
            codexBarVersion: nil,
            accountCollections: [.codex: DashboardAccountsInput(
                accounts: [account], adapterError: nil, weeklyWorkDays: nil)])
        #expect(snapshot.schemaVersion == 1)
        let rows = snapshot.providers
        #expect(rows[0].accounts == nil)
        #expect(rows[2].accounts == nil)
        let projected = try #require(rows[1].accounts?.first)
        #expect(projected.id == "codex-managed:test-account")
        #expect(projected.active)
        let label = switch mode {
        case .full: "owner@example.com · Work admin@company.test"
        case .redacted: "redacted@example.com · Work redacted@company.test"
        case .none: "Account test-account"
        }
        let email: String? = switch mode {
        case .full: "owner@example.com"
        case .redacted: "redacted@example.com"
        case .none: nil
        }
        #expect(projected.label == label)
        #expect(projected.identity?.accountEmail == email)
        #expect(projected.identity?.plan == (mode == .none ? nil : "Plus"))
        #expect(projected.windows.map(\.kind) == ["session", "weekly"])
        #expect(projected.pace?.primary != nil)
        #expect(projected.updatedAt == self.generatedAt)
        #expect(rows[1].source == "fixture")
    }

    @Test
    func `Codex whole adapter failure preserves ambient provider data`() {
        let snapshot = DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [self.ambient(.codex)],
            costPayloads: [],
            config: CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: true)]),
            identityMode: .full,
            generatedAt: self.generatedAt,
            refreshInterval: 60,
            codexBarVersion: nil,
            accountCollections: [.codex: DashboardAccountsInput(
                accounts: nil, adapterError: "Managed account metadata unavailable.", weeklyWorkDays: nil)])
        #expect(snapshot.providers[0].accounts == nil)
        #expect(snapshot.providers[0].accountsError == "Managed account metadata unavailable.")
        #expect(snapshot.providers[0].source == "fixture")
    }

    @Test
    func `producer collects accounts only for requested providers`() async throws {
        let collected = DashboardAccountCollectionRecorder()
        let payload = self.ambient(.codex)
        var producer = DashboardSnapshotProducer(
            collectUsage: { _ in
                var output = UsageCommandOutput()
                output.payload = [payload]
                return output
            },
            collectCost: { _, _ in [] },
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        producer.collectAccounts = { _, provider in
            await collected.append(provider)
            return DashboardAccountsInput(accounts: [], adapterError: nil, weeklyWorkDays: nil)
        }
        let result = try await producer.collect(
            config: CodexBarConfig(providers: [
                ProviderConfig(id: .codex, enabled: true), ProviderConfig(id: .claude, enabled: true),
            ]),
            refreshInterval: 0,
            codexBarVersion: nil,
            providers: [.codex])
        #expect(await collected.providers == [.codex])
        #expect(result.payload.providers[0].accounts?.isEmpty == true)
    }

    private func ambient(_ provider: UsageProvider) -> ProviderPayload {
        ProviderPayload(
            provider: provider,
            account: nil,
            version: nil,
            source: "fixture",
            status: nil,
            usage: nil,
            credits: nil,
            antigravityPlanInfo: nil,
            openaiDashboard: nil,
            error: nil)
    }
}

private actor DashboardAccountCollectionRecorder {
    private(set) var providers: [UsageProvider] = []

    func append(_ provider: UsageProvider) {
        self.providers.append(provider)
    }
}
