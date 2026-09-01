import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
    @Test
    func `decodes legacy widget cache without lower-bound fields`() throws {
        let now = Self.date("2026-06-28T12:00:00Z")
        let provider = CodexBarWidgetProviderSummary(
            id: "codex:dev@example.com",
            providerName: "Codex",
            providerID: "codex",
            loginMethod: "Pro",
            usagePercent: 81,
            todayCostUSD: 7.25,
            todayCostIsLowerBound: true,
            thirtyDayCostUSD: 72.50,
            tokensToday: 45000,
            isError: false,
            statusMessage: nil,
            lastUpdated: now)
        let current = CodexBarWidgetSnapshot(
            state: .loaded,
            generatedAt: now,
            latestSyncAt: now,
            deviceCount: 1,
            providerCount: 1,
            errorCount: 0,
            todayCostUSD: 7.25,
            todayCostIsLowerBound: true,
            thirtyDayCostUSD: 72.50,
            todayTokens: 45000,
            maxUsagePercent: 81,
            topProviders: [provider],
            message: nil,
            isStale: false)

        let encoded = try JSONEncoder().encode(current)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "todayCostIsLowerBound")
        var providers = try #require(legacy["topProviders"] as? [[String: Any]])
        providers[0].removeValue(forKey: "todayCostIsLowerBound")
        legacy["topProviders"] = providers

        let decoded = try JSONDecoder().decode(
            CodexBarWidgetSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy))

        #expect(decoded.todayCostUSD == 7.25)
        #expect(decoded.todayCostIsLowerBound == nil)
        #expect(decoded.topProviders.first?.todayCostIsLowerBound == nil)
    }

    @Test
    func `builds overview metrics from real sync snapshots`() {
        let now = Self.date("2026-06-28T12:00:00Z")
        let snapshot = SyncedUsageSnapshot(
            providers: [
                Self.provider(
                    id: "codex",
                    name: "Codex",
                    email: "dev@example.com",
                    usage: 81,
                    todayCost: 7.25,
                    tokens: 45000,
                    updated: now.addingTimeInterval(-120)),
                Self.provider(
                    id: "claude",
                    name: "Claude",
                    email: "dev@example.com",
                    usage: 33,
                    todayCost: 4.10,
                    tokens: 12000,
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
        #expect(widget.todayTokens == 57000)
        #expect(widget.topProviders.first?.providerName == "Codex")
        #expect(widget.isStale == false)
    }

    @Test
    func `sums local-cost provider accounts across devices`() {
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

    @Test
    func `uses account-level latest cost without double counting`() {
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

    @Test
    func `keeps provider-level cost in totals but excludes its synthetic widget row`() {
        let now = Self.localNoonToday()
        let account = ProviderUsageSnapshot(
            providerID: "openrouter",
            providerName: "OpenRouter",
            primary: SyncRateWindow(
                label: "API key",
                usedPercent: 40,
                windowMinutes: 1440,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API key",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            accountRecordKey: "token-personal")
        let managementCost = ProviderUsageSnapshot(
            providerID: "openrouter",
            providerName: "OpenRouter",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 7,
                sessionTokens: 700,
                last30DaysCostUSD: 70,
                last30DaysTokens: 7000,
                daily: [SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKeyForTest(now),
                    costUSD: 7,
                    totalTokens: 700,
                    costIsKnown: true)],
                sourceUpdatedAt: now,
                historyCoverageIsEstablished: true),
            accountRecordKey: ProviderUsageSnapshot.openRouterManagementCostRecordKey)
        let snapshot = SyncedUsageSnapshot(
            providers: [account, managementCost],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(widget.providerCount == 1)
        #expect(widget.topProviders.count == 1)
        #expect(widget.topProviders.first?.providerName == "OpenRouter")
        #expect(widget.maxUsagePercent == 40)
        #expect(widget.todayCostUSD == 7)
        #expect(widget.thirtyDayCostUSD == 70)
        #expect(widget.todayTokens == 700)
    }

    @Test
    func `matches cost dashboard today totals for multi-device Codex data`() {
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

    @Test
    func `keeps Today Cost widget totals in parity with the Cost dashboard`() throws {
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

    @Test
    func `applies provider account linkages before building widget totals`() {
        let now = Self.date("2026-07-01T22:30:00Z")
        let legacyProvider = Self.provider(
            id: "claude",
            name: "Claude",
            email: nil,
            usage: 19,
            todayCost: 1.49,
            tokens: 1000,
            updated: now.addingTimeInterval(-300))
        let identifiedProvider = Self.provider(
            id: "claude",
            name: "Claude",
            email: nil,
            usage: 22,
            todayCost: 2638.98,
            tokens: 2000,
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
        #expect(abs((widget.todayCostUSD ?? 0) - 2640.47) < 0.001)
        #expect(widget.todayTokens == 3000)
        #expect(abs((widget.topProviders.first?.todayCostUSD ?? 0) - 2640.47) < 0.001)
    }

    @Test
    func `excludes archived device lifecycle records from widget totals`() {
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

    @Test
    func `uses KVS fallback snapshot when CloudKit has no device data`() {
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

    @Test
    func `keeps KVS fallback totals visible when CloudKit returns an error`() {
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

    @Test
    func `preserves configured widget mode and color style`() {
        let intent = CodexBarWidgetConfigurationIntent(
            mode: .todayCost,
            colorStyle: .colorful)

        #expect(intent.mode == .todayCost)
        #expect(intent.colorStyle == .colorful)
    }

    @Test
    func `surfaces no-data, stale, and error states`() {
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

    @Test
    func `suppresses partial history totals that widgets cannot qualify`() {
        let now = Self.localNoonToday()
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "dev@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 1,
                sessionTokens: 100,
                last30DaysCostUSD: 12.34,
                last30DaysTokens: 1000,
                daily: [],
                coverage: SyncCostCoverage(priced: 9, unpriced: 1, unmetered: 0, estimated: 0),
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(widget.thirtyDayCostUSD == nil)
        #expect(widget.topProviders.first?.thirtyDayCostUSD == nil)
        #expect(widget.todayCostUSD == nil)
    }

    @Test
    func `suppresses compact history totals whose cost source stopped before Today`() throws {
        let now = Self.localNoonToday()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let summary = SyncCostSummary(
            sessionCostUSD: 2,
            sessionTokens: 200,
            last30DaysCostUSD: 12.34,
            last30DaysTokens: 1000,
            daily: [],
            sourceUpdatedAt: yesterday,
            sourceDayKey: SyncCostSummary.iso8601DayKeyForTest(yesterday),
            sessionDayKey: SyncCostSummary.iso8601DayKeyForTest(yesterday),
            sessionCostIsKnown: true,
            historyCoverageIsEstablished: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "dev@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: summary)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(summary.completeHistoryCostUSD == nil)
        #expect(widget.thirtyDayCostUSD == nil)
        #expect(widget.topProviders.first?.thirtyDayCostUSD == nil)
    }

    @Test
    func `suppresses aggregate widget cost when any provider is incomplete`() {
        let now = Self.localNoonToday()
        let todayKey = SyncCostSummary.iso8601DayKeyForTest(now)
        let complete = ProviderUsageSnapshot(
            providerID: "openai",
            providerName: "OpenAI",
            primary: nil,
            secondary: nil,
            accountEmail: "complete@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 2,
                sessionTokens: 200,
                last30DaysCostUSD: 20,
                last30DaysTokens: 2000,
                daily: [SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: 2,
                    totalTokens: 200,
                    costIsKnown: true)],
                historyCoverageIsEstablished: true))
        let incomplete = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "partial@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: 100,
                last30DaysCostUSD: 4,
                last30DaysTokens: 1000,
                daily: [SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: 0,
                    totalTokens: 100,
                    costIsKnown: false)],
                coverage: SyncCostCoverage(priced: 1, unpriced: 1, unmetered: 0, estimated: 0),
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [complete, incomplete],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(widget.todayCostUSD == nil)
        #expect(widget.thirtyDayCostUSD == nil)
        #expect(widget.todayTokens == 300)
        #expect(widget.topProviders.first(where: { $0.providerID == "openai" })?.todayCostUSD == 2)
        #expect(widget.topProviders.first(where: { $0.providerID == "codex" })?.todayCostUSD == nil)
    }

    @Test
    func `keeps known Today cost while historical coverage is incomplete`() {
        let now = Self.localNoonToday()
        let todayKey = SyncCostSummary.iso8601DayKeyForTest(now)
        let macBook = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 7.37,
                sessionTokens: 7_000,
                last30DaysCostUSD: 619.55,
                last30DaysTokens: 600_000,
                daily: [SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: 7.37,
                    totalTokens: 7_000,
                    costIsKnown: true)],
                coverage: SyncCostCoverage(priced: 99, unpriced: 1, unmetered: 0, estimated: 0),
                sourceUpdatedAt: now,
                sourceDayKey: todayKey,
                sessionDayKey: todayKey,
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: false))
        let studio = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 193.58,
                sessionTokens: 193_000,
                last30DaysCostUSD: 9_503.87,
                last30DaysTokens: 9_000_000,
                daily: [SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: 193.58,
                    totalTokens: 193_000,
                    costIsKnown: true)],
                coverage: SyncCostCoverage(priced: 999, unpriced: 1, unmetered: 0, estimated: 0),
                sourceUpdatedAt: now,
                sourceDayKey: todayKey,
                sessionDayKey: todayKey,
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: false))
        let snapshots = [
            SyncedUsageSnapshot(
                providers: [macBook],
                syncTimestamp: now,
                deviceName: "MacBook",
                deviceID: "device-a"),
            SyncedUsageSnapshot(
                providers: [studio],
                syncTimestamp: now,
                deviceName: "Studio",
                deviceID: "device-b"),
        ]

        let merged = CloudSyncReader.mergeSnapshots(snapshots)
        let insights = merged.map { CostDashboardInsights(snapshot: $0, now: now) }
        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: snapshots, now: now)
        let share = insights.map { ShareCardData(insights: $0, period: .today) }

        #expect(abs((insights?.totalTodayCost ?? 0) - 200.95) < 0.0001)
        #expect(insights?.totalTodayCostIsKnown == true)
        #expect(insights?.totalTodayCostIsLowerBound == true)
        #expect(insights?.hasIncompleteCostData == true)
        #expect(insights?.providerRows.first?.todayCostDisplayValue == "≥$200.95")
        #expect(share?.todayCostIsKnown == true)
        #expect(share?.todayCostIsLowerBound == true)
        #expect(share?.todayCostDisplayValue == "≥$200.95")
        #expect(abs((widget.todayCostUSD ?? 0) - 200.95) < 0.0001)
        #expect(widget.todayCostIsLowerBound == true)
        #expect(widget.topProviders.allSatisfy { $0.todayCostIsLowerBound == true })
        #expect(widget.thirtyDayCostUSD == nil)
    }

    @Test
    func `does not qualify known Today when only older history has gaps`() {
        let now = Self.localNoonToday()
        let todayKey = SyncCostSummary.iso8601DayKeyForTest(now)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 7.37,
                sessionTokens: 7_000,
                last30DaysCostUSD: 619.55,
                last30DaysTokens: 600_000,
                daily: [SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: 7.37,
                    totalTokens: 7_000,
                    costIsKnown: true)],
                coverage: SyncCostCoverage(priced: 99, unpriced: 1, unmetered: 0, estimated: 0),
                sourceUpdatedAt: now,
                sourceDayKey: todayKey,
                sessionDayKey: todayKey,
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: true))
        let snapshots = [SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "MacBook",
            deviceID: "device-a")]

        let merged = CloudSyncReader.mergeSnapshots(snapshots)
        let insights = merged.map { CostDashboardInsights(snapshot: $0, now: now) }
        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: snapshots, now: now)

        #expect(insights?.totalTodayCostIsKnown == true)
        #expect(insights?.totalTodayCostIsLowerBound == false)
        #expect(insights?.hasIncompleteCostData == true)
        #expect(insights?.providerRows.first?.todayCostDisplayValue == "$7.37")
        #expect(widget.todayCostUSD == 7.37)
        #expect(widget.todayCostIsLowerBound == nil)
        #expect(widget.topProviders.first?.todayCostIsLowerBound == nil)
        #expect(widget.thirtyDayCostUSD == nil)
    }

    /// Exhaustive binary ordering from docs/ios-sync-compatibility-testing.md:
    /// bit 3 = Mac A, bit 2 = Mac B, bit 1 = iPhone A, bit 0 = iPhone B.
    /// The hotfix does not change the Mac payload, so old/new writer fixtures
    /// intentionally share the production wire shape. The reader bit models
    /// published build 196 versus candidate build 197 Today presentation.
    @Test(arguments: Array(0..<16))
    func `2 Mac x 2 iPhone Today cost old-new matrix`(mask: Int) throws {
        let now = Self.localNoonToday()
        let macANew = mask & 0b1000 != 0
        let macBNew = mask & 0b0100 != 0
        let iPhoneANew = mask & 0b0010 != 0
        let iPhoneBNew = mask & 0b0001 != 0

        let writers = try [
            Self.todayCostMatrixSnapshot(
                deviceID: "matrix-mac-a",
                deviceName: "Matrix Mac A",
                cost: 7.37,
                tokens: 7_000,
                isNew: macANew,
                now: now),
            Self.todayCostMatrixSnapshot(
                deviceID: "matrix-mac-b",
                deviceName: "Matrix Mac B",
                cost: 193.58,
                tokens: 193_000,
                isNew: macBNew,
                now: now),
        ].map(Self.roundTripMatrixWriter)

        let phoneA = try Self.readTodayCostMatrixPhone(
            isNew: iPhoneANew,
            snapshots: writers,
            now: now)
        let phoneB = try Self.readTodayCostMatrixPhone(
            isNew: iPhoneBNew,
            snapshots: writers,
            now: now)

        #expect(phoneA.deviceCount == 2)
        #expect(phoneB.deviceCount == 2)
        #expect(phoneA.deviceIDs == ["matrix-mac-a", "matrix-mac-b"])
        #expect(phoneB.deviceIDs == ["matrix-mac-a", "matrix-mac-b"])
        #expect(phoneA.providerCount == 1)
        #expect(phoneB.providerCount == 1)
        #expect(phoneA.providerIdentityKeys == ["codex|matrix@example.com"])
        #expect(phoneB.providerIdentityKeys == ["codex|matrix@example.com"])
        #expect(abs(phoneA.rawTodayCost - 200.95) < 0.0001)
        #expect(abs(phoneB.rawTodayCost - 200.95) < 0.0001)
        #expect(phoneA.todayDisplay == (iPhoneANew ? "≥$200.95" : "—"))
        #expect(phoneB.todayDisplay == (iPhoneBNew ? "≥$200.95" : "—"))
        #expect(phoneA.widgetDisplay == (iPhoneANew ? "≥$200.95" : "—"))
        #expect(phoneB.widgetDisplay == (iPhoneBNew ? "≥$200.95" : "—"))
        #expect(phoneA.shareDisplay == (iPhoneANew ? "≥$200.95" : "—"))
        #expect(phoneB.shareDisplay == (iPhoneBNew ? "≥$200.95" : "—"))

        // Each phone builds and decodes an independent local widget snapshot.
        // Same-version readers must converge even when writer bits differ.
        if iPhoneANew == iPhoneBNew {
            #expect(phoneA == phoneB)
        }
    }

    @Test
    func `suppresses Today subtotal when a modern provider has no current-day cost`() throws {
        let now = Self.localNoonToday()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let complete = Self.provider(
            id: "openai",
            name: "OpenAI",
            email: "complete@example.com",
            usage: 20,
            todayCost: 2,
            tokens: 200,
            updated: now)
        let unresolved = ProviderUsageSnapshot(
            providerID: "mistral",
            providerName: "Mistral",
            primary: nil,
            secondary: nil,
            accountEmail: "partial@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 5,
                last30DaysTokens: 500,
                daily: [SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKeyForTest(yesterday),
                    costUSD: 5,
                    totalTokens: 500,
                    costIsKnown: true)],
                historyCoverageIsEstablished: false))
        let snapshot = SyncedUsageSnapshot(
            providers: [complete, unresolved],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(widget.todayCostUSD == nil)
        #expect(widget.topProviders.first(where: { $0.providerID == "openai" })?.todayCostUSD == 2)
        #expect(widget.topProviders.first(where: { $0.providerID == "mistral" })?.todayCostUSD == nil)
    }

    @Test
    func `suppresses Today subtotal from an explicitly stale cost source`() throws {
        let now = Self.localNoonToday()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let complete = Self.provider(
            id: "openai",
            name: "OpenAI",
            email: "complete@example.com",
            usage: 20,
            todayCost: 2,
            tokens: 200,
            updated: now)
        let stale = ProviderUsageSnapshot(
            providerID: "mistral",
            providerName: "Mistral",
            primary: nil,
            secondary: nil,
            accountEmail: "stale@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 5,
                sessionTokens: 500,
                last30DaysCostUSD: 5,
                last30DaysTokens: 500,
                daily: [],
                sourceUpdatedAt: yesterday,
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [complete, stale],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(widget.todayCostUSD == nil)
        #expect(widget.topProviders.first(where: { $0.providerID == "openai" })?.todayCostUSD == 2)
        #expect(widget.topProviders.first(where: { $0.providerID == "mistral" })?.todayCostUSD == nil)
    }

    @Test
    func `uses the producer bucket timezone when selecting the widget Today row`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-22T00:30:00Z"))
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "dev@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 3,
                last30DaysTokens: 300,
                daily: [SyncDailyPoint(
                    dayKey: "2026-08-22",
                    costUSD: 3,
                    totalTokens: 300,
                    costIsKnown: true)],
                sourceUpdatedAt: now,
                sourceDayKey: "2026-08-22",
                bucketTimeZoneIdentifier: "UTC",
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)

        #expect(widget.todayCostUSD == 3)
        #expect(widget.todayTokens == 300)
        #expect(widget.topProviders.first?.todayCostUSD == 3)
    }

    @Test
    func `history freshness reuses the widget reference instant`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-16T08:00:00Z"))
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 3,
            last30DaysTokens: 300,
            daily: [SyncDailyPoint(
                dayKey: "2026-07-16",
                costUSD: 3,
                totalTokens: 300,
                costIsKnown: true)],
            sourceUpdatedAt: now,
            sourceDayKey: "2026-07-16",
            bucketTimeZoneIdentifier: "UTC",
            historyCoverageIsEstablished: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "dev@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: summary)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "device-a")

        #expect(!summary.hasIncompleteHistoricalCostCoverage(at: now))
        #expect(summary.completeHistoryCostUSD(at: now) == 3)
        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [snapshot], now: now)
        #expect(widget.todayCostUSD == 3)
        #expect(widget.thirtyDayCostUSD == 3)
        #expect(widget.topProviders.first?.thirtyDayCostUSD == 3)
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
        accountIdentities: [String]? = nil) -> ProviderUsageSnapshot
    {
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

    private struct LegacyWidgetSnapshot: Decodable {
        let todayCostUSD: Double?
        let topProviders: [LegacyWidgetProviderSummary]
    }

    private struct LegacyWidgetProviderSummary: Decodable {
        let todayCostUSD: Double?
    }

    private struct TodayCostMatrixPhoneResult: Equatable {
        let deviceCount: Int
        let deviceIDs: [String]
        let providerCount: Int
        let providerIdentityKeys: [String]
        let rawTodayCost: Double
        let todayDisplay: String
        let widgetDisplay: String
        let shareDisplay: String
    }

    private static func todayCostMatrixSnapshot(
        deviceID: String,
        deviceName: String,
        cost: Double,
        tokens: Int,
        isNew: Bool,
        now: Date) -> SyncedUsageSnapshot
    {
        let todayKey = SyncCostSummary.iso8601DayKeyForTest(now)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "matrix@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: cost,
                sessionTokens: tokens,
                last30DaysCostUSD: cost * 10,
                last30DaysTokens: tokens * 10,
                daily: [SyncDailyPoint(
                    dayKey: todayKey,
                    costUSD: cost,
                    totalTokens: tokens,
                    costIsKnown: true)],
                coverage: SyncCostCoverage(priced: 10, unpriced: 1, unmetered: 0, estimated: 0),
                sourceUpdatedAt: now,
                sourceDayKey: todayKey,
                sessionDayKey: todayKey,
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: false))
        return SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "\(deviceName) \(isNew ? "candidate" : "published")",
            deviceID: deviceID,
            appVersion: "0.56.0.1",
            mobileVersion: "1.23.0")
    }

    private static func roundTripMatrixWriter(_ snapshot: SyncedUsageSnapshot) throws -> SyncedUsageSnapshot {
        let encoder = CloudSyncConstants.makeJSONEncoder()
        let decoder = CloudSyncConstants.makeJSONDecoder()
        return try decoder.decode(SyncedUsageSnapshot.self, from: encoder.encode(snapshot))
    }

    private static func readTodayCostMatrixPhone(
        isNew: Bool,
        snapshots: [SyncedUsageSnapshot],
        now: Date) throws -> TodayCostMatrixPhoneResult
    {
        let merged = try #require(CloudSyncReader.mergeSnapshots(snapshots))
        let rawTodayCost = merged.providers.compactMap { provider in
            provider.costSummary?.daily.first(where: {
                $0.dayKey == provider.costSummary?.costDayKey(for: now)
            })?.costUSD
        }.reduce(0, +)

        guard isNew else {
            // Build 196 treated whole-history incompleteness as Today unknown.
            let hasIncompleteHistory = merged.providers.compactMap(\.costSummary).contains {
                $0.hasIncompleteHistoricalCostCoverage(at: now)
            }
            #expect(hasIncompleteHistory)
            return TodayCostMatrixPhoneResult(
                deviceCount: snapshots.count,
                deviceIDs: snapshots.compactMap(\.deviceID).sorted(),
                providerCount: merged.providers.count,
                providerIdentityKeys: merged.providers.map {
                    "\($0.providerID)|\($0.accountEmail ?? "_")"
                }.sorted(),
                rawTodayCost: rawTodayCost,
                todayDisplay: "—",
                widgetDisplay: "—",
                shareDisplay: "—")
        }

        let insights = CostDashboardInsights(snapshot: merged, now: now)
        let share = ShareCardData(insights: insights, period: .today)
        let widget = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: snapshots, now: now)
        let widgetDisplay = widget.todayCostUSD.map {
            "\(widget.todayCostIsLowerBound == true ? "≥" : "")\(CostFormatting.usd($0))"
        } ?? "—"

        // Candidate widget snapshots remain decodable by the published model;
        // the additive qualifier is ignored rather than causing data loss or a
        // crash. The published binary cannot render the new qualifier, which
        // remains a documented rollback-only residual risk.
        let encodedWidget = try JSONEncoder().encode(widget)
        let legacyWidget = try JSONDecoder().decode(LegacyWidgetSnapshot.self, from: encodedWidget)
        #expect(abs((legacyWidget.todayCostUSD ?? 0) - 200.95) < 0.0001)
        #expect(legacyWidget.topProviders.allSatisfy { $0.todayCostUSD != nil })

        return TodayCostMatrixPhoneResult(
            deviceCount: snapshots.count,
            deviceIDs: snapshots.compactMap(\.deviceID).sorted(),
            providerCount: merged.providers.count,
            providerIdentityKeys: merged.providers.map {
                "\($0.providerID)|\($0.accountEmail ?? "_")"
            }.sorted(),
            rawTodayCost: rawTodayCost,
            todayDisplay: "\(insights.totalTodayCostIsLowerBound ? "≥" : "")\(CostFormatting.usd(insights.totalTodayCost))",
            widgetDisplay: widgetDisplay,
            shareDisplay: share.todayCostDisplayValue)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func localNoonToday() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }
}

extension SyncCostSummary {
    fileprivate static func iso8601DayKeyForTest(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
