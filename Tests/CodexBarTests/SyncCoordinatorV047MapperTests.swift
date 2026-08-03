import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarSync

@MainActor
@Suite("SyncCoordinator v0.46-v0.47 mobile bridge")
struct SyncCoordinatorV047MapperTests {
    private static let now = Date(timeIntervalSince1970: 1_786_320_000)

    @Test
    func `zai mapper preserves native hourly and daily series`() throws {
        let zai = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: nil,
            planName: "Pro",
            modelUsage: ZaiModelUsageData(
                xTime: ["2026-08-03 09:00", "2026-08-03 10:00"],
                modelDataList: [
                    ZaiModelDataItem(modelName: "glm-hourly", tokensUsage: [10, 20]),
                ]),
            dailyModelUsage: ZaiModelUsageData(
                xTime: ["2026-08-02", "2026-08-03"],
                modelDataList: [
                    ZaiModelDataItem(modelName: "glm-daily", tokensUsage: [100, 200]),
                ]),
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            zaiUsage: zai,
            updatedAt: Self.now)

        let mapped = try #require(SyncCoordinator.mapZaiHourlyUsage(provider: .zai, snapshot: snapshot))
        #expect(mapped.xTime.count == 2)
        #expect(mapped.modelSeries.first?.tokens == [10, 20])
        #expect(mapped.dailyXTime.count == 2)
        #expect(mapped.dailyModelSeries.first?.tokens == [100, 200])
        #expect(SyncCoordinator.mapZaiHourlyUsage(provider: .claude, snapshot: snapshot) == nil)
    }

    @Test
    func `ZoomMate mapper preserves status cycle and daily history`() throws {
        let start = Int64(Self.now.addingTimeInterval(-10 * 86400).timeIntervalSince1970 * 1000)
        let end = Int64(Self.now.addingTimeInterval(20 * 86400).timeIntervalSince1970 * 1000)
        let status = ZoomMateCreditStatus(
            budgetCap: 1000,
            usedCredit: 250,
            remainingCredit: 750,
            overageCredit: 0,
            allowOverage: true,
            cycleStartDate: start,
            cycleEndDate: end,
            isQuotaAvailable: true,
            isUnlimited: false)
        let record = ZoomMateCreditHistoryRecord(
            sessionID: "session-1",
            title: "Synthetic meeting",
            cost: 12.5,
            time: ISO8601DateFormatter().string(from: Self.now),
            isRunning: false,
            isDeleted: false)
        let history = ZoomMateCreditsHistorySnapshot(
            records: [record],
            creditStatus: status,
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            zoommateCreditsHistory: history,
            updatedAt: Self.now)

        let mapped = try #require(SyncCoordinator.mapZoomMateCredits(provider: .zoommate, snapshot: snapshot))
        #expect(mapped.budgetCap == 1000)
        #expect(mapped.remainingCredits == 750)
        #expect(mapped.cycleEndAt == Date(timeIntervalSince1970: Double(end) / 1000))
        #expect(mapped.daily.reduce(0) { $0 + $1.creditsUsed } == 12.5)
        #expect(mapped.todayCreditsUsed == 12.5)
    }

    @Test
    func `Claude prepaid balance survives alongside a positive spend limit`() throws {
        let cost = ProviderCostSnapshot(
            used: 18,
            limit: 100,
            currencyCode: "USD",
            period: "Monthly",
            balance: 42.5,
            updatedAt: Self.now)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: cost,
            updatedAt: Self.now,
            dataConfidence: .exact)

        let mapped = try #require(SyncCoordinator.mapProviderAmount(
            provider: .claude,
            snapshot: snapshot,
            providerCost: cost))
        #expect(mapped.kind == "balance")
        #expect(mapped.amount == 42.5)
        #expect(mapped.currencyCode == "USD")
    }

    @Test
    func `xAI mapper emits both prepaid balance and daily cost history`() throws {
        let usage = XAIUsageSnapshot(
            balanceUSD: 81.25,
            daily: [
                .init(day: "2026-08-02", costUSD: 1.25),
                .init(day: "2026-08-03", costUSD: 2.75),
            ],
            historyDays: 30,
            limitReached: true,
            updatedAt: Self.now)
        let snapshot = usage.toUsageSnapshot()
        let amount = try #require(SyncCoordinator.mapProviderAmount(
            provider: .xai,
            snapshot: snapshot,
            providerCost: snapshot.providerCost))
        let cost = try #require(SyncCoordinator.mapXAICostSummary(provider: .xai, snapshot: snapshot))

        #expect(amount.amount == 81.25)
        #expect(cost.last30DaysCostUSD == 4)
        #expect(cost.daily.count == 2)
        #expect(cost.isEstimated == true)
    }
}

@Suite("v0.47 mobile envelope compatibility")
struct V047MobileEnvelopeCompatibilityTests {
    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.sortedKeys]
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    @Test
    func `old provider payload decodes new fields as absent`() throws {
        let json = """
        {
          "providerID":"notion",
          "providerName":"Notion AI",
          "rateWindows":[],
          "isError":false,
          "lastUpdated":"2026-08-03T12:00:00Z"
        }
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.accountOrganization == nil)
        #expect(decoded.zoomMateCredits == nil)
    }

    @Test
    func `new provider payload round trips and old reader ignores additive keys`() throws {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let source = ProviderUsageSnapshot(
            providerID: "zoommate",
            providerName: "ZoomMate",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Browser session",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            accountOrganization: "Example Workspace",
            zoomMateCredits: SyncZoomMateCredits(
                budgetCap: 1000,
                usedCredits: 250,
                remainingCredits: 750,
                daily: [.init(dayKey: "2026-08-03", creditsUsed: 12.5)],
                updatedAt: now))
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded == source)

        struct LegacyReader: Decodable {
            let providerID: String
            let providerName: String
            let isError: Bool
            let lastUpdated: Date
        }
        let legacy = try Self.decoder.decode(LegacyReader.self, from: data)
        #expect(legacy.providerID == "zoommate")
        #expect(legacy.providerName == "ZoomMate")
        #expect(!legacy.isError)
        #expect(legacy.lastUpdated == now)
    }
}
