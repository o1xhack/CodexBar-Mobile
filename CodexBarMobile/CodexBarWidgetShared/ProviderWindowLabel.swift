import CodexBarSync
import Foundation

/// Rate-window label localization shared by the app and the widgets
/// (Research/071: the Quota pace window picker names windows the same way
/// as the provider cards).
enum ProviderWindowLabel {
    static func localizationKey(for label: String?) -> String? {
        switch label {
        case "5-hour": "5-hour"
        case "Credits": "Credits"
        case "Requests": "Requests"
        case "Tokens": "Tokens"
        case "Renews": "Renews"
        case "Total": "v052_window_total"
        case "Third Party": "v052_window_third_party"
        case "On-demand": "v052_window_on_demand"
        case "Daily": "v045_window_daily"
        case "Weekly": "v045_window_weekly"
        case "Monthly": "v045_window_monthly"
        case "Monthly Plan": "Monthly Plan"
        case "Fuel Pack": "Fuel Pack"
        case "Monthly Bobcoins": "v049_window_monthly_bobcoins"
        case "Additional": "v045_window_additional"
        case "5 hour limit": "v045_window_5_hour_limit"
        case "Daily limit": "v045_window_daily_limit"
        case "Daily free tokens": "Daily free tokens"
        case "Budget": "Budget"
        case "Secondary budget": "Secondary budget"
        case "7 day limit": "v045_window_7_day_limit"
        case "Designs": "v045_window_designs"
        case "Daily Routines": "v045_window_daily_routines"
        case "Web Sonnet": "v045_window_web_sonnet"
        case "Extra usage": "v045_window_extra_usage"
        default: nil
        }
    }

