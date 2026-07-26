import CodexBarSync
import SwiftUI

enum ProviderWindowLabel {
    static func localizationKey(for label: String?) -> String? {
        switch label {
        case "5-hour": "5-hour"
        case "Credits": "Credits"
        case "Daily": "v045_window_daily"
        case "Weekly": "v045_window_weekly"
        case "Monthly": "v045_window_monthly"
        case "Additional": "v045_window_additional"
        case "5 hour limit": "v045_window_5_hour_limit"
        case "Daily limit": "v045_window_daily_limit"
        case "7 day limit": "v045_window_7_day_limit"
        case "Designs": "v045_window_designs"
        case "Daily Routines": "v045_window_daily_routines"
        case "Web Sonnet": "v045_window_web_sonnet"
        case "Extra usage": "v045_window_extra_usage"
        default: nil
        }
    }

    static func localized(_ label: String?, fallback: String) -> String {
        if let label,
           label.hasSuffix(" only"),
           label.count > " only".count
        {
            let model = String(label.dropLast(" only".count))
            return String(
                format: String(localized: "v045_window_model_only_format", defaultValue: "%@ only"),
                model)
        }
        guard let key = localizationKey(for: label) else {
            return label ?? fallback
        }
        switch key {
        case "5-hour":
            return String(localized: "5-hour")
        case "Credits":
            return String(localized: "Credits", defaultValue: "Credits")
        case "v045_window_daily":
            return String(localized: "v045_window_daily", defaultValue: "Daily")
        case "v045_window_weekly":
            return String(localized: "v045_window_weekly", defaultValue: "Weekly")
        case "v045_window_monthly":
            return String(localized: "v045_window_monthly", defaultValue: "Monthly")
        case "v045_window_additional":
            return String(localized: "v045_window_additional", defaultValue: "Additional")
        case "v045_window_5_hour_limit":
            return String(localized: "v045_window_5_hour_limit", defaultValue: "5-hour limit")
        case "v045_window_daily_limit":
            return String(localized: "v045_window_daily_limit", defaultValue: "Daily limit")
        case "v045_window_7_day_limit":
            return String(localized: "v045_window_7_day_limit", defaultValue: "7-day limit")
        case "v045_window_designs":
            return String(localized: "v045_window_designs", defaultValue: "Designs")
        case "v045_window_daily_routines":
            return String(localized: "v045_window_daily_routines", defaultValue: "Daily routines")
        case "v045_window_web_sonnet":
            return String(localized: "v045_window_web_sonnet", defaultValue: "Web Sonnet")
        default:
            return String(localized: "v045_window_extra_usage", defaultValue: "Extra usage")
        }
    }
}

