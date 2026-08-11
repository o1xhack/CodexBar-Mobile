import Charts
import CodexBarSync
import SwiftUI

struct ProviderDetailsView: View {
    let sections: [SyncProviderDetailSection]
    let tintColor: Color

    var body: some View {
        ForEach(Array(self.sections.enumerated()), id: \.offset) { index, section in
            VStack(alignment: .leading, spacing: 12) {
                if let title = section.title {
                    Text(title)
                        .font(.headline)
                }

                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
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
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    ProviderDetailsChart(chart: chart, tintColor: self.tintColor)
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
    let chart: SyncProviderDetailSection.Chart
    let tintColor: Color

    var body: some View {
        Chart(self.chart.points, id: \.label) { point in
            switch self.chart.kind {
            case .bars:
                BarMark(
                    x: .value(String(localized: "Date"), point.label),
                    y: .value(self.chart.unit ?? String(localized: "Usage"), point.value))
                    .foregroundStyle(self.tintColor.gradient)
            case .line:
                LineMark(
                    x: .value(String(localized: "Date"), point.label),
                    y: .value(self.chart.unit ?? String(localized: "Usage"), point.value))
                    .foregroundStyle(self.tintColor)
                    .interpolationMethod(.monotone)
                PointMark(
                    x: .value(String(localized: "Date"), point.label),
                    y: .value(self.chart.unit ?? String(localized: "Usage"), point.value))
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
    let section: SyncProviderDetailSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = self.section.title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            ForEach(Array(self.section.rows.prefix(2).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
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
