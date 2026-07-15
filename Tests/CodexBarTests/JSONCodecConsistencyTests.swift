import CodexBarSync
import Foundation
import Testing

/// Hardening Phase 3 (Build 68 review).
///
/// Build 65/66 root cause: a `JSONEncoder()` constructed with the default
/// `dateEncodingStrategy` (`.deferredToDate` → `Double` since 2001) was
/// paired with a `JSONDecoder()` configured with `.iso8601` (expecting a
/// String). Every payload that contained a non-nil `Date` failed to decode,
/// `try?` swallowed the throw, and the user lost data on every hydrate.
///
/// These tests pin down the factory contract — `CloudSyncConstants.makeJSONEncoder/Decoder`
/// must produce a matched pair, and every CodexBar `Sync*` type that contains
/// `Date` must round-trip through it. New types added to the wire format MUST
/// add a round-trip test here.
@Suite("JSON codec factory consistency")
struct JSONCodecConsistencyTests {
    private let date1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let date2 = Date(timeIntervalSince1970: 1_700_086_400)

    // MARK: - Factory baseline

    @Test
    func `Factory encoder and decoder agree on a Date`() throws {
        struct Box: Codable, Equatable { let when: Date }
        let original = Box(when: date1)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(Box.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func `Default JSONDecoder cannot read what factory encoder produced — proves factory ISN'T the default`() throws {
        struct Box: Codable, Equatable { let when: Date }
        let original = Box(when: date1)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        // Default JSONDecoder uses `.deferredToDate` → expects Double, will
        // fail to decode an ISO8601 string.
        let defaultDecoded = try? JSONDecoder().decode(Box.self, from: encoded)
        #expect(defaultDecoded == nil) // proves the factory is NOT the default
    }

    @Test
    func `Default JSONEncoder produces output the factory decoder CANNOT read`() throws {
        // This is the literal Build 66 bug shape. If this test ever starts
        // succeeding, someone has changed the factory to default — investigate.
        struct Box: Codable, Equatable { let when: Date }
        let original = Box(when: date1)
        let encoded = try JSONEncoder().encode(original)
        let factoryDecoded = try? CloudSyncConstants.makeJSONDecoder().decode(
            Box.self, from: encoded)
        #expect(factoryDecoded == nil)
    }

    // MARK: - Per-type round-trip (every Sync* type with a Date field)

    @Test
    func `SyncRateWindow round-trips with non-nil resetsAt`() throws {
        let original = SyncRateWindow(
            label: "Session",
            usedPercent: 42.0,
            windowMinutes: 300,
            resetsAt: date1,
            resetDescription: "Resets in 2h")
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncRateWindow.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func `SyncBudgetSnapshot round-trips with non-nil resetsAt (the field that broke Build 66)`() throws {
        let original = SyncBudgetSnapshot(
            usedAmount: 12.34,
            limitAmount: 100,
            currencyCode: "USD",
            period: "monthly",
            resetsAt: date2)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncBudgetSnapshot.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func `SyncUtilizationEntry round-trips with both Date fields`() throws {
        let original = SyncUtilizationEntry(
            capturedAt: date1, usedPercent: 50, resetsAt: date2)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncUtilizationEntry.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func `ProviderUsageSnapshot round-trips with all Date-bearing children populated`() throws {
        let window = SyncRateWindow(
            usedPercent: 30, windowMinutes: 300, resetsAt: date1, resetDescription: nil)
        let budget = SyncBudgetSnapshot(
            usedAmount: 5, limitAmount: 100, currencyCode: "USD", period: nil, resetsAt: date2)
        let utilEntry = SyncUtilizationEntry(capturedAt: date1, usedPercent: 25, resetsAt: date2)
        let utilSeries = SyncUtilizationSeries(
            name: "session", windowMinutes: 300, entries: [utilEntry])
        let original = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: window,
            secondary: nil,
            accountEmail: "u@x.com",
            loginMethod: "oauth",
            statusMessage: nil,
            isError: false,
            lastUpdated: date1,
            costSummary: nil,
            budget: budget,
            rateWindows: [window],
            utilizationHistory: [utilSeries])
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageSnapshot.self, from: encoded)
        // Spot-check: most relevant Date fields landed.
        #expect(decoded.lastUpdated == original.lastUpdated)
        #expect(decoded.primary?.resetsAt == original.primary?.resetsAt)
        #expect(decoded.budget?.resetsAt == original.budget?.resetsAt)
        let decodedUtil = decoded.utilizationHistory?.first?.entries.first?.capturedAt
        let originalUtil = original.utilizationHistory?.first?.entries.first?.capturedAt
        #expect(decodedUtil == originalUtil)
        #expect(decoded.rateWindows.count == original.rateWindows.count)
    }

    @Test
    func `SyncedUsageSnapshot round-trips with syncTimestamp`() throws {
        let original = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: date1,
            deviceName: "Mac",
            deviceID: "abc-123",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0",
            notificationPushEnabled: true)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(SyncedUsageSnapshot.self, from: encoded)
        #expect(decoded.syncTimestamp == original.syncTimestamp)
    }

    @Test
    func `ProviderUsageEnvelope round-trips with syncTimestamp`() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "u@x.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: date1)
        let original = ProviderUsageEnvelope(
            deviceID: "abc-123",
            deviceName: "Mac",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0",
            syncTimestamp: date2,
            notificationPushEnabled: true,
            provider: provider)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageEnvelope.self, from: encoded)
        #expect(decoded.syncTimestamp == original.syncTimestamp)
        #expect(decoded.provider.lastUpdated == original.provider.lastUpdated)
    }

