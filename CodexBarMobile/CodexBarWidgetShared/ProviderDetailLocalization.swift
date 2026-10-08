import CodexBarSync
import Foundation

enum ProviderDetailLocalization {
    enum Context: Equatable {
        case semantic
        case rowLabel(sectionTitle: String?)
    }

    /// Only labels emitted by bundled providers are localized. Custom plugin
    /// authors own their wording, so an arbitrary label must round-trip exactly.
    private static let firstPartyProviderIDs: Set<String> = [
        "aiand", "aixy", "amp", "atlascloud", "bifrost", "chutes", "claude", "clawrouter",
        "clinepass", "coderabbit", "codex", "copilot", "cursor", "deepgram", "deepseek",
        "devpass", "elevenlabs", "fireworks", "gitkraken", "groq", "helmcode",
        "huggingface", "hyper", "ibmbob", "kiro", "langdock", "litellm", "lithosai", "llmman", "llmproxy",
        "mimo", "minimax", "moonshot", "muse", "museai", "nous", "openai", "openrouter",
        "perplexity", "pi", "poe", "raycast", "replicate", "sakana", "sub2api", "typesafe",
        "v0", "vercel", "wayfinder", "workbuddy", "xai", "xkiro", "zai", "zoommate",
    ]

    /// Stable semantic labels currently emitted by bundled provider detail
    /// payloads. Dynamic account, team, model and plugin-provided labels are
    /// intentionally absent and therefore remain verbatim.
    private static let semanticLabels: Set<String> = [
        "30d cash", "30d credits", "30d spend", "30d tokens", "7d spend",
        "API credits", "API key", "API key budget", "API key limit", "API key remaining", "API key used",
        "Aixy key", "Applicable budgets", "Daily allowance", "Daily reset", "Free tokens",
        "Account balance", "Active keys", "Actual cost", "Additional credits", "Agent hours", "All-time key usage",
        "API key (all time)", "Audio", "Available", "Avg decision",
        "Available balance", "Balance", "Billable usage", "Billing", "Billing history",
        "Billing remaining", "Billing summary",
        "Billing type", "Bobcoin usage", "Bonus credits left", "Budget ledger", "Budgets",
        "Cache read", "Cache-hit input", "Cache-miss input", "Cached input", "Chart range",
        "Characters", "Context files", "Context used", "Cost items", "Credit", "Credit balance",
        "Credit history", "Credit quota", "Credits", "Credits left", "Credits total", "Credits used",
        "Cycle remaining", "Cycle used", "Daemon", "Daily", "Hard", "Lifetime", "Monthly", "Monitor",
        "Daily credits", "Daily points", "Daily spend", "Daily tokens", "Detailed usage", "DevPass credits",
        "Exhausted keys", "Extra usage", "Gateway", "GPU time remaining", "GPU time used",
        "Granted", "Gross inference usage", "Included inference amount", "Individual credits",
        "Inference Providers", "Key", "Key spend", "Key spending limit",
        "Hypercredits", "Kiro responses", "Last 30 days", "Last 30 days (partial)", "Lifetime spend",
        "Left", "Loaded", "Loaded models", "Manage", "Models", "Monthly credit limit",
        "Monthly grant", "Muse Code subscription", "On-demand balance", "Other models", "Output", "Overage",
        "Overage cost", "Overage credits left", "Overage usage", "Overages", "Pace",
        "Observed", "Organization", "Period", "Period resets", "Personal", "Plan", "Points", "Prepaid balance",
        "Premium weekly",
        "Professional voices", "Project", "Promotional", "Providers", "Prompts", "Purchased", "Quota",
        "Quota details", "Quota services", "Rate limit", "Rate-limit remaining", "Recurring",
        "Included limits", "Remaining", "Renews", "Request quota", "Requests", "Reset", "Reset window", "Reserved", "Session", "Shared",
        "Rest of organization", "Reviews", "Rollover credits", "Routed", "Saved", "Scope", "Shared pool",
        "Spend history", "Spending limit", "Spent", "Spent this month", "Stored", "Subscription",
        "Subscription credits", "Team credits", "Top-up credits",
        "Team", "Total usable", "Total usage", "TTS characters", "This month", "This week",
        "Today", "Today cash", "Today spend", "Today tokens", "Token quota", "Tools",
        "Tokens", "Tokens remaining", "Tokens used today", "Top method", "Top model", "Total added", "Usage",
        "Usage billing",
        "Usage summary",
        "Used", "User", "v0 API", "Version", "Voice slots", "Weekly", "Weekly usage", "Your shared usage",
        "ZeroGPU", "5 hours",
        "credits", "points", "tokens",
        // Upstream v0.71-v0.72: WorkBuddy, LithosAI, muse.ai and Claude cloud credits.
        "Account status", "Additional tokens", "Cloud credits", "Payment card", "Spend",
        "This month (UTC)", "Today (UTC)", "Total",
    ]

