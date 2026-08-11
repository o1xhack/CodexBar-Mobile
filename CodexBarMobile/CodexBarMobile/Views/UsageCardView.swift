import CodexBarSync
import SwiftUI

struct UsageCardView: View {
    let label: String
    let window: SyncRateWindow
    var tintColor: Color = .blue
    var percentageAccessibilityIdentifier: String?
    /// Quota warning thresholds expressed as **remaining percent**, as
    /// resolved by Mac's `SettingsStore` per (provider, window). `nil`
    /// → fall back to `SyncQuotaWarningConfig.macDefaults` so a sync
    /// gap with an old Mac doesn't leave the bar marker-less. `[]`
    /// → user explicitly cleared all thresholds; render no markers.
    /// See Research/020 §R7.4 for the 16-cell device matrix proof.
    var quotaWarningThresholds: [Int]?
    /// Whether to render warning markers at all. Mirrors Mac's per
    /// (provider, window) enable flag.
    var quotaWarningsEnabled: Bool = true
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode
            .remaining.rawValue
    /// Global "hide warning markers" toggle (iOS 1.7.0, mirrors upstream
    /// PR #918). The quota-warning notification is unaffected — only the
    /// tick-mark on the usage bar is hidden when true.
    @AppStorage(MobileSettingsKeys.hideQuotaWarningMarkers) private var hideQuotaWarningMarkers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                Text(self.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if self.shouldShowWarningIcon {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(self.usageColor)
                        .accessibilityLabel(Text("Quota warning"))
                        .accessibilityIdentifier("usage.warning.icon")
                }
                Spacer()
                self.percentageLabel
                    .modifier(PercentageAccessibilityIdentifierModifier(
                        identifier: self.percentageAccessibilityIdentifier))
            }

            // Progress bar with threshold marker overlay
            // `scaleEffect(y: 2)` makes SwiftUI's 1pt-tall native ProgressView
            // render as ~2pt — large enough to be visible and satisfy a
            // minimum-touch-target hint on iOS but still compact enough to
            // fit inside the card's 12pt vertical spacing. Removing this
            // makes the bar near-invisible on Retina displays.
            ProgressView(value: self.window.usageKnown
                ? self.displayMode.progressFraction(for: self.window)
                : 0)
                .tint(self.usageColor)
                .opacity(self.window.usageKnown ? 1 : 0.35)
                .scaleEffect(y: 2, anchor: .center)
                .overlay(alignment: .leading) {
                    if self.window.usageKnown,
                       self.quotaWarningsEnabled,
                       !self.hideQuotaWarningMarkers,
                       !self.markerUsedPercents.isEmpty
                    {
                        GeometryReader { geo in
                            ForEach(self.markerUsedPercents, id: \.self) { usedPercent in
                                Rectangle()
                                    .fill(Color.secondary)
                                    .frame(width: 1.5, height: 8)
                                    .offset(
                                        x: geo.size.width * CGFloat(usedPercent) / 100.0 - 0.75,
                                        y: -3)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }

            // Reset info
            if let resetsAt = self.window.resetsAt {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("\(String(localized: "Resets")) \(resetsAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else if let description = self.window.resetDescription {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text(description)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var percentageLabel: some View {
        if self.window.usageKnown {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(self.displayMode.percentageValueText(for: self.window))
                        .font(.title2.monospacedDigit())
                        .fontWeight(.bold)

                    Text(self.displayMode.percentSuffix)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .foregroundColor(self.usageColor)
                .fixedSize(horizontal: true, vertical: false)

                Text(self.displayMode.percentageText(for: self.window))
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(self.usageColor)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)
        } else {
            Text(String(localized: "Usage unavailable"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var displayMode: UsagePercentDisplayMode {
        self.showRemainingUsage ? .remaining : .used
    }

    /// Marker x-positions on the bar, in **used percent** units (0…100).
    /// Mac's `QuotaWarningConfig` stores **remaining percent** (e.g.
    /// `[50, 20]` = "warn at 50% remaining" + "warn at 20% remaining"),
    /// which on a used-percent bar maps to positions `100 - threshold`
    /// (= 50% and 80% used). Defensive clamp + dedupe + sort lets us
    /// render even if the wire payload contains out-of-range values
    /// from a future Mac config schema.
    private var markerUsedPercents: [Int] {
        let raw: [Int] = if let configured = self.quotaWarningThresholds {
            configured
        } else {
            SyncQuotaWarningConfig.macDefaults
        }
        let mapped = raw
            .map { 100 - max(0, min(100, $0)) }
            .filter { $0 > 0 && $0 < 100 }
        return Array(Set(mapped)).sorted()
    }

    /// True once the user crosses the most critical warning threshold —
    /// matches Mac's notification firing semantics where the lowest
    /// remaining-percent threshold is the highest used-percent position.
    private var shouldShowWarningIcon: Bool {
        guard self.window.usageKnown else { return false }
        guard self.quotaWarningsEnabled else { return false }
        guard let maxMarker = self.markerUsedPercents.max() else { return false }
        return Int(self.window.usedPercent.rounded()) >= maxMarker
    }

    private var usageColor: Color {
        // 70% (orange warning) / 90% (red critical) thresholds chosen to
        // match the industry-standard quota-warning bands users see on
        // AWS / Azure / GCP dashboards and Apple's built-in Storage UI.
        // These are also the same thresholds used by `BudgetProgressView`;
        // keeping them in sync means every quota-like display across the
        // app turns the same color at the same percentage, so "orange"
        // always reads as "getting close" and "red" as "critical".
        // Changing here requires changing BudgetProgressView symmetrically.
        if self.window.usedPercent >= 90 {
            .red
        } else if self.window.usedPercent >= 70 {
            .orange
        } else {
            self.tintColor
        }
    }
}

private struct PercentageAccessibilityIdentifierModifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview("Low Usage") {
    UsageCardView(
        label: "Session (5h)",
        window: SyncRateWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3600 * 3),
            resetDescription: nil),
        tintColor: Color(red: 0.82, green: 0.55, blue: 0.28),
        quotaWarningThresholds: [50, 20])
        .padding()
}

#Preview("High Usage") {
    UsageCardView(
        label: "Weekly",
        window: SyncRateWindow(
            usedPercent: 92,
            windowMinutes: 10080,
            resetsAt: Date().addingTimeInterval(3600 * 24),
            resetDescription: nil),
        tintColor: .purple,
        quotaWarningThresholds: [50, 20])
        .padding()
}

#Preview("Custom Thresholds") {
    UsageCardView(
        label: "Session (5h)",
        window: SyncRateWindow(
            usedPercent: 65,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3600 * 3),
            resetDescription: nil),
        tintColor: .indigo,
        quotaWarningThresholds: [70, 40, 10])
        .padding()
}
