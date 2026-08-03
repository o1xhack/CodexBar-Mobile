import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("iOS 1.20 v0.47 sync compatibility")
struct V047SyncCompatTests {
    private struct LegacyRateWindow: Decodable {
        let usedPercent: Double
    }

    /// Minimal model of the fields understood by iOS 1.19.1. Decoding the
    /// candidate payload through this type proves that all v0.47 additions
    /// remain ignorable JSON keys for the published reader.
    private struct LegacyProvider: Decodable {
        let providerID: String
        let providerName: String
        let primary: LegacyRateWindow?
        let accountEmail: String?
        let isError: Bool
        let lastUpdated: Date
    }

    private struct LegacySnapshot: Decodable {
        let providers: [LegacyProvider]
        let syncTimestamp: Date
        let deviceName: String
        let deviceID: String?
    }

    private static let encoder = CloudSyncConstants.makeJSONEncoder()
    private static let decoder = CloudSyncConstants.makeJSONDecoder()

    @Test
    func `old z.ai payload decodes daily series as empty`() throws {
        let json = """
        {"xTime":["2026-08-03T09:00:00Z"],"modelSeries":[{"modelName":"glm","tokens":[42]}]}
        """
        let decoded = try Self.decoder.decode(SyncZaiHourlyUsage.self, from: Data(json.utf8))
        #expect(decoded.xTime.count == 1)
        #expect(decoded.dailyXTime.isEmpty)
        #expect(decoded.dailyModelSeries.isEmpty)
    }

    @Test
    func `new ZoomMate and workspace fields round trip`() throws {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let source = ProviderUsageSnapshot(
            providerID: "zoommate",
            providerName: "ZoomMate",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            accountOrganization: "Example Workspace",
            zoomMateCredits: SyncZoomMateCredits(
                budgetCap: 1000,
                usedCredits: 250,
                remainingCredits: 750,
                daily: [.init(dayKey: "2026-08-03", creditsUsed: 12.5)],
                updatedAt: now))
        let decoded = try Self.decoder.decode(
            ProviderUsageSnapshot.self,
            from: Self.encoder.encode(source))
        #expect(decoded == source)
        #expect(decoded.hasUsableSignal)
    }

