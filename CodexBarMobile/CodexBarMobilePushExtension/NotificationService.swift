import CloudKit
import CodexBarSync
import Foundation
import UserNotifications

/// `UNNotificationServiceExtension` that rewrites the incoming CloudKit push to
/// include the `providerName` from the triggering `QuotaTransition` record.
///
/// ### Why this exists
///
/// CloudKit subscription push payloads on our private-DB custom-zone setup can
/// carry a static locale-resolved body (Build 52's `String(localized:)`), but
/// they **cannot** carry per-record values. `titleLocalizationArgs` /
/// `alertLocalizationArgs` are silently dropped by CloudKit on this container,
/// and `desiredKeys` on a `CKRecordZoneSubscription` throws "cannot add
/// additionalFields to this subscription type" — so the subscription cannot
/// embed `providerName` in the push itself.
///
/// iOS invokes this extension before the notification is shown when the push
/// has `mutable-content: 1` (set by the subscription's `shouldSendMutableContent
/// = true`). We parse `CKRecordZoneNotification` out of the push, fetch the
/// latest `QuotaTransition` record in that zone, read `providerName`, and use
/// it as the notification title. The existing locale-resolved body from the
/// subscription is preserved — our only job is to prepend provider identity.
///
/// ### Failure tolerance
///
/// The extension has roughly 30 seconds before iOS delivers whatever content
/// we've mutated. If the CloudKit fetch fails, times out, or the payload isn't
/// a recognised zone notification, we deliver the **original** push content
/// unchanged — which is still the Build 52 state-specific localized body.
/// No regression from Build 52's user experience under extension failure.
///
/// ### Concurrency
///
/// `UNNotificationServiceExtension` is single-instance per push (Apple
/// guarantee), so the mutable state below is not actually shared across
/// concurrent invocations. We use `nonisolated(unsafe)` to acknowledge that
/// guarantee to Swift 6's strict checker without forcing the whole class into
/// `@MainActor` — the system invokes our overrides on a private dispatch
/// queue and may call `serviceExtensionTimeWillExpire()` from a different
/// thread than `didReceive(...)`.
final class NotificationService: UNNotificationServiceExtension {

    /// Wraps the system-provided callback so it can survive a Swift 6 closure
    /// capture into a `Task`. The system promises the handler is callable from
    /// any thread, so the `@unchecked Sendable` is sound in practice.
    private struct ContentHandlerBox: @unchecked Sendable {
        let call: (UNNotificationContent) -> Void
    }

    /// Wraps the mutable content for the same reason — `UNMutableNotificationContent`
    /// is a class without `Sendable` conformance in the iOS 17 SDK.
    private struct ContentBox: @unchecked Sendable {
        let value: UNMutableNotificationContent
    }

