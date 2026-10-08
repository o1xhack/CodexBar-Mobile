#if DEBUG
import AppKit
import CodexBarCore
import SwiftUI

/// An isolated opt-in launcher for the complete production Usage & Spend pane.
/// It supplies fixed synthetic history and prevents normal account/provider startup.
@MainActor
enum ActivityDashboardRuntimeProof {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--activity-dashboard-proof")
            || Bundle.main.bundleIdentifier?.hasPrefix("org.codex.proof.activity.") == true else { return false }
        let environment = ProcessInfo.processInfo.environment
        guard SettingsStore.isRunningTests,
              environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] == "1",
              environment["CODEXBAR_TEST_CODEX_FILE_ISOLATION"] == "1",
              environment["CODEXBAR_TEST_SESSION_FILE_ISOLATION"] == "1",
              environment["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1",
              let directory = environment["CODEXBAR_ACTIVITY_RUNTIME_PROOF_DIR"]
        else { fatalError("Use the isolated runtime-proof launcher environment") }
        KeychainAccessGate.isDisabled = true
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = Delegate(output: URL(fileURLWithPath: directory, isDirectory: true))
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        return true
    }

    @MainActor
    private final class Delegate: NSObject, NSApplicationDelegate {
        let output: URL
        private var window: NSWindow?
        private var controller: SpendDashboardController?
        private var settings: SettingsStore?
        private var store: UsageStore?
        private var timer: Timer?

        init(output: URL) { self.output = output }

        func applicationDidFinishLaunching(_ notification: Notification) {
            do {
                try FileManager.default.createDirectory(at: self.output, withIntermediateDirectories: true)
                let settings = testSettingsStore(
                    suiteName: "ActivityDashboardRuntimeProof",
                    userDefaults: InMemoryUserDefaults(values: ["debugDisableKeychainAccess": true]),
                    config: testConfigWithAllProvidersDisabled())
                enableTestProviders([.cursor], settings: settings)
                settings.statusChecksEnabled = false
                settings.refreshFrequency = .manual
                settings.costUsageEnabled = true
                settings.hidePersonalInfo = true
                settings.preferredCurrencyCode = "USD"
                settings.costUsageBucketTimeZoneIdentifier = "UTC"
                let store = UsageStore(
                    fetcher: UsageFetcher(environment: [:]),
                    browserDetection: BrowserDetection(cacheTTL: 0),
                    settings: settings,
                    startupBehavior: .testing,
                    environmentBase: [:])
                store._test_providerRefreshOverride = { _ in
                    fatalError("The isolated proof must not start a provider transport")
                }
                store._test_widgetSnapshotSaveOverride = { _ in }
                let now = Date(timeIntervalSince1970: 1_791_288_000)
                let configuration = SpendDashboardSource.configuration(settings: settings, store: store)
                let inputs = Self.syntheticInputs(now: now, calendar: configuration.bucketCalendar)
                let controller = SpendDashboardController(
                    userDefaults: InMemoryUserDefaults(),
                    requestBuilder: { mode in
                        SpendDashboardLoadRequest(
                            configuration: configuration,
                            capturedInputs: inputs,
                            unavailableSourceIDs: [],
                            codexRequests: [],
                            now: now,
                            force: mode.forcesLoader)
                    },
                    loader: { request in
                        SpendDashboardLoadResult(inputs: request.capturedInputs, failedSourceIDs: [])
                    },
                    nowProvider: { now },
                    publicationHandler: { store.spendDashboardPublication = $0 })
                store.sharedSpendDashboardControllerStorage = controller
                controller.selectPeriod(.rolling(days: 7))
                controller.update(configuration: configuration)
                self.settings = settings
                self.store = store
                self.controller = controller
                self.showWindow(settings: settings, store: store)
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.recordState() }
                }
            } catch {
                fatalError("Could not initialize isolated dashboard proof: \(error)")
            }
        }

        private func showWindow(settings: SettingsStore, store: UsageStore) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 435, height: 820),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false)
            window.title = "CodexBar Usage & Spend — Synthetic proof"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: VStack(spacing: 0) {
                SpendDashboardPane(settings: settings, store: store)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("SYNTHETIC HISTORY · NO PERSONAL DATA")
                        .font(.caption.weight(.semibold))
                    HStack {
                        Button("Dark") { window.appearance = NSAppearance(named: .darkAqua) }
                        Button("Light") { window.appearance = NSAppearance(named: .aqua) }
                        Button("Narrow") { window.setContentSize(NSSize(width: 435, height: 820)) }
                        Button("Wide") { window.setContentSize(NSSize(width: 930, height: 820)) }
                        Button("Quit") { NSApplication.shared.terminate(nil) }
                    }.controlSize(.small)
                }.padding(10)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .defaultAppStorage(settings.userDefaults)
            .environment(\.locale, Locale(identifier: "en_US")))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.window = window
        }

        private func recordState() {
            guard let controller = self.controller, let window = self.window,
                  let view = window.contentView else { return }
            let scrolls = Self.scrollViews(in: view).map { scroll -> [String: Any] in
                let document = scroll.documentView?.frame ?? .zero
                let bounds = scroll.contentView.bounds
                return [
                    "contentWidth": document.width,
                    "viewportWidth": bounds.width,
                    "offsetX": bounds.minX,
                    "offsetY": bounds.minY,
                    "contentHeight": document.height,
                    "viewportHeight": bounds.height,
                ]
            }
            let record: [String: Any] = [
                "timestamp": Date().timeIntervalSince1970,
                "fixture": "synthetic-only",
                "host": "fresh packaged CodexBar executable, complete SpendDashboardPane",
                "keychainDisabled": KeychainAccessGate.isDisabled,
                "privacy": self.settings?.hidePersonalInfo ?? false,
                "refreshing": controller.isRefreshing,
                "groups": controller.model.groups.count,
                "activityDays": controller.model.tokenActivity.count,
                "coveredActivityDays": controller.model.tokenActivity.count { $0.totalTokens != nil },
                "selectedDay": controller.selectedDay.map {
                    Self.dayKey($0, calendar: self.settings!.costUsageBucketCalendar)
                } ?? "none",
                "activityMode": self.settings?.userDefaults.string(forKey: "spendActivityViewMode") ?? "daily",
                "windowContentWidth": view.bounds.width,
                "scrollViews": scrolls,
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                try data.write(to: self.output.appendingPathComponent("state.json"), options: .atomic)
                let history = self.output.appendingPathComponent("events.jsonl")
                if !FileManager.default.fileExists(atPath: history.path) {
                    FileManager.default.createFile(atPath: history.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: history)
                try handle.seekToEnd()
                try handle.write(contentsOf: data + Data([10]))
                try handle.close()
            } catch {
                fatalError("Could not record runtime state: \(error)")
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { self.scrollViews(in: $0) }
        }

        private static func dayKey(_ date: Date, calendar: Calendar) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }

        private static func syntheticInputs(now: Date, calendar: Calendar) -> [SpendDashboardModel.ProviderInput] {
            let today = calendar.startOfDay(for: now)
            let entries = (0..<365).map { (offset: Int) -> CostUsageDailyReport.Entry in
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                let tokens: Int = offset < 100 && offset % 3 != 0 ? (offset % 4 + 1) * 1_000_000 : 0
                return CostUsageDailyReport.Entry(
                    date: Self.dayKey(day, calendar: calendar),
                    inputTokens: tokens,
                    outputTokens: 0,
                    totalTokens: tokens,
                    costUSD: Double(tokens) / 1_000_000,
                    modelsUsed: ["example-model"],
                    modelBreakdowns: [.init(modelName: "example-model", costUSD: Double(tokens) / 1_000_000)])
            }
            return [SpendDashboardModel.ProviderInput(
                provider: .cursor,
                displayName: "Cursor (synthetic fixture)",
                snapshot: CostUsageTokenSnapshot(
                    sessionTokens: 0,
                    sessionCostUSD: 0,
                    last30DaysTokens: entries.compactMap(\.totalTokens).reduce(0, +),
                    last30DaysCostUSD: entries.compactMap(\.costUSD).reduce(0, +),
                    historyDays: 365,
                    historyCoverageIsEstablished: true,
                    daily: entries,
                    updatedAt: now))]
        }
    }
}
#endif
