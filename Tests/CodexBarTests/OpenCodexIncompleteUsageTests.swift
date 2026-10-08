import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

struct OpenCodexIncompleteUsageTests {
    @Test(arguments: ["fixture-priced", "fixture-pending"])
    func `missing usage retains known model subtotals and propagates exclusions`(pendingModel: String) throws {
        let snapshot = Self.snapshot(entries: [
            Self.entry(id: "known", model: "fixture-priced", usage: .init(inputTokens: 100, outputTokens: 20)),
            Self.entry(id: "pending", model: pendingModel, status: .unreported),
        ])
        let day = try #require(snapshot.daily.first)
        #expect(day.totalTokens == 120)
        #expect(abs((day.costUSD ?? -1) - 0.00014) < 1e-12)
        #expect(day.requestCount == 2)
        #expect(day.unpricedRequestCount == 1)
        #expect(day.incompleteRequestCount == 1)
        #expect(day.modelBreakdowns?.first { $0.modelName == pendingModel }?.incompleteRequestCount == 1)
        #expect(snapshot.sessions.first?.modelBreakdowns.first {
            $0.modelName == pendingModel
        }?.incompleteRequestCount == 1)
        #expect(snapshot.summary(forLastDays: 7, calendar: Self.calendar).incompleteRequestCount == 1)
        #expect(snapshot.hourly.first?.tokensAreComplete == false)
        #expect(snapshot.hourly.first?.costIsComplete == false)

        let model = SpendDashboardModel.build(
            inputs: [.init(
                provider: .codex,
                displayName: "Fixture source",
                snapshot: snapshot,
                sourceKind: .openCodex)],
            requestedDays: 7,
            now: Self.now,
            calendar: Self.calendar)
        let group = try #require(model.groups.first)
        #expect(group.totalTokens == 120)
        #expect(group.totalCost == day.costUSD)
        #expect(group.incompleteRequestCount == 1)
        #expect(group.hasPartialTokens && group.hasPartialCost)
        #expect(group.modelHistoryCompleteness == .incomplete)
        #expect(Set(group.models.map(\.modelName)) == Set(["fixture-priced", pendingModel]))
        #expect(group.models.first { $0.modelName == "fixture-priced" }?.totalTokens == 120)
        #expect(group.models.first { $0.modelName == pendingModel }?.incompleteRequestCount == 1)
        #expect(ShareStatsBuilder.make(model: model)?.topModels.isEmpty == true)
        let exported = try #require(SpendDashboardExportPayload.make(model: model, hiddenSourceIDs: []).groups.first)
        #expect(exported.incompleteRequestCount == 1)
        #expect(exported.models.first { $0.modelName == pendingModel }?.incompleteRequestCount == 1)

        let payload = CodexBarCLI.makeCostPayload(provider: .codex, snapshot: snapshot, error: nil)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(json["incompleteRequestCount"] as? Int == 1)
    }

    @Test(arguments: [OpenCodexUsageStatus.reported, .estimated, .unreported, .unsupported])
    func `absence of token evidence is incomplete regardless of source status`(status: OpenCodexUsageStatus) throws {
        let snapshot = Self.snapshot(entries: [Self.entry(id: "empty", status: status, usage: .init())])
        let day = try #require(snapshot.daily.first)
        #expect(day.incompleteRequestCount == 1)
        #expect(day.totalTokens == nil)
        #expect(day.costUSD == nil)
        #expect(day.requestCount == 1)
    }

    @Test(arguments: [
        OpenCodexTokenUsage(inputTokens: 0, outputTokens: 0),
        OpenCodexTokenUsage(totalTokens: 120),
        OpenCodexTokenUsage(inputTokens: 100, outputTokens: 20),
        OpenCodexTokenUsage(inputTokens: Int.max, outputTokens: 1),
        OpenCodexTokenUsage(reasoningOutputTokens: 5),
    ])
    func `known token evidence and overflow are not missing usage`(usage: OpenCodexTokenUsage) {
        let snapshot = Self.snapshot(entries: [Self.entry(id: "tokens", status: .unreported, usage: usage)])
        #expect(snapshot.daily.first?.incompleteRequestCount == 0)
        #expect(snapshot.daily.first?.totalTokens == usage.resolvedTotalTokens)
        #expect(snapshot.daily.first?.modelBreakdowns?.first?.incompleteRequestCount == nil)
    }

    @Test
    func `window filtering and deduplication precede missing usage counts`() {
        let snapshot = Self.snapshot(entries: [
            Self.entry(id: "replaced", status: .unreported),
            Self.entry(id: "replaced", usage: .init(inputTokens: 100, outputTokens: 20)),
            Self.entry(id: "outside", status: .unreported, timestamp: Self.now.addingTimeInterval(-8 * 86400)),
            Self.entry(id: "future", status: .unreported, timestamp: Self.now.addingTimeInterval(1)),
            Self.entry(id: "pending", status: .unreported),
        ])
        #expect(snapshot.daily.first?.incompleteRequestCount == 1)
        #expect(snapshot.last30DaysRequests == 2)
        #expect(snapshot.last30DaysTokens == 120)
    }

    @Test
    func `new model names and extra log fields retain tokens without inventing prices`() throws {
        let line = """
        {"requestId":"future","timestamp":1789560000000,"provider":"openai",\
        "model":"fixture-future-model","usageStatus":"reported",\
        "usage":{"inputTokens":100,"outputTokens":20},"futureField":{"version":42}}
        """
        let entry = try #require(OpenCodexUsageParser.parseLine(line))
        let snapshot = Self.snapshot(entries: [entry])
        #expect(snapshot.last30DaysTokens == 120)
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.daily.first?.incompleteRequestCount == 0)
        let group = try #require(SpendDashboardModel.build(
            inputs: [.init(
                provider: .codex,
                displayName: "Fixture source",
                snapshot: snapshot,
                sourceKind: .openCodex)],
            requestedDays: 7,
            now: Self.now,
            calendar: Self.calendar).groups.first)
        #expect(group.models.first?.modelName == "fixture-future-model")
        #expect(group.models.first?.totalTokens == 120)
        #expect(group.models.first?.totalCost == nil)
    }

    @Test
    func `cold import and reopened cache preserve incomplete model rows`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("usage.jsonl")
        try """
        {"requestId":"known","timestamp":1789560000000,"provider":"openai","model":"fixture-priced",\
        "usageStatus":"reported","usage":{"inputTokens":100,"outputTokens":20}}
        {"requestId":"pending","timestamp":1789560000000,"provider":"openai","model":"fixture-pending",\
        "usageStatus":"unreported"}

        """.write(to: log, atomically: true, encoding: .utf8)
        let cold = try Self.snapshot(entries: OpenCodexUsageStore(cacheRoot: root).loadEntries(logURL: log))
        let recorder = OpenCodexUsageParser.LogReadRecorder()
        let warm = try OpenCodexUsageStore.withLogReadRecorderForTesting(recorder) {
            try Self.snapshot(entries: OpenCodexUsageStore(cacheRoot: root).loadEntries(logURL: log))
        }
        #expect(recorder.snapshot().bytesRead == 0)
        #expect(warm.daily == cold.daily)
        #expect(warm.daily.first?.incompleteRequestCount == 1)
        let group = try #require(SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Fixture source", snapshot: warm, sourceKind: .openCodex)],
            requestedDays: 7,
            now: Self.now,
            calendar: Self.calendar).groups.first)
        #expect(Set(group.models.map(\.modelName)) == ["fixture-priced", "fixture-pending"])
        #expect(group.modelHistoryCompleteness == .incomplete)
    }

    static let now = Date(timeIntervalSince1970: 1_789_560_000)
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func entry(
        id: String,
        model: String = "fixture-priced",
        status: OpenCodexUsageStatus = .reported,
        usage: OpenCodexTokenUsage? = nil,
        timestamp: Date = Self.now) -> OpenCodexUsageEntry
    {
        .init(
            requestID: id,
            timestamp: timestamp,
            provider: "openai",
            model: model,
            usageStatus: status,
            conversationID: "fixture-session",
            usage: usage)
    }

    static func snapshot(entries: [OpenCodexUsageEntry]) -> CostUsageTokenSnapshot {
        OpenCodexUsageAggregator.snapshot(
            entries: entries,
            now: self.now,
            historyDays: 7,
            calendar: self.calendar,
            customPricing: .init(entries: ["fixture-priced": .init(input: 1, output: 2)], fingerprint: "fixture"),
            modelsDevCatalog: .init(providers: [:]),
            customPricingOverlay: .empty)
    }
}
