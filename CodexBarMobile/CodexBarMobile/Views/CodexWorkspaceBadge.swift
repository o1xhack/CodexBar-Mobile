import CodexBarSync
import SwiftUI

/// Codex workspace data stays verbatim; pace copy belongs to the iPhone locale.
struct CodexWorkspaceBadge: View {
    @Environment(\.locale) private var locale
    @State private var showsPaceExplanation = false
    var window: SyncRateWindow?
    let context: SyncCodexWorkspaceContext
    let tintColor: Color
    var referenceDate: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = context.workspaceName, !name.isEmpty {
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
            if let pace = CodexPacePresentation(
                context: self.context, window: self.window, referenceDate: self.referenceDate)
            {
                HStack(spacing: 6) {
                    Image(systemName: self.paceIconName)
                        .font(.caption)
                        .foregroundStyle(self.paceColor)
                    Text(verbatim: pace.summary(locale: self.locale))
                        .font(.caption.bold())
                        .foregroundStyle(self.paceColor)
                        .accessibilityIdentifier("codex-pace-summary")
                    Button {
                        self.showsPaceExplanation = true
                    } label: {
                        Image(systemName: "info.circle")
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "About the weekly pace estimate"))
                    .accessibilityIdentifier("codex-pace-info")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08)))
        .alert(String(localized: "Weekly pace estimate"), isPresented: self.$showsPaceExplanation) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(
                String(
                    // Keep the complete localization key available to string extraction.
                    // swiftlint:disable:next line_length
                    localized: "Points compare used quota with even use. Forecasts assume the latest Mac average rate continues. At least 1.5× means 50% faster use could still last until reset. This is an estimate, not a guarantee."))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codex-workspace-badge")
    }

    private var paceIconName: String {
        guard let delta = context.weeklyPaceDelta else { return "speedometer" }
        if delta > 0.05 { return "arrow.up.circle.fill" }
        if delta < -0.05 { return "arrow.down.circle.fill" }
        return "equal.circle.fill"
    }

    private var paceColor: Color {
        guard let delta = context.weeklyPaceDelta else { return .secondary }
        if delta > 0.05 { return .orange }
        if delta < -0.05 { return .green }
        return self.tintColor
    }
}

#Preview {
    VStack(spacing: 12) {
        CodexWorkspaceBadge(
            context: SyncCodexWorkspaceContext(
                workspaceID: "ws-acme-prod",
                workspaceName: "Acme Production",
                weeklyPaceDelta: 0.12,
                weeklyPaceLabel: "+12% ahead of pace",
                updatedAt: Date()),
            tintColor: .purple)
        CodexWorkspaceBadge(
            context: SyncCodexWorkspaceContext(
                workspaceID: "ws-personal",
                workspaceName: "Personal",
                weeklyPaceDelta: -0.08,
                weeklyPaceLabel: "-8% under pace",
                updatedAt: Date()),
            tintColor: .purple)
    }
    .padding()
}
