import CodexBarCore
import CodexBarSync
import Foundation

/// Protocol that wraps the `QuotaTransition` CloudKit record write so it can be
/// mocked in unit tests, mirroring the existing `SessionQuotaNotifying` pattern.
@MainActor
protocol QuotaTransitionWriting: AnyObject {
    func write(
        transition: SessionQuotaTransition,
        provider: UsageProvider,
        accountDisplayName: String?)
    /// iOS 1.6.0 / Mac 0.25.2 — fires a `QuotaTransition` record with
    /// state=`"warning"` to the per-provider warning zone so iOS receives
    /// a push notification when the user crosses a configured threshold
    /// (not just at depletion). See `Research/020-multi-account-comprehensive.md`
    /// §R7.4 Phase 2.
    ///
    /// v0.27.0 build 65.2 added `accountDisplayName` so multi-account
    /// pushes can include the triggering account in the body (e.g.
    /// "Codex (admin@example.com) — Session at 50%").
    func writeQuotaWarning(
        event: QuotaWarningEvent,
        provider: UsageProvider)
}

/// Writes `QuotaTransition` records to CloudKit so iOS receives a visible alert push
/// via the existing `CKQuerySubscription` (configured in iOS app).
///
/// This is the **server-side decided notification** path: Mac just persists the fact
/// of the transition; CloudKit + APNs deliver the visible push directly to iPhone
/// without requiring the iOS app to wake up. Replaces the failed silent-push design.
///
/// ### Debounce
///
/// To avoid spamming iPhone when the same provider's quota oscillates near the
/// threshold, writes are debounced per `(provider, state)` key with a 5-minute
/// window. The most recent write within that window wins; earlier ones inside the
/// window are dropped client-side.
///
/// ### Idempotency
///
/// Record names are derived deterministically from `(deviceID, provider, state, hourBucket)`,
/// so two writes within the same hour for the same `(provider, state)` from the same
/// Mac collapse to a single CloudKit record (an update, not a duplicate insert). The
/// subscription's `firesOnRecordCreation` only fires on the first record of that hour,
/// so the user sees at most one push per hour for the same `(provider, state)` per Mac.
@MainActor
final class QuotaTransitionWriter: QuotaTransitionWriting {
    private let logger = CodexBarLog.logger(LogCategories.sessionQuotaNotifications)

    /// Tracks the last successful write per `(provider, state)` to enforce a debounce.
    private var lastWriteByKey: [String: Date] = [:]

    /// Minimum interval between two writes for the same `(provider, state)`.
    ///
    /// 5 minutes is a **user-experience constant**, not an API limit. It
    /// prevents notification spam when a provider's usage oscillates across
    /// the "depleted" / "restored" threshold (e.g. 99% → 100% → 99% due to
    /// retry / eviction churn), which each would otherwise fire a push on
    /// the iPhone. The trade-off is a 5-minute delay for a legitimate
    /// oscillation-then-real-change. Shortening spams users; lengthening
    /// delays alerts past usefulness. If adjusting, validate on a real
    /// Perplexity / Codex usage burst pattern and check the push-notification
    /// cadence in Settings → Notifications.
    private let debounceInterval: TimeInterval = 5 * 60

    /// Tracks the last successful warning write per (provider, window,
    /// threshold) so multi-threshold crossings within the same provider
    /// stay independent — crossing 50% should not suppress a subsequent
    /// 20% crossing if it happens within the debounce window. Keyed
    /// distinctly from `lastWriteByKey` (depleted/restored debounce).
    private var lastWarningWriteByKey: [String: Date] = [:]

    /// Warning debounce is **shorter** than depleted/restored because
    /// the underlying logic (`QuotaWarningNotificationLogic.crossedThreshold`)
    /// already filters out repeated firings of the same threshold via
    /// `firedThresholds`, so the writer mostly sees genuinely new
    /// crossings. The 60s window catches the narrow case where two Macs
    /// detect the same crossing within seconds and both call write — we
    /// only want one push on the iPhone.
    private let warningDebounceInterval: TimeInterval = 60

