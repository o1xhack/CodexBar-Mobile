import CodexBarSync
import Foundation

extension ProviderUsageSnapshot {
    /// Resolves the per-window quota warning config that `UsageCardView`
    /// should render for the given rate-window index.
    ///
    /// Mac stores warning thresholds in session/weekly lanes. Windows with
    /// session/daily periods use session settings; weekly/monthly/lifetime
    /// periods use weekly settings. Period-less payloads keep the historical
    /// primary/secondary mapping. Aixy and Claude's supported named windows
    /// also receive markers; other extras do not have warning events.
    ///
    /// When `self.quotaWarnings` is nil (old Mac pre-0.25.2, or the
    /// provider didn't map to a known `UsageProvider` enum case on
    /// Mac), we still return Mac's documented defaults so the user
    /// sees a marker — matches the 16-cell device matrix proof in
    /// Research/020 §R7.4 (G3 + G7).
    func quotaWarning(
        forWindowIndex index: Int,
        windowID: String? = nil,
        period: SyncRateWindowPeriod? = nil) -> (thresholds: [Int]?, enabled: Bool)
    {
        let isNotifiableExtra = self.providerID == "aixy" ||
            (self.providerID == "claude" &&
                (windowID?.hasPrefix("claude-weekly-scoped-") == true || windowID == "claude-routines"))
        guard index < 2 || isNotifiableExtra else { return (nil, false) }

        let isSessionLane: Bool = switch period {
        case .session, .daily: true
        case .weekly, .monthly, .lifetime: false
        case nil: index == 0
        }
        guard let cfg = self.quotaWarnings else {
            return (SyncQuotaWarningConfig.macDefaults, true)
        }
        return isSessionLane
            ? (cfg.resolvedSessionThresholds(), cfg.resolvedSessionEnabled())
            : (cfg.resolvedWeeklyThresholds(), cfg.resolvedWeeklyEnabled())
    }
}
