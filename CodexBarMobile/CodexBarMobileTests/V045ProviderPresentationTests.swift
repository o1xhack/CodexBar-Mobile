import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("v0.45 provider presentation")
struct V045ProviderPresentationTests {
    @Test
    func `canonical generic window labels map to localized semantic keys`() {
        #expect(ProviderWindowLabel.localizationKey(for: "Daily") == "v045_window_daily")
        #expect(ProviderWindowLabel.localizationKey(for: "Weekly") == "v045_window_weekly")
        #expect(ProviderWindowLabel.localizationKey(for: "5-hour") == "alibaba_token_plan_window_5_hour")
        #expect(ProviderWindowLabel.localizationKey(for: "Credits") == "Credits")
        #expect(ProviderWindowLabel.localizationKey(for: "Monthly") == "v045_window_monthly")
        #expect(ProviderWindowLabel.localizationKey(for: "Additional") == "v045_window_additional")
        #expect(ProviderWindowLabel.localizationKey(for: "5 hour limit") == "v045_window_5_hour_limit")
        #expect(ProviderWindowLabel.localizationKey(for: "Daily Routines") == "v045_window_daily_routines")
        #expect(ProviderWindowLabel.localizationKey(for: "Web Sonnet") == "v045_window_web_sonnet")
        #expect(ProviderWindowLabel.localizationKey(for: "Provider custom lane") == nil)
        #expect(ProviderWindowLabel.localized("Provider custom lane", fallback: "Limit") == "Provider custom lane")
        #expect(ProviderWindowLabel.localized("Fable only", fallback: "Limit").contains("Fable"))
    }

    @Test
    func `sub2api mode and amount formatters preserve wallet semantics`() {
        #expect(Sub2APIUsageCard.modeLabel(kind: "wallet") == String(localized: "v045_mode_wallet"))
        #expect(Sub2APIUsageCard.modeLabel(kind: "subscription") == String(localized: "v045_mode_subscription"))
        #expect(ProviderAmountCard.title(kind: "balance") == String(localized: "v045_amount_balance_title"))
        #expect(ProviderAmountCard.title(kind: "spend") == String(localized: "v045_amount_spend_title"))
        #expect(!ProviderAmountCard.formattedAmount(12.5, currencyCode: "USD").isEmpty)
        #expect(ProviderAmountCard.localizedPeriod("Last 30 days") == String(localized: "v045_period_last_30_days"))
        #expect(ProviderAmountCard.localizedPeriod("Provider custom period") == "Provider custom period")
    }

    @Test(arguments: [
        (offline: true, dryRun: false, missingKeys: 0, status: "healthy", key: "v045_status_offline"),
        (offline: false, dryRun: true, missingKeys: 0, status: "healthy", key: "v045_status_dry_run"),
        (offline: false, dryRun: false, missingKeys: 1, status: "healthy", key: "v045_status_attention"),
        (offline: false, dryRun: false, missingKeys: 0, status: "healthy", key: "v045_status_active"),
    ])
    func `wayfinder status priority is stable`(
        input: (offline: Bool, dryRun: Bool, missingKeys: Int, status: String, key: String))
    {
        let usage = SyncWayfinderUsage(
            gatewayStatus: input.status,
            offline: input.offline,
            dryRun: input.dryRun,
            missingKeyCount: input.missingKeys,
            modelCount: 1,
            requests: 2,
            tokens: 3,
            realized: 1,
            baseline: 2,
            saved: 1,
            savedPercent: 50,
            priced: true,
            routes: [],
            averageDecisionMilliseconds: nil,
            updatedAt: .now)
        #expect(WayfinderUsageCard.statusLabel(for: usage) == String(localized: String.LocalizationValue(input.key)))
    }
}
