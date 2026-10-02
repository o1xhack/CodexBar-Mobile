import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SyncV070BlockingQuotaTests {
    private static let now = Date(timeIntervalSince1970: 1_791_020_400)

    @Test
    func `monthly blockers publish effective access and preserve observed usage`() throws {
        let snapshot = try KimiMonthlyBlockingTests.snapshot(ratio: 1)
        let raw = try #require(snapshot.primary)
        let windows = [SyncCoordinator.syncRateWindow(id: "primary", label: "Weekly", window: raw)]
        let projected = SyncCoordinator.projectingBlockingQuota(windows, provider: .kimi, snapshot: snapshot)
        let result = try #require(projected.first)
        #expect(result.usedPercent == 100)
        #expect(result.resetsAt == snapshot.extraRateWindows?.first { $0.id == "kimi-monthly" }?.window.resetsAt)
        #expect(result.blockingQuota?.rawUsedPercent == raw.usedPercent)
        #expect(result.blockingQuota?.rawResetsAt == raw.resetsAt)
        #expect(result.blockingQuota?.windowID == "kimi-monthly")
        #expect(result.nextRegenPercent == nil)
        #expect(SyncCoordinator.projectingBlockingQuota(projected, provider: .kimi, snapshot: snapshot) == projected)
        #expect(snapshot.primary == raw)
        let data = try CloudSyncConstants.makeJSONEncoder().encode(result)
        let decoder = CloudSyncConstants.makeJSONDecoder()
        #expect(try decoder.decode(SyncRateWindow.self, from: data) == result)
        let legacy = try decoder.decode(LegacyWindow.self, from: data)
        #expect(legacy.usedPercent == 100)
        #expect(legacy.resetsAt == result.resetsAt)
        let oldData = try CloudSyncConstants.makeJSONEncoder().encode(windows[0])
        #expect(try decoder.decode(SyncRateWindow.self, from: oldData).blockingQuota == nil)
    }

    @Test(arguments: ["available", "unknown", "expired", "synthetic", "synthetic-primary", "unknown-primary"])
    func `nonblocking and unknown observations do not synthesize exhaustion`(scenario: String) {
        let blocker = RateWindow(
            usedPercent: scenario == "available" ? 90 : 100,
            windowMinutes: 43200,
            resetsAt: Self.now.addingTimeInterval(scenario == "expired" ? -1 : 86400),
            resetDescription: nil,
            isSyntheticPlaceholder: scenario == "synthetic")
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [.init(
                id: "kimi-monthly",
                title: "Monthly",
                window: blocker,
                usageKnown: scenario != "unknown")],
            updatedAt: Self.now)
        let raw = SyncRateWindow(
            id: "primary",
            usedPercent: 12,
            usageKnown: scenario != "unknown-primary",
            windowMinutes: 300,
            resetsAt: Self.now.addingTimeInterval(60),
            resetDescription: nil,
            isSyntheticPlaceholder: scenario == "synthetic-primary")
        #expect(SyncCoordinator.projectingBlockingQuota([raw], provider: .kimi, snapshot: snapshot) == [raw])
    }

    @Test
    func `unknown monthly reset clears shorter reset and regeneration promises`() {
        let monthly = RateWindow(usedPercent: 100, windowMinutes: 43200, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [.init(id: "kimi-monthly", title: "Monthly", window: monthly)],
            updatedAt: Self.now)
        let raw = SyncRateWindow(
            usedPercent: 20,
            windowMinutes: 300,
            resetsAt: Self.now.addingTimeInterval(60),
            resetDescription: "Short reset",
            nextRegenPercent: 10)
        let result = SyncCoordinator.projectingBlockingQuota([raw], provider: .kimi, snapshot: snapshot)[0]
        #expect(result.resetsAt == nil)
        #expect(result.resetDescription == nil)
        #expect(result.nextRegenPercent == nil)
        #expect(result.blockingQuota?.rawNextRegenPercent == 10)
        #expect(SyncCoordinator.projectingBlockingQuota([raw], provider: .codex, snapshot: snapshot) == [raw])
    }

    @Test
    func `real sync exports share Kimi legacy windows and exclude native Claude inventory`() async throws {
        let settings = testSettingsStore(
            suiteName: "SyncV070BlockingQuotaTests",
            userDefaults: InMemoryUserDefaults(),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { false }))
        settings.iCloudSyncEnabled = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        for provider in [UsageProvider.kimi, .claude] {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(ProviderDefaults.metadata[provider]),
                enabled: true)
        }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(
                homeDirectory: "/nonexistent",
                cacheTTL: 0,
                fileExists: { _ in false },
                directoryContents: { _ in [] }),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let kimi = try KimiMonthlyBlockingTests.snapshot(ratio: 1)
        store._setSnapshotForTesting(kimi, provider: .kimi)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: [.makeSection(rows: [
                    .makeRow(label: "Limit Reset Credits", value: "2 available"),
                    .makeRow(label: "Plan", value: "Synthetic plan"),
                ])],
                updatedAt: Self.now),
            provider: .claude)
        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        await coordinator.pushCurrentSnapshot()
        let exported = try #require(pusher.lastSnapshot?.providers.first { $0.providerID == "kimi" })
        #expect(exported.primary == exported.rateWindows.first)
        #expect(exported.secondary == exported.rateWindows.dropFirst().first)
        #expect(exported.primary?.blockingQuota != nil)
        let monthly = try #require(exported.rateWindows.first { $0.id == "kimi-monthly" })
        #expect(monthly.blockingQuota == nil)
        #expect(monthly.usedPercent == kimi.extraRateWindows?.first { $0.id == "kimi-monthly" }?.window.usedPercent)
        let claude = try #require(pusher.lastSnapshot?.providers.first { $0.providerID == "claude" })
        #expect(claude.details.flatMap(\.rows).map(\.label) == ["Plan"])
        let data = try CloudSyncConstants.makeJSONEncoder().encode(exported)
        let restored = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageSnapshot.self, from: data)
        #expect(restored.primary == exported.primary)
        #expect(restored.rateWindows == exported.rateWindows)
    }

    /// The pre-change consumer ignores the new optional JSON key.
    private struct LegacyWindow: Decodable {
        let usedPercent: Double
        let resetsAt: Date?
    }
}
