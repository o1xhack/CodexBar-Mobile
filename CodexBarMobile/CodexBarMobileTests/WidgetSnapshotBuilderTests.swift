import CodexBarSync
import Foundation
import Testing

@testable import CodexBarMobile

@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
    @Test("builds overview metrics from real sync snapshots")
    func buildsOverviewMetrics() {
        let now = Self.date("2026-06-28T12:00:00Z")
        let snapshot = SyncedUsageSnapshot(
            providers: [
                Self.provider(
                    id: "codex",
                    name: "Codex",
                    email: "dev@example.com",
                    usage: 81,
                    todayCost: 7.25,
                    tokens: 45_000,
                    updated: now.addingTimeInterval(-120)),
                Self.provider(
                    id: "claude",
                    name: "Claude",
                    email: "dev@example.com",
                    usage: 33,
                    todayCost: 4.10,
                    tokens: 12_000,
                    updated: now.addingTimeInterval(-240)),
            ],
            syncTimestamp: now.addingTimeInterval(-180),
            deviceName: "MacBook Pro",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(widget.state == .loaded)
        #expect(widget.deviceCount == 1)
        #expect(widget.providerCount == 2)
        #expect(widget.maxUsagePercent == 81)
        #expect(widget.todayCostUSD == 11.35)
        #expect(widget.todayTokens == 57_000)
        #expect(widget.topProviders.first?.providerName == "Codex")
        #expect(widget.isStale == false)
    }

    @Test("sums local-cost provider accounts across devices")
    func sumsLocalCostProviderAccountsAcrossDevices() {
        let now = Self.date("2026-06-28T12:00:00Z")
        let older = Self.provider(
            id: "codex",
            name: "Codex",
            email: "dev@example.com",
            usage: 20,
            todayCost: 1,
            tokens: 100,
            updated: now.addingTimeInterval(-600))
        let newer = Self.provider(
            id: "codex",
            name: "Codex",
            email: "dev@example.com",
            usage: 88,
            todayCost: 2,
            tokens: 200,
            updated: now.addingTimeInterval(-60))

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: [
                SyncedUsageSnapshot(
                    providers: [older],
                    syncTimestamp: now.addingTimeInterval(-500),
                    deviceName: "MacBook Pro",
                    deviceID: "device-a"),
                SyncedUsageSnapshot(
                    providers: [newer],
                    syncTimestamp: now.addingTimeInterval(-50),
                    deviceName: "Mac Studio",
                    deviceID: "device-b"),
            ],
            now: now)

        #expect(widget.providerCount == 1)
        #expect(widget.maxUsagePercent == 88)
        #expect(abs((widget.todayCostUSD ?? 0) - 3) < 0.001)
        #expect(widget.todayTokens == 300)
    }

    @Test("uses account-level latest cost without double counting")
    func usesAccountLevelLatestCostWithoutDoubleCounting() {
        let now = Self.date("2026-06-28T12:00:00Z")
        let older = Self.provider(
            id: "openrouter",
            name: "OpenRouter",
            email: "dev@example.com",
            usage: 20,
            todayCost: 1,
            tokens: 100,
            updated: now.addingTimeInterval(-600))
        let newer = Self.provider(
            id: "openrouter",
            name: "OpenRouter",
            email: "dev@example.com",
            usage: 88,
            todayCost: 2,
            tokens: 200,
            updated: now.addingTimeInterval(-60))

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: [
                SyncedUsageSnapshot(
                    providers: [older],
                    syncTimestamp: now.addingTimeInterval(-500),
                    deviceName: "MacBook Pro",
                    deviceID: "device-a"),
                SyncedUsageSnapshot(
                    providers: [newer],
                    syncTimestamp: now.addingTimeInterval(-50),
                    deviceName: "Mac Studio",
                    deviceID: "device-b"),
            ],
            now: now)

        #expect(widget.providerCount == 1)
        #expect(widget.maxUsagePercent == 88)
        #expect(abs((widget.todayCostUSD ?? 0) - 2) < 0.001)
        #expect(widget.todayTokens == 200)
    }

    @Test("matches cost dashboard today totals for multi-device Codex data")
    func matchesCostDashboardTodayTotalsForMultiDeviceCodexData() {
        let now = Self.date("2026-07-01T22:30:00Z")
        let deviceA = Self.provider(
            id: "codex",
            name: "Codex",
            email: "msxiao113@gmail.com",
            usage: 25,
            todayCost: 20.59,
            tokens: 10_400_000,
            updated: now.addingTimeInterval(-300))
        let deviceB = Self.provider(
            id: "codex",
            name: "Codex",
            email: "msxiao113@gmail.com",
            usage: 25,
            todayCost: 80.53,
            tokens: 113_700_000,
            updated: now.addingTimeInterval(-60))

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: [
                SyncedUsageSnapshot(
                    providers: [deviceA],
                    syncTimestamp: now.addingTimeInterval(-280),
                    deviceName: "MacBook Pro",
                    deviceID: "device-a"),
                SyncedUsageSnapshot(
                    providers: [deviceB],
                    syncTimestamp: now.addingTimeInterval(-40),
                    deviceName: "Mac Studio",
                    deviceID: "device-b"),
            ],
            now: now)

        #expect(widget.providerCount == 1)
        #expect(abs((widget.todayCostUSD ?? 0) - 101.12) < 0.001)
        #expect(widget.todayTokens == 124_100_000)
        #expect(abs((widget.topProviders.first?.todayCostUSD ?? 0) - 101.12) < 0.001)
    }

    @Test("keeps Today Cost widget totals in parity with the Cost dashboard")
    func keepsTodayCostWidgetTotalsInParityWithCostDashboard() throws {
        let now = Self.localNoonToday()
        let codexDeviceA = Self.provider(
            id: "codex",
            name: "Codex",
            email: "msxiao113@gmail.com",
            usage: 25,
            todayCost: 20.59,
            tokens: 10_400_000,
            updated: now.addingTimeInterval(-300))
        let codexDeviceB = Self.provider(
            id: "codex",
            name: "Codex",
            email: "msxiao113@gmail.com",
            usage: 25,
            todayCost: 80.53,
            tokens: 113_700_000,
            updated: now.addingTimeInterval(-60))
        let olderAccountProvider = Self.provider(
            id: "openrouter",
            name: "OpenRouter",
            email: "dev@example.com",
            usage: 10,
            todayCost: 1,
            tokens: 100,
            updated: now.addingTimeInterval(-400))
        let newerAccountProvider = Self.provider(
            id: "openrouter",
            name: "OpenRouter",
            email: "dev@example.com",
            usage: 11,
            todayCost: 2,
            tokens: 200,
            updated: now.addingTimeInterval(-30))
        let snapshots = [
            SyncedUsageSnapshot(
                providers: [codexDeviceA, olderAccountProvider],
                syncTimestamp: now.addingTimeInterval(-280),
                deviceName: "MacBook Pro",
                deviceID: "device-a"),
            SyncedUsageSnapshot(
                providers: [codexDeviceB, newerAccountProvider],
                syncTimestamp: now.addingTimeInterval(-40),
                deviceName: "Mac Studio",
                deviceID: "device-b"),
        ]

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: snapshots, now: now)
        let mergedSnapshot = try #require(CloudSyncReader.mergeSnapshots(snapshots))
        let costInsights = CostDashboardInsights(snapshot: mergedSnapshot)
        let costDashboardTodayTokens = costInsights.providerRows
            .compactMap { $0.provider.costSummary?.todayTotals(now: now).tokens }
            .reduce(0, +)

        #expect(abs(costInsights.totalTodayCost - 103.12) < 0.001)
        #expect(costDashboardTodayTokens == 124_100_200)
        #expect(abs((widget.todayCostUSD ?? 0) - costInsights.totalTodayCost) < 0.001)
        #expect(widget.todayTokens == costDashboardTodayTokens)
    }

    @Test("applies provider account linkages before building widget totals")
    func appliesProviderAccountLinkagesBeforeBuildingWidgetTotals() {
        let now = Self.date("2026-07-01T22:30:00Z")
        let legacyProvider = Self.provider(
            id: "claude",
            name: "Claude",
            email: nil,
            usage: 19,
            todayCost: 1.49,
            tokens: 1_000,
            updated: now.addingTimeInterval(-300))
        let identifiedProvider = Self.provider(
            id: "claude",
            name: "Claude",
            email: nil,
            usage: 22,
            todayCost: 2_638.98,
            tokens: 2_000,
            updated: now.addingTimeInterval(-60),
            accountIdentities: ["claude:account:team"])
        let snapshots = [
            SyncedUsageSnapshot(
                providers: [legacyProvider],
                syncTimestamp: now.addingTimeInterval(-280),
                deviceName: "MacBook Pro",
                deviceID: "device-a"),
            SyncedUsageSnapshot(
                providers: [identifiedProvider],
                syncTimestamp: now.addingTimeInterval(-40),
                deviceName: "Mac Studio",
                deviceID: "device-b"),
        ]
        let linkage = ProviderAccountLinkage(
            providerID: "claude",
            linkedIdentifiers: [
                "claude:legacy-no-identity",
                "claude:account:team",
            ],
            confirmedAt: now.addingTimeInterval(-20),
            confirmedFromDeviceID: "iphone-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: snapshots,
            providerLinkages: [linkage],
            now: now)

        #expect(widget.providerCount == 1)
        #expect(abs((widget.todayCostUSD ?? 0) - 2_640.47) < 0.001)
        #expect(widget.todayTokens == 3_000)
        #expect(abs((widget.topProviders.first?.todayCostUSD ?? 0) - 2_640.47) < 0.001)
    }

    @Test("excludes archived device lifecycle records from widget totals")
    func excludesArchivedDeviceLifecycleRecordsFromWidgetTotals() {
        let now = Self.date("2026-07-01T22:30:00Z")
        let archivedProvider = Self.provider(
            id: "codex",
            name: "Codex",
            email: "dev@example.com",
            usage: 25,
            todayCost: 101.12,
            tokens: 124_100_000,
            updated: now.addingTimeInterval(-300))
        let activeProvider = Self.provider(
            id: "codex",
            name: "Codex",
            email: "dev@example.com",
            usage: 27,
            todayCost: 20.59,
            tokens: 10_400_000,
            updated: now.addingTimeInterval(-60))
        let archivedDevice = SyncedUsageSnapshot(
            providers: [archivedProvider],
            syncTimestamp: now.addingTimeInterval(-280),
            deviceName: "Old Mac",
            deviceID: "device-old")
        let activeDevice = SyncedUsageSnapshot(
            providers: [activeProvider],
            syncTimestamp: now.addingTimeInterval(-40),
            deviceName: "Mac Studio",
            deviceID: "device-active")
        let archive = DeviceLifecycleEvent(
            kind: .archive,
            primaryDeviceID: "device-old",
            confirmedAt: now.addingTimeInterval(-20),
            confirmedFromDeviceID: "iphone-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: [archivedDevice, activeDevice],
            deviceLifecycleEvents: [archive],
            now: now)

        #expect(widget.deviceCount == 1)
        #expect(widget.providerCount == 1)
        #expect(abs((widget.todayCostUSD ?? 0) - 20.59) < 0.001)
        #expect(widget.todayTokens == 10_400_000)
    }

    @Test("uses KVS fallback snapshot when CloudKit has no device data")
    func usesKVSFallbackSnapshotWhenCloudKitHasNoDeviceData() {
        let now = Self.date("2026-07-01T22:30:00Z")
        let fallbackProvider = Self.provider(
            id: "codex",
            name: "Codex",
            email: "msxiao113@gmail.com",
            usage: 44,
            todayCost: 53.35,
            tokens: 56_500_000,
            updated: now.addingTimeInterval(-120))
        let fallbackSnapshot = SyncedUsageSnapshot(
            providers: [fallbackProvider],
            syncTimestamp: now.addingTimeInterval(-90),
            deviceName: "Mac Studio",
            deviceID: "device-fallback")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: .empty,
            fallbackKVSSnapshot: fallbackSnapshot,
            now: now)

        #expect(widget.state == .loaded)
        #expect(widget.deviceCount == 1)
        #expect(widget.providerCount == 1)
        #expect(abs((widget.todayCostUSD ?? 0) - 53.35) < 0.001)
        #expect(widget.todayTokens == 56_500_000)
        #expect(widget.message == nil)
    }

    @Test("keeps KVS fallback totals visible when CloudKit returns an error")
    func keepsKVSFallbackTotalsVisibleWhenCloudKitReturnsError() {
        let now = Self.date("2026-07-01T22:30:00Z")
        let fallbackProvider = Self.provider(
            id: "codex",
            name: "Codex",
            email: "msxiao113@gmail.com",
            usage: 44,
            todayCost: 53.35,
            tokens: 56_500_000,
            updated: now.addingTimeInterval(-120))
        let fallbackSnapshot = SyncedUsageSnapshot(
            providers: [fallbackProvider],
            syncTimestamp: now.addingTimeInterval(-90),
            deviceName: "Mac Studio",
            deviceID: "device-fallback")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: .error(.notAuthenticated),
            fallbackKVSSnapshot: fallbackSnapshot,
            now: now)

        #expect(widget.state == .loaded)
        #expect(widget.isStale)
        #expect(widget.message == "iCloud account not signed in")
        #expect(abs((widget.todayCostUSD ?? 0) - 53.35) < 0.001)
        #expect(widget.todayTokens == 56_500_000)
    }

    @Test("preserves configured widget mode and color style")
    func preservesConfiguredWidgetModeAndColorStyle() {
        let intent = CodexBarWidgetConfigurationIntent(
            mode: .todayCost,
            colorStyle: .colorful)

        #expect(intent.mode == .todayCost)
        #expect(intent.colorStyle == .colorful)
    }

    @Test("surfaces no-data, stale, and error states")
    func stateCoverage() {
        let now = Self.date("2026-06-28T12:00:00Z")
        #expect(CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [], now: now).state == .noData)

        let stale = SyncedUsageSnapshot(
            providers: [
                Self.provider(
                    id: "openrouter",
                    name: "OpenRouter",
                    email: nil,
                    usage: 91,
                    todayCost: nil,
                    tokens: nil,
                    updated: now.addingTimeInterval(-8 * 60 * 60),
                    isError: true),
            ],
            syncTimestamp: now.addingTimeInterval(-8 * 60 * 60),
            deviceName: "MacBook Pro",
            deviceID: "device-a")
        let staleWidget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [stale], now: now)
        #expect(staleWidget.isStale)
        #expect(staleWidget.errorCount == 1)

        let errorWidget = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: .error(.notAuthenticated),
            now: now)
        #expect(errorWidget.state == .error)
        #expect(errorWidget.message == "iCloud account not signed in")
    }

    private static func provider(
        id: String,
        name: String,
        email: String?,
        usage: Double,
        todayCost: Double?,
        tokens: Int?,
        updated: Date,
        isError: Bool = false,
        accountIdentities: [String]? = nil
    ) -> ProviderUsageSnapshot {
        let dayKey = SyncCostSummary.iso8601DayKeyForTest(updated)
        let costSummary = todayCost.map { cost in
            SyncCostSummary(
                sessionCostUSD: cost,
                sessionTokens: tokens,
                last30DaysCostUSD: cost * 10,
                last30DaysTokens: tokens.map { $0 * 10 },
                daily: [
                    SyncDailyPoint(dayKey: dayKey, costUSD: cost, totalTokens: tokens ?? 0),
                ])
        }
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: SyncRateWindow(
                label: "Session",
                usedPercent: usage,
                windowMinutes: 180,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: "Pro",
            statusMessage: isError ? "Rate limit approaching" : nil,
            isError: isError,
            lastUpdated: updated,
            costSummary: costSummary,
            accountIdentities: accountIdentities)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func localNoonToday() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }
}

private extension SyncCostSummary {
    static func iso8601DayKeyForTest(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
