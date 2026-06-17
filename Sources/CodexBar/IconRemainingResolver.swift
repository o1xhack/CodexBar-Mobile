import CodexBarCore

enum IconRemainingResolver {
    private static let visibleZeroPercent = 0.0001

    private static func codexProjection(snapshot: UsageSnapshot) -> CodexConsumerProjection {
        CodexConsumerProjection.make(
            surface: .menuBar,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: snapshot.updatedAt))
    }

    private static func codexVisibleWindows(snapshot: UsageSnapshot) -> [RateWindow] {
        let projection = self.codexProjection(snapshot: snapshot)
        return projection.visibleRateLanes.compactMap { projection.rateWindow(for: $0) }
    }

    private static func antigravityVisibleWindows(snapshot: UsageSnapshot) -> [RateWindow] {
        var windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
        let compactFallbacks = snapshot.extraRateWindows?
            .filter { $0.usageKnown && $0.id.hasPrefix("antigravity-compact-fallback-") }
            .map(\.window) ?? []
        windows.append(contentsOf: compactFallbacks)
        return windows
    }

    static func resolvedWindows(
        snapshot: UsageSnapshot,
        style: IconStyle,
        secondaryOverrideWindowID: String? = nil)
        -> (primary: RateWindow?, secondary: RateWindow?)
    {
        if style == .perplexity {
            let windows = snapshot.orderedPerplexityDisplayWindows()
            return (
                primary: windows.first,
                secondary: windows.dropFirst().first)
        }
        if style == .antigravity {
            let windows = self.antigravityVisibleWindows(snapshot: snapshot)
            return (
                primary: windows.first,
                secondary: windows.dropFirst().first)
        }
        if style == .codex {
            let windows = self.codexVisibleWindows(snapshot: snapshot)
            return (
                primary: windows.first,
                secondary: windows.dropFirst().first)
        }
        if style == .copilot,
           let secondaryOverrideWindowID,
           let extraWindow = snapshot.extraRateWindows?.first(where: { $0.id == secondaryOverrideWindowID })?.window
        {
            return (
                primary: snapshot.primary,
                secondary: extraWindow)
        }
        return (
            primary: snapshot.primary,
            secondary: snapshot.secondary)
    }

    static func resolvedRemaining(
        snapshot: UsageSnapshot,
        style: IconStyle,
        secondaryOverrideWindowID: String? = nil)
        -> (primary: Double?, secondary: Double?)
    {
        let windows = self.resolvedWindows(
            snapshot: snapshot,
            style: style,
            secondaryOverrideWindowID: secondaryOverrideWindowID)
        return (
            primary: windows.primary?.remainingPercent,
            secondary: windows.secondary?.remainingPercent)
    }

    static func resolvedPercents(
        snapshot: UsageSnapshot,
        style: IconStyle,
        showUsed: Bool,
        secondaryOverrideWindowID: String? = nil)
        -> (primary: Double?, secondary: Double?)
    {
        let windows = Self.resolvedWindows(
            snapshot: snapshot,
            style: style,
            secondaryOverrideWindowID: secondaryOverrideWindowID)
        var percents = (
            primary: showUsed ? windows.primary?.usedPercent : windows.primary?.remainingPercent,
            secondary: showUsed ? windows.secondary?.usedPercent : windows.secondary?.remainingPercent)
        if showUsed, style == .warp, let secondary = windows.secondary {
            if secondary.remainingPercent <= 0 {
                // Preserve Warp's exhausted/no-bonus layout even though used percent is 100.
                percents.secondary = 0
            } else if percents.secondary == 0 {
                // A zero fill means "lane absent" to IconRenderer; keep an unused bonus lane visible.
                percents.secondary = self.visibleZeroPercent
            }
        }
        return percents
    }
}
