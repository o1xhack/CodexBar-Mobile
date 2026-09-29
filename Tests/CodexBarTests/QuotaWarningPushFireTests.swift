import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Tests for iOS 1.6.0 / Mac 0.25.2 Phase 2 — Mac-side warning CKRecord
/// emission alongside the local `postQuotaWarning` notification.
/// See Research/020-multi-account-comprehensive.md §R7.4 Phase 2.
@MainActor
@Suite("Quota warning CK push fire")
struct QuotaWarningPushFireTests {
    @MainActor
    final class QuotaTransitionWriterSpy: QuotaTransitionWriting {
        private(set) var transitionWrites: [(
            transition: SessionQuotaTransition,
            provider: UsageProvider,
            accountDisplayName: String?)] = []
        private(set) var warningWrites: [(provider: UsageProvider, event: QuotaWarningEvent)] = []

        func write(
            transition: SessionQuotaTransition,
            provider: UsageProvider,
            accountDisplayName: String?)
        {
            self.transitionWrites.append((transition, provider, accountDisplayName))
        }

        func writeQuotaWarning(
            event: QuotaWarningEvent,
            provider: UsageProvider)
        {
            self.warningWrites.append((provider, event))
        }
    }

    @MainActor
    final class SessionQuotaNotifierSpy: SessionQuotaNotifying {
        private(set) var quotaWarningPosts: [(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool)] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool)
        {
            self.quotaWarningPosts.append((
                event: event,
                provider: provider,
                soundEnabled: soundEnabled,
                onScreenAlertEnabled: onScreenAlertEnabled))
        }
    }

    private func makeSettings(suiteName: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    @Test
    func `crossing a threshold writes a CKRecord when push gate is on`() {
        let settings = self.makeSettings(suiteName: "QuotaWarningPushFireTests-on")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = true

        let notifier = SessionQuotaNotifierSpy()
        let writer = QuotaTransitionWriterSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            quotaTransitionWriter: writer)

        // First update establishes the baseline at 80% remaining
        // — no thresholds crossed yet.
        let baseline = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: baseline)

        // Now drop to 40% remaining (= 60% used) — crosses the
        // default 50% remaining threshold.
        let crossed = UsageSnapshot(
            primary: RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: crossed)

        #expect(notifier.quotaWarningPosts.count == 1)
        #expect(notifier.quotaWarningPosts.first?.event.threshold == 50)

        // The whole point of Phase 2: writer also got called for iOS push.
        #expect(writer.warningWrites.count == 1)
        #expect(writer.warningWrites.first?.provider == .claude)
        #expect(writer.warningWrites.first?.event.window == .session)
        #expect(writer.warningWrites.first?.event.threshold == 50)
    }

    @Test
    func `push gate off → local notification fires but no CKRecord write`() {
        let settings = self.makeSettings(suiteName: "QuotaWarningPushFireTests-off")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = false // gate OFF

        let notifier = SessionQuotaNotifierSpy()
        let writer = QuotaTransitionWriterSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            quotaTransitionWriter: writer)

        let baseline = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store.handleQuotaWarningTransitions(provider: .codex, snapshot: baseline)

        let crossed = UsageSnapshot(
            primary: RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store.handleQuotaWarningTransitions(provider: .codex, snapshot: crossed)

        // Local fired (gate quotaWarningNotificationsEnabled is on).
        #expect(notifier.quotaWarningPosts.count == 1)
        // Writer did NOT fire (push gate off).
        #expect(writer.warningWrites.isEmpty)
    }

    @Test
    func `crossing two thresholds in sequence writes two records`() {
        let settings = self.makeSettings(suiteName: "QuotaWarningPushFireTests-two-thresholds")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = true

        let notifier = SessionQuotaNotifierSpy()
        let writer = QuotaTransitionWriterSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            quotaTransitionWriter: writer)

        let baseline = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: baseline)

        // Cross 50% threshold.
        let firstCross = UsageSnapshot(
            primary: RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: firstCross)

        // Cross 20% threshold next — remaining drops from 40% to 15%.
        let secondCross = UsageSnapshot(
            primary: RateWindow(usedPercent: 85, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store.handleQuotaWarningTransitions(provider: .claude, snapshot: secondCross)

        #expect(writer.warningWrites.count == 2)
        let thresholds = writer.warningWrites.map(\.event.threshold).sorted()
        #expect(thresholds == [20, 50])
    }

    @Test
    func `Aixy promoted and named budgets keep independent period-aware warning lanes`() {
        let settings = self.makeSettings(suiteName: "QuotaWarningPushFireTests-aixy-periods")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = true
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)
        settings.setQuotaWarningThresholds(.session, thresholds: [70])
        settings.setQuotaWarningThresholds(.weekly, thresholds: [40])

        let notifier = SessionQuotaNotifierSpy()
        let writer = QuotaTransitionWriterSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            quotaTransitionWriter: writer)

        func snapshot(usedPercent: Double, at time: TimeInterval) -> UsageSnapshot {
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: usedPercent,
                    windowMinutes: 1440,
                    resetsAt: nil,
                    resetDescription: nil,
                    period: .daily,
                    id: "aixy-daily-budget",
                    label: "Organization · Daily · Shared · Hard"),
                secondary: RateWindow(
                    usedPercent: usedPercent,
                    windowMinutes: 43200,
                    resetsAt: nil,
                    resetDescription: nil,
                    period: .monthly,
                    id: "aixy-monthly-budget",
                    label: "Project · Monthly · Shared · Hard"),
                extraRateWindows: [
                    NamedRateWindow(
                        id: "aixy-weekly-budget",
                        title: "Team · Weekly · Personal · Monitor",
                        window: RateWindow(
                            usedPercent: usedPercent,
                            windowMinutes: 10080,
                            resetsAt: nil,
                            resetDescription: nil,
                            period: .weekly)),
                ],
                updatedAt: Date(timeIntervalSince1970: time))
        }

        store.handleQuotaWarningTransitions(provider: .aixy, snapshot: snapshot(usedPercent: 10, at: 1_800_000_000))
        store.handleQuotaWarningTransitions(provider: .aixy, snapshot: snapshot(usedPercent: 65, at: 1_800_000_001))

        #expect(writer.warningWrites.count == 3)
        #expect(Set(writer.warningWrites.compactMap(\.event.windowID)) == [
            "aixy-daily-budget", "aixy-monthly-budget", "aixy-weekly-budget",
        ])
        #expect(writer.warningWrites.first(where: { $0.event.windowID == "aixy-daily-budget" })?.event
            .window == .session)
        #expect(writer.warningWrites.first(where: { $0.event.windowID == "aixy-daily-budget" })?.event
            .windowPeriod == .daily)
        #expect(writer.warningWrites.first(where: { $0.event.windowID == "aixy-monthly-budget" })?.event
            .window == .weekly)
        #expect(writer.warningWrites.first(where: { $0.event.windowID == "aixy-monthly-budget" })?.event
            .windowPeriod == .monthly)
        #expect(writer.warningWrites.first(where: { $0.event.windowID == "aixy-monthly-budget" })?.event
            .windowDisplayLabel ==
            "Project · Monthly · Shared · Hard")
        #expect(writer.warningWrites.first(where: { $0.event.windowID == "aixy-weekly-budget" })?.event
            .window == .weekly)
    }

    @Test
    func `daily provider-authored quota labels do not repeat the localized period`() {
        let settings = self.makeSettings(suiteName: "QuotaWarningPushFireTests-daily-label")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = true
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningThresholds(.session, thresholds: [20])

        let writer = QuotaTransitionWriterSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: SessionQuotaNotifierSpy(),
            quotaTransitionWriter: writer)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 85,
                windowMinutes: 1440,
                resetsAt: nil,
                resetDescription: nil,
                period: .daily,
                label: "Daily free tokens"),
            secondary: nil,
            updatedAt: Date())

        store.handleQuotaWarningTransitions(provider: .xkiro, snapshot: snapshot)

        #expect(writer.warningWrites.count == 1)
        #expect(writer.warningWrites.first?.event.window == .session)
        #expect(writer.warningWrites.first?.event.windowPeriod == .daily)
        #expect(writer.warningWrites.first?.event.windowDisplayLabel == nil)
    }
}
