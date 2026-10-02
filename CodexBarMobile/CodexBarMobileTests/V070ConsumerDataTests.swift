import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

@Suite("v0.70 consumer data preservation")
struct V070ConsumerDataTests {
    private let captured = Date(timeIntervalSince1970: 1_791_000_000)

    private func snapshot(
        device: String,
        history: [SyncUtilizationSeries],
        windows: [SyncRateWindow] = [],
        updatedAt: Date? = nil,
        providerID: String = "codex") -> SyncedUsageSnapshot
    {
        let provider = ProviderUsageSnapshot(
            providerID: providerID,
            providerName: "Fixture Provider",
            primary: windows.first,
            secondary: nil,
            accountEmail: "fixture@example.invalid",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: updatedAt ?? self.captured,
            rateWindows: windows,
            utilizationHistory: history)
        return SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: max(
                updatedAt ?? self.captured, self.captured.addingTimeInterval(120)),
            deviceName: device,
            deviceID: device)
    }

    @Test func `Same-hour declines and distinct reset cycles retain actual observations`() throws {
        let reset = self.captured.addingTimeInterval(3000)
        let entries = [
            SyncUtilizationEntry(capturedAt: self.captured, usedPercent: 90, resetsAt: reset),
            SyncUtilizationEntry(capturedAt: self.captured.addingTimeInterval(60), usedPercent: 20, resetsAt: reset),
            SyncUtilizationEntry(
                capturedAt: self.captured.addingTimeInterval(120),
                usedPercent: 5,
                resetsAt: reset.addingTimeInterval(300 * 60)),
        ]
        let a = self.snapshot(device: "fixture-a", history: [
            SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: entries.reversed()),
        ])
        let b = self.snapshot(device: "fixture-b", history: [
            SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [entries[0]]),
        ])
        for sources in [[a, b], [b, a]] {
            let merged = try #require(ProviderSnapshotMerger.mergeSnapshots(sources))
            #expect(merged.providers.first?.utilizationHistory?.first?.entries == entries)
        }
    }

    @Test func `Changed lane duration excludes older-duration history and invalid observations`() throws {
        let a = self.snapshot(device: "fixture-a", history: [
            SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [
                .init(capturedAt: self.captured, usedPercent: 80, resetsAt: nil),
            ]),
        ])
        let latest = SyncUtilizationEntry(
            capturedAt: self.captured.addingTimeInterval(60), usedPercent: 10, resetsAt: nil)
        let b = self.snapshot(device: "fixture-b", history: [
            SyncUtilizationSeries(name: "session", windowMinutes: 60, entries: [
                latest,
                .init(capturedAt: self.captured, usedPercent: .nan, resetsAt: nil),
                .init(capturedAt: Date(timeIntervalSince1970: .infinity), usedPercent: 30, resetsAt: nil),
                .init(
                    capturedAt: self.captured,
                    usedPercent: 30,
                    resetsAt: Date(timeIntervalSince1970: .infinity)),
            ]),
        ])
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([a, b]))
        let series = try #require(merged.providers.first?.utilizationHistory?.first)
        #expect(series.windowMinutes == 60)
        #expect(series.entries == [latest])
    }

    @Test func `Future observations cannot select a different lane duration`() throws {
        let actual = SyncUtilizationEntry(capturedAt: self.captured, usedPercent: 20, resetsAt: nil)
        let a = self.snapshot(device: "fixture-a", history: [
            SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [actual]),
        ])
        let b = self.snapshot(device: "fixture-b", history: [
            SyncUtilizationSeries(name: "session", windowMinutes: 60, entries: [
                .init(capturedAt: self.captured.addingTimeInterval(86400), usedPercent: 90, resetsAt: nil),
            ]),
        ])
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([a, b]))
        #expect(merged.providers.first?.utilizationHistory?.first?.windowMinutes == 300)
        #expect(merged.providers.first?.utilizationHistory?.first?.entries == [actual])
    }

    @Test func `Latest blocked Kimi observation cannot acquire older available lanes`() throws {
        let older = self.snapshot(
            device: "fixture-a",
            history: [],
            windows: [
                .init(
                    label: "Rate Limit",
                    usedPercent: 10,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
            ],
            providerID: "kimi")
        let blocked = SyncRateWindow(
            label: "Weekly",
            usedPercent: 100,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil,
            blockingQuota: SyncBlockingQuota(
                windowID: "monthly",
                rawUsedPercent: 25,
                rawResetsAt: nil,
                rawResetDescription: nil,
                rawNextRegenPercent: 5))
        let newer = self.snapshot(
            device: "fixture-b",
            history: [],
            windows: [blocked],
            updatedAt: self.captured.addingTimeInterval(60),
            providerID: "kimi")
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([older, newer]))
        #expect(merged.providers.first?.rateWindows == [blocked])
        #expect(merged.providers.first?.primary == blocked)
    }

    @Test func `Token-only model observations survive combination without invented prices`() throws {
        let days = TokenActivity.combine([
            .init(
                dayKey: "2026-10-01",
                costUSD: 0,
                totalTokens: 20,
                costIsKnown: false,
                modelsUsed: ["FictitiousModelB", "FictitiousModelA"]),
            .init(
                dayKey: "2026-10-01",
                costUSD: 0,
                totalTokens: 30,
                costIsKnown: false,
                modelsUsed: ["FictitiousModelA"]),
        ])
        let day = try #require(days.first)
        #expect(day.modelsUsed == ["FictitiousModelA", "FictitiousModelB"])
        #expect(day.totalTokens == 50)
        #expect(day.costIsKnown == false)
        #expect(day.modelBreakdowns.isEmpty)
    }

    @Test func `Same-capture conflicts use publication authority rather than the largest percentage`() throws {
        let high = SyncUtilizationEntry(capturedAt: self.captured, usedPercent: 90, resetsAt: nil)
        let low = SyncUtilizationEntry(capturedAt: self.captured, usedPercent: 20, resetsAt: nil)
        let older = self.snapshot(device: "fixture-z", history: [
            .init(name: "session", windowMinutes: 300, entries: [high]),
        ])
        let newer = self.snapshot(
            device: "fixture-a",
            history: [
                .init(name: "session", windowMinutes: 300, entries: [low]),
            ],
            updatedAt: self.captured.addingTimeInterval(180))
        for sources in [[older, newer], [newer, older]] {
            let merged = try #require(ProviderSnapshotMerger.mergeSnapshots(sources))
            #expect(merged.providers.first?.utilizationHistory?.first?.entries == [low])
        }
    }

    @Test func `Local-cost Mac union preserves observed models independently of pricing`() throws {
        func source(device: String, models: [String]?) -> SyncedUsageSnapshot {
            let point = SyncDailyPoint(
                dayKey: "2026-10-01",
                costUSD: 0,
                totalTokens: 20,
                costIsKnown: false,
                modelsUsed: models)
            let provider = ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Fixture Provider",
                primary: nil,
                secondary: nil,
                accountEmail: "fixture@example.invalid",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.captured,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: nil,
                    last30DaysTokens: nil,
                    daily: [point],
                    currencyCode: "USD"))
            return SyncedUsageSnapshot(
                providers: [provider],
                syncTimestamp: self.captured,
                deviceName: device,
                deviceID: device)
        }
        let a = source(device: "fixture-a", models: ["FictitiousModelA", "FictitiousModelB"])
        let b = source(device: "fixture-b", models: ["FictitiousModelB", "FictitiousModelC"])
        let legacy = source(device: "fixture-old", models: nil)
        for sources in [[a, b, legacy], [legacy, b, a]] {
            let merged = try #require(ProviderSnapshotMerger.mergeSnapshots(sources))
            let point = try #require(merged.providers.first?.costSummary?.daily.first)
            #expect(point.modelsUsed == ["FictitiousModelA", "FictitiousModelB", "FictitiousModelC"])
            #expect(point.totalTokens == 60)
            #expect(point.costIsKnown == false)
            #expect(point.modelBreakdowns.isEmpty)
        }
    }

    @Test @MainActor
    func `Two ledger writers preserve observed model union without priced breakdowns`() throws {
        let schema = Schema(CodexBarSwiftDataSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        for (device, models) in [
            ("fixture-a", ["FictitiousModelA", "FictitiousModelB"]),
            ("fixture-b", ["FictitiousModelB", "FictitiousModelC"]),
        ] {
            try CostLedgerService.upsertDayPoint(
                deviceID: device,
                providerID: "codex",
                accountEmail: "fixture@example.invalid",
                dayKey: "2026-10-01",
                costUSD: 0,
                totalTokens: 20,
                costIsKnown: false,
                isEstimated: nil,
                modelsUsed: models,
                modelBreakdowns: [],
                serviceBreakdowns: [],
                lastUpdated: self.captured,
                in: context)
        }
        let referenceDate = try #require(ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z"))
        let result = try CostLedgerService.aggregate(
            windowDays: 30,
            in: context,
            asOf: referenceDate,
            readerTimeZone: .gmt)
        #expect(result.dailyPoints.first?.modelsUsed == [
            "FictitiousModelA", "FictitiousModelB", "FictitiousModelC",
        ])
        #expect(result.dailyPoints.first?.totalTokens == 40)
        #expect(result.modelMix.isEmpty)
    }

    @Test @MainActor
    func `Single-writer history rendering rejects invalid dates and bounds huge gaps`() {
        let series = SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [
            .init(capturedAt: Date(timeIntervalSince1970: .infinity), usedPercent: 30, resetsAt: nil),
            .init(capturedAt: self.captured, usedPercent: .nan, resetsAt: nil),
            .init(capturedAt: Date(timeIntervalSince1970: -1e18), usedPercent: 10, resetsAt: nil),
            .init(capturedAt: self.captured, usedPercent: 20, resetsAt: nil),
        ])
        let points = UtilizationHistoryView.buildPeriodPoints(from: series)
        #expect(points.count == 90)
        #expect(points.last?.usedPercent == 20)
        #expect(points.last?.isObserved == true)
    }

    @Test @MainActor
    func `Equal-time nil-field ledger backfill persists model observations after reopening`() throws {
        let base = URL(fileURLWithPath: "/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070")
        // Runner verifies the mounted volume UUID before testing. Never create
        // the root here: a disconnected SSD must not produce a local look-alike.
        guard FileManager.default.fileExists(atPath: base.path),
              FileManager.default.isWritableFile(atPath: base.path),
              base.resolvingSymlinksInPath().path.hasPrefix("/Volumes/StudioSSD/")
        else { throw CocoaError(.fileNoSuchFile) }
        let root = base.appendingPathComponent("consumer-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store.sqlite")
        func write(context: ModelContext, names: [String]?) throws {
            try CostLedgerService.upsertDayPoint(
                deviceID: "fixture-a",
                providerID: "codex",
                dayKey: "2026-10-01",
                costUSD: 0,
                totalTokens: 20,
                costIsKnown: false,
                isEstimated: nil,
                modelsUsed: names,
                modelBreakdowns: [],
                serviceBreakdowns: [],
                lastUpdated: self.captured,
                in: context)
        }
        do {
            let container = ModelContainerFactory.makeContainer(at: store)
            let context = ModelContext(container)
            try write(context: context, names: nil)
            try context.save()
            #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).first?.modelsUsedData == nil)
            try write(context: context, names: ["FictitiousModelB", "FictitiousModelA", "FictitiousModelA"])
            try context.save()
        }
        let reopened = ModelContainerFactory.makeContainer(at: store)
        let context = ModelContext(reopened)
        let row = try #require(try context.fetch(FetchDescriptor<DailyCostPoint>()).first)
        let names = try JSONDecoder().decode([String].self, from: #require(row.modelsUsedData))
        #expect(names == ["FictitiousModelA", "FictitiousModelB"])
        let referenceDate = try #require(ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z"))
        let rollup = try CostLedgerService.aggregate(
            windowDays: 30,
            in: context,
            asOf: referenceDate,
            readerTimeZone: .gmt)
        #expect(rollup.dailyPoints.first?.modelsUsed == names)
        #expect(rollup.dailyPoints.first?.costIsKnown == false)
        #expect(rollup.dailyPoints.first?.modelBreakdowns.isEmpty == true)
    }

    @Test @MainActor
    func `Pre-v070 disk schema migrates model observations without losing ledger rows`() throws {
        let base = URL(fileURLWithPath: "/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070")
        guard FileManager.default.fileExists(atPath: base.path),
              FileManager.default.isWritableFile(atPath: base.path),
              base.resolvingSymlinksInPath().path.hasPrefix("/Volumes/StudioSSD/")
        else { throw CocoaError(.fileNoSuchFile) }
        let root = base.appendingPathComponent("legacy-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store.sqlite")
        let blob = try JSONEncoder().encode(["fixture-identity"])
        do {
            let schema = Schema([
                LegacyV230Ledger.DeviceRecord.self, LegacyV230Ledger.ProviderSnapshotModel.self,
                LegacyV230Ledger.UtilizationEntryModel.self, LegacyV230Ledger.SyncStateRecord.self,
                LegacyV230Ledger.DailyCostPoint.self,
            ])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                schema: schema, url: store, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let device = LegacyV230Ledger.DeviceRecord(
                deviceID: "fixture-a",
                deviceName: "Fixture Legacy Mac",
                appVersion: "2.3.0",
                lastSyncAt: self.captured)
            context.insert(device)
            context.insert(LegacyV230Ledger.ProviderSnapshotModel(
                deviceID: "fixture-a",
                providerID: "codex",
                providerName: "Fixture Provider",
                lastUpdated: self.captured,
                device: device))
            context.insert(LegacyV230Ledger.DailyCostPoint(
                deviceID: "fixture-a",
                providerID: "codex",
                accountEmail: "fixture@example.invalid",
                accountRecordKey: "fixture-record",
                accountIdentityKey: "fixture-identity",
                accountIdentitiesData: blob,
                dayKey: "2026-10-01",
                costUSD: 1.25,
                totalTokens: 20,
                tokenCountIsKnown: true,
                costIsKnown: true,
                isEstimated: false,
                lastUpdated: self.captured))
            try context.save()
        }
        let opened = ModelContainerFactory.openContainer(at: store)
        #expect(opened.isPersistent)
        let context = ModelContext(opened.container)
        let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
        let device = try #require(devices.first)
        #expect(devices.count == 1 && device.deviceName == "Fixture Legacy Mac")
        #expect(device.providerPublicationTimestampsData == nil)
        #expect(device.providers.count == 1 && device.providers.first?.providerID == "codex")
        let restored = try SwiftDataBridge.readAllDeviceSnapshots(from: context)
        #expect(restored.first?.providerPublicationTimestamps == [:])
        #expect(restored.first?.syncTimestamp == self.captured)
        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.compositeKey == "fixture-a|codex|fixture-record|2026-10-01")
        #expect(row.accountIdentityKey == "fixture-identity")
        #expect(row.accountIdentitiesData == blob)
        #expect(row.costUSD == 1.25 && row.totalTokens == 20)
        #expect(row.tokenCountIsKnown == true && row.costIsKnown == true && row.isEstimated == false)
        #expect(row.lastUpdated == self.captured)
        #expect(row.modelsUsedData == nil)
        row.modelsUsedData = try JSONEncoder().encode(["FictitiousModelA"])
        try context.save()
        let reopened = ModelContainerFactory.openContainer(at: store)
        #expect(reopened.isPersistent)
        let persisted = try #require(try ModelContext(reopened.container)
            .fetch(FetchDescriptor<DailyCostPoint>()).first)
        #expect(persisted.modelsUsedData == row.modelsUsedData)
        #expect(persisted.costUSD == 1.25 && persisted.totalTokens == 20)
    }

    @Test @MainActor
    func `Provider publication authority survives disk reopening with opposing device clocks`() throws {
        let base = URL(fileURLWithPath: "/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070")
        guard FileManager.default.fileExists(atPath: base.path),
              FileManager.default.isWritableFile(atPath: base.path),
              base.resolvingSymlinksInPath().path.hasPrefix("/Volumes/StudioSSD/")
        else { throw CocoaError(.fileNoSuchFile) }
        let root = base.appendingPathComponent("publication-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store.sqlite")
        func source(device: String, used: Double, publication: Double, sync: Double) -> SyncedUsageSnapshot {
            let provider = ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Fixture Provider",
                primary: nil,
                secondary: nil,
                accountEmail: "fixture@example.invalid",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.captured,
                utilizationHistory: [
                    .init(name: "session", windowMinutes: 300, entries: [
                        .init(capturedAt: self.captured, usedPercent: used, resetsAt: nil),
                    ]),
                ])
            return SyncedUsageSnapshot(
                providers: [provider],
                syncTimestamp: self.captured.addingTimeInterval(sync),
                deviceName: device,
                deviceID: device,
                providerPublicationTimestamps: [SyncedUsageSnapshot.providerPublicationKey(for: provider):
                    self.captured.addingTimeInterval(publication)])
        }
        let sources = [
            source(device: "fixture-a", used: 90, publication: 10, sync: 1000),
            source(device: "fixture-b", used: 20, publication: 20, sync: 900),
        ]
        let live = try #require(ProviderSnapshotMerger.mergeSnapshots(sources))
        #expect(live.providers.first?.utilizationHistory?.first?.entries.first?.usedPercent == 20)
        do {
            let opened = ModelContainerFactory.openContainer(at: store)
            #expect(opened.isPersistent)
            try SwiftDataBridge.upsert(deviceSnapshots: sources, into: ModelContext(opened.container))
        }
        let opened = ModelContainerFactory.openContainer(at: store)
        #expect(opened.isPersistent)
        let restored = try SwiftDataBridge.readAllDeviceSnapshots(from: ModelContext(opened.container))
        for source in sources {
            #expect(restored.first { $0.deviceID == source.deviceID }?.providerPublicationTimestamps
                == source.providerPublicationTimestamps)
        }
        for ordered in [restored, Array(restored.reversed())] {
            let cold = try #require(ProviderSnapshotMerger.mergeSnapshots(ordered))
            #expect(cold.providers.first?.utilizationHistory == live.providers.first?.utilizationHistory)
        }
    }
}

