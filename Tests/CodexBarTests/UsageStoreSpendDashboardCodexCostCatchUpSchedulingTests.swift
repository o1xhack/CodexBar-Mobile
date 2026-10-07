import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
extension UsageStoreSpendDashboardCodexCostCatchUpTests {
    @Test(arguments: [0.1, 0.75])
    func `shared automatic worker bounds discovery bursts across accounts`(duration: TimeInterval) async throws {
        let store = try Self.makeStore(suite: "bounded-discovery")
        defer { store.cancelSpendDashboardCodexCostCatchUp() }
        store.settings.backgroundWorkLowPowerModePreference = .off
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in .init(pending: true, progressKey: "start") }
        store._test_spendDashboardCodexCostCatchUpActiveDuration = duration
        var advances = 0
        var accountsScanned: Set<String> = []
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { account, _, _ in
            advances += 1
            accountsScanned.insert(account.id)
            return .init(pending: account.id != "first", progressKey: "page-\(advances)")
        }
        var delayed = false
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { delay in
            guard delay > 0 else { return }
            delayed = true
            #expect(advances == (duration == 0.1 ? 8 : 3))
            #expect(abs(delay - Double(advances) * duration * 999) < 0.000001)
            throw CancellationError()
        }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: [
            Self.account(id: "first", cacheIdentity: "first"),
            Self.account(id: "second", cacheIdentity: "second"),
        ])
        await store.spendDashboardCodexCostCatchUpTask?.value
        #expect(delayed)
        #expect(accountsScanned == ["first", "second"])
    }

    @Test(arguments: [false, true])
    func `accelerated work does not accumulate automatic sleep debt`(switchDuringYield: Bool) async throws {
        let store = try Self.makeStore(suite: "acceleration-debt-\(switchDuringYield)")
        defer { store.cancelSpendDashboardCodexCostCatchUp() }
        let accounts = [Self.account(id: "account", cacheIdentity: "cache-account")]
        store.settings.backgroundWorkLowPowerModePreference = .off
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in .init(pending: true, progressKey: "start") }
        store._test_spendDashboardCodexCostCatchUpActiveDuration = 2
        let expectedAdvances = switchDuringYield ? 4 : 3
        var advances = 0
        var switched = false
        var delayed = false
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, _ in
            advances += 1
            guard advances <= expectedAdvances else { throw CancellationError() }
            if advances == 3, !switchDuringYield {
                #expect(store.spendDashboardCodexCostCatchUpPassIsRunning)
                switched = true
                store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
            }
            return .init(pending: true, progressKey: "page-\(advances)")
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { delay in
            if switchDuringYield, advances == 3, !switched {
                #expect(delay == 0)
                #expect(!store.spendDashboardCodexCostCatchUpPassIsRunning)
                switched = true
                store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
                return
            }
            guard delay > 0 else { return }
            delayed = true
            #expect(delay == 1998)
            #expect(advances == expectedAdvances)
            throw CancellationError()
        }
        store.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .accelerated)
        let original = try #require(store.spendDashboardCodexCostCatchUpTask)
        await original.value
        await store.spendDashboardCodexCostCatchUpTask?.value
        #expect(advances == expectedAdvances)
        #expect(delayed)
        #expect(switched)
        #expect(store.spendDashboardCodexCostCatchUpMode == .automatic)
    }
}