    init() {}

    func write(
        transition: SessionQuotaTransition,
        provider: UsageProvider,
        accountDisplayName: String?)
    {
        guard transition != .none else { return }

        let stateString = stateString(for: transition)
        let providerName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        let key = "\(provider.rawValue)|\(stateString)"
        let now = Date()

        if let lastWrite = self.lastWriteByKey[key],
           now.timeIntervalSince(lastWrite) < self.debounceInterval
        {
            self.logger.debug(
                "QuotaTransition write debounced: provider=\(provider.rawValue) state=\(stateString)")
            return
        }

        // Note: do NOT update `lastWriteByKey` here. Updating it before the async
        // CloudKit write completes would suppress legitimate retry attempts when the
        // initial write fails (network blip / auth glitch). The timestamp is only set
        // after the write succeeds, so failed writes don't start the debounce window.

        // No notification text is written to the record: state is encoded in the
        // zone (QuotaDepletedZone / QuotaRestoredZone) and iOS subscriptions carry
        // static `Push.QuotaDepleted.*` / `Push.QuotaRestored.*` localization keys
        // with `titleLocalizationArgs = ["providerName"]`, so each iPhone
        // substitutes the localized text for its own locale. The new
        // `accountEmail` field flows through for the v0.27.0 NSE rewrite path.

        Task { [providerName, stateString, accountDisplayName] in
            let result = await CloudSyncManager.shared.writeQuotaTransition(
                providerName: providerName,
                providerID: provider.rawValue,
                state: stateString,
                transitionAt: now,
                accountEmail: accountDisplayName)
            if result.succeeded {
                self.lastWriteByKey[key] = now
                self.logger.info(
                    "QuotaTransition record written: provider=\(provider.rawValue) state=\(stateString)")
            } else {
                self.logger.error(
                    "QuotaTransition record write failed: \(result.message ?? "unknown")")
            }
        }
    }

    func writeQuotaWarning(
        event: QuotaWarningEvent,
        provider: UsageProvider)
    {
        let providerName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        let windowString = event.windowPeriod?.rawValue ?? event.window.rawValue
        let key = "\(provider.rawValue)|\(windowString)|\(event.windowID ?? "")|\(event.threshold)"
        let now = Date()

        if let lastWrite = self.lastWarningWriteByKey[key],
           now.timeIntervalSince(lastWrite) < self.warningDebounceInterval
        {
            self.logger.debug(
                "QuotaWarning write debounced: provider=\(provider.rawValue) " +
                    "window=\(windowString) threshold=\(event.threshold)")
            return
        }

        let windowIdentity = event.windowID
        let windowDisplayLabel = event.windowDisplayLabel
        let threshold = event.threshold
        let accountDisplayName = event.accountDisplayName
        Task { [providerName, windowString, windowIdentity, windowDisplayLabel, threshold, accountDisplayName] in
            let result = await CloudSyncManager.shared.writeQuotaWarningTransition(
                providerName: providerName,
                providerID: provider.rawValue,
                window: windowString,
                threshold: threshold,
                transitionAt: now,
                accountEmail: accountDisplayName,
                windowIdentity: windowIdentity,
                windowDisplayLabel: windowDisplayLabel)
            if result.succeeded {
                self.lastWarningWriteByKey[key] = now
                self.logger.info(
                    "QuotaWarning record written: provider=\(provider.rawValue) " +
                        "window=\(windowString) threshold=\(threshold)")
            } else {
                self.logger.error(
                    "QuotaWarning record write failed: \(result.message ?? "unknown")")
            }
        }
    }
}

private func stateString(for transition: SessionQuotaTransition) -> String {
    switch transition {
    case .depleted: "depleted"
    case .restored: "restored"
    case .none: "none"
    }
}
