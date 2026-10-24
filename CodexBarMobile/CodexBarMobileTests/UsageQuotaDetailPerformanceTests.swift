import CodexBarSync
import SwiftUI
import UIKit
import XCTest
@testable import CodexBarMobile

/// Exercise the production detail with dense, explicitly fictitious provider history.
/// The render includes Charts and the accessibility value of the native history slider.
@MainActor
final class UsageQuotaDetailPerformanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDenseHistoryProjectionBaseline() {
        let accounts = self.accounts(pointsPerLine: 96)
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: accounts, now: self.now)
        let clock = ContinuousClock()
        let start = clock.now
        let overview = store.overview(accounts: accounts, now: self.now)
        print(
            "QUOTA_PERF projection=\(start.duration(to: clock.now)) lines=\(overview.lines.count) points=\(overview.lines.reduce(0) { $0 + $1.observedSamples.count })")
        XCTAssertEqual(overview.lines.count, 5)
        XCTAssertGreaterThanOrEqual(overview.lines.reduce(0) { $0 + $1.observedSamples.count }, 190)
    }

    func testDetailInitialLayoutWithDenseObservedHistory() {
        let accounts = self.accounts(pointsPerLine: 96)
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: accounts, now: self.now)
        let preferences = SummaryPreferencesStore.inMemory()
        let size = CGSize(width: 768, height: 951)
        let root = UsageQuotaDetailView(
            store: store, summaryPreferences: preferences, accounts: accounts,
            sourceSnapshots: [], isDemoMode: false, now: self.now)
            .environment(\.mobileAdaptiveLayout, MobileAdaptiveLayout(
                width: size.width, height: size.height, largeText: false))
            .frame(width: size.width, height: size.height)
        let clock = ContinuousClock()
        let start = clock.now
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let elapsed = start.duration(to: clock.now)
        print("QUOTA_PERF detail_initial_layout=\(elapsed) fixture_points_per_provider=96 width=768")
        XCTAssertLessThan(elapsed, .seconds(1), "Initial detail layout must not block the main thread for a second")
    }

    private func accounts(pointsPerLine: Int) -> [ProviderUsageSnapshot] {
        ["claude", "codex", "cursor", "gemini", "grok"].enumerated().map { index, providerID in
            let reset = self.now.addingTimeInterval(2 * 86400)
            let entries = (0..<pointsPerLine).map { sample in
                SyncUtilizationEntry(
                    capturedAt: self.now.addingTimeInterval(Double(sample - pointsPerLine) * 1800),
                    usedPercent: 10 + 40 * Double(sample) / Double(pointsPerLine), resetsAt: reset)
            }
            let weekly = SyncRateWindow(
                id: "secondary", label: "Weekly", usedPercent: 50, windowMinutes: 10080,
                period: .weekly, resetsAt: reset, resetDescription: nil)
            return ProviderUsageSnapshot(
                providerID: providerID, providerName: providerID.capitalized, primary: nil, secondary: nil,
                accountEmail: "fictional-performance-\(index)@example.invalid", loginMethod: nil,
                statusMessage: nil, isError: false, lastUpdated: self.now, rateWindows: [weekly],
                utilizationHistory: [SyncUtilizationSeries(name: "weekly", windowMinutes: 10080, entries: entries)],
                accountIdentities: ["\(providerID):account:fictional-performance-\(index)"],
                accountRecordKey: "fictional-performance-\(index)")
        }
    }
}
