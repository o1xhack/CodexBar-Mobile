import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageClaudeWriteAmplificationTests {
    @Test(arguments: [2, 128], [false, true])
    func `unchanged scans preserve both cache and memo artifacts`(rowCount: Int, forceRescan: Bool) throws {
        let fixture = try Fixture(rowCount: rowCount)
        defer { fixture.env.cleanup() }
        for context in [CostUsageReportContext.regular, .spendDashboard] {
            let initial = try fixture.load(context: context)
            for cycle in 1...3 {
                // Drop the in-process memo as well, exercising the cross-launch baseline.
                CostUsageScanner.evictClaudeReportMemoForTesting(
                    provider: .claude, cacheRoot: fixture.env.cacheRoot, reportContext: context)
                let before = try fixture.stamps(context: context)
                let report = try fixture.load(context: context, cycle: cycle, forceRescan: forceRescan)
                let after = try fixture.stamps(context: context)
                let bytes = zip(before, after).reduce(Int64(0)) { $0 + ($1.0 == $1.1 ? 0 : $1.1.size) }
                print("[claude-json-writes] rows=\(rowCount) context=\(context) force=\(forceRescan) " +
                    "cycle=\(cycle) files=\(zip(before, after).filter { $0 != $1 }.count) bytes=\(bytes)")
                #expect(report.data == initial.data)
                #expect(report.hourly == initial.hourly)
                #expect(report.quotaSlices == initial.quotaSlices)
                #expect(after == before)
                #expect(bytes == 0)
            }
        }
    }

    @Test
    func `identical explicit saves preserve artifact stamps`() throws {
        let fixture = try Fixture(rowCount: 2)
        defer { fixture.env.cleanup() }
        _ = try fixture.load(context: .regular)
        let cacheURL = fixture.cacheURL(context: .regular)
        let cache = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        let memo = try #require(CostUsageClaudeReportMemo.shared.entry(
            provider: .claude, canonicalCachePath: cacheURL.path))
        let before = try fixture.stamps(context: .regular)
        for _ in 0..<3 {
            let saved = try CostUsageClaudeCacheIO.save(
                provider: .claude, cache: cache, cacheRoot: fixture.env.cacheRoot)
            #expect(saved == before[0])
            CostUsageClaudeReportMemo.shared.store(
                provider: .claude,
                canonicalCachePath: cacheURL.path,
                sourceInventory: memo.sourceInventory,
                reportKey: memo.reportKey,
                report: memo.report,
                hasWindowScopedRows: memo.hasWindowScopedRows)
        }
        #expect(try fixture.stamps(context: .regular) == before)
    }

    @Test
    func `changed usage persists once and a cancelled save preserves the artifacts`() throws {
        let fixture = try Fixture(rowCount: 2)
        defer { fixture.env.cleanup() }
        let initial = try fixture.load(context: .regular)
        let before = try fixture.stamps(context: .regular)
        _ = try fixture.env.writeClaudeProjectFile(
            relativePath: "added.jsonl", contents: fixture.event(index: 500))
        let changed = try fixture.load(context: .regular, cycle: 1)
        #expect(changed.summary?.totalInputTokens == (initial.summary?.totalInputTokens ?? 0) + 10)
        let after = try fixture.stamps(context: .regular)
        #expect(after[0] != before[0])
        #expect(after[1] != before[1])
        var cache = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        cache.usage.lastScanUnixMs += 1
        #expect(throws: CancellationError.self) {
            try CostUsageClaudeCacheIO.save(
                provider: .claude,
                cache: cache,
                cacheRoot: fixture.env.cacheRoot,
                checkCancellation: { throw CancellationError() })
        }
        #expect(try fixture.stamps(context: .regular) == after)
        _ = try fixture.load(context: .regular, cycle: 2)
        #expect(try fixture.stamps(context: .regular) == after)
        CostUsageScanner.evictClaudeReportMemoForTesting(provider: .claude, cacheRoot: fixture.env.cacheRoot)
        let cold = try fixture.load(context: .regular, cycle: 3)
        #expect(cold.data == changed.data)
        #expect(cold.quotaSlices == changed.quotaSlices)
    }

    private struct Fixture {
        let env: CostUsageTestEnvironment
        let day: Date

        init(rowCount: Int) throws {
            self.env = try CostUsageTestEnvironment()
            self.day = try self.env.makeLocalNoon(year: 2026, month: 7, day: 1)
            _ = try self.env.writeClaudeProjectFile(
                relativePath: "session.jsonl", contents: (0..<rowCount).map(self.event).joined())
        }

        func event(index: Int) throws -> String {
            try self.env.jsonl([[
                "type": "assistant", "timestamp": self.env.isoString(for: self.day.addingTimeInterval(Double(index))),
                "requestId": "request-\(index)",
                "message": [
                    "id": "message-\(index)",
                    "model": "claude-sonnet-4-20250514",
                    "usage": ["input_tokens": 10, "output_tokens": 5],
                ],
            ]])
        }

        func cacheURL(context: CostUsageReportContext) -> URL {
            CostUsageClaudeCacheIO.cacheFileURL(
                provider: .claude,
                cacheRoot: self.env.cacheRoot,
                reportContext: context)
        }

        func stamps(context: CostUsageReportContext) throws -> [CostUsageClaudeFileStamp] {
            let cache = self.cacheURL(context: context)
            return try [cache, CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: cache)].map {
                try #require(CostUsageClaudeFileStamp.read(at: $0))
            }
        }

        func load(
            context: CostUsageReportContext,
            cycle: Int = 0,
            forceRescan: Bool = false) throws -> CostUsageDailyReport
        {
            var options = CostUsageScanner.Options(
                claudeProjectsRoots: [self.env.claudeProjectsRoot], cacheRoot: self.env.cacheRoot)
            options.refreshMinIntervalSeconds = 0
            options.forceRescan = forceRescan
            return try CostUsageScanner.loadDailyReportCancellable(
                provider: .claude,
                since: self.day.addingTimeInterval(context == .regular ? -29 * 86400 : -364 * 86400),
                until: self.day,
                now: self.day.addingTimeInterval(Double(cycle * 900)),
                options: options,
                reportContext: context,
                checkCancellation: nil)
        }
    }
}
