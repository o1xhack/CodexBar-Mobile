import CodexBarSync
import SwiftUI

/// Codex manual rate-limit reset credits added upstream in v0.37.0. Rendered
/// only when the Mac sync payload carries at least one available credit.
struct CodexResetCreditsCard: View {
    let resetCredits: SyncCodexResetCredits
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(self.tintColor)
                Text(String(localized: "Limit Reset Credits"))
                    .font(.headline)
                Spacer()
                Text(self.availableText)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(self.tintColor)
            }

            if let expiryText = self.expiryText {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(expiryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.tintColor.opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(self.tintColor.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("codex-reset-credits-card")
    }

    private var availableText: String {
        if self.resetCredits.availableCount == 1 {
            return String(localized: "1 manual reset available")
        }
        return String(
            format: String(localized: "%d manual resets available"),
            self.resetCredits.availableCount)
    }

    private var expiryText: String? {
        guard let nextExpiresAt = self.resetCredits.nextExpiresAt else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: nextExpiresAt, relativeTo: Date())
        return String(
            format: String(localized: "Next expires %@"),
            relative)
    }
}

struct UsageDataConfidenceNotice: View {
    let rawValue: String
    let tintColor: Color

    static func shouldRender(_ rawValue: String) -> Bool {
        rawValue != "exact" && rawValue != "unknown"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: self.iconName)
                .font(.subheadline)
                .foregroundStyle(self.noticeColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.noticeColor.opacity(0.10)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usage-data-confidence-notice")
    }

    private var title: String {
        switch self.rawValue {
        case "estimated":
            String(localized: "Estimated usage")
        case "percentOnly":
            String(localized: "Percentage-only usage")
        default:
            String(localized: "Usage confidence")
        }
    }

    private var subtitle: String {
        switch self.rawValue {
        case "estimated":
            String(localized: "Mac could not read exact usage, so this view may use an estimate.")
        case "percentOnly":
            String(localized: "Mac only received percentage data for this provider.")
        default:
            String(localized: "Mac reported limited confidence for this provider's usage data.")
        }
    }

    private var iconName: String {
        switch self.rawValue {
        case "estimated", "percentOnly":
            "exclamationmark.triangle.fill"
        default:
            "info.circle.fill"
        }
    }

    private var noticeColor: Color {
        switch self.rawValue {
        case "estimated", "percentOnly":
            .orange
        default:
            self.tintColor
        }
    }
}

#Preview("Codex reset credits") {
    VStack(spacing: 12) {
        CodexResetCreditsCard(
            resetCredits: SyncCodexResetCredits(
                availableCount: 2,
                nextExpiresAt: Date().addingTimeInterval(86_400),
                credits: [],
                updatedAt: Date()),
            tintColor: .purple)
        UsageDataConfidenceNotice(rawValue: "estimated", tintColor: .purple)
    }
    .padding()
}