    /// These sections deliberately use provider-returned account, team, model,
    /// service, or cost-item names as row labels. Even if a customer-created
    /// name happens to equal one of our semantic strings, it must stay verbatim.
    private static let verbatimRowSections: [String: Set<String>] = [
        "bifrost": ["Budgets", "Models"],
        "claude": ["Cost items"],
        "groq": ["Models"],
        "ibmbob": ["Bobcoin usage"],
        "llmproxy": ["Providers"],
        "llmman": ["Loaded models"],
        "minimax": ["Quota services"],
    ]

    static func localized(
        _ label: String,
        providerID: String,
        context: Context = .semantic,
        locale: Locale = .current) -> String
    {
        if providerID == "aixy",
           let budgetLabel = self.localizedAixyBudgetLabel(label, locale: locale)
        {
            return budgetLabel
        }
        if providerID == "typesafe", case .rowLabel(sectionTitle: "Billing") = context,
           label.hasPrefix("Spent ("), label.hasSuffix(")")
        {
            let cycle = String(label.dropFirst("Spent (".count).dropLast())
            if !cycle.isEmpty {
                return self.localizedFormat("Spent (%@)", argument: cycle, locale: locale)
            }
        }
        guard self.firstPartyProviderIDs.contains(providerID),
              self.semanticLabels.contains(label),
              self.shouldLocalize(context: context, providerID: providerID)
        else {
            return label
        }
        return MobileLocalizedString.value(label, defaultValue: label, locale: locale)
    }

    static func rowContext(
        providerID: String,
        section: SyncProviderDetailSection,
        row: SyncProviderDetailSection.Row,
        index: Int) -> Context
    {
        // Bifrost appends this one synthetic count after five provider-supplied model names.
        // A real model named "Other models" in those first five must stay verbatim.
        if providerID == "bifrost", section.title == "Models", section.rows.count == 6,
           index == 5, row.label == "Other models", Int(row.value) != nil
        {
            return .semantic
        }
        return .rowLabel(sectionTitle: section.title)
    }

