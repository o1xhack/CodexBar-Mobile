import Foundation
import Testing
@testable import CodexBarCore

struct QoderUsageFetcherTests {
    @Test
    func `parses documented member quota summary`() async throws {
        let snapshot = try await CookiePluginFixtures.qoder(data: Data(Self.quotaJSON.utf8), now: Self.now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.usedCredits == 125)
        #expect(snapshot.totalCredits == 500)
        #expect(snapshot.remainingCredits == 375)
        #expect(snapshot.usagePercentage == 25)
        #expect(snapshot.unit == "credit")
        #expect(snapshot.resetsAt == Self.resetDate)
        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.resetsAt == Self.resetDate)
        #expect(usage.primary?.windowMinutes == nil)
        #expect(usage.primary?.resetDescription == "125 / 500 credits")
        #expect(usage.identity?.providerID == .qoder)
        #expect(usage.identity?.loginMethod == nil)
    }

    @Test
    func `parses legacy snake case quota summary`() async throws {
        let snapshot = try await CookiePluginFixtures.qoder(data: Data(Self.legacyQuotaJSON.utf8), now: Self.now)

        #expect(snapshot.usedCredits == 125)
        #expect(snapshot.totalCredits == 500)
        #expect(snapshot.remainingCredits == 375)
        #expect(snapshot.usagePercentage == 25)
        #expect(snapshot.unit == "credit")
        #expect(snapshot.resetsAt == Self.resetDate)
    }

    @Test
    func `parses numeric reset timestamp`() async throws {
        let json = Self.quotaJSON.replacing(
            "\"2024-09-01T00:00:00Z\"",
            with: "1725148800000")
        let snapshot = try await CookiePluginFixtures.qoder(data: Data(json.utf8), now: Self.now)

        #expect(snapshot.resetsAt == Self.resetDate)
    }

    @Test
    func `folds shared quota into displayed totals`() async throws {
        let snapshot = try await CookiePluginFixtures.qoder(
            data: Data(Self.sharedQuotaJSON.utf8),
            now: Self.now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.usedCredits == 1700)
        #expect(snapshot.totalCredits == 2500)
        #expect(snapshot.remainingCredits == 800)
        #expect(snapshot.usagePercentage == 68)
        #expect(usage.primary?.usedPercent == 68)
        #expect(usage.primary?.windowMinutes == nil)
        #expect(usage.primary?.resetDescription == "1,700 / 2,500 credits")
        #expect(usage.identity?.loginMethod == nil)
    }

    @Test
    func `zero total zero usage without percentage is exhausted`() async throws {
        let snapshot = try await CookiePluginFixtures.qoder(
            data: Data(Self.zeroTotalQuotaJSON.utf8),
            now: Self.now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.usedCredits == 0)
        #expect(snapshot.totalCredits == 0)
        #expect(snapshot.remainingCredits == 0)
        #expect(snapshot.usagePercentage == 100)
        #expect(usage.primary?.usedPercent == 100)
        #expect(usage.primary?.resetDescription == "0 / 0 credits")
    }

    @Test
    func `negative quota values are invalid`() async {
        await #expect(throws: QoderUsageError.parseFailed("quota values must be nonnegative")) {
            try await CookiePluginFixtures.qoder(
                data: Data(Self.zeroTotalQuotaJSON.replacing("\"usedValue\": 0", with: "\"usedValue\": -1").utf8),
                now: Self.now)
        }
        await #expect(throws: QoderUsageError.parseFailed("quota values must be nonnegative")) {
            try await CookiePluginFixtures.qoder(
                data: Data(Self.zeroTotalQuotaJSON.replacing("\"limitValue\": 0", with: "\"limitValue\": -1").utf8),
                now: Self.now)
        }
        await #expect(throws: QoderUsageError.parseFailed("quota values must be nonnegative")) {
            try await CookiePluginFixtures.qoder(
                data: Data(Self.zeroTotalQuotaJSON.replacing("\"remainingValue\": 0", with: "\"remainingValue\": -1")
                    .utf8),
                now: Self.now)
        }
    }

    @Test
    func `zero total with positive usage is invalid`() async {
        await #expect(throws: QoderUsageError.parseFailed("zero total quota must have zero usage and remaining")) {
            try await CookiePluginFixtures.qoder(
                data: Data(Self.zeroTotalQuotaJSON.replacing("\"usedValue\": 0", with: "\"usedValue\": 1").utf8),
                now: Self.now)
        }
        await #expect(throws: QoderUsageError.parseFailed("zero total quota must have zero usage and remaining")) {
            try await CookiePluginFixtures.qoder(
                data: Data(Self.zeroTotalQuotaJSON.replacing("\"remainingValue\": 0", with: "\"remainingValue\": 1")
                    .utf8),
                now: Self.now)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_719_206_400)
    private static let resetDate = Date(timeIntervalSince1970: 1_725_148_800)

    /// Fixture shape from steipete/CodexBar#1590 (camelCase browser response).
    private static let quotaJSON = """
    {
      "userId": "redacted",
      "quotaKey": "big_model_credits",
      "nextResetAt": "2024-09-01T00:00:00Z",
      "status": "active",
      "totalQuota": {
        "quotaSummary": {
          "usedValue": 125,
          "limitValue": 500,
          "remainingValue": 375,
          "usagePercentage": 25,
          "unit": "credit"
        },
        "quotaDetail": []
      }
    }
    """

    /// Fixture shape from steipete/CodexBar#1590 (snake_case browser response).
    private static let legacyQuotaJSON = """
    {
      "user_id": "redacted",
      "quota_key": "big_model_credits",
      "next_reset_at": "2024-09-01T00:00:00Z",
      "status": "active",
      "total_quota": {
        "quota_summary": {
          "used_value": 125,
          "limit_value": 500,
          "remaining_value": 375,
          "usage_percentage": 25,
          "unit": "credit"
        },
        "quota_detail": []
      }
    }
    """

    /// Team shared add-on credits are separate from totalQuota (plan + resource pack).
    private static let sharedQuotaJSON = """
    {
      "userId": "redacted",
      "quotaKey": "big_model_credits",
      "status": "active",
      "totalQuota": {
        "quotaSummary": {
          "usedValue": 1500,
          "limitValue": 1500,
          "remainingValue": 0,
          "usagePercentage": 100,
          "unit": "credit"
        }
      },
      "sharedQuota": {
        "quotaSummary": {
          "usedValue": 200,
          "limitValue": 1000,
          "remainingValue": 800,
          "usagePercentage": 20,
          "unit": "credit"
        }
      }
    }
    """

    private static let zeroTotalQuotaJSON = """
    {
      "userId": "redacted",
      "quotaKey": "big_model_credits",
      "totalQuota": {
        "quotaSummary": {
          "usedValue": 0,
          "limitValue": 0,
          "remainingValue": 0,
          "unit": "credit"
        },
        "quotaDetail": []
      }
    }
    """
}