    @Test
    func `pre-1.20 provider payload decodes additive fields as nil`() throws {
        let json = """
        {
          "providerID":"notion",
          "providerName":"Notion AI",
          "rateWindows":[],
          "isError":false,
          "lastUpdated":"2026-08-03T12:00:00Z"
        }
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.accountOrganization == nil)
        #expect(decoded.zoomMateCredits == nil)
    }

    @Test
    func `mixed-version merge keeps newest non-nil v0.47 fields`() throws {
        let oldDate = Date(timeIntervalSince1970: 1_786_320_000)
        let newDate = oldDate.addingTimeInterval(60)
        let oldWriter = ProviderUsageSnapshot(
            providerID: "notion",
            providerName: "Notion AI",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: oldDate)
        let newWriter = ProviderUsageSnapshot(
            providerID: "notion",
            providerName: "Notion AI",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: newDate,
            accountOrganization: "Design Workspace")
        let oldMac = SyncedUsageSnapshot(
            providers: [oldWriter],
            syncTimestamp: oldDate,
            deviceName: "Old Mac")
        let newMac = SyncedUsageSnapshot(
            providers: [newWriter],
            syncTimestamp: newDate,
            deviceName: "New Mac")

        let merged = try #require(CloudSyncReader.mergeSnapshots([oldMac, newMac]))
        #expect(merged.providers.first?.accountOrganization == "Design Workspace")
    }

    /// Exhaustive binary ordering from docs/ios-sync-compatibility-testing.md:
    /// bit 3 = Mac A, bit 2 = Mac B, bit 1 = iPhone A, bit 0 = iPhone B.
    /// Case 1 is all-old (mask 0); case 16 is all-new (mask 15).
    @MainActor
    @Test(arguments: Array(0..<16))
    func `2 Mac x 2 iPhone old/new matrix`(mask: Int) throws {
        let macANew = mask & 0b1000 != 0
        let macBNew = mask & 0b0100 != 0
        let iPhoneANew = mask & 0b0010 != 0
        let iPhoneBNew = mask & 0b0001 != 0
        let baseDate = Date(timeIntervalSince1970: 1_786_320_000)

        let sourceSnapshots = [
            Self.makeMatrixSnapshot(
                deviceID: "matrix-mac-a",
                deviceName: "Matrix Mac A",
                isNew: macANew,
                timestamp: baseDate),
            Self.makeMatrixSnapshot(
                deviceID: "matrix-mac-b",
                deviceName: "Matrix Mac B",
                isNew: macBNew,
                timestamp: baseDate.addingTimeInterval(60)),
        ]
        let writers = try zip(sourceSnapshots, [macANew, macBNew]).map {
            try Self.makeWireWriter(snapshot: $0.0, isNew: $0.1)
        }

        let phoneA = try Self.readMatrixPhone(isNew: iPhoneANew, writers: writers)
        let phoneB = try Self.readMatrixPhone(isNew: iPhoneBNew, writers: writers)

        #expect(phoneA.deviceIDs == ["matrix-mac-a", "matrix-mac-b"])
        #expect(phoneB.deviceIDs == ["matrix-mac-a", "matrix-mac-b"])
        #expect(phoneA.providerIDs.contains("codex"))
        #expect(phoneB.providerIDs.contains("codex"))
        #expect(!phoneA.providerIDs.contains("retired-provider"))
        #expect(!phoneB.providerIDs.contains("retired-provider"))
        #expect(!phoneA.providerIDs.contains("ghost-provider"))
        #expect(!phoneB.providerIDs.contains("ghost-provider"))
        #expect(phoneA.cardIdentityKeys.count == phoneA.providerIDs.count)
        #expect(phoneB.cardIdentityKeys.count == phoneB.providerIDs.count)

        let hasNewWriter = macANew || macBNew
        let newProviderIDs: Set = ["notion", "qwencloud", "xai", "zoommate", "zai"]
        #expect(newProviderIDs.isSubset(of: phoneA.providerIDs) == hasNewWriter)
        #expect(newProviderIDs.isSubset(of: phoneB.providerIDs) == hasNewWriter)

        // Independent phones running the same reader version must converge.
        // Mixed readers intentionally differ only in typed v0.47 details; the
        // published reader still sees every generic provider lane.
        if iPhoneANew == iPhoneBNew {
            #expect(phoneA == phoneB)
        }
        if hasNewWriter, iPhoneANew {
            #expect(phoneA.hasV047TypedFields)
        }
        if hasNewWriter, iPhoneBNew {
            #expect(phoneB.hasV047TypedFields)
        }
    }

    private struct MatrixPhoneResult: Equatable {
        let deviceIDs: [String]
        let providerIDs: Set<String>
        let cardIdentityKeys: Set<String>
        let hasV047TypedFields: Bool
    }

    private struct MatrixWireEnvelope {
        let recordName: String
        let payload: Data
    }

    private struct MatrixWireWriter {
        let legacyPayload: Data
        let perProviderPayloads: [MatrixWireEnvelope]
        let deletedRecordNames: [String]
    }

    @MainActor
    private static func readMatrixPhone(
        isNew: Bool,
        writers: [MatrixWireWriter]) throws -> MatrixPhoneResult
    {
        if !isNew {
            let snapshots = try writers.map {
                try Self.decoder.decode(LegacySnapshot.self, from: $0.legacyPayload)
            }
            let providers = snapshots.flatMap(\.providers)
            #expect(providers.allSatisfy { $0.primary != nil && !$0.isError })
            #expect(providers.allSatisfy { !$0.providerName.isEmpty && $0.lastUpdated > .distantPast })
            #expect(snapshots.allSatisfy { !$0.deviceName.isEmpty && $0.syncTimestamp > .distantPast })
            let identities = Set(providers.map {
                "\($0.providerID)|\($0.accountEmail ?? "")"
            })
            return MatrixPhoneResult(
                deviceIDs: snapshots.compactMap(\.deviceID).sorted(),
                providerIDs: Set(providers.map(\.providerID)),
                cardIdentityKeys: identities,
                hasV047TypedFields: false)
        }

        let legacySnapshots = try writers.map {
            try Self.decoder.decode(SyncedUsageSnapshot.self, from: $0.legacyPayload)
        }
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(perProviderSnapshots: [], legacySnapshots: legacySnapshots)

        // Each new iPhone independently replays the production per-provider
        // codec and change-token delta path. Ghost upserts are ignored and a
        // deleted provider must not leak back through the legacy fallback.
        for writer in writers {
            let envelopes = try writer.perProviderPayloads.map { wire in
                let json = try PayloadCompression.decompress(wire.payload)
                let envelope = try Self.decoder.decode(ProviderUsageEnvelope.self, from: json)
                let parsed = try #require(SnapshotCache.splitRecordName(wire.recordName))
                #expect(parsed.deviceID == envelope.deviceID)
                #expect(parsed.composite == SnapshotCache.compositeKey(for: envelope.provider))
                return envelope
            }
            cache.applyDelta(
                upserted: envelopes,
                deletedRecordNames: writer.deletedRecordNames)
        }

        let cached = cache.buildDeviceSnapshots()
        let merged = try #require(CloudSyncReader.mergeSnapshots(cached))
        let identities = merged.providers.map(\.cardIdentityKey)
        #expect(Set(identities).count == identities.count)
        #expect(merged.providers.allSatisfy(Self.hasRenderableValues))
        let typed = merged.providers.contains(where: {
            $0.accountOrganization != nil || $0.zoomMateCredits != nil
                || $0.zaiHourlyUsage?.dailyModelSeries.isEmpty == false
        })
        return MatrixPhoneResult(
            deviceIDs: cached.compactMap(\.deviceID).sorted(),
            providerIDs: Set(merged.providers.map(\.providerID)),
            cardIdentityKeys: Set(identities),
            hasV047TypedFields: typed)
    }

    private static func makeWireWriter(
        snapshot: SyncedUsageSnapshot,
        isNew: Bool) throws -> MatrixWireWriter
    {
        guard isNew, let deviceID = snapshot.deviceID else {
            return try MatrixWireWriter(
                legacyPayload: self.encoder.encode(snapshot),
                perProviderPayloads: [],
                deletedRecordNames: [])
        }

        let retired = ProviderUsageSnapshot(
            providerID: "retired-provider",
            providerName: "Retired Provider",
            primary: SyncRateWindow(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: snapshot.syncTimestamp,
                resetDescription: nil),
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: snapshot.syncTimestamp.addingTimeInterval(-3600))
        let ghost = ProviderUsageSnapshot(
            providerID: "ghost-provider",
            providerName: "Ghost Provider",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: snapshot.syncTimestamp)
        let wireProviders = snapshot.providers + [retired, ghost]
        let payloads = try wireProviders.map { provider in
            let envelope = ProviderUsageEnvelope(
                deviceID: deviceID,
                deviceName: snapshot.deviceName,
                appVersion: snapshot.appVersion,
                mobileVersion: snapshot.mobileVersion,
                syncTimestamp: snapshot.syncTimestamp,
                notificationPushEnabled: snapshot.notificationPushEnabled,
                provider: provider)
            let recordName = CloudSyncManager.perProviderRecordName(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey)
            return try MatrixWireEnvelope(
                recordName: recordName,
                payload: PayloadCompression.compress(Self.encoder.encode(envelope)))
        }
        let retiredRecordName = CloudSyncManager.perProviderRecordName(
            deviceID: deviceID,
            providerID: retired.providerID,
            accountEmail: retired.accountEmail,
            accountRecordKey: retired.accountRecordKey)
        #expect(Set(payloads.map(\.recordName)).count == payloads.count)
        return try MatrixWireWriter(
            legacyPayload: Self.encoder.encode(snapshot),
            perProviderPayloads: payloads,
            deletedRecordNames: [retiredRecordName])
    }

    private static func hasRenderableValues(_ provider: ProviderUsageSnapshot) -> Bool {
        let windows = [provider.primary, provider.secondary].compactMap(\.self)
        guard windows.allSatisfy({
            $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
        }) else { return false }
        guard !provider.providerID.isEmpty,
              !provider.providerName.isEmpty,
              !provider.cardIdentityKey.isEmpty
        else { return false }
        if let credits = provider.zoomMateCredits {
            let values = [
                credits.budgetCap,
                credits.usedCredits,
                credits.remainingCredits,
                credits.overageCredits,
                credits.todayCreditsUsed,
            ].compactMap(\.self)
            guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
            if let cap = credits.budgetCap,
               let used = credits.usedCredits,
               let remaining = credits.remainingCredits,
               abs((used + remaining) - cap) > 0.0001
            {
                return false
            }
        }
        return true
    }

    private static func makeMatrixSnapshot(
        deviceID: String,
        deviceName: String,
        isNew: Bool,
        timestamp: Date) -> SyncedUsageSnapshot
    {
        let genericWindow = SyncRateWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: timestamp.addingTimeInterval(3600),
            resetDescription: nil)
        var providers = [ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: genericWindow,
            secondary: nil,
            accountEmail: "matrix@example.com",
            loginMethod: "test",
            statusMessage: nil,
            isError: false,
            lastUpdated: timestamp,
            accountIdentities: ["codex:email:matrix%40example.com"])]

        if isNew {
            let additions = ["qwencloud", "zoommate", "xai", "notion"].map { providerID in
                ProviderUsageSnapshot(
                    providerID: providerID,
                    providerName: providerID == "notion" ? "Notion AI" : providerID.capitalized,
                    primary: genericWindow,
                    secondary: nil,
                    accountEmail: "matrix@example.com",
                    loginMethod: "test",
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: timestamp,
                    accountIdentities: ["\(providerID):email:matrix%40example.com"],
                    accountOrganization: providerID == "notion" ? "Matrix Workspace" : nil,
                    zoomMateCredits: providerID == "zoommate"
                        ? SyncZoomMateCredits(
                            budgetCap: 1000,
                            usedCredits: 250,
                            remainingCredits: 750,
                            daily: [.init(dayKey: "2026-08-03", creditsUsed: 12.5)],
                            updatedAt: timestamp)
                        : nil)
            }
            providers.append(contentsOf: additions)
            providers.append(ProviderUsageSnapshot(
                providerID: "zai",
                providerName: "z.ai",
                primary: genericWindow,
                secondary: nil,
                accountEmail: "matrix@example.com",
                loginMethod: "test",
                statusMessage: nil,
                isError: false,
                lastUpdated: timestamp,
                accountIdentities: ["zai:email:matrix%40example.com"],
                zaiHourlyUsage: SyncZaiHourlyUsage(
                    xTime: [timestamp],
                    modelSeries: [.init(modelName: "glm", tokens: [42])],
                    dailyXTime: [timestamp],
                    dailyModelSeries: [.init(modelName: "glm", tokens: [420])])))
        }

        return SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: timestamp,
            deviceName: deviceName,
            deviceID: deviceID,
            appVersion: isNew ? "0.47.0.1" : "0.45.2.2",
            mobileVersion: isNew ? "1.20.0" : "1.19.1",
            notificationPushEnabled: true)
    }
}
