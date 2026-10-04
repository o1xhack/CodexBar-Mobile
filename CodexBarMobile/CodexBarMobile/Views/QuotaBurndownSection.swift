import Charts
import CodexBarSync
import SwiftUI

struct QuotaBurndownSection: View {
    private struct Lane: Identifiable {
        let id: Int
        let label: String
        let model: MobileQuotaBurndown
    }

    private let lanes: [Lane]
    private let providerID: String
    let tintColor: Color

    init(provider: ProviderUsageSnapshot, tintColor: Color, referenceDate: Date) {
        self.providerID = provider.providerID
        self.tintColor = tintColor
        self.lanes = MobileQuotaBurndown.resolvedLanes(for: provider, referenceDate: referenceDate).map {
            Lane(id: $0.lane.index, label: $0.lane.label, model: $0.model)
        }
    }

    var body: some View {
        if !self.lanes.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Quota pace")).font(.headline)
                ForEach(self.lanes) { lane in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ProviderDetailLocalization.localized(lane.label, providerID: self.providerID))
                            .font(.subheadline.bold())
                        Chart {
                            ForEach(Array(lane.model.ideal.enumerated()), id: \.offset) { _, sample in
                                LineMark(
                                    x: .value(String(localized: "Date"), sample.date),
                                    y: .value(String(localized: "Remaining"), sample.remainingPercent),
                                    series: .value(String(localized: "Series"), String(localized: "Even pace")))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(Color.secondary)
                            }
                            ForEach(Array(lane.model.samples.enumerated()), id: \.offset) { _, sample in
                                if lane.model.samples.count > 1 {
                                    LineMark(
                                        x: .value(String(localized: "Date"), sample.date),
                                        y: .value(String(localized: "Remaining"), sample.remainingPercent),
                                        series: .value(
                                            String(localized: "Series"),
                                            String(localized: "Observed remaining quota")))
                                        .foregroundStyle(self.tintColor)
                                }
                                PointMark(
                                    x: .value(String(localized: "Date"), sample.date),
                                    y: .value(String(localized: "Remaining"), sample.remainingPercent))
                                    .foregroundStyle(self.tintColor)
                            }
                        }
                        .chartXScale(domain: lane.model.start...lane.model.reset)
                        .chartYScale(domain: 0...100)
                        .chartXAxis {
                            AxisMarks(values: [0.2, 0.5, 0.8].map { fraction in
                                lane.model.start.addingTimeInterval(
                                    lane.model.reset.timeIntervalSince(lane.model.start) * fraction)
                            }) { value in
                                AxisGridLine()
                                AxisValueLabel(centered: false, anchor: .top) {
                                    if let date = value.as(Date.self) {
                                        if lane.model.reset.timeIntervalSince(lane.model.start) <= 12 * 3600 {
                                            Text(date, format: .dateTime.hour().minute())
                                        } else if lane.model.reset.timeIntervalSince(lane.model.start) <= 48 * 3600 {
                                            VStack(spacing: 2) {
                                                Text(date, format: .dateTime.month(.defaultDigits).day())
                                                Text(date, format: .dateTime.hour().minute())
                                            }
                                        } else {
                                            Text(date, format: .dateTime.month(.defaultDigits).day())
                                        }
                                    }
                                }
                            }
                        }
                        .chartLegend(.hidden)
                        .chartYAxis {
                            AxisMarks(values: [0, 50, 100]) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let percent = value.as(Int.self) { Text("\(percent)%") }
                                }
                            }
                        }
                        .frame(height: 150)
                        .accessibilityIdentifier("quota-burndown-lane-\(lane.id)")
                        .accessibilityLabel(Text(ProviderDetailLocalization.localized(
                            lane.label, providerID: self.providerID) + ": " + String(localized: "Quota pace")))
                        .accessibilityValue(Text(String(localized: "Observed remaining quota") + ": " +
                                (lane.model.samples.last?.remainingPercent.formatted(
                                    .number.precision(.fractionLength(0))) ?? "") + "%"))
                        HStack {
                            Label(String(localized: "Observed remaining quota"), systemImage: "circle.fill")
                                .foregroundStyle(self.tintColor)
                            Spacer()
                            Text(String(localized: "Even pace")).foregroundStyle(.secondary)
                        }.font(.caption2)
                        Text(String(localized: "Last observed") + ": " + lane.model.capturedAt.formatted(
                            date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(String(localized: "The dashed line is a steady-use guide, not a usage prediction."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quota-burndown-section")
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
