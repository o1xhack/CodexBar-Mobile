import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Sync Model Codable Tests")
struct SyncModelTests {
    @Test("ProviderUsageSnapshot round-trips through JSON")
    func providerSnapshotCodable() throws {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: SyncRateWindow(
                usedPercent: 42.5,
                windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
                resetDescription: "Resets in 2h 30m"),
            secondary: SyncRateWindow(
                usedPercent: 15.0,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: "Resets Monday"),
            accountEmail: "user@example.com",
            loginMethod: "Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            subscriptionExpiresAt: Date(timeIntervalSince1970: 1_701_000_000),
            subscriptionRenewsAt: Date(timeIntervalSince1970: 1_700_500_000))

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(snapshot)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.providerID == "claude")
        #expect(decoded.providerName == "Claude")
        #expect(decoded.primary?.usedPercent == 42.5)
        #expect(decoded.primary?.windowMinutes == 300)
        #expect(decoded.primary?.remainingPercent == 57.5)
        #expect(decoded.secondary?.usedPercent == 15.0)
        #expect(decoded.accountEmail == "user@example.com")
        #expect(decoded.loginMethod == "Pro")
        #expect(decoded.isError == false)
        #expect(decoded.costSummary == nil)
        #expect(decoded.budget == nil)
        #expect(decoded.subscriptionExpiresAt == Date(timeIntervalSince1970: 1_701_000_000))
        #expect(decoded.subscriptionRenewsAt == Date(timeIntervalSince1970: 1_700_500_000))
    }

    @Test("SyncedUsageSnapshot round-trips through JSON")
    func syncedSnapshotCodable() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(
                usedPercent: 80.0,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: "Rate limited",
            isError: true,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))

        let synced = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Mac",
            deviceID: "test-uuid-123")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: data)

        #expect(decoded.providers.count == 1)
        #expect(decoded.providers[0].providerID == "codex")
        #expect(decoded.providers[0].isError == true)
        #expect(decoded.deviceName == "Test Mac")
        #expect(decoded.deviceID == "test-uuid-123")
    }

    @Test("SyncedUsageSnapshot without deviceID decodes with nil (backward compat)")
    func deviceIDBackwardCompat() throws {
        let oldJSON = """
        {
            "providers": [],
            "syncTimestamp": "2023-11-14T22:13:20Z",
            "deviceName": "Old Mac"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: Data(oldJSON.utf8))

        #expect(decoded.deviceName == "Old Mac")
        #expect(decoded.deviceID == nil)
    }

    @Test("SyncRateWindow remainingPercent clamps to zero")
    func remainingPercentClamped() {
        let window = SyncRateWindow(
            usedPercent: 150.0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil)
        #expect(window.remainingPercent == 0)
    }

    @Test("Empty provider list encodes correctly")
    func emptyProviders() throws {
        let synced = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Empty Mac")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)
        #expect(data.count < CloudSyncConstants.maxPayloadBytes)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: data)
        #expect(decoded.providers.isEmpty)
    }

    // MARK: - Backward Compatibility

    @Test("Old JSON without cost fields decodes correctly")
    func backwardCompatibility() throws {
        // Simulate a payload from an older Mac app that doesn't include costSummary/budget
        let oldJSON = """
        {
            "providerID": "claude",
            "providerName": "Claude",
            "primary": {
                "usedPercent": 42.5,
                "windowMinutes": 300
            },
            "accountEmail": "user@example.com",
            "loginMethod": "Pro",
            "isError": false,
            "lastUpdated": "2023-11-14T22:13:20Z"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: Data(oldJSON.utf8))

        #expect(decoded.providerID == "claude")
        #expect(decoded.primary?.usedPercent == 42.5)
        #expect(decoded.costSummary == nil)
        #expect(decoded.budget == nil)
        #expect(decoded.subscriptionExpiresAt == nil)
        #expect(decoded.subscriptionRenewsAt == nil)
        #expect(decoded.secondary == nil)
        #expect(decoded.statusMessage == nil)
    }

    // MARK: - Cost Data Round-Trip

    @Test("Cost summary and budget round-trip through JSON")
    func costDataRoundTrip() throws {
        let daily = [
            SyncDailyPoint(
                dayKey: "2024-01-15",
                costUSD: 1.42,
                totalTokens: 12340,
                modelBreakdowns: [
                    SyncCostBreakdown(label: "gpt-5.4", costUSD: 1.10),
                    SyncCostBreakdown(label: "gpt-5.3-codex", costUSD: 0.32),
                ],
                serviceBreakdowns: [SyncCostBreakdown(label: "Codex Run", costUSD: 1.42)]),
            SyncDailyPoint(dayKey: "2024-01-16", costUSD: 2.10, totalTokens: 18500),
        ]

        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            costSummary: SyncCostSummary(
                sessionCostUSD: 1.42,
                sessionTokens: 12340,
                last30DaysCostUSD: 28.90,
                last30DaysTokens: 1_245_000,
                daily: daily),
            budget: SyncBudgetSnapshot(
                usedAmount: 42.50,
                limitAmount: 100.0,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: Date(timeIntervalSince1970: 1_701_000_000)))

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(snapshot)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.costSummary?.sessionCostUSD == 1.42)
        #expect(decoded.costSummary?.sessionTokens == 12340)
        #expect(decoded.costSummary?.last30DaysCostUSD == 28.90)
        #expect(decoded.costSummary?.last30DaysTokens == 1_245_000)
        #expect(decoded.costSummary?.daily.count == 2)
        #expect(decoded.costSummary?.daily[0].dayKey == "2024-01-15")
        #expect(decoded.costSummary?.daily[0].costUSD == 1.42)
        #expect(decoded.costSummary?.daily[0].totalTokens == 12340)
        #expect(decoded.costSummary?.daily[0].modelBreakdowns == [
            SyncCostBreakdown(label: "gpt-5.4", costUSD: 1.10),
            SyncCostBreakdown(label: "gpt-5.3-codex", costUSD: 0.32),
        ])
        #expect(decoded.costSummary?.daily[0].serviceBreakdowns == [
            SyncCostBreakdown(label: "Codex Run", costUSD: 1.42),
        ])

        #expect(decoded.budget?.usedAmount == 42.50)
        #expect(decoded.budget?.limitAmount == 100.0)
        #expect(decoded.budget?.currencyCode == "USD")
        #expect(decoded.budget?.period == "Monthly")
        #expect(decoded.budget?.resetsAt != nil)
    }

    // MARK: - Payload Size

    // MARK: - Version Fields

    @Test("SyncedUsageSnapshot includes appVersion and mobileVersion")
    func versionFieldsRoundTrip() throws {
        let synced = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Mac",
            appVersion: "0.18.0-beta.3",
            mobileVersion: "1.0.0")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: data)

        #expect(decoded.appVersion == "0.18.0-beta.3")
        #expect(decoded.mobileVersion == "1.0.0")
    }

    @Test("Legacy syncVersion key decodes into mobileVersion")
    func legacySyncVersionBackwardCompat() throws {
        let legacyJSON = """
        {
            "providers": [],
            "syncTimestamp": "2023-11-14T22:13:20Z",
            "deviceName": "Old Mac",
            "appVersion": "0.17.0",
            "syncVersion": "0.1.0"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(decoded.mobileVersion == "0.1.0")
    }

    @Test("Old payload without version fields decodes with nil")
    func versionFieldsBackwardCompat() throws {
        let oldJSON = """
        {
            "providers": [],
            "syncTimestamp": "2023-11-14T22:13:20Z",
            "deviceName": "Old Mac"
        }
        """

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: Data(oldJSON.utf8))

        #expect(decoded.deviceName == "Old Mac")
        #expect(decoded.appVersion == nil)
        #expect(decoded.mobileVersion == nil)
    }

    // MARK: - Payload Size

    @Test("10 providers x 30 days stays under 1MB KVS limit")
    func payloadSizeCheck() throws {
        let daily = (0..<30).map { day in
            SyncDailyPoint(
                dayKey: "2024-01-\(String(format: "%02d", day + 1))",
                costUSD: Double.random(in: 0.10...5.00),
                totalTokens: Int.random(in: 1000...100_000),
                modelBreakdowns: [
                    SyncCostBreakdown(label: "Model A", costUSD: 0.7),
                    SyncCostBreakdown(label: "Model B", costUSD: 0.3),
                ])
        }

        let costSummary = SyncCostSummary(
            sessionCostUSD: 2.50,
            sessionTokens: 25000,
            last30DaysCostUSD: 45.00,
            last30DaysTokens: 2_000_000,
            daily: daily)

        let budget = SyncBudgetSnapshot(
            usedAmount: 60.0,
            limitAmount: 100.0,
            currencyCode: "USD",
            period: "Monthly",
            resetsAt: Date(timeIntervalSince1970: 1_701_000_000))

        let providers = (0..<10).map { i in
            ProviderUsageSnapshot(
                providerID: "provider-\(i)",
                providerName: "Provider \(i)",
                primary: SyncRateWindow(
                    usedPercent: Double(i * 15),
                    windowMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
                    resetDescription: nil),
                secondary: SyncRateWindow(
                    usedPercent: Double(i * 10),
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: nil),
                accountEmail: "user\(i)@example.com",
                loginMethod: "Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
                costSummary: costSummary,
                budget: budget)
        }

        let synced = SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Mac")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let data = try encoder.encode(synced)

        // iCloud KVS limit is 1MB per key
        #expect(data.count < CloudSyncConstants.maxPayloadBytes)
    }

    @Test("Cost dashboard insights aggregate ten providers")
    func costDashboardInsightsHandleManyProviders() {
        var providers: [ProviderUsageSnapshot] = []
        var expectedTotal30DayCost = 0.0

        for index in 0..<10 {
            let dayCost = Double(index + 1) * 0.9
            let last30DayCost = Double(index + 1) * 3.5
            let daily = [
                SyncDailyPoint(
                    dayKey: "2024-01-\(String(format: "%02d", index + 1))",
                    costUSD: dayCost,
                    totalTokens: (index + 1) * 1500,
                    modelBreakdowns: [
                        SyncCostBreakdown(label: "Model \(index % 3)", costUSD: Double(index + 1) * 0.5),
                    ],
                    serviceBreakdowns: index == 0
                        ? [SyncCostBreakdown(label: "Codex Run", costUSD: 0.9)]
                        : []),
            ]
            let costSummary = SyncCostSummary(
                sessionCostUSD: Double(index + 1) * 0.4,
                sessionTokens: (index + 1) * 1000,
                last30DaysCostUSD: last30DayCost,
                last30DaysTokens: (index + 1) * 10000,
                daily: daily)
            let budget = SyncBudgetSnapshot(
                usedAmount: Double(index + 1) * 5,
                limitAmount: 100,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: nil)

            providers.append(
                ProviderUsageSnapshot(
                    providerID: "provider-\(index)",
                    providerName: "Provider \(index)",
                    primary: nil,
                    secondary: nil,
                    accountEmail: "user\(index)@example.com",
                    loginMethod: index.isMultiple(of: 2) ? "API" : "Plan",
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                    costSummary: costSummary,
                    budget: budget))
            expectedTotal30DayCost += last30DayCost
        }

        let snapshot = SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Mac")
        let insights = CostDashboardInsights(snapshot: snapshot)

        #expect(insights.providerRows.count == 10)
        #expect(insights.budgetRows.count == 10)
        #expect(insights.dailyPoints.count == 10)
        #expect(insights.total30DayCost == expectedTotal30DayCost)
        #expect(insights.serviceRows.first?.label == "Codex Run")
        #expect(insights.hasDisplayData == true)
    }

    // MARK: - Future-field resilience (Build 78 · Fix C)
    //
    // Scenario: Mac 0.21 (hypothetical future version) adds a new field to
    // `ProviderUsageSnapshot` or `SyncedUsageSnapshot` that iOS 1.3.0 doesn't
    // know about. Mac pushes a CKRecord whose JSON payload includes the new
    // key. iOS 1.3.0's decoder must **silently ignore** the unknown key and
    // preserve all known fields — any `throws` would cascade through
    // `CloudSyncManager.decodeEnvelope(from:)` → `return nil`, and that one
    // Mac's data would vanish from the iPhone view until the user upgraded iOS.
    //
    // These tests synthesize the scenario by encoding a real snapshot, injecting
    // unknown keys at the JSON-dict level, re-encoding, and asserting round-trip.
    // Swift's synthesized + custom `init(from:)` behavior both SHOULD tolerate
    // unknown keys (keyed containers don't fail on unknown keys unless you
    // explicitly enumerate them), but without a pinned test, a future refactor
    // to a strict decoder would silently break all iOS-reading-newer-Mac paths.

    private static func injectFutureFields(
        into data: Data,
        extras: [String: Any]
    ) throws -> Data {
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FutureFieldTestError.notATopLevelDictionary
        }
        for (key, value) in extras { dict[key] = value }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private enum FutureFieldTestError: Error {
        case notATopLevelDictionary
    }

    @Test("ProviderUsageSnapshot tolerates unknown future fields at the JSON top level")
    func providerSnapshotTolerantOfFutureFields() throws {
        let original = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: SyncRateWindow(
                usedPercent: 42.5, windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
                resetDescription: nil),
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: "Pro", statusMessage: nil, isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "futureFieldFromMac021": "hello world",
            "someInt": 42,
            "someNested": ["a": 1, "b": 2],
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: augmented)

        // All known fields survived; unknown fields were silently dropped.
        #expect(decoded.providerID == "claude")
        #expect(decoded.providerName == "Claude")
        #expect(decoded.primary?.usedPercent == 42.5)
        #expect(decoded.accountEmail == "user@example.com")
        #expect(decoded.loginMethod == "Pro")
    }

    @Test("SyncedUsageSnapshot tolerates unknown future fields at the JSON top level")
    func syncedUsageSnapshotTolerantOfFutureFields() throws {
        let original = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Mac A",
            deviceID: "uuid-a",
            appVersion: "0.20.3",
            mobileVersion: "1.3.0",
            notificationPushEnabled: true)

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "hypotheticalHardwareBadge": "AppleSilicon",
            "hypotheticalBatteryLevel": 0.87,
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncedUsageSnapshot.self, from: augmented)
        #expect(decoded.deviceName == "Mac A")
        #expect(decoded.deviceID == "uuid-a")
        #expect(decoded.appVersion == "0.20.3")
        #expect(decoded.mobileVersion == "1.3.0")
        #expect(decoded.notificationPushEnabled == true)
    }

    @Test("SyncCostSummary tolerates unknown future fields at the JSON top level")
    func syncCostSummaryTolerantOfFutureFields() throws {
        let original = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 1000,
            last30DaysCostUSD: 100,
            last30DaysTokens: 50000,
            daily: [
                SyncDailyPoint(dayKey: "2026-04-23", costUSD: 4.56, totalTokens: 4000),
            ])

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "hypothetical90DayTotal": 789.0,
            "hypotheticalBucket": "premium",
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncCostSummary.self, from: augmented)
        #expect(decoded.sessionCostUSD == 1.23)
        #expect(decoded.last30DaysCostUSD == 100)
        #expect(decoded.daily.count == 1)
        #expect(decoded.daily.first?.costUSD == 4.56)
    }

    @Test("SyncPerplexityCreditSummary tolerates unknown future fields")
    func syncPerplexityCreditsTolerantOfFutureFields() throws {
        let original = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            renewalAt: Date(timeIntervalSince1970: 1_700_000_000),
            planName: "Pro")

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let baseline = try encoder.encode(original)
        let augmented = try Self.injectFutureFields(into: baseline, extras: [
            "hypotheticalReferralCredits": 500,
            "hypotheticalTeamSharedPool": true,
        ])

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let decoded = try decoder.decode(SyncPerplexityCreditSummary.self, from: augmented)
        #expect(decoded.recurringTotalCents == 5000)
        #expect(decoded.recurringUsedCents == 2500)
        #expect(decoded.planName == "Pro")
    }
}
