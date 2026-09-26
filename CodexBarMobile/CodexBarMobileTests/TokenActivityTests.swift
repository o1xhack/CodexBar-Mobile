import CodexBarSync
import Foundation
import SwiftData
import Testing
import UIKit
@testable import CodexBarMobile

@Suite("Token Activity data semantics")
struct TokenActivityTests {
    @Test func `High daily usage retains distinct colors despite a single extreme outlier`() {
        let values = [20, 30, 40, 50, 60, 70, 80, 9000].map { $0 * 1_000_000 }
        let scale = TokenActivityColorScale(values: values)
        #expect(Set(values.map(scale.intensity)).count == 4)
        #expect(scale.intensity(0) == 0)
        #expect(scale.intensity(20_000_000) < scale.intensity(80_000_000))
        #expect(TokenActivityColorScale(values: [0, 0]).intensity(0) == 0)
        #expect(TokenActivityColorScale(values: [5, 5, 5]).intensity(5) == 0.25)
    }

    @Test func `Catch up publications invalidate token history even when usage and device timestamps stay fixed`() {
        let now = Date(timeIntervalSince1970: 1_789_084_800)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now)
        func snapshot(publication: Date) -> SyncedUsageSnapshot {
            SyncedUsageSnapshot(
                providers: [provider],
                syncTimestamp: now,
                deviceName: "Fixture Mac",
                deviceID: "fixture-mac",
                providerPublicationTimestamps: [SyncedUsageSnapshot.providerPublicationKey(for: provider): publication])
        }
        let old = snapshot(publication: now)
        let catchUp = snapshot(publication: now.addingTimeInterval(60))
        #expect(old.syncTimestamp == catchUp.syncTimestamp)
        #expect(old.providers.first?.lastUpdated == catchUp.providers.first?.lastUpdated)
        #expect(TokenActivity.sourceRevision([old]) != TokenActivity.sourceRevision([catchUp]))
        #expect(TokenActivity.sourceRevision([old, catchUp]) == TokenActivity.sourceRevision([catchUp, old]))
    }

    @Test func `Extreme synced counters do not overflow daily token combination`() {
        let points = TokenActivity.combine([
            SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: Int.max),
            SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: 1),
        ])
        #expect(points.first?.totalTokens == Int.max)
    }

    @Test func `Confirmed zero token history keeps the Cost entry point reachable without the ledger`() throws {
        let now = Date()
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                daily: [SyncDailyPoint(
                    dayKey: TokenActivity.dayKey(now, calendar: Calendar(identifier: .gregorian)),
                    costUSD: 0,
                    totalTokens: 0,
                    costIsKnown: false,
                    tokenCountIsKnown: true)]))
        let snapshot = SyncedUsageSnapshot(providers: [provider], syncTimestamp: now, deviceName: "Fixture Mac")
        let insights = try #require(CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: nil,
            isLedgerEnabled: false,
            isDemoMode: false,
            localHistoryClearedAt: nil))
        #expect(insights.providerRows.count == 1)
        #expect(insights.total30DayCostIsKnown == false)
        let series = TokenActivity.series(providers: [provider], rollups: nil, referenceDate: now)
        #expect(series.count == 1)
        #expect(TokenActivity.knownTokens(series.first?.days.first) == 0)
    }

    @Test func `A yearly activity window excludes padding across every weekday`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = Date(timeIntervalSince1970: 1_789_084_800)
        for offset in 0..<7 {
            let reference = try #require(calendar.date(byAdding: .day, value: offset, to: start))
            let window = TokenActivity.window(referenceDate: reference, calendar: calendar)
            #expect(calendar.dateComponents([.day], from: window.lowerBound, to: window.upperBound).day == 364)
            #expect(window.contains(window.lowerBound))
            #expect(window.contains(window.upperBound))
            #expect(!window.contains(window.lowerBound.addingTimeInterval(-1)))
            #expect(!window.contains(window.upperBound.addingTimeInterval(86400)))
        }
    }

    private func fixtureProvider(summary: SyncCostSummary? = nil) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 0),
            costSummary: summary)
    }

    @Test func `Producer midnight invalidates history while reader day and publications stay fixed`() throws {
        let formatter = ISO8601DateFormatter()
        let before = try #require(formatter.date(from: "2026-09-11T14:59:00Z"))
        let after = try #require(formatter.date(from: "2026-09-11T15:01:00Z"))
        var reader = Calendar(identifier: .gregorian)
        reader.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let provider = self.fixtureProvider(summary: SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: nil,
            last30DaysTokens: nil,
            daily: [SyncDailyPoint(dayKey: "2026-09-11", costUSD: 0, totalTokens: 100)],
            bucketTimeZoneIdentifier: "Asia/Tokyo"))
        let source = SyncedUsageSnapshot(providers: [provider], syncTimestamp: before, deviceName: "Fixture Mac")
        #expect(TokenActivity.dayKey(before, calendar: reader) == TokenActivity.dayKey(after, calendar: reader))
        #expect(TokenActivity.dayRevision(
            providers: [provider], snapshots: [source], referenceDate: before, readerCalendar: reader)
            != TokenActivity.dayRevision(
                providers: [provider], snapshots: [source], referenceDate: after, readerCalendar: reader))
        #expect(TokenActivity.dayRevision(
            providers: [], snapshots: [source], referenceDate: before, readerCalendar: reader)
            != TokenActivity.dayRevision(
                providers: [], snapshots: [source], referenceDate: after, readerCalendar: reader))
        #expect(TokenActivity.snapshotDays(provider.costSummary, referenceDate: before, readerTimeZone: reader.timeZone)
            .first?.dayKey == "2026-09-11")
        #expect(TokenActivity.snapshotDays(provider.costSummary, referenceDate: after, readerTimeZone: reader.timeZone)
            .first?.dayKey == "2026-09-10")
    }

    @Test func `All aggregate surfaces preserve complete zero unknown and lower bound semantics`() {
        let provider = self.fixtureProvider()
        let key = "2026-09-11"
        let known = TokenActivitySeries(provider: provider, days: [
            SyncDailyPoint(dayKey: key, costUSD: 0, totalTokens: 100, tokenCountIsKnown: true),
        ])
        let unknown = TokenActivitySeries(provider: provider, days: [
            SyncDailyPoint(dayKey: key, costUSD: 0, totalTokens: 999, tokenCountIsKnown: false),
        ])
        let partial = TokenActivitySeries(
            provider: provider,
            days: [SyncDailyPoint(dayKey: key, costUSD: 0, totalTokens: 100, tokenCountIsKnown: false)],
            hasLedgerCounts: true)
        let zero = TokenActivitySeries(provider: provider, days: [
            SyncDailyPoint(dayKey: key, costUSD: 0, totalTokens: 0, tokenCountIsKnown: true),
        ])
        #expect(TokenActivity.total([zero]) == TokenActivityTotal(value: 0, isLowerBound: false))
        #expect(TokenActivity.total([unknown]).value == nil)
        #expect(TokenActivity.dailyTotals([known, partial])[key]
            == TokenActivityTotal(value: 200, isLowerBound: true))
        #expect(TokenActivity.dailyTotals([known, zero])[key]
            == TokenActivityTotal(value: 100, isLowerBound: false))
        #expect(TokenActivity.dailyTotals([unknown])[key]?.value == nil)
        #expect(TokenActivity.dailyTotals([zero])[key]?.value == 0)
        #expect(TokenActivity.total([known], dayKey: "2026-09-10").value == nil)
        for day in [nil, key] {
            #expect(TokenActivity.total([known, unknown], dayKey: day)
                == TokenActivityTotal(value: 100, isLowerBound: true))
            #expect(TokenActivity.total([partial], dayKey: day).text == "≥100")
            #expect(TokenActivity.total([known], dayKey: day).text == "100")
        }
    }

    @Test func `Unknown and absent token counts differ from confirmed zero`() {
        #expect(TokenActivity.knownTokens(nil) == nil)
        #expect(TokenActivity.knownTokens(SyncDailyPoint(
            dayKey: "2026-09-10",
            costUSD: 0,
            totalTokens: 0,
            tokenCountIsKnown: false)) == nil)
        #expect(TokenActivity.knownTokens(SyncDailyPoint(
            dayKey: "2026-09-10",
            costUSD: 0,
            totalTokens: 0,
            tokenCountIsKnown: true)) == 0)
    }

    @Test func `Heatmap share projection preserves window totals and splits a year without overlap`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-09-11T19:00:00Z"))
        let provider = self.fixtureProvider()
        let series = TokenActivitySeries(provider: provider, days: [
            SyncDailyPoint(dayKey: "2026-09-09", costUSD: 0, totalTokens: 100, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: 0, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: "2026-09-11", costUSD: 0, totalTokens: 200, tokenCountIsKnown: true),
        ])
        let short = HeatmapShareData(
            series: [series],
            sourceTitle: "Codex",
            window: .days90,
            color: .purple,
            referenceDate: referenceDate,
            calendar: calendar)
        #expect(short.days.count == 90)
        #expect(short.days.last?.dayKey == "2026-09-11")
        #expect(short.total == TokenActivityTotal(value: 300, isLowerBound: true))
        #expect(short.activeDays == TokenActivityTotal(value: 2, isLowerBound: true))
        #expect(short.peak == TokenActivityTotal(value: 200, isLowerBound: true))
        #expect(short.calendarBlocks.count == 1)

        let year = HeatmapShareData(
            series: [series],
            sourceTitle: "Codex",
            window: .days365,
            color: .purple,
            referenceDate: referenceDate,
            calendar: calendar)
        let flattened = year.calendarBlocks.flatMap(\.self)
        #expect(year.calendarBlocks.count == 2)
        #expect(flattened.count == 365)
        #expect(Set(flattened.map(\.dayKey)).count == 365)
        #expect(flattened.map(\.dayKey) == year.days.map(\.dayKey))
    }

    @Test func `Heatmap share totals saturate across separate days`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-09-11T19:00:00Z"))
        let series = TokenActivitySeries(provider: self.fixtureProvider(), days: [
            SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: Int.max, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: "2026-09-11", costUSD: 0, totalTokens: 1, tokenCountIsKnown: true),
        ])

        let heatmap = HeatmapShareData(
            series: [series],
            sourceTitle: "Codex",
            window: .days90,
            color: .purple,
            referenceDate: referenceDate,
            calendar: calendar)

        #expect(heatmap.total.value == Int.max)
    }

    @Test func `Heatmap share uses Gregorian synced keys with a non Gregorian system calendar`() throws {
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-09-11T19:00:00Z"))
        let series = TokenActivitySeries(provider: self.fixtureProvider(), days: [
            SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: 100, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: "2026-09-11", costUSD: 0, totalTokens: 200, tokenCountIsKnown: true),
        ])

        let heatmap = HeatmapShareData(
            series: [series],
            sourceTitle: "Codex",
            window: .days90,
            color: .purple,
            referenceDate: referenceDate,
            calendar: buddhistCalendar)

        #expect(heatmap.days.last?.dayKey == "2026-09-11")
        #expect(heatmap.total == TokenActivityTotal(value: 300, isLowerBound: true))
        #expect(heatmap.activeDays == TokenActivityTotal(value: 2, isLowerBound: true))
    }

    @Test @MainActor func `Heatmap share title preserves the selected duplicate account`() {
        func series(
            email: String?,
            loginMethod: String? = nil,
            tint: String? = nil,
            accountRecordKey: String? = nil) -> TokenActivitySeries
        {
            TokenActivitySeries(provider: ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: email,
                loginMethod: loginMethod,
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(timeIntervalSince1970: 0),
                accountRecordKey: accountRecordKey,
                providerIconTintHex: tint), days: [])
        }

        let personal = series(email: "personal@example.com")
        let work = series(email: "work@example.com")

        #expect(CostShareSheet
            .heatmapSourceTitle(for: personal.id, in: [personal, work]) == "Codex · personal@example.com")
        #expect(CostShareSheet.heatmapSourceTitle(for: nil, in: [personal, work]) == String(localized: "All Providers"))

        let oauth = series(email: nil, loginMethod: "OAuth", accountRecordKey: "oauth")
        let team = series(email: nil, loginMethod: "Team", accountRecordKey: "team")
        #expect(CostShareSheet.heatmapSourceTitle(for: oauth.id, in: [oauth, team]) == "Codex · OAuth")
        #expect(CostShareSheet.heatmapSourceTitle(for: team.id, in: [oauth, team]) == "Codex · Team")

        let secondOAuth = series(email: nil, loginMethod: "OAuth", accountRecordKey: "oauth-second")
        #expect(CostShareSheet.heatmapSourceTitle(for: secondOAuth.id, in: [oauth, secondOAuth])
            == "Codex · " + String.localizedStringWithFormat(String(localized: "Account %lld"), 2))

        let customTint = series(email: "tint@example.com", tint: "#D044A7")
        let color = UIColor(CostShareSheet.heatmapColor(for: customTint))
        for style in [UIUserInterfaceStyle.light, .dark] {
            let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var red = CGFloat.zero
            var green = CGFloat.zero
            var blue = CGFloat.zero
            var alpha = CGFloat.zero
            #expect(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            let luminance = ProviderColorPalette.relativeLuminance(red: red, green: green, blue: blue)
            #expect(style == .dark ? luminance >= 0.239 : luminance <= 0.181)
            #expect(red > green && blue > green)
            #expect(abs(alpha - 1) < 0.001)
        }

        #expect(CostShareSheet.usesSideBySideLayout(width: 700, dynamicTypeSize: .large))
        #expect(!CostShareSheet.usesSideBySideLayout(width: 700, dynamicTypeSize: .accessibility1))
        #expect(!CostShareSheet.usesSideBySideLayout(width: 699, dynamicTypeSize: .large))
    }

    @Test func `Known tokens remain available without a monetary cost`() {
        let point = SyncDailyPoint(
            dayKey: "2026-09-10",
            costUSD: 0,
            totalTokens: 1234,
            costIsKnown: false,
            tokenCountIsKnown: true)
        #expect(TokenActivity.knownTokens(point) == 1234)
        #expect(TokenActivity.intensity(1234) == 0.25)
    }

    @Test func `Unknown contributions cannot turn a daily total into a confirmed complete value`() {
        let points = TokenActivity.combine([
            SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: 100),
            SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: 0, tokenCountIsKnown: false),
        ])
        #expect(points.count == 1)
        #expect(points[0].totalTokens == 100)
        #expect(points[0].tokenCountIsKnown == false)
    }

    @Test func `Cleared or unmatched ledger never falls back to the current snapshot`() {
        let now = Date(timeIntervalSince1970: 1_789_084_800)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "test@example.invalid",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                daily: [
                    SyncDailyPoint(
                        dayKey: TokenActivity.dayKey(
                            now,
                            calendar: Calendar(identifier: .gregorian)),
                        costUSD: 0,
                        totalTokens: 100,
                        costIsKnown: false),
                ]))
        #expect(TokenActivity.series(providers: [provider], rollups: [], referenceDate: now).isEmpty)
        #expect(TokenActivity.series(providers: [provider], rollups: nil, referenceDate: now).count == 1)
    }

    @Test func `Intensity thresholds stay fixed across chart reloads`() {
        #expect([0, 99999, 100_000, 999_999, 1_000_000, 9_999_999, 10_000_000].map(TokenActivity.intensity) == [
            0,
            0.25,
            0.5,
            0.5,
            0.75,
            0.75,
            1,
        ])
    }

    @Test func `Snapshot window excludes old and future rows and maps producer today to reader today`() {
        let now = Date(timeIntervalSince1970: 1_789_084_800)
        let summary = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: nil,
            last30DaysTokens: nil,
            daily: [
                SyncDailyPoint(dayKey: "2026-09-10", costUSD: 0, totalTokens: 100),
                SyncDailyPoint(dayKey: "2026-09-11", costUSD: 0, totalTokens: 200),
                SyncDailyPoint(dayKey: "2024-09-09", costUSD: 0, totalTokens: 300),
            ],
            bucketTimeZoneIdentifier: "America/Los_Angeles")
        let days = TokenActivity.snapshotDays(summary, referenceDate: now, readerTimeZone: .gmt)
        #expect(days.count == 1)
        #expect(days.first?.totalTokens == 100)
        #expect(days.first?.dayKey == "2026-09-11")
    }

    @Test @MainActor func `A missing writer count preserves the other writer contribution as a lower bound`() throws {
        let container = try ModelContainer(
            for: DailyCostPoint.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none))
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_789_084_800)
        for device in ["mac-A", "mac-B"] {
            try CostLedgerService.upsertDayPoint(
                deviceID: device,
                providerID: "codex",
                dayKey: "2026-09-10",
                costUSD: 0,
                totalTokens: device == "mac-A" ? 100 : 999,
                tokenCountIsKnown: device == "mac-A",
                costIsKnown: false,
                isEstimated: nil,
                modelBreakdowns: [],
                serviceBreakdowns: [],
                lastUpdated: now,
                in: context)
        }
        let result = try CostLedgerService.aggregate(
            windowDays: 365,
            in: context,
            asOf: now,
            readerTimeZone: #require(TimeZone(secondsFromGMT: 0)))
        #expect(result.totalTokens == 100)
        #expect(result.dailyPoints.first?.totalTokens == 100)
        #expect(result.dailyPoints.first?.tokenCountIsKnown == false)
        #expect(result.sortedProviderRollups.first?.dailyPoints.first?.totalTokens == 100)
    }

    @Test @MainActor func `Two local Macs sum once and repeated updates preserve token availability`() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: DailyCostPoint.self, configurations: config)
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_789_084_800)
        for device in ["mac-A", "mac-B", "mac-A"] {
            try CostLedgerService.upsertDayPoint(
                deviceID: device,
                providerID: "codex",
                dayKey: "2026-09-10",
                costUSD: 0,
                totalTokens: device == "mac-A" ? 100 : 200,
                tokenCountIsKnown: true,
                costIsKnown: false,
                isEstimated: nil,
                modelBreakdowns: [],
                serviceBreakdowns: [],
                lastUpdated: now,
                in: context)
        }
        try context.save()
        let result = try CostLedgerService.aggregate(
            windowDays: 365,
            in: context,
            asOf: now,
            readerTimeZone: #require(TimeZone(secondsFromGMT: 0)))
        #expect(try context.fetchCount(FetchDescriptor<DailyCostPoint>()) == 2)
        #expect(result.totalTokens == 300)
        #expect(result.dailyPoints.first?.tokenCountIsKnown == true)
    }
}
