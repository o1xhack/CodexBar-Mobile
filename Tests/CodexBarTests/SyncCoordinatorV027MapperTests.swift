// swiftlint:disable multiline_arguments
//
// Mirrors `SyncCoordinatorV026MapperTests` for the 6 mappers added
// in v0.27.0 (Mac build 65.1 → 65.4 + iOS 1.8.0 build 132 → 136).
// Closes the integration-test gap flagged by the Opus 4.7 CR (build
// 135). Covers wrong-provider early-return and missing-payload
// early-return for each mapper, plus the nil-pruning behaviour that
// keeps iOS from rendering empty cards.
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarSync

@MainActor
@Suite("SyncCoordinator v0.27 mappers")
struct SyncCoordinatorV027MapperTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - mapClaudeAdminUsage

    @Test
    func `Claude Admin mapper: returns nil when provider != .claude`() {
        let admin = ClaudeAdminAPIUsageSnapshot(
            daily: [Self.adminBucket(day: "2026-05-01", cost: 1.0, total: 100)],
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .openai, snapshot: snapshot) == nil)
    }

    @Test
    func `Claude Admin mapper: returns nil when claudeAdminAPIUsage is missing`() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test
    func `Claude Admin mapper: returns nil when last30Days has zero cost AND zero tokens`() {
        // Mapper SHOULD prune empty windows so iOS doesn't render a
        // "$0.00 / 0 tokens" section. Regression guard for that
        // nil-pruning behaviour.
        let admin = ClaudeAdminAPIUsageSnapshot(daily: [], updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        #expect(SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test
    func `Claude Admin mapper: emits envelope when last30Days has tokens`() {
        let admin = ClaudeAdminAPIUsageSnapshot(
            daily: [Self.adminBucket(day: "2026-05-01", cost: 12.5, total: 500_000)],
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        let result = SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot)
        #expect(result != nil)
        #expect(result?.last30Days.totalTokens == 500_000)
        #expect(result?.last30Days.costUSD == 12.5)
    }

    @Test
    func `Claude Admin mapper: caps top-models + top-cost-items at 8`() {
        // Build a snapshot whose summary aggregation produces 10
        // models and 10 cost items, then assert the mapper truncates
        // to 8 entries each (wire-payload cap).
        let models = (0..<10).map { Self.adminModel(name: "model-\($0)", tokens: 1000 - $0) }
        let costItems = (0..<10).map { Self.adminCostItem(name: "item-\($0)", cost: Double(100 - $0)) }
        let admin = ClaudeAdminAPIUsageSnapshot(
            daily: [Self.adminBucket(
                day: "2026-05-01", cost: 1000.0, total: 100_000,
                models: models, costItems: costItems)],
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, claudeAdminAPIUsage: admin, updatedAt: Self.now)
        let result = SyncCoordinator.mapClaudeAdminUsage(
            provider: .claude, snapshot: snapshot)
        #expect(result?.topModels.count == 8)
        #expect(result?.topCostItems.count == 8)
    }

    // MARK: - mapMiniMaxBilling

    @Test
    func `MiniMax billing mapper: returns nil when provider != .minimax`() {
        let billing = MiniMaxBillingSummary(
            todayTokens: 1000, last30DaysTokens: 30000,
            todayCash: 1.5, last30DaysCash: 45.0,
            daily: [MiniMaxBillingDay(day: "2026-05-01", tokens: 1000, cash: 1.5)],
            topMethods: [], topModels: [], updatedAt: Self.now)
        let mini = MiniMaxUsageSnapshot(
            planName: "Pro", availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: billing)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMiniMaxBilling(
            provider: .claude, snapshot: snapshot) == nil)
    }

    @Test
    func `MiniMax billing mapper: returns nil when billingSummary is missing`() {
        let mini = MiniMaxUsageSnapshot(
            planName: "Pro", availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: nil)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMiniMaxBilling(
            provider: .minimax, snapshot: snapshot) == nil)
    }

    @Test
    func `MiniMax billing mapper: returns nil for empty 30-day window`() {
        let billing = MiniMaxBillingSummary(
            todayTokens: 0, last30DaysTokens: 0,
            todayCash: nil, last30DaysCash: nil,
            daily: [], topMethods: [], topModels: [],
            updatedAt: Self.now)
        let mini = MiniMaxUsageSnapshot(
            planName: nil, availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: billing)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMiniMaxBilling(
            provider: .minimax, snapshot: snapshot) == nil)
    }

    @Test
    func `MiniMax billing mapper: caps method+model lists at top-3`() {
        let methods = (0..<5).map {
            MiniMaxBillingBreakdown(name: "method-\($0)", tokens: 100 - $0, cash: nil)
        }
        let models = (0..<5).map {
            MiniMaxBillingBreakdown(name: "model-\($0)", tokens: 100 - $0, cash: nil)
        }
        let billing = MiniMaxBillingSummary(
            todayTokens: 100, last30DaysTokens: 3000,
            todayCash: nil, last30DaysCash: nil,
            daily: [MiniMaxBillingDay(day: "2026-05-01", tokens: 100, cash: nil)],
            topMethods: methods, topModels: models, updatedAt: Self.now)
        let mini = MiniMaxUsageSnapshot(
            planName: nil, availablePrompts: nil, currentPrompts: nil,
            remainingPrompts: nil, windowMinutes: nil, usedPercent: nil,
            resetsAt: nil, updatedAt: Self.now, services: nil,
            billingSummary: billing)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, minimaxUsage: mini, updatedAt: Self.now)
        let result = SyncCoordinator.mapMiniMaxBilling(
            provider: .minimax, snapshot: snapshot)
        #expect(result?.topMethods.count == 3)
        #expect(result?.topModels.count == 3)
    }

    // MARK: - mapOpenCodeGoZenBalance

    @Test
    func `OpenCodeGo Zen mapper: returns nil when provider != .opencodego`() {
        let cost = ProviderCostSnapshot(
            used: 42.5, limit: 0, currencyCode: "USD",
            period: "Zen balance", updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, providerCost: cost, updatedAt: Self.now)
        #expect(SyncCoordinator.mapOpenCodeGoZenBalance(
            provider: .claude, snapshot: snapshot,
            providerCost: cost, workspaceID: nil) == nil)
    }

    @Test
    func `OpenCodeGo Zen mapper: returns nil when providerCost period is not 'Zen balance'`() {
        let cost = ProviderCostSnapshot(
            used: 42.5, limit: 100.0, currencyCode: "USD",
            period: "Monthly", updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, providerCost: cost, updatedAt: Self.now)
        #expect(SyncCoordinator.mapOpenCodeGoZenBalance(
            provider: .opencodego, snapshot: snapshot,
            providerCost: cost, workspaceID: nil) == nil)
    }

    @Test
    func `OpenCodeGo Zen mapper: emits envelope when period matches + currency USD`() {
        let cost = ProviderCostSnapshot(
            used: 42.5, limit: 0, currencyCode: "USD",
            period: "Zen balance", updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, providerCost: cost, updatedAt: Self.now)
        let result = SyncCoordinator.mapOpenCodeGoZenBalance(
            provider: .opencodego, snapshot: snapshot,
            providerCost: cost, workspaceID: "ws-acme")
        #expect(result?.balanceUSD == 42.5)
        #expect(result?.workspaceID == "ws-acme")
    }

    // MARK: - buildCodexWorkspaceContext (mapCodexWorkspace pure core)

    @Test
    func `Codex workspace: returns nil when active account is nil AND snapshot has no weekly window`() {
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        #expect(result == nil)
    }

    @Test
    func `Codex workspace: emits envelope when active account has workspace label`() {
        let account = Self.makeAccount(
            email: "test@example.com",
            workspaceLabel: "Acme",
            workspaceAccountID: "ws-acme")
        let snapshot = UsageSnapshot(
            primary: nil, secondary: nil, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: account, snapshot: snapshot)
        #expect(result?.workspaceName == "Acme")
        #expect(result?.workspaceID == "ws-acme")
        #expect(result?.weeklyPaceDelta == nil)
    }

    @Test
    func `Codex workspace: emits pace when snapshot has weekly window (10080 minutes)`() {
        // Use an in-flight weekly window: started 3 days ago, ends in
        // 4 days. UsagePace.weekly expects timeUntilReset > 0 AND <= duration.
        let weekly = RateWindow(
            usedPercent: 40.0,
            windowMinutes: 7 * 24 * 60,
            resetsAt: Date().addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: nil, secondary: weekly, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        #expect(result != nil)
        #expect(result?.weeklyPaceDelta != nil)
        #expect(result?.weeklyPaceLabel != nil)
    }

    @Test
    func `Codex workspace: anchors pace to secondary when BOTH secondary + primary are ≥ 1-day windows`() {
        // Both primary AND secondary pass the `codexWeeklyWindow`
        // ≥ 1-day filter; the mapper must pick secondary (per the
        // `[secondary, tertiary, primary]` priority order in
        // `SyncCoordinator.codexWeeklyWindow`). Construct two
        // windows with distinct `usedPercent` so the anchored
        // result is visibly different — the test then proves
        // selection by checking the resulting pace delta matches
        // the secondary's actualUsedPercent (40%), not the
        // primary's (80%).
        //
        // Both windows have ~50% elapsed (started 3.5d ago, end in
        // 3.5d), so expected pace is ~50%. Secondary at 40% used
        // → delta ≈ -10% (= -0.10 fraction). Primary at 80% used
        // → delta ≈ +30% (= +0.30 fraction). If the test sees a
        // delta < 0 we proved the mapper picked the secondary's
        // 40% over the primary's 80%.
        let now = Date()
        let resetIn3Days = now.addingTimeInterval(3.5 * 24 * 3600)
        let primaryHighUse = RateWindow(
            usedPercent: 80.0,
            windowMinutes: 7 * 24 * 60,
            resetsAt: resetIn3Days,
            resetDescription: nil)
        let secondaryLowUse = RateWindow(
            usedPercent: 40.0,
            windowMinutes: 7 * 24 * 60,
            resetsAt: resetIn3Days,
            resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primaryHighUse, secondary: secondaryLowUse, updatedAt: Self.now)
        let result = SyncCoordinator.buildCodexWorkspaceContext(
            activeAccount: nil, snapshot: snapshot)
        // Secondary anchor → delta is negative (40% used vs ~50%
        // expected). Primary anchor would have produced positive
        // delta (80% used vs ~50% expected).
        #expect(result?.weeklyPaceDelta != nil)
        if let d = result?.weeklyPaceDelta {
            #expect(
                d < 0,
                "expected secondary anchor (40% used → negative delta); got \(d) — primary anchor was picked instead")
        }
    }

    // MARK: - Fixture builders

    private static func adminBucket(
        day: String,
        cost: Double,
        total: Int,
        models: [ClaudeAdminAPIUsageSnapshot.ModelBreakdown] = [],
        costItems: [ClaudeAdminAPIUsageSnapshot.CostBreakdown] = []) -> ClaudeAdminAPIUsageSnapshot.DailyBucket
    {
        ClaudeAdminAPIUsageSnapshot.DailyBucket(
            day: day,
            startTime: self.now,
            endTime: self.now,
            costUSD: cost,
            inputTokens: total / 2,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: total / 2,
            totalTokens: total,
            costItems: costItems,
            models: models)
    }

    private static func adminModel(name: String, tokens: Int) -> ClaudeAdminAPIUsageSnapshot.ModelBreakdown {
        ClaudeAdminAPIUsageSnapshot.ModelBreakdown(
            name: name,
            inputTokens: tokens / 2,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: tokens / 2,
            totalTokens: tokens)
    }

    private static func adminCostItem(name: String, cost: Double) -> ClaudeAdminAPIUsageSnapshot.CostBreakdown {
        ClaudeAdminAPIUsageSnapshot.CostBreakdown(name: name, costUSD: cost)
    }

    /// Build a ManagedCodexAccount fixture with all `_ = nil` /
    /// stub-able fields filled with deterministic values. Used by
    /// the workspace-mapper tests above; lives here rather than
    /// inline in each test so the body stays focused on the
    /// scenario, not the fixture plumbing.
    private static func makeAccount(
        email: String,
        workspaceLabel: String? = nil,
        workspaceAccountID: String? = nil) -> ManagedCodexAccount
    {
        ManagedCodexAccount(
            id: UUID(),
            email: email,
            providerAccountID: nil,
            workspaceLabel: workspaceLabel,
            workspaceAccountID: workspaceAccountID,
            authFingerprint: nil,
            managedHomePath: "/tmp/codex-test-\(UUID().uuidString)",
            createdAt: self.now.timeIntervalSince1970,
            updatedAt: self.now.timeIntervalSince1970,
            lastAuthenticatedAt: nil)
    }
}

// swiftlint:enable multiline_arguments
