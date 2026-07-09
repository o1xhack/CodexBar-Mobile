import CodexBarSync
import XCTest

@testable import CodexBarMobile

/// Pin the **visible text** the iOS cards render for C1 (Bedrock
/// region) and C2 (Moonshot balance) — not just "view doesn't crash."
///
/// Phase F added `V026ViewSmokeTests` which uses `ImageRenderer` to
/// guarantee the view body executes. That catches nil-deref crashes
/// but **silently passes a card that renders the wrong text** — which
/// is exactly the failure mode of C1/C2: the card rendered, just with
/// the wrong string. These tests close that gap by asserting on the
/// literal string the user sees.
///
/// The helpers under test (`BedrockCostCard.regionLineText`,
/// `MoonshotBalanceCard.formattedAmount`) are the same code paths the
/// SwiftUI body uses — so a future regression in the format string OR
/// in the upstream-mapper data flow (e.g. C1 regression that fed the
/// composite "Spend: $X - Budget: $Y" into `region`) shows up here as
/// a textual mismatch on the asserted string.
final class V026RenderedTextTests: XCTestCase {

    // MARK: - C1: Bedrock region must display the AWS region, NOT the composite cost string

    func testBedrockRenderedRegionShowsCleanAWSRegion() {
        let cost = SyncBedrockCost(
            monthlySpendUSD: 19.10,
            monthlyBudgetUSD: 50.0,
            inputTokens: nil,
            outputTokens: nil,
            region: "us-east-1",
            budgetUsedPercent: 38.2,
            updatedAt: Date())
        let line = BedrockCostCard.regionLineText(for: cost)
        XCTAssertNotNil(line, "Region line must render when region is non-empty")
        // Locale-agnostic: assert the AWS region substring appears.
        // (The wrapping format "Region: %@" / "区域:%@" / "リージョン:%@"
        // varies by simulator locale; the data payload doesn't.)
        XCTAssertTrue(line!.contains("us-east-1"), "Rendered line must show the AWS region — got: \(line!)")
        // C1 regression guard: the line must NOT contain the composite
        // cost-display tokens. If a future change wires `region` back
        // to the Bedrock `loginMethod` (which packs "Spend: $X -
        // Budget: $Y - Tokens: $Z"), these asserts flip.
        XCTAssertFalse(line!.contains("Spend:"), "C1 regression: region must not contain the composite cost string")
        XCTAssertFalse(line!.contains("Budget:"), "C1 regression: region must not contain the composite cost string")
        XCTAssertFalse(line!.contains("Tokens:"), "C1 regression: region must not contain the composite cost string")
    }

    func testBedrockRenderedRegionLineOmittedWhenRegionMissing() {
        let cost = SyncBedrockCost(
            monthlySpendUSD: 3.50,
            monthlyBudgetUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            region: nil,
            budgetUsedPercent: nil,
            updatedAt: Date())
        XCTAssertNil(BedrockCostCard.regionLineText(for: cost), "Region line must be omitted entirely when region is nil")
    }

    func testBedrockRenderedRegionLineOmittedWhenRegionEmpty() {
        let cost = SyncBedrockCost(
            monthlySpendUSD: 3.50,
            monthlyBudgetUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            region: "",
            budgetUsedPercent: nil,
            updatedAt: Date())
        XCTAssertNil(BedrockCostCard.regionLineText(for: cost), "Empty-string region must be treated as missing (skip the line)")
    }

    func testBedrockRenderedSpendRowShowsSpendAndBudget() {
        let cost = SyncBedrockCost(
            monthlySpendUSD: 19.10,
            monthlyBudgetUSD: 50.0,
            inputTokens: nil,
            outputTokens: nil,
            region: "us-west-2",
            budgetUsedPercent: 38.2,
            updatedAt: Date())
        let line = BedrockCostCard.spendRowText(for: cost)
        XCTAssertTrue(line.contains("$19.10"), "Spend value must appear")
        XCTAssertTrue(line.contains("$50.00") || line.contains("$50"), "Budget value must appear when present")
    }

    func testBedrockRenderedSpendRowOmitsBudgetWhenAbsent() {
        let cost = SyncBedrockCost(
            monthlySpendUSD: 3.50,
            monthlyBudgetUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            region: nil,
            budgetUsedPercent: nil,
            updatedAt: Date())
        let line = BedrockCostCard.spendRowText(for: cost)
        XCTAssertTrue(line.contains("3.50"), "Spend value must appear — got: \(line)")
        XCTAssertFalse(line.contains("/"), "Budget separator must be omitted when budget is absent — got: \(line)")
    }

    // MARK: - C2: Moonshot balance must display the actual dollar amount, NOT zero

    func testMoonshotRenderedBalanceShowsNonZero() {
        let formatted = MoonshotBalanceCard.formattedAmount(58.40)
        XCTAssertEqual(formatted, "58.40")
        // C2 regression guard.
        XCTAssertNotEqual(formatted, "0.00", "C2 regression: balance must not silently render as 0")
    }

    func testMoonshotRenderedBalanceTwoDecimalPlaces() {
        // Matches the upstream `UsageFormatter.usdString` convention
        // (2 decimal places) so the iOS card mirrors what the Mac
        // menu displays.
        XCTAssertEqual(MoonshotBalanceCard.formattedAmount(100), "100.00")
        XCTAssertEqual(MoonshotBalanceCard.formattedAmount(0.5), "0.50")
        XCTAssertEqual(MoonshotBalanceCard.formattedAmount(1234.567), "1,234.57")
    }

    func testMoonshotRenderedRegionShowsCleanRegion() {
        let balance = SyncMoonshotBalance(
            balanceAmount: 58.40,
            balanceCurrency: "USD",
            region: "cn-default",
            updatedAt: Date())
        let line = MoonshotBalanceCard.regionLineText(for: balance)
        XCTAssertNotNil(line)
        // Locale-agnostic: assert the region substring appears.
        XCTAssertTrue(line!.contains("cn-default"), "Rendered line must show the region — got: \(line!)")
        // Same C1-style guard — make sure no upstream "Balance: $..."
        // string ends up here by accident.
        XCTAssertFalse(line!.contains("Balance:"))
    }

    func testMoonshotRenderedRegionLineOmittedWhenMissing() {
        let balance = SyncMoonshotBalance(
            balanceAmount: 58.40,
            balanceCurrency: "USD",
            region: nil,
            updatedAt: Date())
        XCTAssertNil(MoonshotBalanceCard.regionLineText(for: balance))
    }
}
