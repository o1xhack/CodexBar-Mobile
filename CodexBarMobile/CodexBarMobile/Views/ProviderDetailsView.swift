import Charts
import CodexBarSync
import Foundation
import SwiftUI

enum ProviderDetailLocalization {
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
        "API credits", "API key", "API key budget", "API key remaining", "API key used",
        "Actual cost", "Agent hours", "Audio", "Available", "Avg decision",
        "Balance", "Billing history", "Billing summary", "Bobcoin usage", "Budget ledger",
        "Cache read", "Cache-hit input", "Cache-miss input", "Cached input", "Chart range",
        "Cost items", "Credit history", "Credit quota", "Credits", "Credits used",
        "Daily credits", "Daily points", "Daily spend", "Daily tokens", "Detailed usage",
        "Extra usage", "Gateway", "Granted", "Individual credits", "Key spend",
        "Last 30 days", "Last 30 days (partial)", "Models", "Output", "Pace",
        "Period", "Points", "Prepaid balance", "Quota details", "Quota services",
        "Rate limit", "Remaining", "Request quota", "Requests", "Reset window",
        "Routed", "Saved", "TTS characters", "This month", "This week",
        "Today", "Today cash", "Today spend", "Today tokens", "Token quota",
        "Tokens", "Top method", "Top model", "Total added", "Usage", "Usage summary",
        "Used", "credits", "points", "tokens",
    ]

    static func localized(
        _ label: String,
        providerID: String,
        locale: Locale = .current) -> String
    {
        guard self.firstPartyProviderIDs.contains(providerID),
              self.semanticLabels.contains(label)
        else {
            return label
        }
        return MobileLocalizedString.value(label, defaultValue: label, locale: locale)
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
                        Text(ProviderDetailLocalization.localized(row.label, providerID: self.providerID))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.value)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            if let secondaryValue = row.secondaryValue {
                                Text(secondaryValue)
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
                    Text(ProviderDetailLocalization.localized(row.label, providerID: self.providerID))
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
