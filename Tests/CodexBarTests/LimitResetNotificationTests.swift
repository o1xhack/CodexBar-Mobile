import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct LimitResetNotificationTests {
    struct LimitResetPost: Equatable {
        let provider: UsageProvider
        let window: QuotaWarningWindow
        let accountDisplayName: String?
    }

    @MainActor
    final class NotifierSpy: SessionQuotaNotifying {
        private(set) var transitionPosts: [(transition: SessionQuotaTransition, provider: UsageProvider)] = []
        private(set) var limitResetPosts: [LimitResetPost] = []
        var deliveryChecks: [@MainActor () -> Bool] = []

        func post(transition: SessionQuotaTransition, provider: UsageProvider, badge _: NSNumber?) {
            self.transitionPosts.append((transition: transition, provider: provider))
        }

        func postQuotaWarning(
            event _: QuotaWarningEvent,
            provider _: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {}

        func postLimitReset(
            provider: UsageProvider,
            window: QuotaWarningWindow,
            accountDisplayName: String?,
            isCurrent: @escaping @MainActor () -> Bool)
        {
            self.deliveryChecks.append(isCurrent)
            self.limitResetPosts.append(LimitResetPost(
                provider: provider,
                window: window,
                accountDisplayName: accountDisplayName))
        }
    }

    private static let accountEmail = "limit-reset-notice@example.com"
    private static let start = Date(timeIntervalSince1970: 1_784_600_000)

    @Test
    func `limit reset notifications default off and persist when enabled`() {
        let defaults = InMemoryUserDefaults()
        let settings = Self.makeSettings(defaults: defaults)

        #expect(settings.limitResetNotificationsEnabled == false)
        #expect(defaults.object(forKey: "limitResetNotificationsEnabled") == nil)

        settings.limitResetNotificationsEnabled = true

        #expect(defaults.bool(forKey: "limitResetNotificationsEnabled") == true)
        #expect(Self.makeSettings(defaults: defaults).limitResetNotificationsEnabled == true)
    }

    @Test
    func `weekly reset notice names provider window and account`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true

        await Self.record(store, sessionUsed: 20, weeklyUsed: 60, offset: 0)
        await Self.record(store, sessionUsed: 20, weeklyUsed: 0, offset: 60 * 60)

        #expect(notifier.limitResetPosts == [
            LimitResetPost(provider: .claude, window: .weekly, accountDisplayName: Self.accountEmail),
        ])
    }

    @Test
    func `session reset notice names the session window`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true

        await Self.record(store, sessionUsed: 65, weeklyUsed: 20, offset: 0)
        await Self.record(store, sessionUsed: 0, weeklyUsed: 20, offset: 60 * 60)

        #expect(notifier.limitResetPosts == [
            LimitResetPost(provider: .claude, window: .session, accountDisplayName: Self.accountEmail),
        ])
    }

    @Test
    func `reset notices stay silent when disabled`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        let recorder = WeeklyLimitResetEventRecorder(provider: .claude, accountLabel: Self.accountEmail)
        defer { recorder.invalidate() }

        await Self.record(store, sessionUsed: 20, weeklyUsed: 60, offset: 0)
        await Self.record(store, sessionUsed: 20, weeklyUsed: 0, offset: 60 * 60)

        #expect(recorder.events.count == 1)
        #expect(notifier.limitResetPosts.isEmpty)
    }

    @Test
    func `hide personal info omits the account from reset notices`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true
        store.settings.hidePersonalInfo = true

        await Self.record(store, sessionUsed: 20, weeklyUsed: 60, offset: 0)
        await Self.record(store, sessionUsed: 20, weeklyUsed: 0, offset: 60 * 60)

        #expect(notifier.limitResetPosts == [
            LimitResetPost(provider: .claude, window: .weekly, accountDisplayName: nil),
        ])
    }

    @Test
    func `session restored notice covers the matching session reset notice`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.sessionQuotaNotificationsEnabled = true
        store.settings.limitResetNotificationsEnabled = true

        let depleted = Self.snapshot(sessionUsed: 100, weeklyUsed: 60, offset: 0)
        let reset = Self.snapshot(sessionUsed: 0, weeklyUsed: 0, offset: 60 * 60)
        store.handleSessionQuotaTransition(provider: .claude, snapshot: depleted, now: depleted.updatedAt)
        await store.recordPlanUtilizationHistorySample(provider: .claude, snapshot: depleted, now: depleted.updatedAt)
        let restored = store.handleSessionQuotaTransition(provider: .claude, snapshot: reset, now: reset.updatedAt)
        await store.recordPlanUtilizationHistorySample(
            provider: .claude, snapshot: reset, sessionRestoredNotificationPending: restored, now: reset.updatedAt)

        #expect(notifier.transitionPosts.map(\.transition) == [.depleted, .restored])
        #expect(notifier.limitResetPosts == [
            LimitResetPost(provider: .claude, window: .weekly, accountDisplayName: Self.accountEmail),
        ])
    }

    @Test
    func `reset notice copy names provider and window`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let weekly = LimitResetNotificationLogic.notificationCopy(
                providerName: "Claude",
                window: .weekly,
                accountDisplayName: nil)
            #expect(weekly.title == "Claude weekly limit reset")
            #expect(weekly.body == "Fresh quota is available.")

            let session = LimitResetNotificationLogic.notificationCopy(
                providerName: "Codex",
                window: .session,
                accountDisplayName: "work@example.com")
            #expect(session.title == "Codex session limit reset")
            #expect(session.body == "Account work@example.com. Fresh quota is available.")
        }
    }

    @Test
    func `reset notice copy is localized for simplified Chinese`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let copy = LimitResetNotificationLogic.notificationCopy(
                providerName: "Claude",
                window: .weekly,
                accountDisplayName: nil)
            #expect(copy.title == "Claude 每周额度已重置")
        }
    }

    @Test
    func `portable preferences carry the reset toggle in both directions`() throws {
        let source = Self.makeSettings(defaults: InMemoryUserDefaults())
        let target = Self.makeSettings(defaults: InMemoryUserDefaults())
        source.limitResetNotificationsEnabled = true
        let document = try PreferencesDocument(data: source.exportPreferences().encoded())
        #expect(try document.value("limitResetNotificationsEnabled") == true)
        try target.importPreferences(document)
        #expect(target.limitResetNotificationsEnabled)
        try target.importPreferences(PreferencesDocument())
        #expect(target.limitResetNotificationsEnabled)
        source.limitResetNotificationsEnabled = false
        try target.importPreferences(source.exportPreferences())
        #expect(!target.limitResetNotificationsEnabled)
    }

    @Test
    func `restored notice for one account does not suppress another account reset`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.sessionQuotaNotificationsEnabled = true
        store.settings.limitResetNotificationsEnabled = true
        let depleted = Self.snapshot(sessionUsed: 100, weeklyUsed: 20, offset: 0)
        let restored = Self.snapshot(sessionUsed: 0, weeklyUsed: 20, offset: 60)
        store.handleSessionQuotaTransition(provider: .claude, snapshot: depleted, now: depleted.updatedAt)
        let pending = store.handleSessionQuotaTransition(provider: .claude, snapshot: restored, now: restored.updatedAt)
        await store.recordPlanUtilizationHistorySample(
            provider: .claude, snapshot: restored, sessionRestoredNotificationPending: pending, now: restored.updatedAt)
        #expect(notifier.transitionPosts.map(\.transition) == [.depleted, .restored])
        let otherHigh = Self.snapshot(sessionUsed: 60, weeklyUsed: 20, offset: 0, email: "other@example.com")
        let otherLow = Self.snapshot(sessionUsed: 0, weeklyUsed: 20, offset: 60, email: "other@example.com")
        await store.recordPlanUtilizationHistorySample(provider: .claude, snapshot: otherHigh, now: otherHigh.updatedAt)
        await store.recordPlanUtilizationHistorySample(provider: .claude, snapshot: otherLow, now: otherLow.updatedAt)
        #expect(notifier.limitResetPosts == [
            LimitResetPost(provider: .claude, window: .session, accountDisplayName: "other@example.com"),
        ])
    }

    @Test
    func `weekly reset boundary is notified once across refreshes and restarts`() async {
        let notifier = NotifierSpy()
        let defaults = InMemoryUserDefaults()
        var store = Self.makeStore(notifier: notifier, defaults: defaults)
        store.settings.limitResetNotificationsEnabled = true
        let boundary = Self.start.addingTimeInterval(7 * 86400)
        for (index, used) in [60.0, 0, 20, 30, 0].enumerated() {
            if index == 2 {
                store = Self.makeStore(notifier: notifier, defaults: defaults)
            }
            let snapshot = Self.snapshot(
                sessionUsed: 20, weeklyUsed: used, offset: Double(index) * 60, resetBoundary: boundary)
            await store.recordPlanUtilizationHistorySample(
                provider: .claude,
                snapshot: snapshot,
                now: snapshot.updatedAt)
        }
        #expect(notifier.limitResetPosts.count == 1)
    }

    @Test
    func `a restored confirmation after restart does not repeat a reset banner`() async {
        let notifier = NotifierSpy()
        let defaults = InMemoryUserDefaults()
        var store = Self.makeStore(notifier: notifier, defaults: defaults)
        store.settings.limitResetNotificationsEnabled = true
        await Self.record(store, sessionUsed: 60, weeklyUsed: 20, offset: 0)
        await Self.record(store, sessionUsed: 0, weeklyUsed: 20, offset: 60)
        store = Self.makeStore(notifier: notifier, defaults: defaults)
        store.settings.sessionQuotaNotificationsEnabled = true
        let depleted = Self.snapshot(sessionUsed: 100, weeklyUsed: 20, offset: 90)
        let reset = Self.snapshot(sessionUsed: 0, weeklyUsed: 20, offset: 120)
        store.handleSessionQuotaTransition(provider: .claude, snapshot: depleted, now: depleted.updatedAt)
        let restored = store.handleSessionQuotaTransition(provider: .claude, snapshot: reset, now: reset.updatedAt)
        await store.recordPlanUtilizationHistorySample(
            provider: .claude, snapshot: reset, sessionRestoredNotificationPending: restored, now: reset.updatedAt)
        #expect(notifier.limitResetPosts.count == 1)
        #expect(notifier.transitionPosts.map(\.transition) == [.depleted])
    }

    @Test(arguments: [2, 4])
    func `reset notices recover when a provider stops reporting reset boundaries`(missingFrom: Int) async {
        let notifier = NotifierSpy()
        let defaults = InMemoryUserDefaults()
        var store = Self.makeStore(notifier: notifier, defaults: defaults)
        store.settings.limitResetNotificationsEnabled = true
        for (index, used) in [60.0, 0, 20, 30, 0].enumerated() {
            if index == 2 {
                store = Self.makeStore(notifier: notifier, defaults: defaults)
            }
            let boundary = index < missingFrom ? Self.start.addingTimeInterval(7 * 86400) : nil
            let snapshot = Self.snapshot(
                sessionUsed: 20, weeklyUsed: used, offset: Double(index) * 60, resetBoundary: boundary)
            await store.recordPlanUtilizationHistorySample(
                provider: .claude,
                snapshot: snapshot,
                now: snapshot.updatedAt)
        }
        #expect(notifier.limitResetPosts.count == 2)
    }

    @Test
    func `partial restored notice also covers the later confirmed reset`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.sessionQuotaNotificationsEnabled = true
        store.settings.limitResetNotificationsEnabled = true
        for (index, used) in [100.0, 50].enumerated() {
            let snapshot = Self.snapshot(sessionUsed: used, weeklyUsed: 20, offset: Double(index) * 60)
            let pending = store.handleSessionQuotaTransition(
                provider: .claude, snapshot: snapshot, now: snapshot.updatedAt)
            await store.recordPlanUtilizationHistorySample(
                provider: .claude,
                snapshot: snapshot,
                sessionRestoredNotificationPending: pending,
                now: snapshot.updatedAt)
        }
        await Self.record(store, sessionUsed: 0, weeklyUsed: 20, offset: 120)
        #expect(notifier.transitionPosts.map(\.transition) == [.depleted, .restored])
        #expect(notifier.limitResetPosts.isEmpty)
        await Self.record(store, sessionUsed: 60, weeklyUsed: 20, offset: 180)
        await Self.record(store, sessionUsed: 0, weeklyUsed: 20, offset: 240)
        #expect(notifier.limitResetPosts.count == 1)
    }

    @Test
    func `known reset boundaries remain deduplicated after a metadata gap`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true
        let boundary = Self.start.addingTimeInterval(7 * 86400)
        for (index, used) in [60.0, 0, 20, 30, 0, 20, 30, 0].enumerated() {
            let snapshot = Self.snapshot(
                sessionUsed: 20,
                weeklyUsed: used,
                offset: Double(index) * 60,
                resetBoundary: (2...4).contains(index) ? nil : boundary)
            await store.recordPlanUtilizationHistorySample(
                provider: .claude,
                snapshot: snapshot,
                now: snapshot.updatedAt)
        }
        #expect(notifier.limitResetPosts.count == 2)
    }

    @Test(arguments: [false, true])
    func `new depleted episodes still deliver restored notices without full resets`(withResetMetadata: Bool) async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.sessionQuotaNotificationsEnabled = true
        store.settings.limitResetNotificationsEnabled = true
        for (index, used) in [100.0, 50, 100, 50].enumerated() {
            let snapshot = Self.snapshot(
                sessionUsed: used,
                weeklyUsed: 20,
                offset: Double(index) * 60,
                resetBoundary: withResetMetadata ? Self.start.addingTimeInterval(5 * 60 * 60) : nil)
            let pending = store.handleSessionQuotaTransition(
                provider: .claude, snapshot: snapshot, now: snapshot.updatedAt)
            await store.recordPlanUtilizationHistorySample(
                provider: .claude,
                snapshot: snapshot,
                sessionRestoredNotificationPending: pending,
                now: snapshot.updatedAt)
        }
        #expect(notifier.transitionPosts.map(\.transition) == [.depleted, .restored, .depleted, .restored])
        #expect(notifier.limitResetPosts.isEmpty)
    }

    @Test
    func `advanced boundaries and independent windows notify separately`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true
        for (index, used) in [60.0, 0, 20, 30, 0].enumerated() {
            let boundary = Self.start.addingTimeInterval(Double(index < 4 ? 1 : 2) * 7 * 86400)
            let snapshot = Self.snapshot(
                sessionUsed: used, weeklyUsed: used, offset: Double(index) * 60, resetBoundary: boundary)
            await store.recordPlanUtilizationHistorySample(
                provider: .claude,
                snapshot: snapshot,
                now: snapshot.updatedAt)
        }
        #expect(notifier.limitResetPosts.map(\.window) == [.weekly, .session, .weekly])
    }

    @Test
    func `pending reset delivery rechecks opt in and personal info`() async throws {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true
        await Self.record(store, sessionUsed: 20, weeklyUsed: 60, offset: 0)
        await Self.record(store, sessionUsed: 20, weeklyUsed: 0, offset: 60)
        let isCurrent = try #require(notifier.deliveryChecks.first)
        #expect(isCurrent())
        store.settings.limitResetNotificationsEnabled = false
        #expect(!isCurrent())
        store.settings.limitResetNotificationsEnabled = true
        store.settings.hidePersonalInfo = true
        #expect(!isCurrent())
    }

    @Test
    func `a later restored confirmation does not repeat an announced reset`() async {
        let notifier = NotifierSpy()
        let defaults = InMemoryUserDefaults()
        var store = Self.makeStore(notifier: notifier, defaults: defaults)
        store.settings.limitResetNotificationsEnabled = true
        await Self.record(store, sessionUsed: 60, weeklyUsed: 20, offset: 0)
        await Self.record(store, sessionUsed: 0, weeklyUsed: 20, offset: 60)
        store = Self.makeStore(notifier: notifier, defaults: defaults)
        store.settings.sessionQuotaNotificationsEnabled = true
        let confirmed = Self.snapshot(sessionUsed: 0, weeklyUsed: 20, offset: 120)
        await store.recordPlanUtilizationHistorySample(
            provider: .claude, snapshot: confirmed, sessionRestoredNotificationPending: true, now: confirmed.updatedAt)
        #expect(notifier.limitResetPosts.count == 1)
        #expect(notifier.transitionPosts.isEmpty)
        await Self.record(store, sessionUsed: 60, weeklyUsed: 20, offset: 180)
        await Self.record(store, sessionUsed: 0, weeklyUsed: 20, offset: 240)
        #expect(notifier.limitResetPosts.count == 2)
    }

    @Test
    func `switching from a depleted account does not cover another accounts reset`() async {
        let notifier = NotifierSpy()
        let store = Self.makeStore(notifier: notifier)
        store.settings.sessionQuotaNotificationsEnabled = true
        store.settings.limitResetNotificationsEnabled = true
        let snapshots = [
            Self.snapshot(sessionUsed: 60, weeklyUsed: 20, offset: 0, email: "other@example.com"),
            Self.snapshot(sessionUsed: 100, weeklyUsed: 20, offset: 60),
            Self.snapshot(sessionUsed: 0, weeklyUsed: 20, offset: 120, email: "other@example.com"),
        ]
        for snapshot in snapshots {
            let pending = store.handleSessionQuotaTransition(
                provider: .claude, snapshot: snapshot, now: snapshot.updatedAt)
            await store.recordPlanUtilizationHistorySample(
                provider: .claude,
                snapshot: snapshot,
                sessionRestoredNotificationPending: pending,
                now: snapshot.updatedAt)
        }
        #expect(notifier.transitionPosts.allSatisfy { $0.transition != .restored })
        #expect(notifier.limitResetPosts == [
            LimitResetPost(provider: .claude, window: .session, accountDisplayName: "other@example.com"),
        ])
    }

    @Test
    func `delayed restored confirmation stays covered when usage has resumed`() {
        let store = Self.makeStore(notifier: NotifierSpy())
        store.settings.sessionQuotaNotificationsEnabled = true
        store.settings.limitResetNotificationsEnabled = true
        let previous = UsageStore.LimitResetDetectorState(
            wasAboveThreshold: false,
            lastObservedAt: Self.start,
            sourceRawValue: nil,
            notificationReceipt: UsageStore.LimitResetNotificationReceipt(resetBoundary: nil))
        var current = UsageStore.LimitResetDetectorState(
            wasAboveThreshold: true,
            lastObservedAt: Self.start.addingTimeInterval(60),
            sourceRawValue: nil,
            notificationReceipt: previous.notificationReceipt)
        let notice = store.prepareLimitResetNotification(
            state: &current,
            previousState: previous,
            observation: UsageStore.LimitResetObservation(
                usedPercent: 2,
                observedAt: current.lastObservedAt,
                resetBoundary: nil,
                source: nil),
            resetConfirmed: false,
            restored: true)
        #expect(notice == nil)
        var next = UsageStore.LimitResetDetectorState(
            wasAboveThreshold: false,
            lastObservedAt: Self.start.addingTimeInterval(120),
            sourceRawValue: nil,
            notificationReceipt: current.notificationReceipt)
        let nextNotice = store.prepareLimitResetNotification(
            state: &next,
            previousState: current,
            observation: UsageStore.LimitResetObservation(
                usedPercent: 0,
                observedAt: next.lastObservedAt,
                resetBoundary: nil,
                source: nil),
            resetConfirmed: true,
            restored: false)
        #expect(nextNotice != nil)
    }

    // MARK: - Helpers

    private static func makeSettings(defaults: UserDefaults) -> SettingsStore {
        testSettingsStore(suiteName: "LimitResetNotificationTests", userDefaults: defaults)
    }

    private static func makeStore(
        notifier: NotifierSpy,
        defaults: UserDefaults = InMemoryUserDefaults()) -> UsageStore
    {
        let suiteName = "LimitResetNotificationTests-\(UUID().uuidString)"
        let settings = Self.makeSettings(defaults: defaults)
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.sessionQuotaNotificationsEnabled = false
        settings.hidePersonalInfo = false
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            planUtilizationHistoryStore: testPlanUtilizationHistoryStore(suiteName: suiteName),
            sessionQuotaNotifier: notifier,
            startupBehavior: .testing)
        store._cancelPlanUtilizationHistoryLoadForTesting()
        store.planUtilizationHistory = [:]
        return store
    }

    private static func snapshot(
        sessionUsed: Double,
        weeklyUsed: Double,
        offset: TimeInterval,
        email: String = Self.accountEmail,
        resetBoundary: Date? = nil) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: sessionUsed,
                windowMinutes: 300,
                resetsAt: resetBoundary,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: weeklyUsed,
                windowMinutes: 10080,
                resetsAt: resetBoundary,
                resetDescription: nil),
            updatedAt: self.start.addingTimeInterval(offset),
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "max"))
    }

    private static func record(
        _ store: UsageStore,
        sessionUsed: Double,
        weeklyUsed: Double,
        offset: TimeInterval) async
    {
        let snapshot = self.snapshot(sessionUsed: sessionUsed, weeklyUsed: weeklyUsed, offset: offset)
        await store.recordPlanUtilizationHistorySample(provider: .claude, snapshot: snapshot, now: snapshot.updatedAt)
    }
}
