import CodexBarSync
import Foundation

enum CodexBarWidgetSnapshotState: String, Codable, Equatable, Sendable {
    case placeholder
    case syncing
    case loaded
    case noData
    case error
}

struct CodexBarWidgetProviderSummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let providerName: String
    let providerID: String
    let loginMethod: String?
    let usagePercent: Double?
    let resetsAt: Date?
    let todayCostUSD: Double?
    let todayCostIsLowerBound: Bool?
    let thirtyDayCostUSD: Double?
    let tokensToday: Int?
    let isError: Bool
    let statusMessage: String?
    let lastUpdated: Date
    /// Quota Pace widget data (Research/065); nil when the provider has no
    /// window of at least one day with a usable observation.
    let quotaPace: CodexBarWidgetPaceSummary?

    init(
        id: String,
        providerName: String,
        providerID: String,
        loginMethod: String?,
        usagePercent: Double?,
        resetsAt: Date? = nil,
        todayCostUSD: Double?,
        todayCostIsLowerBound: Bool? = nil,
        thirtyDayCostUSD: Double?,
        tokensToday: Int?,
        isError: Bool,
        statusMessage: String?,
        lastUpdated: Date,
        quotaPace: CodexBarWidgetPaceSummary? = nil)
    {
        self.id = id
        self.providerName = providerName
        self.providerID = providerID
        self.loginMethod = loginMethod
        self.usagePercent = usagePercent
        self.resetsAt = resetsAt
        self.todayCostUSD = todayCostUSD
        self.todayCostIsLowerBound = todayCostIsLowerBound
        self.thirtyDayCostUSD = thirtyDayCostUSD
        self.tokensToday = tokensToday
        self.isError = isError
        self.statusMessage = statusMessage
        self.lastUpdated = lastUpdated
        self.quotaPace = quotaPace
    }

    /// The same provider with its pace data pointed at another window.
    func withQuotaPace(_ quotaPace: CodexBarWidgetPaceSummary?) -> CodexBarWidgetProviderSummary {
        CodexBarWidgetProviderSummary(
            id: self.id,
            providerName: self.providerName,
            providerID: self.providerID,
            loginMethod: self.loginMethod,
            usagePercent: self.usagePercent,
            resetsAt: self.resetsAt,
            todayCostUSD: self.todayCostUSD,
            todayCostIsLowerBound: self.todayCostIsLowerBound,
            thirtyDayCostUSD: self.thirtyDayCostUSD,
            tokensToday: self.tokensToday,
            isError: self.isError,
            statusMessage: self.statusMessage,
            lastUpdated: self.lastUpdated,
            quotaPace: quotaPace)
    }

    var displaySubtitle: String? {
        if let loginMethod, !loginMethod.isEmpty {
            return loginMethod
        }
        if self.isError {
            return self.statusMessage
        }
        return nil
    }

    var hasDisplayableTodayCost: Bool {
        guard let todayCostUSD else { return false }
        return todayCostUSD > 0 || self.todayCostIsLowerBound == true
    }
}

/// One observed burndown lane for the Quota Pace widget, thinned for the
/// widget's memory and render budget.
struct CodexBarWidgetPaceLane: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        let date: Date
        let remainingPercent: Double
    }

    static let pointLimit = 60

    let seriesName: String
    let label: String
    let start: Date
    let reset: Date
    let points: [Point]

    var remainingPercent: Double? {
        self.points.last?.remainingPercent
    }
}

/// One selectable quota window of a provider (Research/071), evaluated with
/// the same reducers as the provider detail page.
struct CodexBarWidgetPaceWindow: Codable, Equatable, Sendable {
    let id: String
    /// Raw Mac label; the view localizes it like the provider cards.
    let label: String?
    let period: SyncRateWindowPeriod?
    let windowMinutes: Int?
    let pace: QuotaPace?
    /// Nil when usage is unknown or the window has already reset.
    let remainingPercent: Double?
    let resetsAt: Date?
    /// The observed lane drawn for this window (Codex and Claude native slots).
    let laneSeriesName: String?

