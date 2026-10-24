import UIKit
import XCTest

final class SummaryTabUITests: XCTestCase {
    override func setUpWithError() throws { self.continueAfterFailure = false }

    @MainActor private func launch(
        language: String = "en", hidePersonalInfo: Bool = false) -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_PREVIEW_DATA", "UI_TEST_MULTI_ACCOUNT_DATA", "UI_TEST_SKIP_ONBOARDING", "UI_TEST_RESET_DEFAULTS",
            "-cwlEnabled", "NO", "-AppleLanguages", "(\(language))", "-AppleLocale",
            language == "ja" ? "ja_JP" : "en_US",
        ]
        if hidePersonalInfo { app.launchArguments += ["-hidePersonalInfo", "YES"] }
        app.launch()
        let names = ["en": "Summary", "zh-Hans": "摘要", "zh-Hant": "摘要", "ja": "概要"]
        let tab = app.nativeTab(names[language] ?? "Summary")
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor private func cards(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "summary-card-"))
    }

    @MainActor private func capture(_ name: String) {
        // Duo keeps the inactive outer display as main; preserve every screen so the
        // active inner display is not replaced by a black outer-screen attachment.
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "\(name) screen \(index)"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
    }

    /// Select the real inner-display pose in Device Hub before running either case.
    /// XCUIDevice.orientation alone does not reliably rotate Duo's inner display.
    @MainActor func testSummaryExpandedPortraitViewport() {
        self.assertSummaryExpandedViewport(landscape: false)
    }

    @MainActor func testSummaryExpandedLandscapeViewport() {
        self.assertSummaryExpandedViewport(landscape: true)
    }

    @MainActor private func assertSummaryExpandedViewport(landscape: Bool) {
        let app = self.launch()
        let grid = app.scrollViews["summary-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["summary-edit"].label, "Edit", "Summary must open outside editing mode")
        XCTAssertEqual(self.summaryDetails(app).count, 0, "Opening or rotating Summary must not select an account")

        // The root app frame may stay in fixed display coordinates on Duo; validate
        // the actual card viewport rather than the requested device orientation.
        XCTAssertEqual(
            grid.frame.width > grid.frame.height, landscape,
            "The actual viewport must match the pose selected in Device Hub")
        let width = grid.frame.width
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThanOrEqual(
            width, app.frame.width * 0.82,
            "Summary's grid must occupy the available window, not a split-view sidebar")
        let columns = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "summary-grid-columns-")).firstMatch
        XCTAssertTrue(columns.waitForExistence(timeout: 5))
        // The column marker is a standalone count label, not the Layout container.
        // Measure the real first card row, which already excludes Duo's native rail
        // safe area; Summary adds 16pt of content padding at each horizontal edge.
        let visibleCards = self.cards(app).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visibleCards.count, 2)
        guard let firstY = visibleCards.map(\.frame.minY).min() else { return }
        let firstRow = visibleCards.filter { abs($0.frame.minY - firstY) < 4 }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let first = firstRow.first, let last = firstRow.last else { return }
        let contentWidth = last.frame.maxX - first.frame.minX
        let expectedColumns = max(2, min(4, Int((contentWidth + 32) / 175)))
        XCTAssertEqual(
            columns.identifier, "summary-grid-columns-\(expectedColumns)",
            "Columns must follow the actual safe-area card width")
        XCTAssertEqual(firstRow.count, expectedColumns)
        XCTAssertGreaterThanOrEqual(
            contentWidth,
            grid.frame.width * 0.75,
            "The card row must use the full grid width after native rail and content insets")
        for card in firstRow {
            XCTAssertEqual(card.frame.width, first.frame.width, accuracy: 2)
            XCTAssertGreaterThanOrEqual(card.frame.minX, grid.frame.minX - 1)
            XCTAssertLessThanOrEqual(card.frame.maxX, grid.frame.maxX + 1)
        }
        for (left, right) in zip(firstRow, firstRow.dropFirst()) {
            XCTAssertEqual(
                right.frame.minX - left.frame.maxX,
                8,
                accuracy: 2,
                "Adjacent metric cards must preserve the grid spacing without overlap")
        }
        // Capture the whole screen, including the system-owned Duo tab/navigation chrome.
        self.capture("Summary Duo \(landscape ? "landscape" : "portrait") full-width grid with native chrome")
    }

    @MainActor func testSummaryCardPushAndBackPreserveProviderFilter() {
        XCUIDevice.shared.orientation = .portrait
        let app = self.launch()
        XCTAssertEqual(self.summaryDetails(app).count, 0)
        XCTAssertEqual(app.buttons["summary-edit"].label, "Edit")
        let codex = app.buttons["summary-filter-codex"]
        XCTAssertTrue(codex.waitForExistence(timeout: 5))
        codex.tap()
        XCTAssertGreaterThan(self.cards(app).count, 0)
        XCTAssertTrue(self.cards(app).allElementsBoundByIndex.allSatisfy { $0.identifier.contains("-codex-") })
        XCTAssertEqual(self.summaryDetails(app).count, 0, "Filtering alone must leave Summary on the grid")

        let first = self.cards(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let detail = app.descendants(matching: .any)
            .matching(identifier: "summary-selected-detail-codex").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8), "An explicit card tap must push that account's details")
        XCTAssertFalse(app.buttons["summary-save"].exists, "A normal tap must not open the customization sheet")
        self.capture("Summary Duo account details after explicit card tap")

        let back = self.summaryBackButton(app)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 8))
        XCTAssertEqual(self.summaryDetails(app).count, 0)
        XCTAssertTrue(app.buttons["summary-filter-codex"].isSelected)
        XCTAssertGreaterThan(self.cards(app).count, 0)
        XCTAssertTrue(self.cards(app).allElementsBoundByIndex.allSatisfy { $0.identifier.contains("-codex-") })
        XCTAssertEqual(app.buttons["summary-edit"].label, "Edit")
        self.capture("Summary Duo returned to grid with Codex filter retained")
    }

    @MainActor private func summaryDetails(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "summary-selected-detail-"))
    }

    @MainActor private func summaryBackButton(_ app: XCUIApplication) -> XCUIElement {
        // Duo's actual accessibility tree identifies the native rail control as BackButton,
        // outside NavigationBar. The rail may be hosted by the app or by SpringBoard.
        let railBack = app.buttons["BackButton"]
        if railBack.exists { return railBack }
        let navigationBack = app.navigationBars.buttons["Summary"]
        if navigationBack.exists { return navigationBack }
        return XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["BackButton"]
    }

    @MainActor func testProviderFilterAndEditingCountdownNameAndColor() {
        let app = self.launch()
        self.capture("Summary initial")
        let codex = app.buttons["summary-filter-codex"]
        XCTAssertTrue(codex.waitForExistence(timeout: 5))
        codex.tap()
        XCTAssertGreaterThan(self.cards(app).count, 0)
        XCTAssertTrue(self.cards(app).allElementsBoundByIndex.allSatisfy { $0.identifier.contains("-codex-") })
        app.buttons["summary-filter-all"].tap()
        app.buttons["summary-edit"].tap()
        let first = self.cards(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.buttons["summary-save"].waitForExistence(timeout: 5))
        let countdown = app.buttons["Time to reset"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        countdown.tap()
        let name = app.textFields["summary-card-name"]
        name.tap()
        name.typeText("My key limit")
        app.buttons["summary-color-purple"].tap()
        self.capture("Summary edited countdown preview")
        app.buttons["summary-save"].tap()
        XCTAssertTrue(self.cards(app).matching(NSPredicate(format: "label CONTAINS %@", "My key limit")).firstMatch
            .waitForExistence(timeout: 5))
        app.buttons["summary-edit"].tap()
        self.capture("Summary custom card")
    }

    @MainActor func testPrivacyModeKeepsNamesEditableAsPlainText() {
        let app = self.launch(hidePersonalInfo: true)
        app.buttons["summary-edit"].tap()
        self.cards(app).firstMatch.tap()
        let name = app.textFields["summary-card-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["summary-card-name"].exists)
        name.tap()
        let displayName = "C 5x fictional@example.invalid"
        name.typeText(displayName)
        XCTAssertEqual(name.value as? String, displayName)
        let aliasDisclosure = app.buttons["summary-account-alias-disclosure"]
        XCTAssertTrue(aliasDisclosure.waitForExistence(timeout: 5))
        aliasDisclosure.tap()
        let alias = app.textFields["summary-account-alias"]
        XCTAssertTrue(alias.waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["summary-account-alias"].exists)
        alias.tap()
        alias.typeText("Work")
        XCTAssertEqual(alias.value as? String, "Work")
        self.capture("Summary plain-text names with privacy enabled")
        app.buttons["summary-save"].tap()
        let saved = self.cards(app).matching(NSPredicate(format: "label CONTAINS %@", "C 5x")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertFalse(saved.label.contains("fictional@example.invalid"))
        saved.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, displayName)
        app.buttons["Cancel"].tap()
    }

    /// Select the simulator's actual system appearance before running this case.
    /// AppleInterfaceStyle launch defaults do not reliably change Duo's trait environment.
    @MainActor func testTabSurfacesInCurrentSystemAppearance() {
        let app = self.launch()
        self.capture("Summary unified surface")
        for tabName in ["Usage", "Cost", "Setting"] {
            let tab = app.nativeTab(tabName)
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            tab.tap()
            if tabName == "Cost" {
                XCTAssertTrue(app.staticTexts["Overview"].firstMatch.waitForExistence(timeout: 8))
            } else if tabName == "Setting" {
                XCTAssertTrue(app.staticTexts["Setup Guide"].firstMatch.waitForExistence(timeout: 5))
            }
            self.capture("\(tabName) surface reference")
        }
        app.terminate()
    }

    @MainActor func testCancelledCreationDoesNotAddAndCreatingAddsOneCard() {
        let app = self.launch()
        let initial = self.cards(app).count
        app.buttons["summary-add"].tap()
        XCTAssertTrue(app.buttons["summary-add-next"].waitForExistence(timeout: 5))
        app.buttons["summary-add-next"].tap()
        XCTAssertTrue(app.buttons["summary-save"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))
        XCTAssertEqual(self.cards(app).count, initial)
        app.buttons["summary-add"].tap()
        app.buttons["summary-add-next"].tap()
        app.buttons["summary-save"].tap()
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))
        XCTAssertEqual(self.cards(app).count, initial + 1)
        self.capture("Summary created metric")
    }

    @MainActor func testQuotaModuleIsOptionalRemovableAndOrderPersists() {
        let app = self.launch()
        let module = app.descendants(matching: .any)["summary-quota-module"].firstMatch
        XCTAssertFalse(module.exists, "Existing Summary cards must not opt users into the chart")
        let originalCardIDs = Set(self.cards(app).allElementsBoundByIndex.map(\.identifier))
        SummaryQuotaUITestFlow.addModule(app)
        SummaryQuotaUITestFlow.moveModuleToFirst(app)
        XCTAssertTrue(module.waitForExistence(timeout: 5))
        XCTAssertEqual(Set(self.cards(app).allElementsBoundByIndex.map(\.identifier)), originalCardIDs)

        app.buttons["summary-add"].tap()
        let addModule = app.buttons["summary-add-quota-module"]
        XCTAssertTrue(addModule.waitForExistence(timeout: 5))
        XCTAssertFalse(addModule.isEnabled, "Only one Remaining Quota module can be pinned")
        app.buttons["Cancel"].tap()

        // UI preview data intentionally uses an in-memory preferences store. Verify
        // saving across navigation here; store tests cover persistence across processes.
        app.nativeTab("Usage").tap()
        XCTAssertTrue(app.scrollViews["usage-provider-list"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["usage-quota-chart"].exists)
        app.nativeTab("Summary").tap()
        XCTAssertTrue(module.waitForExistence(timeout: 8))
        SummaryQuotaUITestFlow.openOrder(app)
        XCTAssertTrue(
            SummaryQuotaUITestFlow.moduleIsFirst(app),
            "Module order must survive tab changes and editor reentry")
        app.buttons["summary-order-done"].tap()
        self.capture("Summary optional quota module saved at the front of the grid")

        app.buttons["summary-edit"].tap()
        let remove = app.buttons["summary-remove-quota-module"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5) && remove.isHittable)
        remove.tap()
        XCTAssertTrue(module.waitForNonExistence(timeout: 5))
        XCTAssertEqual(
            Set(self.cards(app).allElementsBoundByIndex.map(\.identifier)),
            originalCardIDs,
            "Unpinning the module must leave individual metric cards unchanged")
        app.buttons["summary-edit"].tap()
        SummaryQuotaUITestFlow.addModule(app)
        SummaryQuotaUITestFlow.moveModuleToFirst(app)
        XCTAssertTrue(module.waitForExistence(timeout: 5))
        self.capture("Summary quota module re-added without duplicating metric cards")
    }

    @MainActor func testSummaryAcrossFourLanguages() {
        for language in ["en", "zh-Hans", "zh-Hant", "ja"] {
            let app = self.launch(language: language)
            XCTAssertGreaterThan(self.cards(app).count, 0)
            self.capture("Summary \(language)")
            app.terminate()
        }
    }
}

