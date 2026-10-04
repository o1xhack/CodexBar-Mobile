import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Research/065 — Quota Pace widget data and provider selection.
@Suite("Quota pace widget")
struct QuotaPaceWidgetTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func weekly(used: Double, resetInDays days: Double) -> SyncRateWindow {
        SyncRateWindow(
            id: "secondary",
            label: "Weekly",
            usedPercent: used,
            windowMinutes: 10080,
            resetsAt: self.now.addingTimeInterval(days * 86400),
            resetDescription: nil)
    }

    private static func provider(
        _ providerID: String,
        used: Double = 40,
        resetInDays: Double = 3,
        history: Int = 0,
        windows: [SyncRateWindow]? = nil) -> ProviderUsageSnapshot
    {
        let weekly = Self.weekly(used: used, resetInDays: resetInDays)
        let reset = weekly.resetsAt!
        let start = reset.addingTimeInterval(-604_800)
        let entries = (0..<history).map { index in
            SyncUtilizationEntry(
                capturedAt: start.addingTimeInterval(Double(index + 1) * 600),
                usedPercent: min(used, Double(index) * 0.05),
                resetsAt: reset)
        }
        return ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerID.capitalized,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.now.addingTimeInterval(-60),
            rateWindows: windows ?? [weekly],
            utilizationHistory: history > 0
                ? [SyncUtilizationSeries(name: "weekly", windowMinutes: 10080, entries: entries)]
                : nil)
    }

    @Test
    func `Codex and Claude carry pace plus a thinned weekly lane`() throws {
        for providerID in ["codex", "claude"] {
            let summary = try #require(CodexBarWidgetPaceSummary(
                provider: Self.provider(providerID, history: 400),
                now: Self.now))
            #expect(summary.pace != nil)
            #expect(summary.paceRemainingPercent == 60)
            let lane = try #require(summary.primaryLane)
            #expect(lane.seriesName == "weekly")
            #expect(lane.points.count <= CodexBarWidgetPaceLane.pointLimit)
            #expect(lane.points.last?.remainingPercent == 60)
            #expect(lane.points.last?.date == Self.now.addingTimeInterval(-60))
        }
    }

    @Test
    func `Other providers get pace without a chart and short windows get nothing`() throws {
        let other = try #require(CodexBarWidgetPaceSummary(provider: Self.provider("zai"), now: Self.now))
        #expect(other.pace != nil)
        #expect(other.lanes.isEmpty)

        let session = SyncRateWindow(
            usedPercent: 50,
            windowMinutes: 300,
            resetsAt: Self.now.addingTimeInterval(3600),
            resetDescription: nil)
        #expect(CodexBarWidgetPaceSummary(provider: Self.provider("zai", windows: [session]), now: Self.now) == nil)
    }

    @Test
    func `Thinning keeps the first and latest sample and never exceeds the limit`() {
        let samples = (0..<500).map {
            MobileQuotaBurndown.Sample(
                date: Self.now.addingTimeInterval(Double($0)),
                remainingPercent: 100 - Double($0) / 5)
        }
        let thinned = MobileQuotaBurndown.downsample(samples, limit: 60)
        #expect(thinned.count == 60)
        #expect(thinned.first == samples.first)
        #expect(thinned.last == samples.last)
        #expect(zip(thinned, thinned.dropFirst()).allSatisfy { $0.date < $1.date })
        #expect(MobileQuotaBurndown.downsample(Array(samples.prefix(10)), limit: 60).count == 10)
    }

    private static func summary(
        _ providerID: String,
        lanes: Bool,
        remaining: Double,
        isError: Bool = false) -> CodexBarWidgetProviderSummary
    {
        let pace = CodexBarWidgetPaceSummary.sample(
            now: Self.now,
            weeklyUsed: 100 - remaining,
            weeklyResetIn: 3,
            sessionUsed: nil)
        return CodexBarWidgetProviderSummary(
            id: "\(providerID)|x",
            providerName: providerID.capitalized,
            providerID: providerID,
            loginMethod: nil,
            usagePercent: 100 - remaining,
            todayCostUSD: nil,
            thirtyDayCostUSD: nil,
            tokensToday: nil,
            isError: isError,
            statusMessage: nil,
            lastUpdated: Self.now,
            quotaPace: CodexBarWidgetPaceSummary(
                pace: pace.pace,
                paceRemainingPercent: remaining,
                paceResetsAt: pace.paceResetsAt,
                lanes: lanes ? pace.lanes : []))
    }

    @Test
    func `Automatic selection prefers charted providers then the least remaining quota`() {
        let providers = [
            Self.summary("zai", lanes: false, remaining: 5),
            Self.summary("claude", lanes: true, remaining: 60),
            Self.summary("codex", lanes: true, remaining: 30),
            Self.summary("broken", lanes: true, remaining: 1, isError: true),
        ]
        let picked = WidgetProviderSelection.pace(from: providers, selected: nil, limit: 2)
        #expect(picked.map(\.providerID) == ["codex", "claude"])
        #expect(WidgetProviderSelection.pace(from: providers, selected: nil, limit: 4).map(\.providerID)
            == ["codex", "claude", "zai"])
    }

    @Test
    func `A configured provider wins and an unusable choice is shown as unavailable`() {
        let providers = [
            Self.summary("claude", lanes: true, remaining: 60),
            Self.summary("codex", lanes: true, remaining: 30),
        ]
        let claude = [WidgetProviderEntity(id: "claude", name: "Claude")]
        #expect(WidgetProviderSelection.pace(from: providers, selected: claude, limit: 1).map(\.providerID)
            == ["claude"])
        // An unusable configured provider is reported, not silently replaced.
        let gone = [WidgetProviderEntity(id: "gemini", name: "Gemini")]
        let picked = WidgetProviderSelection.pace(from: providers, selected: gone, limit: 1, now: Self.now)
        #expect(picked.map(\.providerID) == ["gemini"])
        #expect(picked.first?.quotaPace == nil)
        #expect(picked.first?.providerName == "Gemini")
    }

    @Test
    func `Placeholder snapshot has pace data for the gallery and simulator`() {
        let providers = CodexBarWidgetSnapshot.placeholder(now: Self.now).topProviders
        let paced = providers.filter { $0.quotaPace?.pace != nil }
        #expect(paced.map(\.providerID).sorted() == ["claude", "codex"])
        #expect(paced.allSatisfy { $0.quotaPace?.lanes.count == 2 })
    }

    @Test
    func `Without a pace the hero falls back to the charted lane and pace ranks first`() throws {
        // Weekly window not usable for pace (unknown usage), session lane charted.
        let reset = Self.now.addingTimeInterval(3600)
        let session = SyncRateWindow(
            id: "primary", label: "Session", usedPercent: 30, windowMinutes: 300, resetsAt: reset,
            resetDescription: nil)
        let weekly = SyncRateWindow(
            id: "secondary", label: "Weekly", usedPercent: 0, usageKnown: false, windowMinutes: 10080,
            resetsAt: Self.now.addingTimeInterval(86400), resetDescription: nil)
        let provider = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: session,
            secondary: weekly,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.now.addingTimeInterval(-60),
            rateWindows: [session, weekly])
        let summary = try #require(CodexBarWidgetPaceSummary(provider: provider, now: Self.now))
        #expect(summary.pace == nil)
        #expect(summary.paceRemainingPercent == 70)
        #expect(summary.paceResetsAt == reset)

        // A provider with a pace outranks one that only has a chart.
        let chartOnly = CodexBarWidgetProviderSummary(
            id: "claude|x", providerName: "Claude", providerID: "claude", loginMethod: nil,
            usagePercent: 30, todayCostUSD: nil, thirtyDayCostUSD: nil, tokensToday: nil,
            isError: false, statusMessage: nil, lastUpdated: Self.now, quotaPace: summary)
        let paced = Self.summary("zai", lanes: false, remaining: 50)
        #expect(WidgetProviderSelection.pace(from: [chartOnly, paced], selected: nil, limit: 1).map(\.providerID)
            == ["zai"])
    }
}
