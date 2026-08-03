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

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    @Test("old z.ai payload decodes daily series as empty")
    func oldZaiPayload() throws {
        let json = """
        {"xTime":["2026-08-03T09:00:00Z"],"modelSeries":[{"modelName":"glm","tokens":[42]}]}
        """
        let decoded = try Self.decoder.decode(SyncZaiHourlyUsage.self, from: Data(json.utf8))
        #expect(decoded.xTime.count == 1)
        #expect(decoded.dailyXTime.isEmpty)
        #expect(decoded.dailyModelSeries.isEmpty)
    }

    @Test("new ZoomMate and workspace fields round trip")
    func newFieldsRoundTrip() throws {
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

    @Test("pre-1.20 provider payload decodes additive fields as nil")
    func oldProviderPayload() throws {
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

    @Test("mixed-version merge keeps newest non-nil v0.47 fields")
    func mixedVersionMerge() throws {
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
    @Test("2 Mac x 2 iPhone old/new matrix", arguments: Array(0..<16))
    func fourDeviceCompatibilityMatrix(mask: Int) throws {
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
        let encoded = try sourceSnapshots.map(Self.encoder.encode)

        let phoneA = try Self.readMatrixPhone(isNew: iPhoneANew, encoded: encoded)
        let phoneB = try Self.readMatrixPhone(isNew: iPhoneBNew, encoded: encoded)

        #expect(phoneA.deviceIDs == ["matrix-mac-a", "matrix-mac-b"])
        #expect(phoneB.deviceIDs == ["matrix-mac-a", "matrix-mac-b"])
        #expect(phoneA.providerIDs.contains("codex"))
        #expect(phoneB.providerIDs.contains("codex"))

        let hasNewWriter = macANew || macBNew
        let newProviderIDs: Set<String> = ["notion", "qwencloud", "xai", "zoommate", "zai"]
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
        let hasV047TypedFields: Bool
    }

    @MainActor
    private static func readMatrixPhone(
        isNew: Bool,
        encoded: [Data]) throws -> MatrixPhoneResult
    {
        if !isNew {
            let snapshots = try encoded.map { try Self.decoder.decode(LegacySnapshot.self, from: $0) }
            let providers = snapshots.flatMap(\.providers)
            #expect(providers.allSatisfy { $0.primary != nil && !$0.isError })
            #expect(providers.allSatisfy { !$0.providerName.isEmpty && $0.lastUpdated > .distantPast })
            #expect(snapshots.allSatisfy { !$0.deviceName.isEmpty && $0.syncTimestamp > .distantPast })
            return MatrixPhoneResult(
                deviceIDs: snapshots.compactMap(\.deviceID).sorted(),
                providerIDs: Set(providers.map(\.providerID)),
                hasV047TypedFields: false)
        }

        let snapshots = try encoded.map { try Self.decoder.decode(SyncedUsageSnapshot.self, from: $0) }
        // Two separate calls create the same isolated cache state an iPhone
        // reconstructs after its own full fetch. The matrix invokes this once
        // per phone, so cache convergence is verified without shared memory.
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(perProviderSnapshots: snapshots, legacySnapshots: [])
        let cached = cache.buildDeviceSnapshots()
        let merged = try #require(CloudSyncReader.mergeSnapshots(cached))
        let typed = merged.providers.contains(where: {
            $0.accountOrganization != nil || $0.zoomMateCredits != nil
                || $0.zaiHourlyUsage?.dailyModelSeries.isEmpty == false
        })
        return MatrixPhoneResult(
            deviceIDs: cached.compactMap(\.deviceID).sorted(),
            providerIDs: Set(merged.providers.map(\.providerID)),
            hasV047TypedFields: typed)
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
