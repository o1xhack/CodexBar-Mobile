import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

struct KimiContradictoryUsageTests {
    @Test
    func `reported exhausted session wins over its zero ratio without weekly counts`() throws {
        let usage = try Self.snapshot()
        #expect(usage.primary == nil)
        #expect(usage.secondary?.usedPercent == 100)
        #expect(usage.secondary?.windowMinutes == 300)
        #expect(usage.secondary?.resetsAt == ISO8601DateParser.parse("2026-10-06T13:23:46.915474Z"))
        #expect(usage.secondary?.resetDescription == "Rate: 100/100 per 5 hours")
    }

    @Test
    func `reported monthly pool is selected for text menus and CLI output`() throws {
        let usage = try Self.snapshot()
        let monthly = try #require(usage.extraRateWindows?.first)
        #expect(monthly.id == "kimi-monthly")
        #expect(abs(monthly.window.usedPercent - 55.31) < 0.00001)
        #expect(monthly.window.resetsAt == ISO8601DateParser.parse("2026-10-22T14:26:29Z"))
        #expect(KimiProviderDescriptor.descriptor.presentation.extraRateWindows(snapshot: usage) == [monthly])

        let output = CLIRenderer.renderText(
            provider: .kimi,
            snapshot: usage,
            credits: nil,
            context: RenderContext(header: "Kimi Code", status: nil, useColor: false, resetStyle: .countdown),
            now: Self.now)
        #expect(output.contains("5-hour usage: 0% left"))
        #expect(output.contains("Total usage: 45% left"))
        #expect(!output.contains("7-day usage:"))
    }

    @Test
    func `reported monthly pool remains visible in the menu card`() throws {
        let model = try KimiMonthlyBlockingTests.model(Self.snapshot())
        let monthly = try #require(model.metrics.first { $0.id == "kimi-monthly" })
        #expect(monthly.title == "Total usage")
        #expect(abs(monthly.percent - 44.69) < 0.00001)
        #expect(model.metrics.first { $0.id == "secondary" }?.percent == 0)
    }

    private static let now = Date(timeIntervalSince1970: 1_791_284_400)

    private static func snapshot() throws -> UsageSnapshot {
        // Exact quota response from #4306; no credentials or account identifiers.
        try KimiUsageFetcher.parseCodeAPIUsage(from: Data("""
        {
            "limits": [{ "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                "detail": { "limit": "100", "used": "100", "resetTime": "2026-10-06T13:23:46.915474Z" } }],
            "usages": {
                "limit_5h": { "used_ratio": 0, "reset_time": "2026-10-06T13:23:46Z" },
                "limit_month_total": { "used_ratio": 0.5531, "reset_time": "2026-10-22T14:26:29Z" },
                "limit_month_code": { "used_ratio": 0, "reset_time": "2026-10-22T14:26:29Z" }
            }
        }
        """.utf8), now: self.now).toUsageSnapshot()
    }
}
