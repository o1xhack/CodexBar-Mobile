import Foundation
import UIKit
import XCTest

/// Explicit, manual, physical-device QA only. Never enables demo data or resets defaults.
/// Pass TEST_RUNNER_CODEXBAR_RUN_LIVE_QUOTA_PERFORMANCE=1 to xcodebuild and select only
/// LiveQuotaPerformanceUITests/testLiveQuotaInteractions. The runner receives the key
/// without TEST_RUNNER_. Screenshots contain live account data: keep the xcresult private.
final class LiveQuotaPerformanceUITests: XCTestCase {
    override func setUpWithError() throws { self.continueAfterFailure = false }

    @MainActor func testLiveQuotaInteractions() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live quota QA is never run against simulator fixtures")
        #else
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CODEXBAR_RUN_LIVE_QUOTA_PERFORMANCE"] == "1",
            "Requires explicit manual physical-device opt-in")
        let app = XCUIApplication()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        let bottomSummary = app.tabBars.buttons.matching(NSPredicate(
            format: "label IN %@", ["Summary", "摘要", "概要"])).firstMatch
        let summary = bottomSummary.exists ? bottomSummary : app.nativeTab("Summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 10) && summary.isHittable)
        summary.tap()
        // A previously open detail may be restored by the production app. Only leave
        // this known screen; do not dismiss unknown sheets or alter saved settings.
        if app.scrollViews["quota-detail-scroll"].exists {
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.exists && back.isHittable)
            back.tap()
        }
        let grid = app.scrollViews["summary-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        let entry = app.buttons["summary-quota-open-detail"]
        self.reveal(entry, in: grid, app: app)
        self.capture("Live Air Summary before opening quota")
        let detail = app.scrollViews["quota-detail-scroll"]
        self.timed("open quota detail", action: { entry.tap() }) {
            detail.exists && app.buttons["quota-detail-edit"].isHittable
        }
        self.capture("Live Air quota detail initial")

        let focus = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "quota-detail-line-")).firstMatch
        self.reveal(focus, in: detail, app: app)
        let originalLineIDs = self.lineIDs(app)
        XCTAssertFalse(originalLineIDs.isEmpty)
        self.timed("focus line", action: { focus.tap() }) { focus.isSelected }
        let all = app.buttons["quota-detail-show-all"]
        self.reveal(all, in: detail, app: app)
        self.timed("show all lines", action: { all.tap() }) { all.isSelected }
        let scrubber = app.sliders["quota-detail-scrubber"]
        self.reveal(scrubber, in: detail, app: app)
        // Establish a distinct inspection time without changing saved line choices.
        scrubber.adjust(toNormalizedSliderPosition: 0)
        let before = try XCTUnwrap(scrubber.value as? String)
        self.timed("inspect recorded history", action: {
            scrubber.adjust(toNormalizedSliderPosition: 0.25)
        }) { (scrubber.value as? String) != before }
        self.capture("Live Air selected actual history")

        let chart = app.descendants(matching: .any)["quota-detail-chart-container"].firstMatch
        self.reveal(chart, in: detail, app: app)
        let selected = try XCTUnwrap(scrubber.value as? String)
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        self.measure(
            metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTCPUMetric(application: app)],
            options: options)
        {
            self.reveal(chart, in: detail, app: app)
            let chartY = chart.frame.minY
            self.startMeasuring()
            self.timed("vertical scroll starting inside chart", action: {
                chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(
                    forDuration: 0.05,
                    thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0)
            }) { chart.frame.minY < chartY - 12 }
            self.stopMeasuring()
        }
        XCTAssertEqual(scrubber.value as? String, selected, "Vertical scrolling must not inspect another time")
        self.capture("Live Air chart scroll response")

        let edit = app.buttons["quota-detail-edit"]
        let done = app.buttons["quota-editor-done"]
        self.timed("open quota settings", action: { edit.tap() }) { done.exists && done.isHittable }
        self.capture("Live Air quota editor read only visit")
        // Done only dismisses. Do not tap any row, color, picker, reorder or remove control.
        self.timed("dismiss quota settings without changes", action: { done.tap() }) {
            !done.exists && detail.exists
        }
        XCTAssertEqual(self.lineIDs(app), originalLineIDs, "The live selected lines must remain unchanged")
        self.capture("Live Air quota detail after unchanged settings")
        #endif
    }

    @MainActor private func timed(
        _ name: String, action: () -> Void, until condition: () -> Bool)
    {
        let start = ProcessInfo.processInfo.systemUptime
        action()
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let attachment = XCTAttachment(string:
            "\(name): \(elapsed) seconds. Includes XCTest actions, transport and idle waits; not touch-to-frame latency.")
        attachment.name = "Live end-to-end response — " + name
        attachment.lifetime = .keepAlways
        self.add(attachment)
        XCTAssertTrue(condition(), "\(name) did not reach its expected state")
        XCTAssertLessThan(elapsed, 15, "\(name) exceeded the bounded end-to-end response budget")
    }

    @MainActor private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            var visible = scroll.frame.intersection(app.windows.firstMatch.frame)
            if app.navigationBars.firstMatch.exists {
                let top = app.navigationBars.firstMatch.frame.maxY
                visible = visible.intersection(CGRect(
                    x: visible.minX,
                    y: top,
                    width: visible.width,
                    height: max(0, visible.maxY - top)))
            }
            if app.tabBars.firstMatch.exists {
                visible.size.height = max(0, min(visible.maxY, app.tabBars.firstMatch.frame.minY) - visible.minY)
            }
            visible = visible.insetBy(dx: 8, dy: 8)
            if element.exists, visible.contains(element.frame), element.isHittable { return }
            XCTAssertGreaterThan(visible.height, 80)
            let upward = !element.exists || element.frame.midY > visible.midY
            let distance = visible.height * 0.35
            let window = app.windows.firstMatch
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(
                dx: visible.midX - window.frame.minX,
                dy: visible.midY - window.frame.minY + (upward ? distance / 2 : -distance / 2)))
            let end = origin.withOffset(CGVector(
                dx: visible.midX - window.frame.minX,
                dy: visible.midY - window.frame.minY + (upward ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        self.capture("Live quota element not reachable")
        XCTFail("Expected existing live UI element is not reachable; no settings were modified")
    }

    @MainActor private func lineIDs(_ app: XCUIApplication) -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-detail-line-"))
            .allElementsBoundByIndex.map(\.identifier).sorted()
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