    /// Localizes only stable value fragments emitted by bundled providers. Dynamic values and
    /// custom-plugin content remain verbatim, and the canonical CloudKit payload stays unchanged.
    static func localizedValue(
        _ value: String,
        providerID: String,
        rowLabel: String? = nil,
        sectionTitle: String? = nil,
        locale: Locale = .current) -> String
    {
        switch providerID {
        case "aixy":
            if rowLabel == nil,
               let localized = self.localizedAixyResetDescription(value, locale: locale)
            {
                return localized
            }
            return self.localizedAixyBudgetValue(
                value, rowLabel: rowLabel, sectionTitle: sectionTitle, locale: locale) ?? value
        case "xkiro":
            if ["No cap reported", "Unavailable"].contains(value) {
                return MobileLocalizedString.value(value, defaultValue: value, locale: locale)
            }
        case "raycast":
            if rowLabel == nil,
               let localized = self.localizedRaycastCreditReset(value, locale: locale)
            {
                return localized
            }
        case "openrouter":
            return self.localizedOpenRouterValue(value, locale: locale) ?? value
        case "zai":
            return self.localizedZAIBalanceBreakdown(value, locale: locale) ?? value
        case "bifrost", "clinepass", "devpass", "elevenlabs", "gitkraken", "helmcode",
             "huggingface", "hyper", "llmman", "llmproxy", "muse", "nous", "perplexity",
             "typesafe", "v0":
            return self.localizedBundledPluginValue(
                value, providerID: providerID, rowLabel: rowLabel, locale: locale)
        case "lithosai":
            // "Added" here is a card state, not the generic "Added" counter label.
            let keys = [
                "Active": "lithosai_value_active",
                "Added": "lithosai_value_card_added",
                "Not added": "lithosai_value_card_not_added",
                "On hold": "lithosai_value_on_hold",
                "Browser session": "Browser session",
                "Unavailable": "Unavailable",
            ]
            guard let key = keys[value] else { return value }
            return MobileLocalizedString.value(key, defaultValue: value, locale: locale)
        case "workbuddy":
            return self.localizedCreditsLeft(value, locale: locale) ?? value
        case "langdock":
            guard value == "No included usage limits available" else { return value }
            return MobileLocalizedString.value("langdock_value_no_included_limits", defaultValue: value, locale: locale)
        case "museai":
            return self.localizedAmountLeft(value, locale: locale) ?? value
        case "kiro":
            break
        default:
            return value
        }

        if value == "Enabled" || value == "Disabled" {
            return MobileLocalizedString.value(value, defaultValue: value, locale: locale)
        }

        let fragments = value.components(separatedBy: " · ")
        if fragments.count == 2,
           let cap = self.localizedKiroCap(fragments[0], locale: locale),
           let expiry = self.localizedKiroExpiry(fragments[1], locale: locale)
        {
            return "\(cap) · \(expiry)"
        }

        if let cap = self.localizedKiroCap(value, locale: locale) {
            return cap
        }

        if let expiry = self.localizedKiroExpiry(value, locale: locale) {
            return expiry
        }

        let creditsSuffix = " credits"
        if value.hasSuffix(creditsSuffix) {
            let amount = String(value.dropLast(creditsSuffix.count))
            let credits = MobileLocalizedString.value(
                "credits",
                defaultValue: "credits",
                locale: locale)
            return "\(amount) \(credits)"
        }

        return value
    }

    static func localizedAixyBudgetLabel(_ value: String, locale: Locale = .current) -> String? {
        let fragments = value.components(separatedBy: " · ")
        guard fragments.count == 4,
              ["Organization", "Project", "Team", "User", "Key"].contains(fragments[0]),
              ["Daily", "Weekly", "Monthly", "Lifetime"].contains(fragments[1]),
              ["Shared", "Personal"].contains(fragments[2]),
              ["Hard", "Monitor"].contains(fragments[3])
        else {
            return nil
        }
        return fragments.map { self.localized($0, providerID: "aixy", locale: locale) }
            .joined(separator: " · ")
    }

