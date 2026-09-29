import CloudKit
import CodexBarSync
import Foundation
import Testing

@Suite("QuotaZoneNotificationParser Tests")
struct QuotaZoneNotificationParserTests {

    @Test("isQuotaPushZone accepts depleted zone")
    func acceptsDepletedZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaDepletedZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone accepts restored zone")
    func acceptsRestoredZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaRestoredZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone rejects legacy QuotaTransitionsZone")
    func rejectsLegacyZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudSyncConstants.quotaTransitionsZoneName,
            ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone rejects unrelated zone")
    func rejectsUnrelatedZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "DeviceSnapshotsZone", ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone rejects arbitrary zone name")
    func rejectsArbitraryZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "FooBarZone", ownerName: CKCurrentUserDefaultName)
        #expect(!QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("extractQuotaZoneID returns nil for empty userInfo")
    func emptyUserInfoReturnsNil() {
        #expect(QuotaZoneNotificationParser.extractQuotaZoneID(from: [:]) == nil)
    }

    @Test("extractQuotaZoneID returns nil for non-CK userInfo")
    func nonCloudKitUserInfoReturnsNil() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": "Test"],
            "custom": "value",
        ]
        #expect(QuotaZoneNotificationParser.extractQuotaZoneID(from: userInfo) == nil)
    }

    // MARK: - Per-provider zone recognition (Build 54+)

    @Test("isQuotaPushZone accepts per-provider depleted zone")
    func acceptsPerProviderDepletedZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "Quota-codex-depletedZone",
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone accepts per-provider restored zone")
    func acceptsPerProviderRestoredZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "Quota-claude-restoredZone",
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("isQuotaPushZone accepts per-provider warning zone (iOS 1.6.0)")
    func acceptsPerProviderWarningZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "Quota-perplexity-warningZone",
            ownerName: CKCurrentUserDefaultName)
        #expect(QuotaZoneNotificationParser.isQuotaPushZone(zoneID))
    }

    @Test("parseQuotaZoneName extracts (providerID, state) for warning")
    func parseWarningZoneName() {
        let parsed = QuotaZoneNotificationParser.parseQuotaZoneName(
            "Quota-codex-warningZone")
        #expect(parsed?.providerID == "codex")
        #expect(parsed?.state == .warning)
    }

    @Test("parseQuotaZoneName extracts (providerID, state) for depleted")
    func parseDepletedZoneName() {
        let parsed = QuotaZoneNotificationParser.parseQuotaZoneName(
            "Quota-claude-depletedZone")
        #expect(parsed?.providerID == "claude")
        #expect(parsed?.state == .depleted)
    }

    @Test("parseQuotaZoneName rejects malformed names")
    func parseRejectsMalformed() {
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName("NotAQuotaZone") == nil)
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName("Quota-no-state-Zone") == nil)
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName("") == nil)
    }

    @Test("parseQuotaZoneName rejects legacy global zone names")
    func parseRejectsGlobalLegacy() {
        // The legacy QuotaDepletedZone / QuotaRestoredZone names are
        // matched by `isQuotaPushZone` via the constants, NOT by
        // `parseQuotaZoneName` which only handles per-provider format.
        // Pinning this so the NSE branch on `parsed?.state == .warning`
        // doesn't accidentally fire for legacy depleted zones.
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName(
            "QuotaDepletedZone") == nil)
        #expect(QuotaZoneNotificationParser.parseQuotaZoneName(
            "QuotaRestoredZone") == nil)
    }

    // MARK: - Warning recordName parsing

    @Test("parseWarningRecordName extracts window + threshold")
    func parseWarningRecord() {
        let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
            "codex-session-t50-477312")
        #expect(parsed?.providerID == "codex")
        #expect(parsed?.window == "session")
        #expect(parsed?.threshold == 50)
    }

    @Test("parseWarningRecordName handles weekly window")
    func parseWeeklyWarningRecord() {
        let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
            "claude-weekly-t20-477500")
        #expect(parsed?.providerID == "claude")
        #expect(parsed?.window == "weekly")
        #expect(parsed?.threshold == 20)
    }

    @Test("parseWarningRecordName preserves hashed named-window identity and display label")
    func parseNamedWindowWarningRecord() {
        let label = "Organization · Monthly · Shared · Hard"
        let recordName = QuotaZoneNotificationParser.warningRecordName(
            providerID: "aixy",
            window: "monthly",
            threshold: 50,
            hourBucket: 477312,
            identityHash: "0123456789abcdef01234567",
            windowDisplayLabel: label)
        let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
            recordName)
        #expect(parsed?.providerID == "aixy")
        #expect(parsed?.window == "monthly")
        #expect(parsed?.threshold == 50)
        #expect(parsed?.windowLabel == label)
        let legacy = Self.parseWarningRecordNameWithV066Rules(recordName)
        #expect(legacy?.window == "monthly")
        #expect(legacy?.threshold == 50)
    }

    @Test("parseWarningRecordName reads existing post-hour identity suffixes")
    func parsePreviouslyWrittenNamedWindowWarningRecord() {
        let label = "Organization · Monthly · Shared · Hard"
        let encoded = QuotaZoneNotificationParser.encodeWarningWindowLabel(label)!
        let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
            "aixy-monthly-t50-477312-w0123456789abcdef01234567-l\(encoded)")
        #expect(parsed?.providerID == "aixy")
        #expect(parsed?.window == "monthly")
        #expect(parsed?.threshold == 50)
        #expect(parsed?.windowLabel == label)
    }

    private static func parseWarningRecordNameWithV066Rules(
        _ recordName: String) -> (window: String, threshold: Int)?
    {
        let parts = recordName.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 4,
              let thresholdPart = parts.dropLast(1).last,
              thresholdPart.hasPrefix("t"),
              let threshold = Int(thresholdPart.dropFirst())
        else { return nil }
        return (String(parts[parts.count - 3]), threshold)
    }

    @Test("near-simultaneous warning records do not claim an exact trigger")
    func warningRecordAmbiguity() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!QuotaZoneNotificationParser.warningRecordsAreAmbiguous(transitionTimes: [now]))
        #expect(QuotaZoneNotificationParser.warningRecordsAreAmbiguous(
            transitionTimes: [now, now.addingTimeInterval(0.4)],
            latestTransitionAt: now.addingTimeInterval(0.4)))
        #expect(!QuotaZoneNotificationParser.warningRecordsAreAmbiguous(
            transitionTimes: [now, now.addingTimeInterval(0.5), now.addingTimeInterval(10)],
            latestTransitionAt: now.addingTimeInterval(10)))
        #expect(QuotaZoneNotificationParser.warningRecordsAreAmbiguous(
            transitionTimes: [now.addingTimeInterval(10), now.addingTimeInterval(10.5)],
            latestTransitionAt: now.addingTimeInterval(10.5)))
    }

    @Test("warning record reads stop at a fixed bound when more records remain")
    func warningRecordScanBound() {
        #expect(!QuotaZoneNotificationParser.warningRecordScanReachedLimit(
            recordsExamined: 499,
            hasContinuationCursor: true))
        #expect(!QuotaZoneNotificationParser.warningRecordScanReachedLimit(
            recordsExamined: 500,
            hasContinuationCursor: false))
        #expect(QuotaZoneNotificationParser.warningRecordScanReachedLimit(
            recordsExamined: QuotaZoneNotificationParser.warningRecordScanLimit,
            hasContinuationCursor: true))
    }

    @Test("parseWarningRecordName rejects malformed names")
    func parseWarningRecordMalformed() {
        #expect(QuotaZoneNotificationParser.parseWarningRecordName(
            "codex-session-477312") == nil) // missing threshold
        #expect(QuotaZoneNotificationParser.parseWarningRecordName(
            "codex-session-tABC-477312") == nil) // non-numeric threshold
        #expect(QuotaZoneNotificationParser.parseWarningRecordName("") == nil)
    }
}
