import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// v0.72 merge: upstream reset notifications may replace the Mac's restored banner, but the
/// iPhone QuotaTransition record must still be written for both transitions.
@MainActor
@Suite("Session quota transitions reach iOS alongside reset arbitration")
struct SessionQuotaTransitionIOSPushTests {
    private typealias WriterSpy = QuotaWarningPushFireTests.QuotaTransitionWriterSpy
    private typealias NotifierSpy = QuotaWarningPushFireTests.SessionQuotaNotifierSpy

    private func makeStore(
        suiteName: String,
        resetNotifications: Bool,
        writer: WriterSpy) -> UsageStore
    {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.sessionQuotaNotificationsEnabled = true
        settings.limitResetNotificationsEnabled = resetNotifications
        settings.notificationPushToiOSEnabled = true
        return UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: NotifierSpy(),
            quotaTransitionWriter: writer)
    }

    private func snapshot(used: Double, at date: Date) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: used,
                windowMinutes: 300,
                resetsAt: date.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            updatedAt: date)
    }

    @Test(arguments: [true, false])
    func `restored transitions are written for iOS whether or not reset notices arbitrate`(
        resetNotifications: Bool)
    {
        let writer = WriterSpy()
        let store = self.makeStore(
            suiteName: "SessionQuotaTransitionIOSPushTests-\(resetNotifications)",
            resetNotifications: resetNotifications,
            writer: writer)
        let start = Date(timeIntervalSince1970: 1_791_500_000)
        store.handleSessionQuotaTransition(provider: .claude, snapshot: self.snapshot(used: 40, at: start))
        store.handleSessionQuotaTransition(
            provider: .claude,
            snapshot: self.snapshot(used: 100, at: start.addingTimeInterval(60)),
            now: start.addingTimeInterval(60))
        let deferred = store.handleSessionQuotaTransition(
            provider: .claude,
            snapshot: self.snapshot(used: 10, at: start.addingTimeInterval(120)),
            now: start.addingTimeInterval(120))

        #expect(writer.transitionWrites.map(\.transition) == [.depleted, .restored])
        #expect(writer.transitionWrites.allSatisfy { $0.provider == .claude })
        // The account-scoped reset detector owns the restored banner only when reset notices are on.
        #expect(deferred == resetNotifications)
    }
}
