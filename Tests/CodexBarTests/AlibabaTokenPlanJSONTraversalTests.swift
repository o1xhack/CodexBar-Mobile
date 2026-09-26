import Foundation
import Testing
@testable import CodexBarCore

struct AlibabaTokenPlanJSONTraversalTests {
    @Test
    func `summary traversal keeps nested arrays and exact key precedence`() throws {
        let json = """
        {
          "envelope": [{"Data": {
            "totalQuota": 100,
            "usedQuota": "invalid",
            "usedCredits": 20,
            "metadata": [{
              "packageName": "Current plan",
              "PLANNAME": "Wrong case",
              "data": {"planName": "Nested plan"}
            }]
          }}]
        }
        """
        let snapshot = try AlibabaTokenPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.planName == "Current plan")
        #expect(snapshot.usedQuota == 20)
        #expect(snapshot.totalQuota == 100)
    }

    @Test
    func `nested reset dates keep the token plan epoch threshold`() throws {
        let json = """
        {
          "Data": {
            "totalQuota": 100,
            "metadata": [{"resetTime": 100, "data": {"resetTime": 1700000000}}]
          }
        }
        """
        let snapshot = try AlibabaTokenPlanUsageFetcher.parseUsageSnapshot(from: Data(json.utf8))

        #expect(snapshot.resetsAt == Date(timeIntervalSince1970: 1_700_000_000))
    }
}
