import CodexBarSync
import Foundation

enum MobileSettingsKeys {
    static let usageCostChartStyle = "usageCostChartStyle"
    static let dashboardCostChartStyle = "dashboardCostChartStyle"
    static let hidePersonalInfo = "hidePersonalInfo"
    static let openCostByDefault = "openCostByDefault"
    static let usagePercentDisplayMode = "usagePercentDisplayMode"
    static let showRemainingUsage = "showRemainingUsage"
    // iOS 1.7.0 — mirrors upstream v0.26.0 / v0.26.1 settings.
    /// When `true`, the warning tick-marks on each usage bar are
    /// suppressed (the quota warning notification still fires — only
    /// the visual marker is hidden). Mirrors the Mac toggle added in
    /// upstream PR #918.
    static let hideQuotaWarningMarkers = "hideQuotaWarningMarkers"
    /// When `true`, the Settings / About page shows a "Provider
    /// changelogs" section linking to upstream provider release notes
    /// (Codex CLI, Claude Code, Gemini CLI). Mirrors upstream PR #929.
    static let showProviderChangelogLinks = "showProviderChangelogLinks"

    // iOS 1.9.0 + Round 2 (research doc 024) — Cost Window Ledger.
    /// When `true`, `SwiftDataBridge.upsertProvider` also writes each
    /// per-day cost point into the `DailyCostPoint` ledger (via
    /// `CostLedgerService.upsertFromSnapshot`). Defaults to `true` so Cost
    /// uses the local daily ledger when available, with the existing blob path
    /// as fallback. Reader (Round 3 / P3) honors the same key when deciding
    /// whether to read from the ledger vs. the existing blob path.
    static let cwlEnabled = "cwlEnabled"
    /// CWL cost window in days (Round 6 / P4b). The Cost dashboard, when CWL
    /// is on, aggregates the ledger over this trailing window. Picker offers
    /// 7 / 30 / 90 / 365; default 90.
    static let cwlWindowDays = "cwlWindowDays"
    /// Timestamp written when the user explicitly clears local cost history.
    /// Default-on blob migration only seeds provider blobs newer than this
    /// value, so a normal Cost-page read cannot immediately undo the clear.
    static let cwlBlobSeedClearedAt = "cwlBlobSeedClearedAt"
}

enum MobileSettingsDefaults {
    static let cwlEnabled = true
    static let cwlWindowDays = 90
}

enum UsagePercentDisplayMode: String, CaseIterable, Identifiable {
    case used
    case remaining

    var id: String {
        self.rawValue
    }

    var percentSuffix: String {
        switch self {
        case .used:
            String(localized: "used")
        case .remaining:
            String(localized: "left")
        }
    }

    func displayedPercent(for window: SyncRateWindow) -> Double {
        switch self {
        case .used:
            window.usedPercent
        case .remaining:
            window.remainingPercent
        }
    }

    func progressFraction(for window: SyncRateWindow) -> Double {
        min(max(self.displayedPercent(for: window) / 100, 0), 1)
    }

    func percentageValueText(for window: SyncRateWindow) -> String {
        let displayedPercent = self.displayedPercent(for: window)
        if displayedPercent > 0, displayedPercent < 1 {
            return "<1%"
        }
        let roundedValue = Int(displayedPercent.rounded())
        return "\(roundedValue)%"
    }

    func percentageText(for window: SyncRateWindow) -> String {
        "\(self.percentageValueText(for: window)) \(self.percentSuffix)"
    }
}
