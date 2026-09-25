import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ClaudeSwapWidgetSnapshotTests {
    private let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `swap refresh and clearing publish provider widgets without account widgets`() async throws {
        let (settings, store) = self.makeStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("cswap")
        try #"""
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo 'cswap 0.0.0-synthetic'; exit 0; fi
        if [ "$#" -eq 2 ] && [ "$1" = "--list" ] && [ "$2" = "--json" ]; then
          exec /bin/cat "$0.json"
        fi
        exit 64
        """#.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        settings.claudeSwapExecutablePath = executable.path
        #expect(!settings.accountWidgetsEnabled)
        store._setSnapshotForTesting(self.usage(100), provider: .claude)
        var publications: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { publications.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        for activeSlot in 1...2 {
            let data = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1,
                "activeAccountNumber": activeSlot,
                "accounts": (1...2).map { slot in
                    [
                        "number": slot,
                        "email": "account\(slot)@example.invalid",
                        "organizationName": "",
                        "active": slot == activeSlot,
                        "usageStatus": "ok",
                        "usage": ["fiveHour": ["pct": slot * 20]],
                    ] as [String: Any]
                },
            ])
            try data.write(to: URL(fileURLWithPath: executable.path + ".json"))
            await store.refreshClaudeSwapAccounts()
            await store.widgetSnapshotPersistTask?.value
            #expect(publications.count == activeSlot)
            let entry = publications.last?.entries.first { $0.provider == .claude }
            #expect(entry?.primary?.usedPercent == Double(activeSlot * 20))
            #expect(entry?.quotaOwnerKey?.hasPrefix("claude/swap:\(activeSlot):") == true)
            #expect(publications.last?.accounts.isEmpty == true)
        }

        store.clearClaudeSwapAccountState()
        await store.widgetSnapshotPersistTask?.value
        #expect(publications.count == 3)
        #expect(publications.last?.entries.first { $0.provider == .claude }?.primary?.usedPercent == 100)
    }

    @Test(arguments: ["missing", "replacement", "no-active"])
    func `unavailable swap owners cannot inherit another accounts quota`(state: String) async {
        let (_, store) = self.makeStore()
        store._setSnapshotForTesting(self.usage(100), provider: .claude)
        store.claudeSwapAccountSnapshots = [self.account("1", used: 20), self.account("2", active: false, used: 40)]
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        defer { store._test_widgetSnapshotSaveOverride = nil }
        store.persistWidgetSnapshot(reason: "swap-owner-before")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.first { $0.provider == .claude }?.primary?.usedPercent == 20)

        store.claudeSwapAccountSnapshots = [
            self.account(
                state == "missing" ? "3" : "1",
                active: state != "no-active",
                used: nil,
                email: state == "replacement" ? "replacement@example.invalid" : nil),
            self.account("2", active: false, used: 40),
        ]
        store.persistWidgetSnapshot(reason: "swap-owner-after")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.contains { $0.provider == .claude } == false)
    }

    @Test
    func `matching retained swap quota keeps its measurement age`() async throws {
        let (_, store) = self.makeStore()
        store.claudeSwapAccountSnapshots = [self.account("1", used: 20), self.account("2", active: false, used: 40)]
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        defer { store._test_widgetSnapshotSaveOverride = nil }
        store.persistWidgetSnapshot(reason: "swap-retained-before")
        await store.widgetSnapshotPersistTask?.value
        let owner = saved?.entries.first?.quotaOwnerKey
        #expect(owner?.hasPrefix("claude/swap:1:") == true)

        store.claudeSwapAccountSnapshots = [self.account("1", used: nil), self.account("2", active: false, used: 40)]
        store.persistWidgetSnapshot(reason: "swap-retained-after")
        await store.widgetSnapshotPersistTask?.value
        let entry = try #require(saved?.entries.first { $0.provider == .claude })
        #expect(entry.primary?.usedPercent == 20)
        #expect(entry.updatedAt == self.measuredAt)
        #expect(entry.quotaOwnerKey == owner)
    }

    @Test(arguments: [false, true])
    func `single swap account obeys presentation preference and stays provider scoped`(showSingle: Bool) async {
        let (settings, store) = self.makeStore()
        settings.claudeSwapShowSingleAccount = showSingle
        store._setSnapshotForTesting(self.usage(100), provider: .claude)
        store._setSnapshotForTesting(self.usage(70), provider: .codex)
        store.claudeSwapAccountSnapshots = [self.account("1", used: 20)]
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        defer { store._test_widgetSnapshotSaveOverride = nil }
        store.persistWidgetSnapshot(reason: "swap-single")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.first { $0.provider == .claude }?.primary?.usedPercent == (showSingle ? 20 : 100))
        #expect(saved?.entries.first { $0.provider == .codex }?.primary?.usedPercent == 70)

        settings.claudeSwapEnabled = false
        store.persistWidgetSnapshot(reason: "swap-disabled")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved?.entries.first { $0.provider == .claude }?.primary?.usedPercent == 100)
    }

    private func makeStore() -> (SettingsStore, UsageStore) {
        let settings = testSettingsStore(
            suiteName: "ClaudeSwapWidgetSnapshotTests",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        enableTestProviders([.claude, .codex], settings: settings)
        settings.claudeSwapEnabled = true
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(homeDirectory: "/synthetic", fileExists: { _ in false }),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        return (settings, store)
    }

    private func usage(_ used: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: used, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: self.measuredAt)
    }

    private func account(
        _ slot: String,
        active: Bool = true,
        used: Double?,
        email: String? = nil) -> ProviderAccountUsageSnapshot
    {
        ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "claude-swap", opaqueID: slot),
            provider: .claude,
            displayLabel: "Account \(slot)",
            accountEmail: email ?? "account\(slot)@example.invalid",
            isActive: active,
            snapshot: used.map(self.usage),
            error: nil,
            sourceLabel: "claude-swap")
    }
}