struct ProviderAmountCard: View {
    let amount: SyncProviderAmount
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.title(kind: self.amount.kind))
                    .font(.headline)
                Spacer()
                Text(Self.formattedAmount(self.amount.amount, currencyCode: self.amount.currencyCode))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(self.tintColor)
            }
            HStack(spacing: 8) {
                if let period = amount.period, !period.isEmpty {
                    Text(Self.localizedPeriod(period))
                }
                if self.amount.isEstimated {
                    Text(String(localized: "v045_estimated_label", defaultValue: "Estimated"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("provider-amount-card")
    }

    static func title(kind: String) -> String {
        kind == "balance"
            ? String(localized: "v045_amount_balance_title", defaultValue: "Balance")
            : String(localized: "v045_amount_spend_title", defaultValue: "API spend")
    }

    static func formattedAmount(_ value: Double, currencyCode: String) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    static func localizedPeriod(_ period: String) -> String {
        switch period {
        case "Last 30 days":
            String(localized: "v045_period_last_30_days", defaultValue: "Last 30 days")
        case "Last 30 days (partial)":
            String(localized: "v045_period_last_30_days_partial", defaultValue: "Last 30 days (partial)")
        case "Neuralwatt prepaid balance":
            String(localized: "v045_period_neuralwatt_prepaid", defaultValue: "Neuralwatt prepaid balance")
        case "ZenMux PAYG balance":
            String(localized: "v045_period_zenmux_payg", defaultValue: "ZenMux PAYG balance")
        case "Prepaid balance":
            String(localized: "v045_period_prepaid_balance", defaultValue: "Prepaid balance")
        default:
            period
        }
    }
}

struct Sub2APIUsageCard: View {
    let usage: SyncSub2APIUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "v045_account_summary_title", defaultValue: "Account summary"))
                    .font(.headline)
                Spacer()
                Text(Self.modeLabel(kind: self.usage.kind))
                    .font(.caption.bold())
                    .foregroundStyle(self.tintColor)
            }

            if let balance = usage.balance {
                self.metric(
                    label: String(localized: "v045_balance_label", defaultValue: "Balance"),
                    value: Self.currency(balance, unit: self.usage.unit))
            }
            if let today = usage.today {
                self.metric(
                    label: String(localized: "v045_today_label", defaultValue: "Today"),
                    value: Self.totalsText(today))
            }
            if let total = usage.total {
                self.metric(
                    label: String(localized: "v045_total_label", defaultValue: "Total"),
                    value: Self.totalsText(total))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sub2api-usage-card")
    }

    static func modeLabel(kind: String) -> String {
        switch kind {
        case "subscription": String(localized: "v045_mode_subscription", defaultValue: "Subscription")
        case "keyQuota": String(localized: "v045_mode_key_quota", defaultValue: "Key quota")
        case "wallet": String(localized: "v045_mode_wallet", defaultValue: "Wallet")
        default: String(localized: "v045_mode_account", defaultValue: "Account")
        }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
        }
    }

    private static func totalsText(_ totals: SyncSub2APIUsage.Totals) -> String {
        String(
            format: String(
                localized: "v045_usage_totals_format",
                defaultValue: "%1$lld requests · %2$@ tokens · %3$@"),
            totals.requests,
            self.compactNumber(totals.totalTokens),
            self.currency(totals.actualCostUSD, unit: "USD"))
    }

    static func currency(_ value: Double, unit: String) -> String {
        if unit.uppercased() == "USD" {
            return value.formatted(.currency(code: "USD"))
        }
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    fileprivate static func compactNumber(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }
}

struct WayfinderUsageCard: View {
    let usage: SyncWayfinderUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "v045_routing_summary_title", defaultValue: "Routing summary"))
                    .font(.headline)
                Spacer()
                Text(Self.statusLabel(for: self.usage))
                    .font(.caption.bold())
                    .foregroundStyle(self.tintColor)
            }

            HStack(spacing: 12) {
                self.metric(
                    label: String(localized: "v045_models_label", defaultValue: "Models"),
                    value: self.usage.modelCount.formatted())
                self.metric(
                    label: String(localized: "v045_requests_label", defaultValue: "Requests"),
                    value: self.usage.requests.formatted(.number.notation(.compactName)))
                self.metric(
                    label: String(localized: "v045_tokens_label", defaultValue: "Tokens"),
                    value: self.usage.tokens.formatted(.number.notation(.compactName)))
            }

            if self.usage.saved > 0 {
                self.metric(
                    label: String(localized: "v045_saved_label", defaultValue: "Saved"),
                    value: self.savedText)
            }
            if let milliseconds = usage.averageDecisionMilliseconds {
                self.metric(
                    label: String(localized: "v045_average_decision_label", defaultValue: "Average decision"),
                    value: String(format: "%.1f ms", milliseconds))
            }

            if !self.usage.routes.isEmpty {
                Divider()
                Text(String(localized: "v045_routes_label", defaultValue: "Routes"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(Array(self.usage.routes.prefix(5).enumerated()), id: \.offset) { _, route in
                    HStack {
                        Text(route.name).font(.subheadline)
                        Spacer()
                        Text(String(
                            format: String(
                                localized: "v045_route_totals_format",
                                defaultValue: "%1$lld requests · %2$@ tokens"),
                            route.requests,
                            Sub2APIUsageCard.compactNumber(route.tokens)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wayfinder-usage-card")
    }

    static func statusLabel(for usage: SyncWayfinderUsage) -> String {
        if usage.offline {
            return String(localized: "v045_status_offline", defaultValue: "Offline")
        }
        if usage.dryRun {
            return String(localized: "v045_status_dry_run", defaultValue: "Dry run")
        }
        if usage.missingKeyCount > 0 || usage.gatewayStatus == "degraded" {
            return String(localized: "v045_status_attention", defaultValue: "Attention")
        }
        return String(localized: "v045_status_active", defaultValue: "Active")
    }

    private var savedText: String {
        let percentage = self.usage.savedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%"
        guard self.usage.priced else { return percentage }
        return self.usage.saved.formatted(.currency(code: "USD")) + " · " + percentage
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
