import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct CodexAccountPromotionConcurrencyTests {
    @Test(arguments: [false, true])
    func `managed home cannot also be the live promotion destination`(alias: Bool) async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "promotion-managed-destination")
        defer { container.tearDown() }
        let displaced = try container.createManagedAccount(
            persistedEmail: "original@example.com", authAccountID: "acct-original")
        let target = try container.createManagedAccount(
            persistedEmail: "target@example.com", authAccountID: "acct-target")
        try container.persistAccounts([displaced, target])
        let displacedData = try container.managedAuthData(for: displaced)
        let targetData = try container.managedAuthData(for: target)
        let managedHome = URL(fileURLWithPath: displaced.managedHomePath, isDirectory: true)
        let liveHome = alias ? container.rootURL.appendingPathComponent("alias") : managedHome
        if alias {
            try FileManager.default.createSymbolicLink(at: liveHome, withDestinationURL: managedHome)
        }
        let swapper = RecordingCodexLiveAuthSwapper()
        let transaction = CodexAccountPromotionTransaction(
            store: container.fileStore,
            homeFactory: container.homeFactory,
            authMaterialReader: DefaultCodexAuthMaterialReader(),
            liveAuthSwapper: swapper,
            baseEnvironment: ["CODEX_HOME": liveHome.path])

        await #expect(throws: CodexAccountPromotionError.liveHomeIsManaged) {
            try await transaction.promoteManagedAccount(id: target.id)
        }
        #expect(swapper.swapCallCount == 0)
        #expect(try container.managedAuthData(for: displaced) == displacedData)
        #expect(try container.managedAuthData(for: target) == targetData)
        #expect(try container.loadAccounts().accounts.map(\.id) == [displaced.id, target.id])
    }

    @Test
    func `competing task promotion fails without blocking the main actor`() async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "promotion-competing-task")
        defer { container.tearDown() }
        let target = try container.createManagedAccount(
            persistedEmail: "target@example.com", authAccountID: "acct-target")
        try container.persistAccounts([target])
        let live = try container.writeLiveOAuthAuthFile(email: "original@example.com", accountID: "acct-original")
        let service = container.makeService()

        try await ManagedCodexAccountLock.withLock(at: container.fileStore.lockURL) {
            // Detached tasks model a separate app/CLI operation, without inherited transaction state.
            let competing = Task.detached { await Self.expectBusy(service: service, id: target.id) }
            await competing.value
        }
        #expect(try container.liveAuthData() == live)
        #expect(try container.loadAccounts().accounts.count == 1)
    }

    @Test(arguments: [false, true])
    func `preserved live copy is reverified before the swap removes the original`(importNew: Bool) async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "promotion-preserved-clobbered")
        defer { container.tearDown() }
        let target = try container.createManagedAccount(
            persistedEmail: "target@example.com", authAccountID: "acct-target")
        let destination = try container.createManagedAccount(
            persistedEmail: "original@example.com", authAccountID: "acct-original")
        try container.persistAccounts(importNew ? [target] : [destination, target])
        let originalLive = try container.writeLiveOAuthAuthFile(
            email: "original@example.com", accountID: "acct-original")
        let foreignAuthData = try container.managedAuthData(for: target)
        let destinationHome = URL(fileURLWithPath: destination.managedHomePath, isDirectory: true)
        if importNew { try FileManager.default.removeItem(at: destinationHome) }
        let swapper = RecordingCodexLiveAuthSwapper()
        // The target's second read happens after preservation on both main and the fixed path.
        let transaction = CodexAccountPromotionTransaction(
            store: container.fileStore,
            homeFactory: FixedManagedHomeFactory(base: container.homeFactory, stagedHomeURL: destinationHome),
            authMaterialReader: RacingAuthMaterialReader(
                triggerHomePath: target.managedHomePath,
                triggerOnRead: 2,
                victimHomePath: destination.managedHomePath,
                replacementData: foreignAuthData),
            liveAuthSwapper: swapper,
            baseEnvironment: container.baseEnvironment)

        await #expect(throws: CodexAccountPromotionError.displacedLiveManagedAccountConflict) {
            try await transaction.promoteManagedAccount(id: target.id)
        }
        #expect(swapper.swapCallCount == 0)
        #expect(try container.liveAuthData() == originalLive)
        #expect(try container.managedAuthData(for: destination) == foreignAuthData)
    }

    private static func expectBusy(service: CodexAccountPromotionService, id: UUID) async {
        await #expect(throws: ManagedCodexAccountLockError.busy) {
            try await service.promoteManagedAccount(id: id)
        }
    }

    @Test
    func `external target refresh during preservation prevents stale promotion`() async throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexAccountPromotionServiceTests-target-refresh")
        defer { container.tearDown() }
        let target = try container.createManagedAccount(
            persistedEmail: "target@example.com", authAccountID: "acct-target")
        try container.persistAccounts([target])
        let originalLive = try container.writeLiveOAuthAuthFile(
            email: "original@example.com", accountID: "acct-original")
        let targetURL = URL(fileURLWithPath: target.managedHomePath).appendingPathComponent("auth.json")
        var refreshed = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: targetURL)) as? [String: Any])
        var tokens = try #require(refreshed["tokens"] as? [String: Any])
        tokens["access_token"] = "refreshed-synthetic-access"
        refreshed["tokens"] = tokens
        let refreshedData = try JSONSerialization.data(withJSONObject: refreshed)
        let store = RecordingManagedCodexAccountStore(base: container.fileStore, onStore: { _ in
            try refreshedData.write(to: targetURL, options: .atomic)
        })
        let swapper = RecordingCodexLiveAuthSwapper()

        await #expect(throws: CodexAccountPromotionError.targetAuthChangedDuringPromotion) {
            try await container.makeService(store: store, liveAuthSwapper: swapper)
                .promoteManagedAccount(id: target.id)
        }
        #expect(swapper.swapCallCount == 0)
        #expect(try container.liveAuthData() == originalLive)
        #expect(try container.managedAuthData(for: target) == refreshedData)
    }
}
