import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CodexKeyringCostInvestigationTests {
    @Test(arguments: [false, true])
    func `local spend publishes without auth json or a quota identity`(localLedger: Bool) async throws {
        let files = try CostUsageTestEnvironment()
        defer { files.cleanup() }
        let home = files.root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions", isDirectory: true)
        let archive = home.appendingPathComponent("archived_sessions", isDirectory: true)
        let now = Date()
        let day = CostUsageScanner.CostUsageDayRange.dayKey(from: now)
        let partition = sessions.appendingPathComponent(day.replacingOccurrences(of: "-", with: "/"))
        try FileManager.default.createDirectory(at: partition, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for (directory, count) in [(partition, 1_000_000), (archive, 2_000_000)] {
            let contents = try files.jsonl([
                [
                    "type": "turn_context",
                    "timestamp": files.isoString(for: now),
                    "payload": ["model": "gpt-5.4"],
                ],
                [
                    "type": "event_msg",
                    "timestamp": files.isoString(for: now),
                    "payload": ["type": "token_count", "info": [
                        "last_token_usage": ["input_tokens": count, "cached_input_tokens": 0, "output_tokens": 0],
                        "model": "gpt-5.4",
                    ]],
                ],
            ])
            try contents.write(
                to: directory.appendingPathComponent("rollout-\(day)-\(count).jsonl"),
                atomically: true,
                encoding: .utf8)
        }
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
        let settings = testSettingsStore(suiteName: "CodexKeyringCostInvestigationTests")
        settings._test_managedCodexAccountStoreURL = files.root.appendingPathComponent("accounts.json")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.costUsageEnabled = true
        settings.codexLocalSessionCostLedgerEnabled = localLedger
        settings.codexActiveSource = .liveSystem
        enableTestProviders([.codex, .pi], settings: settings)
        let environment = ["HOME": files.root.path, "CODEX_HOME": home.path]
        settings._test_codexReconciliationEnvironment = environment
        let options = CostUsageScanner.Options(
            codexSessionsRoot: sessions,
            cacheRoot: files.cacheRoot,
            codexTraceDatabaseURL: files.root.appendingPathComponent("missing-traces.sqlite"))
        let fetcher = CostUsageFetcher(scannerOptions: options)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: files.root.path, cacheTTL: 0),
            costUsageFetcher: fetcher,
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        store._test_widgetSnapshotSaveOverride = { _ in }
        #expect(store.tokenCostScope(for: .codex).signature == "codex:ambient")
        #expect(store.snapshot(for: .codex) == nil)
        // Keep pricing offline in both modes while exercising the real scanner and publication path.
        store._test_tokenUsageResultLoaderOverride = { provider, _, date, homePath, days, includePi in
            try await fetcher.loadTokenResult(
                provider: provider,
                environment: environment,
                now: date,
                codexHomePath: homePath,
                historyDays: days,
                allowPricingRefresh: false,
                includePiSessions: includePi,
                bypassScannerDebounce: true)
        }
        await store.refreshTokenUsage(.codex, force: true)
        let snapshot = try #require(store.tokenSnapshot(for: .codex))
        #expect(snapshot.sessionTokens == 3_000_000)
        #expect(try #require(snapshot.sessionCostUSD) > 0)
        #expect(try #require(snapshot.last30DaysCostUSD) > 0)
        #expect(store.tokenError(for: .codex) == nil)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
        let requests = SpendDashboardSource.codexRequests(settings: settings, store: store)
        #expect(requests.count == 1)
        #expect(requests.first?.homePath == home.path)
        let request = try #require(requests.first)
        #expect(request.id == "local")
        #expect(request.authFingerprint == nil)
        #expect(!request.authFileWasReadable)
        #expect(SpendDashboardSource.codexAuthFingerprintMatches(request))
        let dashboard = try await fetcher.loadTokenSnapshot(
            provider: .codex,
            environment: environment,
            now: now,
            codexHomePath: request.homePath,
            historyDays: SpendDashboardSource.scanDays,
            allowPricingRefresh: false,
            includePiSessions: false)
        #expect(dashboard.sessionTokens == 3_000_000)
        #expect(try #require(dashboard.last30DaysCostUSD) > 0)

        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "synthetic@example.com", codexHomePath: home.path, observedAt: now)
        let identified = SpendDashboardSource.codexRequests(settings: settings, store: store)
        #expect(identified.count == 1)
        #expect(identified.first?.homePath == home.path)
        #expect(identified.first?.id != "local")

        let managedHome = files.root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managedHome, withIntermediateDirectories: true)
        let managed = ManagedCodexAccount(
            id: UUID(),
            email: "managed@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        settings._test_liveSystemCodexAccount = nil
        settings._test_activeManagedCodexAccount = managed
        settings._test_activeManagedCodexRemoteHomePath = managedHome.path
        settings.codexActiveSource = .managedAccount(id: managed.id)
        let combined = SpendDashboardSource.codexRequests(settings: settings, store: store)
        #expect(combined.count == 2)
        #expect(combined.first(where: { $0.id == "local" })?.homePath == home.path)
        #expect(combined.first(where: { $0.source == .managedAccount(id: managed.id) })?.homePath == managedHome.path)
        #expect(Set(combined.map(\.cacheIdentity)).count == 2)

        settings._test_activeManagedCodexRemoteHomePath = home.path + "/../.codex/"
        let aliased = SpendDashboardSource.codexRequests(settings: settings, store: store)
        #expect(aliased.count == 1)
        #expect(aliased.first?.homePath == home.path)
        #expect(aliased.first?.source == .managedAccount(id: managed.id))
    }
}
