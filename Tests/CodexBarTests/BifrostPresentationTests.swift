import AppKit
import SwiftUI
import XCTest
@testable import CodexBar
@testable import CodexBarCore

@MainActor
final class BifrostPresentationTests: XCTestCase {
    func test_resetOnlyQuotaRendersUnavailable() async throws {
        let snapshot = try await BifrostPluginTests.fetch(BifrostPluginTests.quota, engine: .quickJS)
        let model = try Self.model(snapshot)
        let metric = try XCTUnwrap(model.metrics.first { $0.id == "bifrost-requests-1" })
        XCTAssertTrue(metric.statusText?.contains("Unavailable") == true)
        XCTAssertNotNil(model.providerDetails.first { $0.title == "Budgets" }?.rows.first?.progress)
    }

    func test_renderSyntheticCards() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_BIFROST_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set CODEXBAR_BIFROST_SCREENSHOT_DIR to render synthetic Bifrost cards.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let after = try await BifrostPluginTests.fetch(BifrostPluginTests.quota, engine: .quickJS)
        let before = try after.with(extraRateWindows: after.extraRateWindows?.map {
            NamedRateWindow(id: $0.id, title: $0.title, window: $0.window)
        }).with(details: after.details.map { section in
            try ProviderDetailSection(title: section.title, rows: section.rows.map {
                try .init(label: $0.label, value: $0.value, secondaryValue: $0.secondaryValue)
            })
        })
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for (name, snapshot) in [("before", before), ("after", after)] {
                let view = try AnyView(UsageMenuCardView(model: Self.model(snapshot), width: 360)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.colorScheme, .light)
                    .environment(\.displayScale, 2)
                    .background(Color(nsColor: .windowBackgroundColor)))
                let hosting = NSHostingView(rootView: view)
                hosting.appearance = NSAppearance(named: .aqua)
                try XCTUnwrap(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
                    .write(to: directory.appendingPathComponent("bifrost-\(name).png"))
            }
        }
    }

    private static func model(_ snapshot: UsageSnapshot) throws -> UsageMenuCardView.Model {
        try UsageMenuCardView.Model.make(.init(
            provider: .bifrost,
            metadata: XCTUnwrap(ProviderDefaults.metadata[.bifrost]),
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: "api"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .absolute,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: true,
            usesLiveSubtitle: false,
            now: BifrostPluginTests.now))
    }
}
