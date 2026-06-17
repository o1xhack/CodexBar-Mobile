import CloudKit
import CodexBarSync
import Foundation

/// Sets up one `CKRecordZoneSubscription` per `(provider, state)` pair so every
/// incoming CloudKit push already carries the provider's name in its body text,
/// then asks APNS to wake the `NotificationService` extension (NSE) to enrich
/// the body further with record-specific context (e.g. the crossed warning
/// threshold).
///
/// ### Two-layer push copy (iOS 1.6.0 / Mac 0.25.2+)
///
/// 1. **Static fallback** baked into the subscription's `alertBody` at
///    setup time — e.g. `"Codex usage warning"` / `"Codex 用量警告"`. This is
///    what shows up if the NSE doesn't run (low memory, extension load
///    failure, etc.) so the push is still informative.
/// 2. **NSE-enriched body** rewritten by `NotificationService` after the
///    push lands — e.g. `"Codex session usage at 50% threshold"`. The NSE
///    parses the record's `recordName` (which encodes window + threshold)
///    and formats `Push.QuotaWarning.detailBody`. Without this layer the
///    warning push has no way to surface the threshold % because the
///    same subscription serves all thresholds for one provider.
///
/// Waking the NSE requires `shouldSendMutableContent = true` on the
/// subscription's `CKSubscription.NotificationInfo`. Build 53 once
/// concluded this CloudKit container silently strips the flag — that
/// turned out to be incorrect (the actual culprit was Build 53's NSE not
/// being correctly bundled). The flag works on this container; the
/// drift-detection logic below checks it explicitly so older subs that
/// were saved without it get re-saved on next launch.
///
/// ### Why one subscription per provider instead of one per state
///
/// We still use one sub per `(provider, state)` pair so that the static
/// fallback `alertBody` already carries the provider's display name
/// without needing the NSE. This way, even if the NSE fails on a given
/// push, the user still sees `"Codex usage warning"` (not just
/// `"CodexBar"`). The iPhone's locale is resolved at subscription-setup
/// time, so each iPhone bakes its own language into the fallback.
///
/// ### What shows up on the iPhone
///
/// - **Title**: iOS default (the app name "CodexBar"). NSE can rewrite
///   this too via `mutableContent.title` for depleted/restored.
/// - **Body, NSE OK**: e.g. "Codex session usage at 50% threshold" —
///   threshold and window parsed from the record's `recordName`.
/// - **Body, NSE skipped**: e.g. "Codex usage warning" / "Codex 用量警告"
///   — the static fallback baked into the sub at setup.
///
/// ### Scale
///
/// `QuotaProviderList.providers.count × 3` subscriptions (159 today, iOS 1.13.0) created
/// in a single batched `modifySubscriptions(saving:deleting:)` call on first
/// launch. Subsequent launches diff the server state against the expected
/// config and only save the subs whose `alertBody` has drifted (e.g. locale
/// change, new display name, new provider in the list). CloudKit Private DB
/// has no practical subscription limit for a single user at this scale.
@MainActor
final class QuotaTransitionSubscriptions {
    static let shared = QuotaTransitionSubscriptions()

    private let containerIdentifier = CloudSyncConstants.containerIdentifier
    private let recordType = CloudSyncConstants.quotaTransitionRecordType

    /// Closures are used for `localizedAlertBody` so `String(localized:)`
    /// re-resolves against the iPhone's **current** locale on every call,
    /// instead of the locale that was active when `configs` was populated.
    /// That's what lets a locale change trigger a sub recreate on next launch
    /// (the stored body no longer matches the expected body).
    private struct SubConfig {
        let zoneName: String
        let subscriptionID: String
        let localizedAlertBody: () -> String
    }