    init(
        id: String,
        label: String?,
        period: SyncRateWindowPeriod? = nil,
        windowMinutes: Int?,
        pace: QuotaPace?,
        remainingPercent: Double?,
        resetsAt: Date?,
        laneSeriesName: String?)
    {
        self.id = id
        self.label = label
        self.period = period
        self.windowMinutes = windowMinutes
        self.pace = pace
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.laneSeriesName = laneSeriesName
    }

    func title(providerID: String, locale: Locale = .current) -> String {
        QuotaPaceWindowSelection.title(
            label: self.label,
            windowID: self.id,
            windowMinutes: self.windowMinutes,
            period: self.period,
            providerID: providerID,
            locale: locale)
    }
}

/// Pace and burndown data for one provider (Research/065). Computed with the
/// same shared reducers as the provider detail page.
struct CodexBarWidgetPaceSummary: Codable, Equatable, Sendable {
    let pace: QuotaPace?
    /// Remaining percent and reset of the window the pace describes.
    let paceRemainingPercent: Double?
    let paceResetsAt: Date?
    /// Observed lanes (Codex and Claude only), session first.
    let lanes: [CodexBarWidgetPaceLane]
    /// Every window the provider reports (Research/071).
    let windows: [CodexBarWidgetPaceWindow]
    /// The window the pace, remaining percent and reset describe; nil keeps
    /// the Research/065 charted-lane fallback.
    let windowID: String?
    /// True when the widget configuration picked `windowID` explicitly.
    let isExplicitWindow: Bool

    init(
        pace: QuotaPace?,
        paceRemainingPercent: Double?,
        paceResetsAt: Date?,
        lanes: [CodexBarWidgetPaceLane],
        windows: [CodexBarWidgetPaceWindow] = [],
        windowID: String? = nil,
        isExplicitWindow: Bool = false)
    {
        self.pace = pace
        self.paceRemainingPercent = paceRemainingPercent
        self.paceResetsAt = paceResetsAt
        self.lanes = lanes
        self.windows = windows
        self.windowID = windowID
        self.isExplicitWindow = isExplicitWindow
    }

    private enum CodingKeys: String, CodingKey {
        case pace, paceRemainingPercent, paceResetsAt, lanes, windows, windowID, isExplicitWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pace = try container.decodeIfPresent(QuotaPace.self, forKey: .pace)
        self.paceRemainingPercent = try container.decodeIfPresent(Double.self, forKey: .paceRemainingPercent)
        self.paceResetsAt = try container.decodeIfPresent(Date.self, forKey: .paceResetsAt)
        self.lanes = try container.decode([CodexBarWidgetPaceLane].self, forKey: .lanes)
        self.windows = try container.decodeIfPresent([CodexBarWidgetPaceWindow].self, forKey: .windows) ?? []
        self.windowID = try container.decodeIfPresent(String.self, forKey: .windowID)
        self.isExplicitWindow = try container.decodeIfPresent(Bool.self, forKey: .isExplicitWindow) ?? false
    }

