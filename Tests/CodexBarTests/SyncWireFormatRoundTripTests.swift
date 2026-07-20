// swiftlint:disable multiline_arguments
import CodexBarSync
import Foundation
import Testing

/// Wire-format encode/decode round-trip + cross-version compatibility tests
/// for `ProviderUsageSnapshot` and `SyncedUsageSnapshot` (R5 §B). Verifies:
///
/// 1. Round-trip stability — encode → decode → re-encode produces equivalent
///    JSON for all field combinations (including multi-account scenarios
///    introduced in R1+R2).
/// 2. Backward compatibility — old wire-format payloads (without
///    `accountIdentities`, `perplexityCredits`, `utilizationHistory`,
///    `rateWindows`, etc.) decode correctly into the current model with
///    sensible defaults.
/// 3. Forward compatibility — payloads with unknown fields decode
///    cleanly (Codable's strictness behavior verified).
/// 4. Multi-account specific — distinct `accountEmail` values produce
///    distinct serialized records.
///
/// Without these tests we only know "it works on this build" — these tests
/// pin the contract Mac and iOS share for any version pair (R1+R2 Mac vs.
/// 1.5.x iOS, etc.). Critical because we can't manually run a 2-version
/// matrix on real iCloud.
///
/// See `Research/020-multi-account-comprehensive.md` R5 §B.
struct SyncWireFormatRoundTripTests {
    private func makeRichSnapshot(
        providerID: String = "codex",
        accountEmail: String? = "alice@example.com",
        accountIdentities: [String]? = ["codex:email:alice%40example.com"])
        -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerID.capitalized,
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                resetDescription: "in 1 hour"),
            secondary: SyncRateWindow(
                label: "weekly",
                usedPercent: 60,
                windowMinutes: 10080,
                resetsAt: Date(timeIntervalSince1970: 1_800_604_800),
                resetDescription: "in 7 days"),
            accountEmail: accountEmail,
            loginMethod: "oauth",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            costSummary: SyncCostSummary(
                sessionCostUSD: 1.23,
                sessionTokens: 4567,
                last30DaysCostUSD: 45.67,
                last30DaysTokens: 89012,
                daily: [
                    SyncDailyPoint(
                        dayKey: "2026-04-01",
                        costUSD: 1.5, totalTokens: 1000,
                        modelBreakdowns: [SyncCostBreakdown(label: "gpt-5", costUSD: 1.5)],
                        serviceBreakdowns: [SyncCostBreakdown(label: "codex", costUSD: 1.5)]),
                ],
                isEstimated: false),
            budget: SyncBudgetSnapshot(
                usedAmount: 12.34,
                limitAmount: 100,
                currencyCode: "USD",
                period: "monthly",
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
            rateWindows: [
                SyncRateWindow(
                    label: "5h",
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                    resetDescription: "in 1 hour"),
                SyncRateWindow(
                    label: "weekly",
                    usedPercent: 60,
                    windowMinutes: 10080,
                    resetsAt: Date(timeIntervalSince1970: 1_800_604_800),
                    resetDescription: "in 7 days"),
            ],
            utilizationHistory: [
                SyncUtilizationSeries(
                    name: "session", windowMinutes: 300,
                    entries: [
                        SyncUtilizationEntry(
                            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                            usedPercent: 0.25,
                            resetsAt: Date(timeIntervalSince1970: 1_700_018_000)),
                    ]),
            ],
            perplexityCredits: nil,
            accountIdentities: accountIdentities)
    }

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - 1. Round-trip stability

    @Test
    func `R5 B1: ProviderUsageSnapshot round-trip is byte-stable for fully-populated snapshot`() throws {
        let original = self.makeRichSnapshot()
        let firstPass = try self.encoder().encode(original)
        let decoded = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: firstPass)
        let secondPass = try self.encoder().encode(decoded)
        #expect(
            firstPass == secondPass,
            "encode → decode → re-encode must produce byte-identical output")
    }

    @Test
    func `R5 B2: minimal-fields snapshot round-trips`() throws {
        let minimal = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        let json = try self.encoder().encode(minimal)
        let decoded = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: json)
        #expect(decoded.providerID == "codex")
        #expect(decoded.accountEmail == nil)
        #expect(decoded.accountIdentities == nil)
        #expect(decoded.rateWindows.isEmpty)
    }

    @Test
    func `R5 B2b: CrossModel optional payload round-trips`() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: "crossmodel",
            providerName: "CrossModel",
            primary: nil,
            secondary: nil,
            accountEmail: "wallet@example.com",
            loginMethod: "API key",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            crossModelUsage: SyncCrossModelUsage(
                currency: "USD",
                balance: 8.06,
                uncollected: 0.42,
                daily: .init(
                    cost: 0.27,
                    promptTokens: 5200,
                    completionTokens: 7267,
                    totalTokens: 12467,
                    requestCount: 84,
                    successCount: 83),
                weekly: nil,
                monthly: .init(
                    cost: 5.37,
                    promptTokens: 110_000,
                    completionTokens: 150_000,
                    totalTokens: 260_000,
                    requestCount: 3166,
                    successCount: 3140),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let data = try self.encoder().encode(snapshot)
        let decoded = try self.decoder().decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded.crossModelUsage?.balance == 8.06)
        #expect(decoded.crossModelUsage?.monthly?.requestCount == 3166)
    }

    @Test
    func `R5 B2c: v0.45 provider optional payloads round-trip`() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: "wayfinder",
            providerName: "Wayfinder",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Local gateway",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            wayfinderUsage: SyncWayfinderUsage(
                gatewayStatus: "healthy",
                offline: false,
                dryRun: false,
                missingKeyCount: 0,
                modelCount: 6,
                requests: 1420,
                tokens: 8_600_000,
                realized: 7.84,
                baseline: 12.68,
                saved: 4.84,
                savedPercent: 38.2,
                priced: true,
                routes: [.init(name: "local", requests: 960, saved: 3.61, tokens: 5_900_000)],
                averageDecisionMilliseconds: 7.4,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            sub2APIUsage: SyncSub2APIUsage(
                kind: "subscription",
                balance: 61.6,
                unit: "USD",
                today: .init(requests: 84, totalTokens: 12467, actualCostUSD: 0.27),
                total: .init(requests: 3166, totalTokens: 260_000, actualCostUSD: 5.37)))
        let data = try self.encoder().encode(snapshot)
        let decoded = try self.decoder().decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded.wayfinderUsage?.routes.first?.name == "local")
        #expect(decoded.wayfinderUsage?.savedPercent == 38.2)
        #expect(decoded.sub2APIUsage?.today?.requests == 84)
        #expect(decoded.sub2APIUsage?.balance == 61.6)
    }

    @Test
    func `R5 B3: SyncedUsageSnapshot with multiple multi-account providers round-trips`() throws {
        let alice = self.makeRichSnapshot(
            accountEmail: "alice@example.com",
            accountIdentities: ["codex:email:alice%40example.com"])
        let bob = self.makeRichSnapshot(
            accountEmail: "bob@example.com",
            accountIdentities: ["codex:email:bob%40example.com"])
        let claude = self.makeRichSnapshot(
            providerID: "claude",
            accountEmail: "claude-user@example.com",
            accountIdentities: ["claude:email:claude-user%40example.com"])
        let payload = SyncedUsageSnapshot(
            providers: [alice, bob, claude],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_001_000),
            deviceName: "Test Mac",
            deviceID: "device-uuid-1234",
            appVersion: "0.23.4",
            mobileVersion: "1.5.1")
        let json = try self.encoder().encode(payload)
        let decoded = try self.decoder().decode(
            SyncedUsageSnapshot.self, from: json)
        #expect(decoded.providers.count == 3)
        let emails = Set(decoded.providers.compactMap(\.accountEmail))
        #expect(
            emails == [
                "alice@example.com",
                "bob@example.com",
                "claude-user@example.com",
            ])
    }

    // MARK: - 2. Backward compatibility (old payload → current model)

    @Test
    func `R5 B4: pre-1.2.0 payload (no rateWindows / costSummary / budget / accountIdentities) decodes`() throws {
        // What a Mac on iOS 1.1.0 era would have written — only
        // primary/secondary, no extras.
        let legacyJSON = """
        {
            "providerID": "codex",
            "providerName": "Codex",
            "isError": false,
            "lastUpdated": "2024-01-01T00:00:00Z",
            "primary": {
                "usedPercent": 25.0,
                "windowMinutes": 300,
                "resetsAt": "2024-01-01T01:00:00Z",
                "resetDescription": "in 1 hour"
            }
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: data)
        #expect(decoded.providerID == "codex")
        #expect(decoded.primary?.usedPercent == 25.0)
        #expect(decoded.rateWindows.isEmpty, "missing rateWindows defaults to []")
        #expect(decoded.costSummary == nil)
        #expect(decoded.budget == nil)
        #expect(decoded.accountIdentities == nil, "missing accountIdentities defaults to nil")
        #expect(decoded.perplexityCredits == nil)
        #expect(decoded.utilizationHistory == nil)
    }

    @Test
    func `R5 B5: payload from 1.2.x with utilizationHistory but no perplexityCredits decodes`() throws {
        // 1.2.x added utilizationHistory but predates 1.3.0's
        // perplexityCredits field.
        let payload12X = """
        {
            "providerID": "claude",
            "providerName": "Claude",
            "isError": false,
            "lastUpdated": "2025-04-01T00:00:00Z",
            "rateWindows": [
                {
                    "label": "session", "usedPercent": 30, "windowMinutes": 300,
                    "resetsAt": "2025-04-01T01:00:00Z", "resetDescription": "1h"
                },
                {
                    "label": "weekly", "usedPercent": 50, "windowMinutes": 10080,
                    "resetsAt": "2025-04-08T00:00:00Z", "resetDescription": "7d"
                }
            ],
            "utilizationHistory": [
                {"name": "session", "windowMinutes": 300, "entries": []}
            ],
            "accountEmail": "user@anthropic.com",
            "loginMethod": "oauth"
        }
        """
        let data = try #require(payload12X.data(using: .utf8))
        let decoded = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: data)
        #expect(decoded.providerID == "claude")
        #expect(decoded.rateWindows.count == 2)
        #expect(decoded.utilizationHistory?.count == 1)
        #expect(decoded.perplexityCredits == nil)
        #expect(decoded.accountIdentities == nil)
    }

    @Test
    func `R5 B6: payload from pre-Mac-0.23 lacks accountIdentities (Tier-A providers)`() throws {
        // Mac < 0.23 didn't write accountIdentities. iOS new should
        // gracefully decode with nil and fall back to per-device legacy
        // bucket (no cross-Mac merge).
        let payload = """
        {
            "providerID": "codex",
            "providerName": "Codex",
            "isError": false,
            "lastUpdated": "2025-12-01T00:00:00Z",
            "accountEmail": "alice@example.com",
            "loginMethod": "oauth",
            "rateWindows": []
        }
        """
        let data = try #require(payload.data(using: .utf8))
        let decoded = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: data)
        #expect(decoded.accountIdentities == nil)
    }

    // MARK: - 3. Forward compatibility (payload with future fields → current model)

    @Test
    func `R5 B7: payload with unknown future fields decodes (ignored)`() throws {
        // A future Mac version might add `tier` or `experimentalFeature`.
        // Current iOS must decode without error, ignoring unknowns.
        let payloadWithUnknowns = """
        {
            "providerID": "codex",
            "providerName": "Codex",
            "isError": false,
            "lastUpdated": "2026-04-01T00:00:00Z",
            "accountEmail": "alice@example.com",
            "futureFieldString": "experimental-value",
            "futureFieldArray": ["a", "b", "c"],
            "futureFieldNested": {"x": 1, "y": 2}
        }
        """
        let data = try #require(payloadWithUnknowns.data(using: .utf8))
        // Must not throw.
        let decoded = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: data)
        #expect(decoded.providerID == "codex")
        #expect(decoded.accountEmail == "alice@example.com")
    }

    // MARK: - 4. Multi-account scenarios

    @Test
    func `R5 B8: distinct accountEmail produce distinct JSON`() throws {
        let alice = self.makeRichSnapshot(accountEmail: "alice@x.com")
        let bob = self.makeRichSnapshot(accountEmail: "bob@x.com")
        let aliceJSON = try self.encoder().encode(alice)
        let bobJSON = try self.encoder().encode(bob)
        #expect(aliceJSON != bobJSON, "distinct accountEmail must distinguish snapshots in wire format")
    }

    @Test
    func `R5 B9: distinct accountIdentities produce distinct JSON`() throws {
        let withOrgA = self.makeRichSnapshot(
            accountEmail: nil,
            accountIdentities: ["codex:account:org-a"])
        let withOrgB = self.makeRichSnapshot(
            accountEmail: nil,
            accountIdentities: ["codex:account:org-b"])
        let aJSON = try self.encoder().encode(withOrgA)
        let bJSON = try self.encoder().encode(withOrgB)
        #expect(aJSON != bJSON)
    }

    @Test
    func `R5 B10: nil vs empty array accountIdentities are distinct after round-trip`() throws {
        let withNil = self.makeRichSnapshot(
            accountEmail: "user@x.com", accountIdentities: nil)
        let withEmpty = self.makeRichSnapshot(
            accountEmail: "user@x.com", accountIdentities: [])

        let nilJSON = try self.encoder().encode(withNil)
        let emptyJSON = try self.encoder().encode(withEmpty)
        // Both encode identifiably (nil omits the key, empty includes []).
        let decodedNil = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: nilJSON)
        let decodedEmpty = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: emptyJSON)
        #expect(decodedNil.accountIdentities == nil)
        #expect(decodedEmpty.accountIdentities == [])
    }

    // MARK: - Edge cases: non-ASCII, whitespace, empty

    @Test
    func `R5 B11: non-ASCII accountEmail (café@example.com) round-trips through UTF-8`() throws {
        let cafe = self.makeRichSnapshot(
            accountEmail: "café@münich.example.com",
            accountIdentities: ["codex:email:caf%C3%A9%40m%C3%BCnich.example.com"])
        let json = try self.encoder().encode(cafe)
        let decoded = try self.decoder().decode(
            ProviderUsageSnapshot.self, from: json)
        #expect(decoded.accountEmail == "café@münich.example.com")
        #expect(decoded.accountIdentities?.first?.contains("caf%C3%A9") == true)
    }

    @Test
    func `R5 B12: empty-string vs nil accountEmail are distinct`() throws {
        let withNil = self.makeRichSnapshot(accountEmail: nil)
        let withEmpty = self.makeRichSnapshot(accountEmail: "")
        let nilJSON = try self.encoder().encode(withNil)
        let emptyJSON = try self.encoder().encode(withEmpty)
        #expect(nilJSON != emptyJSON, "nil and empty-string accountEmail must serialize distinguishably")
    }

    @Test
    func `v045 opaque account key and uncapped amount round-trip additively`() throws {
        let source = ProviderUsageSnapshot(
            providerID: "neuralwatt", providerName: "Neuralwatt",
            primary: nil, secondary: nil,
            accountEmail: "Duplicate | label", loginMethod: nil,
            statusMessage: nil, isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            providerAmount: SyncProviderAmount(
                kind: "balance", amount: 12.5, currencyCode: "USD",
                period: "Prepaid balance", isEstimated: false),
            accountRecordKey: "token-1234")
        let data = try self.encoder().encode(source)
        let decoded = try self.decoder().decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded.providerAmount?.kind == "balance")
        #expect(decoded.providerAmount?.amount == 12.5)
        #expect(decoded.accountRecordKey == "token-1234")
        #expect(decoded.hasUsableSignal)
    }
}

// swiftlint:enable multiline_arguments
