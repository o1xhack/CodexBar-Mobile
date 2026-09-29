import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuDescriptorMistralTests {
    @Test(arguments: [nil, Date(timeIntervalSince1970: 1_790_812_800)])
    func `Monthly Plan amounts show as detail, never as a reset time`(resetsAt: Date?) {
        let suite = "MenuDescriptorMistralTests-\(resetsAt == nil ? "undated" : "dated")"
        let settings = testSettingsStore(suiteName: suite, userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [NamedRateWindow(
                id: "mistral-monthly-plan",
                title: "Monthly Plan",
                window: RateWindow(
                    usedPercent: 13,
                    windowMinutes: nil,
                    resetsAt: resetsAt,
                    resetDescription: "€34.07 / €255.00 · €220.93 left"))],
            updatedAt: Date(timeIntervalSince1970: 1))
        store._setSnapshotForTesting(snapshot, provider: .mistral)

        let descriptor = MenuDescriptor.build(
            provider: .mistral,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)
        let lines = descriptor.sections.flatMap(\.entries).compactMap { entry -> String? in
            guard case let .text(text, _) = entry else { return nil }
            return text
        }

        #expect(lines.contains(where: { $0.hasPrefix("Monthly Plan:") }))
        #expect(lines.contains("€34.07 / €255.00 · €220.93 left"))
        #expect(!lines.contains(where: { $0.contains("Resets") && $0.contains("€") }))
    }
}