/// Shared production navigation for the Summary lifecycle and quota-editor suites.
/// No launch fixture pre-pins the module: every caller uses the same Add and native
/// Edit Order controls available to the user.
@MainActor enum SummaryQuotaUITestFlow {
    static func tab(_ app: XCUIApplication, name: String) -> XCUIElement {
        let names: [String: String] = app.launchArguments.contains("(ja)")
            ? ["Summary": "概要", "Setting": "設定"] : [:]
        let label = names[name] ?? name
        let bottomButton = app.tabBars.buttons[label]
        if bottomButton.exists { return bottomButton }
        let symbol = [
            "Usage": "chart.bar.fill", "Summary": "square.grid.2x2.fill",
            "Cost": "dollarsign.circle.fill", "Setting": "gearshape",
        ][name] ?? name
        // Prefer the native tab's symbol identifier on either hosting surface.
        // A pushed quota detail can also have a navigation Back button labelled
        // "Summary"; treating it as a tab invents an obstruction across the viewport.
        let local = app.buttons.matching(identifier: symbol).firstMatch
        if local.exists { return local }
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let external = system.buttons.matching(identifier: symbol).firstMatch
        if external.exists { return external }
        let localLabel = app.buttons.matching(identifier: label).firstMatch
        if localLabel.exists { return localLabel }
        return system.buttons.matching(identifier: label).firstMatch
    }