    /// Nil when the provider has neither pace, an observed lane, nor a window.
    init?(provider: ProviderUsageSnapshot, now: Date) {
        let resolved = MobileQuotaBurndown.resolvedLanes(for: provider, referenceDate: now)
        let lanes = resolved.map { resolved in
            CodexBarWidgetPaceLane(
                seriesName: resolved.lane.seriesName,
                label: resolved.lane.label,
                start: resolved.model.start,
                reset: resolved.model.reset,
                points: MobileQuotaBurndown.downsample(resolved.model.samples, limit: CodexBarWidgetPaceLane.pointLimit)
                    .map { CodexBarWidgetPaceLane.Point(date: $0.date, remainingPercent: $0.remainingPercent) })
        }
        // Mirrors the Mac's only `allowsEstimatedUsage: false` pace capability.
        let paceAllowed = !(provider.providerID == "opencodego" && provider.usageDataConfidence == "estimated")
        let windows = QuotaPaceWindowSelection.candidates(for: provider).map { candidate in
            let window = candidate.window
            return CodexBarWidgetPaceWindow(
                id: candidate.id,
                label: window.label,
                period: window.period,
                windowMinutes: window.windowMinutes,
                pace: paceAllowed ? QuotaPace(
                    window: window,
                    capturedAt: provider.lastUpdated,
                    referenceDate: now,
                    providerID: provider.providerID) : nil,
                remainingPercent: QuotaPaceWindowSelection.remainingPercent(of: window, now: now),
                resetsAt: window.resetsAt,
                laneSeriesName: resolved.first { $0.lane.window == window }?.lane.seriesName)
        }
        let defaultWindow = QuotaPaceWindowSelection.defaultWindowID(for: provider, now: now)
            .flatMap { id in windows.first { $0.id == id } }
        if let defaultWindow {
            self.init(
                pace: defaultWindow.pace,
                paceRemainingPercent: defaultWindow.remainingPercent,
                paceResetsAt: defaultWindow.resetsAt,
                lanes: lanes,
                windows: windows,
                windowID: defaultWindow.id)
            return
        }
        guard !lanes.isEmpty || !windows.isEmpty else { return nil }
        // Without a default window the hero falls back to the charted lane
        // so it never shows a placeholder next to a chart.
        let fallbackLane = lanes.first { $0.seriesName == "weekly" } ?? lanes.last
        self.init(
            pace: nil,
            paceRemainingPercent: fallbackLane?.remainingPercent,
            paceResetsAt: fallbackLane?.reset,
            lanes: lanes,
            windows: windows)
    }

    /// The same data pointed at the configured window. An unknown id (the
    /// window disappeared) keeps the default window.
    func selecting(windowID: String?) -> CodexBarWidgetPaceSummary {
        guard let windowID, let window = self.windows.first(where: { $0.id == windowID }) else { return self }
        return CodexBarWidgetPaceSummary(
            pace: window.pace,
            paceRemainingPercent: window.remainingPercent,
            paceResetsAt: window.resetsAt,
            lanes: self.lanes,
            windows: self.windows,
            windowID: window.id,
            isExplicitWindow: true)
    }

    /// The window the summary describes, if any.
    var selectedWindow: CodexBarWidgetPaceWindow? {
        self.windowID.flatMap { id in self.windows.first { $0.id == id } }
    }

    /// Automatic provider selection only considers a pace or a chart, as
    /// before window selection existed.
    var isAutomaticCandidate: Bool {
        self.pace != nil || !self.lanes.isEmpty
    }

    /// Something to draw: a pace, a remaining percent, or a chart.
    var hasDisplayableData: Bool {
        self.pace != nil || self.paceRemainingPercent != nil || self.primaryLane != nil
    }