    static func localized(
        _ label: String?,
        fallback: String,
        providerID: String? = nil,
        period: SyncRateWindowPeriod? = nil,
        locale: Locale = .current) -> String
    {
        if providerID == "antigravity", let label {
            for (suffix, key) in [(" weekly", "Weekly"), (" 5-hour", "5-hour")] where label.hasSuffix(suffix) {
                let group = String(label.dropLast(suffix.count))
                return group + " · " + MobileLocalizedString.value(key, defaultValue: key, locale: locale)
            }
        }
        if providerID == "raycast", period == .monthly, label == nil || label == "Additional" {
            return MobileLocalizedString.value("Monthly", defaultValue: "Monthly", locale: locale)
        }
        if providerID == "aixy",
           let label,
           let localized = ProviderDetailLocalization.localizedAixyBudgetLabel(label, locale: locale)
        {
            return localized
        }
        if providerID == "xkiro", period == .daily {
            return MobileLocalizedString.value("Daily free tokens", defaultValue: "Daily free tokens", locale: locale)
        }
        if providerID == "aixy",
           let label,
           ["Budget", "Secondary budget"].contains(label),
           let periodLabel = self.localizedPeriodLabel(period, locale: locale)
        {
            let base = MobileLocalizedString.value(label, defaultValue: label, locale: locale)
            return "\(base) · \(periodLabel)"
        }
        if providerID == "kiro", label == "Overage" {
            return MobileLocalizedString.value("Overage", defaultValue: "Overage", locale: locale)
        }
        if providerID == "antigravity",
           let count = self.antigravityOfflineConversationCount(from: label)
        {
            if count == 1 {
                return MobileLocalizedString.value(
                    "v056_window_antigravity_offline_conversation_one",
                    defaultValue: "Offline · 1 conversation",
                    locale: locale)
            }
            let format = MobileLocalizedString.value(
                "v056_window_antigravity_offline_conversations_format",
                defaultValue: "Offline · %lld conversations",
                locale: locale)
            return String(format: format, locale: locale, arguments: [Int64(count)])
        }
        if let label,
           label.hasSuffix(" only"),
           label.count > " only".count
        {
            let model = String(label.dropLast(" only".count))
            return String(
                format: MobileLocalizedString.value(
                    "v045_window_model_only_format",
                    defaultValue: "%@ only",
                    locale: locale),
                locale: locale,
                arguments: [model])
        }
        guard let key = localizationKey(for: label) else {
            return label ?? fallback
        }
        switch key {
        case "5-hour":
            return MobileLocalizedString.value("5-hour", defaultValue: "5-hour", locale: locale)
        case "Credits":
            return MobileLocalizedString.value("Credits", defaultValue: "Credits", locale: locale)
        case "Requests":
            return MobileLocalizedString.value("Requests", defaultValue: "Requests", locale: locale)
        case "Tokens":
            return MobileLocalizedString.value("Tokens", defaultValue: "Tokens", locale: locale)
        case "Renews":
            return MobileLocalizedString.value("Renews", defaultValue: "Renews", locale: locale)
        case "v052_window_total":
            return MobileLocalizedString.value("v052_window_total", defaultValue: "Total", locale: locale)
        case "v052_window_third_party":
            return MobileLocalizedString.value(
                "v052_window_third_party",
                defaultValue: "Third Party",
                locale: locale)
        case "v052_window_on_demand":
            return MobileLocalizedString.value(
                "v052_window_on_demand",
                defaultValue: "On-demand",
                locale: locale)
        case "v045_window_daily":
            return MobileLocalizedString.value("v045_window_daily", defaultValue: "Daily", locale: locale)
        case "v045_window_weekly":
            return MobileLocalizedString.value("v045_window_weekly", defaultValue: "Weekly", locale: locale)
        case "v045_window_monthly":
            return MobileLocalizedString.value("v045_window_monthly", defaultValue: "Monthly", locale: locale)
        case "Monthly Plan":
            return MobileLocalizedString.value("Monthly Plan", defaultValue: "Monthly Plan", locale: locale)
        case "Fuel Pack":
            return MobileLocalizedString.value("Fuel Pack", defaultValue: "Fuel Pack", locale: locale)
        case "v049_window_monthly_bobcoins":
            return MobileLocalizedString.value(
                "v049_window_monthly_bobcoins",
                defaultValue: "Monthly Bobcoins",
                locale: locale)
        case "v045_window_additional":
            return MobileLocalizedString.value("v045_window_additional", defaultValue: "Additional", locale: locale)
        case "v045_window_5_hour_limit":
            return MobileLocalizedString.value(
                "v045_window_5_hour_limit",
                defaultValue: "5-hour limit",
                locale: locale)
        case "v045_window_daily_limit":
            return MobileLocalizedString.value(
                "v045_window_daily_limit",
                defaultValue: "Daily limit",
                locale: locale)
        case "v045_window_7_day_limit":
            return MobileLocalizedString.value(
                "v045_window_7_day_limit",
                defaultValue: "7-day limit",
                locale: locale)
        case "v045_window_designs":
            return MobileLocalizedString.value("v045_window_designs", defaultValue: "Designs", locale: locale)
        case "v045_window_daily_routines":
            return MobileLocalizedString.value(
                "v045_window_daily_routines",
                defaultValue: "Daily routines",
                locale: locale)
        case "v045_window_web_sonnet":
            return MobileLocalizedString.value(
                "v045_window_web_sonnet",
                defaultValue: "Web Sonnet",
                locale: locale)
        default:
            return MobileLocalizedString.value(
                "v045_window_extra_usage",
                defaultValue: "Extra usage",
                locale: locale)
        }
    }

    private static func antigravityOfflineConversationCount(from label: String?) -> Int? {
        let prefix = "Offline · "
        let singularSuffix = " conversation"
        let pluralSuffix = " conversations"
        guard let label, label.hasPrefix(prefix) else { return nil }

        let suffix: String
        if label.hasSuffix(pluralSuffix) {
            suffix = pluralSuffix
        } else if label.hasSuffix(singularSuffix) {
            suffix = singularSuffix
        } else {
            return nil
        }
        let countText = label.dropFirst(prefix.count).dropLast(suffix.count)
        guard let count = Int(countText), count > 0 else { return nil }
        guard (count == 1) == (suffix == singularSuffix) else { return nil }
        return count
    }

    private static func localizedPeriodLabel(_ period: SyncRateWindowPeriod?, locale: Locale) -> String? {
        let key: String
        switch period {
        case .session: key = "Session"
        case .daily: key = "Daily"
        case .weekly: key = "Weekly"
        case .monthly: key = "Monthly"
        case .lifetime: key = "Lifetime"
        case nil: return nil
        }
        return MobileLocalizedString.value(key, defaultValue: key, locale: locale)
    }
}