    private static func localizedAixyBudgetValue(
        _ value: String,
        rowLabel: String?,
        sectionTitle: String?,
        locale: Locale) -> String?
    {
        guard sectionTitle == "Applicable budgets",
              self.localizedAixyBudgetLabel(rowLabel ?? "", locale: locale) != nil
        else {
            return nil
        }
        if value == "Unavailable" {
            return MobileLocalizedString.value(value, defaultValue: value, locale: locale)
        }
        let remaining = value.components(separatedBy: " / ")
        if remaining.count == 2, remaining[1].hasSuffix(" remaining") {
            let limit = String(remaining[1].dropLast(" remaining".count))
            guard self.isAixyAmount(remaining[0]), self.isAixyAmount(limit) else { return nil }
            return self.localizedFormat("%@ / %@ remaining", arguments: [remaining[0], limit], locale: locale)
        }
        let fragments = value.components(separatedBy: " · ")
        if fragments.count == 2,
           fragments[0].hasSuffix(" spent"),
           fragments[1].hasSuffix(" reserved")
        {
            let spent = String(fragments[0].dropLast(" spent".count))
            let reserved = String(fragments[1].dropLast(" reserved".count))
            guard self.isAixyAmount(spent), self.isAixyAmount(reserved) else { return nil }
            return self.localizedFormat("%@ spent · %@ reserved", arguments: [spent, reserved], locale: locale)
        }
        if value.hasSuffix(" spent") {
            let spent = String(value.dropLast(" spent".count))
            guard self.isAixyAmount(spent) else { return nil }
            return self.localizedFormat("%@ spent", arguments: [spent], locale: locale)
        }
        return nil
    }

    private static func localizedAixyResetDescription(_ value: String, locale: Locale) -> String? {
        guard let separator = value.range(of: " · ", options: .backwards) else { return nil }
        let label = String(value[..<separator.lowerBound])
        let amount = String(value[separator.upperBound...])
        guard let localizedLabel = self.localizedAixyBudgetLabel(label, locale: locale) else { return nil }
        if amount == "Unavailable" {
            return "\(localizedLabel) · " +
                MobileLocalizedString.value(amount, defaultValue: amount, locale: locale)
        }
        guard amount.hasSuffix(" remaining") else { return nil }
        let numericAmount = String(amount.dropLast(" remaining".count))
        guard self.isAixyAmount(numericAmount) else { return nil }
        let remaining = self.localizedFormat("%@ remaining", arguments: [numericAmount], locale: locale)
        return "\(localizedLabel) · \(remaining)"
    }

    private static func isAixyAmount(_ value: String) -> Bool {
        !value.isEmpty && value.contains(where: \.isNumber) &&
            value.allSatisfy { $0.isNumber || "$€£¥,.- ".contains($0) }
    }

    private static func localizedRaycastCreditReset(_ value: String, locale: Locale) -> String? {
        let parts = value.components(separatedBy: " / ")
        guard parts.count == 2,
              parts[1].hasSuffix(" credits left")
        else {
            return nil
        }
        let total = String(parts[1].dropLast(" credits left".count))
        guard self.isAixyAmount(parts[0]), self.isAixyAmount(total) else { return nil }
        return self.localizedFormat("%@ / %@ credits left", arguments: [parts[0], total], locale: locale)
    }