/// Frozen pre-v0.70 persisted schema: lacks both new optional fields.
private enum LegacyV230Ledger {
    @Model
    final class DeviceRecord {
        /// Stable UUID coming from `SyncedUsageSnapshot.deviceID`. For legacy
        /// single-device snapshots without a deviceID, bridge layer substitutes
        /// a deterministic fallback (see `SwiftDataBridge.deviceIDFallback`).
        @Attribute(.unique) var deviceID: String
        var deviceName: String
        var appVersion: String?
        var lastSyncAt: Date

        @Relationship(deleteRule: .cascade, inverse: \ProviderSnapshotModel.device)
        var providers: [ProviderSnapshotModel] = []

        init(
            deviceID: String,
            deviceName: String,
            appVersion: String? = nil,
            lastSyncAt: Date = .now)
        {
            self.deviceID = deviceID
            self.deviceName = deviceName
            self.appVersion = appVersion
            self.lastSyncAt = lastSyncAt
        }
    }

    // MARK: - Provider Snapshot

    @Model
    final class ProviderSnapshotModel {
        /// Unique key composed from `deviceID|providerID|accountEmail ?? ""`.
        /// SwiftData does not currently support composite `.unique`; using a
        /// computed-and-stored key keeps uniqueness enforceable at the store level.
        @Attribute(.unique) var compositeKey: String

