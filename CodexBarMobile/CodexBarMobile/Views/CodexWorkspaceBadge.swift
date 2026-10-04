import CodexBarSync
import SwiftUI

/// Pace row on the provider detail page (Research/065): reader-local linear
/// pace for every provider with a window of at least one day, plus the Codex
/// workspace name when the Mac synced one. Workspace data stays verbatim; pace
/// copy belongs to the iPhone locale.
struct ProviderPaceBadge: View {
    @Environment(\.locale) private var locale
    @State private var showsPaceExplanation = false
    let providerID: String
    var workspaceName: String?
    let pace: QuotaPace?
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = self.workspaceName, !name.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if let pace = self.pace {
                HStack(spacing: 6) {
                    Image(systemName: Self.iconName(for: pace))
                        .font(.caption)
                        .foregroundStyle(self.color(for: pace))
                    Text(verbatim: pace.summary(locale: self.locale))
                        .font(.caption.bold())
                        .foregroundStyle(self.color(for: pace))
                        .accessibilityIdentifier("\(self.providerID)-pace-summary")
                    Button {
                        self.showsPaceExplanation = true
                    } label: {
                        Image(systemName: "info.circle")
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "About the pace estimate"))
                    .accessibilityIdentifier("\(self.providerID)-pace-info")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08)))
        .alert(String(localized: "Pace estimate"), isPresented: self.$showsPaceExplanation) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(
                String(
                    // Keep the complete localization key available to string extraction.
                    // swiftlint:disable:next line_length
                    localized: "Points compare used quota with even use. Forecasts assume the latest Mac average rate continues. At least 1.5× means 50% faster use could still last until reset. This is an estimate, not a guarantee."))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(self.providerID)-workspace-badge")
    }

    static func iconName(for pace: QuotaPace) -> String {
        switch pace.trend {
        case .ahead: "arrow.up.circle.fill"
        case .behind: "arrow.down.circle.fill"
        case .onPace: "equal.circle.fill"
        }
    }

    private func color(for pace: QuotaPace) -> Color {
        switch pace.trend {
        case .ahead: .orange
        case .behind: .green
        case .onPace: self.tintColor
        }
    }
}

#Preview {
    let now = Date()
    let window = SyncRateWindow(
        usedPercent: 40,
        windowMinutes: 10080,
        resetsAt: now.addingTimeInterval(3 * 86400),
        resetDescription: nil)
    VStack(spacing: 12) {
        ProviderPaceBadge(
            providerID: "codex",
            workspaceName: "Acme Production",
            pace: QuotaPace(window: window, capturedAt: now, referenceDate: now),
            tintColor: .purple)
        ProviderPaceBadge(
            providerID: "claude",
            pace: QuotaPace(window: window, capturedAt: now, referenceDate: now),
            tintColor: .orange)
    }
    .padding()
}
