import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Widget Token Activity projection")
struct WidgetActivityProjectionTests {
    private let now = Date(timeIntervalSince1970: 1_790_294_400)

    private func provider(_ id: String, name: String, tintHex: String? = nil) -> ProviderUsageSnapshot {
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
            providerIconTintHex: tintHex)
    }

    @Test func `Projection keeps known zero unknown and partial totals identical to Token Activity`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "GMT"))
        let today = TokenActivity.dayKey(self.now, calendar: calendar)
        let yesterday = TokenActivity.dayKey(
            try #require(calendar.date(byAdding: .day, value: -1, to: self.now)), calendar: calendar)
        let twoDaysAgo = TokenActivity.dayKey(
            try #require(calendar.date(byAdding: .day, value: -2, to: self.now)), calendar: calendar)
        let codex = TokenActivitySeries(provider: self.provider("codex", name: "Codex"), days: [
            SyncDailyPoint(dayKey: today, costUSD: 0, totalTokens: 0, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: yesterday, costUSD: 0, totalTokens: 400, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: twoDaysAgo, costUSD: 0, totalTokens: -1, tokenCountIsKnown: false),
        ])
        let claude = TokenActivitySeries(provider: self.provider("claude", name: "Claude"), days: [
            SyncDailyPoint(dayKey: today, costUSD: 0, totalTokens: 0, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: yesterday, costUSD: 0, totalTokens: 70, tokenCountIsKnown: false),
        ], hasLedgerCounts: true)
        let series = [codex, claude]
        let projection = WidgetActivityProjectionBuilder.make(
            series: series, latestSyncAt: self.now, now: self.now, calendar: calendar)

        #expect(projection.state == .loaded)
        #expect(projection.sources.map(\.id) == ["all", "claude", "codex"])
        #expect(projection.source(id: "claude")?.name == "Claude Code")
        for id in ["all", "claude", "codex"] {
            let selected = id == "all" ? series : series.filter { $0.provider.providerID == id }
            let source = try #require(projection.source(id: id))
            #expect(source.days.count == 365)
            for key in [today, yesterday, twoDaysAgo] {
                let widgetDay = try #require(source.days.first { $0.key == key })
                let appTotal = TokenActivity.total(selected, dayKey: key)
                #expect(widgetDay.tokens == appTotal.value)
                #expect(widgetDay.isLowerBound == appTotal.isLowerBound)
            }
        }
        #expect(projection.source(id: "all")?.days.last?.tokens == 0)
        #expect(projection.source(id: "all")?.days.first { $0.key == yesterday }?.isLowerBound == true)
        #expect(projection.source(id: "codex")?.days.first { $0.key == twoDaysAgo }?.tokens == nil)
    }

    @Test func `Projection file round trip preserves source selection and day meaning`() throws {
        let projection = WidgetActivityProjection.preview(now: self.now)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try WidgetActivityStore.write(projection, to: url)
        let decoded = try WidgetActivityStore.read(from: url)
        let restored = try #require(decoded)
        #expect(restored == projection)
        #expect(restored.source(id: "codex") != nil)
        #expect(restored.source(id: "claude") != nil)
    }

    @Test func `Widget source keeps the same provider tint as the app`() throws {
        let series = TokenActivitySeries(
            provider: self.provider("sample", name: "Sample", tintHex: "#3366CC"),
            days: [])
        let projection = WidgetActivityProjectionBuilder.make(
            series: [series], latestSyncAt: self.now, now: self.now)
        #expect(projection.source(id: "sample")?.tintHex == "#3366CC")
        #expect(projection.source(id: "all")?.tintHex == nil)
        let decoded = try JSONDecoder().decode(
            WidgetActivityProjection.self, from: JSONEncoder().encode(projection))
        #expect(decoded.source(id: "sample")?.tintHex == "#3366CC")
    }

    @Test @MainActor func `Refresh error and syncing keep the last known heatmap`() {
        let previous = WidgetActivityProjection.preview(now: self.now)
        let failed = WidgetActivityPublisher.statePreservingHistory(
            .error,
            previous: previous,
            latestSyncAt: self.now.addingTimeInterval(60),
            now: self.now.addingTimeInterval(120))
        #expect(failed.state == .error)
        #expect(failed.sources == previous.sources)
        #expect(failed.latestSyncAt == previous.latestSyncAt)

        let syncing = WidgetActivityPublisher.statePreservingHistory(
            .syncing,
            previous: previous,
            latestSyncAt: nil,
            now: self.now.addingTimeInterval(180))
        #expect(syncing.state == .syncing)
        #expect(syncing.sources == previous.sources)
        #expect(syncing.latestSyncAt == previous.latestSyncAt)
    }

    @Test func `Projection retains ledger history beyond the current sync blob`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "GMT"))
        let olderDate = try #require(calendar.date(byAdding: .day, value: -180, to: self.now))
        let olderKey = TokenActivity.dayKey(olderDate, calendar: calendar)
        let currentKey = TokenActivity.dayKey(self.now, calendar: calendar)
        let ledgerSeries = TokenActivitySeries(provider: self.provider("codex", name: "Codex"), days: [
            SyncDailyPoint(dayKey: olderKey, costUSD: 0, totalTokens: 810, tokenCountIsKnown: true),
            SyncDailyPoint(dayKey: currentKey, costUSD: 0, totalTokens: 120, tokenCountIsKnown: true),
        ], hasLedgerCounts: true)
        let currentBlobOnly = TokenActivitySeries(provider: self.provider("codex", name: "Codex"), days: [
            SyncDailyPoint(dayKey: currentKey, costUSD: 0, totalTokens: 120, tokenCountIsKnown: true),
        ])
        let projection = WidgetActivityProjectionBuilder.make(
            series: [ledgerSeries], latestSyncAt: self.now, now: self.now, calendar: calendar)
        #expect(TokenActivity.total([currentBlobOnly], dayKey: olderKey).value == nil)
        #expect(projection.source(id: "codex")?.days.first { $0.key == olderKey }?.tokens == 810)
    }

    @Test func `Active-day summary counts only dates visible in the Monday-aligned grid`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "GMT"))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        let source = WidgetActivitySource(id: "codex", name: "Codex", days: [
            WidgetActivityDay(key: "2026-08-20", tokens: 100, isLowerBound: false, intensity: 0.25),
            WidgetActivityDay(key: "2026-08-24", tokens: 200, isLowerBound: false, intensity: 0.50),
            WidgetActivityDay(key: "2026-09-20", tokens: 0, isLowerBound: false, intensity: 0),
            WidgetActivityDay(key: "2026-09-21", tokens: 300, isLowerBound: true, intensity: 0.75),
            WidgetActivityDay(key: "2026-09-22", tokens: 400, isLowerBound: false, intensity: 1),
        ])

        #expect(WidgetActivityWindow.startDate(weeks: 5, referenceDate: monday, calendar: calendar)
            == calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        #expect(WidgetActivityWindow.activeDayCount(
            source: source, weeks: 5, referenceDate: monday, calendar: calendar) == 2)
    }

    @Test func `Small widget fills recent days upward from the bottom-right cell`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "GMT"))
        let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23)))
        let dates = WidgetActivityWindow.compactDates(weeks: 7, referenceDate: wednesday, calendar: calendar)

        #expect(dates.count == 49)
        #expect(dates.first == calendar.date(from: DateComponents(year: 2026, month: 8, day: 6)))
        #expect(dates[34] == calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        #expect(dates[41] == calendar.date(from: DateComponents(year: 2026, month: 9, day: 22)))
        #expect(dates[47] == calendar.date(from: DateComponents(year: 2026, month: 9, day: 16)))
        #expect(dates.last == wednesday)
    }
}
