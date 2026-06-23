import CloudKit
import CodexBarSync
import Foundation
import Testing

@testable import CodexBarMobile

@Suite("DeviceLifecycleEvent device management")
struct DeviceLifecycleEventTests {
    @Test("DeviceLifecycleEvent round-trips through JSON")
    func lifecycleCodableRoundTrip() throws {
        let event = DeviceLifecycleEvent(
            recordID: "event-1",
            kind: .alias,
            primaryDeviceID: "new-mac",
            relatedDeviceIDs: ["old-mac"],
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
            confirmedFromDeviceID: "iphone-a",
            note: "manual merge")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(DeviceLifecycleEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test("CKRecord encode decode round-trips without reserved recordID field")
    func lifecycleCKRecordRoundTrip() throws {
        let original = DeviceLifecycleEvent(
            recordID: "F84A2B7C-AAAA-BBBB-CCCC-DDDDDDDDDDDD",
            kind: .archive,
            primaryDeviceID: "old-mac",
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
            confirmedFromDeviceID: "iphone-a")

        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.providerZoneName,
            ownerName: CKCurrentUserDefaultName)
        let ckRecordID = CKRecord.ID(
            recordName: DeviceLifecycleEvent.recordName(for: original.recordID),
            zoneID: zoneID)
        let record = CKRecord(
            recordType: CloudSyncConstants.deviceLifecycleEventRecordType,
            recordID: ckRecordID)
        record["kind"] = original.kind.rawValue as CKRecordValue
        record["primaryDeviceID"] = original.primaryDeviceID as CKRecordValue
        record["relatedDeviceIDs"] = original.relatedDeviceIDs as CKRecordValue
        record["confirmedAt"] = original.confirmedAt as CKRecordValue
        record["confirmedFromDeviceID"] = original.confirmedFromDeviceID as CKRecordValue

        let decoded = try #require(CloudSyncManager.decodeDeviceLifecycleEvent(from: record))
        #expect(decoded == original)
    }

    @Test("Alias collapses duplicate Mac IDs into one active device")
    func aliasCollapsesDuplicateMacIDs() {
        let oldMac = Self.makeMac(deviceID: "old", deviceName: "Pixel's Mac", cost: 1, timestamp: 100)
        let newMac = Self.makeMac(deviceID: "new", deviceName: "Pixel's Mac", cost: 2, timestamp: 200)
        let alias = DeviceLifecycleEvent(
            kind: .alias,
            primaryDeviceID: "new",
            relatedDeviceIDs: ["old"],
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [oldMac, newMac],
            lifecycleEvents: [alias])

        #expect(resolved.activeSnapshots.count == 1)
        #expect(resolved.archivedSnapshots.isEmpty)
        #expect(resolved.items.first?.isMergedAlias == true)
        #expect(resolved.activeSnapshots.first?.deviceID == "new")
    }

    @Test("Unalias restores the original device identities")
    func unaliasRestoresDuplicateMacIDs() {
        let oldMac = Self.makeMac(deviceID: "old", deviceName: "Pixel's Mac", cost: 1, timestamp: 100)
        let newMac = Self.makeMac(deviceID: "new", deviceName: "Pixel's Mac", cost: 2, timestamp: 200)
        let alias = DeviceLifecycleEvent(
            kind: .alias,
            primaryDeviceID: "new",
            relatedDeviceIDs: ["old"],
            confirmedFromDeviceID: "iphone-a")
        let unalias = DeviceLifecycleEvent(
            kind: .unalias,
            primaryDeviceID: "old",
            relatedDeviceIDs: ["new"],
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [oldMac, newMac],
            lifecycleEvents: [alias, unalias])

        #expect(resolved.activeSnapshots.count == 2)
        #expect(resolved.items.allSatisfy { !$0.isMergedAlias })
    }

    @Test("Unalias of a merged group suppresses constituent alias edges")
    func unaliasSuppressesConstituentAliasEdges() {
        let macA = Self.makeMac(deviceID: "a", deviceName: "Pixel's Mac", cost: 1, timestamp: 100)
        let macB = Self.makeMac(deviceID: "b", deviceName: "Pixel's Mac", cost: 2, timestamp: 200)
        let macC = Self.makeMac(deviceID: "c", deviceName: "Pixel's Mac", cost: 3, timestamp: 300)
        let aliasAB = DeviceLifecycleEvent(
            recordID: "alias-ab",
            kind: .alias,
            primaryDeviceID: "b",
            relatedDeviceIDs: ["a"],
            confirmedAt: Date(timeIntervalSince1970: 100),
            confirmedFromDeviceID: "iphone-a")
        let aliasBC = DeviceLifecycleEvent(
            recordID: "alias-bc",
            kind: .alias,
            primaryDeviceID: "c",
            relatedDeviceIDs: ["b"],
            confirmedAt: Date(timeIntervalSince1970: 200),
            confirmedFromDeviceID: "iphone-a")
        let unaliasABC = DeviceLifecycleEvent(
            recordID: "unalias-abc",
            kind: .unalias,
            primaryDeviceID: "a",
            relatedDeviceIDs: ["b", "c"],
            confirmedAt: Date(timeIntervalSince1970: 300),
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [macA, macB, macC],
            lifecycleEvents: [aliasAB, aliasBC, unaliasABC])

        #expect(resolved.activeSnapshots.count == 3)
        #expect(resolved.items.allSatisfy { !$0.isMergedAlias })
        #expect(resolved.activeSnapshots.compactMap(\.deviceID).sorted() == ["a", "b", "c"])
    }

    @Test("Later alias can re-merge devices after unalias")
    func laterAliasCanRemergeAfterUnalias() {
        let oldMac = Self.makeMac(deviceID: "old", deviceName: "Pixel's Mac", cost: 1, timestamp: 100)
        let newMac = Self.makeMac(deviceID: "new", deviceName: "Pixel's Mac", cost: 2, timestamp: 200)
        let alias = DeviceLifecycleEvent(
            recordID: "alias-old-new-1",
            kind: .alias,
            primaryDeviceID: "new",
            relatedDeviceIDs: ["old"],
            confirmedAt: Date(timeIntervalSince1970: 100),
            confirmedFromDeviceID: "iphone-a")
        let unalias = DeviceLifecycleEvent(
            recordID: "unalias-old-new",
            kind: .unalias,
            primaryDeviceID: "old",
            relatedDeviceIDs: ["new"],
            confirmedAt: Date(timeIntervalSince1970: 200),
            confirmedFromDeviceID: "iphone-a")
        let laterAlias = DeviceLifecycleEvent(
            recordID: "alias-old-new-2",
            kind: .alias,
            primaryDeviceID: "new",
            relatedDeviceIDs: ["old"],
            confirmedAt: Date(timeIntervalSince1970: 300),
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [oldMac, newMac],
            lifecycleEvents: [alias, unalias, laterAlias])

        #expect(resolved.activeSnapshots.count == 1)
        #expect(resolved.archivedSnapshots.isEmpty)
        #expect(resolved.items.first?.isMergedAlias == true)
        #expect(resolved.activeSnapshots.first?.deviceID == "new")
    }

    @Test("Archive excludes a retired Mac from active devices")
    func archiveExcludesRetiredDevice() {
        let oldMac = Self.makeMac(deviceID: "old", deviceName: "Old Mac", cost: 1, timestamp: 100)
        let newMac = Self.makeMac(deviceID: "new", deviceName: "New Mac", cost: 2, timestamp: 200)
        let archive = DeviceLifecycleEvent(
            kind: .archive,
            primaryDeviceID: "old",
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [oldMac, newMac],
            lifecycleEvents: [archive])

        #expect(resolved.activeSnapshots.compactMap(\.deviceID).sorted() == ["new"])
        #expect(resolved.archivedSnapshots.compactMap(\.deviceID) == ["old"])
        #expect(resolved.items.first(where: { $0.canonicalDeviceID == "old" })?.isArchived == true)
    }

    @Test("Archived merged alias stays archived when canonical device changes")
    func archivedMergedAliasSurvivesCanonicalShift() {
        let oldCanonical = Self.makeMac(deviceID: "old", deviceName: "Pixel's Mac", cost: 1, timestamp: 100)
        let newerAlias = Self.makeMac(deviceID: "new", deviceName: "Pixel's Mac", cost: 2, timestamp: 300)
        let alias = DeviceLifecycleEvent(
            kind: .alias,
            primaryDeviceID: "old",
            relatedDeviceIDs: ["new"],
            confirmedFromDeviceID: "iphone-a")
        let archiveOldCanonical = DeviceLifecycleEvent(
            kind: .archive,
            primaryDeviceID: "old",
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [oldCanonical, newerAlias],
            lifecycleEvents: [alias, archiveOldCanonical])

        let item = resolved.items.first
        #expect(resolved.activeSnapshots.isEmpty)
        #expect(resolved.archivedSnapshots.count == 1)
        #expect(item?.canonicalDeviceID == "new")
        #expect(item?.isArchived == true)
    }

    @Test("Unarchive restores an archived Mac")
    func unarchiveRestoresDevice() {
        let oldMac = Self.makeMac(deviceID: "old", deviceName: "Old Mac", cost: 1, timestamp: 100)
        let archive = DeviceLifecycleEvent(
            kind: .archive,
            primaryDeviceID: "old",
            confirmedAt: Date(timeIntervalSince1970: 100),
            confirmedFromDeviceID: "iphone-a")
        let unarchive = DeviceLifecycleEvent(
            kind: .unarchive,
            primaryDeviceID: "old",
            confirmedAt: Date(timeIntervalSince1970: 200),
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [oldMac],
            lifecycleEvents: [archive, unarchive])

        #expect(resolved.activeSnapshots.count == 1)
        #expect(resolved.archivedSnapshots.isEmpty)
    }

    @Test("Same-name real Macs do not auto-merge")
    func sameNameMacsDoNotAutoMerge() {
        let macA = Self.makeMac(deviceID: "a", deviceName: "MacBook Pro", cost: 1, timestamp: 100)
        let macB = Self.makeMac(deviceID: "b", deviceName: "MacBook Pro", cost: 2, timestamp: 200)

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [macA, macB],
            lifecycleEvents: [])

        #expect(resolved.activeSnapshots.count == 2)
    }

