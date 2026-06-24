import Foundation
import Testing
@testable import CodexBarSync

@Suite("v0.37 Codex reset-credit envelope — Codable round-trip + compat")
struct V037SnapshotsCodableTests {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let expiresAt = Date(timeIntervalSince1970: 1_700_086_400)

    private static func sampleCredits() -> SyncCodexResetCredits {
        SyncCodexResetCredits(
            availableCount: 1,
            nextExpiresAt: self.expiresAt,
            credits: [
                SyncCodexResetCredit(
                    id: "credit-1",
                    resetType: "manual",
                    status: "available",
                    grantedAt: self.now,
                    expiresAt: self.expiresAt,
                    redeemStartedAt: nil,
                    redeemedAt: nil,
                    title: "Manual reset",
                    detail: "One-time limit reset"),
            ],
            updatedAt: self.now)
    }

    @Test("SyncCodexResetCredits round-trips with all fields")
    func resetCreditsRoundTrip() throws {
        let source = Self.sampleCredits()
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncCodexResetCredits.self, from: data)
        #expect(decoded == source)
        #expect(decoded.availableCount == 1)
        #expect(decoded.nextExpiresAt == Self.expiresAt)
        #expect(decoded.credits.first?.status == "available")
    }

    @Test("Partial reset-credit payload decodes with defaults")
    func partialResetCreditsPayloadDecodes() throws {
        let json = """
        {"availableCount": 2, "updatedAt": "2023-11-14T22:13:20Z"}
        """
        let decoded = try Self.decoder.decode(SyncCodexResetCredits.self, from: Data(json.utf8))
        #expect(decoded.availableCount == 2)
        #expect(decoded.nextExpiresAt == nil)
        #expect(decoded.credits.isEmpty)
        #expect(decoded.updatedAt == Self.now)
    }

    @Test("ProviderUsageSnapshot carries v0.37 Codex fields through round-trip")
    func providerSnapshotCarriesCodexV037Fields() throws {
        let snap = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "alice@example.com",
            loginMethod: "oauth",
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.now,
            codexResetCredits: Self.sampleCredits(),
            usageDataConfidence: "estimated")
        let data = try Self.encoder.encode(snap)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded.codexResetCredits?.availableCount == 1)
        #expect(decoded.codexResetCredits?.credits.first?.id == "credit-1")
        #expect(decoded.usageDataConfidence == "estimated")
    }

    @Test("Old provider payload without v0.37 fields decodes to nil")
    func oldProviderPayloadDecodesV037FieldsNil() throws {
        let json = """
        {"providerID": "codex", "providerName": "Codex",
         "isError": false, "lastUpdated": "2023-11-14T22:13:20Z"}
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.codexResetCredits == nil)
        #expect(decoded.usageDataConfidence == nil)
        #expect(decoded.providerID == "codex")
    }

    @Test("Future reset-credit status and unknown provider keys are tolerated")
    func futureValuesAreTolerated() throws {
        let json = """
        {"providerID": "codex", "providerName": "Codex",
         "isError": false, "lastUpdated": "2023-11-14T22:13:20Z",
         "codexResetCredits": {
           "availableCount": 1,
           "nextExpiresAt": "2023-11-15T22:13:20Z",
           "updatedAt": "2023-11-14T22:13:20Z",
           "credits": [{
             "id": "credit-future",
             "resetType": "manual",
             "status": "queued",
             "grantedAt": "2023-11-14T22:13:20Z"
           }]
         },
         "usageDataConfidence": "future-confidence",
         "someFutureField_v999": true}
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.codexResetCredits?.credits.first?.status == "queued")
        #expect(decoded.usageDataConfidence == "future-confidence")
    }

    @Test("Partial credit entries decode with defaults")
    func partialCreditEntriesDecodeWithDefaults() throws {
        let json = """
        {"availableCount": 1,
         "updatedAt": "2023-11-14T22:13:20Z",
         "credits": [{"expiresAt": "2023-11-15T22:13:20Z"}]}
        """
        let decoded = try Self.decoder.decode(SyncCodexResetCredits.self, from: Data(json.utf8))
        let credit = try #require(decoded.credits.first)
        #expect(credit.id == "unknown")
        #expect(credit.resetType == "unknown")
        #expect(credit.status == "unknown")
        #expect(credit.grantedAt == .distantPast)
        #expect(credit.expiresAt == Self.expiresAt)
    }
}
