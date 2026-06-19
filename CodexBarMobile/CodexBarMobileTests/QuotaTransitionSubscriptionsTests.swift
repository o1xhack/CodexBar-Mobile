import CloudKit
import Testing

@testable import CodexBarMobile

/// Pins the `CKSubscription.NotificationInfo` payload used by every quota
/// transition subscription. The `shouldSendMutableContent = true` bit in
/// particular regressed silently in 1.6.0 build ≤121 — every quota push
/// landed without `mutable-content: 1`, so iOS never woke the NSE, and
/// the rich body (`"Codex session usage at 50% threshold"`) was never
/// substituted for the static fallback (`"Codex usage warning"`). If this
/// test fails, all quota push body / title rewrites are dead.
@Suite("Quota transition subscriptions")
struct QuotaTransitionSubscriptionsTests {
    @Test("notification info sets alertBody from input")
    func notificationInfoSetsAlertBody() {
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "Codex 用量警告")
        #expect(info.alertBody == "Codex 用量警告")
    }

    @Test("notification info wakes NSE via mutable-content flag")
    func notificationInfoEnablesMutableContent() {
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "anything")
        // shouldSendMutableContent translates into `mutable-content: 1`
        // in the APNS payload, which is the ONLY way to wake the
        // NotificationService extension to rewrite the push body.
        #expect(info.shouldSendMutableContent == true)
    }

    @Test("notification info plays default sound")
    func notificationInfoSetsDefaultSound() {
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "anything")
        #expect(info.soundName == "default")
    }

    @Test("notification info leaves localization-args empty")
    func notificationInfoLeavesLocalizationArgsEmpty() {
        // titleLocalizationArgs / alertLocalizationArgs are intentionally
        // unused on this CloudKit container; the localized body is baked
        // into `alertBody` at setup time. The drift-detection logic in
        // setupIfNeeded() rejects subs whose info has either of these
        // populated, so leaving them nil here is part of the contract.
        let info = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "anything")
        #expect((info.titleLocalizationArgs ?? []).isEmpty)
        #expect((info.alertLocalizationArgs ?? []).isEmpty)
    }

    @Test("diagnostic summary groups warning subscriptions separately")
    func diagnosticSummaryGroupsWarningSubscriptions() {
        let zoneID = CKRecordZone.ID(
            zoneName: "Quota-codex-warningZone",
            ownerName: CKCurrentUserDefaultName)
        let sub = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: "quota-codex-warning-sub")
        sub.notificationInfo = QuotaTransitionSubscriptions.makeNotificationInfo(
            alertBody: "Codex usage warning")

        let summary = PushSetupDiagnostic.formatSubscriptions([sub])

        #expect(summary.contains("1 × quota-*-warning-sub"))
        #expect(!summary.contains("other"))
    }
}