    private static func localizedFormat(_ key: String, arguments: [String], locale: Locale) -> String {
        let format = MobileLocalizedString.value(key, defaultValue: key, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func localizedBundledPluginValue(
        _ value: String,
        providerID: String,
        rowLabel: String?,
        locale: Locale) -> String
    {
        let v0QuotaRow = providerID == "v0" &&
            (rowLabel == "Billing remaining" || rowLabel == "Rate-limit remaining")
        if self.isFixedBundledPluginValue(value, providerID: providerID, rowLabel: rowLabel) {
            return MobileLocalizedString.value(value, defaultValue: value, locale: locale)
        }
        if providerID == "typesafe", rowLabel == nil, value.hasPrefix("Balance: ") {
            let amount = String(value.dropFirst("Balance: ".count))
            if !amount.isEmpty {
                return self.localizedFormat("Balance: %@", argument: amount, locale: locale)
            }
        }
        if providerID == "typesafe", rowLabel == "Credit",
           let localized = self.localizedTypeSafeCreditValue(value, locale: locale)
        {
            return localized
        }
        if providerID == "gitkraken" {
            let fragments = value.components(separatedBy: " · ")
            if fragments.count == 2 {
                return fragments.map {
                    self.localizedBundledPluginValue(
                        $0, providerID: providerID, rowLabel: rowLabel, locale: locale)
                }.joined(separator: " · ")
            }
        }
        if providerID == "perplexity" || providerID == "gitkraken" {
            for suffix in [" credits used", " credits"] where value.hasSuffix(suffix) {
                let amount = String(value.dropLast(suffix.count))
                let unit = String(suffix.dropFirst())
                return "\(amount) \(MobileLocalizedString.value(unit, defaultValue: unit, locale: locale))"
            }
        }
        if v0QuotaRow, let cap = self.localizedKiroCap(value, locale: locale) {
            return cap
        }
        if v0QuotaRow, value.hasPrefix("limit ") {
            let amount = String(value.dropFirst("limit ".count))
            if !amount.isEmpty, amount.allSatisfy({ $0.isNumber || ",. ".contains($0) }) {
                return self.localizedFormat("limit %@", argument: amount, locale: locale)
            }
        }
        if providerID == "bifrost" {
            let periods: Set = ["Hourly", "Daily", "Weekly", "Monthly", "Quarterly", "Yearly"]
            if periods.contains(value) {
                return MobileLocalizedString.value(value, defaultValue: value, locale: locale)
            }
        }
        return value
    }

    private static func isFixedBundledPluginValue(
        _ value: String,
        providerID: String,
        rowLabel: String?) -> Bool
    {
        switch providerID {
        case "perplexity": value == "Unavailable"
        case "v0": ((rowLabel == "Billing remaining" || rowLabel == "Rate-limit remaining") &&
                value == "Unavailable") || (rowLabel == nil && value == "API key")
        case "gitkraken": value == "No allowance" || value == "Unlimited"
        case "muse": (rowLabel == "Quota" && value == "Not included in this login response") ||
            (rowLabel == nil && value == "Muse login")
        case "devpass": rowLabel == nil && value == "Pay as you go"
        case "clinepass": rowLabel == nil && value == "API key"
        case "hyper": rowLabel == nil && (value == "API key" || value == "Browser session")
        case "llmman": rowLabel == nil && (value == "API key" || value == "Local daemon")
        case "nous": rowLabel == nil && value == "Subscription"
        case "helmcode": rowLabel == nil && value == "Dashboard session"
        default: false
        }
    }

    private static func localizedTypeSafeCreditValue(_ value: String, locale: Locale) -> String? {
        let expiryParts = value.components(separatedBy: ", expires ")
        guard expiryParts.count == 2 else { return nil }
        let amountParts = expiryParts[0].components(separatedBy: " of ")
        guard amountParts.count == 2,
              amountParts.allSatisfy({ !$0.isEmpty }),
              !expiryParts[1].isEmpty
        else {
            return nil
        }
        let format = MobileLocalizedString.value(
            "%@ of %@, expires %@",
            defaultValue: "%@ of %@, expires %@",
            locale: locale)
        return String(format: format, locale: locale, arguments: [
            amountParts[0], amountParts[1], expiryParts[1],
        ])
    }

    private static func localizedOpenRouterValue(_ value: String, locale: Locale) -> String? {
        let stableValues: Set = [
            "Management API key not configured",
            "Management API key required",
            "No limit configured",
            "Request failed",
            "Request timed out",
            "Response was invalid",
            "Response was unavailable",
            "Spending cap, not balance",
            "Unavailable right now",
        ]
        if stableValues.contains(value) {
            return MobileLocalizedString.value(value, defaultValue: value, locale: locale)
        }

        let httpPrefix = "Request returned HTTP "
        if value.hasPrefix(httpPrefix) {
            let status = String(value.dropFirst(httpPrefix.count))
            guard Int(status) != nil else { return nil }
            return self.localizedFormat(
                "Request returned HTTP %@",
                argument: status,
                locale: locale)
        }

        let requestMarker = " requests / "
        guard let markerRange = value.range(of: requestMarker) else { return nil }
        let count = String(value[..<markerRange.lowerBound])
        let interval = String(value[markerRange.upperBound...])
        guard Int(count) != nil, !interval.isEmpty else { return nil }
        let format = MobileLocalizedString.value(
            "%@ requests / %@",
            defaultValue: "%@ requests / %@",
            locale: locale)
        return String(format: format, locale: locale, arguments: [count, interval])
    }

    private static func localizedZAIBalanceBreakdown(_ value: String, locale: Locale) -> String? {
        let prefixes = [
            (prefix: "recharged ", format: "recharged %@"),
            (prefix: "granted ", format: "granted %@"),
            (prefix: "spent ", format: "spent %@"),
        ]
        let fragments = value.components(separatedBy: " · ")
        guard !fragments.isEmpty else { return nil }

        var localized: [String] = []
        for fragment in fragments {
            guard let match = prefixes.first(where: { fragment.hasPrefix($0.prefix) }) else { return nil }
            let amount = String(fragment.dropFirst(match.prefix.count))
            guard !amount.isEmpty else { return nil }
            localized.append(self.localizedFormat(match.format, argument: amount, locale: locale))
        }
        return localized.joined(separator: " · ")
    }

    /// WorkBuddy: "1,200 / 5,000 credits left".
    private static func localizedCreditsLeft(_ value: String, locale: Locale) -> String? {
        let suffix = " credits left"
        guard value.hasSuffix(suffix) else { return nil }
        let parts = value.dropLast(suffix.count).components(separatedBy: " / ")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return self.localizedFormat("%@ / %@ credits left", arguments: parts, locale: locale)
    }

    /// muse.ai: "2.8B tokens left" or a dollar top-up fallback such as "$4.20 left".
    private static func localizedAmountLeft(_ value: String, locale: Locale) -> String? {
        for (suffix, key) in [(" tokens left", "%@ tokens left"), (" left", "%@ left")] where value.hasSuffix(suffix) {
            let amount = String(value.dropLast(suffix.count))
            guard !amount.isEmpty, !amount.contains(" ") else { return nil }
            return self.localizedFormat(key, argument: amount, locale: locale)
        }
        return nil
    }

    private static func localizedFormat(_ key: String, argument: String, locale: Locale) -> String {
        let format = MobileLocalizedString.value(key, defaultValue: key, locale: locale)
        return String(format: format, locale: locale, arguments: [argument])
    }

    private static func localizedKiroCap(_ value: String, locale: Locale) -> String? {
        let capPrefix = "of "
        guard value.hasPrefix(capPrefix) else { return nil }
        let format = MobileLocalizedString.value(
            "of %@",
            defaultValue: "of %@",
            locale: locale)
        return String(
            format: format,
            locale: locale,
            arguments: [String(value.dropFirst(capPrefix.count))])
    }

    private static func localizedKiroExpiry(_ value: String, locale: Locale) -> String? {
        let expiryPrefix = "expires in "
        guard value.hasPrefix(expiryPrefix), value.hasSuffix("d") else { return nil }
        let daysText = value.dropFirst(expiryPrefix.count).dropLast()
        guard let days = Int(daysText) else { return nil }

        if days <= 0 {
            return MobileLocalizedString.value(
                "kiro_bonus_expired",
                defaultValue: "expired",
                locale: locale)
        }
        if days == 1 {
            return MobileLocalizedString.value(
                "kiro_bonus_expiring_one_day",
                defaultValue: "expires in 1 day",
                locale: locale)
        }
        let format = MobileLocalizedString.value(
            "kiro_bonus_expiring_days_format",
            defaultValue: "expires in %d days",
            locale: locale)
        return String(format: format, locale: locale, days)
    }

    private static func shouldLocalize(context: Context, providerID: String) -> Bool {
        switch context {
        case .semantic:
            true
        case let .rowLabel(sectionTitle):
            !self.verbatimRowSections[providerID, default: []].contains(sectionTitle ?? "")
        }
    }
}
