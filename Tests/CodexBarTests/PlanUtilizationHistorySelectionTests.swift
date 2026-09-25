import Testing
@testable import CodexBar

struct PlanUtilizationHistorySelectionTests {
    @Test
    func `bucket selection keeps account identity separate from unavailable history`() {
        let histories = [planSeries(name: .session, windowMinutes: 300, entries: [])]
        let buckets = PlanUtilizationHistoryBuckets(unscoped: histories, accounts: ["fixture": histories])
        for accountKey: String? in [nil, "", "fixture", "missing"] {
            let selection = buckets.selection(for: accountKey)
            #expect(selection.accountKey == accountKey)
            #expect(selection.histories == (accountKey == "missing" ? [] : histories))
            #expect(selection
                .cacheIdentity == "account:\(accountKey ?? UsageStore.planUtilizationUnscopedPreferredKey)")
            #expect(selection.cacheIdentity != PlanUtilizationHistorySelection.unavailable.cacheIdentity)
        }
    }
}
