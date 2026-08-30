import Charts
import CodexBarSync
import Foundation
import SwiftUI

enum ProviderDetailLocalization {
    enum Context: Equatable {
        case semantic
        case rowLabel(sectionTitle: String?)
    }

    /// Only labels emitted by bundled providers are localized. Custom plugin
    /// authors own their wording, so an arbitrary label must round-trip exactly.
    private static let firstPartyProviderIDs: Set<String> = [
        "amp", "claude", "clawrouter", "copilot", "cursor", "deepgram",
        "deepseek", "fireworks", "groq", "ibmbob", "kiro", "mimo",
        "minimax", "openai", "openrouter", "poe", "sakana", "sub2api",
        "wayfinder", "xai", "zai", "zoommate",
    ]

    /// Stable semantic labels currently emitted by bundled provider detail
    /// payloads. Dynamic account, team, model and plugin-provided labels are
    /// intentionally absent and therefore remain verbatim.
    private static let semanticLabels: Set<String> = [
        "30d cash", "30d credits", "30d spend", "30d tokens", "7d spend",
        "API credits", "API key", "API key budget", "API key limit", "API key remaining", "API key used",
        "Account balance", "Actual cost", "Agent hours", "Audio", "Available", "Avg decision",
        "Balance", "Billing history", "Billing summary", "Bobcoin usage", "Bonus credits left", "Budget ledger",
        "Cache read", "Cache-hit input", "Cache-miss input", "Cached input", "Chart range",
        "Context files", "Context used", "Cost items", "Credit history", "Credit quota",
        "Credits", "Credits left", "Credits total", "Credits used",
        "Daily credits", "Daily points", "Daily spend", "Daily tokens", "Detailed usage",
        "Extra usage", "Gateway", "Granted", "Individual credits", "Key spend",
        "Kiro responses", "Last 30 days", "Last 30 days (partial)", "Manage", "Models",
        "Output", "Overage", "Overage cost", "Overage credits left", "Overage usage", "Overages", "Pace",
        "Period", "Plan", "Points", "Prepaid balance", "Prompts", "Quota details", "Quota services",
        "Rate limit", "Remaining", "Request quota", "Requests", "Reset window",
        "Routed", "Saved", "Spend history", "TTS characters", "This month", "This week",
        "Today", "Today cash", "Today spend", "Today tokens", "Token quota", "Tools",
        "Tokens", "Top method", "Top model", "Total added", "Usage", "Usage summary",
        "Used", "credits", "points", "tokens",
    ]

    /// These sections deliberately use provider-returned account, team, model,
    /// service, or cost-item names as row labels. Even if a customer-created
    /// name happens to equal one of our semantic strings, it must stay verbatim.
    private static let verbatimRowSections: [String: Set<String>] = [
        "claude": ["Cost items"],
        "groq": ["Models"],
        "ibmbob": ["Bobcoin usage"],
        "minimax": ["Quota services"],
    ]

    static func localized(
        _ label: String,
        providerID: String,
        context: Context = .semantic,
        locale: Locale = .current) -> String
    {
        guard self.firstPartyProviderIDs.contains(providerID),
              self.semanticLabels.contains(label),
              self.shouldLocalize(context: context, providerID: providerID)
        else {
            return label
        }
        return MobileLocalizedString.value(label, defaultValue: label, locale: locale)
    }

    /// Localizes only stable value fragments emitted by bundled providers. Dynamic values and
    /// custom-plugin content remain verbatim, and the canonical CloudKit payload stays unchanged.
    static func localizedValue(
        _ value: String,
        providerID: String,
        locale: Locale = .current) -> String
    {
        switch providerID {
        case "openrouter":
            return self.localizedOpenRouterValue(value, locale: locale) ?? value
        case "zai":
            return self.localizedZAIBalanceBreakdown(value, locale: locale) ?? value
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

    private static func localizedOpenRouterValue(_ value: String, locale: Locale) -> String? {
        let stableValues: Set<String> = [
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

struct ProviderDetailsView: View {
    let providerID: String
    let sections: [SyncProviderDetailSection]
    let tintColor: Color

    var body: some View {
        ForEach(Array(self.sections.enumerated()), id: \.offset) { index, section in
            VStack(alignment: .leading, spacing: 12) {
                if let title = section.title {
                    Text(ProviderDetailLocalization.localized(title, providerID: self.providerID))
                        .font(.headline)
                }

                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(ProviderDetailLocalization.localized(
                            row.label,
                            providerID: self.providerID,
                            context: .rowLabel(sectionTitle: section.title)))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ProviderDetailLocalization.localizedValue(
                                row.value,
                                providerID: self.providerID))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            if let secondaryValue = row.secondaryValue {
                                Text(ProviderDetailLocalization.localizedValue(
                                    secondaryValue,
                                    providerID: self.providerID))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let chart = section.chart, !chart.points.isEmpty {
                    if let title = chart.title {
                        Text(ProviderDetailLocalization.localized(title, providerID: self.providerID))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    ProviderDetailsChart(
                        providerID: self.providerID,
                        chart: chart,
                        tintColor: self.tintColor)
                        .frame(height: 150)
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("provider-details-section-\(index)")
        }
    }
}

private struct ProviderDetailsChart: View {
    let providerID: String
    let chart: SyncProviderDetailSection.Chart
    let tintColor: Color

    private var localizedUnit: String {
        ProviderDetailLocalization.localized(
            self.chart.unit ?? "Usage",
            providerID: self.providerID)
    }

    var body: some View {
        Chart(self.chart.points, id: \.label) { point in
            switch self.chart.kind {
            case .bars:
                BarMark(
                    x: .value(String(localized: "Date"), point.label),
                    y: .value(self.localizedUnit, point.value))
                    .foregroundStyle(self.tintColor.gradient)
            case .line:
                LineMark(
                    x: .value(String(localized: "Date"), point.label),
                    y: .value(self.localizedUnit, point.value))
                    .foregroundStyle(self.tintColor)
                    .interpolationMethod(.monotone)
                PointMark(
                    x: .value(String(localized: "Date"), point.label),
                    y: .value(self.localizedUnit, point.value))
                    .foregroundStyle(self.tintColor)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(5, self.chart.points.count)))
        }
    }
}

struct ProviderDetailsTeaserView: View {
    let providerID: String
    let section: SyncProviderDetailSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = self.section.title {
                Text(ProviderDetailLocalization.localized(title, providerID: self.providerID))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            ForEach(Array(self.section.rows.prefix(2).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ProviderDetailLocalization.localized(
                        row.label,
                        providerID: self.providerID,
                        context: .rowLabel(sectionTitle: self.section.title)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
