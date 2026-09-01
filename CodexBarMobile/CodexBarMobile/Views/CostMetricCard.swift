import SwiftUI

struct CostMetricCard: View {
    let title: LocalizedStringResource
    let value: String
    let subtitle: String?
    var tintColor: Color = .secondary
    /// When true, an `*` is appended to the value to flag that the cost
    /// was computed via a Mac-side fallback resolver (model name not yet
    /// in the local pricing table). The footnote in `ProviderDetailView`
    /// explains the asterisk.
    var isEstimated: Bool = false
    /// Prefix the amount with ≥ when the producer has priced the rows scanned
    /// so far but has not yet established that the configured scan is complete.
    var isLowerBound: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                self.valueText(font: .title2.monospacedDigit())
                self.valueText(font: .headline.monospacedDigit())
            }
            .layoutPriority(1)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func valueText(font: Font) -> some View {
        let estimatedDisplay = self.isEstimated ? "\(self.value)*" : self.value
        let display = self.isLowerBound ? "≥\(estimatedDisplay)" : estimatedDisplay
        return Text(display)
            .font(font)
            .fontWeight(.bold)
            .foregroundStyle(self.tintColor)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHint(self.valueAccessibilityHint)
    }

    private var valueAccessibilityHint: Text {
        switch (self.isLowerBound, self.isEstimated) {
        case (true, true): Text("Lower bound and estimated")
        case (true, false): Text("Lower bound")
        case (false, true): Text("Estimated")
        case (false, false): Text("")
        }
    }
}

#Preview {
    HStack {
        CostMetricCard(title: "Today", value: "$1.42", subtitle: "12,340 tokens", tintColor: .orange)
        CostMetricCard(title: "30 Days", value: "$28.90", subtitle: "1.2M tokens", tintColor: .blue)
    }
    .padding()
}
