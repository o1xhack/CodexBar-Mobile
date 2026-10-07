import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexMissingResetInventoryTests {
    private let previousTime = Date(timeIntervalSince1970: 1_790_964_643)
    private let initialTime = Date(timeIntervalSince1970: 1_790_967_671)
    private let previousBoundary = Date(timeIntervalSince1970: 1_791_307_920)
    private let freshBoundary = Date(timeIntervalSince1970: 1_791_569_581)

    @Test
    func `issue 4210 publishes two matching fresh reads without historical inventory`() async throws {
        let previous = self.snapshot(at: self.previousTime, used: 99, boundary: self.previousBoundary)
        let initial = self.freshSnapshot(at: self.initialTime)
        let confirmation = self.freshSnapshot(at: self.initialTime.addingTimeInterval(1))

        #expect(CodexWeeklyResetConfirmation.initialDecision(previous: previous, initial: initial)
            == .requiresConfirmation)
        let admission = await self.admit(previous: previous, initial: initial, confirmation: confirmation)
        let published = try #require(admission.outcome).result.get().usage
        #expect(published.secondary?.usedPercent == 1)
        #expect(published.secondary?.resetsAt == self.freshBoundary)
        #expect(published.codexResetCredits?.availableCount == 3)
        #expect(published.updatedAt == confirmation.updatedAt)
        #expect(admission.pendingCandidate == nil)
        #expect(admission.withheldSuccess == nil)
    }

    @Test(arguments: [
        "previous-account", "confirmation-account", "confirmation-plan", "missing-plan", "blank-plans",
        "initial-credits", "confirmation-credits", "changed-credit", "changed-expiry", "changed-multiplicity",
        "partial-inventory", "stale-credits", "invalid-credits", "estimated", "missing-weekly",
        "historical-credits", "concurrent-credits", "historical-credits-unchanged-boundary",
    ])
    func `missing history still requires compatible complete fresh evidence`(rejection: String) async {
        var previous = self.snapshot(at: self.previousTime, used: 99, boundary: self.previousBoundary)
        var initial = self.freshSnapshot(at: self.initialTime)
        var confirmation = self.freshSnapshot(at: self.initialTime.addingTimeInterval(1))
        switch rejection {
        case "previous-account": previous = self.identified(previous, email: "other@example.com")
        case "confirmation-account": confirmation = self.identified(confirmation, email: "other@example.com")
        case "confirmation-plan": confirmation = self.identified(confirmation, plan: "plus")
        case "missing-plan": confirmation = self.identified(confirmation, plan: nil)
        case "blank-plans":
            previous = self.identified(previous, plan: " ")
            initial = self.identified(initial, plan: " ")
            confirmation = self.identified(confirmation, plan: " ")
        case "initial-credits": initial = initial.withCodexResetCredits(nil)
        case "confirmation-credits": confirmation = confirmation.withCodexResetCredits(nil)
        case "changed-credit":
            confirmation = confirmation.withCodexResetCredits(self.credits(
                at: confirmation.updatedAt, ids: ["a", "b", "different"]))
        case "changed-expiry":
            confirmation = confirmation.withCodexResetCredits(self.credits(
                at: confirmation.updatedAt, expiryOffset: 1))
        case "changed-multiplicity":
            initial = initial.withCodexResetCredits(self.credits(at: initial.updatedAt, ids: ["a", "a", "b"]))
            confirmation = confirmation.withCodexResetCredits(self.credits(
                at: confirmation.updatedAt, ids: ["a", "b", "b"]))
        case "partial-inventory":
            confirmation = confirmation.withCodexResetCredits(self.credits(
                at: confirmation.updatedAt, ids: ["a", "b"]))
        case "stale-credits":
            confirmation = confirmation.withCodexResetCredits(self.credits(at: self.previousTime))
        case "historical-credits", "concurrent-credits", "historical-credits-unchanged-boundary":
            if rejection == "historical-credits-unchanged-boundary" {
                previous = self.snapshot(at: self.previousTime, used: 99, boundary: self.freshBoundary)
            }
            let creditTime = self.previousTime.addingTimeInterval(rejection == "concurrent-credits" ? 0 : -1)
            initial = initial.withCodexResetCredits(self.credits(at: creditTime))
            confirmation = confirmation.withCodexResetCredits(self.credits(at: creditTime))
        case "invalid-credits":
            confirmation = confirmation.withCodexResetCredits(self.credits(at: Date(timeIntervalSince1970: .nan)))
        case "estimated": confirmation = confirmation.withDataConfidence(.estimated)
        case "missing-weekly": confirmation = confirmation.with(primary: confirmation.primary, secondary: nil)
        default: Issue.record("Unhandled rejection fixture")
        }
        let admission = await self.admit(previous: previous, initial: initial, confirmation: confirmation)
        #expect(admission.outcome == nil)
        #expect(admission.pendingCandidate == nil)
    }

    @Test
    func `missing history can retain unchanged boundary evidence for delayed confirmation`() async throws {
        let previous = self.snapshot(at: self.previousTime, used: 99, boundary: self.freshBoundary)
        let initial = self.freshSnapshot(at: self.initialTime)
        let confirmation = self.freshSnapshot(at: self.initialTime.addingTimeInterval(1))
        let first = await self.admit(previous: previous, initial: initial, confirmation: confirmation)
        #expect(first.outcome == nil)
        let candidate = try #require(first.pendingCandidate)
        let later = self.freshSnapshot(at: self.initialTime.addingTimeInterval(61))
        let admitted = await UsageStore.codexOutcomeAdmittedForPublication(
            initialOutcome: self.outcome(later),
            previousSnapshot: previous,
            previousSourceLabel: "oauth",
            missingWindowBackfillSnapshot: nil,
            pendingCandidate: candidate,
            observedAt: later.updatedAt,
            fetchConfirmation: {
                Issue.record("Delayed evidence should not require another confirmation")
                return self.outcome(later)
            })
        let published = try #require(admitted.outcome).result.get().usage
        #expect(published.updatedAt == later.updatedAt)
        #expect(published.codexResetCredits?.availableCount == 3)
    }

    private func admit(
        previous: UsageSnapshot,
        initial: UsageSnapshot,
        confirmation: UsageSnapshot) async -> UsageStore.CodexWeeklyResetPublicationAdmission
    {
        await UsageStore.codexOutcomeAdmittedForPublication(
            initialOutcome: self.outcome(initial),
            previousSnapshot: previous,
            previousSourceLabel: "oauth",
            missingWindowBackfillSnapshot: nil,
            observedAt: initial.updatedAt,
            fetchConfirmation: { self.outcome(confirmation) })
    }

    private func freshSnapshot(at time: Date) -> UsageSnapshot {
        self.snapshot(at: time, used: 1, boundary: self.freshBoundary)
            .withCodexResetCredits(self.credits(at: time))
    }

    private func snapshot(at time: Date, used: Double, boundary: Date) -> UsageSnapshot {
        let weekly = RateWindow(
            usedPercent: used, windowMinutes: 10080, resetsAt: boundary, resetDescription: nil)
        return self.identified(UsageSnapshot(primary: nil, secondary: weekly, updatedAt: time))
            .withDataConfidence(.exact)
    }

    private func identified(
        _ snapshot: UsageSnapshot,
        email: String = "quota-fixture@example.com",
        plan: String? = "pro") -> UsageSnapshot
    {
        snapshot.withIdentity(ProviderIdentitySnapshot(
            providerID: .codex, accountEmail: email, accountOrganization: nil, loginMethod: plan))
    }

    private func credits(
        at time: Date,
        ids: [String] = ["a", "b", "c"],
        expiryOffset: TimeInterval = 0) -> CodexRateLimitResetCreditsSnapshot
    {
        let credits = ids.map { id in
            CodexRateLimitResetCredit(
                id: id,
                resetType: "codex_rate_limits",
                status: .available,
                grantedAt: self.previousTime,
                expiresAt: self.freshBoundary.addingTimeInterval(86400 + expiryOffset),
                redeemStartedAt: nil,
                redeemedAt: nil,
                title: nil,
                description: nil)
        }
        return CodexRateLimitResetCreditsSnapshot(credits: credits, availableCount: 3, updatedAt: time)
    }

    private func outcome(_ snapshot: UsageSnapshot) -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: snapshot,
                credits: nil,
                dashboard: nil,
                sourceLabel: "oauth",
                strategyID: "missing-inventory-test",
                strategyKind: .oauth)),
            attempts: [])
    }
}
