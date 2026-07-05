import CodexBarSync
import SwiftUI

/// CrossModel wallet balance plus day/week/month usage.
///
/// CrossModel upstream exposes wallet/spend metrics but no generic quota
/// window, so this typed card is the primary iOS detail UI for the provider.
struct CrossModelUsageCard: View {
    let usage: SyncCrossModelUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "crossmodel_usage_title", defaultValue: "CrossModel usage"))
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "crossmodel_balance_label", defaultValue: "Balance"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.currencyString(self.usage.balance, currency: self.usage.currency))
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(self.tintColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if self.usage.uncollected > 0 {
                Text(String(
                    format: String(localized: "crossmodel_uncollected_format", defaultValue: "Uncollected: %@"),
                    Self.currencyString(self.usage.uncollected, currency: self.usage.currency)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 8) {
                self.windowRow(
                    label: String(localized: "crossmodel_daily_label", defaultValue: "Daily"),
                    window: self.usage.daily)
                self.windowRow(
                    label: String(localized: "crossmodel_weekly_label", defaultValue: "Weekly"),
                    window: self.usage.weekly)
                self.windowRow(
                    label: String(localized: "crossmodel_monthly_label", defaultValue: "Monthly"),
                    window: self.usage.monthly)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("crossmodel-usage-card")
    }

    @ViewBuilder
    private func windowRow(label: String, window: SyncCrossModelUsage.Window?) -> some View {
        if let window {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.currencyString(window.cost, currency: self.usage.currency))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(Self.requestTokenSummary(window))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    static func requestTokenSummary(_ window: SyncCrossModelUsage.Window) -> String {
        String(
            format: String(localized: "crossmodel_requests_tokens_format", defaultValue: "%d requests · %@ tokens"),
            window.requestCount,
            Self.compactInt(window.totalTokens))
    }

    static func currencyString(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, currency)
    }

    static func compactInt(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

#Preview {
    CrossModelUsageCard(
        usage: SyncCrossModelUsage(
            currency: "USD",
            balance: 8.06,
            uncollected: 0.42,
            daily: .init(
                cost: 0.27,
                promptTokens: 5_200,
                completionTokens: 7_267,
                totalTokens: 12_467,
                requestCount: 84,
                successCount: 83),
            weekly: .init(
                cost: 1.92,
                promptTokens: 41_000,
                completionTokens: 52_000,
                totalTokens: 93_000,
                requestCount: 526,
                successCount: 520),
            monthly: .init(
                cost: 5.37,
                promptTokens: 110_000,
                completionTokens: 150_000,
                totalTokens: 260_000,
                requestCount: 3_166,
                successCount: 3_140),
            updatedAt: Date()),
        tintColor: Color(red: 0.0, green: 0.62, blue: 0.72))
        .padding()
}
