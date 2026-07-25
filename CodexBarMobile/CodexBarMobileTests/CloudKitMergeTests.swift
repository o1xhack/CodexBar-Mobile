import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Multi-device Merge Tests")
struct CloudKitMergeTests {
    private let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let newerDate = Date(timeIntervalSince1970: 1_700_100_000)

    private func makeProvider(
        id: String,
        name: String,
        email: String? = nil,
        lastUpdated: Date,
        usedPercent: Double = 50.0) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: SyncRateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated)
    }

    private func makeSnapshot(
        deviceName: String,
        deviceID: String,
        providers: [ProviderUsageSnapshot],
        timestamp: Date? = nil,
        appVersion: String? = nil) -> SyncedUsageSnapshot
    {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: timestamp ?? providers.map(\.lastUpdated).max() ?? Date(),
            deviceName: deviceName,
            deviceID: deviceID,
            appVersion: appVersion)
    }

    // MARK: - Single device (degenerate case)

    @Test
    func `Single device returns its data unchanged`() throws {
        let provider = self.makeProvider(id: "claude", name: "Claude", email: "a@b.com", lastUpdated: self.olderDate)
        let snapshot = self.makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-1", providers: [provider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([snapshot]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].providerID == "claude")
        #expect(merged.providers[0].accountEmail == "a@b.com")
        #expect(merged.deviceName == "MacBook Air")
    }

    // MARK: - Same provider, same account → take newest

    @Test
    func `Same provider + same account deduplicates to most recent`() throws {
        let oldProvider = self.makeProvider(
            id: "claude", name: "Claude", email: "user@a.com",
            lastUpdated: self.olderDate, usedPercent: 30.0)
        let newProvider = self.makeProvider(
            id: "claude", name: "Claude", email: "user@a.com",
            lastUpdated: self.newerDate, usedPercent: 80.0)

        let macA = self.makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [oldProvider])
        let macB = self.makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [newProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].primary?.usedPercent == 80.0) // Newer data wins
    }

    @Test
    func `Same provider old/new Mac merge preserves non-nil subscription metadata`() throws {
        let renewal = Date(timeIntervalSince1970: 1_801_000_000)
        let oldMacLatestProvider = self.makeProvider(
            id: "minimax", name: "MiniMax", email: "user@a.com",
            lastUpdated: self.newerDate, usedPercent: 70.0)
        let newMacOlderProvider = ProviderUsageSnapshot(
            providerID: "minimax",
            providerName: "MiniMax",
            primary: SyncRateWindow(
                usedPercent: 40.0,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: "user@a.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: olderDate,
            subscriptionRenewsAt: renewal)

        let oldMac = self.makeSnapshot(
            deviceName: "Old Mac", deviceID: "uuid-old",
            providers: [oldMacLatestProvider])
        let newMac = self.makeSnapshot(
            deviceName: "New Mac", deviceID: "uuid-new",
            providers: [newMacOlderProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([oldMac, newMac]))
        let provider = try #require(merged.providers.first)
        #expect(provider.primary?.usedPercent == 70.0)
        #expect(provider.subscriptionRenewsAt == renewal)
        #expect(provider.subscriptionExpiresAt == nil)
    }

    @Test
    func `Same provider old/new Mac merge preserves v0.37 Codex reset credits and confidence`() throws {
        let expiry = Date(timeIntervalSince1970: 1_801_000_000)
        let oldMacLatestProvider = self.makeProvider(
            id: "codex", name: "Codex", email: "user@a.com",
            lastUpdated: self.newerDate, usedPercent: 70.0)
        let newMacOlderProvider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(
                usedPercent: 40.0,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: "user@a.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: olderDate,
            codexResetCredits: SyncCodexResetCredits(
                availableCount: 2,
                nextExpiresAt: expiry,
                credits: [
                    SyncCodexResetCredit(
                        id: "credit-1",
                        resetType: "manual",
                        status: "available",
                        grantedAt: olderDate,
                        expiresAt: expiry,
                        redeemStartedAt: nil,
                        redeemedAt: nil),
                ],
                updatedAt: olderDate),
            usageDataConfidence: "estimated")

        let oldMac = self.makeSnapshot(
            deviceName: "Old Mac", deviceID: "uuid-old",
            providers: [oldMacLatestProvider])
        let newMac = self.makeSnapshot(
            deviceName: "New Mac", deviceID: "uuid-new",
            providers: [newMacOlderProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([oldMac, newMac]))
        let provider = try #require(merged.providers.first)
        #expect(provider.primary?.usedPercent == 70.0)
        #expect(provider.codexResetCredits?.availableCount == 2)
        #expect(provider.codexResetCredits?.nextExpiresAt == expiry)
        #expect(provider.codexResetCredits?.credits.first?.id == "credit-1")
        #expect(provider.usageDataConfidence == "estimated")
    }

    @Test
    func `Same provider old/new Mac merge preserves v0.39 CrossModel usage`() throws {
        let crossModelUsage = SyncCrossModelUsage(
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
            updatedAt: olderDate)
        let olderMacProvider = ProviderUsageSnapshot(
            providerID: "crossmodel",
            providerName: "CrossModel",
            primary: nil,
            secondary: nil,
            accountEmail: "wallet@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: olderDate,
            crossModelUsage: crossModelUsage)
        let newerMacProvider = self.makeProvider(
            id: "crossmodel", name: "CrossModel", email: "wallet@example.com",
            lastUpdated: self.newerDate, usedPercent: 0)

        let olderMac = self.makeSnapshot(
            deviceName: "Old Mac", deviceID: "uuid-old",
            providers: [olderMacProvider])
        let newerMac = self.makeSnapshot(
            deviceName: "New Mac", deviceID: "uuid-new",
            providers: [newerMacProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([olderMac, newerMac]))
        let provider = try #require(merged.providers.first)
        #expect(provider.primary?.usedPercent == 0)
        #expect(provider.crossModelUsage?.balance == 8.06)
        #expect(provider.crossModelUsage?.daily?.totalTokens == 12467)
        #expect(provider.crossModelUsage?.monthly?.requestCount == 3166)
    }

    @Test(arguments: [false, true])
    func `Mixed Kimi writers preserve v0.41 lanes in both freshness orders`(
        oldMacIsFresher: Bool) throws
    {
        let oldDate = oldMacIsFresher ? self.newerDate : self.olderDate
        let newDate = oldMacIsFresher ? self.olderDate : self.newerDate
        let oldMacProvider = ProviderUsageSnapshot(
            providerID: "kimi", providerName: "Kimi",
            primary: nil, secondary: nil,
            accountEmail: "kimi@example.com", loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: oldDate,
            rateWindows: [
                SyncRateWindow(
                    label: "Weekly", usedPercent: 70, windowMinutes: nil,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Rate Limit", usedPercent: 60, windowMinutes: 300,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Monthly", usedPercent: 50, windowMinutes: nil,
                    resetsAt: nil, resetDescription: nil),
            ])
        let newMacProvider = ProviderUsageSnapshot(
            providerID: "kimi", providerName: "Kimi",
            primary: nil, secondary: nil,
            accountEmail: "kimi@example.com", loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: newDate,
            rateWindows: [
                SyncRateWindow(
                    label: "Weekly", usedPercent: 20, windowMinutes: nil,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Rate Limit", usedPercent: 30, windowMinutes: 300,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Monthly", usedPercent: 40, windowMinutes: nil,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Code 7-day", usedPercent: 10, windowMinutes: 10080,
                    resetsAt: nil, resetDescription: nil),
            ])

        let oldMac = self.makeSnapshot(
            deviceName: "Old Mac", deviceID: "uuid-old", providers: [oldMacProvider],
            appVersion: "0.39.0.1")
        let newMac = self.makeSnapshot(
            deviceName: "New Mac", deviceID: "uuid-new", providers: [newMacProvider],
            appVersion: "0.41.0.1")
        let merged = try #require(CloudSyncReader.mergeSnapshots([oldMac, newMac]))
        let kimi = try #require(merged.providers.first)

        #expect(kimi.rateWindows.compactMap(\.label) == [
            "Weekly", "Rate Limit", "Monthly", "Code 7-day",
        ])
        #expect(kimi.rateWindows.first?.usedPercent == (oldMacIsFresher ? 70 : 20))
        #expect(kimi.rateWindows.last?.usedPercent == 10)
    }

    @Test(arguments: [false, true])
    func `Mixed Alibaba writers preserve rolling lanes in both freshness orders`(
        oldMacIsFresher: Bool) throws
    {
        let oldDate = oldMacIsFresher ? self.newerDate : self.olderDate
        let newDate = oldMacIsFresher ? self.olderDate : self.newerDate
        let oldMacProvider = ProviderUsageSnapshot(
            providerID: "alibabatokenplan", providerName: "Alibaba Token Plan",
            primary: SyncRateWindow(
                label: "Credits", usedPercent: 30, windowMinutes: 43200,
                resetsAt: nil, resetDescription: nil),
            secondary: nil,
            accountEmail: nil, loginMethod: "Bailian Pro",
            statusMessage: nil, isError: false, lastUpdated: oldDate,
            rateWindows: [
                SyncRateWindow(
                    label: "Credits", usedPercent: 30, windowMinutes: 43200,
                    resetsAt: nil, resetDescription: nil),
            ])
        let newMacProvider = ProviderUsageSnapshot(
            providerID: "alibabatokenplan", providerName: "Alibaba Token Plan",
            primary: SyncRateWindow(
                label: "5-hour", usedPercent: 10, windowMinutes: 300,
                resetsAt: nil, resetDescription: nil),
            secondary: SyncRateWindow(
                label: "Weekly", usedPercent: 20, windowMinutes: 10080,
                resetsAt: nil, resetDescription: nil),
            accountEmail: nil, loginMethod: "Bailian Pro",
            statusMessage: nil, isError: false, lastUpdated: newDate,
            rateWindows: [
                SyncRateWindow(
                    label: "5-hour", usedPercent: 10, windowMinutes: 300,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 20, windowMinutes: 10080,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Credits", usedPercent: 30, windowMinutes: 43200,
                    resetsAt: nil, resetDescription: nil),
            ])

        let oldMac = self.makeSnapshot(
            deviceName: "Old Mac", deviceID: "uuid-old", providers: [oldMacProvider],
            appVersion: "0.45.2.1")
        let newMac = self.makeSnapshot(
            deviceName: "New Mac", deviceID: "uuid-new", providers: [newMacProvider],
            appVersion: "0.45.2.2")
        let iPhoneA = try #require(CloudSyncReader.mergeSnapshots([oldMac, newMac]))
        let iPhoneB = try #require(CloudSyncReader.mergeSnapshots([newMac, oldMac]))
        let alibabaA = try #require(iPhoneA.providers.first)
        let alibabaB = try #require(iPhoneB.providers.first)

        #expect(alibabaA.rateWindows.compactMap(\.label) == ["5-hour", "Weekly", "Credits"])
        #expect(alibabaA.rateWindows.map(\.windowMinutes) == [300, 10080, 43200])
        #expect(alibabaB.rateWindows == alibabaA.rateWindows)
    }

    @Test(arguments: [false, true])
    func `Mixed Claude writers preserve a specific Max tier in both freshness orders`(
        oldMacIsFresher: Bool) throws
    {
        let oldDate = oldMacIsFresher ? self.newerDate : self.olderDate
        let newDate = oldMacIsFresher ? self.olderDate : self.newerDate
        let oldMacProvider = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "max@example.com", loginMethod: "Claude Max",
            statusMessage: nil, isError: false, lastUpdated: oldDate)
        let newMacProvider = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "max@example.com", loginMethod: "Claude Max 20x",
            statusMessage: nil, isError: false, lastUpdated: newDate)

        let oldMac = self.makeSnapshot(
            deviceName: "Old Mac", deviceID: "uuid-old", providers: [oldMacProvider],
            appVersion: "0.39.0.1")
        let newMac = self.makeSnapshot(
            deviceName: "New Mac", deviceID: "uuid-new", providers: [newMacProvider],
            appVersion: "0.41.0.1")
        let merged = try #require(CloudSyncReader.mergeSnapshots([oldMac, newMac]))

        #expect(merged.providers.first?.loginMethod == "Claude Max 20x")
    }

    @Test(arguments: [false, true])
    func `Mixed Claude writers preserve scoped lanes in both freshness orders`(
        oldMacIsFresher: Bool) throws
    {
        let oldDate = oldMacIsFresher ? self.newerDate : self.olderDate
        let newDate = oldMacIsFresher ? self.olderDate : self.newerDate
        let oldMacProvider = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "lanes@example.com", loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: oldDate,
            rateWindows: [
                SyncRateWindow(
                    label: "Weekly", usedPercent: 81, windowMinutes: 10080,
                    resetsAt: nil, resetDescription: nil),
            ])
        let newMacProvider = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "lanes@example.com", loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: newDate,
            rateWindows: [
                SyncRateWindow(
                    label: "Weekly", usedPercent: 23, windowMinutes: 10080,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Designs", usedPercent: 34, windowMinutes: 10080,
                    resetsAt: nil, resetDescription: nil),
                SyncRateWindow(
                    label: "Web Sonnet", usedPercent: 45, windowMinutes: 10080,
                    resetsAt: nil, resetDescription: nil),
            ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([
            self.makeSnapshot(deviceName: "Old Mac", deviceID: "old", providers: [oldMacProvider]),
            self.makeSnapshot(deviceName: "New Mac", deviceID: "new", providers: [newMacProvider]),
        ]))
        let claude = try #require(merged.providers.first)
        #expect(Set(claude.rateWindows.compactMap(\.label)) == ["Weekly", "Designs", "Web Sonnet"])
        #expect(
            claude.rateWindows.first(where: { $0.label == "Weekly" })?.usedPercent
                == (oldMacIsFresher ? 81 : 23))
    }

    @Test
    func `A genuinely different fresh Claude plan replaces an older specific Max tier`() throws {
        let olderMax = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "plan@example.com", loginMethod: "Claude Max 20x",
            statusMessage: nil, isError: false, lastUpdated: olderDate)
        let newerPro = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "plan@example.com", loginMethod: "Claude Pro",
            statusMessage: nil, isError: false, lastUpdated: newerDate)

        let oldMac = self.makeSnapshot(
            deviceName: "Old Mac", deviceID: "uuid-old", providers: [olderMax])
        let newMac = self.makeSnapshot(
            deviceName: "New Mac", deviceID: "uuid-new", providers: [newerPro])
        let merged = try #require(CloudSyncReader.mergeSnapshots([oldMac, newMac]))

        #expect(merged.providers.first?.loginMethod == "Claude Pro")
    }

    @Test
    func `A current generic Claude Max value replaces an older specific tier`() throws {
        let olderSpecific = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "current@example.com", loginMethod: "Claude Max 20x",
            statusMessage: nil, isError: false, lastUpdated: olderDate)
        let newerGeneric = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: "current@example.com", loginMethod: "Claude Max",
            statusMessage: nil, isError: false, lastUpdated: newerDate)

        let olderMac = self.makeSnapshot(
            deviceName: "Current Mac A", deviceID: "uuid-current-a",
            providers: [olderSpecific], appVersion: "0.41.0.1")
        let newerMac = self.makeSnapshot(
            deviceName: "Current Mac B", deviceID: "uuid-current-b",
            providers: [newerGeneric], appVersion: "0.41.0.1")
        let merged = try #require(CloudSyncReader.mergeSnapshots([olderMac, newerMac]))

        #expect(merged.providers.first?.loginMethod == "Claude Max")
    }

    // MARK: - Same provider, different accounts → keep both

    @Test
    func `Same provider + different accounts are preserved as separate entries`() throws {
        let accountA = self.makeProvider(
            id: "claude", name: "Claude", email: "personal@a.com", lastUpdated: self.olderDate)
        let accountB = self.makeProvider(
            id: "claude", name: "Claude", email: "work@b.com", lastUpdated: self.newerDate)

        let macA = self.makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [accountA])
        let macB = self.makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [accountB])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 2)

        let emails = Set(merged.providers.compactMap(\.accountEmail))
        #expect(emails == ["personal@a.com", "work@b.com"])
    }

    @Test
    func `Opaque mapper identities keep duplicate editable labels separate`() throws {
        let first = ProviderUsageSnapshot(
            providerID: "sub2api", providerName: "sub2api",
            primary: nil, secondary: nil,
            accountEmail: "Production | shared", loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: olderDate,
            accountIdentities: ["sub2api:record:token-a"],
            sub2APIUsage: .init(kind: "wallet", balance: 10, unit: "USD", today: nil, total: nil),
            accountRecordKey: "token-a")
        let second = ProviderUsageSnapshot(
            providerID: "sub2api", providerName: "sub2api",
            primary: nil, secondary: nil,
            accountEmail: "Production | shared", loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: newerDate,
            accountIdentities: ["sub2api:record:token-b"],
            sub2APIUsage: .init(kind: "wallet", balance: 20, unit: "USD", today: nil, total: nil),
            accountRecordKey: "token-b")
        let merged = try #require(CloudSyncReader.mergeSnapshots([
            self.makeSnapshot(deviceName: "Mac", deviceID: "mac", providers: [first, second]),
        ]))
        #expect(merged.providers.count == 2)
        #expect(Set(merged.providers.compactMap(\.accountRecordKey)) == ["token-a", "token-b"])
    }

    @Test
    func `Real account identity merges across Macs despite different opaque record keys`() throws {
        func provider(recordKey: String, updated: Date) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "cursor", providerName: "Cursor",
                primary: nil, secondary: nil,
                accountEmail: "same@example.com", loginMethod: "Token",
                statusMessage: nil, isError: false, lastUpdated: updated,
                accountIdentities: [
                    "cursor:email:same@example.com",
                    "cursor:record:\(recordKey)",
                ],
                accountRecordKey: recordKey)
        }
        let merged = try #require(CloudSyncReader.mergeSnapshots([
            self.makeSnapshot(
                deviceName: "Mac A", deviceID: "a",
                providers: [provider(recordKey: "token-a", updated: self.olderDate)]),
            self.makeSnapshot(
                deviceName: "Mac B", deviceID: "b",
                providers: [provider(recordKey: "token-b", updated: self.newerDate)]),
        ]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers.first?.accountEmail == "same@example.com")
    }

    @Test
    func `Wayfinder device identities do not collapse two gateways`() throws {
        func provider(device: String, requests: Int, updated: Date) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "wayfinder", providerName: "Wayfinder",
                primary: nil, secondary: nil,
                accountEmail: nil, loginMethod: nil,
                statusMessage: nil, isError: false, lastUpdated: updated,
                accountIdentities: ["wayfinder:record:device-\(device)"],
                wayfinderUsage: SyncWayfinderUsage(
                    gatewayStatus: "healthy", offline: false, dryRun: false,
                    missingKeyCount: 0, modelCount: 1, requests: requests,
                    tokens: 100, realized: 1, baseline: 2, saved: 1,
                    savedPercent: 50, priced: true, routes: [],
                    averageDecisionMilliseconds: 2, updatedAt: updated),
                accountRecordKey: "device-\(device)")
        }
        let merged = try #require(CloudSyncReader.mergeSnapshots([
            self.makeSnapshot(
                deviceName: "Mac A", deviceID: "a",
                providers: [provider(device: "a", requests: 10, updated: self.olderDate)]),
            self.makeSnapshot(
                deviceName: "Mac B", deviceID: "b",
                providers: [provider(device: "b", requests: 20, updated: self.newerDate)]),
        ]))
        #expect(merged.providers.count == 2)
        #expect(Set(merged.providers.compactMap { $0.wayfinderUsage?.requests }) == [10, 20])
    }

    // MARK: - Different providers from different devices

    @Test
    func `Different providers from different Macs are combined`() throws {
        let claude = self.makeProvider(id: "claude", name: "Claude", lastUpdated: self.olderDate)
        let cursor = self.makeProvider(id: "cursor", name: "Cursor", lastUpdated: self.olderDate)
        let codex = self.makeProvider(id: "codex", name: "Codex", lastUpdated: self.newerDate)

        let macA = self.makeSnapshot(deviceName: "MacBook Air", deviceID: "uuid-a", providers: [claude, cursor])
        let macB = self.makeSnapshot(deviceName: "Mac Mini", deviceID: "uuid-b", providers: [codex])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 3)

        let ids = Set(merged.providers.map(\.providerID))
        #expect(ids == ["claude", "cursor", "codex"])
    }

    // MARK: - Combined device name

    @Test
    func `Merged snapshot combines device names`() throws {
        let macA = self.makeSnapshot(
            deviceName: "MacBook Air", deviceID: "uuid-a",
            providers: [self.makeProvider(id: "claude", name: "Claude", lastUpdated: self.olderDate)])
        let macB = self.makeSnapshot(
            deviceName: "Mac Mini", deviceID: "uuid-b",
            providers: [self.makeProvider(id: "codex", name: "Codex", lastUpdated: self.newerDate)])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.deviceName.contains("MacBook Air"))
        #expect(merged.deviceName.contains("Mac Mini"))
    }

    // MARK: - Empty input

    @Test
    func `Empty snapshot list returns nil`() {
        let result = CloudSyncReader.mergeSnapshots([])
        #expect(result == nil)
    }

    // MARK: - Provider with nil email vs non-nil email

    @Test
    func `Provider with nil email is treated as separate from one with email`() throws {
        let noEmail = self.makeProvider(id: "claude", name: "Claude", email: nil, lastUpdated: self.olderDate)
        let withEmail = self.makeProvider(id: "claude", name: "Claude", email: "a@b.com", lastUpdated: self.newerDate)

        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [noEmail])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [withEmail])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 2) // Different keys: "claude|" vs "claude|a@b.com"
    }

    // MARK: - Providers sorted by name

    @Test
    func `Merged providers are sorted alphabetically by name`() throws {
        let zProvider = self.makeProvider(id: "z-tool", name: "Z Tool", lastUpdated: self.olderDate)
        let aProvider = self.makeProvider(id: "a-tool", name: "A Tool", lastUpdated: self.newerDate)

        let snapshot = self.makeSnapshot(
            deviceName: "Mac", deviceID: "uuid-1",
            providers: [zProvider, aProvider])

        let merged = try #require(CloudSyncReader.mergeSnapshots([snapshot]))
        #expect(merged.providers[0].providerName == "A Tool")
        #expect(merged.providers[1].providerName == "Z Tool")
    }

    // MARK: - Uses latest sync timestamp

    @Test
    func `Merged snapshot uses the most recent syncTimestamp across devices`() throws {
        let macA = self.makeSnapshot(
            deviceName: "Mac A", deviceID: "uuid-a",
            providers: [self.makeProvider(id: "claude", name: "Claude", lastUpdated: self.olderDate)],
            timestamp: self.olderDate)
        let macB = self.makeSnapshot(
            deviceName: "Mac B", deviceID: "uuid-b",
            providers: [self.makeProvider(id: "codex", name: "Codex", lastUpdated: self.newerDate)],
            timestamp: self.newerDate)

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.syncTimestamp == self.newerDate)
    }

    // MARK: - Cost aggregation for local-cost providers

    private func makeProviderWithCost(
        id: String,
        name: String,
        email: String? = nil,
        lastUpdated: Date,
        sessionCost: Double,
        daily: [SyncDailyPoint]) -> ProviderUsageSnapshot
    {
        let totalCost = daily.reduce(0) { $0 + $1.costUSD }
        let totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: SyncCostSummary(
                sessionCostUSD: sessionCost,
                sessionTokens: nil,
                last30DaysCostUSD: totalCost,
                last30DaysTokens: totalTokens,
                daily: daily))
    }

    @Test
    func `Claude cost data is summed across devices (local-cost provider)`() throws {
        let dailyA = [
            SyncDailyPoint(dayKey: "2024-01-15", costUSD: 1.50, totalTokens: 10000),
            SyncDailyPoint(dayKey: "2024-01-16", costUSD: 2.00, totalTokens: 15000),
        ]
        let dailyB = [
            SyncDailyPoint(dayKey: "2024-01-15", costUSD: 0.80, totalTokens: 5000),
            SyncDailyPoint(dayKey: "2024-01-17", costUSD: 3.00, totalTokens: 20000),
        ]

        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makeProviderWithCost(
                id: "claude",
                name: "Claude",
                email: "user@a.com",
                lastUpdated: self.olderDate,
                sessionCost: 0.50,
                daily: dailyA),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makeProviderWithCost(
                id: "claude",
                name: "Claude",
                email: "user@a.com",
                lastUpdated: self.newerDate,
                sessionCost: 0.30,
                daily: dailyB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)

        let cost = try #require(merged.providers[0].costSummary)

        // Session costs should be summed
        #expect(cost.sessionCostUSD == 0.80) // 0.50 + 0.30

        // Daily points: Jan 15 summed, Jan 16 from A only, Jan 17 from B only
        #expect(cost.daily.count == 3)

        let jan15 = try #require(cost.daily.first { $0.dayKey == "2024-01-15" })
        #expect(jan15.costUSD == 2.30) // 1.50 + 0.80
        #expect(jan15.totalTokens == 15000) // 10000 + 5000

        let jan16 = try #require(cost.daily.first { $0.dayKey == "2024-01-16" })
        #expect(jan16.costUSD == 2.00) // Only from Mac A

        let jan17 = try #require(cost.daily.first { $0.dayKey == "2024-01-17" })
        #expect(jan17.costUSD == 3.00) // Only from Mac B

        // 30-day total recalculated from merged daily
        #expect(cost.last30DaysCostUSD == 7.30) // 2.30 + 2.00 + 3.00
    }

    @Test
    func `Account-level provider cost is NOT summed (takes newest)`() throws {
        let daily = [SyncDailyPoint(dayKey: "2024-01-15", costUSD: 5.00, totalTokens: 50000)]

        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makeProviderWithCost(
                id: "augment",
                name: "Augment",
                email: "user@a.com",
                lastUpdated: self.olderDate,
                sessionCost: 1.00,
                daily: daily),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makeProviderWithCost(
                id: "augment",
                name: "Augment",
                email: "user@a.com",
                lastUpdated: self.newerDate,
                sessionCost: 2.00,
                daily: daily),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let cost = try #require(merged.providers[0].costSummary)

        // Should NOT be summed — account-level data, take newest
        #expect(cost.sessionCostUSD == 2.00) // From Mac B (newer), not 3.00
        #expect(cost.last30DaysCostUSD == 5.00) // Not doubled
    }

    @Test
    func `Model breakdowns are merged by label with summed costs`() throws {
        let dailyA = [SyncDailyPoint(
            dayKey: "2024-01-15", costUSD: 2.00, totalTokens: 10000,
            modelBreakdowns: [
                SyncCostBreakdown(label: "claude-4-sonnet", costUSD: 1.50),
                SyncCostBreakdown(label: "claude-4-opus", costUSD: 0.50),
            ])]
        let dailyB = [SyncDailyPoint(
            dayKey: "2024-01-15", costUSD: 1.00, totalTokens: 5000,
            modelBreakdowns: [
                SyncCostBreakdown(label: "claude-4-sonnet", costUSD: 0.80),
                SyncCostBreakdown(label: "claude-4-haiku", costUSD: 0.20),
            ])]

        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makeProviderWithCost(
                id: "claude",
                name: "Claude",
                lastUpdated: self.olderDate,
                sessionCost: 0,
                daily: dailyA),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makeProviderWithCost(
                id: "claude",
                name: "Claude",
                lastUpdated: self.newerDate,
                sessionCost: 0,
                daily: dailyB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let jan15 = try #require(merged.providers[0].costSummary?.daily.first)

        #expect(jan15.modelBreakdowns.count == 3)

        let sonnet = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-sonnet" })
        #expect(sonnet.costUSD == 2.30) // 1.50 + 0.80

        let opus = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-opus" })
        #expect(opus.costUSD == 0.50) // Only from Mac A

        let haiku = try #require(jan15.modelBreakdowns.first { $0.label == "claude-4-haiku" })
        #expect(haiku.costUSD == 0.20) // Only from Mac B
    }

    @Test
    func `Provider without cost data is unaffected by merge`() throws {
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makeProvider(
                id: "copilot",
                name: "Copilot",
                email: "user@a.com",
                lastUpdated: self.olderDate,
                usedPercent: 40),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makeProvider(
                id: "copilot",
                name: "Copilot",
                email: "user@a.com",
                lastUpdated: self.newerDate,
                usedPercent: 60),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        #expect(merged.providers[0].primary?.usedPercent == 60) // Newer wins
        #expect(merged.providers[0].costSummary == nil) // No cost data
    }

    // MARK: - Perplexity credits passthrough (T3 · Build 71 / Mac 0.20.3)

    //
    // Regression guard: `mergeProviderEntries` rebuilds
    // `ProviderUsageSnapshot` for multi-device scenarios. Build 71's new
    // `perplexityCredits` field was added with a default-nil initializer
    // parameter, which would compile cleanly even if the merger forgot
    // to forward it — silently regressing the iOS Perplexity detail page
    // to the legacy 3-bar fallback whenever the user had >1 Mac signed in.
    // Codex-reviewer caught this in the initial T3 review; this test pins
    // the fix.

    private func makePerplexitySnapshot(
        email: String? = "user@example.com",
        lastUpdated: Date,
        credits: SyncPerplexityCreditSummary?) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: credits?.planName,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            perplexityCredits: credits)
    }

    @Test
    func `Merged Perplexity snapshot preserves perplexityCredits from latest device`() throws {
        // Mac A (older) has no structured credits (e.g. still on 0.20.2);
        // Mac B (newer) has the full 3-pool breakdown. Merger must pick
        // Mac B's data (lastUpdated wins for identity fields) AND preserve
        // the credits field, not drop it to nil.
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            promoTotalCents: 1000,
            promoUsedCents: 500,
            promoExpiresAt: nil,
            purchasedTotalCents: nil,
            purchasedUsedCents: nil,
            renewalAt: Date(timeIntervalSince1970: 1_700_500_000),
            planName: "Pro",
            balanceCents: 3000)
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makePerplexitySnapshot(lastUpdated: self.olderDate, credits: nil),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makePerplexitySnapshot(lastUpdated: self.newerDate, credits: credits),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 1)
        let perplexity = try #require(merged.providers.first)
        #expect(perplexity.perplexityCredits?.planName == "Pro")
        #expect(perplexity.perplexityCredits?.recurringTotalCents == 5000)
        #expect(perplexity.perplexityCredits?.recurringUsedCents == 2500)
    }

    // MARK: - Cross-version data-loss regression (Build 76)

    //
    // The scenario: user has 2 Macs on different CodexBar versions. The
    // older Mac (e.g. 0.20.2) doesn't know about `perplexityCredits` /
    // account-level `budget` and pushes nil. The newer Mac (0.20.3) pushes
    // the real data. Critically: the OLDER Mac may refresh **later** in
    // wall-clock time (e.g. it's the one the user is actively using today).
    // Naive take-latest-by-lastUpdated would silently drop the real data
    // whenever the older Mac happened to push last — the iPhone detail
    // view would flicker between the new rendering (when newer Mac is
    // authoritative) and the legacy fallback (when older Mac is). Not a
    // temporary transition issue; a real steady-state scenario for any
    // user with mixed Mac versions — which IS the default until they
    // manually update both (could be months apart).
    //
    // These tests pin the `latestNonNil` semantics: if ANY device has the
    // structured data, the merged snapshot uses it, regardless of which
    // device was most recently refreshed.

    @Test
    func `perplexityCredits: older Mac with credits + newer Mac with nil → merged has credits`() throws {
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 5000,
            recurringUsedCents: 2500,
            renewalAt: Date(timeIntervalSince1970: 1_700_500_000),
            planName: "Pro")
        // Key twist: Mac A (with data) is OLDER; Mac B (without) is NEWER.
        // Naive take-latest would return Mac B's nil credits.
        let macAWithCreditsOlder = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makePerplexitySnapshot(lastUpdated: self.olderDate, credits: credits),
        ])
        let macBNoCreditsNewer = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makePerplexitySnapshot(lastUpdated: self.newerDate, credits: nil),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots(
            [macAWithCreditsOlder, macBNoCreditsNewer]))
        let perplexity = try #require(merged.providers.first)
        #expect(perplexity.perplexityCredits?.planName == "Pro")
        #expect(perplexity.perplexityCredits?.recurringTotalCents == 5000)
    }

    @Test
    func `budget: older Mac with budget + newer Mac with nil → merged keeps budget`() throws {
        // Same class of bug as perplexityCredits but on the `budget` field.
        // Pre-Build-76 merger took `base.budget` (latest-lastUpdated's value)
        // which dropped the budget if the newer Mac hadn't fetched it yet.
        let budget = SyncBudgetSnapshot(
            usedAmount: 12.34,
            limitAmount: 100,
            currencyCode: "USD",
            period: "monthly",
            resetsAt: nil)
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "claude",
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.olderDate,
                budget: budget),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "claude",
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.newerDate,
                budget: nil),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let claude = try #require(merged.providers.first)
        #expect(claude.budget?.usedAmount == 12.34)
        #expect(claude.budget?.limitAmount == 100)
    }

    @Test
    func `non-local-cost costSummary: older Mac with data + newer Mac with nil → merged keeps data`() throws {
        // Cost for account-level providers (Cursor, Perplexity, OpenCode Go,
        // etc. — anything NOT in localCostProviders) should follow
        // latestNonNil semantics, not take-latest. Test with `cursor`
        // (account-level via API, not per-Mac CLI).
        let cost = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 0,
            last30DaysCostUSD: 45.67,
            last30DaysTokens: 0,
            daily: [])
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "cursor",
                providerName: "Cursor",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.olderDate,
                costSummary: cost),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "cursor",
                providerName: "Cursor",
                primary: nil,
                secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.newerDate,
                costSummary: nil),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let cursor = try #require(merged.providers.first)
        #expect(cursor.costSummary?.sessionCostUSD == 1.23)
    }

    @Test
    func `local-cost costSummary STILL sums (not overridden by the new latestNonNil path)`() throws {
        // Guard against accidentally regressing the claude / codex / vertexai
        // SUMMING semantic when we added latestNonNil for non-local. Two
        // Macs both report $10 session cost for claude (a local-cost
        // provider) — merged should be $20 (sum), not $10 (latest).
        let costA = SyncCostSummary(
            sessionCostUSD: 10,
            sessionTokens: 0,
            last30DaysCostUSD: 100,
            last30DaysTokens: 0,
            daily: [])
        let costB = SyncCostSummary(
            sessionCostUSD: 10,
            sessionTokens: 0,
            last30DaysCostUSD: 100,
            last30DaysTokens: 0,
            daily: [])
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "claude", providerName: "Claude",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: self.olderDate,
                costSummary: costA),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "claude", providerName: "Claude",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: self.newerDate,
                costSummary: costB),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let claude = try #require(merged.providers.first)
        #expect(claude.costSummary?.sessionCostUSD == 20) // SUMMED, not 10
        #expect(claude.costSummary?.last30DaysCostUSD == 200) // SUMMED from summaries, not dropped
    }

    @Test
    func `local-cost merge sums summary totals when daily history is incomplete`() throws {
        let costA = SyncCostSummary(
            sessionCostUSD: 1.49,
            sessionTokens: 1490,
            last30DaysCostUSD: 2638.98,
            last30DaysTokens: 2_638_980,
            daily: [
                SyncDailyPoint(dayKey: "2026-06-28", costUSD: 42.34, totalTokens: 42340),
            ],
            historyDays: 30)
        let costB = SyncCostSummary(
            sessionCostUSD: 23.34,
            sessionTokens: 23340,
            last30DaysCostUSD: 2368.16,
            last30DaysTokens: 2_368_160,
            daily: [
                SyncDailyPoint(dayKey: "2026-06-29", costUSD: 23.34, totalTokens: 23340),
            ],
            historyDays: 30)
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "claude", providerName: "Claude",
                primary: nil, secondary: nil,
                accountEmail: nil,
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: self.olderDate,
                costSummary: costA),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "claude", providerName: "Claude",
                primary: nil, secondary: nil,
                accountEmail: nil,
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: self.newerDate,
                costSummary: costB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let claude = try #require(merged.providers.first)
        let cost = try #require(claude.costSummary)

        #expect(abs((cost.sessionCostUSD ?? 0) - 24.83) < 0.001)
        #expect(abs((cost.last30DaysCostUSD ?? 0) - 5007.14) < 0.001)
        #expect(cost.last30DaysTokens == 5_007_140)
        #expect(cost.daily.reduce(0) { $0 + $1.costUSD } == 65.68)
        #expect(cost.historyDays == 30)
    }

    @Test
    func `local-cost merge preserves daily model split and service breakdowns`() throws {
        let dayKey = "2026-06-30"
        let costA = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: nil,
            last30DaysTokens: nil,
            daily: [
                SyncDailyPoint(
                    dayKey: dayKey,
                    costUSD: 1.0,
                    totalTokens: 100,
                    modelBreakdowns: [
                        SyncCostBreakdown(
                            label: "gpt-5",
                            costUSD: 1.0,
                            standardCostUSD: 1.0,
                            standardTokens: 100),
                    ],
                    serviceBreakdowns: [
                        SyncCostBreakdown(label: "Codex Run", costUSD: 0.8),
                        SyncCostBreakdown(label: "Codex Cloud", costUSD: 0.2),
                    ],
                    isEstimated: false),
            ],
            isEstimated: false,
            historyDays: 30,
            sessionRequests: 2,
            last30DaysRequests: 20,
            currencyCode: "USD")
        let costB = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: nil,
            last30DaysTokens: nil,
            daily: [
                SyncDailyPoint(
                    dayKey: dayKey,
                    costUSD: 9.0,
                    totalTokens: 900,
                    modelBreakdowns: [
                        SyncCostBreakdown(
                            label: "gpt-5",
                            costUSD: 9.0,
                            isEstimated: true,
                            priorityCostUSD: 9.0,
                            priorityTokens: 900),
                    ],
                    serviceBreakdowns: [
                        SyncCostBreakdown(label: "Codex Run", costUSD: 7.2),
                        SyncCostBreakdown(label: "Codex Cloud", costUSD: 1.8),
                    ],
                    isEstimated: true),
            ],
            isEstimated: true,
            historyDays: 30,
            sessionRequests: 3,
            last30DaysRequests: 30,
            currencyCode: "USD")
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: self.olderDate,
                costSummary: costA),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: self.newerDate,
                costSummary: costB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let codex = try #require(merged.providers.first)
        let cost = try #require(codex.costSummary)
        let point = try #require(cost.daily.first)
        let model = try #require(point.modelBreakdowns.first { $0.label == "gpt-5" })
        let serviceTotals = Dictionary(uniqueKeysWithValues: point.serviceBreakdowns.map {
            ($0.label, $0.costUSD)
        })

        #expect(point.costUSD == 10.0)
        #expect(point.totalTokens == 1000)
        #expect(point.isEstimated == true)
        #expect(model.costUSD == 10.0)
        #expect(model.isEstimated == true)
        #expect(model.standardCostUSD == 1.0)
        #expect(model.priorityCostUSD == 9.0)
        #expect(model.standardTokens == 100)
        #expect(model.priorityTokens == 900)
        #expect(serviceTotals["Codex Run"] == 8.0)
        #expect(serviceTotals["Codex Cloud"] == 2.0)
        #expect(cost.sessionRequests == 5)
        #expect(cost.last30DaysRequests == 50)
        #expect(cost.currencyCode == "USD")
    }

    @Test
    func `loginMethod: older Mac with plan + newer Mac with nil → merged keeps plan`() throws {
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: "Pro",
                statusMessage: nil, isError: false,
                lastUpdated: self.olderDate),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: "user@example.com",
                loginMethod: nil,
                statusMessage: nil, isError: false,
                lastUpdated: self.newerDate),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.first?.loginMethod == "Pro")
    }

    @Test
    func `Single-device Perplexity snapshot preserves perplexityCredits through merge no-op`() throws {
        // Degenerate single-device path: mergeProviderEntries still runs
        // (merger doesn't special-case count == 1 at the provider level),
        // so this verifies the field survives even the trivial passthrough.
        let credits = SyncPerplexityCreditSummary(
            recurringTotalCents: 7500, renewalAt: Date(timeIntervalSince1970: 1_700_600_000), planName: "Max")
        let mac = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makePerplexitySnapshot(lastUpdated: self.olderDate, credits: credits),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.first?.perplexityCredits?.planName == "Max")
        #expect(merged.providers.first?.perplexityCredits?.recurringTotalCents == 7500)
    }

    // MARK: - App/mobile version: take highest across devices (Build 77)

    //
    // Reported scenario: user has two Macs on different CodexBar versions
    // (e.g. 0.19.0 and 0.20.3). The "Mac App" field in iOS Settings used
    // `snapshots.first?.appVersion`, which is whichever snapshot CloudKit
    // iterated first — flipped non-deterministically run to run. Users saw
    // the older version "randomly" even though the newer Mac was fully
    // synced. Fix: take highest semver across devices.

    @Test
    func `Mac App version merged to highest semver across two Macs`() throws {
        let macOld = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)],
            syncTimestamp: olderDate,
            deviceName: "Old Mac", deviceID: "uuid-old",
            appVersion: "0.19.0", mobileVersion: "1.2.0")
        let macNew = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)],
            syncTimestamp: newerDate,
            deviceName: "New Mac", deviceID: "uuid-new",
            appVersion: "0.20.3", mobileVersion: "1.3.0")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macOld, macNew]))
        #expect(merged.appVersion == "0.20.3")
        #expect(merged.mobileVersion == "1.3.0")
    }

    @Test
    func `Mac App version merge is order-independent`() throws {
        // Same two snapshots, flipped iteration order — the result must not
        // change. The pre-fix bug was: `snapshots.first?.appVersion` returned
        // 0.19.0 here but 0.20.3 in the previous test, purely based on order.
        let macNew = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", name: "Codex", lastUpdated: newerDate)],
            syncTimestamp: newerDate,
            deviceName: "New Mac", deviceID: "uuid-new",
            appVersion: "0.20.3", mobileVersion: "1.3.0")
        let macOld = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", name: "Claude", lastUpdated: olderDate)],
            syncTimestamp: olderDate,
            deviceName: "Old Mac", deviceID: "uuid-old",
            appVersion: "0.19.0", mobileVersion: "1.2.0")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macNew, macOld]))
        #expect(merged.appVersion == "0.20.3")
        #expect(merged.mobileVersion == "1.3.0")
    }

    @Test
    func `Semver comparison handles 2-segment, 3-segment, and non-numeric segments`() {
        // Numeric-segment ordering
        #expect(CloudSyncReader.semverLessThan("0.19.0", "0.20.0"))
        #expect(CloudSyncReader.semverLessThan("0.20.0", "0.20.3"))
        #expect(!CloudSyncReader.semverLessThan("0.20.3", "0.20.0"))
        #expect(!CloudSyncReader.semverLessThan("0.20.3", "0.20.3"))

        // Mixed segment counts (treat missing as 0)
        #expect(CloudSyncReader.semverLessThan("0.20", "0.20.1"))
        #expect(!CloudSyncReader.semverLessThan("0.20.0", "0.20"))

        // Non-numeric suffix falls back to string comparison
        #expect(CloudSyncReader.semverLessThan("0.20.0-beta", "0.20.0-rc"))
    }

    // MARK: - Utilization history: cross-version series merge (Build 77)

    //
    // Reported scenario: iPhone Cost tab's "Subscription Utilization"
    // section showed Codex at 0% even though the Codex detail page rendered
    // clear session bars and "16% used". Root cause was two-fold:
    //   (a) aggregate view averaged raw entries instead of daily peaks
    //       (bursty providers look like zeros in raw avg) — fixed in
    //       UtilizationAggregateView.buildModel;
    //   (b) `mergeUtilizationHistories` grouped by (name, windowMinutes),
    //       so if two Macs disagreed on `windowMinutes` for the same series,
    //       two "session" entries landed in the merged history and
    //       downstream pickers hit the stale one non-deterministically.
    // These tests pin (b): same-name series must union, and the freshest
    // device's windowMinutes wins.

    private func makeCodexWithSession(
        email: String = "user@example.com",
        lastUpdated: Date,
        windowMinutes: Int = 300,
        entries: [SyncUtilizationEntry]) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil, secondary: nil,
            accountEmail: email,
            loginMethod: nil, statusMessage: nil,
            isError: false, lastUpdated: lastUpdated,
            utilizationHistory: [SyncUtilizationSeries(
                name: "session", windowMinutes: windowMinutes, entries: entries)])
    }

    @Test
    func `Two Macs reporting session with mismatched windowMinutes merge into ONE session series`() throws {
        let hourAgo = Date().addingTimeInterval(-3600)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makeCodexWithSession(
                lastUpdated: self.olderDate,
                windowMinutes: 300,
                entries: [SyncUtilizationEntry(
                    capturedAt: twoHoursAgo, usedPercent: 25, resetsAt: nil)]),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makeCodexWithSession(
                lastUpdated: self.newerDate,
                // Different windowMinutes — pre-fix, this created a SECOND
                // "session" series that downstream code could pick instead.
                windowMinutes: 180,
                entries: [SyncUtilizationEntry(
                    capturedAt: hourAgo, usedPercent: 40, resetsAt: nil)]),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let sessions = codex.utilizationHistory?.filter { $0.name == "session" } ?? []
        #expect(sessions.count == 1) // Unioned, not split
        // The newer Mac's windowMinutes wins (180), because its entry was
        // captured more recently.
        #expect(sessions.first?.windowMinutes == 180)
        // Both devices' entries survive the union.
        let entryCount = sessions.first?.entries.count ?? 0
        #expect(entryCount == 2)
    }

    // MARK: - notificationPushEnabled merge (Build 78)

    //
    // Reported class: Build 77 fixed appVersion picking `snapshots.first?` which
    // flipped non-deterministically with CloudKit iteration order. The same
    // pattern existed for `notificationPushEnabled`: when one device set the
    // field explicitly and another hadn't (nil), the merged value depended on
    // iteration order — the iPhone's push setting appeared to toggle on/off
    // across refreshes.
    //
    // Fixed semantics:
    //   - ANY explicit false → false (conservative: respect the off-signal)
    //   - Else ANY explicit true → true
    //   - Else nil (fresh install / every snapshot predates the field)

    private func pushSnapshot(deviceID: String, value: Bool?) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            providers: [self.makeProvider(id: "claude", name: "Claude", lastUpdated: self.newerDate)],
            syncTimestamp: self.newerDate,
            deviceName: "Mac \(deviceID)",
            deviceID: deviceID,
            notificationPushEnabled: value)
    }

    @Test
    func `notificationPushEnabled: all true → true`() throws {
        let merged = try #require(CloudSyncReader.mergeSnapshots([
            self.pushSnapshot(deviceID: "a", value: true),
            self.pushSnapshot(deviceID: "b", value: true),
        ]))
        #expect(merged.notificationPushEnabled == true)
    }

    @Test
    func `notificationPushEnabled: any false → false (conservative)`() throws {
        let merged = try #require(CloudSyncReader.mergeSnapshots([
            self.pushSnapshot(deviceID: "a", value: true),
            self.pushSnapshot(deviceID: "b", value: false),
        ]))
        #expect(merged.notificationPushEnabled == false)
    }

    @Test
    func `notificationPushEnabled: true + nil → true (explicit opinion wins over silence)`() throws {
        // Pre-fix: `snapshots.first?.notificationPushEnabled` flipped between
        // `true` and `nil` depending on which snapshot CloudKit returned first.
        // Post-fix: explicit true always surfaces.
        let merged1 = try #require(CloudSyncReader.mergeSnapshots([
            self.pushSnapshot(deviceID: "true-mac", value: true),
            self.pushSnapshot(deviceID: "nil-mac", value: nil),
        ]))
        let merged2 = try #require(CloudSyncReader.mergeSnapshots([
            self.pushSnapshot(deviceID: "nil-mac", value: nil),
            self.pushSnapshot(deviceID: "true-mac", value: true),
        ]))
        #expect(merged1.notificationPushEnabled == true)
        #expect(merged2.notificationPushEnabled == true)
    }

    @Test
    func `notificationPushEnabled: false + nil → false (order-independent)`() throws {
        let merged1 = try #require(CloudSyncReader.mergeSnapshots([
            self.pushSnapshot(deviceID: "false-mac", value: false),
            self.pushSnapshot(deviceID: "nil-mac", value: nil),
        ]))
        let merged2 = try #require(CloudSyncReader.mergeSnapshots([
            self.pushSnapshot(deviceID: "nil-mac", value: nil),
            self.pushSnapshot(deviceID: "false-mac", value: false),
        ]))
        #expect(merged1.notificationPushEnabled == false)
        #expect(merged2.notificationPushEnabled == false)
    }

    @Test
    func `notificationPushEnabled: all nil → nil (no opinion)`() throws {
        let merged = try #require(CloudSyncReader.mergeSnapshots([
            self.pushSnapshot(deviceID: "a", value: nil),
            self.pushSnapshot(deviceID: "b", value: nil),
        ]))
        #expect(merged.notificationPushEnabled == nil)
    }

    // MARK: - SyncCostSummary.todayCostUSD prefers daily[today] over session (Build 78)

    //
    // Reported class: same as Subscription Utilization aggregate/detail mismatch
    // — Cost tab's summary card used `daily[today].costUSD ?? sessionCostUSD`
    // while `ProviderDetailView`'s "Today" card used `sessionCostUSD` directly.
    // Mid-day the two numbers diverge (session is stale relative to the
    // accumulated daily point, or vice versa). Fix: both paths now go through
    // `SyncCostSummary.todayCostUSD`.

    /// Fixed pin so the tests stay deterministic across wall-clock midnight
    /// crossings. `todayTotals(now:)` is called with this same date, and the
    /// fixture's daily point uses the dayKey derived from it.
    private static let pinnedToday = Date(timeIntervalSince1970: 1_745_500_000)
    private static let pinnedTodayKey = SyncCostSummary.iso8601DayKey(for: pinnedToday)

    @Test
    func `todayTotals prefers daily[today] over sessionCostUSD and sessionTokens`() {
        let cost = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 1000,
            last30DaysCostUSD: 50,
            last30DaysTokens: 30000,
            daily: [
                SyncDailyPoint(
                    dayKey: Self.pinnedTodayKey,
                    costUSD: 4.56,
                    totalTokens: 4000),
            ])
        let today = cost.todayTotals(now: Self.pinnedToday)
        #expect(today.costUSD == 4.56) // daily[today], not session
        #expect(today.tokens == 4000)
    }

    @Test
    func `todayTotals falls back to session when no daily entry for today`() {
        let cost = SyncCostSummary(
            sessionCostUSD: 1.23,
            sessionTokens: 1000,
            last30DaysCostUSD: 50,
            last30DaysTokens: 30000,
            daily: [
                SyncDailyPoint(
                    dayKey: "2020-01-01", // far from pinnedToday
                    costUSD: 99,
                    totalTokens: 9999),
            ])
        let today = cost.todayTotals(now: Self.pinnedToday)
        #expect(today.costUSD == 1.23) // session fallback
        #expect(today.tokens == 1000)
    }

    @Test
    func `todayTotals both fields nil when neither daily[today] nor session has data`() {
        let cost = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 100,
            last30DaysTokens: 50000,
            daily: [])
        let today = cost.todayTotals(now: Self.pinnedToday)
        #expect(today.costUSD == nil)
        #expect(today.tokens == nil)
        #expect(today.costUSD == nil && today.tokens == nil)
    }

    @Test
    func `todayTotals resolves cost and tokens from the SAME day key (no midnight drift)`() {
        // Anchor both fixture and lookup to a date just before midnight. If the
        // implementation called Date() twice with drift potential, this could
        // mismatch; since the whole resolution uses a single injected `now`,
        // both fields resolve from the same key and stay coherent.
        let justBeforeMidnight = Date(timeIntervalSince1970: 1_745_539_199) // 23:59:59 local
        let key = SyncCostSummary.iso8601DayKey(for: justBeforeMidnight)
        let cost = SyncCostSummary(
            sessionCostUSD: 10.00,
            sessionTokens: 2000,
            last30DaysCostUSD: 100,
            last30DaysTokens: 50000,
            daily: [
                SyncDailyPoint(dayKey: key, costUSD: 12.34, totalTokens: 5000),
            ])
        let today = cost.todayTotals(now: justBeforeMidnight)
        #expect(today.costUSD == 12.34) // both come from the same daily point
        #expect(today.tokens == 5000)
    }

    @Test
    func `Mac B reports empty session; Mac A's real entries survive the union`() throws {
        // Degenerate but common: one Mac opens, samples Codex once, then gets
        // put to sleep. Its "session" series may be empty until the next
        // refresh. That empty series must not shadow the other Mac's real
        // data when picking windowMinutes or when downstream views filter
        // for `!entries.isEmpty`.
        let now = Date()
        let macARealData = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makeCodexWithSession(
                lastUpdated: self.newerDate,
                entries: [
                    SyncUtilizationEntry(
                        capturedAt: now.addingTimeInterval(-3600),
                        usedPercent: 30,
                        resetsAt: nil),
                    SyncUtilizationEntry(
                        capturedAt: now.addingTimeInterval(-7200),
                        usedPercent: 50,
                        resetsAt: nil),
                ]),
        ])
        let macBEmpty = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makeCodexWithSession(
                lastUpdated: self.olderDate,
                entries: []),
        ])
        let merged = try #require(CloudSyncReader.mergeSnapshots([macARealData, macBEmpty]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let sessions = codex.utilizationHistory?.filter { $0.name == "session" } ?? []
        #expect(sessions.count == 1)
        #expect((sessions.first?.entries.count ?? 0) >= 2)
    }

    // MARK: - Realistic-distribution regression fixtures (Build 80 · Fix D)

    //
    // Round 3 of the 5-round audit found every pre-Build-78 merge test ran on
    // "toy" data: `usedPercent: 50.0`, `costUSD: $1.50`, three rate-limit
    // entries. Real 30-day data is bursty (mostly 0%), interleaved across
    // devices, and covers reset boundaries. These fixtures re-exercise the
    // same merge paths the existing tests already cover, but with realistic
    // distributions — a regression in a dedup / ordering / bucketing branch
    // that showed no symptom on 3 entries would instantly break these.

    /// Seeds a Codex session series with `daysCount` days of hourly samples,
    /// placing a single `peakPercent` burst at `peakHour` each day and zeros
    /// elsewhere. Mimics the real usage pattern that made the user-reported
    /// Codex-0% bug surface.
    ///
    /// Uses a **UTC calendar** deliberately. `Calendar.current` would make
    /// the generated entry count timezone- and DST-dependent: in Europe/Paris
    /// around late March, the spring-forward skips an hour inside the 30-day
    /// window, so one local day produces 23 hourly entries instead of 24 and
    /// the merged bucket count drops to 719, failing the `== 720` assertion
    /// even when merge logic is correct. Pinning UTC avoids that class of
    /// false positive entirely — DST doesn't exist in UTC.
    private func burstySessionSeries(
        anchor: Date,
        daysCount: Int,
        peakHour: Int,
        peakPercent: Double,
        deviceOffsetMinutes: Int = 0) -> SyncUtilizationSeries
    {
        var entries: [SyncUtilizationEntry] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let anchorStartOfDay = calendar.startOfDay(for: anchor)
        for dayOffset in 0..<daysCount {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: anchorStartOfDay)!
            for hour in 0..<24 {
                let captured = calendar.date(
                    byAdding: .minute, value: deviceOffsetMinutes,
                    to: calendar.date(byAdding: .hour, value: hour, to: day)!)!
                let used = (hour == peakHour) ? peakPercent : 0.0
                entries.append(SyncUtilizationEntry(
                    capturedAt: captured, usedPercent: used, resetsAt: nil))
            }
        }
        return SyncUtilizationSeries(
            name: "session", windowMinutes: 300, entries: entries)
    }

    @Test
    func `Merged utilization with bursty 30-day Codex: union size, peaks preserved, order monotonic`() throws {
        // Two Macs each sample hourly for 30 days. Mac A samples at :00 of
        // the hour, Mac B at :30 — so every real hour has TWO entries going
        // in, one from each Mac. `dedupByHour` must average them (0 from one
        // + 16 from the other at peak hour → 8%). Pre-fix a bursty merge
        // could silently drop one device's entries on hash collision; this
        // test would fail if that regressed.
        let anchor = Date(timeIntervalSince1970: 1_745_500_000)
        let macA = SyncedUsageSnapshot(
            providers: [ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: anchor,
                utilizationHistory: [self.burstySessionSeries(
                    anchor: anchor, daysCount: 30, peakHour: 14,
                    peakPercent: 16, deviceOffsetMinutes: 0)])],
            syncTimestamp: anchor, deviceName: "Mac A", deviceID: "uuid-a")
        let macB = SyncedUsageSnapshot(
            providers: [ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: anchor,
                utilizationHistory: [self.burstySessionSeries(
                    anchor: anchor, daysCount: 30, peakHour: 14,
                    peakPercent: 16, deviceOffsetMinutes: 30)])],
            syncTimestamp: anchor, deviceName: "Mac B", deviceID: "uuid-b")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let session = try #require(codex.utilizationHistory?.first { $0.name == "session" })

        // Both devices' entries land in the same hour buckets; dedup averages
        // them. We expect ~24 hourly entries * 30 days = 720 buckets.
        #expect(session.entries.count == 720)

        // Entries are sorted by capturedAt monotonically.
        let sorted = session.entries.map(\.capturedAt).sorted()
        #expect(session.entries.map(\.capturedAt) == sorted)

        // Each peak-hour bucket averages Mac A's 16% and Mac B's 0%-at-that-
        // minute (since Mac B's :30 sample is still at peakHour in the same
        // calendar hour) → both are 16% → average is 16%. Find the peak
        // entries and confirm they're 16%, not 0% (that would indicate the
        // bursty-merge regression).
        let peakValues = session.entries.filter { $0.usedPercent > 0 }.map(\.usedPercent)
        #expect(peakValues.count == 30) // one peak per day
        #expect(peakValues.allSatisfy { $0 == 16 })
    }

    @Test
    func `Merged utilization with entries straddling a session reset keeps pre-/post-reset buckets separate`() throws {
        // Session reset occurs mid-hour (:30). Two entries in the SAME clock
        // hour — one before reset (usedPercent=90%, resetsAt=T), one after
        // (usedPercent=5%, resetsAt=T+5h). Pre-fix dedup-by-hour would
        // collide them into one bucket averaging to 47.5%, which is both
        // wrong and unrecoverable. Post-fix BucketKey(hourSlot, resetEpoch)
        // separates them. This fixture catches any regression that drops
        // the resetEpoch component of the key.
        //
        // NOTE: two Macs are used deliberately. `mergeSnapshots` has a
        // passthrough branch for single-device input (providers.count == 1)
        // that bypasses `mergeProviderEntries` → `mergeUtilizationHistories`
        // → `dedupByHour`. A single-Mac version of this test would return
        // the original entries as-is and assert nothing about dedup. By
        // feeding two Macs, we force the dedup code path that actually
        // applies the BucketKey separation under audit.
        let anchor = Date(timeIntervalSince1970: 1_745_500_000)
        let resetT = Date(timeIntervalSince1970: 1_745_502_000) // reset happens at T
        let resetTPlus5 = Date(timeIntervalSince1970: 1_745_502_000 + 5 * 3600)
        let preReset = SyncUtilizationEntry(
            capturedAt: anchor, usedPercent: 90, resetsAt: resetT)
        let postReset = SyncUtilizationEntry(
            capturedAt: anchor.addingTimeInterval(600), // same clock hour, 10 min later
            usedPercent: 5, resetsAt: resetTPlus5)

        func provider(entries: [SyncUtilizationEntry]) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: anchor,
                utilizationHistory: [SyncUtilizationSeries(
                    name: "session", windowMinutes: 300, entries: entries)])
        }

        // Both Macs independently observed the reset; each carries both
        // pre- and post-reset entries. The dedup path must preserve the
        // per-resetEpoch separation across the combined entries.
        let macA = SyncedUsageSnapshot(
            providers: [provider(entries: [preReset, postReset])],
            syncTimestamp: anchor, deviceName: "Mac A", deviceID: "uuid-a")
        let macB = SyncedUsageSnapshot(
            providers: [provider(entries: [preReset, postReset])],
            syncTimestamp: anchor, deviceName: "Mac B", deviceID: "uuid-b")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let session = try #require(codex.utilizationHistory?.first { $0.name == "session" })

        // Two distinct buckets survived dedup — one per (hourSlot, resetEpoch).
        // If the resetEpoch component were dropped from the BucketKey, both
        // entries from both Macs would collapse into a single hour bucket
        // averaging 47.5% — the regression we're guarding against.
        #expect(session.entries.count == 2)
        #expect(session.entries.contains(where: { $0.usedPercent == 90 }))
        #expect(session.entries.contains(where: { $0.usedPercent == 5 }))
    }

    @Test
    func `Merged utilization with disordered input across two Macs produces hour-sorted output`() throws {
        // Two Macs, each with their entries deliberately shuffled. `dedupByHour`
        // (only invoked when providers.count > 1) sorts the bucketed output by
        // hourSlot. This pins that behavior: the merge path — when actually
        // exercised — produces monotonic time order from arbitrary input order.
        //
        // NOTE: single-device passthrough (providers.count == 1) intentionally
        // returns the original `ProviderUsageSnapshot` as-is and does NOT dedup
        // or sort entries — that's fine because downstream consumers
        // (`UtilizationHistoryView.buildPeriodPoints`) bucket into dictionaries
        // rather than assuming sorted input. Pinning this test on the
        // multi-device path, since that's where dedup order matters.
        let base = Date(timeIntervalSince1970: 1_745_500_000)
        func disorderedEntries(offsetMinutes: Int) -> [SyncUtilizationEntry] {
            (0..<10).shuffled().map { i in
                SyncUtilizationEntry(
                    capturedAt: base.addingTimeInterval(
                        Double(i) * 3600 + Double(offsetMinutes * 60)),
                    usedPercent: Double(i * 8),
                    resetsAt: nil)
            }
        }
        func provider(entries: [SyncUtilizationEntry]) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: base,
                utilizationHistory: [SyncUtilizationSeries(
                    name: "session", windowMinutes: 300, entries: entries)])
        }
        let macA = SyncedUsageSnapshot(
            providers: [provider(entries: disorderedEntries(offsetMinutes: 0))],
            syncTimestamp: base, deviceName: "Mac A", deviceID: "uuid-a")
        let macB = SyncedUsageSnapshot(
            providers: [provider(entries: disorderedEntries(offsetMinutes: 30))],
            syncTimestamp: base, deviceName: "Mac B", deviceID: "uuid-b")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let session = try #require(codex.utilizationHistory?.first { $0.name == "session" })

        // Both devices' entries for each hour merge into one bucket (same
        // hourSlot), dedup averages them. Output: 10 hour buckets in sorted
        // order.
        #expect(session.entries.count == 10)
        let captures = session.entries.map(\.capturedAt)
        #expect(captures == captures.sorted())
    }

    @Test
    func `Merged utilization with long-idle gap keeps both old and new entries`() throws {
        // Mac A has entries from 30 days ago; Mac B comes alive today with
        // fresh entries. Merged series must contain BOTH — a regression
        // that filtered "stale" entries at merge time would show up as
        // missing early data (downstream the aggregate view already filters
        // for `>= last30Start`; the merger itself must preserve everything).
        let today = Date()
        let calendar = Calendar.current
        let thirtyDaysAgo = try #require(calendar.date(byAdding: .day, value: -30, to: today))

        let oldEntries = (0..<5).map { i in
            SyncUtilizationEntry(
                capturedAt: thirtyDaysAgo.addingTimeInterval(Double(i) * 3600),
                usedPercent: 42, resetsAt: nil)
        }
        let newEntries = (0..<5).map { i in
            SyncUtilizationEntry(
                capturedAt: today.addingTimeInterval(-Double(i) * 3600),
                usedPercent: 18, resetsAt: nil)
        }
        let macA = SyncedUsageSnapshot(
            providers: [ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: thirtyDaysAgo,
                utilizationHistory: [SyncUtilizationSeries(
                    name: "session", windowMinutes: 300, entries: oldEntries)])],
            syncTimestamp: thirtyDaysAgo, deviceName: "Mac A", deviceID: "uuid-a")
        let macB = SyncedUsageSnapshot(
            providers: [ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: today,
                utilizationHistory: [SyncUtilizationSeries(
                    name: "session", windowMinutes: 300, entries: newEntries)])],
            syncTimestamp: today, deviceName: "Mac B", deviceID: "uuid-b")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let session = try #require(codex.utilizationHistory?.first { $0.name == "session" })

        // Both old and new entries survived.
        #expect(session.entries.count == 10)
        #expect(session.entries.contains { $0.usedPercent == 42 })
        #expect(session.entries.contains { $0.usedPercent == 18 })
    }

    @Test
    func `Merged utilization with all-zero entries across 30 days is preserved (not dropped)`() throws {
        // User who has CodexBar running continuously but never uses Codex:
        // 720 hourly samples all at 0%. These must still make it through
        // the merger — UtilizationAggregateView uses the count to decide
        // whether to show the provider at all, and dropping zero-only
        // providers would hide them from Subscription Utilization.
        let anchor = Date(timeIntervalSince1970: 1_745_500_000)
        let entries = (0..<720).map { i in
            SyncUtilizationEntry(
                capturedAt: anchor.addingTimeInterval(Double(i) * 3600),
                usedPercent: 0, resetsAt: nil)
        }
        let macA = SyncedUsageSnapshot(
            providers: [ProviderUsageSnapshot(
                providerID: "codex", providerName: "Codex",
                primary: nil, secondary: nil, accountEmail: "user@example.com",
                loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: anchor,
                utilizationHistory: [SyncUtilizationSeries(
                    name: "session", windowMinutes: 300, entries: entries)])],
            syncTimestamp: anchor, deviceName: "Mac A", deviceID: "uuid-a")

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA]))
        let codex = try #require(merged.providers.first { $0.providerID == "codex" })
        let session = try #require(codex.utilizationHistory?.first { $0.name == "session" })
        #expect(session.entries.count == 720)
        #expect(session.entries.allSatisfy { $0.usedPercent == 0 })
    }

    @Test
    func `Cost merge with cross-date daily points keeps dayKey identity intact`() throws {
        // Two Macs push overlapping daily cost points spanning a month end
        // (2026-01-31 → 2026-02-01). The merger must preserve both day keys
        // distinctly; a regression that normalized by calendar computation
        // with a different locale could produce wrong dayKey strings.
        let dailyA = [
            SyncDailyPoint(dayKey: "2026-01-30", costUSD: 1.00, totalTokens: 1000),
            SyncDailyPoint(dayKey: "2026-01-31", costUSD: 2.50, totalTokens: 2500),
            SyncDailyPoint(dayKey: "2026-02-01", costUSD: 0.75, totalTokens: 750),
        ]
        let dailyB = [
            SyncDailyPoint(dayKey: "2026-01-31", costUSD: 1.50, totalTokens: 1500),
            SyncDailyPoint(dayKey: "2026-02-02", costUSD: 3.00, totalTokens: 3000),
        ]
        let macA = self.makeSnapshot(deviceName: "Mac A", deviceID: "uuid-a", providers: [
            self.makeProviderWithCost(
                id: "claude",
                name: "Claude",
                email: "user@a.com",
                lastUpdated: self.olderDate,
                sessionCost: 0,
                daily: dailyA),
        ])
        let macB = self.makeSnapshot(deviceName: "Mac B", deviceID: "uuid-b", providers: [
            self.makeProviderWithCost(
                id: "claude",
                name: "Claude",
                email: "user@a.com",
                lastUpdated: self.newerDate,
                sessionCost: 0,
                daily: dailyB),
        ])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        let cost = try #require(merged.providers.first?.costSummary)
        let keys = Set(cost.daily.map(\.dayKey))
        #expect(keys == ["2026-01-30", "2026-01-31", "2026-02-01", "2026-02-02"])

        // 2026-01-31 is the overlap day — costs from both Macs sum.
        let jan31 = try #require(cost.daily.first { $0.dayKey == "2026-01-31" })
        #expect(jan31.costUSD == 4.00) // 2.50 + 1.50
    }
}
