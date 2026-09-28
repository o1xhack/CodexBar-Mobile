import CloudKit
import CodexBarSync
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

private enum MobileTestLaunch {
    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

@main
struct CodexBarMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var usageData: SyncedUsageData

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        if arguments.contains("UI_TEST_RESET_DEFAULTS") {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: MobileSettingsKeys.usageCostChartStyle)
            defaults.removeObject(forKey: MobileSettingsKeys.dashboardCostChartStyle)
            defaults.removeObject(forKey: MobileSettingsKeys.hidePersonalInfo)
            defaults.removeObject(forKey: MobileSettingsKeys.openCostByDefault)
            defaults.removeObject(forKey: MobileSettingsKeys.usagePercentDisplayMode)
            defaults.removeObject(forKey: MobileSettingsKeys.showRemainingUsage)
            defaults.removeObject(forKey: "onboardingSeenVersion")
            defaults.removeObject(forKey: "releaseNotesSeenVersion")
        }

        if arguments.contains("UI_TEST_SKIP_ONBOARDING") {
            UserDefaults.standard.set(currentVersion, forKey: "releaseNotesSeenVersion")
        }

        if arguments.contains("UI_TEST_PREVIEW_DATA") || MobileTestLaunch.isUnitTestHost {
            _usageData = State(initialValue: PreviewData.makeSyncedUsageData())
        } else {
            _usageData = State(initialValue: SyncedUsageData())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(usageData: usageData)
                .onAppear {
                    guard !ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA"),
                          !MobileTestLaunch.isUnitTestHost else { return }
                    usageData.startObserving()
                }
        }
        // P2a: attach SwiftData container. Views do not yet use @Query;
        // this makes the mainContext available for P2b migration and ensures
        // the container is bootstrapped at launch for parallel-write.
        .modelContainer(ModelContainerFactory.shared())
    }
}

extension Notification.Name {
    /// Posted by AppDelegate when a silent CloudKit push arrives from the
    /// per-provider zone. `SyncedUsageData` listens and triggers its
    /// cache-based incremental refresh (Research/011 v2).
    static let codexBarProviderZoneDidChange = Notification.Name(
        "com.o1xhack.codexbar.providerZoneDidChange")
}

// MARK: - AppDelegate

/// `UIApplicationDelegate` responsibilities:
///
/// 1. Request notification permission on first launch.
/// 2. Register for remote notifications so CloudKit can dispatch subscriptions.
/// 3. Configure alert-push (quota transitions) + silent-push (DeviceProvidersZone)
///    subscriptions.
/// 4. Re-run all subscription setup on iCloud account change.
/// 5. Handle incoming silent pushes on DeviceProvidersZone — post a notification
///    so SyncedUsageData can refresh against its in-memory cache.
/// 6. Allow alert-push to display in foreground via
///    `UNUserNotificationCenterDelegate`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        let isTestLaunch = ProcessInfo.processInfo.arguments.contains("UI_TEST_RESET_DEFAULTS")
            || ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA")
            || MobileTestLaunch.isUnitTestHost
        guard !isTestLaunch else { return true }

        // 1. Request notification permission on first launch (Decision A — option 1).
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .sound, .badge])
                let msg = granted ? "✓ granted" : "✗ denied by user"
                print("[CodexBar Push v2] Notification permission \(msg)")
                PushSetupDiagnostic.shared.recordPermission(msg)
            } catch {
                let msg = "✗ request failed: \(error.localizedDescription)"
                print("[CodexBar Push v2] \(msg)")
                PushSetupDiagnostic.shared.recordPermission(msg)
            }
        }

        // 2. Register for remote notifications so CloudKit knows the APNs token.
        application.registerForRemoteNotifications()

        // 3. Set up alert-push subscriptions + silent-push subscription on
        //    DeviceProvidersZone.
        Task { @MainActor in
            await QuotaTransitionSubscriptions.shared.setupIfNeeded()
            await DeviceProviderZoneSubscription.shared.setupIfNeeded()
        }

        // 4. Re-setup on iCloud account change.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.iCloudAccountChanged),
            name: .CKAccountChanged,
            object: nil)

        return true
    }

    /// Handle silent CloudKit push. Today only the DeviceProvidersZone
    /// subscription fires here (quota subs render their alertBody without
    /// app code). On match, broadcast so SyncedUsageData can run its
    /// cache-based incremental refresh. We report `.newData` optimistically
    /// since the real work is async — iOS awards background time budget
    /// based on this signal.
    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard DeviceProviderZoneSubscription.isPushForThisSubscription(userInfo: userInfo) else {
            completionHandler(.noData)
            return
        }
        NotificationCenter.default.post(
            name: .codexBarProviderZoneDidChange, object: nil)
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let prefix = String(token.prefix(16))
        print("[CodexBar Push v2] Remote notification registration succeeded. Token: \(prefix)…")
        Task { @MainActor in
            PushSetupDiagnostic.shared.recordRegistration("✓ token: \(prefix)…")
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[CodexBar Push v2] Remote notification registration FAILED: " +
            "\(error.localizedDescription)")
        Task { @MainActor in
            PushSetupDiagnostic.shared.recordRegistration("✗ \(error.localizedDescription)")
        }
    }

    /// MUST be `nonisolated` — `CKAccountChanged` posts on
    /// `com.apple.cloudkit.CKProcessScopedStateManager.notificationQueue`,
    /// not the main queue. Without `nonisolated`, the implicit
    /// `@MainActor` isolation on `AppDelegate` (inherited from
    /// `UIApplicationDelegate` conformance under Swift 6 strict
    /// concurrency) causes `_swift_task_checkIsolatedSwift` to trap
    /// (`EXC_BREAKPOINT`) the moment the notification fires. Crash
    /// happens on every cold launch as soon as CloudKit's first
    /// account-state read posts the notification — was the cause of
    /// the App Store 1.5.2 (112) review rejection ("App crashed after
    /// initial launch"). The body still hops to `@MainActor` via
    /// `Task { @MainActor in ... }` so the actual subscription setup
    /// is properly main-isolated.
    @objc nonisolated private func iCloudAccountChanged() {
        print("[CodexBar Push v2] iCloud account changed — re-running subscription setup")
        Task { @MainActor in
            await QuotaTransitionSubscriptions.shared.setupIfNeeded()
            await DeviceProviderZoneSubscription.shared.setupIfNeeded()
        }
    }

    /// Allow alert push to display while the app is in the foreground. Without this,
    /// iOS silently suppresses the notification UI for the currently active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
