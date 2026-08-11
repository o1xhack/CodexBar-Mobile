import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@MainActor
@Suite("iOS 1.21 v0.49 generic detail compatibility")
struct V049SyncCompatTests {
    private struct LegacyRateWindow: Codable {
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: Date?
        let resetDescription: String?
    }

    private struct LegacyProvider: Codable {
        let providerID: String
        let providerName: String
        let primary: LegacyRateWindow?
        let secondary: LegacyRateWindow?
        let accountEmail: String?
        let loginMethod: String?
        let statusMessage: String?
        let isError: Bool
        let lastUpdated: Date
    }

    private struct LegacySnapshot: Codable {
        let providers: [LegacyProvider]
        let syncTimestamp: Date
        let deviceName: String
        let deviceID: String?
        let appVersion: String?
        let mobileVersion: String?
        let notificationPushEnabled: Bool?
    }

    private struct PhoneResult: Equatable {
        let providerIDs: Set<String>
        let seesDetails: Bool
        let seesPluginBranding: Bool
    }

    private static let encoder = CloudSyncConstants.makeJSONEncoder()
    private static let decoder = CloudSyncConstants.makeJSONDecoder()
    private static let timestamp = Date(timeIntervalSince1970: 1_786_427_200)

    @Test
    func `pre-v049 rate window and provider payloads use compatibility defaults`() throws {
        let json = """
        {
          "providerID":"legacy-provider",
          "providerName":"Legacy Provider",
          "primary":{
            "usedPercent":42,
            "windowMinutes":300,
            "resetsAt":null,
            "resetDescription":null
          },
          "secondary":null,
          "accountEmail":null,
          "loginMethod":null,
          "statusMessage":null,
          "isError":false,
          "lastUpdated":"2026-08-11T12:00:00Z"
        }
        """

        let provider = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        let window = try #require(provider.primary)
        #expect(window.id == nil)
        #expect(window.usageKnown)
        #expect(window.nextRegenPercent == nil)
        #expect(!window.isSyntheticPlaceholder)
        #expect(provider.details.isEmpty)
        #expect(provider.providerIconMonogram == nil)
        #expect(provider.providerIconTintHex == nil)
    }

    @Test
    func `synthetic Mac layout windows stay out of iPhone quota cards`() {
        let real = SyncRateWindow(
            id: "weekly",
            label: "Weekly",
            usedPercent: 55,
            usageKnown: false,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        let placeholder = SyncRateWindow(
            id: "session-placeholder",
            label: "Session",
            usedPercent: 0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil,
            isSyntheticPlaceholder: true)
        let provider = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: placeholder,
            secondary: real,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.timestamp,
            rateWindows: [placeholder, real])

        #expect(provider.allRateWindows == [real])
        #expect(provider.allRateWindows.first?.usageKnown == false)
    }

    @Test
    func `details-only plugin survives the incremental ghost filter`() throws {
        let provider = Self.makeNewProvider(timestamp: Self.timestamp)
        #expect(provider.primary == nil)
        #expect(provider.rateWindows.isEmpty)
        #expect(provider.hasUsableSignal)

        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [ProviderUsageEnvelope(
                deviceID: "matrix-mac-a",
                deviceName: "Matrix Mac A",
                appVersion: "0.49.2.1",
                mobileVersion: "1.21.0",
                syncTimestamp: Self.timestamp,
                notificationPushEnabled: true,
                provider: provider)],
            deletedRecordNames: [])

