import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SyncV072BridgeTests {
    private let observed = Date(timeIntervalSince1970: 1_791_500_000)

    @Test
    func `LithosAI prepaid balance publishes as a mobile balance amount`() throws {
        let cost = ProviderCostSnapshot(
            used: 42.5,
            limit: 0,
            currencyCode: "USD",
            period: "Prepaid credits",
            updatedAt: self.observed)
        let amount = try #require(SyncCoordinator.mapProviderAmount(
            provider: .lithosai,
            snapshot: nil,
            providerCost: cost))
        #expect(amount.kind == "balance")
        #expect(amount.amount == 42.5)
        #expect(amount.period == "Prepaid credits")
        #expect(amount.observedAt == self.observed)
    }

    @Test
    func `Grok purchased credits publish including a confirmed zero`() throws {
        for balance in [12.75, 0] {
            let cost = ProviderCostSnapshot(
                used: 0,
                limit: 0,
                currencyCode: "USD",
                balance: balance,
                balanceUpdatedAt: self.observed,
                updatedAt: self.observed.addingTimeInterval(-60))
            let amount = try #require(SyncCoordinator.mapProviderAmount(
                provider: .grok,
                snapshot: nil,
                providerCost: cost))
            #expect(amount.kind == "balance")
            #expect(amount.amount == balance)
            #expect(amount.observedAt == self.observed)
            #expect(amount.period == "Purchased credits")
        }
        let noBalance = ProviderCostSnapshot(used: 0, limit: 0, currencyCode: "USD", updatedAt: self.observed)
        #expect(SyncCoordinator.mapProviderAmount(provider: .grok, snapshot: nil, providerCost: noBalance) == nil)
    }

    @Test
    func `detail rows forward id progress and usage and old rows keep their wire shape`() throws {
        let progress = try ProviderDetailSection.Row.Progress(used: 2.5, total: 10)
        let sections: [ProviderDetailSection] = [
            .makeSection(title: "Cloud credits", rows: [
                .makeRow(
                    id: "claude-cloud-credits",
                    label: "Cloud credits",
                    value: "$7.50 of $10.00 remaining",
                    secondaryValue: "Expires 2026-11-01T00:00:00Z",
                    progress: progress,
                    usageValue: 7.5),
                .makeRow(label: "Plan", value: "Synthetic plan"),
            ]),
        ]
        let mapped = SyncCoordinator.mapSyncedDetails(sections, provider: .claude)
        let row = try #require(mapped.first?.rows.first)
        #expect(row.id == "claude-cloud-credits")
        #expect(row.progress == SyncProviderDetailSection.Row.Progress(used: 2.5, total: 10))
        #expect(row.usageValue == 7.5)

        let plain = try #require(mapped.first?.rows.last)
        let json = try #require(String(
            bytes: CloudSyncConstants.makeJSONEncoder().encode(plain),
            encoding: .utf8))
        // Rows without the new metadata must encode exactly as before so payload hashes stay stable.
        #expect(!json.contains("\"id\""))
        #expect(!json.contains("progress"))
        #expect(!json.contains("usageValue"))

        let data = try CloudSyncConstants.makeJSONEncoder().encode(mapped)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode([SyncProviderDetailSection].self, from: data)
        #expect(decoded == mapped)
    }

    @Test
    func `invalid row metadata is dropped without losing the row`() throws {
        let payload = Data(#"""
        {"label":"Cloud credits","value":"$1 left","id":"claude-cloud-credits",
         "progress":{"used":1,"total":0},"usageValue":"oops"}
        """#.utf8)
        let row = try CloudSyncConstants.makeJSONDecoder().decode(SyncProviderDetailSection.Row.self, from: payload)
        #expect(row.label == "Cloud credits")
        #expect(row.id == "claude-cloud-credits")
        #expect(row.progress == nil)
        #expect(row.usageValue == nil)
    }

    @Test
    func `Claude cloud credit rows from the live snapshot survive the mobile filter`() throws {
        let data = Data(#"{"limit_dollars":10,"used_dollars":2.5,"resets_at":"2026-11-01T00:00:00Z"}"#.utf8)
        let credits = try JSONDecoder().decode(ClaudeCloudCreditsSnapshot.self, from: data)
        let sections = credits.detailSections(now: self.observed) + [
            .makeSection(rows: [.makeRow(label: "Limit Reset Credits", value: "1 available")]),
        ]
        let mapped = SyncCoordinator.mapSyncedDetails(sections, provider: .claude)
        let rows = mapped.flatMap(\.rows)
        #expect(rows.map(\.label) == ["Cloud credits"])
        #expect(rows.first?.id == ClaudeCloudCreditsSnapshot.detailRowID)
        #expect(rows.first?.usageValue == 7.5)
        #expect(rows.first?.progress?.total == 10)
    }

    @Test
    func `balance descriptions publish only for providers whose Mac card shows them`() throws {
        let window = RateWindow(
            usedPercent: 24,
            windowMinutes: 43200,
            resetsAt: self.observed.addingTimeInterval(86400),
            resetDescription: " 3,800 / 5,000 credits left ")
        let plain = SyncCoordinator.syncRateWindow(id: "primary", label: "Monthly", window: window)
        let shown = SyncCoordinator.withBalanceDescription(plain, shows: true)
        #expect(shown.balanceDescription == "3,800 / 5,000 credits left")
        #expect(shown.resetDescription == " 3,800 / 5,000 credits left ")
        #expect(SyncCoordinator.withBalanceDescription(shown, shows: false) == plain)
        let hidden = SyncCoordinator.withBalanceDescription(plain, shows: false)
        #expect(hidden.balanceDescription == nil)
        let json = try #require(String(
            bytes: CloudSyncConstants.makeJSONEncoder().encode(hidden),
            encoding: .utf8))
        #expect(!json.contains("balanceDescription"))

        for provider in [UsageProvider.workbuddy, .museai] {
            #expect(ProviderDescriptorRegistry.descriptor(for: provider)
                .presentation.menuCard.showsPrimaryBalanceDescription)
        }
        #expect(!ProviderDescriptorRegistry.descriptor(for: .codex).presentation.menuCard
            .showsPrimaryBalanceDescription)
    }

    @Test
    func `older readers decode the new optional fields away`() throws {
        let window = SyncRateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: self.observed,
            resetDescription: "2.8B tokens left",
            balanceDescription: "2.8B tokens left")
        let data = try CloudSyncConstants.makeJSONEncoder().encode(window)
        let legacy = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(legacy["balanceDescription"] as? String == "2.8B tokens left")
        var stripped = legacy
        stripped.removeValue(forKey: "balanceDescription")
        let old = try CloudSyncConstants.makeJSONDecoder().decode(
            SyncRateWindow.self,
            from: JSONSerialization.data(withJSONObject: stripped))
        #expect(old.balanceDescription == nil)
        #expect(old.resetDescription == "2.8B tokens left")
    }

    @Test
    func `blocking projections drop the lane balance description`() throws {
        let snapshot = try KimiMonthlyBlockingTests.snapshot(ratio: 1)
        let raw = try #require(snapshot.primary)
        let annotated = SyncCoordinator.withBalanceDescription(
            SyncCoordinator.syncRateWindow(
                id: "primary",
                label: "Weekly",
                window: RateWindow(
                    usedPercent: raw.usedPercent,
                    windowMinutes: raw.windowMinutes,
                    resetsAt: raw.resetsAt,
                    resetDescription: "12 credits left")),
            shows: true)
        #expect(annotated.balanceDescription == "12 credits left")
        let projected = try #require(SyncCoordinator.projectingBlockingQuota(
            [annotated],
            provider: .kimi,
            snapshot: snapshot).first)
        #expect(projected.blockingQuota != nil)
        #expect(projected.balanceDescription == nil)
    }
}