        var deviceID: String
        var providerID: String
        var providerName: String
        var accountEmail: String?
        /// Opaque token/device identity used in CloudKit record names. Optional
        /// keeps existing SwiftData stores lightweight-migratable.
        var accountRecordKey: String?
        var loginMethod: String?
        var statusMessage: String?
        var isError: Bool
        var lastUpdated: Date
        var subscriptionExpiresAt: Date?
        var subscriptionRenewsAt: Date?

        /// JSON-encoded `ProviderUsageSnapshot` — canonical cold-start mirror.
        /// Older rows leave this nil and fall back to the decomposed columns below.
        var providerPayloadData: Data?

        /// JSON-encoded `[SyncRateWindow]` — opaque blob, decoded on read.
        var rateWindowsData: Data
        /// JSON-encoded `SyncCostSummary` — opaque blob, decoded on read.
        var costSummaryData: Data?
        /// JSON-encoded `SyncBudgetSnapshot` — opaque blob, decoded on read.
        var budgetData: Data?
        /// JSON-encoded `SyncPerplexityCreditSummary` — opaque blob, decoded on
        /// read. Only populated for `providerID == "perplexity"` when Mac is
        /// pushing structured credit data (Mac 0.20.3+); nil for every other
        /// provider and for legacy Mac payloads.
        var perplexityCreditsData: Data?

