import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct OllamaUsageStoreDurabilityTests {
    @Test
    func `empty Ollama API result preserves the last good quota snapshot`() async throws {
        let settings = testSettingsStore(suiteName: "OllamaUsageStoreDurabilityTests-empty-api")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.providerDetectionCompleted = true
        settings.ollamaAPIToken = "fixture-ollama-api-key"
        try settings.setProviderEnabled(
            provider: .ollama,
            metadata: #require(ProviderDefaults.metadata[.ollama]),
            enabled: true)

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let goodSnapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 38,
                windowMinutes: 60,
                resetsAt: pinned.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: pinned.addingTimeInterval(86400),
                resetDescription: nil),
            updatedAt: pinned,
            identity: ProviderIdentitySnapshot(
                providerID: .ollama,
                accountEmail: "user@example.com",
                accountOrganization: nil,
                loginMethod: "web"))
        store._setSnapshotForTesting(goodSnapshot, provider: .ollama)

        let emptyAPISnapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: pinned.addingTimeInterval(60),
            identity: ProviderIdentitySnapshot(
                providerID: .ollama,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "API key"))
        store._test_providerFetchOutcomeOverride = { provider in
            #expect(provider == .ollama)
            return ProviderFetchOutcome(
                result: .success(ProviderFetchResult(
                    usage: emptyAPISnapshot,
                    credits: nil,
                    dashboard: nil,
                    sourceLabel: "api",
                    strategyID: "ollama.api",
                    strategyKind: .apiToken,
                    diagnostic: OllamaAPIUsageSnapshot.cloudQuotaDiagnostic)),
                attempts: [])
        }
        defer { store._test_providerFetchOutcomeOverride = nil }

        await store.refreshProvider(.ollama)

        #expect(store.snapshot(for: .ollama)?.primary?.usedPercent == 38)
        #expect(store.snapshot(for: .ollama)?.secondary?.usedPercent == 12)
        #expect(store.sourceLabel(for: .ollama) == "api")
        #expect(store.diagnostic(for: .ollama) == OllamaAPIUsageSnapshot.cloudQuotaDiagnostic)
    }
}
