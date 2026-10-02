import AppKit
import CodexBarCore
import SwiftUI
import XCTest
@testable import CodexBar

@MainActor
final class CostHistoryModelNamesRenderTests: XCTestCase {
    func test_renderSyntheticNames() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_MODEL_NAMES_PROOF"] else {
            throw XCTSkip("Set CODEXBAR_MODEL_NAMES_PROOF to render synthetic chart proof")
        }
        let daily = [CostUsageDailyReport.Entry(
            date: "2026-09-27",
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 12345,
            costUSD: nil,
            modelsUsed: ["fictional-model-a", "fictional-model-b"],
            modelBreakdowns: nil)]
        let view = CostHistoryChartMenuView(
            provider: .grok, daily: daily, totalCostUSD: nil, hidePersonalInfo: true, width: 320)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        try XCTUnwrap(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
            .write(to: URL(fileURLWithPath: path))
    }
}
