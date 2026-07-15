import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Pins that `MockProviderInjector` populates the iOS 1.9.0 / Mac 0.29.0
/// parity-gap cards (A / D / E / F / G) so the Debug · Mock Provider Data
/// toggle actually exercises the new iOS detail cards — without this, mock
/// injection mode silently renders only generic rate windows for OpenRouter /
/// Azure OpenAI / Alibaba Token Plan and hides the Codex split + N-day window,
/// the exact regression vector the v0.26 `v026ExtrasFor` hook was built to
/// prevent.
@MainActor
@Suite("Mock injector — v0.29 parity extras (A/D/E/F/G)")
struct MockProviderV029ExtrasTests {
    private func mocks() -> [ProviderUsageSnapshot] {
        MockProviderInjector.allMocks()
    }

    @Test
    func `OpenRouter mock carries openRouterStats (gap D)`() throws {
        let mock = try #require(self.mocks().first { $0.providerID == "openrouter" })
        let stats = try #require(mock.openRouterStats)
        #expect(stats.balanceUSD == 7.50)
        #expect(stats.rateLimitRequests == 20)
        #expect(stats.rateLimitInterval == "10s")
    }

    @Test
    func `Azure OpenAI mock carries azureOpenAIInfo (gap E)`() throws {
        let mock = try #require(self.mocks().first { $0.providerID == "azureopenai" })
        let info = try #require(mock.azureOpenAIInfo)
        #expect(info.deploymentName == "gpt-4o-prod")
        #expect(info.endpointHost == "my-resource.openai.azure.com")
        #expect(info.model == "gpt-4o")
    }

    @Test
    func `Alibaba Token Plan mock carries alibabaTokenPlan (gap G)`() throws {
        let mock = try #require(self.mocks().first { $0.providerID == "alibabatokenplan" })
        let plan = try #require(mock.alibabaTokenPlan)
        #expect(plan.totalCredits == 1_000_000)
        #expect(plan.remainingCredits == 480_000)
        #expect(plan.planName == "Bailian Pro (Mock)")
    }

    @Test
    func `Codex mock carries the standard/fast split (gap A) + 90-day window (gap F)`() throws {
        // Alice is the only Codex mock with a daily breakdown.
        let alice = try #require(self.mocks().first {
            $0.providerID == "codex" && ($0.costSummary?.daily.isEmpty == false)
        })
        let cost = try #require(alice.costSummary)
        #expect(cost.historyDays == 90) // gap F
        let day = try #require(cost.daily.first)
        let breakdown = try #require(day.modelBreakdowns.first)
        let std = try #require(breakdown.standardCostUSD) // gap A
        let fast = try #require(breakdown.priorityCostUSD)
        #expect(std > 0)
        #expect(fast > 0)
        // 60/40 split sums back to the model cost.
        #expect(abs(std + fast - breakdown.costUSD) < 0.0001)
    }

    @Test
    func `Antigravity mock carries the multi-account switcher (gap B)`() throws {
        let mock = try #require(self.mocks().first {
            $0.providerID == "antigravity" && $0.antigravityAccounts != nil
        })
        let accounts = try #require(mock.antigravityAccounts)
        #expect(accounts.accounts.count >= 2)
    }
}