    /// Single-delivery latch. `UNNotificationServiceExtension` requires the
    /// content handler to be invoked **at most once** — invoking it twice is
    /// undefined behaviour. The fetch `Task` and `serviceExtensionTimeWillExpire`
    /// can race (the system cancels in-flight work but `fetchLatestProviderName`
    /// catches `CancellationError` and returns `nil`, so the task continues to
    /// the handler call after cancellation). This latch makes whichever path
    /// reaches the handler first the winner; the loser becomes a no-op.
    private final class DeliveryLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func tryFire() -> Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.fired else { return false }
            self.fired = true
            return true
        }
    }

    private nonisolated(unsafe) var pendingHandler: ContentHandlerBox?
    private nonisolated(unsafe) var pendingContent: UNMutableNotificationContent?
    private nonisolated(unsafe) var fetchTask: Task<Void, Never>?
    private nonisolated(unsafe) var deliveryLatch: DeliveryLatch?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let best = request.content.mutableCopy()
            as? UNMutableNotificationContent
        else {
            contentHandler(request.content)
            return
        }

        // Build 124: every NSE invocation logs to the shared App Group store
        // so the iOS app's Push Setup diagnostic UI surfaces the entire NSE
        // history without polluting the user-visible push body.
        let started = Date()
        NSEInvocationLog.shared.recordEntry(
            timestamp: started,
            event: .woke,
            zoneName: nil,
            detail: "userInfo keys: \(request.content.userInfo.keys.map { "\($0)" }.sorted().joined(separator: ","))")

        let handlerBox = ContentHandlerBox(call: contentHandler)
        let latch = DeliveryLatch()
        self.pendingHandler = handlerBox
        self.pendingContent = best
        self.deliveryLatch = latch

        guard let zoneID = QuotaZoneNotificationParser.extractQuotaZoneID(
            from: request.content.userInfo)
        else {
            // Not one of our quota zone notifications — deliver unchanged.
            NSEInvocationLog.shared.recordEntry(
                timestamp: started,
                event: .zoneNil,
                zoneName: nil,
                detail: "extractQuotaZoneID returned nil")
            if latch.tryFire() {
                handlerBox.call(best)
            }
            return
        }

        let contentBox = ContentBox(value: best)
        self.fetchTask = Self.makeFetchTask(
            startedAt: started,
            zoneID: zoneID,
            handler: handlerBox,
            content: contentBox,
            latch: latch)
    }

    /// Spawns the CloudKit fetch + content rewrite as a `Task`. Pulled out of
    /// `didReceive(...)` so the closure captures only function-local Sendable
    /// values — Swift 6's region-based isolation checker can't reason about a
    /// `Task` created inside a `nonisolated(unsafe)` method that captures
    /// `self`'s mutable state, but a free function with Sendable args sidesteps
    /// the issue.
    private static func makeFetchTask(
        startedAt: Date,
        zoneID: CKRecordZone.ID,
        handler: ContentHandlerBox,
        content: ContentBox,
        latch: DeliveryLatch) -> Task<Void, Never>
    {
        return Task {
            let parsed = QuotaZoneNotificationParser.parseQuotaZoneName(zoneID.zoneName)
            if parsed?.state == .warning {
                let result = await Self.fetchLatestWarningInfoDiagnostic(in: zoneID)
                switch result {
                case let .success(providerName, window, threshold, accountEmail):
                    content.value.title = Self.formatTitle(
                        providerName: providerName,
                        accountEmail: accountEmail)
                    content.value.body = Self.formatWarningBody(
                        providerName: providerName,
                        window: window,
                        threshold: threshold,
                        accountEmail: accountEmail)
                    NSEInvocationLog.shared.recordEntry(
                        timestamp: startedAt,
                        event: .ok,
                        zoneName: zoneID.zoneName,
                        detail: "rewrote body: provider=\(providerName) window=\(window) threshold=\(threshold) account=\(EmailRedaction.redact(accountEmail))")
                case let .empty(reason):
                    NSEInvocationLog.shared.recordEntry(
                        timestamp: startedAt,
                        event: .fetchNil,
                        zoneName: zoneID.zoneName,
                        detail: reason)
                case let .error(message):
                    NSEInvocationLog.shared.recordEntry(
                        timestamp: startedAt,
                        event: .fetchError,
                        zoneName: zoneID.zoneName,
                        detail: message)
                }
            } else {
                let info = await Self.fetchLatestProviderInfo(in: zoneID)
                if let info, !info.providerName.isEmpty {
                    content.value.title = Self.formatTitle(
                        providerName: info.providerName,
                        accountEmail: info.accountEmail)
                    NSEInvocationLog.shared.recordEntry(
                        timestamp: startedAt,
                        event: .ok,
                        zoneName: zoneID.zoneName,
                        detail: "title rewrite: \(info.providerName) account=\(EmailRedaction.redact(info.accountEmail))")
                } else {
                    NSEInvocationLog.shared.recordEntry(
                        timestamp: startedAt,
                        event: .fetchNil,
                        zoneName: zoneID.zoneName,
                        detail: "depleted/restored fetch returned nil")
                }
            }
            if latch.tryFire() {
                handler.call(content.value)
            }
        }
    }

    /// Diagnostic variant of `fetchLatestWarningInfo` that distinguishes
    /// between empty-result, error, and success. Build 124 only — once the
    /// pipeline is verified end-to-end we can collapse back to the optional-
    /// returning version, but for now we want the NSE log to record the
    /// exact CloudKit error message when fetch fails.
    enum WarningFetchResult {
        case success(providerName: String, window: String, threshold: Int, accountEmail: String?)
        case empty(reason: String)
        case error(message: String)
    }

    static func fetchLatestWarningInfoDiagnostic(
        in zoneID: CKRecordZone.ID
    ) async -> WarningFetchResult {
        let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        let query = CKQuery(
            recordType: CloudSyncConstants.quotaTransitionRecordType,
            predicate: NSPredicate(value: true))
        // INTENTIONALLY no sortDescriptors. Build 125 used `transitionAt` desc
        // sort + resultsLimit: 1 — but that depends on CK's secondary index
        // for `transitionAt`, which Apple's CKContainer infrastructure updates
        // **asynchronously after record save**. The subscription push fires
        // BEFORE the index catches up, so a sorted+limited query routinely
        // returns a stale older record instead of the one that just triggered
        // the push. Confirmed by NSE log @ 18:13:33 fetching `claude session 20`
        // when Mac had just written `claude weekly 10` at 18:13:32 — wrong
        // record returned by server-side sort.
        //
        // Build 126 fix: pull up to 100 records unsorted, then pick the record
        // with the newest `creationDate` (server-authoritative metadata that
        // doesn't go through a secondary index). With per-hour recordName
        // bucketing on the writer side, zones rarely accumulate beyond a few
        // dozen records, so the over-fetch is cheap.
        //
        // v0.27.0 build 65.2 adds `accountEmail` to `desiredKeys` — Mac
        // writes it when the triggering provider has a resolvable account
        // (Codex managed, Claude multi-account, etc.). Pre-65.2 Macs leave
        // it absent so we treat nil as "no account scope" and fall back to
        // the existing non-scoped body template.
        do {
            let (matchResults, _) = try await container.privateCloudDatabase.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: ["providerName", "accountEmail"],
                resultsLimit: 100)
            var newest: CKRecord?
            for (_, result) in matchResults {
                guard case let .success(record) = result else { continue }
                if let cur = newest {
                    let curDate = cur.creationDate ?? .distantPast
                    let newDate = record.creationDate ?? .distantPast
                    if newDate > curDate {
                        newest = record
                    }
                } else {
                    newest = record
                }
            }
            guard let record = newest else {
                return .empty(reason: "matchResults empty in \(zoneID.zoneName)")
            }
            guard let providerName = record["providerName"] as? String else {
                return .empty(reason: "record \(record.recordID.recordName) missing providerName")
            }
            let accountEmail = (record["accountEmail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAccount = (accountEmail?.isEmpty ?? true) ? nil : accountEmail
            guard let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
                record.recordID.recordName)
            else {
                return .success(
                    providerName: providerName,
                    window: "",
                    threshold: 0,
                    accountEmail: normalizedAccount)
            }
            return .success(
                providerName: providerName,
                window: parsed.window,
                threshold: parsed.threshold,
                accountEmail: normalizedAccount)
        } catch {
            let ckErr = error as? CKError
            let ckCode = ckErr.map { "code=\($0.code.rawValue)" } ?? "type=\(type(of: error))"
            return .error(message: "query failed \(ckCode): \(error.localizedDescription)")
        }
    }

    override func serviceExtensionTimeWillExpire() {
        self.fetchTask?.cancel()
        if let handler = self.pendingHandler,
           let content = self.pendingContent,
           let latch = self.deliveryLatch,
           latch.tryFire()
        {
            handler.call(content)
        }
    }

    // MARK: - CloudKit fetch

    /// Returns the most recent `QuotaTransition` record's `providerName` in the
    /// given zone, or `nil` if the fetch fails or returns nothing useful.
    ///
    /// Build 126: stopped relying on `transitionAt` server-side sort — the
    /// secondary index lags record save, so the "latest" record returned by
    /// CloudKit is routinely the previous burst's record, not the one that
    /// just fired this NSE. Now we fetch up to 100 records unsorted and pick
    /// the newest by server-authoritative `creationDate` client-side.
    static func fetchLatestProviderName(
        in zoneID: CKRecordZone.ID) async -> String?
    {
        await Self.fetchLatestProviderInfo(in: zoneID)?.providerName
    }

    /// Returns the most recent record's providerName + optional
    /// accountEmail. v0.27.0 build 65.2 — added the `accountEmail`
    /// fetch alongside the existing `providerName` so depleted /
    /// restored pushes can also include the triggering account in the
    /// rewritten title. Pre-65.2 Macs leave the field absent — caller
    /// sees `accountEmail == nil` and falls back to the bare provider
    /// name.
    static func fetchLatestProviderInfo(
        in zoneID: CKRecordZone.ID
    ) async -> (providerName: String, accountEmail: String?)? {
        let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        let query = CKQuery(
            recordType: CloudSyncConstants.quotaTransitionRecordType,
            predicate: NSPredicate(value: true))
        do {
            let (matchResults, _) = try await container.privateCloudDatabase.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: ["providerName", "accountEmail"],
                resultsLimit: 100)
            var newest: CKRecord?
            for (_, result) in matchResults {
                guard case let .success(record) = result else { continue }
                if let cur = newest {
                    if (record.creationDate ?? .distantPast) > (cur.creationDate ?? .distantPast) {
                        newest = record
                    }
                } else {
                    newest = record
                }
            }
            guard let record = newest,
                  let providerName = record["providerName"] as? String
            else { return nil }
            let accountEmail = (record["accountEmail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAccount = (accountEmail?.isEmpty ?? true) ? nil : accountEmail
            return (providerName, normalizedAccount)
        } catch {
            return nil
        }
    }

    /// iOS 1.6.0 / Mac 0.25.2 — fetches the latest warning record and
    /// parses its `recordName` to extract the crossed threshold and
    /// affected window so the push body can show specifics.
    /// `recordName` format documented at
    /// `CloudSyncManager.writeQuotaWarningTransition`.
    ///
    /// Returns `nil` when the fetch fails or the recordName format
    /// doesn't parse — the caller then falls back to the static
    /// subscription alertBody (the generic "[Provider] usage warning"),
    /// which still gives the user an actionable signal. No regression
    /// vs not having NSE enrichment at all.
    static func fetchLatestWarningInfo(
        in zoneID: CKRecordZone.ID
    ) async -> (providerName: String, window: String, threshold: Int)? {
        let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        let query = CKQuery(
            recordType: CloudSyncConstants.quotaTransitionRecordType,
            predicate: NSPredicate(value: true))
        query.sortDescriptors = [
            NSSortDescriptor(key: "transitionAt", ascending: false),
        ]
        do {
            let (matchResults, _) = try await container.privateCloudDatabase.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: ["providerName"],
                resultsLimit: 1)
            guard let first = matchResults.first else { return nil }
            let record = try first.1.get()
            guard let providerName = record["providerName"] as? String else { return nil }
            guard let parsed = QuotaZoneNotificationParser.parseWarningRecordName(
                record.recordID.recordName)
            else {
                // Unparseable recordName — preserve provider title at least.
                return (providerName, "", 0)
            }
            return (providerName, parsed.window, parsed.threshold)
        } catch {
            return nil
        }
    }

    /// Builds the push body for a warning notification. Localized
    /// templates handle the 4 supported languages; the threshold and
    /// window are formatted via `%lld` + `%@`. The window string is
    /// localized via a small lookup so "session" / "weekly" become
    /// "Session" / "Weekly" / "会话" / "週間" etc.
    ///
    /// v0.27.0 build 65.2 — account scoping is reflected in the title
    /// (`formatTitle`) rather than the body so the body stays uniform
    /// across single-account and multi-account providers. Accepting
    /// `accountEmail` here keeps the call sites symmetric for a future
    /// body-template change without an API churn.
    static func formatWarningBody(
        providerName: String,
        window: String,
        threshold: Int,
        accountEmail _: String? = nil
    ) -> String {
        let windowLabel = self.localizedWindowLabel(window)
        let template = String(localized: "Push.QuotaWarning.detailBody")
        // %1$@ providerName · %2$@ windowLabel · %3$lld threshold
        return String(format: template, providerName, windowLabel, threshold)
    }

    /// Builds the push title (depleted / restored / warning). When Mac
    /// supplies an `accountEmail`, formats as "Provider · account@…"
    /// so the user immediately sees which account fired the push on
    /// the locked screen. Falls back to bare providerName when nil.
    ///
    /// **Template note for translators**: `Push.Quota.titleWithAccount`
    /// is intentionally `"%1$@ · %2$@"` in ALL 4 locales (en / zh-Hans
    /// / zh-Hant / ja). The mid-dot U+00B7 is universal punctuation,
    /// and the order (provider then account) is fixed by lock-screen
    /// UX requirements regardless of locale grammar. Do NOT "localize"
    /// the separator or argument order — that would break the visual
    /// scan pattern users on the lock screen rely on.
    static func formatTitle(providerName: String, accountEmail: String?) -> String {
        guard let accountEmail, !accountEmail.isEmpty else { return providerName }
        let template = String(localized: "Push.Quota.titleWithAccount")
        // %1$@ providerName · %2$@ accountEmail
        return String(format: template, providerName, accountEmail)
    }

    private static func localizedWindowLabel(_ window: String) -> String {
        switch window {
        case "session": return String(localized: "Push.QuotaWarning.window.session")
        case "weekly":  return String(localized: "Push.QuotaWarning.window.weekly")
        default:        return window
        }
    }
}
