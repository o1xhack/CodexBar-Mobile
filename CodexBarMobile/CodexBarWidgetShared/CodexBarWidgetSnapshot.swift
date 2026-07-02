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
    let todayCostUSD: Double?
    let thirtyDayCostUSD: Double?
    let tokensToday: Int?
    let isError: Bool
    let statusMessage: String?
    let lastUpdated: Date

    var displaySubtitle: String? {
        if let loginMethod, !loginMethod.isEmpty {
            return loginMethod
        }
        if isError {
            return statusMessage
        }
        return nil
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
    let thirtyDayCostUSD: Double?
    let todayTokens: Int?
    let maxUsagePercent: Double?
    let topProviders: [CodexBarWidgetProviderSummary]
    let message: String?
    let isStale: Bool

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
                    todayCostUSD: 12.64,
                    thirtyDayCostUSD: 109.33,
                    tokensToday: 366_000,
                    isError: false,
                    statusMessage: nil,
                    lastUpdated: now.addingTimeInterval(-120)),
                CodexBarWidgetProviderSummary(
                    id: "claude|sample",
                    providerName: "Claude",
                    providerID: "claude",
                    loginMethod: "Max",
                    usagePercent: 42,
                    todayCostUSD: 6.78,
                    thirtyDayCostUSD: 129.44,
                    tokensToday: 456_000,
                    isError: false,
                    statusMessage: nil,
                    lastUpdated: now.addingTimeInterval(-300)),
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
        now: Date = .now
    ) -> CodexBarWidgetSnapshot {
        switch result {
        case .success(let snapshots):
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
        case .error(let error):
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
        now: Date = .now
    ) -> CodexBarWidgetSnapshot {
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

        let summaries = providers.map { self.summary(for: $0, now: now) }
        let todayCost = summaries.compactMap(\.todayCostUSD).reduce(0, +)
        let thirtyDayCost = summaries.compactMap(\.thirtyDayCostUSD).reduce(0, +)
        let todayTokens = summaries.compactMap(\.tokensToday).reduce(0, +)
        let latestSyncAt = activeSnapshots.map(\.syncTimestamp).max()
        let maxUsage = summaries.compactMap(\.usagePercent).max()
        let errorCount = summaries.filter(\.isError).count

        let topProviders = summaries
            .sorted { lhs, rhs in
                let lhsScore = lhs.isError ? 1_000 + (lhs.usagePercent ?? 0) : (lhs.usagePercent ?? 0)
                let rhsScore = rhs.isError ? 1_000 + (rhs.usagePercent ?? 0) : (rhs.usagePercent ?? 0)
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
            providerCount: summaries.count,
            errorCount: errorCount,
            todayCostUSD: todayCost > 0 ? todayCost : nil,
            thirtyDayCostUSD: thirtyDayCost > 0 ? thirtyDayCost : nil,
            todayTokens: todayTokens > 0 ? todayTokens : nil,
            maxUsagePercent: maxUsage,
            topProviders: Array(topProviders.prefix(6)),
            message: nil,
            isStale: latestSyncAt.map { now.timeIntervalSince($0) > Self.staleInterval } ?? false)
    }

    private static func summary(
        for provider: ProviderUsageSnapshot,
        now: Date
    ) -> CodexBarWidgetProviderSummary {
        let today = provider.costSummary.map { self.todayTotals(from: $0, now: now) }
        let windows = provider.allRateWindows.map(\.usedPercent)
        let budgetPercent: Double? = provider.budget.flatMap { budget in
            guard budget.limitAmount > 0 else { return nil }
            return min(100, max(0, budget.usedAmount / budget.limitAmount * 100))
        }
        let usagePercent = (windows + [budgetPercent].compactMap(\.self)).max()
        let accountKey = provider.accountEmail ?? "_"
        return CodexBarWidgetProviderSummary(
            id: "\(provider.providerID)|\(accountKey)",
            providerName: provider.providerName,
            providerID: provider.providerID,
            loginMethod: provider.loginMethod,
            usagePercent: usagePercent,
            todayCostUSD: today?.costUSD,
            thirtyDayCostUSD: provider.costSummary?.last30DaysCostUSD,
            tokensToday: today?.tokens,
            isError: provider.isError,
            statusMessage: provider.statusMessage,
            lastUpdated: provider.lastUpdated)
    }

    private static func todayTotals(
        from summary: SyncCostSummary,
        now: Date
    ) -> (costUSD: Double?, tokens: Int?) {
        let dayKey = Self.dayKey(for: now)
        if let point = summary.daily.first(where: { $0.dayKey == dayKey }) {
            return (point.costUSD, point.totalTokens)
        }
        return (summary.sessionCostUSD, summary.sessionTokens)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
