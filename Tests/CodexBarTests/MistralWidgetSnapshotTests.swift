import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, ProviderTransportRegressionFixtures())
@MainActor
struct MistralWidgetSnapshotTests {
    @Test(arguments: [
        (MenuBarMetricPreference.automatic, ["primary"]),
        (MenuBarMetricPreference.primary, ["primary"]),
        (MenuBarMetricPreference.monthlyPlan, ["mistral-monthly-plan"]),
    ], ["known", "unknown", "missing"])
    func `widget snapshot follows the Mistral metric for Monthly Plan rows`(
        selection: (MenuBarMetricPreference, [String]),
        planState: String) async throws
    {
        let (preference, selectedIDs) = selection
        let expectedIDs = planState == "known" ? selectedIDs : ["primary"]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let suite = "UsageStoreWidgetSnapshotTests-mistral-monthly-plan-\(preference.rawValue)"
        let root = ProviderTransportRegressionFixtures.root.appendingPathComponent(UUID().uuidString)
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("codex").path]
        let settings = testSettingsStore(
            suiteName: suite,
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        settings._test_codexReconciliationEnvironment = environment
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.setMenuBarMetricPreference(preference, for: .mistral)
        enableTestProviders([.mistral], settings: settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: root.path, fileExists: { _ in false }),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: root
                .appendingPathComponent("history.json")),
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: environment,
            widgetSnapshotURL: root.appendingPathComponent("widget.json"),
            widgetTimelineReloader: {})
        let planWindow = RateWindow(
            usedPercent: 40,
            windowMinutes: nil,
            resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60),
            resetDescription: "€102.00 / €255.00 · €153.00 left")
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                extraRateWindows: planState == "missing" ? [] : [
                    NamedRateWindow(
                        id: "mistral-monthly-plan",
                        title: "Monthly Plan",
                        window: planWindow,
                        usageKnown: planState == "known"),
                    NamedRateWindow(id: "unrelated", title: "Unrelated", window: planWindow),
                ],
                updatedAt: now),
            provider: .mistral)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "mistral-monthly-plan-test")
        await store.widgetSnapshotPersistTask?.value

        let entry = try #require(widgetSnapshots.last?.entries.first { $0.provider == .mistral })
        let rows = try #require(entry.usageRows)
        #expect(rows.map(\.id) == expectedIDs)
        let titles = ["primary": "Included API", "mistral-monthly-plan": "Monthly Plan"]
        let percents = ["primary": 90.0, "mistral-monthly-plan": 60.0]
        #expect(rows.map(\.title) == expectedIDs.compactMap { titles[$0] })
        #expect(rows.compactMap(\.percentLeft) == expectedIDs.compactMap { percents[$0] })
        // The plan row carries its window so widgets can show when the plan resets.
        #expect(rows.last?.window == (expectedIDs.last == "mistral-monthly-plan" ? planWindow : nil))
    }

    @Test
    func `providers without a widget row resolver retain their rows`() {
        let rows = [WidgetSnapshot.WidgetUsageRowSnapshot(id: "custom", title: "Custom", percentLeft: 25)]
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date(timeIntervalSince1970: 1))
        let presentation = ProviderUsagePresentation()
        #expect(!presentation.widgetRowsFollowMenuBarMetric)
        #expect(MistralProviderDescriptor.descriptor.presentation.widgetRowsFollowMenuBarMetric)
        for metric in [ProviderMenuBarMetric.automatic, .primary, .monthlyPlan] {
            #expect(presentation.widgetRows(rows, snapshot: snapshot, metric: metric) == rows)
        }
    }
}
