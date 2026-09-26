import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct UsageStoreTokenRetryPolicyTests {
    @Test
    func `timed out token scans keep the fetch TTL while fast failures retry early`() {
        #expect(UsageStore.tokenFetchFailureRetryDelay(CostUsageError.timedOut(seconds: 600), ttl: 900) == 900)
        #expect(UsageStore.tokenFetchFailureRetryDelay(CocoaError(.fileReadNoSuchFile), ttl: 900) == nil)
        #expect(UsageStore.tokenFetchFailureRetryDelay(CursorStatusProbeError.notLoggedIn, ttl: 900) == nil)
        #expect(UsageStore
            .tokenFetchFailureRetryDelay(CursorStatusProbeError.networkError("HTTP 500"), ttl: 900) == nil)
        #expect(UsageStore
            .tokenFetchFailureRetryDelay(CursorStatusProbeError.networkError("HTTP 403"), ttl: 900) == nil)
    }

    @Test(arguments: [nil, 900, 1800, 43200] as [TimeInterval?])
    func `forbidden costs wait at least six hours when automatic refresh is enabled`(ttl: TimeInterval?) {
        #expect(UsageStore.tokenFetchFailureRetryDelay(CursorStatusProbeError.costRequestForbidden, ttl: ttl)
            == ttl.map { max($0, 21600) })
        #expect(UsageStore.tokenFetchFailureRetryDelay(CostUsageError.timedOut(seconds: 600), ttl: ttl) == ttl)
    }
}