    /// Deterministic placeholder/preview data: a weekly lane `weeklyUsed`%
    /// used with `weeklyResetIn` days left, plus an optional session lane.
    /// `extraWindows` adds selectable windows without a chart (for example
    /// Claude's model-only weekly window).
    static func sample(
        now: Date,
        weeklyUsed: Double,
        weeklyResetIn days: Double,
        sessionUsed: Double?,
        extraWindows: [(id: String, label: String, used: Double)] = []) -> CodexBarWidgetPaceSummary
    {
        let captured = now.addingTimeInterval(-120)
        func lane(name: String, label: String, minutes: Int, used: Double, resetIn: TimeInterval) -> (
            CodexBarWidgetPaceLane, SyncRateWindow)
        {
            let reset = captured.addingTimeInterval(resetIn)
            let start = reset.addingTimeInterval(-Double(minutes) * 60)
            let span = captured.timeIntervalSince(start)
            let points = (0...12).map { step -> CodexBarWidgetPaceLane.Point in
                let fraction = Double(step) / 12
                // Uneven use: quiet start, steadier middle, a recent burst.
                let curve = fraction < 0.5 ? fraction * 0.6 : 0.3 + (fraction - 0.5) * 1.4
                return .init(
                    date: start.addingTimeInterval(span * fraction),
                    remainingPercent: 100 - used * min(1, curve))
            }
            let window = SyncRateWindow(
                usedPercent: used,
                windowMinutes: minutes,
                resetsAt: reset,
                resetDescription: nil)
            return (
                CodexBarWidgetPaceLane(seriesName: name, label: label, start: start, reset: reset, points: points),
                window)
        }
        let weekly = lane(name: "weekly", label: "Weekly", minutes: 10080, used: weeklyUsed, resetIn: days * 86400)
        let session = sessionUsed.map {
            lane(name: "session", label: "Session", minutes: 300, used: $0, resetIn: 2.4 * 3600).0
        }
        let weeklyPace = QuotaPace(window: weekly.1, capturedAt: captured, referenceDate: now)
        var windows: [CodexBarWidgetPaceWindow] = []
        if let session, let sessionUsed {
            windows.append(CodexBarWidgetPaceWindow(
                id: "primary", label: "Session", windowMinutes: 300, pace: nil,
                remainingPercent: 100 - sessionUsed, resetsAt: session.reset, laneSeriesName: "session"))
        }
        windows.append(CodexBarWidgetPaceWindow(
            id: "secondary", label: "Weekly", windowMinutes: 10080, pace: weeklyPace,
            remainingPercent: 100 - weeklyUsed, resetsAt: weekly.1.resetsAt, laneSeriesName: "weekly"))
        for extra in extraWindows {
            let window = SyncRateWindow(
                usedPercent: extra.used,
                windowMinutes: 10080,
                resetsAt: weekly.1.resetsAt,
                resetDescription: nil)
            windows.append(CodexBarWidgetPaceWindow(
                id: extra.id, label: extra.label, windowMinutes: 10080,
                pace: QuotaPace(window: window, capturedAt: captured, referenceDate: now),
                remainingPercent: 100 - extra.used, resetsAt: window.resetsAt, laneSeriesName: nil))
        }
        return CodexBarWidgetPaceSummary(
            pace: weeklyPace,
            paceRemainingPercent: 100 - weeklyUsed,
            paceResetsAt: weekly.1.resetsAt,
            lanes: [session, weekly.0].compactMap(\.self),
            windows: windows,
            windowID: "secondary")
    }

    /// The lane of the described window for single-chart layouts. An
    /// explicitly chosen window without an observed lane (a model-only or
    /// extra window) has no chart; otherwise weekly comes first.
    var primaryLane: CodexBarWidgetPaceLane? {
        if let name = self.selectedWindow?.laneSeriesName,
           let lane = self.lanes.first(where: { $0.seriesName == name })
        {
            return lane
        }
        if self.isExplicitWindow { return nil }
        return self.lanes.first { $0.seriesName == "weekly" } ?? self.lanes.last
    }

    /// Lanes for the two-chart layout: the first two lanes when they include
    /// the described window's lane, else only that lane; nothing for an
    /// explicitly chosen window without a lane.
    var displayLanes: [CodexBarWidgetPaceLane] {
        let leading = Array(self.lanes.prefix(2))
        guard self.isExplicitWindow else { return leading }
        guard let lane = self.primaryLane else { return [] }
        return leading.contains(lane) ? leading : [lane]
    }
}

struct CodexBarWidgetSnapshot: Codable, Equatable, Sendable {
    let state: CodexBarWidgetSnapshotState
    let generatedAt: Date
    let latestSyncAt: Date?
    let deviceCount: Int
    let providerCount: Int
    let errorCount: Int
    let todayCostUSD: Double?
    let todayCostIsLowerBound: Bool?
    let thirtyDayCostUSD: Double?
    let todayTokens: Int?
    let maxUsagePercent: Double?
    let topProviders: [CodexBarWidgetProviderSummary]
    let message: String?
    let isStale: Bool

    init(
        state: CodexBarWidgetSnapshotState,
        generatedAt: Date,
        latestSyncAt: Date?,
        deviceCount: Int,
        providerCount: Int,
        errorCount: Int,
        todayCostUSD: Double?,
        todayCostIsLowerBound: Bool? = nil,
        thirtyDayCostUSD: Double?,
        todayTokens: Int?,
        maxUsagePercent: Double?,
        topProviders: [CodexBarWidgetProviderSummary],
        message: String?,
        isStale: Bool)
    {
        self.state = state
        self.generatedAt = generatedAt
        self.latestSyncAt = latestSyncAt
        self.deviceCount = deviceCount
        self.providerCount = providerCount
        self.errorCount = errorCount
        self.todayCostUSD = todayCostUSD
        self.todayCostIsLowerBound = todayCostIsLowerBound
        self.thirtyDayCostUSD = thirtyDayCostUSD
        self.todayTokens = todayTokens
        self.maxUsagePercent = maxUsagePercent
        self.topProviders = topProviders
        self.message = message
        self.isStale = isStale
    }