    /// Builds the full `(provider × state)` matrix of desired subscriptions.
    ///
    /// **Subscription-ID format WIRE CONTRACT:**
    /// `"quota-{providerID}-{state}-sub"` (e.g. `"quota-codex-depleted-sub"`).
    /// This ID is the primary key CloudKit uses to identify the
    /// subscription; once saved on the server, re-registering with a
    /// different ID creates a duplicate rather than updating, and
    /// `reconcileSubscriptions()` below uses the ID for diff detection.
    /// Changing the format (separator, suffix, casing) on a live user would
    /// orphan their existing subscriptions — pushes would keep firing
    /// against the old ID and the new config would silently never activate.
    private func makeConfigs() -> [SubConfig] {
        var configs: [SubConfig] = []
        for provider in QuotaProviderList.providers {
            configs.append(SubConfig(
                zoneName: QuotaProviderList.quotaZoneName(
                    providerID: provider.id, state: "depleted"),
                subscriptionID: "quota-\(provider.id)-depleted-sub",
                localizedAlertBody: {
                    let template = String(localized: "Push.QuotaDepleted.bodyWithProvider")
                    return String(format: template, provider.displayName)
                }))
            configs.append(SubConfig(
                zoneName: QuotaProviderList.quotaZoneName(
                    providerID: provider.id, state: "restored"),
                subscriptionID: "quota-\(provider.id)-restored-sub",
                localizedAlertBody: {
                    let template = String(localized: "Push.QuotaRestored.bodyWithProvider")
                    return String(format: template, provider.displayName)
                }))
            // iOS 1.6.0 / Mac 0.25.2 — third state per provider for the
            // pre-depletion warning thresholds. The static alertBody is
            // generic ("[Provider] usage warning") because the actual
            // threshold % is encoded in the record's recordName, which
            // `NotificationService` (NSE) reads to rewrite the body
            // with the specific window + threshold ("Codex session at
            // 50%"). Subscription count: 76 → 114 zones. APPENDED at
            // the tail so existing 76-entry CK subscription IDs stay
            // stable across the 1.5.x/1.6.0 upgrade.
            configs.append(SubConfig(
                zoneName: QuotaProviderList.quotaZoneName(
                    providerID: provider.id, state: "warning"),
                subscriptionID: "quota-\(provider.id)-warning-sub",
                localizedAlertBody: {
                    let template = String(localized: "Push.QuotaWarning.bodyWithProvider")
                    return String(format: template, provider.displayName)
                }))
        }
        return configs
    }

    /// Subscription IDs to delete on upgrade. Covers Build 42–49
    /// (single zone-level sub) and Build 52–53 (state-level subs; provider
    /// was expected to come from localization args or the now-disabled
    /// service extension).
    private let legacySubscriptionIDs: [CKSubscription.ID] = [
        CloudSyncConstants.quotaTransitionLegacySubscriptionID,
        CloudSyncConstants.quotaTransitionDepletedSubscriptionID,
        CloudSyncConstants.quotaTransitionRestoredSubscriptionID,
    ]

    private init() {}

    /// Configures the `(provider, state)` subscription matrix and cleans up
    /// legacy subscriptions from older builds. Idempotent — safe to call on
    /// every launch and on every `CKAccountChangedNotification`.
    func setupIfNeeded() async {
        let diag = await PushSetupDiagnostic.shared
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase

        // Step 0: clean up legacy subs. Safe to no-op if they don't exist.
        for legacyID in self.legacySubscriptionIDs {
            _ = try? await database.deleteSubscription(withID: legacyID)
        }

        let configs = self.makeConfigs()

        // Step 1: batch create all zones in one round-trip. CloudKit treats
        // saving an existing zone as a no-op, so this is idempotent.
        let zones = configs.map { CKRecordZone(zoneName: $0.zoneName) }
        do {
            _ = try await database.modifyRecordZones(saving: zones, deleting: [])
            await diag.recordZone("✓ \(zones.count) quota zones ensured")
        } catch {
            let msg = "✗ quota zones batch create failed: \(error.localizedDescription)"
            print("[CodexBar Push v6] \(msg)")
            await diag.recordZone(msg)
            await diag.recordError(msg)
            // Keep going — individual zone creates may succeed implicitly when
            // the subscription save references them.
        }

        // Step 2: diff server state vs expected configs.
        let existing: [CKSubscription]
        do {
            existing = try await database.allSubscriptions()
        } catch {
            let msg = "✗ allSubscriptions failed: \(error.localizedDescription)"
            print("[CodexBar Push v6] \(msg)")
            await diag.recordError(msg)
            await diag.refreshSubscriptionList()
            return
        }

        var subsToSave: [CKSubscription] = []
        var alreadyCorrect = 0
        for config in configs {
            let expectedBody = config.localizedAlertBody()
            let zoneID = CKRecordZone.ID(
                zoneName: config.zoneName, ownerName: CKCurrentUserDefaultName)
            if let zoneSub = existing.first(where: {
                $0.subscriptionID == config.subscriptionID
            }) as? CKRecordZoneSubscription,
               zoneSub.zoneID == zoneID,
               zoneSub.recordType == recordType,
               let info = zoneSub.notificationInfo,
               info.alertBody == expectedBody,
               info.shouldSendMutableContent,
               (info.titleLocalizationArgs ?? []).isEmpty,
               (info.alertLocalizationArgs ?? []).isEmpty
            {
                alreadyCorrect += 1
                continue
            }

            // Either missing or drifted — queue for save. CloudKit treats save
            // with an existing subscriptionID as an overwrite. Note: any sub
            // saved before iOS 1.6.0 build 122 lacks `shouldSendMutableContent`
            // and will be re-saved here on first launch of the new build so the
            // NSE wakes up for subsequent pushes.
            let sub = CKRecordZoneSubscription(
                zoneID: zoneID, subscriptionID: config.subscriptionID)
            sub.recordType = self.recordType
            sub.notificationInfo = Self.makeNotificationInfo(alertBody: expectedBody)
            subsToSave.append(sub)
        }

        let summaryPrefix = "✓ \(configs.count) subs desired, "
            + "\(alreadyCorrect) already correct, "
            + "\(subsToSave.count) to save"
        print("[CodexBar Push v6] \(summaryPrefix)")
        await diag.recordDepletedSub(summaryPrefix)
        await diag.recordRestoredSub("")

        // Step 3: batch save the drifted subs.
        if !subsToSave.isEmpty {
            do {
                _ = try await database.modifySubscriptions(
                    saving: subsToSave, deleting: [])
                let msg = "✓ saved \(subsToSave.count) subs"
                print("[CodexBar Push v6] \(msg)")
                await diag.recordDepletedSub(summaryPrefix + " — " + msg)
            } catch {
                let msg = "✗ sub batch save failed: \(error.localizedDescription)"
                print("[CodexBar Push v6] \(msg)")
                await diag.recordError(msg)
            }
        }

        await diag.refreshSubscriptionList()
    }

