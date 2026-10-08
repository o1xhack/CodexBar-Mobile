import AppKit
import CodexBarCore
import SwiftUI
import XCTest
@testable import CodexBar

@MainActor
final class SpendUILaneRenderTests: XCTestCase {
    func test_renderSyntheticBeforeAfter() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_LANE_PROOF_DIR"] else {
            throw XCTSkip("Local synthetic lane proof")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        let points = try (0..<365).map { offset in
            try SpendDashboardModel.TokenActivityPoint(
                day: XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now)),
                totalTokens: offset > 100 ? nil : offset % 3 == 0 ? 0 : (offset % 4 + 1) * 1_000_000,
                isScanned: offset <= 100)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let inputs = try ["account-a", "account-b"].enumerated().map { account, id in
            let daily = try (0..<90).map { offset in
                try CostUsageDailyReport.Entry(
                    date: formatter.string(from: XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now))),
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: 1000,
                    costUSD: Double((offset + account) % 7),
                    modelsUsed: nil,
                    modelBreakdowns: nil)
            }
            return SpendDashboardModel.ProviderInput(
                id: id,
                provider: .codex,
                displayName: "Demo account",
                snapshot: CostUsageTokenSnapshot(
                    sessionTokens: nil,
                    sessionCostUSD: nil,
                    last30DaysTokens: nil,
                    last30DaysCostUSD: nil,
                    historyDays: 90,
                    daily: daily,
                    updatedAt: now))
        }
        let group = try XCTUnwrap(SpendDashboardModel.build(
            inputs: inputs, requestedDays: 90, now: now, calendar: calendar).groups.first)
        try await CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for scheme in [ColorScheme.dark, .light] {
                let activity = AnyView(SpendActivityHeatmapView(points: points, now: now, calendar: calendar)
                    .defaultAppStorage(InMemoryUserDefaults()).padding(16).frame(width: 371))
                let spend = AnyView(SpendDashboardCurrencySection(group: group, requestedDays: 90)
                    .padding(20).frame(width: 760))
                for (name, content) in [("activity", activity), ("spend", spend)] {
                    let hosting = NSHostingView(rootView: content.environment(\.colorScheme, scheme)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
                    let window = NSWindow(
                        contentRect: hosting.frame,
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = hosting.appearance
                    window.contentView = hosting
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(150))
                    hosting.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: output.appendingPathComponent("\(name)-\(scheme).png"))
                    window.close()
                }
            }
        }
    }
}
