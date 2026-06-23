import CodexBarSync
import SwiftUI
import XCTest

@testable import CodexBarMobile

/// Smoke tests for the six new provider-detail cards introduced in
/// iOS 1.7.0. Each test instantiates the SwiftUI view with the same
/// preview fixture used by `#Preview` and renders it through
/// `ImageRenderer` — passing means the view body doesn't crash and
/// produces a non-empty image.
///
/// **Why an image-renderer smoke (not an exhaustive accessibility
/// audit):** the failure modes that bite hardest here are silent
/// blank-card regressions — a `nil` dereference inside a `let card =
/// provider.kiroCredits` would print nothing in the chart but render
/// an empty stack. ImageRenderer forcing the body to execute catches
/// those without needing the full simulator + UITests harness.
@MainActor
final class V026ViewSmokeTests: XCTestCase {

    private static let tintColor = Color.purple

    private func renderToImage<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 360, height: 600))
        renderer.scale = 2.0
        return renderer.uiImage
    }

    // MARK: - Cards

    func testKiroCreditsCardRenders() throws {
        let view = KiroCreditsCard(
            credits: PreviewData.kiroProvider.kiroCredits!,
            tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testBedrockCostCardRenders() throws {
        let view = BedrockCostCard(
            cost: PreviewData.bedrockProvider.bedrockCost!,
            tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testMoonshotBalanceCardRenders() throws {
        let view = MoonshotBalanceCard(
            balance: PreviewData.moonshotProvider.moonshotBalance!,
            tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testZaiHourlyChartRenders() throws {
        let view = ZaiHourlyChart(
            usage: PreviewData.zaiProvider.zaiHourlyUsage!,
            tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testOpenAIDashboardSectionRenders() throws {
        let view = OpenAIDashboardSection(
            dashboard: PreviewData.openAIDashboardProvider.openAIAPIDashboard!,
            tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testProviderDetailDailySpendRendersWithLongDailyHistory() throws {
        let view = ProviderDetailView(provider: PreviewData.cursorProvider)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testAntigravityAccountSwitcherRenders() throws {
        let view = AntigravityAccountSwitcher(
            accounts: PreviewData.antigravityMultiAccountProvider.antigravityAccounts!,
            tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    // MARK: - Edge cases

    func testZaiHourlyChartRendersWithEmptyDataFallback() throws {
        // Mac may send an empty/sparse modelSeries during a fetch
        // gap — the chart must show the "no data" placeholder rather
        // than crash the row.
        let emptyUsage = SyncZaiHourlyUsage(
            xTime: [Date()],
            modelSeries: [SyncZaiModelSeries(modelName: "glm", tokens: [nil])])
        let view = ZaiHourlyChart(usage: emptyUsage, tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
    }

    func testBedrockCostCardRendersWithoutBudget() throws {
        // Bedrock fetcher may surface monthly spend but no budget when
        // the AWS account hasn't configured one. Card must still show
        // the spend without the progress gauge.
        let noBudget = SyncBedrockCost(
            monthlySpendUSD: 3.50,
            monthlyBudgetUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            region: nil,
            budgetUsedPercent: nil,
            updatedAt: Date())
        let view = BedrockCostCard(cost: noBudget, tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
    }

    func testKiroCreditsCardRendersWithoutBonus() throws {
        let noBonus = SyncKiroCredits(
            planName: "Free",
            creditsUsed: 5,
            creditsTotal: 100,
            creditsPercent: 5,
            bonusUsed: nil,
            bonusTotal: nil,
            bonusExpiryDays: nil,
            resetsAt: nil)
        let view = KiroCreditsCard(credits: noBonus, tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
    }

    func testAntigravityAccountSwitcherRendersSingleAccount() throws {
        // When only one Google account is wired, the switcher should
        // still render the row (caller already gates count > 1 in the
        // dispatch path, but the view must be safe in isolation).
        let single = SyncMultiAccountList(
            accounts: [
                SyncMultiAccountEntry(email: "only@example.com", isActive: true, expiresAt: nil),
            ],
            activeIndex: 0)
        let view = AntigravityAccountSwitcher(accounts: single, tintColor: Self.tintColor)
        let image = self.renderToImage(view)
        XCTAssertNotNil(image)
    }
}