        @Relationship(deleteRule: .cascade, inverse: \UtilizationEntryModel.provider)
        var utilizationEntries: [UtilizationEntryModel] = []

        var device: DeviceRecord?

        init(
            deviceID: String,
            providerID: String,
            providerName: String,
            accountEmail: String? = nil,
            accountRecordKey: String? = nil,
            loginMethod: String? = nil,
            statusMessage: String? = nil,
            isError: Bool = false,
            lastUpdated: Date,
            subscriptionExpiresAt: Date? = nil,
            subscriptionRenewsAt: Date? = nil,
            providerPayloadData: Data? = nil,
            rateWindowsData: Data = Data("[]".utf8),
            costSummaryData: Data? = nil,
            budgetData: Data? = nil,
            perplexityCreditsData: Data? = nil,
            device: DeviceRecord? = nil)
        {
            self.compositeKey = Self.makeCompositeKey(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: accountEmail,
                accountRecordKey: accountRecordKey)
            self.deviceID = deviceID
            self.providerID = providerID
            self.providerName = providerName
            self.accountEmail = accountEmail
            self.accountRecordKey = accountRecordKey
            self.loginMethod = loginMethod
            self.statusMessage = statusMessage
            self.isError = isError
            self.lastUpdated = lastUpdated
            self.subscriptionExpiresAt = subscriptionExpiresAt
            self.subscriptionRenewsAt = subscriptionRenewsAt
            self.providerPayloadData = providerPayloadData
            self.rateWindowsData = rateWindowsData
            self.costSummaryData = costSummaryData
            self.budgetData = budgetData
            self.perplexityCreditsData = perplexityCreditsData
            self.device = device
        }

