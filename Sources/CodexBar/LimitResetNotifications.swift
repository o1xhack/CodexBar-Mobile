import CodexBarCore
import Foundation

enum LimitResetNotificationLogic {
    static func notificationCopy(
        providerName: String,
        window: QuotaWarningWindow,
        accountDisplayName: String?) -> (title: String, body: String)
    {
        let title = L("limit_reset_notification_title", providerName, window.localizedNotificationDisplayName)
        let body = if let accountDisplayName {
            L("limit_reset_notification_body_with_account", accountDisplayName)
        } else {
            L("limit_reset_notification_body")
        }
        return (title, body)
    }
}

@MainActor
extension UsageStore {
    struct LimitResetNotificationReceipt: Codable, Equatable {
        let resetBoundary: Date?
    }

    enum LimitResetNotice {
        case restored
        case reset
    }

    func prepareLimitResetNotification(
        state: inout LimitResetDetectorState,
        previousState: LimitResetDetectorState?,
        observation: LimitResetObservation,
        resetConfirmed: Bool,
        restored: Bool) -> LimitResetNotice?
    {
        let newUsageCycle = state.wasAboveThreshold && previousState?.wasAboveThreshold == false
        let restoredAlreadyCovered = state.notificationReceipt.map { receipt in
            !Self.limitResetBoundaryAdvanced(
                previous: receipt.resetBoundary,
                current: observation.resetBoundary,
                requiresPreviousBoundary: true)
        } ?? false
        let restoredNoticeEnabled = restored && self.settings
            .sessionQuotaNotificationsEnabled && !restoredAlreadyCovered
        // Re-arm cycle coverage without forgetting known reset boundaries. Depletion also starts a new
        // restored-notice episode, even if the prior recovery never reached the reset detector's low threshold.
        if newUsageCycle || SessionQuotaNotificationLogic.isDepleted(100 - observation.usedPercent) {
            state.notificationReceipt = nil
        }
        if let boundary = observation.resetBoundary {
            let advanced = Self.limitResetBoundaryAdvanced(previous: state.lastNotifiedResetBoundary, current: boundary)
            if let receipt = state.notificationReceipt, receipt.resetBoundary == nil {
                // Resolve the window of an already announced cycle when its reset metadata returns.
                if advanced { state.lastNotifiedResetBoundary = boundary }
                state.notificationReceipt = LimitResetNotificationReceipt(resetBoundary: boundary)
                return nil
            }
            guard advanced || (restoredNoticeEnabled && state.notificationReceipt == nil) else {
                if resetConfirmed || restored {
                    state.notificationReceipt = LimitResetNotificationReceipt(resetBoundary: boundary)
                }
                return nil
            }
        } else if state.notificationReceipt != nil {
            return nil
        }
        let notice: LimitResetNotice
        if restoredNoticeEnabled {
            notice = .restored
        } else if resetConfirmed, self.settings.limitResetNotificationsEnabled {
            notice = .reset
        } else {
            return nil
        }
        // Reserved before persistence and delivery; retries and restarts cannot announce this boundary twice.
        state.notificationReceipt = LimitResetNotificationReceipt(resetBoundary: observation.resetBoundary)
        if let boundary = observation.resetBoundary {
            state.lastNotifiedResetBoundary = max(state.lastNotifiedResetBoundary ?? boundary, boundary)
        }
        return notice
    }

    func postLimitResetNotificationIfNeeded(
        provider: UsageProvider,
        window: QuotaWarningWindow,
        accountLabel: String?)
    {
        guard self.settings.limitResetNotificationsEnabled else { return }
        let trimmedLabel = accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountDisplayName = self.settings.hidePersonalInfo || trimmedLabel?.isEmpty != false
            ? nil
            : trimmedLabel
        self.sessionQuotaNotifier.postLimitReset(
            provider: provider,
            window: window,
            accountDisplayName: accountDisplayName,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return self.settings.limitResetNotificationsEnabled
                    && (accountDisplayName == nil || !self.settings.hidePersonalInfo)
            })
    }
}