        let cached = try #require(cache.buildDeviceSnapshots().first)
        let retained = try #require(cached.providers.first)
        #expect(retained.providerID == "user:matrix-plugin")
        #expect(retained.details == provider.details)
    }

    @Test
    func `same-timestamp plugin merge is deterministic by device ID`() throws {
        let macA = Self.makeNewSnapshot(
            deviceID: "matrix-mac-a",
            timestamp: Self.timestamp,
            providerName: "Matrix Plugin A",
            monogram: "A",
            tint: "#AA0000")
        let macB = Self.makeNewSnapshot(
            deviceID: "matrix-mac-b",
            timestamp: Self.timestamp,
            providerName: "Matrix Plugin B",
            monogram: "B",
            tint: "#0000BB")

        let forward = try #require(ProviderSnapshotMerger.mergeSnapshots([macA, macB]))
        let reverse = try #require(ProviderSnapshotMerger.mergeSnapshots([macB, macA]))
        #expect(forward.providers == reverse.providers)
        #expect(forward.providers.first?.providerName == "Matrix Plugin B")
        #expect(forward.providers.first?.providerIconMonogram == "B")
        #expect(forward.providers.first?.providerIconTintHex == "#0000BB")
        #expect(forward.providers.first?.details.first?.rows.first?.value == "Matrix Plugin B")
    }

    @Test
    func `old empty details do not clear a new writer`() throws {
        let newWriter = Self.makeNewSnapshot(
            deviceID: "matrix-mac-new",
            timestamp: Self.timestamp,
            providerName: "Matrix Plugin",
            monogram: "MP",
            tint: "#3366CC")
        let oldWriter = Self.makeSnapshot(
            deviceID: "matrix-mac-old",
            appVersion: "0.47.0.1",
            timestamp: Self.timestamp.addingTimeInterval(60),
            details: [])

        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([newWriter, oldWriter]))
        #expect(merged.providers.first?.details == newWriter.providers.first?.details)
    }

    @Test
    func `new empty details authoritatively clear an older new writer`() throws {
        let populatedWriter = Self.makeNewSnapshot(
            deviceID: "matrix-mac-populated",
            timestamp: Self.timestamp,
            providerName: "Matrix Plugin",
            monogram: "MP",
            tint: "#3366CC")
        let clearingWriter = Self.makeSnapshot(
            deviceID: "matrix-mac-clearing",
            appVersion: "0.49.2.1",
            timestamp: Self.timestamp.addingTimeInterval(60),
            details: [])

        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([populatedWriter, clearingWriter]))
        #expect(merged.providers.first?.details.isEmpty == true)
    }

    /// Exhaustive binary ordering from docs/ios-sync-compatibility-testing.md:
    /// bit 3 = Mac A, bit 2 = Mac B, bit 1 = iPhone A, bit 0 = iPhone B.
    /// `false` models the already-released v0.47/1.20 wire reader/writer;
    /// `true` models this v0.49/1.21 candidate.
    @Test(arguments: Array(0..<16))
    func `2 Mac x 2 iPhone old-new generic-details matrix`(mask: Int) throws {
        let macANew = mask & 0b1000 != 0
        let macBNew = mask & 0b0100 != 0
        let iPhoneANew = mask & 0b0010 != 0
        let iPhoneBNew = mask & 0b0001 != 0

        let payloads = try [
            Self.makeWriterPayload(
                deviceID: "matrix-mac-a",
                isNew: macANew,
                timestamp: Self.timestamp),
            Self.makeWriterPayload(
                deviceID: "matrix-mac-b",
                isNew: macBNew,
                timestamp: Self.timestamp.addingTimeInterval(60)),
        ]
        let phoneA = try Self.readPhone(isNew: iPhoneANew, payloads: payloads)
        let phoneB = try Self.readPhone(isNew: iPhoneBNew, payloads: payloads)
        let expectedIDs: Set = ["user:matrix-plugin"]
        let hasNewWriter = macANew || macBNew

        #expect(phoneA.providerIDs == expectedIDs)
        #expect(phoneB.providerIDs == expectedIDs)
        #expect(phoneA.seesDetails == (iPhoneANew && hasNewWriter))
        #expect(phoneB.seesDetails == (iPhoneBNew && hasNewWriter))
        #expect(phoneA.seesPluginBranding == (iPhoneANew && hasNewWriter))
        #expect(phoneB.seesPluginBranding == (iPhoneBNew && hasNewWriter))
        if iPhoneANew == iPhoneBNew {
            #expect(phoneA == phoneB)
        }
    }

    private static func makeWriterPayload(
        deviceID: String,
        isNew: Bool,
        timestamp: Date) throws -> Data
    {
        if isNew {
            return try self.encoder.encode(self.makeNewSnapshot(
                deviceID: deviceID,
                timestamp: timestamp,
                providerName: "Matrix Plugin",
                monogram: "MP",
                tint: "#3366CC"))
        }

        let legacy = LegacySnapshot(
            providers: [LegacyProvider(
                providerID: "user:matrix-plugin",
                providerName: "Matrix Plugin",
                primary: LegacyRateWindow(
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: timestamp.addingTimeInterval(3600),
                    resetDescription: nil),
                secondary: nil,
                accountEmail: "matrix@example.com",
                loginMethod: "plugin",
                statusMessage: nil,
                isError: false,
                lastUpdated: timestamp)],
            syncTimestamp: timestamp,
            deviceName: deviceID,
            deviceID: deviceID,
            appVersion: "0.47.0.1",
            mobileVersion: "1.20.0",
            notificationPushEnabled: true)
        return try Self.encoder.encode(legacy)
    }

    private static func readPhone(isNew: Bool, payloads: [Data]) throws -> PhoneResult {
        if !isNew {
            let snapshots = try payloads.map {
                try Self.decoder.decode(LegacySnapshot.self, from: $0)
            }
            let providers = snapshots.flatMap(\.providers)
            return PhoneResult(
                providerIDs: Set(providers.map(\.providerID)),
                seesDetails: false,
                seesPluginBranding: false)
        }

        let snapshots = try payloads.map {
            try Self.decoder.decode(SyncedUsageSnapshot.self, from: $0)
        }
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots(snapshots))
        let provider = try #require(merged.providers.first)
        return PhoneResult(
            providerIDs: Set(merged.providers.map(\.providerID)),
            seesDetails: !provider.details.isEmpty,
            seesPluginBranding: provider.providerIconMonogram != nil
                && provider.providerIconTintHex != nil)
    }

    private static func makeNewSnapshot(
        deviceID: String,
        timestamp: Date,
        providerName: String,
        monogram: String,
        tint: String) -> SyncedUsageSnapshot
    {
        SyncedUsageSnapshot(
            providers: [self.makeNewProvider(
                timestamp: timestamp,
                providerName: providerName,
                monogram: monogram,
                tint: tint)],
            syncTimestamp: timestamp,
            deviceName: deviceID,
            deviceID: deviceID,
            appVersion: "0.49.2.1",
            mobileVersion: "1.21.0",
            notificationPushEnabled: true)
    }

    private static func makeSnapshot(
        deviceID: String,
        appVersion: String,
        timestamp: Date,
        details: [SyncProviderDetailSection]) -> SyncedUsageSnapshot
    {
        SyncedUsageSnapshot(
            providers: [ProviderUsageSnapshot(
                providerID: "user:matrix-plugin",
                providerName: "Matrix Plugin",
                primary: nil,
                secondary: nil,
                accountEmail: "matrix@example.com",
                loginMethod: "plugin",
                statusMessage: nil,
                isError: false,
                lastUpdated: timestamp,
                accountIdentities: ["user:matrix-plugin:email:matrix%40example.com"],
                details: details,
                providerIconMonogram: "MP",
                providerIconTintHex: "#3366CC")],
            syncTimestamp: timestamp,
            deviceName: deviceID,
            deviceID: deviceID,
            appVersion: appVersion,
            mobileVersion: appVersion == "0.47.0.1" ? "1.20.0" : "1.21.0",
            notificationPushEnabled: true)
    }

    private static func makeNewProvider(
        timestamp: Date,
        providerName: String = "Matrix Plugin",
        monogram: String = "MP",
        tint: String = "#3366CC") -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: "user:matrix-plugin",
            providerName: providerName,
            primary: nil,
            secondary: nil,
            accountEmail: "matrix@example.com",
            loginMethod: "plugin",
            statusMessage: nil,
            isError: false,
            lastUpdated: timestamp,
            accountIdentities: ["user:matrix-plugin:email:matrix%40example.com"],
            details: [SyncProviderDetailSection(
                title: "Plugin details",
                rows: [.init(label: "Plan", value: providerName)],
                chart: .init(
                    kind: .bars,
                    title: "Daily usage",
                    unit: "requests",
                    points: [.init(label: "Today", value: 42)]))],
            providerIconMonogram: monogram,
            providerIconTintHex: tint)
    }
}
