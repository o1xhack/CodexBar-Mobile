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
        private(set) var warningWrites: [(
            provider: UsageProvider,
            window: QuotaWarningWindow,
            threshold: Int,
            accountDisplayName: String?)] = []

        func write(
            transition: SessionQuotaTransition,
            provider: UsageProvider,
            accountDisplayName: String?)
        {
            self.transitionWrites.append((transition, provider, accountDisplayName))
        }

        func writeQuotaWarning(
            provider: UsageProvider,
            window: QuotaWarningWindow,
            threshold: Int,
            accountDisplayName: String?)
        {
            self.warningWrites.append((provider, window, threshold, accountDisplayName))
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
        #expect(writer.warningWrites.first?.window == .session)
        #expect(writer.warningWrites.first?.threshold == 50)
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
        let thresholds = writer.warningWrites.map(\.threshold).sorted()
        #expect(thresholds == [20, 50])
    }
}