    static func placeholder(now: Date = .now) -> CodexBarWidgetSnapshot {
        CodexBarWidgetSnapshot(
            state: .placeholder,
            generatedAt: now,
            latestSyncAt: now.addingTimeInterval(-180),
            deviceCount: 2,
            providerCount: 6,
            errorCount: 1,
            todayCostUSD: 19.42,
            thirtyDayCostUSD: 238.77,
            todayTokens: 822_000,
            maxUsagePercent: 78,
            topProviders: [
                CodexBarWidgetProviderSummary(
                    id: "codex|sample",
                    providerName: "Codex",
                    providerID: "codex",
                    loginMethod: "Team",
                    usagePercent: 78,
                    resetsAt: now.addingTimeInterval(3.7 * 86400),
                    todayCostUSD: 12.64,
                    thirtyDayCostUSD: 109.33,
                    tokensToday: 366_000,
                    isError: false,
                    statusMessage: nil,
                    lastUpdated: now.addingTimeInterval(-120),
                    quotaPace: .sample(now: now, weeklyUsed: 39, weeklyResetIn: 2.9, sessionUsed: 22)),
                CodexBarWidgetProviderSummary(
                    id: "claude|sample",
                    providerName: "Claude",
                    providerID: "claude",
                    loginMethod: "Max",
                    usagePercent: 42,
                    resetsAt: now.addingTimeInterval(0.6 * 86400),
                    todayCostUSD: 6.78,
                    thirtyDayCostUSD: 129.44,
                    tokensToday: 456_000,
                    isError: false,
                    statusMessage: nil,
                    lastUpdated: now.addingTimeInterval(-300),
                    quotaPace: .sample(
                        now: now,
                        weeklyUsed: 54,
                        weeklyResetIn: 3.6,
                        sessionUsed: 17,
                        extraWindows: [(id: "claude-weekly-scoped-fable", label: "Fable only", used: 71)])),
                CodexBarWidgetProviderSummary(
                    id: "raycast|sample", providerName: "Raycast", providerID: "raycast",
                    loginMethod: nil, usagePercent: 30, resetsAt: now.addingTimeInterval(3.6 * 86400),
                    todayCostUSD: nil, thirtyDayCostUSD: nil, tokensToday: nil,
                    isError: false, statusMessage: nil, lastUpdated: now),
                CodexBarWidgetProviderSummary(
                    id: "openrouter|sample",
                    providerName: "OpenRouter",
                    providerID: "openrouter",
                    loginMethod: "Credits",
                    usagePercent: 92,
                    todayCostUSD: nil,
                    thirtyDayCostUSD: nil,
                    tokensToday: nil,
                    isError: true,
                    statusMessage: "Rate limit approaching",
                    lastUpdated: now.addingTimeInterval(-60)),
            ],
            message: nil,
            isStale: false)
    }

    #if targetEnvironment(simulator)
    static func simulatorMock(now: Date = .now) -> CodexBarWidgetSnapshot {
        let sample = Self.placeholder(now: now)
        return CodexBarWidgetSnapshot(
            state: .loaded,
            generatedAt: sample.generatedAt,
            latestSyncAt: sample.latestSyncAt,
            deviceCount: sample.deviceCount,
            providerCount: sample.providerCount,
            errorCount: sample.errorCount,
            todayCostUSD: sample.todayCostUSD,
            thirtyDayCostUSD: sample.thirtyDayCostUSD,
            todayTokens: sample.todayTokens,
            maxUsagePercent: sample.maxUsagePercent,
            topProviders: sample.topProviders,
            message: sample.message,
            isStale: sample.isStale)
    }
    #endif