    // MARK: - Compressed round-trip (envelope → zlib → CKRecord-like blob → decode)

    @Test
    func `Envelope survives encode → zlib → decompress → decode pipeline (CloudKit-faithful)`() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(
                usedPercent: 70,
                windowMinutes: 300,
                resetsAt: date1,
                resetDescription: nil),
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: date1)
        let envelope = ProviderUsageEnvelope(
            deviceID: "mac-A",
            deviceName: "Mac A",
            appVersion: nil,
            mobileVersion: nil,
            syncTimestamp: date1,
            notificationPushEnabled: nil,
            provider: provider)

        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(envelope)
        let compressed = try PayloadCompression.compress(encoded)
        let decompressed = try PayloadCompression.decompress(compressed)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(
            ProviderUsageEnvelope.self, from: decompressed)

        #expect(decoded.provider.lastUpdated == envelope.provider.lastUpdated)
        #expect(decoded.provider.primary?.resetsAt == envelope.provider.primary?.resetsAt)
    }

    // MARK: - Perplexity credits (T3 · iOS 1.3.0)

    @Test
    func `SyncPerplexityCreditSummary round-trips fully populated (both Date fields)`() throws {
        // Pins the ISO8601 date strategy for the two new Date fields
        // (`promoExpiresAt`, `renewalAt`) — the Build 66 bug shape. If the
        // factory codec ever drifts back to `.deferredToDate`, this test
        // will catch it before it silently drops Perplexity renewal dates
        // on the wire.
        let original = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            promoTotalCents: 5000,
            promoUsedCents: 1000,
            promoExpiresAt: date1,
            purchasedTotalCents: 10000,
            purchasedUsedCents: 0,
            renewalAt: date2,
            planName: "Pro",
            balanceCents: 11500)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(
            SyncPerplexityCreditSummary.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func `SyncPerplexityCreditSummary round-trips with every field nil (free-tier edge case)`() throws {
        // Free-tier Perplexity account: no recurring, no promo, no purchased,
        // no renewal, no plan. Decoder must tolerate all-nil without
        // raising, and encoded output must not produce keys that break the
        // decoder on round-trip.
        let original = SyncPerplexityCreditSummary()
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(
            SyncPerplexityCreditSummary.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func `ProviderUsageSnapshot round-trips with perplexityCredits populated`() throws {
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            promoTotalCents: 5000,
            promoUsedCents: 1000,
            promoExpiresAt: date1,
            purchasedTotalCents: nil,
            purchasedUsedCents: nil,
            renewalAt: date2,
            planName: "Pro",
            balanceCents: 6500)
        let original = ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            primary: nil,
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: date1,
            perplexityCredits: credits)
        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(original)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(
            ProviderUsageSnapshot.self, from: encoded)
        #expect(decoded.perplexityCredits?.renewalAt == original.perplexityCredits?.renewalAt)
        #expect(decoded.perplexityCredits?.promoExpiresAt == original.perplexityCredits?.promoExpiresAt)
        #expect(decoded.perplexityCredits?.recurringUsedCents == 2500)
        #expect(decoded.perplexityCredits?.planName == "Pro")
    }

    @Test
    func `ProviderUsageSnapshot decodes old Mac payloads (no perplexityCredits key)`() throws {
        // Hand-roll the exact JSON shape Mac 0.20.2 produces (pre-T3) —
        // every known key present, no `perplexityCredits`. iOS 1.3.0
        // MUST decode this without error and surface `perplexityCredits ==
        // nil` so the detail view falls back to the generic rate-window
        // list.
        let legacyJSON = """
        {
          "providerID": "perplexity",
          "providerName": "Perplexity",
          "rateWindows": [],
          "isError": false,
          "lastUpdated": "2023-11-14T22:13:20Z"
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(
            ProviderUsageSnapshot.self, from: data)
        #expect(decoded.providerID == "perplexity")
        #expect(decoded.perplexityCredits == nil)
    }

    @Test
    func `Envelope survives encode → zlib → decode with perplexityCredits populated`() throws {
        // Extends envelopeCompressionRoundTrip to cover the Perplexity
        // field under the compression path. `perplexityCredits` rides the
        // same ProviderUsageEnvelope → zlib → CKRecord pipeline as every
        // other optional — this pins that our new field plays nice with
        // the existing compression step (not just the JSON step).
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            promoTotalCents: nil,
            promoUsedCents: nil,
            promoExpiresAt: nil,
            purchasedTotalCents: 10000,
            purchasedUsedCents: 7500,
            renewalAt: date2,
            planName: "Max",
            balanceCents: nil)
        let provider = ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: date1,
            perplexityCredits: credits)
        let envelope = ProviderUsageEnvelope(
            deviceID: "mac-A",
            deviceName: "Mac A",
            appVersion: nil,
            mobileVersion: nil,
            syncTimestamp: date1,
            notificationPushEnabled: nil,
            provider: provider)

        let encoded = try CloudSyncConstants.makeJSONEncoder().encode(envelope)
        let compressed = try PayloadCompression.compress(encoded)
        let decompressed = try PayloadCompression.decompress(compressed)
        let decoded = try CloudSyncConstants.makeJSONDecoder().decode(
            ProviderUsageEnvelope.self, from: decompressed)

        #expect(decoded.provider.perplexityCredits?.planName == "Max")
        #expect(decoded.provider.perplexityCredits?.renewalAt == self.date2)
        #expect(decoded.provider.perplexityCredits?.purchasedUsedCents == 7500)
        // Intentionally-nil fields survive as nil (not 0 / not empty string).
        #expect(decoded.provider.perplexityCredits?.promoTotalCents == nil)
    }
}
