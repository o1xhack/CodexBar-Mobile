import UIKit
import XCTest

/// Run the current-pose case again after selecting each real Duo display/pose and system appearance.
/// Hosting-size render tests complement these captures; they do not establish actual Duo geometry.
final class UsageQuotaOverviewUITests: XCTestCase {
    override func setUpWithError() throws { self.continueAfterFailure = false }

    @MainActor private func launch(
        hidden: Bool = false,
        largeText: Bool = false,
        addModule: Bool = true,
        language: String = "en",
        contentSize: String? = nil) -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_PREVIEW_DATA", "UI_TEST_MULTI_ACCOUNT_DATA", "UI_TEST_SKIP_ONBOARDING", "UI_TEST_RESET_DEFAULTS",
            "-cwlEnabled", "NO", "-openCostByDefault", "NO",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ja" ? "ja_JP" : "en_US",
            "-hidePersonalInfo", hidden ? "YES" : "NO", "-showRemainingUsage", "NO",
        ]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        } else if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let usage = SummaryQuotaUITestFlow.tab(app, name: "Usage")
        XCTAssertTrue(usage.waitForExistence(timeout: 10))
        usage.tap()
        XCTAssertTrue(app.scrollViews["usage-provider-list"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["usage-quota-chart"].exists,
            "Usage must show provider usage without the optional Summary module")
        if addModule {
            SummaryQuotaUITestFlow.tab(app, name: "Summary").tap()
            XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["summary-quota-module"].exists)
            SummaryQuotaUITestFlow.addModule(app)
            SummaryQuotaUITestFlow.moveModuleToFirst(app)
            self.reveal(app.buttons["usage-quota-edit"], in: app)
        }
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var visible = false
        // The catalog/account pages are pushed inside the editor and do not keep
        // its root Done button. Detect their actual Form instead of falling back
        // to the Summary grid underneath the presented navigation stack.
        if app.collectionViews.containing(self.quotaEditorRowControl).firstMatch.exists {
            for _ in 0..<10 where !(element.exists && element.isHittable) {
                self.scrollEditorForm(app, upward: true)
            }
            visible = element.exists && element.isHittable
        } else {
            visible = self.revealSummaryElement(element, in: app)
        }
        if !visible {
            self.attachHierarchy(app, name: "Element still obscured after bounded scrolling")
            self.capture("Element still obscured after bounded scrolling")
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(visible, "The requested content must be reachable inside the unobscured scroll viewport")
    }

    @MainActor private func revealSummaryElement(
        _ element: XCUIElement, in app: XCUIApplication, hittableControl: XCUIElement? = nil) -> Bool
    {
        let detailOpen = app.scrollViews["quota-detail-scroll"].exists
        let id = detailOpen ? "quota-detail-scroll" : "summary-grid"
        let scroller = app.scrollViews[id]
        XCTAssertTrue(scroller.waitForExistence(timeout: 5))
        let window = app.windows.containing(.scrollView, identifier: id).firstMatch
        XCTAssertTrue(window.exists)
        for _ in 0..<12 {
            let visible = self.unobscuredViewport(app, scroller: scroller, window: window).insetBy(dx: 4, dy: 4)
            if visible.isNull || visible.width <= 100 || visible.height <= 80 {
                self.attachHierarchy(app, name: "Summary scroll viewport geometry failure")
                self.capture("Summary scroll viewport geometry failure with complete native app")
                self.attachViewportGeometry(app, scroller: scroller, window: window, visible: visible)
            }
            XCTAssertGreaterThan(visible.width, 100)
            XCTAssertGreaterThan(visible.height, 80)
            let frame = element.exists ? element.frame : CGRect.null
            if !frame.isNull, frame.minY >= visible.minY - 0.5, frame.maxY <= visible.maxY + 0.5,
               (hittableControl ?? element).isHittable
            {
                return true
            }
            // Summary's production Layout and quota detail retain their own scroll
            // positions. Drag only within the currently visible surface.
            let upward = frame.isNull || frame.midY > visible.midY
            // The complete module nearly fills a short landscape viewport. Center
            // its measured frame instead of repeatedly overshooting with a fixed drag.
            // Native pans consume about 10pt before content moves: the observed 9.6pt
            // residual never scrolled. Include that recognition distance in the gesture,
            // then measure the resulting frame again; the visibility check stays exact.
            let remainingDistance = frame.isNull ? visible.height * 0.28 : abs(frame.midY - visible.midY)
            // Accessibility history can span several screens before current quotas.
            // Travel farther only while the measured destination is still far away.
            let maximumDistance = detailOpen ? visible.height * 0.45 : 72
            let distance = min(maximumDistance, max(16, remainingDistance + 12))
            let startY = visible.midY + (upward ? distance / 2 : -distance / 2)
            let origin = scroller.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(
                dx: visible.midX - scroller.frame.minX, dy: startY - scroller.frame.minY))
            let end = origin.withOffset(CGVector(
                dx: visible.midX - scroller.frame.minX,
                dy: startY + (upward ? -distance : distance) - scroller.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return false
    }

    @MainActor private func unobscuredViewport(
        _ app: XCUIApplication, scroller: XCUIElement, window: XCUIElement) -> CGRect
    {
        let bounds = window.frame.intersection(scroller.frame)
        var visible = bounds
        let chrome = app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
            + app.searchFields.allElementsBoundByIndex.filter(\.isHittable)
        let tabBounds = ["Usage", "Summary", "Cost", "Setting"].map { SummaryQuotaUITestFlow.tab(app, name: $0) }
            .filter { $0.exists && $0.isHittable }.reduce(CGRect.null) { $0.union($1.frame) }
        let obstructions = chrome.filter(\.exists).map(\.frame) + [tabBounds]
        for frame in obstructions where !frame.isNull && frame.intersects(visible) {
            if frame.width > frame.height {
                if frame.midY < bounds.midY {
                    let bottom = visible.maxY
                    visible.origin.y = max(visible.minY, frame.maxY)
                    visible.size.height = max(0, bottom - visible.minY)
                } else {
                    visible.size.height = max(0, min(visible.maxY, frame.minY) - visible.minY)
                }
            } else if frame.midX < bounds.midX {
                let right = visible.maxX
                visible.origin.x = max(visible.minX, frame.maxX)
                visible.size.width = max(0, right - visible.minX)
            } else {
                visible.size.width = max(0, min(visible.maxX, frame.minX) - visible.minX)
            }
        }
        return visible
    }

    @MainActor private func attachViewportGeometry(
        _ app: XCUIApplication, scroller: XCUIElement, window: XCUIElement, visible: CGRect)
    {
        let tabs = ["Usage", "Summary", "Cost", "Setting"].map { SummaryQuotaUITestFlow.tab(app, name: $0) }
        let elements = app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
            + app.searchFields.allElementsBoundByIndex + tabs
        let descriptions = elements.filter(\.exists).map {
            "\($0.elementType) id=\($0.identifier) label=\($0.label) frame=\($0.frame) hittable=\($0.isHittable)"
        }
        let attachment = XCTAttachment(string:
            "Window: \(window.frame)\nScroll \(scroller.identifier): \(scroller.frame)\n"
                + "Computed viewport: \(visible)\n" + descriptions.joined(separator: "\n"))
        attachment.name = "Summary viewport and actual native control frames"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    @MainActor private func top(_ app: XCUIApplication) {
        if app.buttons["quota-editor-done"].exists {
            let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-5] / 5")).firstMatch
            for _ in 0..<10 where !(count.exists && count.isHittable) {
                XCTAssertTrue(
                    app.buttons["quota-editor-done"].exists,
                    "Scrolling the Form must keep the native editor sheet open")
                self.scrollEditorForm(app, upward: false)
            }
            XCTAssertTrue(count.exists && count.isHittable)
        } else {
            self.reveal(app.buttons["usage-quota-edit"], in: app)
        }
    }

    private var quotaEditorRowControl: NSPredicate {
        NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
            "quota-line-actions-",
            "quota-catalog-",
            "quota-candidate-")
    }

    @MainActor private func scrollEditorForm(_ app: XCUIApplication, upward: Bool) {
        let rowControl = self.quotaEditorRowControl
        let forms = app.collectionViews.containing(rowControl)
        let form = forms.allElementsBoundByIndex.first { candidate in
            candidate.buttons.matching(rowControl).allElementsBoundByIndex.contains { $0.isHittable }
        } ?? forms.firstMatch
        let visible = form.frame.intersection(app.windows.firstMatch.frame)
        let reachableRow = form.buttons.matching(rowControl).allElementsBoundByIndex.contains {
            $0.isHittable && $0.frame.intersects(visible)
        }
        if !form.exists || visible.isNull || visible.width <= 100 || visible.height <= 100 || !reachableRow {
            self.attachHierarchy(app, name: "Quota editor scroll lacks visible Form or hittable row")
            self.capture("Quota editor scroll before geometry and row assertions")
            let attachment =
                XCTAttachment(
                    string: "Selected Form:\n\(form.debugDescription)\nCollection views:\n"
                        + app.collectionViews.debugDescription)
            attachment.name = "Quota editor selected Form and candidate geometry"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        XCTAssertTrue(form.exists, "Scroll the native Form containing quota row controls")
        XCTAssertFalse(visible.isNull)
        XCTAssertGreaterThan(visible.width, 100)
        XCTAssertGreaterThan(visible.height, 100)
        XCTAssertTrue(reachableRow, "A real row control inside the visible editor must remain hittable")
        // Duo's visible Form reports isHittable=false while its row buttons are hittable.
        // Drag inside the observed Form/window intersection, below the sheet's navigation bar,
        // rather than asking XCTest for a hit point on the non-interactive container itself.
        let origin = form.coordinate(withNormalizedOffset: .zero)
        let x = visible.midX - form.frame.minX
        let upperY = visible.minY + visible.height * 0.30 - form.frame.minY
        let lowerY = visible.minY + visible.height * 0.78 - form.frame.minY
        let upper = origin.withOffset(CGVector(dx: x, dy: upperY))
        let lower = origin.withOffset(CGVector(dx: x, dy: lowerY))
        (upward ? lower : upper).press(forDuration: 0.05, thenDragTo: upward ? upper : lower)
    }

    @MainActor private func currentQuotaRows(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-detail-current-"))
            .allElementsBoundByIndex
    }

    @MainActor private func assertQuotaClearsNativeChrome(_ app: XCUIApplication) {
        let module = app.descendants(matching: .any)["summary-quota-module"].firstMatch
        let chart = app.descendants(matching: .any)["usage-quota-chart"].firstMatch
        let legend = app.descendants(matching: .any)["usage-quota-legend-toggle"].firstMatch
        let window = app.windows.containing(.any, identifier: "usage-quota-chart").firstMatch
        let scroller = app.scrollViews["summary-grid"]
        XCTAssertTrue(module.exists && chart.exists && legend.exists && window.exists && scroller.exists)
        // A hittable chart can still leave its title clipped. Check the complete
        // module as well as its plot and legend against the real viewport and bars.
        let viewport = window.frame.intersection(scroller.frame)
        let tabs = ["Usage", "Summary", "Cost", "Setting"].map { SummaryQuotaUITestFlow.tab(app, name: $0) }
        let chrome = app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
            + app.searchFields.allElementsBoundByIndex.filter(\.isHittable) + tabs
        var problems: [String] = []
        if viewport.isNull || viewport.width <= 0 || viewport.height <= 0 {
            problems.append("Quota viewport is empty: \(viewport)")
        }
        for tab in tabs where !tab.exists || !tab.isHittable {
            problems.append("Native tab must remain reachable: \(tab)")
        }
        for element in [module, chart, legend] {
            let frame = element.frame
            if !viewport.insetBy(dx: -1, dy: -1).contains(frame) {
                problems.append("\(element.identifier) \(frame) escapes visible viewport \(viewport)")
            }
            for obstruction in chrome where obstruction.exists && !obstruction.frame.isEmpty {
                if frame.insetBy(dx: 1, dy: 1).intersects(obstruction.frame.insetBy(dx: 1, dy: 1)) {
                    problems.append("\(element.identifier) overlaps \(obstruction.elementType) "
                        + "\(obstruction.label) at \(obstruction.frame)")
                }
            }
        }
        if !app.buttons["summary-quota-open-detail"].isHittable {
            problems.append("The module must expose a reachable detail entry separate from its gear")
        }
        if !problems.isEmpty {
            self.attachHierarchy(app, name: "Quota native chrome overlap")
            self.capture("Quota visibility failure with complete native app")
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    @MainActor private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let predicate = NSPredicate { _, _ in
            landscape ? app.frame.width > app.frame.height : app.frame.height > app.frame.width
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 8),
            .completed)
    }

    @MainActor private func showQuotaBody(_ app: XCUIApplication) {
        let module = app.descendants(matching: .any)["summary-quota-module"].firstMatch
        let visible = self.revealSummaryElement(
            module, in: app, hittableControl: app.buttons["summary-quota-open-detail"])
        if !visible {
            self.attachHierarchy(app, name: "Complete Summary module is not reachable")
            self.capture("Complete Summary module visibility failure")
        }
        XCTAssertTrue(visible, "The entire module, including its title, must be reachable between native bars")
        self.assertQuotaClearsNativeChrome(app)
    }

    @MainActor private func openQuotaDetail(_ app: XCUIApplication) {
        let entry = app.buttons["summary-quota-open-detail"]
        let chart = app.descendants(matching: .any)["usage-quota-chart"].firstMatch
        self.reveal(chart, in: app)
        XCTAssertTrue(entry.exists && entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.scrollViews["quota-detail-scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quota-detail-chart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["quota-detail-chart-container"].exists)
        XCTAssertFalse(app.buttons["quota-editor-done"].exists, "The module body opens details, not the line editor")
    }

    @MainActor private func closeQuotaDetail(_ app: XCUIApplication) {
        self.back(app, title: app.launchArguments.contains("(ja)") ? "概要" : "Summary")
        XCTAssertTrue(app.scrollViews["quota-detail-scroll"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))
    }

    @MainActor private func assertDetailElementClearsChrome(_ element: XCUIElement, in app: XCUIApplication) {
        self.reveal(element, in: app)
        let scroller = app.scrollViews["quota-detail-scroll"]
        let window = app.windows.containing(.scrollView, identifier: "quota-detail-scroll").firstMatch
        let viewport = self.unobscuredViewport(app, scroller: scroller, window: window)
        let fits = viewport.insetBy(dx: -1, dy: -1).contains(element.frame)
        if !fits {
            self.attachHierarchy(app, name: "Quota detail native chrome overlap")
            self.capture("Quota detail visibility failure with complete native app")
            self.attachViewportGeometry(app, scroller: scroller, window: window, visible: viewport)
        }
        XCTAssertTrue(
            fits,
            "\(element.identifier) must fit inside the actual viewport: \(element.frame) vs \(viewport)")
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func assertDetailContentReachable(_ app: XCUIApplication) {
        let chart = app.descendants(matching: .any)["quota-detail-chart-container"].firstMatch
        self.assertDetailElementClearsChrome(chart, in: app)
        XCTAssertGreaterThan(chart.frame.width, 140)
        XCTAssertGreaterThanOrEqual(chart.frame.height, 179.5)
        self.capture("Quota detail chart with complete native app in current display pose")
        let all = app.buttons["quota-detail-show-all"]
        self.assertDetailElementClearsChrome(all, in: app)
        let scrubber = app.sliders["quota-detail-scrubber"]
        self.assertDetailElementClearsChrome(scrubber, in: app)
        let rows = self.currentQuotaRows(app)
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            self.assertDetailElementClearsChrome(row, in: app)
            XCTAssertGreaterThanOrEqual(row.frame.height, 43.5)
        }
        let notice = app.descendants(matching: .any)["quota-detail-history-notice"].firstMatch
        self.assertDetailElementClearsChrome(notice, in: app)
        self.capture("Quota detail current accounts and complete history notice at the bottom")
    }

    @MainActor private func addNonDefaultCodexWeeklyInEditor(_ app: XCUIApplication) {
        // Exercise a second account of the same provider, not merely a provider-level
        // destination whose default account could accidentally make the test pass.
        self.actions(app).firstMatch.tap()
        app.buttons["Remove"].tap()
        let add = app.buttons["quota-editor-add"]
        self.reveal(add, in: app)
        add.tap()
        let weekly = app.buttons["quota-catalog-codex-secondary"]
        self.reveal(weekly, in: app)
        weekly.tap()
        let account = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "quota-candidate-", "work@example.com"))
            .firstMatch
        self.reveal(account, in: app)
        XCTAssertTrue(account.isEnabled)
        account.tap()
        XCTAssertTrue(app.staticTexts["5 / 5"].waitForExistence(timeout: 5))
    }

    @MainActor func testQuotaDetailScrubbingFocusAndNonDefaultAccountNavigation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = self.launch()
        app.buttons["usage-quota-edit"].tap()
        XCTAssertTrue(app.buttons["quota-editor-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["quota-detail-scroll"].exists, "The gear must only open quota configuration")
        self.addNonDefaultCodexWeeklyInEditor(app)
        app.buttons["quota-editor-done"].tap()
        self.openQuotaDetail(app)

        let originalValues = self.currentValues(app)
        let period = app.staticTexts["quota-detail-period"].label
        let all = app.buttons["quota-detail-show-all"]
        let lines = self.lineButtons(app)
        XCTAssertEqual(lines.count, 5)
        let first = lines[0]
        self.reveal(first, in: app)
        XCTAssertTrue(all.isSelected)
        first.tap()
        self.waitFor { first.isSelected && !all.isSelected }
        XCTAssertEqual(self.lineButtons(app).filter(\.isSelected).count, 1)
        XCTAssertEqual(
            app.staticTexts["quota-detail-period"].label,
            period,
            "Focusing a line must not change the date domain")
        first.tap()
        self.waitFor { all.isSelected }
        XCTAssertTrue(self.lineButtons(app).allSatisfy { !$0.isSelected })
        first.tap()
        all.tap()
        self.waitFor { all.isSelected }
        first.tap()

        let scrubber = app.sliders["quota-detail-scrubber"]
        self.reveal(scrubber, in: app)
        scrubber.adjust(toNormalizedSliderPosition: 0)
        let earliest = self.historyReadout(app)
        XCTAssertFalse(earliest.isEmpty)
        scrubber.adjust(toNormalizedSliderPosition: 1)
        self.waitFor { self.historyReadout(app) != earliest }
        XCTAssertTrue(
            self.historyReadout(app).contains("No observation at this time"),
            "The future end of the shared date axis must not reuse a past reading")
        XCTAssertEqual(self.currentValues(app), originalValues, "Scrubbing history must not rewrite current quotas")
        self.capture("Quota detail focused history at an unobserved time with current values unchanged")

        // Charts also exposes enlarged virtual accessibility regions. Its .contain
        // wrapper measures the actual rendered bounds; these interior coordinates
        // stay inside the real plot and exercise its gesture, not only the Slider.
        let chart = app.descendants(matching: .any)["quota-detail-chart-container"].firstMatch
        self.reveal(chart, in: app)
        let previousTime = try XCTUnwrap(scrubber.value as? String)
        XCTAssertFalse(previousTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.2)
        self.waitFor { scrubber.value as? String != previousTime }
        XCTAssertEqual(self.currentValues(app), originalValues)
        XCTAssertEqual(app.staticTexts["quota-detail-period"].label, period)
        let selectedTime = try XCTUnwrap(scrubber.value as? String)
        XCTAssertFalse(selectedTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let work = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "quota-detail-current-", "work@example.com"))
            .firstMatch
        self.assertDetailElementClearsChrome(work, in: app)
        XCTAssertEqual(work.value as? String, "39%")
        let selectionID = String(work.identifier.dropFirst("quota-detail-current-".count))
        work.tap()
        let account = app.descendants(matching: .any)["quota-detail-account-" + selectionID].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        self.waitForAccountNavigationToSettle(account, in: app)
        self.capture("Quota detail opens the selected non-default Codex account")
        for (index, expected) in [(0, "42%"), (1, "61%")] {
            // UsageCardView applies its identifier to a percentage HStack, so the
            // numeric text and its separate "used" suffix inherit the same ID.
            // Scope to this pushed account and require one actual percentage.
            let percentages = account.staticTexts.matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "provider-detail-percent-codex-\(index)",
                "%"))
            XCTAssertTrue(percentages.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(percentages.count, 1, "Each selected-account window must expose exactly one percentage")
            let label = percentages.firstMatch.label
            XCTAssertTrue(
                label == expected || label.hasPrefix(expected + " "),
                "The selected work account must show Session 42% and Weekly 61%; got \(label)")
        }
        self.back(app, title: "Remaining Quota")
        XCTAssertTrue(app.scrollViews["quota-detail-scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(first.isSelected, "Account drill-down and back must preserve the focused quota line")
        XCTAssertEqual(scrubber.value as? String, selectedTime)
        XCTAssertEqual(self.currentValues(app), originalValues)
        app.buttons["quota-detail-edit"].tap()
        XCTAssertTrue(app.buttons["quota-editor-done"].waitForExistence(timeout: 5))
        app.buttons["quota-editor-done"].tap()
        XCTAssertTrue(app.buttons["quota-editor-done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["quota-detail-scroll"].exists && first.isSelected)
        self.closeQuotaDetail(app)
        XCTAssertFalse(app.buttons["quota-editor-done"].exists)
    }

    @MainActor func testPhoneQuotaDetailSurvivesRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = self.launch()
        self.waitForOrientation(app, landscape: false)
        XCTAssertLessThan(app.frame.width, 600, "Run this transition regression on an ordinary iPhone")
        self.openQuotaDetail(app)
        let chart = app.descendants(matching: .any)["quota-detail-chart-container"].firstMatch
        self.assertDetailElementClearsChrome(chart, in: app)
        self.capture("Phone quota detail portrait with native navigation and tabs")
        let first = self.lineButtons(app)[0]
        self.reveal(first, in: app)
        first.tap()
        let scrubber = app.sliders["quota-detail-scrubber"]
        self.reveal(scrubber, in: app)
        scrubber.adjust(toNormalizedSliderPosition: 0.2)
        let selectedTime = try XCTUnwrap(scrubber.value as? String)
        XCTAssertFalse(selectedTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let values = self.currentValues(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForOrientation(app, landscape: true)
        XCTAssertTrue(app.scrollViews["quota-detail-scroll"].exists)
        XCTAssertTrue(first.isSelected)
        XCTAssertEqual(scrubber.value as? String, selectedTime)
        self.assertVerticalChartDragScrollsPage(app)
        self.assertDetailContentReachable(app)
        XCTAssertEqual(self.currentValues(app), values)
        XCUIDevice.shared.orientation = .portrait
        self.waitForOrientation(app, landscape: false)
        XCTAssertTrue(first.isSelected)
        XCTAssertEqual(scrubber.value as? String, selectedTime)
        let last = try XCTUnwrap(self.currentQuotaRows(app).last)
        self.assertDetailElementClearsChrome(last, in: app)
        self.capture("Phone quota detail portrait restored with focus and history time intact")
        self.closeQuotaDetail(app)
    }

    @MainActor func testPhoneSummaryModuleSurvivesRotationAndTabChanges() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = self.launch()
        self.waitForOrientation(app, landscape: false)
        XCTAssertLessThan(app.frame.width, 600, "Run this regression on an ordinary compact iPhone")
        self.showQuotaBody(app)
        self.capture("Phone Summary quota module portrait with complete native app")
        // The entry exposes the same privacy-safe selection summary as its static
        // legend, even when native Button accessibility combines the child labels.
        let entry = app.buttons["summary-quota-open-detail"]
        let selectedLines = try XCTUnwrap(entry.value as? String)
        XCTAssertFalse(selectedLines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForOrientation(app, landscape: true)
        self.showQuotaBody(app)
        self.capture("Phone Summary quota module landscape with complete native app")
        self.openQuotaDetail(app)
        let rows = self.currentQuotaRows(app)
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            self.reveal(row, in: app)
        }
        self.capture("Phone Summary landscape quota detail last row reachable")
        self.closeQuotaDetail(app)

        SummaryQuotaUITestFlow.tab(app, name: "Usage").tap()
        XCTAssertTrue(app.scrollViews["usage-provider-list"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["usage-quota-chart"].exists)
        self.capture("Phone Usage landscape provider cards without quota module")
        SummaryQuotaUITestFlow.tab(app, name: "Summary").tap()
        self.showQuotaBody(app)
        XCTAssertEqual(entry.value as? String, selectedLines)
        XCTAssertTrue(self.currentQuotaRows(app).isEmpty, "Returning from details must restore the compact module")

        XCUIDevice.shared.orientation = .portrait
        self.waitForOrientation(app, landscape: false)
        self.showQuotaBody(app)
        self.capture("Phone Summary quota module portrait restored after rotation and tab changes")
    }

    /// Run independently in each actual phone/Duo pose and light/dark system appearance.
    /// The test never changes those traits; each attachment is a complete actual app screen.
    @MainActor func testNativeSummaryQuotaModuleInCurrentDisplayPose() throws {
        try self.verifyNativeSummaryQuotaModuleInCurrentDisplayPose()
    }

    @MainActor func testPhoneSummaryQuotaModuleInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try self.verifyNativeSummaryQuotaModuleInCurrentDisplayPose(requiresPhoneLandscape: true)
    }

    @MainActor private func verifyNativeSummaryQuotaModuleInCurrentDisplayPose(
        requiresPhoneLandscape: Bool = false) throws
    {
        let app = self.launch(addModule: false)
        if requiresPhoneLandscape {
            self.waitForOrientation(app, landscape: true)
            XCTAssertGreaterThan(
                app.frame.width,
                app.frame.height,
                "Capture actual landscape, not just a rotation request")
            XCTAssertLessThan(app.frame.height, 600, "Use the explicit rotation entry point only on a compact iPhone")
        }
        self.capture("Native Usage provider cards without quota module in current display pose")
        SummaryQuotaUITestFlow.tab(app, name: "Summary").tap()
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["summary-quota-module"].exists)
        self.capture("Native Summary before optional quota module in current display pose")
        SummaryQuotaUITestFlow.addModule(app)
        SummaryQuotaUITestFlow.moveModuleToFirst(app)
        self.showQuotaBody(app)
        let module = app.descendants(matching: .any)["summary-quota-module"].firstMatch
        let chart = app.descendants(matching: .any)["usage-quota-chart"].firstMatch
        let metric = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "summary-card-"))
            .firstMatch
        self.capture("Native Summary four-tile quota module with tabs in current display pose")
        XCTAssertTrue(module.exists && chart.exists && metric.exists)
        XCTAssertGreaterThan(chart.frame.width, 140)
        XCTAssertGreaterThanOrEqual(chart.frame.height, 99.5, "Allow half a point for CGFloat frame rounding")
        XCTAssertEqual(
            module.frame.width,
            metric.frame.width * 2 + 8,
            accuracy: 3,
            "The module must occupy two metric columns")
        XCTAssertGreaterThanOrEqual(
            module.frame.height,
            metric.frame.height * 2 - 0.5,
            "The module must reserve two metric rows, allowing subpixel frame rounding")
        XCTAssertLessThan(
            module.frame.height,
            metric.frame.height * 2 + 40,
            "The module must retain its compact four-tile footprint")
        XCTAssertGreaterThanOrEqual(chart.frame.minX, module.frame.minX - 1)
        XCTAssertLessThanOrEqual(chart.frame.maxX, module.frame.maxX + 1)
        XCTAssertTrue(self.currentQuotaRows(app).isEmpty, "Current account rows belong in the pushed quota detail")
        XCTAssertTrue(app.staticTexts["+3"].exists, "The module summarizes two labels and the remaining count")

        self.openQuotaDetail(app)
        self.assertDetailContentReachable(app)
        let accountRow = try XCTUnwrap(self.currentQuotaRows(app).last)
        self.assertDetailElementClearsChrome(accountRow, in: app)
        let accountID = String(accountRow.identifier.dropFirst("quota-detail-current-".count))
        accountRow.tap()
        let account = app.descendants(matching: .any)["quota-detail-account-" + accountID].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        self.waitForAccountNavigationToSettle(account, in: app)
        self.capture("Quota detail account drill-down with complete native app in current display pose")
        self.back(app, title: "Remaining Quota")
        XCTAssertTrue(app.scrollViews["quota-detail-scroll"].waitForExistence(timeout: 5))
        self.closeQuotaDetail(app)
        self.top(app)
        app.buttons["usage-quota-edit"].tap()
        XCTAssertTrue(app.buttons["quota-editor-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 / 5"].exists)
        self.capture("Native Summary quota selection sheet in current display pose")
        app.buttons["quota-editor-done"].tap()
        for title in ["Cost", "Setting", "Usage"] {
            let tab = SummaryQuotaUITestFlow.tab(app, name: title)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Every tab must remain a native reachable control")
            tab.tap()
            if title == "Cost" {
                XCTAssertTrue(app.buttons["cost-group-order-button"].waitForExistence(timeout: 15))
            } else if title == "Setting" {
                XCTAssertTrue(app.staticTexts["Setup Guide"].firstMatch.waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(app.scrollViews["usage-provider-list"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.descendants(matching: .any)["usage-quota-chart"].exists)
            }
            self.capture("Native \(title) complete app in current display pose")
        }
        SummaryQuotaUITestFlow.tab(app, name: "Summary").tap()
        self.showQuotaBody(app)
        XCTAssertTrue(self.currentQuotaRows(app).isEmpty)
        self.capture("Native Summary restored with compact quota module")
    }

    // The iOS 26 XCTest runner discovers the throwing entry point but skips its synchronous void counterpart.
    // swiftformat:disable:next redundantThrows
    @MainActor func testJapaneseSummaryModuleAtLargestStandardTextSizeKeepsLabelsSeparate() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = self.launch(language: "ja", contentSize: "UICTContentSizeCategoryXXXL")
        self.waitForOrientation(app, landscape: false)
        XCTAssertLessThan(app.frame.width, 600, "Run the largest standard text regression on a compact iPhone")
        self.showQuotaBody(app)
        XCTAssertTrue(app.descendants(matching: .any)["summary-grid-columns-2"].exists)
        let module = app.descendants(matching: .any)["summary-quota-module"].firstMatch
        let title = app.staticTexts["残りの利用枠"].firstMatch
        let period = app.staticTexts["usage-quota-period"]
        let chart = app.descendants(matching: .any)["usage-quota-chart"].firstMatch
        let legend = app.descendants(matching: .any)["usage-quota-legend-toggle"].firstMatch
        let edit = app.buttons["usage-quota-edit"]
        for element in [title, period, chart, legend] {
            XCTAssertTrue(element.exists)
            XCTAssertTrue(
                module.frame.insetBy(dx: -1, dy: -1).contains(element.frame),
                "Every title, date, plot and legend must stay inside its four-tile module")
        }
        XCTAssertLessThanOrEqual(title.frame.maxY, period.frame.minY + 1)
        XCTAssertLessThanOrEqual(period.frame.maxY, chart.frame.minY + 1)
        XCTAssertLessThanOrEqual(chart.frame.maxY, legend.frame.minY + 1)
        XCTAssertLessThanOrEqual(
            title.frame.maxX,
            edit.frame.minX + 1,
            "The Japanese title must not overlap the line selection control")
        self.capture("Phone Japanese Summary module largest standard text complete app")
        self.openQuotaDetail(app)
        XCTAssertEqual(self.currentQuotaRows(app).count, 5)
        for row in self.currentQuotaRows(app) {
            self.reveal(row, in: app)
        }
        self.assertDetailElementClearsChrome(
            app.descendants(matching: .any)["quota-detail-history-notice"].firstMatch, in: app)
        self.capture("Phone Japanese largest standard text quota detail with complete history notice")
        self.closeQuotaDetail(app)
    }

    @MainActor func testEditorLimitRemoveAddColorAndOrderSurviveReentry() {
        let app = self.launch()
        app.buttons["usage-quota-edit"].tap()
        XCTAssertTrue(app.buttons["quota-editor-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 / 5"].waitForExistence(timeout: 5))
        let add = app.buttons["quota-editor-add"]
        self.reveal(add, in: app)
        XCTAssertFalse(add.isEnabled, "A sixth selection must not be possible")
        self.top(app)
        let color = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "quota-line-color-")).firstMatch
        if !color.exists { self.attachHierarchy(app, name: "Missing production ColorPicker identifier") }
        XCTAssertTrue(color.exists, "Every selected line must expose the production ColorPicker")
        XCTAssertGreaterThan(color.frame.width, 20)

        let removed = self.actions(app).firstMatch
        let removedID = removed.identifier
        removed.tap()
        app.buttons["Remove"].tap()
        XCTAssertFalse(app.buttons[removedID].exists)
        XCTAssertTrue(app.staticTexts["4 / 5"].exists)
        self.reveal(add, in: app)
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(app.navigationBars["Add quota"].waitForExistence(timeout: 5))

        let metrics = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-catalog-"))
        XCTAssertTrue(metrics.firstMatch.waitForExistence(timeout: 5))
        let metricIDs = metrics.allElementsBoundByIndex.map(\.identifier)
        var didAdd = false
        for metricID in metricIDs {
            let metric = app.buttons[metricID]
            self.reveal(metric, in: app)
            metric.tap()
            let available = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND enabled == true", "quota-candidate-")).firstMatch
            if available.waitForExistence(timeout: 1) {
                available.tap()
                didAdd = true
                break
            }
            self.back(app, title: "Add quota")
        }
        XCTAssertTrue(didAdd, "Removing a selection must make at least one account quota addable again")
        XCTAssertTrue(app.staticTexts["5 / 5"].waitForExistence(timeout: 5))
        self.capture("Quota editor restored to five lines with color controls")

        self.top(app)
        let visible = self.actions(app).allElementsBoundByIndex.filter(\.isHittable)
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertGreaterThanOrEqual(visible.count, 2)
        guard visible.count >= 2 else { return }
        let firstID = visible[0].identifier
        let secondID = visible[1].identifier
        app.buttons[firstID].tap()
        app.buttons["Move down"].tap()
        XCTAssertLessThan(app.buttons[secondID].frame.minY, app.buttons[firstID].frame.minY)
        app.buttons["quota-editor-done"].tap()
        XCTAssertTrue(app.buttons["usage-quota-edit"].waitForExistence(timeout: 5))
        app.buttons["usage-quota-edit"].tap()
        XCTAssertTrue(app.buttons["quota-editor-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 / 5"].exists)
        XCTAssertLessThan(app.buttons[secondID].frame.minY, app.buttons[firstID].frame.minY)
        self.capture("Quota editor order retained after closing and reentering")
        app.buttons["quota-editor-done"].tap()
    }

    // Keep the throwing entry point for iOS 26 XCTest discovery.
    // swiftformat:disable:next redundantThrows
    @MainActor func testQuotaEditorAndDetailHideAccountEmails() throws {
        let app = self.launch(hidden: true)
        self.openQuotaDetail(app)
        XCTAssertEqual(self.currentQuotaRows(app).count, 5)
        XCTAssertTrue(self.currentQuotaRows(app).allSatisfy { !$0.label.contains("@") })
        XCTAssertFalse(
            self.historyReadout(app).contains("@"),
            "History inspection must also respect hidden personal info")
        XCTAssertTrue(self.lineButtons(app).allSatisfy { !$0.label.contains("@") })
        self.closeQuotaDetail(app)
        self.top(app)
        app.buttons["usage-quota-edit"].tap()
        XCTAssertTrue(app.buttons["quota-editor-done"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "@")).count, 0)
        self.capture("Quota editor with hidden personal info and distinguishable account ordinals")
        self.actions(app).firstMatch.tap()
        app.buttons["Remove"].tap()
        let add = app.buttons["quota-editor-add"]
        self.reveal(add, in: app)
        add.tap()
        let metric = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-catalog-")).firstMatch
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        metric.tap()
        let candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-candidate-"))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(candidates.allElementsBoundByIndex.allSatisfy { !$0.label.contains("@") })
        self.capture("Quota account picker respects hidden personal info")
    }

    // Keep the throwing entry point for iOS 26 XCTest discovery.
    // swiftformat:disable:next redundantThrows
    @MainActor func testQuotaDetailAtAccessibilitySizeKeepsAllRowsReachable() throws {
        let app = self.launch(largeText: true)
        let chart = app.descendants(matching: .any)["usage-quota-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            chart.frame.height,
            200,
            "The real app must have applied an accessibility content size before claiming AX evidence")
        self.openQuotaDetail(app)
        let rows = self.currentQuotaRows(app)
        XCTAssertEqual(rows.count, 5)
        self.assertDetailElementClearsChrome(
            app.descendants(matching: .any)["quota-detail-chart-container"].firstMatch, in: app)
        self.capture("Summary quota accessibility quota detail top")
        self.assertAccessibleTextStack(
            app.descendants(matching: .any)["quota-detail-history-readout"].firstMatch,
            minimumFieldCount: 16,
            in: app)
        for (index, row) in rows.enumerated() {
            // At maximum AX size a fully wrapped account card can exceed one screen.
            // Every field must still fit and be readable as the user scrolls through it.
            self.assertAccessibleTextStack(row, minimumFieldCount: 7, in: app)
            XCTAssertTrue(row.isHittable, "The visible portion must remain an account navigation target")
            if index == 0 {
                let accountID = String(row.identifier.dropFirst("quota-detail-current-".count))
                // The last field is fully visible; tap that part of the large Button,
                // rather than asking XCTest to tap its potentially offscreen center.
                let lastField = try XCTUnwrap(row.staticTexts.allElementsBoundByIndex.last)
                lastField.tap()
                let account = app.descendants(matching: .any)["quota-detail-account-" + accountID].firstMatch
                XCTAssertTrue(account.waitForExistence(timeout: 5))
                self.waitForAccountNavigationToSettle(account, in: app)
                self.capture("Maximum accessibility account navigation from a visible card field")
                self.back(app, title: "Remaining Quota")
                XCTAssertTrue(app.scrollViews["quota-detail-scroll"].waitForExistence(timeout: 5))
            }
        }
        self.assertDetailElementClearsChrome(
            app.descendants(matching: .any)["quota-detail-history-notice"].firstMatch, in: app)
        self.capture("Summary quota accessibility complete history notice reached by scrolling")
        self.closeQuotaDetail(app)
    }

    @MainActor func testCostWholeGroupOrderMovesNumbersAcrossTheOldPaneBoundary() {
        let app = self.launch(addModule: false)
        SummaryQuotaUITestFlow.tab(app, name: "Cost").tap()
        let edit = app.buttons["cost-group-order-button"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        edit.tap()
        let spend = app.staticTexts["cost-order-dailySpend"]
        let overview = app.staticTexts["cost-order-overview"]
        XCTAssertTrue(spend.waitForExistence(timeout: 5))
        XCTAssertTrue(overview.exists)
        XCTAssertGreaterThan(spend.frame.minY, overview.frame.minY)
        let source = app.cells.containing(.staticText, identifier: "cost-order-dailySpend").firstMatch
        let destination = app.cells.containing(.staticText, identifier: "cost-order-overview").firstMatch
        XCTAssertTrue(source.exists && destination.exists)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .press(
                forDuration: 0.7,
                thenDragTo: destination.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)))
        XCTAssertLessThan(spend.frame.minY, overview.frame.minY)
        self.capture("Cost whole group native reorder editor")
        app.buttons["cost-order-done"].tap()
        let primary = app.scrollViews["workspace-primary"]
        let spendTitle = primary.staticTexts["cost-dashboard-daily-spend-title"]
        let overviewTitle = primary.staticTexts["Overview"].firstMatch
        if !spendTitle.exists { self.attachHierarchy(app, name: "Cost production group after reorder") }
        XCTAssertTrue(
            spendTitle.waitForExistence(timeout: 5),
            "Daily Spend must move from the secondary to primary sequence")
        XCTAssertTrue(overviewTitle.exists)
        XCTAssertLessThan(spendTitle.frame.minY, overviewTitle.frame.minY)
        XCTAssertGreaterThan(spendTitle.frame.width, 60)
        self.capture("Cost reordered production numbers with native tabs")
        edit.tap()
        XCTAssertTrue(spend.waitForExistence(timeout: 5))
        XCTAssertLessThan(spend.frame.minY, overview.frame.minY)
        app.buttons["cost-order-done"].tap()
    }

    @MainActor private func attachHierarchy(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}

