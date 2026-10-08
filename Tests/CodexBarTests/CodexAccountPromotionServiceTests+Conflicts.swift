import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

extension CodexAccountPromotionServiceTests {
    @Test(arguments: [nil, "acct-alpha"] as [String?])
    func `promotion preserves a divergent readable home matched only by legacy email`(
        liveAccountID: String?) async throws
    {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexAccountPromotionServiceTests-legacy-email-readable-conflict")
        defer { container.tearDown() }

        let target = try container.createManagedAccount(
            persistedEmail: "beta@example.com",
            authAccountID: "acct-beta")
        let divergentManaged = try container.createManagedAccount(
            persistedEmail: "alpha@example.com",
            authAccountID: "acct-gamma",
            legacyRecord: true)
        try container.persistAccounts([target, divergentManaged])
        let liveAuthData = try container.writeLiveOAuthAuthFile(email: "alpha@example.com", accountID: liveAccountID)
        let divergentAuthData = try container.managedAuthData(for: divergentManaged)
        let managedHomePaths = try Set(container.managedHomeURLs().map(\.path))
        let swapper = RecordingCodexLiveAuthSwapper()

        await #expect(throws: CodexAccountPromotionError.displacedLiveManagedAccountConflict) {
            try await container.makeService(liveAuthSwapper: swapper).promoteManagedAccount(id: target.id)
        }

        let accounts = try container.loadAccounts().accounts
        let persistedDivergent = try #require(accounts.first(where: { $0.id == divergentManaged.id }))
        #expect(try container.liveAuthData() == liveAuthData)
        #expect(try container.managedAuthData(for: persistedDivergent) == divergentAuthData)
        #expect(persistedDivergent.effectiveWorkspaceAccountID == nil)
        #expect(accounts.count == 2)
        #expect(swapper.swapCallCount == 0)
        #expect(try Set(container.managedHomeURLs().map(\.path)) == managedHomePaths)
    }
}
