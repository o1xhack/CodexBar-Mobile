import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Cost tab insight resolver")
struct CostTabInsightsResolverTests {
    private let now = Date()

    @Test(arguments: [true, false])
    func `Sparse ledger history completeness is independent of missing Today`(completed: Bool) throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let point = SyncDailyPoint(dayKey: "2026-10-01", costUSD: 8, totalTokens: 800, costIsKnown: true)
        let summary = SyncCostSummary(
            sessionCostUSD: nil, sessionTokens: nil, last30DaysCostUSD: 8, last30DaysTokens: 800,
            daily: [point], historyDays: 30, reportingPeriod: "rolling:30",
            sourceUpdatedAt: now, sourceDayKey: "2026-10-02", bucketTimeZoneIdentifier: "UTC",
            historyCoverageIsEstablished: completed)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Synthetic Ledger", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: now, costSummary: summary)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: now, deviceName: "Synthetic Mac", deviceID: "mac-A")
        let aggregation = CostLedgerAggregation(
            windowDays: 7, totalCostUSD: 8, totalTokens: 800, activeDayCount: 1,
            providerRollups: ["codex|_": CostLedgerProviderRollup(
                providerID: "codex", accountEmail: nil, totalCostUSD: 8, totalTokens: 800,
                dailyPoints: [point], modelBreakdowns: [], serviceBreakdowns: [])],
            dailyPoints: [point], modelMix: [], serviceMix: [])
        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: snapshot, ledgerAggregation: aggregation, isLedgerEnabled: true,
            isDemoMode: false, localHistoryClearedAt: nil, ledgerWindowDays: 7,
            now: now, calendar: calendar))

        #expect(insights.total30DayCost == 8)
        #expect(insights.hasIncompleteCostData == !completed)
        #expect(insights.historyCostIsLowerBound == !completed)
        #expect(!insights.providerRows[0].todayCostIsKnown)
        #expect(!insights.totalTodayCostIsKnown)
    }

    @Test
    func `Empty ledger after clear does not fall back to stale synced cost summary`() {
        let snapshot = SyncedUsageSnapshot(
            providers: [self.provider(cost: 12, tokens: 1200)],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: self.now.addingTimeInterval(60))

        #expect(insights == nil)
    }

    @Test
    func `Missing ledger after clear does not fall back to stale synced cost summary`() {
        let snapshot = SyncedUsageSnapshot(
            providers: [self.provider(cost: 12, tokens: 1200)],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: nil,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: self.now.addingTimeInterval(60),
            ledgerWindowDays: 90)

        #expect(insights == nil)
    }

    @Test
    func `Match Mac uses the synced reporting period even when local history is enabled`() throws {
        for period in ["month-to-date", "all"] {
            let summary = SyncCostSummary(
                sessionCostUSD: 12,
                sessionTokens: 1200,
                last30DaysCostUSD: 12,
                last30DaysTokens: 1200,
                daily: [SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
                    costUSD: 12,
                    totalTokens: 1200,
                    costIsKnown: true)],
                historyDays: 640,
                reportingPeriod: period,
                historyCoverageIsEstablished: true)
            let provider = ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.now,
                costSummary: summary)
            let snapshot = SyncedUsageSnapshot(
                providers: [provider],
                syncTimestamp: self.now,
                deviceName: "Mac",
                deviceID: "mac-A")

            let insights = try #require(CostTabInsightsResolver.make(
                snapshot: snapshot,
                ledgerAggregation: nil,
                isLedgerEnabled: true,
                isDemoMode: false,
                localHistoryClearedAt: self.now,
                ledgerWindowDays: 0))

            #expect(insights.historyDisplayTitle == summary.reportingPeriodDisplayTitle)
            #expect(insights.cwlWindowDays == nil)
        }
    }

    @Test
    func `Empty local ledger without clear uses scoped dated snapshot fallback`() {
        let snapshot = SyncedUsageSnapshot(
            providers: [self.provider(cost: 12, tokens: 1200)],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: nil)

        #expect(insights?.total30DayCost == 12)
    }

    @Test
    func `Snapshot insights preserve daily model and service breakdowns`() throws {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(
                    id: "codex",
                    name: "Codex",
                    cost: 8,
                    tokens: 800,
                    models: [SyncCostBreakdown(label: "codex-model", costUSD: 8)],
                    services: [SyncCostBreakdown(label: "codex-run", costUSD: 8)]),
                self.provider(
                    id: "claude",
                    name: "Claude",
                    cost: 12,
                    tokens: 1200,
                    models: [SyncCostBreakdown(label: "claude-model", costUSD: 12)],
                    services: [SyncCostBreakdown(label: "claude-api", costUSD: 12)]),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: nil,
            isLedgerEnabled: false,
            isDemoMode: false,
            localHistoryClearedAt: nil))

        #expect(insights.dailyPoints.count == 1)
        #expect(Set(insights.dailyPoints[0].modelBreakdowns.map(\.label)) == [
            "codex-model",
            "claude-model",
        ])
        #expect(insights.dailyPoints[0].modelBreakdowns.reduce(0) { $0 + $1.costUSD } == 20)
        #expect(Set(insights.dailyPoints[0].serviceBreakdowns.map(\.label)) == [
            "codex-run",
            "claude-api",
        ])
        #expect(insights.dailyPoints[0].serviceBreakdowns.reduce(0) { $0 + $1.costUSD } == 20)
    }

    @Test
    func `Snapshot insights exclude unavailable daily breakdown dollars`() throws {
        let unavailable = SyncDailyPoint(
            dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
            costUSD: 7,
            totalTokens: 700,
            modelBreakdowns: [.init(label: "unverified-model", costUSD: 7)],
            serviceBreakdowns: [.init(label: "unverified-service", costUSD: 7)],
            costIsKnown: false)
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(
                    id: "codex",
                    name: "Codex",
                    cost: 5,
                    tokens: 500,
                    models: [.init(label: "known-model", costUSD: 5)],
                    services: [.init(label: "known-service", costUSD: 5)]),
                self.provider(
                    id: "grok",
                    name: "Grok",
                    cost: 0,
                    tokens: 700,
                    daily: [unavailable]),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: nil,
            isLedgerEnabled: false,
            isDemoMode: false,
            localHistoryClearedAt: nil))

        #expect(insights.modelRows.map(\.label) == ["known-model"])
        #expect(insights.serviceRows.map(\.label) == ["known-service"])
        #expect(insights.dailyPoints.first?.costIsKnown == false)
        #expect(insights.dailyPoints.first?.modelBreakdowns.map(\.label) == ["known-model"])
        #expect(insights.dailyPoints.first?.serviceBreakdowns.map(\.label) == ["known-service"])
    }

    @Test
    func `Empty ledger after clear preserves synced budget rows`() {
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(
                    cost: 12,
                    tokens: 1200,
                    budget: SyncBudgetSnapshot(
                        usedAmount: 40,
                        limitAmount: 100,
                        currencyCode: "USD",
                        period: "Monthly",
                        resetsAt: nil)),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: self.now.addingTimeInterval(60))

        #expect(insights != nil)
        #expect(insights?.budgetRows.count == 1)
    }

    @Test
    func `Partial ledger after clear does not append missing providers from stale snapshots`() {
        let refreshed = self.provider(id: "codex", name: "Codex", cost: 8, tokens: 800)
        let stale = self.provider(id: "claude", name: "Claude", cost: 12, tokens: 1200)
        let snapshot = SyncedUsageSnapshot(
            providers: [refreshed, stale],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let aggregation = CostLedgerAggregation(
            windowDays: 90,
            totalCostUSD: 8,
            totalTokens: 800,
            activeDayCount: 1,
            providerRollups: [
                "codex|_": CostLedgerProviderRollup(
                    providerID: "codex",
                    accountEmail: nil,
                    totalCostUSD: 8,
                    totalTokens: 800,
                    dailyPoints: [
                        SyncDailyPoint(
                            dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
                            costUSD: 8,
                            totalTokens: 800,
                            modelBreakdowns: [],
                            serviceBreakdowns: [],
                            isEstimated: false),
                    ],
                    modelBreakdowns: [],
                    serviceBreakdowns: []),
            ],
            dailyPoints: [
                SyncDailyPoint(
                    dayKey: SyncCostSummary.iso8601DayKey(for: self.now),
                    costUSD: 8,
                    totalTokens: 800,
                    modelBreakdowns: [],
                    serviceBreakdowns: [],
                    isEstimated: false),
            ],
            modelMix: [],
            serviceMix: [])

        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: self.now.addingTimeInterval(60))

        #expect(insights?.total30DayCost == 8)
        #expect(insights?.providerRows.map(\.provider.providerID) == ["codex"])
    }

    @Test
    func `Partial ledger fallback contributes to daily and breakdown aggregates`() throws {
        let codexDay = self.syncDay(
            cost: 8,
            tokens: 800,
            models: [SyncCostBreakdown(label: "codex-model", costUSD: 8)],
            services: [SyncCostBreakdown(label: "codex-run", costUSD: 8)])
        let claude = self.provider(
            id: "claude",
            name: "Claude",
            cost: 12,
            tokens: 1200,
            models: [SyncCostBreakdown(label: "claude-model", costUSD: 12)],
            services: [SyncCostBreakdown(label: "claude-api", costUSD: 12)])
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(id: "codex", name: "Codex", cost: 8, tokens: 800),
                claude,
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let aggregation = CostLedgerAggregation(
            windowDays: 90,
            totalCostUSD: 8,
            totalTokens: 800,
            activeDayCount: 1,
            providerRollups: [
                "codex|_": CostLedgerProviderRollup(
                    providerID: "codex",
                    accountEmail: nil,
                    totalCostUSD: 8,
                    totalTokens: 800,
                    dailyPoints: [codexDay],
                    modelBreakdowns: [SyncCostBreakdown(label: "codex-model", costUSD: 8)],
                    serviceBreakdowns: [SyncCostBreakdown(label: "codex-run", costUSD: 8)]),
            ],
            dailyPoints: [codexDay],
            modelMix: [SyncCostBreakdown(label: "codex-model", costUSD: 8)],
            serviceMix: [SyncCostBreakdown(label: "codex-run", costUSD: 8)])

        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: nil))

        #expect(insights.total30DayCost == 20)
        #expect(insights.dailyPoints.reduce(0) { $0 + $1.costUSD } == 20)
        #expect(Set(insights.dailyPoints.flatMap(\.modelBreakdowns).map(\.label)) == [
            "codex-model",
            "claude-model",
        ])
        #expect(insights.dailyPoints.flatMap(\.modelBreakdowns).reduce(0) { $0 + $1.costUSD } == 20)
        #expect(Set(insights.dailyPoints.flatMap(\.serviceBreakdowns).map(\.label)) == [
            "codex-run",
            "claude-api",
        ])
        #expect(insights.dailyPoints.flatMap(\.serviceBreakdowns).reduce(0) { $0 + $1.costUSD } == 20)
        #expect(Set(insights.modelRows.map(\.label)) == ["codex-model", "claude-model"])
        #expect(insights.modelRows.reduce(0) { $0 + $1.amountUSD } == 20)
        #expect(Set(insights.serviceRows.map(\.label)) == ["codex-run", "claude-api"])
        #expect(insights.serviceRows.reduce(0) { $0 + $1.amountUSD } == 20)
    }

    @Test
    func `Short ledger windows count missing-provider daily fallback totals`() throws {
        let codexDay = self.syncDay(
            daysAgo: 0,
            cost: 2,
            tokens: 200,
            models: [SyncCostBreakdown(label: "codex-model", costUSD: 2)],
            services: [])
        let claudeRecentDay = self.syncDay(
            daysAgo: 1,
            cost: 6,
            tokens: 600,
            models: [SyncCostBreakdown(label: "claude-recent", costUSD: 6)],
            services: [])
        let claudeOldDay = self.syncDay(
            daysAgo: 10,
            cost: 10,
            tokens: 1000,
            models: [SyncCostBreakdown(label: "claude-old", costUSD: 10)],
            services: [])
        let snapshot = SyncedUsageSnapshot(
            providers: [
                self.provider(id: "codex", name: "Codex", cost: 2, tokens: 200),
                self.provider(
                    id: "claude",
                    name: "Claude",
                    cost: 16,
                    tokens: 1600,
                    daily: [claudeRecentDay, claudeOldDay]),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let aggregation = CostLedgerAggregation(
            windowDays: 7,
            totalCostUSD: 2,
            totalTokens: 200,
            activeDayCount: 1,
            providerRollups: [
                "codex|_": CostLedgerProviderRollup(
                    providerID: "codex",
                    accountEmail: nil,
                    totalCostUSD: 2,
                    totalTokens: 200,
                    dailyPoints: [codexDay],
                    modelBreakdowns: codexDay.modelBreakdowns,
                    serviceBreakdowns: []),
            ],
            dailyPoints: [codexDay],
            modelMix: codexDay.modelBreakdowns,
            serviceMix: [])

        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: nil))

        #expect(insights.total30DayCost == 8)
        #expect(insights.total30DayTokens == 800)
        #expect(insights.providerRows.first(where: { $0.provider.providerID == "claude" })?.thirtyDayCost == 6)
        #expect(insights.dailyPoints.reduce(0) { $0 + $1.costUSD } == 8)
        #expect(Set(insights.modelRows.map(\.label)) == ["codex-model", "claude-recent"])
    }

    @Test(arguments: [1, 7, 30, 90, 365], [false, true])
    func `Missing provider daily totals include qualified Today exactly once`(
        windowDays: Int, hasTodayRow: Bool) throws
    {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T02:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var points = [SyncDailyPoint(dayKey: "2026-10-01", costUSD: 4, totalTokens: 40, costIsKnown: true)]
        if hasTodayRow {
            points.append(SyncDailyPoint(dayKey: "2026-10-02", costUSD: 3, totalTokens: 30, costIsKnown: true))
        }
        let summary = SyncCostSummary(
            sessionCostUSD: 2, sessionTokens: 20,
            last30DaysCostUSD: 99, last30DaysTokens: 990,
            daily: points, historyDays: 30,
            sourceUpdatedAt: now, sourceDayKey: "2026-10-02", sessionDayKey: "2026-10-02",
            bucketTimeZoneIdentifier: "Asia/Tokyo", sessionCostIsKnown: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: now, costSummary: summary)
        let snapshot = SyncedUsageSnapshot(
            providers: [provider], syncTimestamp: now, deviceName: "Mac", deviceID: "mac-A")
        let insights = try self.resolveLocalInsights(
            aggregation: self.emptyAggregation(windowDays: windowDays), snapshot: snapshot,
            now: now, calendar: calendar)
        let todayCost = hasTodayRow ? 3.0 : 2.0
        let todayTokens = hasTodayRow ? 30 : 20
        let earlierCost = windowDays == 1 ? 0.0 : 4.0
        let earlierTokens = windowDays == 1 ? 0 : 40
        #expect(insights.total30DayCost == earlierCost + todayCost)
        #expect(insights.total30DayTokens == earlierTokens + todayTokens)
        #expect(insights.totalTodayCost == todayCost)
        #expect(insights.dailyPoints.reduce(0) { $0 + $1.costUSD } == earlierCost + todayCost)
        #expect(insights.dailyPoints.reduce(0) { $0 + $1.totalTokens } == earlierTokens + todayTokens)
        #expect(insights.dailyPoints.filter { $0.dayKey == "2026-10-01" }.count == 1)
        #expect(insights.dailyPoints.first(where: { $0.dayKey == "2026-10-01" })?.costUSD == todayCost)
    }

    @Test
    func `Stale session does not fill missing Today in local daily fallback`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z"))
        let summary = SyncCostSummary(
            sessionCostUSD: 2, sessionTokens: 20,
            last30DaysCostUSD: 99, last30DaysTokens: 990,
            daily: [SyncDailyPoint(dayKey: "2026-10-01", costUSD: 4, totalTokens: 40, costIsKnown: true)],
            sourceUpdatedAt: now, sourceDayKey: "2026-10-02", sessionDayKey: "2026-10-01",
            bucketTimeZoneIdentifier: "UTC", sessionCostIsKnown: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: now, costSummary: summary)
        let insights = try self.resolveLocalInsights(
            aggregation: self.emptyAggregation(windowDays: 7),
            snapshot: SyncedUsageSnapshot(providers: [provider], syncTimestamp: now,
                                          deviceName: "Mac", deviceID: "mac-A"),
            now: now)
        #expect(insights.total30DayCost == 4)
        #expect(insights.total30DayTokens == 40)
        #expect(insights.totalTodayCostIsKnown == false)
        #expect(insights.dailyPoints.count == 1)
    }

    @Test(arguments: [false, true])
    func `Legacy session requires a current producer observation before filling daily history`(
        isCurrentObservation: Bool) throws
    {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z"))
        let yesterday = now.addingTimeInterval(-86400)
        let summary = SyncCostSummary(
            sessionCostUSD: 2, sessionTokens: 20,
            last30DaysCostUSD: 99, last30DaysTokens: 990,
            daily: [SyncDailyPoint(dayKey: "2026-10-01", costUSD: 4, totalTokens: 40, costIsKnown: true)],
            bucketTimeZoneIdentifier: "UTC")
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: isCurrentObservation ? now : yesterday, costSummary: summary)
        let insights = try self.resolveLocalInsights(
            aggregation: self.emptyAggregation(windowDays: 7),
            snapshot: SyncedUsageSnapshot(providers: [provider], syncTimestamp: now,
                                          deviceName: "Mac", deviceID: "mac-A"),
            now: now)
        #expect(insights.total30DayCost == (isCurrentObservation ? 6 : 4))
        #expect(insights.total30DayTokens == (isCurrentObservation ? 60 : 40))
        #expect(insights.dailyPoints.count == (isCurrentObservation ? 2 : 1))
        #expect(insights.dailyPoints.contains { $0.dayKey == "2026-10-02" } == isCurrentObservation)
    }

    @Test(arguments: ["legacy", "valid", "invalid", "incomplete", "incomparable"], [false, true])
    func `Live daily fallback validates producer metadata without invalidating saved ledger`(
        metadata: String, hasSavedLedger: Bool) throws
    {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let points = (0..<7).map { offset in
            SyncDailyPoint(
                dayKey: SyncCostSummary.iso8601DayKey(for: now.addingTimeInterval(Double(-offset) * 86400)),
                costUSD: 2, totalTokens: 20, costIsKnown: true)
        }
        let summary = SyncCostSummary(
            sessionCostUSD: 2, sessionTokens: 20,
            last30DaysCostUSD: 14, last30DaysTokens: 140,
            daily: points, historyDays: 7,
            reportingPeriod: metadata == "legacy" ? nil : "rolling:7",
            sourceUpdatedAt: now,
            bucketTimeZoneIdentifier: metadata == "invalid" ? "Not/A-Time-Zone" :
                (metadata == "legacy" ? nil : "UTC"),
            historyCoverageIsEstablished: metadata == "incomplete" ? false : nil,
            historyWindowIsComparable: metadata == "incomparable" ? false : nil)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: now, costSummary: summary)
        let aggregation = CostLedgerAggregation(
            windowDays: 7, totalCostUSD: hasSavedLedger ? 14 : 0,
            totalTokens: hasSavedLedger ? 140 : 0, activeDayCount: hasSavedLedger ? 7 : 0,
            providerRollups: hasSavedLedger ? ["codex|_": CostLedgerProviderRollup(
                providerID: "codex", accountEmail: nil, totalCostUSD: 14, totalTokens: 140,
                dailyPoints: points, modelBreakdowns: [], serviceBreakdowns: [])] : [:],
            dailyPoints: hasSavedLedger ? points : [], modelMix: [], serviceMix: [])
        let insights = try self.resolveLocalInsights(
            aggregation: aggregation,
            snapshot: SyncedUsageSnapshot(providers: [provider], syncTimestamp: now,
                                          deviceName: "Mac", deviceID: "mac-A"),
            now: now, calendar: calendar)
        let isInvalidLiveSource = !hasSavedLedger && metadata == "invalid"
        #expect(insights.total30DayCost == (isInvalidLiveSource ? 0 : 14))
        #expect(insights.total30DayTokens == (isInvalidLiveSource ? 0 : 140))
        #expect(insights.total30DayCostIsKnown ==
            (hasSavedLedger || metadata == "legacy" || metadata == "valid"))
        #expect(insights.dailyPoints.count == (isInvalidLiveSource ? 0 : 7))
    }

    @Test(arguments: [1, 7, 30, 90, 365],
          ["session-only", "cost-and-tokens", "tokens-only", "unmatched"].flatMap { headline in
              [false, true].map { (headline, $0) }
          })
    func `Session-only Today fills history without replacing a matching period headline`(
        windowDays: Int, shape: (String, Bool)) throws
    {
        let (headline, hasLoadedAggregation) = shape
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let summary = SyncCostSummary(
            sessionCostUSD: 2, sessionTokens: 20,
            last30DaysCostUSD: headline == "cost-and-tokens" || headline == "unmatched" ? 17 : nil,
            last30DaysTokens: headline == "session-only" ? nil : 170,
            daily: [], historyDays: windowDays,
            reportingPeriod: headline == "unmatched" ? "all" : "rolling:\(windowDays)",
            sourceUpdatedAt: now, sourceDayKey: "2026-10-02", sessionDayKey: "2026-10-02",
            bucketTimeZoneIdentifier: "UTC", sessionCostIsKnown: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: now, costSummary: summary)
        let insights = try self.resolveLocalInsights(
            aggregation: hasLoadedAggregation ? self.emptyAggregation(windowDays: windowDays) : nil,
            snapshot: SyncedUsageSnapshot(providers: [provider], syncTimestamp: now,
                                          deviceName: "Mac", deviceID: "mac-A"),
            now: now, calendar: calendar, windowDays: windowDays)
        let useCostHeadline = headline == "cost-and-tokens"
        let useTokenHeadline = useCostHeadline || headline == "tokens-only"
        #expect(insights.total30DayCost == (useCostHeadline ? 17 : 2))
        #expect(insights.total30DayTokens == (useTokenHeadline ? 170 : 20))
        #expect(insights.total30DayCostIsKnown == (useCostHeadline || windowDays == 1))
        #expect(insights.totalTodayCost == 2)
        #expect(insights.providerRows.first?.thirtyDayCost == (useCostHeadline ? 17 : 2))
        #expect(insights.dailyPoints.count == 1)
        #expect(insights.dailyPoints.first?.costUSD == 2)
        #expect(insights.dailyPoints.first?.totalTokens == 20)
    }

    @Test(arguments: [1, 7, 30, 90, 365], [false, true])
    func `Complete headline distinguishes missing cost from explicit zero`(windowDays: Int, hasExplicitZero: Bool) throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z"))
        let summary = SyncCostSummary(
            sessionCostUSD: nil, sessionTokens: nil,
            last30DaysCostUSD: hasExplicitZero ? 0 : nil, last30DaysTokens: 170,
            daily: [], historyDays: windowDays, reportingPeriod: "rolling:\(windowDays)",
            sourceUpdatedAt: now, bucketTimeZoneIdentifier: "UTC",
            historyCoverageIsEstablished: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: now, costSummary: summary)
        let insights = try self.resolveLocalInsights(
            aggregation: self.emptyAggregation(windowDays: windowDays),
            snapshot: SyncedUsageSnapshot(providers: [provider], syncTimestamp: now,
                                          deviceName: "Mac", deviceID: "mac-A"),
            now: now)
        #expect(insights.total30DayCost == 0)
        #expect(insights.total30DayCostIsKnown == hasExplicitZero)
        #expect(insights.total30DayTokens == 170)
        #expect(insights.dailyPoints.isEmpty)
    }

    @Test
    func `Ledger refresh signature changes when the local day changes`() {
        let snapshot = SyncedUsageSnapshot(
            providers: [self.provider(cost: 8, tokens: 800)],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let today = CostLedgerRefreshSignature.make(
            isEnabled: true,
            windowDays: 90,
            activeDeviceIDs: ["mac-A"],
            snapshots: [snapshot],
            clearTombstone: 0,
            currentDayKey: "2026-07-07")
        let tomorrow = CostLedgerRefreshSignature.make(
            isEnabled: true,
            windowDays: 90,
            activeDeviceIDs: ["mac-A"],
            snapshots: [snapshot],
            clearTombstone: 0,
            currentDayKey: "2026-07-08")

        #expect(today != tomorrow)
        #expect(today.hasPrefix("2026-07-07|"))
        #expect(tomorrow.hasPrefix("2026-07-08|"))
    }

    @Test
    func `Cost refresh clock advances at a producer midnight before reader midnight`() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let beforeTokyoMidnight = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 22,
            hour: 14,
            minute: 59,
            second: 59)))
        let afterTokyoMidnight = beforeTokyoMidnight.addingTimeInterval(2)

        let beforeKey = CostLedgerRefreshClock.refreshKey(
            now: beforeTokyoMidnight,
            sourceTimeZoneIdentifiers: ["Asia/Tokyo"])
        let afterKey = CostLedgerRefreshClock.refreshKey(
            now: afterTokyoMidnight,
            sourceTimeZoneIdentifiers: ["Asia/Tokyo"])

        #expect(beforeKey.contains("Asia/Tokyo=2026-08-22"))
        #expect(afterKey.contains("Asia/Tokyo=2026-08-23"))
        #expect(beforeKey != afterKey)
    }

    @Test
    func `Cost refresh clock sleeps only until the earliest producer boundary`() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 22,
            hour: 14,
            minute: 59,
            second: 30)))

        let nanoseconds = CostLedgerRefreshClock.nanosecondsUntilNextDayBoundary(
            now: now,
            sourceTimeZoneIdentifiers: ["Asia/Tokyo"])

        // The clock adds a one-second cushion after the boundary.
        #expect(nanoseconds == 31_000_000_000)
    }

    @Test
    func `Cost refresh clock restarts when the reader time zone changes`() {
        let sourceTimeZones: Set = ["Asia/Tokyo", "UTC"]
        let losAngeles = CostLedgerRefreshClock.restartKey(
            sourceTimeZoneIdentifiers: sourceTimeZones,
            readerTimeZoneIdentifier: "America/Los_Angeles")
        let newYork = CostLedgerRefreshClock.restartKey(
            sourceTimeZoneIdentifiers: sourceTimeZones,
            readerTimeZoneIdentifier: "America/New_York")

        #expect(losAngeles == "America/Los_Angeles|Asia/Tokyo|UTC")
        #expect(newYork == "America/New_York|Asia/Tokyo|UTC")
        #expect(losAngeles != newYork)
    }

    @Test
    func `Cost refresh clock reads only valid producer time zones`() {
        func provider(id: String, timeZoneIdentifier: String?) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: id,
                providerName: id,
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.now,
                costSummary: SyncCostSummary(
                    sessionCostUSD: 1,
                    sessionTokens: 1,
                    last30DaysCostUSD: 1,
                    last30DaysTokens: 1,
                    daily: [],
                    bucketTimeZoneIdentifier: timeZoneIdentifier))
        }

        let snapshot = SyncedUsageSnapshot(
            providers: [
                provider(id: "utc", timeZoneIdentifier: "UTC"),
                provider(id: "tokyo", timeZoneIdentifier: "Asia/Tokyo"),
                provider(id: "invalid", timeZoneIdentifier: "Not/A-Time-Zone"),
                provider(id: "legacy", timeZoneIdentifier: nil),
            ],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        #expect(CostLedgerRefreshClock.sourceTimeZoneIdentifiers(in: [snapshot]) == [
            "Asia/Tokyo",
            "UTC",
        ])
    }

    @Test
    func `Ledger refresh signature changes when provider identities change`() {
        let codex = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "codex@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 8,
                last30DaysTokens: 800,
                daily: [],
                historyDays: 30))
        let claude = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: "claude@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 8,
                last30DaysTokens: 800,
                daily: [],
                historyDays: 30))
        let codexSnapshot = SyncedUsageSnapshot(
            providers: [codex],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")
        let claudeSnapshot = SyncedUsageSnapshot(
            providers: [claude],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let codexSignature = CostLedgerRefreshSignature.make(
            isEnabled: true,
            windowDays: 90,
            activeDeviceIDs: ["mac-A"],
            snapshots: [codexSnapshot],
            clearTombstone: 0,
            currentDayKey: "2026-07-07")
        let claudeSignature = CostLedgerRefreshSignature.make(
            isEnabled: true,
            windowDays: 90,
            activeDeviceIDs: ["mac-A"],
            snapshots: [claudeSnapshot],
            clearTombstone: 0,
            currentDayKey: "2026-07-07")

        #expect(codexSignature != claudeSignature)
        #expect(codexSignature.contains("mac-A:codex|codex@example.com"))
        #expect(claudeSignature.contains("mac-A:claude|claude@example.com"))
    }

    @Test
    func `Ledger refresh signature changes for an independent provider publication`() {
        let provider = self.provider(cost: 8, tokens: 800)
        let first = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A",
            providerPublicationTimestamps: [
                SyncedUsageSnapshot.providerPublicationKey(for: provider): self.now,
            ])
        let second = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A",
            providerPublicationTimestamps: [
                SyncedUsageSnapshot.providerPublicationKey(for: provider): self.now.addingTimeInterval(60),
            ])

        func signature(_ snapshot: SyncedUsageSnapshot) -> String {
            CostLedgerRefreshSignature.make(
                isEnabled: true,
                windowDays: 30,
                activeDeviceIDs: ["mac-A"],
                snapshots: [snapshot],
                clearTombstone: 0,
                currentDayKey: "2026-07-07")
        }

        #expect(signature(first) != signature(second))
    }

    @Test
    func `summary only after clear cannot fill a different local history window`() {
        let clearTime = self.now
        let freshSummaryOnly = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: clearTime.addingTimeInterval(60),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: nil,
                last30DaysCostUSD: 14, last30DaysTokens: 1400, daily: [], historyDays: 30))
        let snapshot = SyncedUsageSnapshot(
            providers: [freshSummaryOnly],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: clearTime)

        #expect(insights?.total30DayCost == 0)
        #expect(insights?.providerRows.map(\.provider.providerID) == ["claude"])
        #expect(insights?.dailyPoints.isEmpty == true)
    }

    @Test
    func `Fresh session after clear fills Today without restoring an unrelated period`() throws {
        let now = Date()
        let summary = SyncCostSummary(
            sessionCostUSD: 2, sessionTokens: 20,
            last30DaysCostUSD: 99, last30DaysTokens: 990,
            daily: [], historyDays: 30, reportingPeriod: "rolling:30",
            sourceUpdatedAt: now,
            bucketTimeZoneIdentifier: "UTC", sessionCostIsKnown: true)
        let provider = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: now, costSummary: summary)
        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: SyncedUsageSnapshot(providers: [provider], syncTimestamp: now,
                                          deviceName: "Mac", deviceID: "mac-A"),
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true, isDemoMode: false,
            localHistoryClearedAt: now.addingTimeInterval(-60)))
        #expect(insights.total30DayCost == 2)
        #expect(insights.total30DayTokens == 20)
        #expect(insights.totalTodayCost == 2)
        #expect(insights.total30DayCostIsKnown == false)
        #expect(insights.dailyPoints.count == 1)
    }

    @Test
    func `Fresh usage refresh cannot restore a summary whose cost source predates clear`() {
        let clearTime = self.now
        let staleCost = self.provider(
            id: "claude",
            name: "Claude",
            cost: 14,
            tokens: 1400,
            lastUpdated: clearTime.addingTimeInterval(60),
            includeDaily: false,
            sourceUpdatedAt: clearTime.addingTimeInterval(-60))
        let snapshot = SyncedUsageSnapshot(
            providers: [staleCost],
            syncTimestamp: self.now,
            deviceName: "Mac",
            deviceID: "mac-A")

        let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: self.emptyAggregation(windowDays: 90),
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: clearTime)

        #expect(insights == nil)
    }

    private func resolveLocalInsights(
        aggregation: CostLedgerAggregation?,
        snapshot: SyncedUsageSnapshot,
        now: Date,
        calendar: Calendar = .current,
        windowDays: Int? = nil) throws -> CostDashboardInsights
    {
        try #require(CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: true,
            isDemoMode: false,
            localHistoryClearedAt: nil,
            ledgerWindowDays: windowDays ?? aggregation?.windowDays,
            now: now,
            calendar: calendar))
    }

    private func emptyAggregation(windowDays: Int) -> CostLedgerAggregation {
        CostLedgerAggregation(
            windowDays: windowDays,
            totalCostUSD: 0,
            totalTokens: 0,
            activeDayCount: 0,
            providerRollups: [:],
            dailyPoints: [],
            modelMix: [],
            serviceMix: [])
    }

    private func provider(
        id: String = "codex",
        name: String = "Codex",
        cost: Double,
        tokens: Int,
        budget: SyncBudgetSnapshot? = nil,
        lastUpdated: Date? = nil,
        includeDaily: Bool = true,
        sourceUpdatedAt: Date? = nil) -> ProviderUsageSnapshot
    {
        self.provider(
            id: id,
            name: name,
            cost: cost,
            tokens: tokens,
            budget: budget,
            lastUpdated: lastUpdated,
            includeDaily: includeDaily,
            sourceUpdatedAt: sourceUpdatedAt,
            models: [],
            services: [])
    }

    private func provider(
        id: String,
        name: String,
        cost: Double,
        tokens: Int,
        daily: [SyncDailyPoint]) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: cost,
                last30DaysTokens: tokens,
                daily: daily,
                isEstimated: false,
                historyDays: 30))
    }

    private func provider(
        id: String,
        name: String,
        cost: Double,
        tokens: Int,
        budget: SyncBudgetSnapshot? = nil,
        lastUpdated: Date? = nil,
        includeDaily: Bool = true,
        sourceUpdatedAt: Date? = nil,
        models: [SyncCostBreakdown],
        services: [SyncCostBreakdown]) -> ProviderUsageSnapshot
    {
        let daily = self.syncDay(
            cost: cost,
            tokens: tokens,
            models: models,
            services: services)
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated ?? self.now,
            costSummary: SyncCostSummary(
                sessionCostUSD: cost,
                sessionTokens: tokens,
                last30DaysCostUSD: cost,
                last30DaysTokens: tokens,
                daily: includeDaily ? [daily] : [],
                isEstimated: false,
                historyDays: 30,
                sourceUpdatedAt: sourceUpdatedAt),
            budget: budget)
    }

    private func syncDay(
        daysAgo: Int = 0,
        cost: Double,
        tokens: Int,
        models: [SyncCostBreakdown],
        services: [SyncCostBreakdown]) -> SyncDailyPoint
    {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: self.now) ?? self.now
        return SyncDailyPoint(
            dayKey: SyncCostSummary.iso8601DayKey(for: date),
            costUSD: cost,
            totalTokens: tokens,
            modelBreakdowns: models,
            serviceBreakdowns: services,
            isEstimated: false)
    }
}