    static func syncing(now: Date = .now) -> CodexBarWidgetSnapshot {
        CodexBarWidgetSnapshot(
            state: .syncing,
            generatedAt: now,
            latestSyncAt: nil,
            deviceCount: 0,
            providerCount: 0,
            errorCount: 0,
            todayCostUSD: nil,
            thirtyDayCostUSD: nil,
            todayTokens: nil,
            maxUsagePercent: nil,
            topProviders: [],
            message: nil,
            isStale: false)
    }

    static func noData(now: Date = .now) -> CodexBarWidgetSnapshot {
        CodexBarWidgetSnapshot(
            state: .noData,
            generatedAt: now,
            latestSyncAt: nil,
            deviceCount: 0,
            providerCount: 0,
            errorCount: 0,
            todayCostUSD: nil,
            thirtyDayCostUSD: nil,
            todayTokens: nil,
            maxUsagePercent: nil,
            topProviders: [],
            message: nil,
            isStale: false)
    }

    static func error(_ message: String, now: Date = .now) -> CodexBarWidgetSnapshot {
        CodexBarWidgetSnapshot(
            state: .error,
            generatedAt: now,
            latestSyncAt: nil,
            deviceCount: 0,
            providerCount: 0,
            errorCount: 0,
            todayCostUSD: nil,
            thirtyDayCostUSD: nil,
            todayTokens: nil,
            maxUsagePercent: nil,
            topProviders: [],
            message: message,
            isStale: false)
    }
}

enum CodexBarWidgetSnapshotBuilder {
    static let staleInterval: TimeInterval = 60 * 60 * 6

    static func makeSnapshot(
        from result: MultiDeviceSyncResult,
        fallbackKVSSnapshot: SyncedUsageSnapshot? = nil,
        providerLinkages: [ProviderAccountLinkage] = [],
        deviceLifecycleEvents: [DeviceLifecycleEvent] = [],
        now: Date = .now) -> CodexBarWidgetSnapshot
    {
        switch result {
        case let .success(snapshots):
            return self.makeSnapshot(
                from: snapshots,
                providerLinkages: providerLinkages,
                deviceLifecycleEvents: deviceLifecycleEvents,
                now: now)
        case .empty:
            if let fallbackKVSSnapshot {
                return self.makeSnapshot(
                    from: [fallbackKVSSnapshot],
                    providerLinkages: providerLinkages,
                    deviceLifecycleEvents: deviceLifecycleEvents,
                    now: now)
            }
            return .noData(now: now)
        case let .error(error):
            if let fallbackKVSSnapshot {
                var snapshot = self.makeSnapshot(
                    from: [fallbackKVSSnapshot],
                    providerLinkages: providerLinkages,
                    deviceLifecycleEvents: deviceLifecycleEvents,
                    now: now)
                snapshot = CodexBarWidgetSnapshot(
                    state: snapshot.state,
                    generatedAt: snapshot.generatedAt,
                    latestSyncAt: snapshot.latestSyncAt,
                    deviceCount: snapshot.deviceCount,
                    providerCount: snapshot.providerCount,
                    errorCount: snapshot.errorCount,
                    todayCostUSD: snapshot.todayCostUSD,
                    todayCostIsLowerBound: snapshot.todayCostIsLowerBound,
                    thirtyDayCostUSD: snapshot.thirtyDayCostUSD,
                    todayTokens: snapshot.todayTokens,
                    maxUsagePercent: snapshot.maxUsagePercent,
                    topProviders: snapshot.topProviders,
                    message: error.description,
                    isStale: true)
                return snapshot
            }
            return .error(error.description, now: now)
        }
    }

