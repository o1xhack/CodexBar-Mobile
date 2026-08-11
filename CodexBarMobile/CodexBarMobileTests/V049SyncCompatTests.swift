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
        let providerAmount: SyncProviderAmount?

        var hasUsableSignal: Bool {
            self.primary != nil || self.secondary != nil || self.providerAmount != nil
                || self.isError || self.statusMessage?.isEmpty == false
        }
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
        let providerIDs: [String]
        let cardIdentityKeys: [String]
        let codexUsedPercent: Double?
        let codexSourceDeviceID: String?
        let seesDetails: Bool
        let seesPluginBranding: Bool
        let seesFireworksSpend: Bool
        let seesIBMBobWindow: Bool
    }

    private struct LegacyCard {
        let provider: LegacyProvider
        let sourceDeviceID: String?
    }

    private struct MatrixWriter {
        let legacyPayload: Data
        let envelopePayloads: [Data]
    }

    private enum NewReaderPath {
        case fullFetch
        case delta
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
    func `generic detail decoder bounds sections rows points and strings`() throws {
        let boundaryString = String(repeating: "x", count: 120)
        let rows = (0..<26).map { index in
            let label = index == 0 ? boundaryString : "Row \(index)"
            return #"{"label":"\#(label)","value":"Value \#(index)"}"#
        }.joined(separator: ",")
        let points = (0..<122).map { index in
            let label = index == 0 ? boundaryString : "Point \(index)"
            return #"{"label":"\#(label)","value":\#(index)}"#
        }.joined(separator: ",")
        let sections = (0..<10).map { index in
            let title = index == 0 ? boundaryString : "Section \(index)"
            return """
            {"title":"\(title)","rows":[\(rows)],"chart":{"kind":"line","points":[\(points)]}}
            """
        }.joined(separator: ",")

        let provider = try Self.decodeDetailsProvider(sections)

        #expect(provider.details.count == SyncProviderDetailSection.maximumSectionsPerSnapshot)
        #expect(provider.details[0].rows.count == SyncProviderDetailSection.maximumRowsPerSection)
        #expect(provider.details[0].chart?.points.count == SyncProviderDetailSection.maximumPointsPerChart)
        #expect(provider.details[0].title == boundaryString)
        #expect(provider.details[0].rows[0].label == boundaryString)
        #expect(provider.details[0].chart?.points[0].label == boundaryString)
    }

    @Test
    func `generic detail decoder drops empty overlong and malformed siblings lossily`() throws {
        let overlong = String(repeating: "y", count: 121)
        let sections = """
        {"title":" Keep ","rows":[
          {"label":" Plan ","value":" Pro "},
          {"label":"   ","value":"bad"},
          {"label":"Too long","value":"\(overlong)"},
          {"label":"Balance","value":" 42 "}
        ],"chart":{"kind":"bars","points":[
          {"label":" First ","value":1},
          {"label":"   ","value":2},
          {"label":"\(overlong)","value":3},
          {"label":"Last","value":4}
        ]}},
        {"title":"\(overlong)","rows":[]},
        {"title":"   ","rows":[]},
        {"title":"Broken rows","rows":"not-an-array"},
        {"title":"Sibling","rows":[{"label":"Status","value":"OK"}]}
        """

        let provider = try Self.decodeDetailsProvider(sections)

        #expect(provider.providerName == "Detail Fixture")
        #expect(provider.details.count == 3)
        #expect(provider.details[0].title == "Keep")
        #expect(provider.details[0].rows.map(\.label) == ["Plan", "Balance"])
        #expect(provider.details[0].rows.map(\.value) == ["Pro", "42"])
        #expect(provider.details[0].chart?.points.map(\.label) == ["First", "Last"])
        #expect(provider.details[1].title == nil)
        #expect(provider.details[2].title == "Sibling")
    }

    @Test
    func `generic detail decoder drops nonfinite points without losing chart or payload`() throws {
        let sections = """
        {"title":"Chart","rows":[],"chart":{"kind":"line","points":[
          {"label":"One","value":1},
          {"label":"Positive","value":"Infinity"},
          {"label":"NaN","value":"NaN"},
          {"label":"Negative","value":"-Infinity"},
          {"label":"Two","value":2}
        ]}},
        {"title":"Sibling","rows":[{"label":"Status","value":"OK"}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN")

        let provider = try decoder.decode(
            ProviderUsageSnapshot.self,
            from: Self.detailsProviderPayload(sections))

        #expect(provider.details.count == 2)
        #expect(provider.details[0].chart?.points.map(\.value) == [1, 2])
        #expect(provider.details[1].rows.first?.value == "OK")
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
        #expect(retained.providerID == "matrix-plugin")
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

        let writers = try [
            Self.makeMatrixWriter(
                deviceID: "matrix-mac-a",
                isNew: macANew,
                timestamp: Self.timestamp),
            Self.makeMatrixWriter(
                deviceID: "matrix-mac-b",
                isNew: macBNew,
                timestamp: Self.timestamp.addingTimeInterval(60)),
        ]
        let phoneA = try Self.readPhone(isNew: iPhoneANew, writers: writers, path: .fullFetch)
        let phoneB = try Self.readPhone(isNew: iPhoneBNew, writers: writers, path: .delta)
        let hasNewWriter = macANew || macBNew
        var expectedIDs = ["codex"]
        if hasNewWriter {
            expectedIDs += ["fireworks", "ibmbob"]
            if iPhoneANew { expectedIDs.append("matrix-plugin") }
        }
        expectedIDs.sort()

        #expect(phoneA.providerIDs == expectedIDs)
        var phoneBExpectedIDs = ["codex"]
        if hasNewWriter {
            phoneBExpectedIDs += ["fireworks", "ibmbob"]
            if iPhoneBNew { phoneBExpectedIDs.append("matrix-plugin") }
        }
        phoneBExpectedIDs.sort()
        #expect(phoneB.providerIDs == phoneBExpectedIDs)
        let expectedCodexUsedPercent = macBNew ? 30.0 : 25.0
        #expect(phoneA.cardIdentityKeys == Self.expectedIdentityKeys(
            isNewReader: iPhoneANew,
            hasNewWriter: hasNewWriter))
        #expect(phoneB.cardIdentityKeys == Self.expectedIdentityKeys(
            isNewReader: iPhoneBNew,
            hasNewWriter: hasNewWriter))
        #expect(phoneA.codexUsedPercent == expectedCodexUsedPercent)
        #expect(phoneB.codexUsedPercent == expectedCodexUsedPercent)
        #expect(phoneA.codexSourceDeviceID == "matrix-mac-b")
        #expect(phoneB.codexSourceDeviceID == "matrix-mac-b")
        #expect(phoneA.seesDetails == (iPhoneANew && hasNewWriter))
        #expect(phoneB.seesDetails == (iPhoneBNew && hasNewWriter))
        #expect(phoneA.seesPluginBranding == (iPhoneANew && hasNewWriter))
        #expect(phoneB.seesPluginBranding == (iPhoneBNew && hasNewWriter))
        #expect(phoneA.seesFireworksSpend == hasNewWriter)
        #expect(phoneB.seesFireworksSpend == hasNewWriter)
        #expect(phoneA.seesIBMBobWindow == hasNewWriter)
        #expect(phoneB.seesIBMBobWindow == hasNewWriter)
        if iPhoneANew == iPhoneBNew {
            #expect(phoneA == phoneB)
        }
    }

    private static func makeMatrixWriter(
        deviceID: String,
        isNew: Bool,
        timestamp: Date) throws -> MatrixWriter
    {
        if isNew {
            let snapshot = self.makeMatrixNewSnapshot(deviceID: deviceID, timestamp: timestamp)
            let envelopes = try snapshot.providers.map { provider in
                try self.encoder.encode(ProviderUsageEnvelope(
                    deviceID: deviceID,
                    deviceName: deviceID,
                    appVersion: "0.49.2.1",
                    mobileVersion: "1.21.0",
                    syncTimestamp: timestamp,
                    notificationPushEnabled: true,
                    provider: provider))
            }
            return try MatrixWriter(
                legacyPayload: self.encoder.encode(snapshot),
                envelopePayloads: envelopes)
        }

        let legacy = LegacySnapshot(
            providers: [LegacyProvider(
                providerID: "codex",
                providerName: "Codex",
                primary: LegacyRateWindow(
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: timestamp.addingTimeInterval(3600),
                    resetDescription: nil),
                secondary: nil,
                accountEmail: "matrix@example.com",
                loginMethod: "OAuth",
                statusMessage: nil,
                isError: false,
                lastUpdated: timestamp,
                providerAmount: nil)],
            syncTimestamp: timestamp,
            deviceName: deviceID,
            deviceID: deviceID,
            appVersion: "0.47.0.1",
            mobileVersion: "1.20.0",
            notificationPushEnabled: true)
        return try MatrixWriter(
            legacyPayload: Self.encoder.encode(legacy),
            envelopePayloads: [])
    }

    private static func readPhone(
        isNew: Bool,
        writers: [MatrixWriter],
        path: NewReaderPath) throws -> PhoneResult
    {
        if !isNew {
            let snapshots = try writers.map {
                try Self.decoder.decode(LegacySnapshot.self, from: $0.legacyPayload)
            }
            var latestByIdentity: [String: LegacyCard] = [:]
            for snapshot in snapshots {
                for provider in snapshot.providers where provider.hasUsableSignal {
                    let key = "\(provider.providerID)|\(provider.accountEmail ?? "")"
                    if (latestByIdentity[key]?.provider.lastUpdated ?? Date.distantPast) < provider.lastUpdated {
                        latestByIdentity[key] = LegacyCard(
                            provider: provider,
                            sourceDeviceID: snapshot.deviceID)
                    }
                }
            }
            let cards = latestByIdentity.values.sorted { $0.provider.providerID < $1.provider.providerID }
            let providers = cards.map(\.provider)
            let codex = cards.first { $0.provider.providerID == "codex" }
            return PhoneResult(
                providerIDs: providers.map(\.providerID),
                cardIdentityKeys: latestByIdentity.keys.sorted(),
                codexUsedPercent: codex?.provider.primary?.usedPercent,
                codexSourceDeviceID: codex?.sourceDeviceID,
                seesDetails: false,
                seesPluginBranding: false,
                seesFireworksSpend: providers.contains {
                    $0.providerID == "fireworks" && $0.providerAmount?.kind == "spend"
                },
                seesIBMBobWindow: providers.contains {
                    $0.providerID == "ibmbob" && $0.primary != nil
                })
        }

        let legacySnapshots = try writers.map {
            try Self.decoder.decode(SyncedUsageSnapshot.self, from: $0.legacyPayload)
        }
        let envelopes = try writers.flatMap(\.envelopePayloads).map {
            try Self.decoder.decode(ProviderUsageEnvelope.self, from: $0)
        }
        var cache = SnapshotCache()
        switch path {
        case .fullFetch:
            let perProviderSnapshots = legacySnapshots.filter { $0.appVersion == "0.49.2.1" }
            cache.replaceFromFullFetch(
                perProviderSnapshots: perProviderSnapshots,
                legacySnapshots: legacySnapshots)
        case .delta:
            cache.replaceFromFullFetch(perProviderSnapshots: [], legacySnapshots: legacySnapshots)
            cache.applyDelta(upserted: Array(envelopes.reversed()), deletedRecordNames: [])
        }
        let deviceSnapshots = cache.buildDeviceSnapshots()
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots(deviceSnapshots))
        let plugin = merged.providers.first { $0.providerID == "matrix-plugin" }
        let codex = merged.providers.first { $0.providerID == "codex" }
        let codexSourceDeviceID = deviceSnapshots
            .filter { snapshot in snapshot.providers.contains { $0.providerID == "codex" } }
            .max { lhs, rhs in
                let lhsUpdated = lhs.providers.first { $0.providerID == "codex" }?.lastUpdated ?? .distantPast
                let rhsUpdated = rhs.providers.first { $0.providerID == "codex" }?.lastUpdated ?? .distantPast
                return lhsUpdated < rhsUpdated
            }?.deviceID
        let identities = merged.providers.map(\.cardIdentityKey).sorted()
        return PhoneResult(
            providerIDs: merged.providers.map(\.providerID).sorted(),
            cardIdentityKeys: identities,
            codexUsedPercent: codex?.primary?.usedPercent,
            codexSourceDeviceID: codexSourceDeviceID,
            seesDetails: plugin?.details.isEmpty == false,
            seesPluginBranding: plugin?.providerIconMonogram != nil
                && plugin?.providerIconTintHex != nil,
            seesFireworksSpend: merged.providers.contains {
                $0.providerID == "fireworks" && $0.providerAmount?.kind == "spend"
            },
            seesIBMBobWindow: merged.providers.contains {
                $0.providerID == "ibmbob" && $0.primary != nil
            })
    }

    private static func expectedIdentityKeys(
        isNewReader: Bool,
        hasNewWriter: Bool) -> [String]
    {
        var keys = ["codex|matrix@example.com"]
        if hasNewWriter {
            keys += ["fireworks|", "ibmbob|bob@matrix.example"]
            if isNewReader { keys.append("matrix-plugin|matrix@example.com") }
        }
        return keys.sorted()
    }

    private static func makeMatrixNewSnapshot(
        deviceID: String,
        timestamp: Date) -> SyncedUsageSnapshot
    {
        let codex = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(
                label: "5-hour",
                usedPercent: 30,
                windowMinutes: 300,
                resetsAt: timestamp.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            accountEmail: "matrix@example.com",
            loginMethod: "OAuth",
            statusMessage: nil,
            isError: false,
            lastUpdated: timestamp,
            accountIdentities: ["codex:email:matrix@example.com"])
        let fireworks = ProviderUsageSnapshot(
            providerID: "fireworks",
            providerName: "Fireworks AI",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API key",
            statusMessage: nil,
            isError: false,
            lastUpdated: timestamp,
            providerAmount: SyncProviderAmount(
                kind: "spend",
                amount: 42,
                currencyCode: "USD",
                period: "Current month",
                isEstimated: false))
        let ibmBob = ProviderUsageSnapshot(
            providerID: "ibmbob",
            providerName: "IBM Bob",
            primary: SyncRateWindow(
                id: "monthly-bobcoins",
                label: "Monthly Bobcoins",
                usedPercent: 40,
                windowMinutes: 43200,
                resetsAt: timestamp.addingTimeInterval(10 * 86400),
                resetDescription: nil),
            secondary: nil,
            accountEmail: "bob@matrix.example",
            loginMethod: "API key",
            statusMessage: nil,
            isError: false,
            lastUpdated: timestamp,
            details: [SyncProviderDetailSection(
                title: "Bobcoin usage",
                rows: [.init(label: "Plan", value: "Team")])])
        let ghost = ProviderUsageSnapshot(
            providerID: "ghost-provider",
            providerName: "Ghost Provider",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: timestamp)
        return SyncedUsageSnapshot(
            providers: [codex, fireworks, ibmBob, self.makeNewProvider(timestamp: timestamp), ghost],
            syncTimestamp: timestamp,
            deviceName: deviceID,
            deviceID: deviceID,
            appVersion: "0.49.2.1",
            mobileVersion: "1.21.0",
            notificationPushEnabled: true)
    }

    private static func decodeDetailsProvider(_ sections: String) throws -> ProviderUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(
            ProviderUsageSnapshot.self,
            from: self.detailsProviderPayload(sections))
    }

    private static func detailsProviderPayload(_ sections: String) -> Data {
        Data(
            """
            {
              "providerID":"detail-fixture",
              "providerName":"Detail Fixture",
              "isError":false,
              "lastUpdated":0,
              "details":[\(sections)]
            }
            """.utf8)
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
                providerID: "matrix-plugin",
                providerName: "Matrix Plugin",
                primary: nil,
                secondary: nil,
                accountEmail: "matrix@example.com",
                loginMethod: "plugin",
                statusMessage: nil,
                isError: false,
                lastUpdated: timestamp,
                accountIdentities: ["matrix-plugin:email:matrix@example.com"],
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
            providerID: "matrix-plugin",
            providerName: providerName,
            primary: nil,
            secondary: nil,
            accountEmail: "matrix@example.com",
            loginMethod: "plugin",
            statusMessage: nil,
            isError: false,
            lastUpdated: timestamp,
            accountIdentities: ["matrix-plugin:email:matrix@example.com"],
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
