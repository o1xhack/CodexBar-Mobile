import CodexBarSync
import Testing
@testable import CodexBarMobile

@Suite("Mobile Display Formatting")
@MainActor
struct MobileDisplayFormattingTests {
    @Test("Used mode shows used percent and fill")
    func usedModeValues() {
        let window = SyncRateWindow(usedPercent: 78, windowMinutes: 300, resetsAt: nil, resetDescription: nil)

        #expect(UsagePercentDisplayMode.used.displayedPercent(for: window) == 78)
        #expect(UsagePercentDisplayMode.used.progressFraction(for: window) == 0.78)
        #expect(UsagePercentDisplayMode.used.percentageValueText(for: window) == "78%")
        #expect(UsagePercentDisplayMode.used.percentageText(for: window) == "78% \(String(localized: "used"))")
    }

    @Test("Remaining mode shows inverse percent and fill")
    func remainingModeValues() {
        let window = SyncRateWindow(usedPercent: 78, windowMinutes: 300, resetsAt: nil, resetDescription: nil)

        #expect(UsagePercentDisplayMode.remaining.displayedPercent(for: window) == 22)
        #expect(UsagePercentDisplayMode.remaining.progressFraction(for: window) == 0.22)
        #expect(UsagePercentDisplayMode.remaining.percentageValueText(for: window) == "22%")
        #expect(UsagePercentDisplayMode.remaining.percentageText(for: window) == "22% \(String(localized: "left"))")
    }

    @Test("Positive sub-one values stay visible in used mode")
    func usedModeShowsPositiveSubOnePercent() {
        let window = SyncRateWindow(usedPercent: 0.01, windowMinutes: 300, resetsAt: nil, resetDescription: nil)

        #expect(UsagePercentDisplayMode.used.percentageValueText(for: window) == "<1%")
        #expect(UsagePercentDisplayMode.used.percentageText(for: window) == "<1% \(String(localized: "used"))")
    }

    @Test("Positive sub-one values stay visible in remaining mode")
    func remainingModeShowsPositiveSubOnePercent() {
        let window = SyncRateWindow(usedPercent: 99.99, windowMinutes: 300, resetsAt: nil, resetDescription: nil)

        #expect(UsagePercentDisplayMode.remaining.percentageValueText(for: window) == "<1%")
        #expect(UsagePercentDisplayMode.remaining.percentageText(for: window) == "<1% \(String(localized: "left"))")
    }

    @Test("Exact zero stays zero")
    func exactZeroDoesNotUseLessThanLabel() {
        let window = SyncRateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)

        #expect(UsagePercentDisplayMode.used.percentageValueText(for: window) == "0%")
    }

    @Test("Axis formatter uses clean integer ticks for large values")
    func axisFormatterLargeValues() {
        #expect(MobileChartAxisFormatter.axisValues(for: [12.4, 64.3, 152.71]) == [0, 50, 100, 150, 200])
    }

    @Test("Axis formatter avoids decimal tick labels for small values")
    func axisFormatterSmallValues() {
        #expect(MobileChartAxisFormatter.axisValues(for: [0.18, 1.42, 2.48]) == [0, 1, 2, 3])
        #expect(MobileChartAxisFormatter.axisLabel(for: 3) == "3")
    }

    @Test("Provider daily spend axis shows weekly labels instead of every day")
    func providerDailySpendAxisUsesWeeklyLabels() {
        let points = (1...30).map {
            SyncDailyPoint(
                dayKey: String(format: "2026-06-%02d", $0),
                costUSD: Double($0),
                totalTokens: $0 * 1_000)
        }

        #expect(ProviderDetailView.dailyAxisDayKeys(for: points) == [
            "2026-06-01",
            "2026-06-08",
            "2026-06-15",
            "2026-06-22",
            "2026-06-29",
        ])
    }

    @Test("Provider daily spend axis sorts unsorted points before choosing ticks")
    func providerDailySpendAxisSortsBeforeChoosingTicks() {
        let points = [
            SyncDailyPoint(dayKey: "2026-06-15", costUSD: 15, totalTokens: 15_000),
            SyncDailyPoint(dayKey: "2026-06-01", costUSD: 1, totalTokens: 1_000),
            SyncDailyPoint(dayKey: "2026-06-08", costUSD: 8, totalTokens: 8_000),
        ]

        #expect(ProviderDetailView.sortedDailyPoints(points).map(\.dayKey) == [
            "2026-06-01",
            "2026-06-08",
            "2026-06-15",
        ])
        #expect(ProviderDetailView.dailyAxisDayKeys(for: points) == ["2026-06-01"])
    }

    @Test("Provider daily spend axis label uses compact month slash day text")
    func providerDailySpendAxisLabelUsesCompactText() {
        #expect(ProviderDetailView.dailyAxisLabel(for: "2026-06-15") == "6/15")
        #expect(ProviderDetailView.dailyAxisLabel(for: "not-a-date") == "not-a-date")
    }
}
