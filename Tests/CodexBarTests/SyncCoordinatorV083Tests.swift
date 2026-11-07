import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SyncCoordinatorV083Tests {
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

    @Test
    func `Different OpenDesign workspaces on two Macs do not merge by a shared label`() throws {
        let identifiers = ["mac-a", "mac-b"].enumerated().map { index, device in
            let identity = ProviderIdentitySnapshot(
                providerID: .opendesign,
                accountEmail: nil,
                accountOrganization: "Shared workspace name",
                loginMethod: "Pro",
                accountID: "workspace-\(index)")
            let key = SyncCoordinator.syncAccountRecordKey(
                provider: .opendesign,
                requested: nil,
                deviceID: device,
                identity: identity)
            return SyncCoordinator.syncAccountIdentities(
                provider: .opendesign,
                identity: identity,
                accountRecordKey: key)
        }
        #expect(identifiers[0] == ["opendesign:record:device-mac-a"])
        #expect(identifiers[1] == ["opendesign:record:device-mac-b"])
        #expect(try Set(#require(identifiers[0])).isDisjoint(with: #require(identifiers[1])))
    }
}
