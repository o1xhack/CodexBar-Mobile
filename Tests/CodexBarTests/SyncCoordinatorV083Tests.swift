import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SyncCoordinatorV083Tests {
    @Test
    func `Organization credits remain available after personal pools run out`() {
        let spent = RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: "100/100 credits")
        let organization = RateWindow(
            usedPercent: 20,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: "20/100 credits")
        let snapshot = UsageSnapshot(
            primary: spent,
            secondary: spent,
            tertiary: spent,
            extraRateWindows: [.init(
                id: "org-credits",
                title: "Organization",
                window: organization)],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let windows = ["primary", "secondary", "tertiary", "org-credits"].map { id in
            SyncCoordinator.syncRateWindow(
                id: id,
                label: id,
                window: id == "org-credits" ? organization : spent)
        }
        let ordered = SyncCoordinator.orderedPerplexitySyncWindows(windows, snapshot: snapshot)
        #expect(ordered.first?.id == "org-credits")
        #expect(ordered.first?.usedPercent == 20)
        #expect(Set(ordered.compactMap(\.id)) == Set(windows.compactMap(\.id)))
        #expect(SyncCoordinator.orderedPerplexitySyncWindows(windows, snapshot: snapshot) == ordered)
    }

    @Test
    func `OpenDesign quotas retain limits and workspace stays source scoped`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let window = RateWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3600),
            resetDescription: nil,
            quotaLimit: 200,
            quotaUnit: "credits")
        let snapshot = UsageSnapshot(primary: window, secondary: nil, updatedAt: now)
        let synced = try #require(SyncCoordinator.syncPrimaryRateWindow(
            provider: .opendesign,
            snapshot: snapshot,
            metadata: ProviderDefaults
                .metadata[.opendesign]))
        #expect(synced.label == "Session")
        #expect(synced.quotaLimit == 200)
        #expect(synced.quotaUnit == "credits")
        #expect(AccountIdentityComputer.compute(provider: .opendesign, identity: nil) == nil)
        #expect(QuotaProviderList.providers.last?.id == "opendesign")
        #expect(MockProviderInjector.allMocks().contains { $0.providerID == "opendesign" })
    }
}