        /// Build the composite unique key. Used by the upsert bridge to look up
        /// existing rows and by the initializer. **Format must stay byte-identical
        /// to `CloudSyncManager.perProviderRecordName` and
        /// `SnapshotCache.compositeKey` — `"_"` for nil `accountEmail`.** Letting
        /// these drift means a delete-by-recordName from CloudKit silently misses
        /// the matching SwiftData row, and any cross-layer key comparison breaks.
        /// (Codex hardening review on Build 67 surfaced the empty-string-vs-`"_"`
        /// drift here.)
        static func makeCompositeKey(
            deviceID: String,
            providerID: String,
            accountEmail: String?,
            accountRecordKey: String? = nil) -> String
        {
            "\(deviceID)|\(providerID)|\(accountRecordKey ?? accountEmail ?? "_")"
        }
    }

    // MARK: - Utilization Entry

    @Model
    final class UtilizationEntryModel {
        /// e.g. "session" / "weekly" / "opus". Matches `SyncUtilizationSeries.name`.
        var seriesName: String
        var capturedAt: Date
        var usedPercent: Double
        var resetsAt: Date?
        /// Window length in minutes (from parent series). Stored redundantly so
        /// per-entry @Query filtering can group by window without a join.
        var windowMinutes: Int

        var provider: ProviderSnapshotModel?

