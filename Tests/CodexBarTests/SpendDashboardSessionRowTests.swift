import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct SpendDashboardSessionRowTests {
    @Test
    func `sessions rank by cost and carry thread names and projects`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let sessions = [
            Self.session(id: "cheap", cost: 1, tokens: 10),
            Self.session(id: "unpriced", cost: nil, tokens: 999),
            Self.session(
                id: "expensive",
                cost: 5,
                tokens: 50,
                title: "Fix the icon",
                projectPath: "/Users/example/Projects/example-app"),
        ]
        let model = SpendDashboardModel.build(
            inputs: [Self.sessionInput(sessions: sessions)],
            requestedDays: 90,
            now: Self.now,
            calendar: calendar)

        let rows = try #require(model.groups.first?.sessions)
        #expect(rows.map(\.sessionID) == ["expensive", "cheap", "unpriced"])
        #expect(rows.map(\.rank) == [1, 2, 3])
        #expect(rows[0].title == "Fix the icon")
        #expect(rows[0].projectName == "example-app")
        #expect(rows[0].projectPath == "/Users/example/Projects/example-app")
        #expect(rows[1].title == nil)
    }

    @Test
    func `sessions keep the most expensive rows up to the display limit`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let count = SpendDashboardModel.sessionRowLimit + 5
        let sessions = (1...count).map { Self.session(id: "s\($0)", cost: Double($0), tokens: $0) }
        let model = SpendDashboardModel.build(
            inputs: [Self.sessionInput(sessions: sessions)],
            requestedDays: 90,
            now: Self.now,
            calendar: calendar)

        let rows = try #require(model.groups.first?.sessions)
        #expect(rows.count == SpendDashboardModel.sessionRowLimit)
        #expect(rows.first?.sessionID == "s\(count)")
        #expect(rows.last?.sessionID == "s6")
    }

    @Test
    func `session privacy masks thread names and projects but keeps model and date`() {
        let row = SpendDashboardModel.SessionRow(
            id: "codex:019f79b9-1790-7921-8d6f-258a1e92b191",
            rank: 1,
            sessionID: "019f79b9-1790-7921-8d6f-258a1e92b191",
            sourceID: "codex",
            provider: .codex,
            title: "private thread name",
            projectName: "private-project",
            projectPath: "/Users/example/Projects/private-project",
            lastActivity: Self.now,
            totalTokens: 10,
            totalCost: 1,
            modelName: "gpt-5.4")
        let date = SpendActivityDateFormatting.mediumDateString(Self.now)
        let masked = L("Session %@", "019f...1e92b191")

        let visible = row.displayIdentity(hidePersonalInfo: false)
        #expect(visible.name == "private thread name")
        #expect(visible.path == "/Users/example/Projects/private-project")
        #expect(row
            .displaySubtitle(hidePersonalInfo: false, calendar: .current) == "private-project · gpt-5.4 · \(date)")

        let hidden = row.displayIdentity(hidePersonalInfo: true)
        #expect(hidden.name == masked)
        #expect(hidden.path == nil)
        #expect(row.displaySubtitle(hidePersonalInfo: true, calendar: .current) == "gpt-5.4 · \(date)")
    }

    @Test
    func `untitled sessions fall back to the short session ID`() {
        let row = SpendDashboardModel.SessionRow(
            id: "codex:019f79b9-1790-7921-8d6f-258a1e92b191",
            rank: 1,
            sessionID: "019f79b9-1790-7921-8d6f-258a1e92b191",
            sourceID: "codex",
            provider: .codex,
            title: nil,
            projectName: nil,
            projectPath: nil,
            lastActivity: Self.now,
            totalTokens: 10,
            totalCost: 1,
            modelName: nil)

        #expect(row.displayIdentity(hidePersonalInfo: false).name == L("Session %@", "019f...1e92b191"))
        #expect(row.displaySubtitle(hidePersonalInfo: false, calendar: .current)
            == SpendActivityDateFormatting.mediumDateString(Self.now))
    }

    @Test
    func `session subtitles use the dashboard date at the UTC midnight boundary`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let activity = Self.now.addingTimeInterval(30 * 60)
        let model = SpendDashboardModel.build(
            inputs: [Self.sessionInput(sessions: [Self.session(
                id: "midnight",
                cost: 1,
                tokens: 10,
                lastActivity: activity)])],
            requestedDays: 90,
            now: activity,
            calendar: calendar)
        let group = try #require(model.groups.first)
        let row = try #require(group.sessions.first)
        let expected = SpendActivityDateFormatting.mediumDateString(activity, calendar: group.calendar)
        #expect(row.displaySubtitle(hidePersonalInfo: false, calendar: group.calendar) == expected)
        #expect(row.displaySubtitle(hidePersonalInfo: true, calendar: group.calendar) == expected)
    }

    @Test(arguments: [false, true])
    func `built session rows respect privacy without changing costs or ranks`(hidePersonalInfo: Bool) throws {
        let model = SpendDashboardModel.build(
            inputs: [Self.sessionInput(sessions: [Self.session(
                id: "fixture-session",
                cost: 2.5,
                tokens: 20,
                title: "Synthetic client work",
                projectPath: "/Users/example/Projects/synthetic-client")])],
            requestedDays: 90,
            now: Self.now)
        let group = try #require(model.groups.first)
        let row = try #require(group.sessions.first)
        let identity = row.displayIdentity(hidePersonalInfo: hidePersonalInfo)
        let subtitle = row.displaySubtitle(hidePersonalInfo: hidePersonalInfo, calendar: group.calendar)
        #expect(identity.name == (hidePersonalInfo ? L("Session %@", "fixt...-session") : "Synthetic client work"))
        #expect(identity.path == (hidePersonalInfo ? nil : "/Users/example/Projects/synthetic-client"))
        #expect(subtitle.contains("synthetic-client") == !hidePersonalInfo)
        #expect(row.totalCost == 2.5)
        #expect(row.totalTokens == 20)
        #expect(row.rank == 1)
    }

    @Test
    func `equal session IDs across sources use source qualified ties`() throws {
        let sessions = [Self.session(id: "shared", cost: 1, tokens: 10)]
        let first = Self.sessionInput(sessions: sessions)
        let second = SpendDashboardModel.ProviderInput(
            id: "codex-second", provider: .codex, displayName: "Codex second", snapshot: first.snapshot)
        for inputs in [[first, second], [second, first]] {
            let model = SpendDashboardModel.build(inputs: inputs, requestedDays: 90, now: Self.now)
            let rows = try #require(model.groups.first?.sessions)
            #expect(rows.map(\.id) == ["codex-second:shared", "codex:shared"])
            #expect(rows.map(\.rank) == [1, 2])
        }
    }

    @Test
    func `session ties rank deterministically regardless of input order without changing daily totals`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let sessions = [
            Self.session(id: "b", cost: 1, tokens: 10),
            Self.session(id: "a", cost: 1, tokens: 10),
            Self.session(id: "older", cost: 1, tokens: 10, lastActivity: Self.now.addingTimeInterval(-60)),
            Self.session(id: "more-tokens", cost: 1, tokens: 20),
            Self.session(id: "free", cost: 0, tokens: 10),
            Self.session(id: "unpriced", cost: nil, tokens: 999),
        ]
        let expected = ["more-tokens", "a", "b", "older", "free", "unpriced"]
        let baseline = SpendDashboardModel.build(
            inputs: [Self.sessionInput(sessions: [])], requestedDays: 90, now: Self.now, calendar: calendar)
        let baselineGroup = try #require(baseline.groups.first)
        for offset in sessions.indices {
            let rotated = Array(sessions[offset...] + sessions[..<offset])
            for ordered in [rotated, Array(rotated.reversed())] {
                let model = SpendDashboardModel.build(
                    inputs: [Self.sessionInput(sessions: ordered)],
                    requestedDays: 90,
                    now: Self.now,
                    calendar: calendar)
                let group = try #require(model.groups.first)
                #expect(group.sessions.map(\.sessionID) == expected)
                #expect(group.sessions.map(\.rank) == Array(1...sessions.count))
                #expect(group.sessions.last?.totalCost == nil)
                #expect(group.sessions.first(where: { $0.sessionID == "free" })?.totalCost == 0)
                #expect(group.dailySummaries == baselineGroup.dailySummaries)
                #expect(group.totalCost == baselineGroup.totalCost)
                #expect(group.totalTokens == baselineGroup.totalTokens)
            }
        }
    }

    private static func sessionInput(sessions: [CostUsageSessionBreakdown]) -> SpendDashboardModel.ProviderInput {
        SpendDashboardModel.ProviderInput(
            id: "codex",
            provider: .codex,
            displayName: "Codex",
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: nil,
                last30DaysCostUSD: nil,
                currencyCode: "USD",
                historyDays: 90,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-07-16",
                        inputTokens: nil,
                        outputTokens: nil,
                        totalTokens: 10,
                        costUSD: 1,
                        modelsUsed: nil,
                        modelBreakdowns: nil),
                ],
                sessions: sessions,
                updatedAt: self.now))
    }

    private static func session(
        id: String,
        cost: Double?,
        tokens: Int,
        title: String? = nil,
        projectPath: String? = nil,
        lastActivity: Date = Self.now) -> CostUsageSessionBreakdown
    {
        CostUsageSessionBreakdown(
            sessionID: id,
            lastActivity: lastActivity,
            inputTokens: tokens,
            cachedInputTokens: nil,
            outputTokens: 0,
            totalTokens: tokens,
            requestCount: 1,
            costUSD: cost,
            modelBreakdowns: [],
            projectPath: projectPath,
            projectName: projectPath.map { URL(fileURLWithPath: $0).lastPathComponent },
            title: title)
    }

    private static let now = Date(timeIntervalSince1970: 1_784_179_200) // 2026-07-16 00:00:00 UTC
}