    @Test("Alias group does not double-count local-cost providers")
    func aliasDoesNotDoubleCountLocalCost() throws {
        let oldMac = Self.makeMac(deviceID: "old", deviceName: "Pixel's Mac", cost: 1, timestamp: 100)
        let newMac = Self.makeMac(deviceID: "new", deviceName: "Pixel's Mac", cost: 2, timestamp: 200)
        let alias = DeviceLifecycleEvent(
            kind: .alias,
            primaryDeviceID: "new",
            relatedDeviceIDs: ["old"],
            confirmedFromDeviceID: "iphone-a")

        let resolved = CloudSyncReader.resolveDeviceSnapshots(
            [oldMac, newMac],
            lifecycleEvents: [alias])
        let provider = try #require(resolved.activeSnapshots.first?.providers.first)

        #expect(provider.costSummary?.sessionCostUSD == 2)
        #expect(provider.costSummary?.last30DaysCostUSD == 2)
    }

    private static func makeMac(
        deviceID: String,
        deviceName: String,
        cost: Double,
        timestamp: TimeInterval
    ) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            providers: [Self.makeClaudeProvider(cost: cost, timestamp: timestamp)],
            syncTimestamp: Date(timeIntervalSince1970: timestamp),
            deviceName: deviceName,
            deviceID: deviceID,
            appVersion: "0.36.1",
            mobileVersion: "1.13.0")
    }

    private static func makeClaudeProvider(
        cost: Double,
        timestamp: TimeInterval
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: timestamp),
            costSummary: SyncCostSummary(
                sessionCostUSD: cost,
                sessionTokens: nil,
                last30DaysCostUSD: cost,
                last30DaysTokens: nil,
                daily: [
                    SyncDailyPoint(dayKey: "2026-06-20", costUSD: cost, totalTokens: 100),
                ]),
            accountIdentities: ["claude:account:pixel"])
    }
}