        init(
            seriesName: String,
            capturedAt: Date,
            usedPercent: Double,
            resetsAt: Date? = nil,
            windowMinutes: Int = 0,
            provider: ProviderSnapshotModel? = nil)
        {
            self.seriesName = seriesName
            self.capturedAt = capturedAt
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
            self.windowMinutes = windowMinutes
            self.provider = provider
        }
    }

    // MARK: - Sync State (per CloudKit zone)

    @Model
    final class SyncStateRecord {
        /// CloudKit zone name (e.g. "DeviceSnapshotsZone", "DeviceProvidersZone").
        @Attribute(.unique) var zoneName: String
        /// Archived `CKServerChangeToken` blob. Nil on first sync.
        var changeTokenData: Data?
        var lastSyncAt: Date

        init(zoneName: String, changeTokenData: Data? = nil, lastSyncAt: Date = .distantPast) {
            self.zoneName = zoneName
            self.changeTokenData = changeTokenData
            self.lastSyncAt = lastSyncAt
        }
    }

    // MARK: - Schema registry

    @Model
    final class DailyCostPoint {
        /// Composite unique key `{deviceID}|{providerID}|{dayKey}`. The three
        /// source fields below are also stored directly for query-side filtering.
        /// **Format must stay byte-identical across writer / reader / tests** —
        /// drift here silently produces duplicate rows for the same logical day.
        @Attribute(.unique) var compositeKey: String