    /// Runs a persistence test on a bare `CKRecordZoneSubscription` in the
    /// first provider's depleted zone. Representative of the real subs since
    /// all of them share the same subscription type + alertBody-only payload.
    func runPersistenceTest() async -> String {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let testID = "ios-persistence-test"
        guard let firstProvider = QuotaProviderList.providers.first else {
            return "✗ no providers configured"
        }
        let zoneName = QuotaProviderList.quotaZoneName(
            providerID: firstProvider.id, state: "depleted")
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        do {
            try await self.ensureZoneExists(database: database, zoneID: zoneID)
        } catch {
            return "✗ zone creation failed: \(error.localizedDescription)"
        }

        // Always clean up on exit
        defer {
            Task { try? await database.deleteSubscription(withID: testID) }
        }

        do {
            _ = try? await database.deleteSubscription(withID: testID)
            let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: testID)
            sub.recordType = recordType
            sub.notificationInfo = Self.makeNotificationInfo(alertBody: "Persistence test")
            _ = try await database.modifySubscriptions(saving: [sub], deleting: [])
        } catch {
            return "✗ save failed: \(error.localizedDescription)"
        }

        let persisted: Bool
        do {
            let all = try await database.allSubscriptions()
            persisted = all.contains(where: { $0.subscriptionID == testID })
        } catch {
            return "✗ allSubscriptions failed: \(error.localizedDescription)"
        }

        return persisted
            ? "✓ CKRecordZoneSubscription persists from iOS!"
            : "✗ NOT FOUND after save — same issue as CKQuerySubscription"
    }

    // MARK: - Internals

    /// Builds the `CKSubscription.NotificationInfo` payload used by every quota
    /// transition subscription this class creates (real + persistence test).
    ///
    /// `shouldSendMutableContent = true` is REQUIRED to wake the
    /// `NotificationService` extension — without it APNS delivers the static
    /// `alertBody` only and the NSE never gets a chance to rewrite the body
    /// with record-specific context (e.g. the crossed warning threshold).
    /// Both `setupIfNeeded()` and `runPersistenceTest()` go through this
    /// helper so the flag can't drift between paths.
    ///
    /// Exposed `internal` for `QuotaTransitionSubscriptionsTests` to assert
    /// the flag is set; not intended to be called outside this file.
    /// `nonisolated` because it touches no actor state — keeps the test
    /// callable from a plain synchronous test context.
    nonisolated static func makeNotificationInfo(alertBody: String) -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.alertBody = alertBody
        info.soundName = "default"
        info.shouldSendMutableContent = true
        return info
    }

    private func ensureZoneExists(
        database: CKDatabase, zoneID: CKRecordZone.ID) async throws
    {
        do {
            _ = try await database.recordZone(for: zoneID)
            return
        } catch let error as CKError where error.code == .zoneNotFound {
            // Fall through to create
        }
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
    }
}
