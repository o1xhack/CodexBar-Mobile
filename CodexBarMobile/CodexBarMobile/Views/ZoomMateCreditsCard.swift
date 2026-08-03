import Charts
import CodexBarSync
import SwiftUI

/// ZoomMate's plan credits do not map cleanly to a USD budget. This card keeps
/// the provider's native credit unit, cycle state, overage, and daily history.
struct ZoomMateCreditsCard: View {
    let credits: SyncZoomMateCredits
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(String(localized: "ZoomMate credits"), systemImage: "video.badge.checkmark")
                    .font(.headline)
                Spacer()
                if self.credits.isUnlimited == true {
                    Text(String(localized: "Unlimited"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(self.tintColor.opacity(0.14), in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.number(self.credits.remainingCredits))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(self.tintColor)
                Text(String(localized: "credits remaining"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                self.metric(String(localized: "Used"), value: self.credits.usedCredits)
                if let cap = self.credits.budgetCap {
                    self.metric(String(localized: "Limit"), value: cap)
                }
                if let today = self.credits.todayCreditsUsed {
                    self.metric(String(localized: "Today"), value: today)
                }
            }

            if let overage = self.credits.overageCredits, overage > 0 {
                Label(
                    "\(self.number(overage)) \(String(localized: "credits over the limit"))",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
            }

            if let end = self.credits.cycleEndAt {
                Label {
                    Text("\(String(localized: "Renews")) \(end.formatted(date: .abbreviated, time: .omitted))")
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !self.credits.daily.isEmpty {
                Divider()
                Text(String(localized: "Credit history"))
                    .font(.subheadline.weight(.semibold))
                Chart(self.credits.daily, id: \.dayKey) { point in
                    BarMark(
                        x: .value("Day", Self.date(from: point.dayKey) ?? .distantPast, unit: .day),
                        y: .value("Credits", point.creditsUsed))
                        .foregroundStyle(self.tintColor.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zoommate-credits-card")
    }

    private func metric(_ label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(self.number(value))
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func date(from dayKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey)
    }
}