        var deviceID: String
        var providerID: String
        /// Account email (`nil` for single-account providers). Part of the
        /// composite key so multi-account providers (two Codex accounts on one
        /// Mac, etc.) keep separate per-day rows — matching the blob path's
        /// `ProviderSnapshotModel` per-(providerID, accountEmail) granularity.
        /// Without this, the two accounts collide on `(deviceID, providerID,
        /// dayKey)` and one silently overwrites the other.
        var accountEmail: String?
        /// Opaque record identity. It owns per-device row uniqueness when present,
        /// so editable account-label changes do not create a new history bucket.
        var accountRecordKey: String?
        /// Stable cross-Mac merge identity selected from the wire identity set.
        /// This differs from `accountRecordKey` when two Macs know the same real
        /// account by authenticated email/org but use different local token UUIDs.
        var accountIdentityKey: String?
        /// Encoded `[String]` identity set used for the same overlap/union
        /// semantics as `ProviderSnapshotMerger` across mixed Mac writers.
        var accountIdentitiesData: Data?
        /// `YYYY-MM-DD` UTC, matches `SyncDailyPoint.dayKey` on the wire.
        var dayKey: String

        var costUSD: Double
        var totalTokens: Int
        var tokenCountIsKnown: Bool?
        /// Three-state wire availability: true = authoritative cost (including
        /// zero), false = cost unavailable, nil = legacy writer with no metadata.
        var costIsKnown: Bool?
        /// Mirrors `SyncCostBreakdown.isEstimated` rolled up to the day. Preserved
        /// so the iOS estimated-badge (P5) still works under CWL.
        var isEstimated: Bool?

        /// Encoded `[SyncCostBreakdown]` — preserves `isEstimated`,
        /// `standardCostUSD` / `priorityCostUSD` / `standardTokens` /
        /// `priorityTokens` (gap A Codex standard/fast split). Decoded on read.
        var modelBreakdownsData: Data?
        /// Encoded `[SyncCostBreakdown]` for service-level breakdowns. Decoded on read.
        var serviceBreakdownsData: Data?

        /// When this day's data was last refreshed by the Mac that pushed it.
        /// Used by the writer's dedup:
        /// `if existing.lastUpdated >= new.lastUpdated → skip` (we already have
        /// fresher data for this `(deviceID, providerID, dayKey)`). Also used by
        /// the reader's multi-device merge — same `(providerID, dayKey)` across
        /// devices, latest `lastUpdated` wins.
        var lastUpdated: Date

        init(
            deviceID: String,
            providerID: String,
            accountEmail: String?,
            accountRecordKey: String? = nil,
            accountIdentityKey: String? = nil,
            accountIdentitiesData: Data? = nil,
            dayKey: String,
            costUSD: Double,
            totalTokens: Int,
            tokenCountIsKnown: Bool? = nil,
            costIsKnown: Bool? = nil,
            isEstimated: Bool? = nil,
            modelBreakdownsData: Data? = nil,
            serviceBreakdownsData: Data? = nil,
            lastUpdated: Date)
        {
            self.compositeKey = Self.makeCompositeKey(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: accountEmail,
                accountRecordKey: accountRecordKey,
                dayKey: dayKey)
            self.deviceID = deviceID
            self.providerID = providerID
            self.accountEmail = accountEmail
            self.accountRecordKey = accountRecordKey
            self.accountIdentityKey = accountIdentityKey
            self.accountIdentitiesData = accountIdentitiesData
            self.dayKey = dayKey
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.tokenCountIsKnown = tokenCountIsKnown
            self.costIsKnown = costIsKnown
            self.isEstimated = isEstimated
            self.modelBreakdownsData = modelBreakdownsData
            self.serviceBreakdownsData = serviceBreakdownsData
            self.lastUpdated = lastUpdated
        }

        /// Compose the composite unique key. Format pinned:
        /// `{deviceID}|{providerID}|{accountEmail ?? "_"}|{dayKey}`. The `"_"`
        /// for nil `accountEmail` matches `ProviderSnapshotModel.makeCompositeKey`
        /// byte-for-byte. Writer + reader + tests must all build it via this
        /// helper so any future format change propagates uniformly.
        static func makeCompositeKey(
            deviceID: String,
            providerID: String,
            accountEmail: String?,
            accountRecordKey: String? = nil,
            dayKey: String) -> String
        {
            "\(deviceID)|\(providerID)|\(accountRecordKey ?? accountEmail ?? "_")|\(dayKey)"
        }
    }
}