/// Focus and inspection helpers shared by the detail interaction and rotation cases.
extension UsageQuotaOverviewUITests {
    @MainActor private func capture(_ name: String) {
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "\(name) - screen \(index)"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
    }

    @MainActor private func back(_ app: XCUIApplication, title: String) {
        let rail = app.buttons["BackButton"]
        if rail.exists { rail.tap(); return }
        let navigation = app.navigationBars.buttons[title]
        if navigation.exists { navigation.tap(); return }
        let systemRail = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["BackButton"]
        XCTAssertTrue(systemRail.exists)
        systemRail.tap()
    }

    @MainActor private func assertAccessibleTextStack(
        _ container: XCUIElement, minimumFieldCount: Int, in app: XCUIApplication)
    {
        let fields = container.descendants(matching: .staticText).allElementsBoundByIndex
            .filter { $0.children(matching: .staticText).allElementsBoundByIndex.isEmpty }
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertGreaterThanOrEqual(fields.count, minimumFieldCount, "Validate every displayed field, not one sample")
        let frames = fields.map(\.frame)
        for (previous, next) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.maxY, next.minY + 0.5, "Accessibility text must not overlap")
        }
        for field in fields {
            XCTAssertFalse(field.label.isEmpty)
            self.assertDetailElementClearsChrome(field, in: app)
            XCTAssertGreaterThanOrEqual(field.frame.minX, container.frame.minX - 0.5)
            XCTAssertLessThanOrEqual(field.frame.maxX, container.frame.maxX + 0.5)
        }
    }

    @MainActor private func actions(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-line-actions-"))
    }

    @MainActor private func assertVerticalChartDragScrollsPage(_ app: XCUIApplication) {
        let chart = app.descendants(matching: .any)["quota-detail-chart-container"].firstMatch
        self.assertDetailElementClearsChrome(chart, in: app)
        let scrubber = app.sliders["quota-detail-scrubber"]
        let inspectionTime = scrubber.value as? String
        let initialY = chart.frame.minY
        // The plot fills most of a short landscape viewport. Users must be able
        // to scroll from its interior, without finding a narrow margin around it.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.75)).press(
            forDuration: 0.05,
            thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.35)),
            withVelocity: .slow,
            thenHoldForDuration: 0.2)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in chart.frame.minY < initialY - 12 }, object: nil)], timeout: 5)
        if result != .completed {
            self.attachHierarchy(app, name: "Vertical plot drag failed to scroll quota detail")
            self.capture("Vertical plot drag must scroll the page without changing history time")
        }
        XCTAssertEqual(result, .completed, "A vertical drag inside the plot must move the detail page")
        XCTAssertEqual(
            scrubber.value as? String,
            inspectionTime,
            "Vertical scrolling must not inspect a different time")
    }

    @MainActor private func lineButtons(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-detail-line-"))
            .allElementsBoundByIndex
    }

    @MainActor private func currentValues(_ app: XCUIApplication) -> [String: String] {
        let rows = self.currentQuotaRows(app)
        XCTAssertEqual(rows.count, 5)
        return Dictionary(uniqueKeysWithValues: rows.map {
            let value = $0.value as? String ?? ""
            XCTAssertFalse(
                value.isEmpty,
                "Current quota rows must expose their own current value or availability state")
            return ($0.identifier, value)
        })
    }

    @MainActor private func historyReadout(_ app: XCUIApplication) -> String {
        let readout = app.descendants(matching: .any)["quota-detail-history-readout"].firstMatch
        XCTAssertTrue(readout.exists)
        return ([readout.label] + readout.descendants(matching: .any).allElementsBoundByIndex.map(\.label))
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    @MainActor private func waitFor(_ condition: @escaping () -> Bool) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 5), .completed)
    }

    @MainActor private func waitForAccountNavigationToSettle(_ account: XCUIElement, in app: XCUIApplication) {
        var previousFrame: CGRect?
        var stableSince = Date()
        self.waitFor {
            let previousGear = app.buttons["quota-detail-edit"]
            guard account.exists, account.isHittable, !previousGear.exists || !previousGear.isHittable else {
                previousFrame = nil
                return false
            }
            let frame = account.frame
            guard previousFrame == frame else {
                previousFrame = frame
                stableSince = Date()
                return false
            }
            // iOS 27 exposes the destination before its push animation finishes.
            // Capture only after actual geometry stays stable and the old toolbar is inactive.
            return Date().timeIntervalSince(stableSince) >= 0.6
        }
    }
}
