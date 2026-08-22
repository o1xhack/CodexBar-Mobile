import CodexBarSync
import SwiftUI

struct ProviderUsageView: View {
    let provider: ProviderUsageSnapshot
    /// 1-based ordinal among cards sharing this same `providerID`. `nil`
    /// when this is the only card for its providerID — subtitle then stays
    /// in its pre-T5 single-card form.
    ///
    /// **Note (Phase G):** since the Usage list now groups by providerID
    /// (one row per `ProviderAccountGroup`), this is always passed `nil`
    /// from the list. The field is kept for the few legacy call sites
    /// (RawProviderDetailView previews, tests) that still drive a single
    /// snapshot through the card.
    var duplicateOrdinal: Int?
    /// **Phase G:** when the row represents a multi-account group, this
    /// is the count (≥ 2). The card renders a small "· N" badge after
    /// the provider name so the user knows "tap → see N tabs". `nil`
    /// for single-account groups (suppress badge).
    var accountCount: Int?
    /// Optional linkage candidate when this card is part of a
    /// cross-version-detected pair (Research/019 §7). When non-nil and
    /// `onConfirmMerge` is provided, the card renders an inline prompt
    /// for the user to confirm or dismiss the merge.
    var linkageCandidate: MultiAccountLinkageCandidate?
    /// Set when this card represents an already-merged composite that
    /// the user can revoke. Driven from `SyncedUsageData.providerLinkages`
    /// — a context menu "Unmerge accounts" item writes the inverse
    /// LinkageRecord. nil → no unmerge available.
    var activeLinkage: ProviderAccountLinkage?
    var onConfirmMerge: ((MultiAccountLinkageCandidate) -> Void)?
    var onDismissMergeCandidate: ((MultiAccountLinkageCandidate) -> Void)?
    var onRevokeLinkage: ((ProviderAccountLinkage) -> Void)?
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false

