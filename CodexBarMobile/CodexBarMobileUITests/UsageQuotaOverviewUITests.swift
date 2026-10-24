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
            "-hidePersonalInfo", hidden ? "YES" : "NO",
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

    @MainActor private func capture(_ name: String) {
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "\(name) - screen \(index)"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
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
        let legendOpen = app.buttons["quota-legend-done"].exists
        let id = legendOpen ? "quota-legend-sheet" : "summary-grid"
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
            // Summary's production Layout eagerly lays out its module, while the
            // sheet keeps its own scrolling. Drag only within the visible surface.
            let upward = frame.isNull || frame.midY > visible.midY
            // The complete module nearly fills a short landscape viewport. Center
            // its measured frame instead of repeatedly overshooting with a fixed drag.
            // Native pans consume about 10pt before content moves: the observed 9.6pt
            // residual never scrolled. Include that recognition distance in the gesture,
            // then measure the resulting frame again; the visibility check stays exact.
            let remainingDistance = frame.isNull ? visible.height * 0.28 : abs(frame.midY - visible.midY)
            let distance = min(72, max(16, remainingDistance + 12))
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
        let obstructions: [CGRect]
        if scroller.identifier == "quota-legend-sheet" {
            // The native sheet covers Summary's TabBar, which remains in the AX
            // tree. Only the sheet's own navigation controls can obscure its rows.
            let bars = app.navigationBars.containing(.button, identifier: "quota-legend-done")
                .allElementsBoundByIndex
            let chrome = bars.isEmpty ? [app.buttons["quota-legend-done"]] : bars
            obstructions = chrome.filter(\.exists).map(\.frame)
        } else {
            let chrome = app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
                + app.searchFields.allElementsBoundByIndex.filter(\.isHittable)
            let tabBounds = ["Usage", "Summary", "Cost", "Setting"].map { SummaryQuotaUITestFlow.tab(app, name: $0) }
                .filter { $0.exists && $0.isHittable }.reduce(CGRect.null) { $0.union($1.frame) }
            obstructions = chrome.filter(\.exists).map(\.frame) + [tabBounds]
        }
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
            "quota-line-actions-", "quota-catalog-", "quota-candidate-")
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

    @MainActor private func actions(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quota-line-actions-"))
    }

    @MainActor private func legendRows(_ app: XCUIApplication) -> [XCUIElement] {
        let matches = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier != %@",
            "usage-quota-legend-",
            "usage-quota-legend-toggle"))
        var seen = Set<String>()
        return matches.allElementsBoundByIndex.filter { seen.insert($0.identifier).inserted }
    }

    @MainActor private func assertQuotaClearsNativeChrome(_ app: XCUIApplication) {
        let module = app.descendants(matching: .any)["summary-quota-module"].firstMatch
        let chart = app.descendants(matching: .any)["usage-quota-chart"].firstMatch
        let legend = app.buttons["usage-quota-legend-toggle"]
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
        if !legend.isHittable { problems.append("The collapsed legend must be directly tappable") }
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
            module, in: app, hittableControl: app.buttons["usage-quota-legend-toggle"])
        if !visible {
            self.attachHierarchy(app, name: "Complete Summary module is not reachable")
            self.capture("Complete Summary module visibility failure")
        }
        XCTAssertTrue(visible, "The entire module, including its title, must be reachable between native bars")
        self.assertQuotaClearsNativeChrome(app)
    }

    @MainActor private func openLegend(_ app: XCUIApplication) {
        let toggle = app.buttons["usage-quota-legend-toggle"]
        self.reveal(toggle, in: app)
        toggle.tap()
        XCTAssertTrue(app.scrollViews["quota-legend-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quota-legend-done"].isHittable)
    }

    @MainActor private func closeLegend(_ app: XCUIApplication) {
        app.buttons["quota-legend-done"].tap()
        XCTAssertTrue(app.scrollViews["quota-legend-sheet"].waitForNonExistence(timeout: 5))
    }

    @MainActor func testPhoneSummaryModuleSurvivesRotationAndTabChanges() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = self.launch()
        self.waitForOrientation(app, landscape: false)
        XCTAssertLessThan(app.frame.width, 600, "Run this regression on an ordinary compact iPhone")
        self.showQuotaBody(app)
        self.capture("Phone Summary quota module portrait with complete native app")
        let toggle = app.buttons["usage-quota-legend-toggle"]
        let selectedLines = toggle.value as? String

        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForOrientation(app, landscape: true)
        self.showQuotaBody(app)
        self.capture("Phone Summary quota module landscape with complete native app")
        self.openLegend(app)
        let rows = self.legendRows(app)
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            self.reveal(row, in: app)
        }
        self.capture("Phone Summary landscape legend sheet last row reachable")
        self.closeLegend(app)

        SummaryQuotaUITestFlow.tab(app, name: "Usage").tap()
        XCTAssertTrue(app.scrollViews["usage-provider-list"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["usage-quota-chart"].exists)
        self.capture("Phone Usage landscape provider cards without quota module")
        SummaryQuotaUITestFlow.tab(app, name: "Summary").tap()
        self.showQuotaBody(app)
        XCTAssertEqual(toggle.value as? String, selectedLines)
        XCTAssertTrue(self.legendRows(app).isEmpty, "The legend sheet must close without expanding the module")

        XCUIDevice.shared.orientation = .portrait
        self.waitForOrientation(app, landscape: false)
        self.showQuotaBody(app)
        self.capture("Phone Summary quota module portrait restored after rotation and tab changes")
    }

    /// Run independently in each actual phone/Duo pose and light/dark system appearance.
    /// The test never changes those traits; each attachment is a complete actual app screen.
    @MainActor func testNativeSummaryQuotaModuleInCurrentDisplayPose() {
        let app = self.launch(addModule: false)
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
        XCTAssertTrue(self.legendRows(app).isEmpty, "Detailed rows belong in the separate legend sheet")
        XCTAssertTrue(app.staticTexts["+3"].exists, "The module summarizes two labels and the remaining count")

        self.openLegend(app)
        let rows = self.legendRows(app)
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            self.reveal(row, in: app)
            XCTAssertGreaterThan(row.frame.height, 20)
            XCTAssertGreaterThan(row.frame.width, 120)
        }
        self.capture("Native Summary quota legend sheet in current display pose")
        self.closeLegend(app)
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
        XCTAssertTrue(self.legendRows(app).isEmpty)
        self.capture("Native Summary restored with compact quota module")
    }

    @MainActor func testJapaneseSummaryModuleAtLargestStandardTextSizeKeepsLabelsSeparate() {
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
        let legend = app.buttons["usage-quota-legend-toggle"]
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
        self.openLegend(app)
        XCTAssertEqual(self.legendRows(app).count, 5)
        for row in self.legendRows(app) {
            self.reveal(row, in: app)
        }
        self.capture("Phone Japanese largest standard text quota legend sheet")
        self.closeLegend(app)
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

    @MainActor func testQuotaEditorAndExpandedLegendHideAccountEmails() {
        let app = self.launch(hidden: true)
        self.openLegend(app)
        XCTAssertEqual(self.legendRows(app).count, 5)
        XCTAssertTrue(self.legendRows(app).allSatisfy { !$0.label.contains("@") })
        self.closeLegend(app)
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

    @MainActor func testExpandedLegendAtAccessibilitySizeKeepsAllRowsReachable() {
        let app = self.launch(largeText: true)
        let chart = app.descendants(matching: .any)["usage-quota-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            chart.frame.height,
            200,
            "The real app must have applied an accessibility content size before claiming AX evidence")
        self.openLegend(app)
        let rows = self.legendRows(app)
        XCTAssertEqual(rows.count, 5)
        let sheet = app.scrollViews["quota-legend-sheet"]
        self.capture("Summary quota accessibility legend sheet top")
        for row in rows {
            self.reveal(row, in: app)
            XCTAssertGreaterThan(row.frame.height, 40)
            XCTAssertGreaterThanOrEqual(row.frame.minX, sheet.frame.minX - 2)
            XCTAssertLessThanOrEqual(
                row.frame.maxX,
                sheet.frame.maxX + 2,
                "Large text must wrap inside the legend sheet rather than escape horizontally")
            XCTAssertFalse(row.label.isEmpty)
        }
        self.capture("Summary quota accessibility fifth legend row reached by scrolling")
        self.closeLegend(app)
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

    @MainActor private func back(_ app: XCUIApplication, title: String) {
        let rail = app.buttons["BackButton"]
        if rail.exists { rail.tap(); return }
        let navigation = app.navigationBars.buttons[title]
        if navigation.exists { navigation.tap(); return }
        let systemRail = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["BackButton"]
        XCTAssertTrue(systemRail.exists)
        systemRail.tap()
    }

    @MainActor private func attachHierarchy(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