    static func makeSnapshot(
        from snapshots: [SyncedUsageSnapshot],
        providerLinkages: [ProviderAccountLinkage] = [],
        deviceLifecycleEvents: [DeviceLifecycleEvent] = [],
        now: Date = .now) -> CodexBarWidgetSnapshot
    {
        guard !snapshots.isEmpty else {
            return .noData(now: now)
        }

        let activeSnapshots = DeviceSnapshotResolver
            .resolveDeviceSnapshots(
                snapshots,
                lifecycleEvents: deviceLifecycleEvents,
                providerLinkages: providerLinkages)
            .activeSnapshots

        guard !activeSnapshots.isEmpty else {
            return .noData(now: now)
        }

        guard let mergedSnapshot = ProviderSnapshotMerger.mergeSnapshots(
            activeSnapshots,
            linkages: providerLinkages)
        else {
            return .noData(now: now)
        }

        let providers = mergedSnapshot.providers
        guard !providers.isEmpty else {
            return CodexBarWidgetSnapshot(
                state: .noData,
                generatedAt: now,
                latestSyncAt: mergedSnapshot.syncTimestamp,
                deviceCount: activeSnapshots.count,
                providerCount: 0,
                errorCount: 0,
                todayCostUSD: nil,
                thirtyDayCostUSD: nil,
                todayTokens: nil,
                maxUsagePercent: nil,
                topProviders: [],
                message: nil,
                isStale: false)
        }

        // Provider-level cost envelopes contribute to aggregate spend, but
        // they are not user accounts and must not become widget provider rows.
        let summaries = providers.map { self.summary(for: $0, now: now) }
        let visibleSummaries = zip(providers, summaries)
            .filter { provider, _ in !provider.isProviderLevelCostEnvelope }
            .map(\.1)
        let costSummaries = providers.compactMap(\.costSummary)
            .filter(ProviderSnapshotMerger.supportsUSDAggregation)
        let todayCostIsUnavailable = costSummaries.contains { summary in
            let today = self.todayTotals(from: summary, now: now)
            return today.costIsKnown == false
        }
        let todayCostIsLowerBound = !todayCostIsUnavailable && costSummaries.contains { summary in
            self.todayTotals(from: summary, now: now).isLowerBound
        }
        let thirtyDayCostIsIncomplete = costSummaries.contains {
            $0.hasIncompleteHistoricalCostCoverage(at: now)
        }
        let todayCost = summaries.compactMap(\.todayCostUSD).reduce(0, +)
        let thirtyDayCost = summaries.compactMap(\.thirtyDayCostUSD).reduce(0, +)
        let todayTokens = summaries.compactMap(\.tokensToday).reduce(0, +)
        let latestSyncAt = activeSnapshots.map(\.syncTimestamp).max()
        let maxUsage = visibleSummaries.compactMap(\.usagePercent).max()
        let errorCount = visibleSummaries.filter(\.isError).count

        let topProviders = visibleSummaries
            .sorted { lhs, rhs in
                let lhsScore = lhs.isError ? 1000 + (lhs.usagePercent ?? 0) : (lhs.usagePercent ?? 0)
                let rhsScore = rhs.isError ? 1000 + (rhs.usagePercent ?? 0) : (rhs.usagePercent ?? 0)
                if lhsScore == rhsScore {
                    return lhs.lastUpdated > rhs.lastUpdated
                }
                return lhsScore > rhsScore
            }

        return CodexBarWidgetSnapshot(
            state: .loaded,
            generatedAt: now,
            latestSyncAt: latestSyncAt,
            deviceCount: activeSnapshots.count,
            providerCount: visibleSummaries.count,
            errorCount: errorCount,
            todayCostUSD: !todayCostIsUnavailable && (todayCost > 0 || todayCostIsLowerBound)
                ? todayCost
                : nil,
            todayCostIsLowerBound: todayCostIsLowerBound ? true : nil,
            thirtyDayCostUSD: !thirtyDayCostIsIncomplete && thirtyDayCost > 0 ? thirtyDayCost : nil,
            todayTokens: todayTokens > 0 ? todayTokens : nil,
            maxUsagePercent: maxUsage,
            topProviders: topProviders,
            message: nil,
            isStale: latestSyncAt.map { now.timeIntervalSince($0) > Self.staleInterval } ?? false)
    }

