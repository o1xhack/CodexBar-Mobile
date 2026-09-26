import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Widget Token Activity projection")
struct WidgetActivityProjectionTests {
    private let now = Date(timeIntervalSince1970: 1_790_294_400)

    private func provider(_ id: String, name: String) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.now)
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

    @Test @MainActor func `Refresh error keeps last known heatmap without inventing new days`() {
        let previous = WidgetActivityProjection.preview(now: self.now)
        let failed = WidgetActivityPublisher.statePreservingHistory(
            .error,
            previous: previous,
            latestSyncAt: self.now.addingTimeInterval(60),
            now: self.now.addingTimeInterval(120))
        #expect(failed.state == .error)
        #expect(failed.sources == previous.sources)
        #expect(failed.latestSyncAt == previous.latestSyncAt)
    }
}
