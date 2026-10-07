import Charts
import CodexBarSync
import Foundation
import SwiftUI

struct ProviderDetailsView: View {
    let providerID: String
    let sections: [SyncProviderDetailSection]
    let tintColor: Color

    static func visibleSections(
        providerID: String, sections: [SyncProviderDetailSection]) -> [SyncProviderDetailSection]
    {
        guard providerID == "claude" else { return sections }
        return sections.compactMap { section in
            let rows = section.rows.filter { $0.label != "Limit Reset Credits" }
            if rows.count == section.rows.count { return section }
            guard !rows.isEmpty || section.chart != nil else { return nil }
            return SyncProviderDetailSection(title: section.title, rows: rows, chart: section.chart)
        }
    }

    private var visibleSections: [SyncProviderDetailSection] {
        Self.visibleSections(providerID: self.providerID, sections: self.sections)
    }

    var body: some View {
        ForEach(Array(self.visibleSections.enumerated()), id: \.offset) { index, section in
            VStack(alignment: .leading, spacing: 12) {
                if let title = section.title {
                    Text(ProviderDetailLocalization.localized(title, providerID: self.providerID))
                        .font(.headline)
                }

                ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                    // Re-evaluate once a minute so an expiry observed by the Mac flips to Expired
                    // while the page stays open.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let presentation = ProviderDetailRowPresentation(
                            providerID: self.providerID,
                            row: row,
                            sectionTitle: section.title,
                            now: context.date)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(ProviderDetailLocalization.localized(
                                    row.label,
                                    providerID: self.providerID,
                                    context: ProviderDetailLocalization.rowContext(
                                        providerID: self.providerID,
                                        section: section,
                                        row: row,
                                        index: index)))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(presentation.value)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundStyle(presentation.isExpired ? HierarchicalShapeStyle
                                            .secondary : .primary)
                                    if let localizedSecondary = presentation.secondaryValue {
                                        Text(localizedSecondary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if let fraction = presentation.progressFraction {
                                ProgressView(value: fraction)
                                    .tint(self.tintColor)
                                    .accessibilityHidden(true)
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

    static func displayValue(
        _ value: String,
        providerID: String,
        rowLabel: String? = nil,
        locale: Locale = .current) -> String
    {
        ProviderDetailLocalization.localizedValue(
            value, providerID: providerID, rowLabel: rowLabel, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = self.section.title {
                Text(ProviderDetailLocalization.localized(title, providerID: self.providerID))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            ForEach(Array(self.section.rows.prefix(2).enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ProviderDetailLocalization.localized(
                        row.label,
                        providerID: self.providerID,
                        context: ProviderDetailLocalization.rowContext(
                            providerID: self.providerID,
                            section: self.section,
                            row: row,
                            index: index)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    // Same minute clock as the full details so a cached expiry flips while visible.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(ProviderDetailRowPresentation(
                            providerID: self.providerID,
                            row: row,
                            sectionTitle: self.section.title,
                            now: context.date).value)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