    static func addModule(_ app: XCUIApplication) {
        let add = app.buttons["summary-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5) && add.isHittable)
        add.tap()
        let module = app.buttons["summary-add-quota-module"]
        XCTAssertTrue(module.waitForExistence(timeout: 5) && module.isEnabled && module.isHittable)
        module.tap()
        XCTAssertTrue(module.waitForNonExistence(timeout: 5), "Adding the module must close the catalog")
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))
    }

    static func openOrder(_ app: XCUIApplication) {
        let more = app.buttons["summary-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5) && more.isHittable)
        more.tap()
        let order = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Edit Order", "编辑排序", "編輯排序", "並び順を編集"])).firstMatch
        XCTAssertTrue(order.waitForExistence(timeout: 5))
        order.tap()
        XCTAssertTrue(app.buttons["summary-order-done"].waitForExistence(timeout: 5))
    }

    static func moduleIsFirst(_ app: XCUIApplication) -> Bool {
        let first = app.cells.firstMatch
        return first.exists && first.descendants(matching: .any)["summary-order-quota-module"].exists
    }

    static func moveModuleToFirst(_ app: XCUIApplication) {
        self.openOrder(app)
        let row = app.cells.containing(.any, identifier: "summary-order-quota-module").firstMatch
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        var hasMovedModuleUp = false
        // A short phone may expose only a few order rows. Move through the visible
        // rows, then reveal earlier rows; never drag toward an offscreen destination.
        for _ in 0..<12 {
            if self.moduleIsFirst(app) { break }
            let viewport = self.orderViewport(app, list: list)
            if !row.exists {
                // Reordering can move a large row above the virtualized viewport.
                // Initially it is appended below; after dragging up, search earlier rows.
                self.scroll(list, viewport: viewport, upward: !hasMovedModuleUp)
                continue
            }
            if !row.isHittable || row.frame.minY < viewport.minY || row.frame.maxY > viewport.maxY {
                self.scroll(list, viewport: viewport, upward: row.frame.midY > viewport.midY)
                continue
            }
            let preceding = list.cells.allElementsBoundByIndex.filter {
                $0.isHittable && $0.frame.minY >= viewport.minY && $0.frame.maxY <= viewport.maxY
                    && $0.frame.minY < row.frame.minY - 1
            }
            if let target = preceding.min(by: { $0.frame.minY < $1.frame.minY }) {
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
                    .press(forDuration: 0.7, thenDragTo: target.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)))
                hasMovedModuleUp = true
            } else {
                self.scroll(list, viewport: viewport, upward: false)
            }
        }
        if !self.moduleIsFirst(app) {
            self.captureOrderFailure(app, name: "Summary native order drag failure")
        }
        XCTAssertTrue(self.moduleIsFirst(app), "The native order editor must move the module before all metric cards")
        let done = app.buttons["summary-order-done"]
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))

        // A virtualized list can report its first visible cell as firstMatch after
        // scrolling. Recreate the editor at its initial scroll position and verify
        // the saved first item before accepting the drag as a successful reorder.
        self.openOrder(app)
        if !self.moduleIsFirst(app) {
            self.captureOrderFailure(app, name: "Summary saved order reentry failure")
        }
        XCTAssertTrue(
            self.moduleIsFirst(app),
            "The saved module must be first when the order editor reopens at the top")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["summary-grid"].waitForExistence(timeout: 5))
    }

    private static func captureOrderFailure(_ app: XCUIApplication, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            activity.add(hierarchy)
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let screenshot = XCTAttachment(screenshot: screen.screenshot())
                screenshot.name = "\(name) screen \(index)"
                screenshot.lifetime = .keepAlways
                activity.add(screenshot)
            }
        }
    }

    private static func orderViewport(_ app: XCUIApplication, list: XCUIElement) -> CGRect {
        var viewport = list.frame.intersection(app.windows.firstMatch.frame)
        let navigation = app.navigationBars.containing(.button, identifier: "summary-order-done").firstMatch
        if navigation.exists, navigation.frame.intersects(viewport) {
            // CollectionView extends beneath the translucent sheet navigation bar.
            // A partially visible row there is not a valid native reorder destination.
            let bottom = viewport.maxY
            viewport.origin.y = max(viewport.minY, navigation.frame.maxY)
            viewport.size.height = max(0, bottom - viewport.minY)
        }
        return viewport.insetBy(dx: 4, dy: 8)
    }

    private static func scroll(_ list: XCUIElement, viewport: CGRect, upward: Bool) {
        let origin = list.coordinate(withNormalizedOffset: .zero)
        let upper = origin.withOffset(CGVector(
            dx: viewport.midX - list.frame.minX,
            dy: viewport.minY + viewport.height * 0.3 - list.frame.minY))
        let lower = origin.withOffset(CGVector(
            dx: viewport.midX - list.frame.minX,
            dy: viewport.minY + viewport.height * 0.7 - list.frame.minY))
        (upward ? lower : upper).press(
            forDuration: 0.05, thenDragTo: upward ? upper : lower,
            withVelocity: .slow, thenHoldForDuration: 0.2)
    }
}
