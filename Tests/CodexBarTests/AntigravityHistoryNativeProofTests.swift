import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Opt-in production chart rendering from synthetic history; no app launch or visible window.
@MainActor
struct AntigravityHistoryNativeProofTests {
    @Test
    func `render quota observations`() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_ANTIGRAVITY_PROOF_PATH"] else { return }
        let store = UsageStorePlanUtilizationTests.makeStore()
        let now = Date()
        for (index, used) in [18.0, 37, 64, 82, 20].enumerated() {
            let capturedAt = now.addingTimeInterval(Double(index - 4) * 3600)
            let snapshot = UsageSnapshot(
                primary: .init(usedPercent: used, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: capturedAt)
            await store.recordPlanUtilizationHistorySample(provider: .antigravity, snapshot: snapshot, now: capturedAt)
        }
        let histories = store.planUtilizationHistory(for: .antigravity)
        let hosting = NSHostingView(rootView: PlanUtilizationHistoryChartMenuView(
            provider: .antigravity, histories: histories, width: 400)
            .frame(width: 400)
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