    /// True when this is a synthetic mock provider injected by Mac's
    /// `MockProviderInjector` (per `MockProviderDetector`). Drives the
    /// purple accent ring + MOCK badge in the header.
    private var isMockProvider: Bool {
        MockProviderDetector.isMock(self.provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provider header
            providerHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            if let subscriptionLine = self.subscriptionMetadataLine() {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                    Text(subscriptionLine)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .accessibilityIdentifier("provider-subscription-metadata-\(self.provider.providerID)")
            }

            // Usage metrics — dynamic count per provider
            VStack(spacing: 10) {
                ForEach(Array(self.provider.allRateWindows.enumerated()), id: \.offset) { index, window in
                    let warning = self.provider.quotaWarning(forWindowIndex: index)
                    UsageCardView(
                        label: ProviderWindowLabel.localized(
                            window.label,
                            fallback: self.defaultLabel(at: index)),
                        window: window,
                        tintColor: self.providerColor,
                        percentageAccessibilityIdentifier: "usage-card-percent-\(self.provider.providerID)-\(index)",
                        quotaWarningThresholds: warning.thresholds,
                        quotaWarningsEnabled: warning.enabled)
                }
                if let amount = self.provider.providerAmount {
                    ProviderAmountCard(amount: amount, tintColor: self.providerColor)
                }
                if self.provider.allRateWindows.isEmpty,
                   let section = self.provider.details.first
                {
                    ProviderDetailsTeaserView(
                        providerID: self.provider.providerID,
                        section: section)
                }
            }
            .padding(.horizontal, 16)

            // Error / status message
            if let message = self.provider.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // Cost teaser + tap chevron
            HStack {
                if let cost = self.provider.costSummary {
                    self.costTeaserText(cost)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Inline linkage candidate prompt (Research/019 §7 + §9). Shown
            // ONLY when a `MultiAccountLinkageCandidate` was passed in AND
            // the dismiss callback is wired. The card's primary content
            // stays visible above; this is a sub-region the user can
            // confirm/dismiss.
            if let candidate = self.linkageCandidate,
               let onConfirm = self.onConfirmMerge
            {
                self.linkagePromptSection(
                    candidate: candidate,
                    onConfirm: onConfirm,
                    onDismiss: self.onDismissMergeCandidate ?? { _ in })
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            Spacer().frame(height: 20)
        }
        .modifier(ProviderCardBackgroundModifier(isMock: self.isMockProvider))
        .contextMenu {
            if let active = self.activeLinkage, let onRevoke = self.onRevokeLinkage {
                Button(role: .destructive) {
                    onRevoke(active)
                } label: {
                    Label(String(localized: "Unmerge Accounts"), systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    // MARK: - Provider Header

    @ViewBuilder
    private var providerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.provider.providerName)
                    .font(.title3)
                    .fontWeight(.bold)

                if let count = self.accountCount, count > 1 {
                    // Multi-account group indicator. Mirrors Mac's
                    // implicit "N tabs at top of provider menu" hint.
                    Text("· \(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(String(
                            format: String(localized: "provider-account-count-label"),
                            count)))
                        .accessibilityIdentifier("provider-account-count")
                }

                if self.isMockProvider {
                    MockBadgeView()
                }

                Spacer()

                if self.provider.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            HStack(spacing: 8) {
                if let line = self.subtitleLine() {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                        Text(line)
                            .font(.subheadline)
                            .accessibilityIdentifier("provider-card-subtitle-\(self.provider.providerID)")
                    }
                    .foregroundStyle(.secondary)
                }

                if let plan = self.provider.loginMethod {
                    Text(MobilePersonalInfoRedactor.redactEmails(in: plan, isEnabled: self.hidePersonalInfo) ?? plan)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            Text(self.provider.lastUpdated.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var providerColor: Color {
        ProviderColorPalette.color(for: self.provider)
    }

    /// Selects the subtitle string under the provider name. Prefers the
    /// account email (honoring the redactor), then a workspace/organization,
    /// and finally a localized ordinal (`"Codex 2"`) when both are nil and this card is one of
    /// multiple for the same `providerID`, otherwise returns nil so the
    /// single-card layout stays minimal.
    ///
    /// Exposed as `internal` (no `private`) so unit tests can pin the
    /// selection rule without going through SwiftUI's view hierarchy.
    func subtitleLine() -> String? {
        if let email = self.provider.accountEmail, !email.isEmpty {
            return MobilePersonalInfoRedactor.redactEmail(email, isEnabled: self.hidePersonalInfo)
        }
        if let organization = self.provider.accountOrganization, !organization.isEmpty {
            return MobilePersonalInfoRedactor.redactEmails(
                in: organization,
                isEnabled: self.hidePersonalInfo) ?? organization
        }
        if let ordinal = self.duplicateOrdinal {
            // Localized format: "%@ %lld" → `"Codex 2"` / `"Codex 2 号账户"`
            // depending on locale. No-email-but-single-card keeps nil.
            let template = String(localized: "provider-account-ordinal")
            return String(format: template, self.provider.providerName, ordinal)
        }
        return nil
    }

    // MARK: - Linkage prompt (Research/019 §7 + §9)

    @ViewBuilder
    private func linkagePromptSection(
        candidate: MultiAccountLinkageCandidate,
        onConfirm: @escaping (MultiAccountLinkageCandidate) -> Void,
        onDismiss: @escaping (MultiAccountLinkageCandidate) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    // Primary line — Research/019 §9 framing: "another Mac
                    // looks like the same account but is too old/inconsistent
                    // to auto-merge".
                    Text(self.linkagePromptHeadline(candidate: candidate))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(self.linkagePromptDetail(candidate: candidate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button {
                    onConfirm(candidate)
                } label: {
                    Label(
                        String(localized: "Yes, same account"),
                        systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(self.providerColor)

                Button {
                    onDismiss(candidate)
                } label: {
                    Text(String(localized: "Keep separate"))
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
        .accessibilityIdentifier("linkage-prompt-\(candidate.hashKey)")
    }

    private func linkagePromptHeadline(candidate: MultiAccountLinkageCandidate) -> String {
        // "Looks like the same Codex account on another Mac."
        let template = String(localized: "linkage-prompt-headline")
        return String(format: template, candidate.named.providerName)
    }

    private func linkagePromptDetail(candidate: MultiAccountLinkageCandidate) -> String {
        // "The other Mac (CodexBar 0.23.6) reports this provider without an
        // account email, so iOS can't auto-link them. Confirm if it's the
        // same login."
        if let version = candidate.legacyMacVersion {
            let template = String(localized: "linkage-prompt-detail-with-version")
            return String(format: template, version)
        }
        return String(localized: "linkage-prompt-detail")
    }

    @ViewBuilder
    private func costTeaserText(_ cost: SyncCostSummary) -> some View {
        // Route "Today" through `todayTotals()` so this card's teaser and the
        // detail page's "Today" summary stay in lockstep (Build 78 fixed the
        // detail page; this card was still reading `sessionCostUSD` directly,
        // causing Usage-tab teaser ≠ detail-page "Today" mid-day). Same
        // class-of-bug as the Subscription Utilization aggregate/detail
        // mismatch fixed in Build 77.
        let parts = Self.costTeaserParts(cost)

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func costTeaserParts(_ cost: SyncCostSummary) -> [String] {
        let today = cost.todayTotals()
        return [
            today.displayCostUSD.map { "\(String(localized: "Today")): \(Self.formatUSD($0))" },
            cost.completeHistoryCostUSD.map { "\(String(localized: "30d")): \(Self.formatUSD($0))" },
        ].compactMap { $0 }
    }

    private func defaultLabel(at index: Int) -> String {
        switch index {
        case 0: return String(localized: "Session")
        case 1: return String(localized: "Weekly")
        default: return "\(String(localized: "Limit")) \(index + 1)"
        }
    }

    private func subscriptionMetadataLine() -> String? {
        if let renewsAt = self.provider.subscriptionRenewsAt {
            let template = String(localized: "Renews %@")
            return String(format: template, self.subscriptionDateString(renewsAt))
        }
        if let expiresAt = self.provider.subscriptionExpiresAt {
            let template = String(localized: "Plan expires %@")
            return String(format: template, self.subscriptionDateString(expiresAt))
        }
        return nil
    }

    private func subscriptionDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = self.subscriptionDateTimeZone
        return formatter.string(from: date)
    }

    private var subscriptionDateTimeZone: TimeZone {
        if self.provider.providerID == "minimax",
           let shanghai = TimeZone(identifier: "Asia/Shanghai")
        {
            return shanghai
        }
        return .current
    }

    private static func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }
}

private enum MobilePersonalInfoRedactor {
    private static var emailPlaceholder: String {
        String(localized: "Hidden")
    }

    private static let emailRegex: NSRegularExpression? = {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func redactEmail(_ email: String?, isEnabled: Bool) -> String {
        guard let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard isEnabled else { return email }
        return Self.emailPlaceholder
    }

    static func redactEmails(in text: String?, isEnabled: Bool) -> String? {
        guard let text else { return nil }
        guard isEnabled else { return text }
        guard let regex = Self.emailRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: Self.emailPlaceholder)
    }
}

/// Unified with Cost tab's card style — `.ultraThinMaterial` on all iOS versions.
///
/// Commit `408ce6f25` (2026-03-19) had drive-by replaced the original
/// `.regularMaterial + glassEffect` pair with `.thickMaterial`. On a solid
/// `systemGroupedBackground`, material thickness is visually indistinguishable
/// (verified by user inspection 2026-04-20), but `.thickMaterial` costs
/// significantly more on first-frame GPU compositing — large Gaussian blur
/// radius, heavier tint overlay, independent compositing pass per card.
///
/// Matching Cost's `.ultraThinMaterial` (`CostMetricCard.swift:38`,
/// `ContentView.swift:563,641`, `BudgetProgressView.swift:57`) cuts the
/// Usage-tab first-render cost users perceived as ~1s blank after cold start.
private struct ProviderCardBackgroundModifier: ViewModifier {
    /// True when the card holds synthetic mock data — overlays a purple
    /// accent border so the user sees the mock signal even without
    /// reading the MOCK badge or the email subtitle.
    let isMock: Bool

    func body(content: Content) -> some View {
        if self.isMock {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.40), lineWidth: 1.5))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Previews

#Preview("Claude") {
    ScrollView {
        ProviderUsageView(provider: PreviewData.claudeProvider)
            .padding()
    }
}

#Preview("OpenRouter (Error)") {
    ScrollView {
        ProviderUsageView(provider: PreviewData.openRouterProvider)
            .padding()
    }
}
