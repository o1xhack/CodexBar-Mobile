import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

@Suite("SwiftDataBridge Tests")
struct SwiftDataBridgeTests {

    // MARK: - Fixtures

    private func makeContainer() -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarBridgeTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Store.sqlite")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        return ModelContainerFactory.makeContainer(at: url)
    }

    private let ts1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let ts2 = Date(timeIntervalSince1970: 1_700_003_600)

    private func makeProvider(
        id: String = "claude",
        name: String = "Claude",
        email: String? = "user@example.com",
        lastUpdated: Date,
        utilization: [SyncUtilizationSeries]? = nil,
        subscriptionExpiresAt: Date? = nil,
        subscriptionRenewsAt: Date? = nil,
        accountIdentities: [String]? = nil,
        quotaWarnings: SyncQuotaWarningConfig? = nil
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            subscriptionExpiresAt: subscriptionExpiresAt,
            subscriptionRenewsAt: subscriptionRenewsAt,
            rateWindows: [],
            utilizationHistory: utilization,
            accountIdentities: accountIdentities,
            quotaWarnings: quotaWarnings)
    }

    private func makeSnapshot(
        deviceID: String?,
        deviceName: String = "Mac",
        providers: [ProviderUsageSnapshot],
        timestamp: Date
    ) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: timestamp,
            deviceName: deviceName,
            deviceID: deviceID,
            appVersion: "0.20.0")
    }

    // MARK: - Tests

    @Test("Upserting the same snapshot twice does not duplicate rows")
    func testUpsertIdempotency() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        let snapshot = self.makeSnapshot(
            deviceID: "device-A",
            providers: [self.makeProvider(lastUpdated: self.ts1)],
            timestamp: self.ts1)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)
        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)

        let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(devices.count == 1)
        #expect(providers.count == 1)
    }

    @Test("Two devices with the same provider produce two distinct rows")
    func testMultiDeviceInsert() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        let snapA = self.makeSnapshot(
            deviceID: "device-A",
            deviceName: "Mac A",
            providers: [self.makeProvider(lastUpdated: self.ts1)],
            timestamp: self.ts1)
        let snapB = self.makeSnapshot(
            deviceID: "device-B",
            deviceName: "Mac B",
            providers: [self.makeProvider(lastUpdated: self.ts2)],
            timestamp: self.ts2)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapA, snapB], into: context)

        let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(devices.count == 2)
        #expect(providers.count == 2)
        let deviceIDs = Set(providers.map(\.deviceID))
        #expect(deviceIDs == Set(["device-A", "device-B"]))
    }

    @Test("Utilization entries dedup on (seriesName, capturedAt)")
    func testUtilizationEntryDedup() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        let captured = Date(timeIntervalSince1970: 1_700_001_000)
        let series = SyncUtilizationSeries(
            name: "session",
            windowMinutes: 300,
            entries: [
                SyncUtilizationEntry(capturedAt: captured, usedPercent: 42.0, resetsAt: nil),
            ])
        let provider = self.makeProvider(lastUpdated: self.ts1, utilization: [series])
        let snapshot = self.makeSnapshot(
            deviceID: "device-A",
            providers: [provider],
            timestamp: self.ts1)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)
        // Upsert again with the same entry — should not insert a second row.
        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)

        let entries = try context.fetch(FetchDescriptor<UtilizationEntryModel>())
        #expect(entries.count == 1)
        #expect(entries.first?.usedPercent == 42.0)
    }

    @Test("Updating a provider field is reflected on the existing row")
    func testUpsertUpdatesInPlace() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        let first = self.makeSnapshot(
            deviceID: "device-A",
            providers: [self.makeProvider(name: "Claude", lastUpdated: self.ts1)],
            timestamp: self.ts1)
        try SwiftDataBridge.upsert(deviceSnapshots: [first], into: context)

        let second = self.makeSnapshot(
            deviceID: "device-A",
            providers: [self.makeProvider(name: "Claude Code", lastUpdated: self.ts2)],
            timestamp: self.ts2)
        try SwiftDataBridge.upsert(deviceSnapshots: [second], into: context)

        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(providers.count == 1)
        #expect(providers.first?.providerName == "Claude Code")
        #expect(providers.first?.lastUpdated == self.ts2)
    }

    @Test("Subscription metadata survives SwiftData bridge round-trip")
    func testSubscriptionMetadataRoundTrip() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)
        let expiresAt = Date(timeIntervalSince1970: 1_801_000_000)
        let renewsAt = Date(timeIntervalSince1970: 1_800_500_000)
        let provider = self.makeProvider(
            id: "minimax",
            name: "MiniMax",
            lastUpdated: self.ts1,
            subscriptionExpiresAt: expiresAt,
            subscriptionRenewsAt: renewsAt)
        let snapshot = self.makeSnapshot(
            deviceID: "device-subscription",
            providers: [provider],
            timestamp: self.ts1)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)
        let decoded = try SwiftDataBridge.readAllDeviceSnapshots(from: context)
        let decodedProvider = try #require(decoded.first?.providers.first)
        #expect(decodedProvider.subscriptionExpiresAt == expiresAt)
        #expect(decodedProvider.subscriptionRenewsAt == renewsAt)
    }

    @Test("Rich provider payload survives SwiftData bridge round-trip")
    func testRichProviderPayloadRoundTrip() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)
        let quotaWarnings = SyncQuotaWarningConfig(
            sessionThresholds: [60, 25],
            sessionEnabled: true,
            weeklyThresholds: [80],
            weeklyEnabled: false)
        let provider = self.makeProvider(
            id: "minimax",
            name: "MiniMax",
            lastUpdated: self.ts1,
            accountIdentities: ["minimax:email:user@example.com"],
            quotaWarnings: quotaWarnings)
        let snapshot = self.makeSnapshot(
            deviceID: "device-rich-payload",
            providers: [provider],
            timestamp: self.ts1)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)
        let decoded = try SwiftDataBridge.readAllDeviceSnapshots(from: context)
        let decodedProvider = try #require(decoded.first?.providers.first)
        #expect(decodedProvider.accountIdentities == ["minimax:email:user@example.com"])
        #expect(decodedProvider.quotaWarnings == quotaWarnings)
    }

    @Test("Snapshots without deviceID map to a deterministic fallback row")
    func testLegacySnapshotFallbackDeviceID() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        // Legacy KVS snapshot — single-device Mac, no deviceID but stable deviceName.
        let legacy = SyncedUsageSnapshot(
            providers: [self.makeProvider(lastUpdated: self.ts1)],
            syncTimestamp: self.ts1,
            deviceName: "Old Mac",
            deviceID: nil)

        try SwiftDataBridge.upsert(deviceSnapshots: [legacy], into: context)
        try SwiftDataBridge.upsert(deviceSnapshots: [legacy], into: context)

        let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
        #expect(devices.count == 1)
        #expect(devices.first?.deviceID.hasPrefix("legacy:") == true)
    }

    @Test("Utilization entries aged out upstream are pruned locally")
    func testUtilizationEntriesPruned() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        let e1 = SyncUtilizationEntry(capturedAt: self.ts1, usedPercent: 10, resetsAt: nil)
        let e2 = SyncUtilizationEntry(capturedAt: self.ts2, usedPercent: 20, resetsAt: nil)
        let seriesBoth = SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [e1, e2])
        let providerBoth = self.makeProvider(lastUpdated: self.ts2, utilization: [seriesBoth])
        let snapshot1 = self.makeSnapshot(
            deviceID: "mac-prune",
            providers: [providerBoth],
            timestamp: self.ts2)
        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot1], into: context)

        let rowsAfterFirst = try context.fetch(FetchDescriptor<UtilizationEntryModel>())
        #expect(rowsAfterFirst.count == 2)

        // Second upsert drops e1 from the rolling window — only e2 remains upstream.
        let seriesPruned = SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [e2])
        let providerPruned = self.makeProvider(lastUpdated: self.ts2, utilization: [seriesPruned])
        let snapshot2 = self.makeSnapshot(
            deviceID: "mac-prune",
            providers: [providerPruned],
            timestamp: self.ts2)
        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot2], into: context)

        let rowsAfterSecond = try context.fetch(FetchDescriptor<UtilizationEntryModel>())
        #expect(rowsAfterSecond.count == 1)
        #expect(rowsAfterSecond.first?.capturedAt == self.ts2)
    }

    // MARK: - Realistic-distribution fixtures (Build 83 · Agent C)
    //
    // Round 3 of the 5-round audit flagged SwiftDataBridge's Storage layer
    // as under-tested on production-shaped data. These 3 tests exercise
    // the same upsert / pruning path with (1) 720 hourly zero entries,
    // (2) two entries straddling a session reset in the same clock hour,
    // (3) multi-account same provider.

    @Test("Upsert survives all-zero 720-entry utilization roundtrip without dropping entries")
    func realisticAllZeroUtilizationRoundtrip() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        let series = TestFixtures.allZeroSessionSeries(anchor: self.ts1)
        let snapshot = self.makeSnapshot(
            deviceID: "device-zero",
            providers: [self.makeProvider(
                lastUpdated: self.ts1,
                utilization: [series])],
            timestamp: self.ts1)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)

        let entries = try context.fetch(FetchDescriptor<UtilizationEntryModel>())
        #expect(entries.count == 720)
        // All preserved at 0%; a regression that "prunes" zero entries as
        // uninteresting would drop the count below 720.
        #expect(entries.allSatisfy { $0.usedPercent == 0 })
    }

    @Test("Cross-reset boundary entries in same clock hour don't collide in SwiftData")
    func realisticCrossResetBoundaryPreservedInStorage() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        // Two entries in the same calendar hour but different reset windows.
        // SwiftData's composite key must separate them (or the reset epoch
        // must be part of the key); a regression that keys purely on
        // (series, capturedAt.hour) would drop one of the two.
        let entries = TestFixtures.crossResetBoundaryEntries(anchor: self.ts1)
        let series = SyncUtilizationSeries(
            name: "session", windowMinutes: 300, entries: entries)
        let snapshot = self.makeSnapshot(
            deviceID: "device-reset",
            providers: [self.makeProvider(
                lastUpdated: self.ts1,
                utilization: [series])],
            timestamp: self.ts1)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)

        let stored = try context.fetch(FetchDescriptor<UtilizationEntryModel>())
        #expect(stored.count == 2)
        let percents = Set(stored.map(\.usedPercent))
        #expect(percents == [90, 5])
    }

    @Test("Multi-account same provider persists as two distinct rows")
    func realisticMultiAccountSameProviderPreserved() throws {
        let container = self.makeContainer()
        let context = ModelContext(container)

        // `providerID|accountEmail` composite key must keep alice / bob
        // separate; a regression that collapses to providerID alone would
        // show 1 row and one account's data lost.
        let providers = TestFixtures.multiAccountProviders(
            id: "codex",
            emails: ["alice@example.com", "bob@example.com"],
            lastUpdated: self.ts1)
        let snapshot = self.makeSnapshot(
            deviceID: "device-multi",
            providers: providers,
            timestamp: self.ts1)

        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)

        let rows = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        #expect(rows.count == 2)
        let emails = Set(rows.compactMap(\.accountEmail))
        #expect(emails == ["alice@example.com", "bob@example.com"])
    }
}
