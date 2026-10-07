import Foundation
import Testing
@testable import CodexBarCore

extension CostUsageClaudeReportContextTests {
    @Test(arguments: [false, true], [CostUsageReportContext.regular, .spendDashboard])
    func `catalog replacement during a pass preserves the window and reprices the next report`(
        replaceCatalogMidPass: Bool, context: CostUsageReportContext) throws
    {
        for cold in [false, true] {
            let fixture = try Fixture()
            defer { fixture.env.cleanup() }
            let initialCatalog = try Self.racePricingCatalog(inputRate: 3)
            #expect(ModelsDevCache.save(
                catalog: initialCatalog, fetchedAt: fixture.now, cacheRoot: fixture.env.cacheRoot))
            func event(day: Date, id: String, input: Int) throws -> String {
                try fixture.event(day: day, id: id, input: input)
                    .replacingOccurrences(of: "claude-sonnet-4-20250514", with: "claude-test-pricing")
            }
            let recent = try fixture.env.writeClaudeProjectFile(
                relativePath: "recent.jsonl", contents: event(day: fixture.now, id: "recent", input: 10))
            _ = try fixture.env.writeClaudeProjectFile(
                relativePath: "old.jsonl", contents: event(day: fixture.day(-12), id: "old", input: 20))
            _ = try fixture.env.writeClaudeProjectFile(
                relativePath: "older.jsonl", contents: event(day: fixture.day(-20), id: "older", input: 30))
            _ = try fixture.load(context: context, days: 30)
            let handle = try FileHandle(forWritingTo: recent)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(event(day: fixture.now, id: "append", input: 5).utf8))
            try handle.close()

            var checks = 0
            var catalog = initialCatalog
            var inputRate: Double = 3
            let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
            _ = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
                try CostUsageScanner.loadDailyReportCancellable(
                    provider: .claude,
                    since: fixture.day(-29),
                    until: fixture.now,
                    now: fixture.now,
                    options: fixture.options,
                    reportContext: context,
                    checkCancellation: {
                        checks += 1
                        guard replaceCatalogMidPass else { return }
                        inputRate = Double(10 + checks)
                        catalog = try Self.racePricingCatalog(inputRate: inputRate)
                        #expect(ModelsDevCache.save(
                            catalog: catalog,
                            fetchedAt: fixture.now.addingTimeInterval(Double(checks)),
                            cacheRoot: fixture.env.cacheRoot))
                    })
            }
            #expect(recorder.snapshot().transcriptParses == 1)
            let (next, work) = try fixture.load(context: context, days: 30, cold: cold)
            #expect(work.transcriptParses == 0)
            #expect(next.summary?.totalInputTokens == 65)
            let cost = try #require(next.summary?.totalCostUSD)
            #expect(abs(cost - Double(65) * inputRate / 1_000_000) < 1e-12)
            if replaceCatalogMidPass { #expect(work.repricedRows > 0) }
            let oracleRoot = fixture.env.root.appendingPathComponent("oracle-pricing")
            #expect(ModelsDevCache.save(catalog: catalog, fetchedAt: fixture.now, cacheRoot: oracleRoot))
            let (oracle, _) = try fixture.load(context: context, days: 30, cacheRoot: oracleRoot)
            #expect(next.data == oracle.data)
            #expect(next.summary == oracle.summary)
            #expect(next.hourly == oracle.hourly)
            #expect(next.quotaSlices == oracle.quotaSlices)
            let (reopened, reopenedWork) = try fixture.load(context: context, days: 30, cold: true)
            #expect(reopenedWork.transcriptParses == 0)
            #expect(reopened.data == next.data)
            #expect(reopened.summary == next.summary)
        }
    }

    private static func racePricingCatalog(inputRate: Double) throws -> ModelsDevCatalog {
        let payload: [String: Any] = [
            "anthropic": ["id": "anthropic", "models": [
                "claude-test-pricing": ["id": "claude-test-pricing", "cost": ["input": inputRate, "output": 15]],
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return try JSONDecoder().decode(ModelsDevCatalog.self, from: data)
    }
}
