import CodexBarCore
import Foundation

/// Maps the layout's common top-level percentage tokens onto one picker. Conditional branches
/// and direct primary/secondary lane tokens remain under the layout editor's control.
enum MenuBarPercentWindowPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case session
    case weekly
    case tertiary
    case monthlyPlan

    var id: String {
        self.rawValue
    }

    private var percentWindow: PercentWindow? {
        switch self {
        case .automatic: .automatic
        case .session: .session
        case .weekly: .weekly
        case .tertiary, .monthlyPlan: nil
        }
    }

    private var layoutToken: MenuBarLayoutToken {
        if self == .tertiary { return .lanePercent(lane: .tertiary) }
        // Metric-backed choices resolve through the automatic lane.
        return .percent(window: self.percentWindow ?? .automatic)
    }

    /// The per-provider metric this choice stores for providers that offer Monthly Plan, which the
    /// automatic percent and widgets read.
    var menuBarMetric: MenuBarMetricPreference {
        self == .monthlyPlan ? .monthlyPlan : .automatic
    }

    func label(for provider: UsageProvider) -> String {
        guard self != .automatic else { return L("menu_bar_layout_token_auto") }
        if self == .monthlyPlan { return MenuBarMetricPreference.monthlyPlan.label }
        if self == .tertiary {
            return MenuBarLayoutLaneLabels(provider: provider, snapshot: nil).label(for: .tertiary)
        }
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let primary = PercentWindow.forSemanticWindow(descriptor.presentation.primarySemanticWindow)
        let presentation = descriptor.presentation
        return L(self.percentWindow == primary
            ? presentation.menuBarLayoutPrimaryLabel ?? descriptor.metadata.sessionLabel
            : presentation.menuBarLayoutSecondaryLabel ?? descriptor.metadata.weeklyLabel)
    }

    /// Semantic windows keep their existing mapping; an independently selectable tertiary pool
    /// uses the already-supported direct lane token and its provider-owned label.
    static func available(
        metrics: ProviderMenuBarMetricCapabilities,
        primarySemanticWindow: ProviderSemanticWindow = .session,
        secondarySemanticWindow: ProviderSemanticWindow = .weekly) -> [Self]
    {
        var windows = Set<PercentWindow>()
        for metric in metrics.supported {
            windows.insert(PercentWindow.forMetric(
                metric,
                primarySemanticWindow: primarySemanticWindow,
                secondarySemanticWindow: secondarySemanticWindow))
        }
        var options = Self.allCases.filter { preference in
            guard let window = preference.percentWindow else { return false }
            return windows.contains(window)
        }
        if metrics.supported.contains(.tertiary), !metrics.tertiaryRequiresWindow {
            options.append(.tertiary)
        }
        if metrics.supported.contains(.monthlyPlan) {
            options.append(.monthlyPlan)
        }
        return options
    }

    static func available(for provider: UsageProvider, layout: MenuBarLayout? = nil) -> [Self] {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let options = Self.available(
            metrics: descriptor.menuBarMetrics,
            primarySemanticWindow: descriptor.presentation.primarySemanticWindow,
            secondarySemanticWindow: descriptor.presentation.secondarySemanticWindow)
        if let layout, !self.percentWindows(in: layout).isEmpty, self.hasTertiaryPercent(in: layout) {
            return options.filter { $0 != .tertiary }
        }
        // Without a percentage in the layout, only the stored metric can change.
        if let layout, options.contains(.monthlyPlan), !self.hasPercentToken(in: layout) {
            return [.automatic, .monthlyPlan]
        }
        return options
    }

    /// The simplified picker controls percent layouts without changing the global icon style.
    /// Monthly Plan also picks the widget allowance, so it stays reachable in every style and layout.
    static func isVisible(
        iconStyle: MenuBarIconStyle,
        layout: MenuBarLayout,
        available: [Self]) -> Bool
    {
        guard available.count > 1 else { return false }
        if available.contains(.monthlyPlan) { return true }
        return iconStyle == .iconAndPercent && self.hasPercentToken(in: layout)
    }

    static func isVisible(
        iconStyle: MenuBarIconStyle,
        layout: MenuBarLayout,
        provider: UsageProvider) -> Bool
    {
        self.isVisible(
            iconStyle: iconStyle,
            layout: layout,
            available: self.available(for: provider, layout: layout))
    }

    /// Ordinary percentages own the choice when a custom layout also has an independent tertiary
    /// token. Only layouts without ordinary percentages treat tertiary tokens as the controlled group.
    /// Pass the stored metric for providers that offer Monthly Plan: it turns an all-automatic layout into the
    /// Monthly Plan choice, and alone decides the choice when the layout has no percentage.
    static func current(in layout: MenuBarLayout, metric: MenuBarMetricPreference? = nil) -> Self? {
        let windows = Self.percentWindows(in: layout)
        guard let first = windows.first else {
            if self.hasTertiaryPercent(in: layout) { return .tertiary }
            guard let metric else { return nil }
            return metric == .monthlyPlan ? .monthlyPlan : .automatic
        }
        guard windows.allSatisfy({ $0 == first }) else { return nil }
        if first == .automatic, metric == .monthlyPlan { return .monthlyPlan }
        return Self.allCases.first { $0.percentWindow == first }
    }

    static func hasPercentToken(in layout: MenuBarLayout) -> Bool {
        !self.percentWindows(in: layout).isEmpty || self.hasTertiaryPercent(in: layout)
    }

    /// Changes only the common percentage group, preserving pace, resets and custom tokens.
    func applied(to layout: MenuBarLayout) -> MenuBarLayout {
        let hasOrdinaryPercent = !Self.percentWindows(in: layout).isEmpty
        // Collapsing an ordinary percent and an independent tertiary token would lose their identities.
        if self == .tertiary, hasOrdinaryPercent, Self.hasTertiaryPercent(in: layout) { return layout }
        return MenuBarLayout(lines: layout.lines.map { line in
            line.map { token in
                if case .percent = token { return self.layoutToken }
                if !hasOrdinaryPercent, token == .lanePercent(lane: .tertiary) { return self.layoutToken }
                return token
            }
        })
    }

    private static func hasTertiaryPercent(in layout: MenuBarLayout) -> Bool {
        layout.lines.joined().contains(.lanePercent(lane: .tertiary))
    }

    private static func percentWindows(in layout: MenuBarLayout) -> [PercentWindow] {
        layout.lines.flatMap(\.self).compactMap { token in
            guard case let .percent(window) = token else { return nil }
            return window
        }
    }
}
