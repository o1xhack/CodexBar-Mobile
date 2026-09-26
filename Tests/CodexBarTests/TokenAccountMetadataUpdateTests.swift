import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct TokenAccountMetadataUpdateTests {
    @Test
    func `metadata updates distinguish preservation clearing and replacement`() throws {
        let changes: [(update: String??, expected: String?)] = [
            (nil, "original"), (.some(nil), nil), (.some(" \n"), nil), (.some(" updated \n"), "updated"),
        ]
        for change in changes {
            let settings = testSettingsStore(
                suiteName: "TokenAccountMetadataUpdateTests",
                userDefaults: InMemoryUserDefaults(),
                config: testConfigWithAllProvidersDisabled())
            settings.addTokenAccount(
                provider: .copilot,
                label: "Primary",
                token: "fixture-token",
                externalIdentifier: " original ",
                usageScope: " original ",
                organizationID: " original ",
                workspaceID: " original ")
            let original = try #require(settings.selectedTokenAccount(for: .copilot))
            #expect([original.externalIdentifier, original.usageScope, original.organizationID, original.workspaceID]
                == Array(repeating: "original", count: 4))
            settings.updateTokenAccount(
                provider: .copilot, accountID: original.id, seatCreditEntitlement: " original ")

            settings.updateTokenAccount(
                provider: .copilot,
                accountID: original.id,
                externalIdentifier: change.update,
                usageScope: change.update,
                organizationID: change.update,
                workspaceID: change.update,
                seatCreditEntitlement: change.update)

            let updated = try #require(settings.selectedTokenAccount(for: .copilot))
            #expect(updated.id == original.id)
            #expect(updated.token == original.token)
            #expect([
                updated.externalIdentifier, updated.usageScope, updated.organizationID,
                updated.workspaceID, updated.seatCreditEntitlement,
            ] == Array(repeating: change.expected, count: 5))
        }
    }
}
