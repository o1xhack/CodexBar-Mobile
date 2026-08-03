import Charts
import CodexBarSync
import SwiftUI

/// Per-model hourly token usage chart for z.ai. Mirrors the upstream
/// menu addition from PR #913 (v0.26.0) — stacked bars where each
/// segment is a model's contribution to that hour's total.
///
/// Populated only when `ProviderUsageSnapshot.zaiHourlyUsage` is
/// non-nil (Mac 0.26.2+ on the `zai` provider).
struct ZaiHourlyChart: View {
    let usage: SyncZaiHourlyUsage
    let tintColor: Color
    @State private var range: Range = .last24Hours

    private enum Range: String, CaseIterable, Identifiable {
        case last24Hours
        case last7Days
        case last30Days

        var id: String { self.rawValue }

        var title: String {
            switch self {
            case .last24Hours: String(localized: "24 hours")
            case .last7Days: String(localized: "7 days")
            case .last30Days: String(localized: "30 days")
            }
        }

        var dayCount: Int? {
            switch self {
            case .last24Hours: nil
            case .last7Days: 7
            case .last30Days: 30
            }
        }
    }

    /// Flattened bar points for SwiftUI Charts. Each point represents
    /// one model's tokens at one hour. A nil/zero token slot is
    /// skipped so the stacked bars don't render zero-height segments.
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let model: String
        let tokens: Int
    }

    private struct ChartData {
        let dates: [Date]
        let series: [SyncZaiModelSeries]
        let isDaily: Bool
    }

    private var chartData: ChartData {
        guard let dayCount = self.range.dayCount else {
            return ChartData(dates: self.usage.xTime, series: self.usage.modelSeries, isDaily: false)
        }
        let count = min(dayCount, self.usage.dailyXTime.count)
        let start = max(0, self.usage.dailyXTime.count - count)
        let dates = Array(self.usage.dailyXTime.dropFirst(start))
        let series = self.usage.dailyModelSeries.map { row in
            let tokens = start < row.tokens.count
                ? Array(row.tokens.dropFirst(start).prefix(count))
                : []
            return SyncZaiModelSeries(modelName: row.modelName, tokens: tokens)
        }
        return ChartData(dates: dates, series: series, isDaily: true)
    }

    private var points: [Point] {
        var out: [Point] = []
        for (index, date) in self.chartData.dates.enumerated() {
            for series in self.chartData.series {
                guard index < series.tokens.count else { continue }
                guard let value = series.tokens[index], value > 0 else { continue }
                out.append(Point(
                    id: "\(date.timeIntervalSince1970)-\(series.modelName)",
                    date: date,
                    model: series.modelName,
                    tokens: value))
            }
        }
        return out
    }

    private var totalTokens: Int {
        self.chartData.series.reduce(0) { acc, series in
            acc + series.tokens.compactMap(\.self).reduce(0, +)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(String(localized: "zai_hourly_chart_title", defaultValue: "Hourly token usage"))
                    .font(.headline)
                Text("(\(Self.formatTokens(self.totalTokens)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !self.usage.dailyXTime.isEmpty, !self.usage.dailyModelSeries.isEmpty {
                Picker("", selection: self.$range) {
                    ForEach(Range.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("zai-token-range-picker")
            }

            if self.points.isEmpty {
                Text(String(localized: "No model usage in this range"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                Chart(self.points) { point in
                    BarMark(
                        x: .value(
                            "Period",
                            point.date,
                            unit: self.chartData.isDaily ? .day : .hour),
                        y: .value("Tokens", point.tokens))
                        .foregroundStyle(by: .value("Model", point.model))
                }
                .chartForegroundStyleScale(domain: self.chartData.series.map(\.modelName))
                .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
                .chartXAxis {
                    if self.chartData.isDaily {
                        AxisMarks(values: .stride(by: .day, count: self.range == .last7Days ? 1 : 5)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    } else {
                        AxisMarks(values: .stride(by: .hour, count: 4)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(Self.formatTokens(v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zai-hourly-chart")
    }

    private static func formatTokens(_ count: Int) -> String {
        CostFormatting.tokens(count)
    }
}

#Preview {
    let now = Date()
    let cal = Calendar.current
    let xTime: [Date] = (0..<24).compactMap { offset in
        cal.date(byAdding: .hour, value: -23 + offset, to: now)
    }
    let series = [
        SyncZaiModelSeries(
            modelName: "glm-4.6",
            tokens: (0..<24).map { ($0 % 4 == 0) ? Int.random(in: 1000...6000) : nil }),
        SyncZaiModelSeries(
            modelName: "glm-4.6-plus",
            tokens: (0..<24).map { ($0 % 3 == 0) ? Int.random(in: 800...3000) : nil }),
    ]
    let dailyXTime: [Date] = (0..<30).compactMap { offset in
        cal.date(byAdding: .day, value: -29 + offset, to: now)
    }
    return ZaiHourlyChart(
        usage: SyncZaiHourlyUsage(
            xTime: xTime,
            modelSeries: series,
            dailyXTime: dailyXTime,
            dailyModelSeries: [
                SyncZaiModelSeries(
                    modelName: "glm-4.6",
                    tokens: (0..<30).map { _ in Int.random(in: 10000...60000) }),
            ]),
        tintColor: Color(red: 0.18, green: 0.44, blue: 0.50))
        .padding()
}
