import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIResetCreditPayloadTests {
    @Test
    func `reset credit summary uses the shared available inventory and omits identifiers`() throws {
        let credits = [
            Self.credit("usable-expiring", status: .available, expiresAt: .distantFuture),
            Self.credit("usable-no-expiry", status: .available, expiresAt: nil),
            Self.credit("expired-private-id", status: .available, expiresAt: .distantPast),
            Self.credit("redeemed-private-id", status: .redeemed, expiresAt: .distantFuture),
        ]
        let object = try Self.encodedSummary(credits)
        #expect(object["available"] as? Int == 2)
        #expect(object["nextExpiresAt"] as? Double == Date.distantFuture.timeIntervalSinceReferenceDate)
        let text = try String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        #expect(!text.contains("private-id"))
        #expect(!text.contains("usable-"))
        #expect(Set(object.keys) == ["available", "nextExpiresAt"])
    }

    @Test
    func `empty inventory reports zero despite an outdated aggregate count`() throws {
        let object = try Self.encodedSummary([])
        #expect(object["available"] as? Int == 0)
        #expect(object["nextExpiresAt"] == nil)
    }

    private static func encodedSummary(_ credits: [CodexRateLimitResetCredit]) throws -> [String: Any] {
        let usage = UsageSnapshot(
            primary: nil, secondary: nil,
            codexResetCredits: .init(credits: credits, availableCount: 99, updatedAt: .distantPast),
            updatedAt: .distantPast)
        let payload = ProviderPayload(
            provider: .codex, account: nil, version: nil, source: "fixture", status: nil,
            usage: usage, credits: nil, antigravityPlanInfo: nil, openaiDashboard: nil, error: nil)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        return try #require(object["resetCredits"] as? [String: Any])
    }

    private static func credit(
        _ id: String, status: CodexRateLimitResetCreditStatus, expiresAt: Date?) -> CodexRateLimitResetCredit
    {
        CodexRateLimitResetCredit(
            id: id, resetType: "fixture-reset", status: status, grantedAt: .distantPast,
            expiresAt: expiresAt, redeemStartedAt: nil, redeemedAt: nil, title: nil, description: nil)
    }
}