    private static func summary(
        for provider: ProviderUsageSnapshot,
        now: Date) -> CodexBarWidgetProviderSummary
    {
        let costSummary = ProviderSnapshotMerger.supportsUSDAggregation(provider.costSummary)
            ? provider.costSummary : nil
        let today = costSummary.map { self.todayTotals(from: $0, now: now) }
        let leadingWindow = provider.allRateWindows
            .filter { $0.usageKnown && !$0.isSyntheticPlaceholder && $0.usedPercent.isFinite }
            .max { $0.usedPercent < $1.usedPercent }
        let windowPercent = leadingWindow?.usedPercent
        let budgetPercent: Double? = provider.budget.flatMap { budget in
            guard budget.limitAmount > 0, budget.limitAmount.isFinite, budget.usedAmount.isFinite else { return nil }
            return min(100, max(0, budget.usedAmount / budget.limitAmount * 100))
        }
        let budgetLeads = budgetPercent.map { $0 > (windowPercent ?? -1) } ?? false
        let usagePercent = budgetLeads ? budgetPercent : windowPercent
        let resetsAt = budgetLeads ? provider.budget?.resetsAt : leadingWindow?.resetsAt
        let accountKey = provider.accountEmail ?? "_"
        return CodexBarWidgetProviderSummary(
            id: "\(provider.providerID)|\(accountKey)",
            providerName: provider.providerName,
            providerID: provider.providerID,
            loginMethod: provider.loginMethod,
            usagePercent: usagePercent,
            resetsAt: resetsAt,
            todayCostUSD: today?.costIsKnown == false ? nil : today?.costUSD,
            todayCostIsLowerBound: today?.isLowerBound == true ? true : nil,
            thirtyDayCostUSD: costSummary?.completeThirtyDayHistoryCostUSD(at: now),
            tokensToday: today?.tokens,
            isError: provider.isError,
            statusMessage: provider.statusMessage,
            lastUpdated: provider.lastUpdated,
            quotaPace: CodexBarWidgetPaceSummary(provider: provider, now: now))
    }

    private static func todayTotals(
        from summary: SyncCostSummary,
        now: Date) -> (costUSD: Double?, tokens: Int?, costIsKnown: Bool?, isLowerBound: Bool)
    {
        let dayKey = summary.costDayKey(for: now)
        let sourceDayKey = summary.sourceDayKey ?? summary.sourceUpdatedAt.map(summary.costDayKey)
        let sessionDayKey = summary.sessionDayKey ?? sourceDayKey
        let sourceIsStale = sourceDayKey.map { $0 != dayKey } ?? false
        let sessionSourceIsStale = sessionDayKey.map { $0 != dayKey } ?? false
        // Historical coverage belongs to the configured scan window. A known
        // dated point/session remains displayable while an undated legacy
        // fallback keeps the aggregate coverage guard.
        let todayCalendarIsInvalid = summary.hasInvalidBucketTimeZoneIdentifier
        let historyScanIsIncomplete = summary.reportingPeriodHistoryCoverageIsEstablished == false
        let historicalCoverageIsIncomplete = historyScanIsIncomplete ||
            summary.reportingPeriodCoverage.map { $0.unpriced > 0 || $0.unmetered > 0 } == true
        if let point = summary.reportingPeriodDaily.first(where: { $0.dayKey == dayKey }) {
            let costIsKnown = todayCalendarIsInvalid || sourceIsStale ? false : point.costIsKnown
            return (
                costIsKnown == false ? nil : point.costUSD,
                point.totalTokens,
                costIsKnown,
                costIsKnown != false && historyScanIsIncomplete)
        }
        if sessionSourceIsStale {
            return (nil, nil, false, false)
        }
        let hasQualifiedCurrentSession = sessionDayKey == dayKey && summary.sessionCostIsKnown == true
        let costIsKnown = todayCalendarIsInvalid ||
            (historicalCoverageIsIncomplete && !hasQualifiedCurrentSession)
            ? false
            : summary.sessionCostIsKnown ?? (summary.sessionCostUSD == nil ? nil : true)
        return (
            costIsKnown == false ? nil : summary.sessionCostUSD,
            summary.sessionTokens,
            costIsKnown,
            costIsKnown != false && summary.sessionCostUSD != nil && historyScanIsIncomplete)
    }
}
