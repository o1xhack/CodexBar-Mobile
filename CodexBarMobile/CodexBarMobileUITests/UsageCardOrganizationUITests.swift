import XCTest

/// Research/064 — multi-account cards, provider `…` menu, pins and Edit Order.
/// Runs on the multi-account preview data: Codex × 3, Claude × 2, plus the
/// single-account demo providers.
final class UsageCardOrganizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func makeApp(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_PREVIEW_DATA",
            "UI_TEST_MULTI_ACCOUNT_DATA",
            "UI_TEST_SKIP_ONBOARDING",
            "-cwlEnabled", "NO",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        if reset {
            app.launchArguments.append("UI_TEST_RESET_DEFAULTS")
        }
        return app
    }

    @MainActor
    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        self.add(shot)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upFirst: Bool = false) {
        if upFirst {
            for _ in 0..<6 where !element.isHittable {
                app.swipeDown()
            }
        }
        for _ in 0..<10 where !element.isHittable {
            app.swipeUp()
        }
    }

    @MainActor
    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<6 {
            app.swipeDown(velocity: .fast)
        }
    }

    @MainActor
    private func openDetail(_ identifier: String, title: String, in app: XCUIApplication) {
        let card = app.buttons[identifier]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "missing \(identifier)")
        self.reveal(card, in: app)
        card.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openMenuItem(_ identifier: String, in app: XCUIApplication) {
        let menu = app.buttons["provider-more-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let item = app.buttons[identifier]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "missing menu item \(identifier)")
        item.tap()
    }

    @MainActor
    private func backToList(_ app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    /// Stack navigation (iPhone, iPad portrait) needs a back tap; the
    /// list-detail layout keeps the list on screen.
    @MainActor
    private func returnToListIfNeeded(_ app: XCUIApplication) {
        if !app.searchFields.firstMatch.waitForExistence(timeout: 1) {
            self.backToList(app)
        }
    }

    @MainActor
    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "1") != on {
            // Tap the switch knob itself; a Form row tap can land on the label.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let expected = on ? "1" : "0"
        let predicate = NSPredicate(format: "value == %@", expected)
        expectation(for: predicate, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    private func requireCompactPhone(_ app: XCUIApplication) throws {
        try XCTSkipUnless(app.frame.width < 600, "Card flow is verified on a compact phone layout")
    }

    // MARK: - Expansion, pin, persistence

    @MainActor
    func testProviderMenuExpandsAccountsPinsCardsAndPersistsAcrossLaunch() throws {
        XCUIDevice.shared.orientation = .portrait
        var app = self.makeApp(reset: true)
        app.launch()
        try self.requireCompactPhone(app)

        // Default: one grouped Codex card with a "· 3" account badge.
        XCTAssertTrue(app.buttons["provider-group-codex"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["provider-account-card-codex-1"].exists)
        self.capture("Usage grouped default")

        // … → Provider Settings → expand Codex accounts.
        self.openDetail("provider-group-codex", title: "Codex", in: app)
        self.openMenuItem("provider-menu-settings", in: app)
        let expand = app.switches["provider-settings-expand-accounts"]
        self.setSwitch(expand, on: true)
        self.capture("Provider settings expanded")
        app.buttons["provider-settings-done"].tap()
        // The open detail follows the provider to its first account card.
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        self.backToList(app)
        for ordinal in 1...3 {
            XCTAssertTrue(
                app.buttons["provider-account-card-codex-\(ordinal)"].waitForExistence(timeout: 5),
                "Codex account card \(ordinal) missing")
        }
        XCTAssertFalse(app.buttons["provider-group-codex"].exists)
        // Claude was not expanded: still one card.
        XCTAssertTrue(app.buttons["provider-group-claude"].exists)
        self.capture("Usage Codex accounts expanded")

        // Pin the third Codex account from its own detail menu.
        self.openDetail("provider-account-card-codex-3", title: "Codex", in: app)
        self.openMenuItem("provider-menu-pin", in: app)
        self.backToList(app)
        self.scrollToTop(app)
        let pinnedHeader = app.staticTexts["usage-section-pinned"]
        XCTAssertTrue(pinnedHeader.waitForExistence(timeout: 5))
        let pinnedCard = app.buttons["provider-account-card-codex-3"]
        let firstOther = app.buttons["provider-group-claude"]
        XCTAssertTrue(pinnedCard.exists)
        XCTAssertLessThan(pinnedCard.frame.minY, firstOther.frame.minY)
        XCTAssertGreaterThan(pinnedCard.frame.minY, pinnedHeader.frame.minY)
        self.capture("Usage pinned account card")

        // Relaunch without resetting defaults: expansion and pin survive.
        app.terminate()
        app = self.makeApp(reset: false)
        app.launch()
        XCTAssertTrue(app.staticTexts["usage-section-pinned"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["provider-account-card-codex-3"].exists)
        XCTAssertTrue(app.buttons["provider-account-card-codex-1"].exists)
        XCTAssertFalse(app.buttons["provider-group-codex"].exists)
        self.capture("Usage after relaunch")

        // Unpin from the menu, then collapse Codex again.
        self.openDetail("provider-account-card-codex-3", title: "Codex", in: app)
        self.openMenuItem("provider-menu-pin", in: app)
        self.openMenuItem("provider-menu-settings", in: app)
        self.setSwitch(app.switches["provider-settings-expand-accounts"], on: false)
        app.buttons["provider-settings-done"].tap()
        self.backToList(app)
        self.scrollToTop(app)
        XCTAssertFalse(app.staticTexts["usage-section-pinned"].exists)
        XCTAssertTrue(app.buttons["provider-group-codex"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["provider-account-card-codex-1"].exists)
    }

    @MainActor
    func testSingleAccountProviderSettingsExplainWhyExpansionIsUnavailable() throws {
        let app = self.makeApp(reset: true)
        app.launch()
        try self.requireCompactPhone(app)
        self.openDetail("provider-group-openrouter", title: "OpenRouter", in: app)
        self.openMenuItem("provider-menu-settings", in: app)
        let expand = app.switches["provider-settings-expand-accounts"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertFalse(expand.isEnabled)
        XCTAssertTrue(app.staticTexts["Only one account of this provider is synced right now."].exists)
        XCTAssertTrue(app.staticTexts["Saved on this iPhone only. Not synced to your Mac."].exists)
        app.buttons["provider-settings-done"].tap()
    }

    // MARK: - Edit Order

    /// Full editor order (pinned then others) filtered to `keys`.
    @MainActor
    private func rowOrder(_ app: XCUIApplication, keys: [String]) -> [String] {
        let state = app.descendants(matching: .any)["sort-order-state"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        let all = (state.value as? String ?? "").split(separator: ",").map(String.init)
        return all.filter { keys.contains($0) }
    }

    @MainActor
    func testEditOrderDefaultRulesManualDragAndPersistence() throws {
        XCUIDevice.shared.orientation = .portrait
        var app = self.makeApp(reset: true)
        app.launch()
        try self.requireCompactPhone(app)

        let keys = ["provider:claude", "provider:codex", "provider:openrouter", "provider:zai"]
        let editOrder = app.buttons["usage-edit-order"]
        XCTAssertTrue(editOrder.waitForExistence(timeout: 8))
        editOrder.tap()
        XCTAssertTrue(app.navigationBars["Edit Order"].waitForExistence(timeout: 5))
        self.capture("Edit order manual default")

        // Default order → Name (Z to A).
        self.setSwitch(app.switches["sort-default-toggle"], on: true)
        app.buttons["Name (Z to A)"].firstMatch.tap()
        var order = self.rowOrder(app, keys: keys)
        XCTAssertEqual(order, ["provider:zai", "provider:openrouter", "provider:codex", "provider:claude"])
        self.capture("Edit order Z to A")

        // Name (A to Z).
        app.buttons["Name (A to Z)"].firstMatch.tap()
        order = self.rowOrder(app, keys: keys)
        XCTAssertEqual(order, ["provider:claude", "provider:codex", "provider:openrouter", "provider:zai"])

        // Weekly reset: every card here has a weekly reset except
        // OpenRouter, which follows after them.
        app.buttons["Weekly Reset (Soonest First)"].firstMatch.tap()
        order = self.rowOrder(app, keys: keys)
        XCTAssertEqual(order.last, "provider:openrouter")
        self.capture("Edit order weekly reset")

        // Manual: starts from the visible A to Z order, then drag Codex
        // above Antigravity (both near the top of the list).
        app.buttons["Name (A to Z)"].firstMatch.tap()
        self.setSwitch(app.switches["sort-default-toggle"], on: false)
        let manualKeys = ["provider:antigravity", "provider:codex"]
        XCTAssertEqual(self.rowOrder(app, keys: manualKeys), manualKeys)
        let source = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder' AND label CONTAINS 'Codex'"))
            .firstMatch
        let target = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Reorder' AND label CONTAINS 'Antigravity'"))
            .firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(target.exists)
        source.press(forDuration: 0.6, thenDragTo: target)
        XCTAssertEqual(self.rowOrder(app, keys: manualKeys), ["provider:codex", "provider:antigravity"])
        self.capture("Edit order manual dragged")
        app.buttons["sort-editor-done"].tap()

        // Usage list follows the manual order.
        self.scrollToTop(app)
        let codex = app.buttons["provider-group-codex"]
        let antigravity = app.buttons["provider-group-antigravity"]
        XCTAssertTrue(codex.waitForExistence(timeout: 5))
        XCTAssertLessThan(codex.frame.minY, antigravity.frame.minY)

        // Persisted across launch.
        app.terminate()
        app = self.makeApp(reset: false)
        app.launch()
        XCTAssertTrue(app.buttons["provider-group-codex"].waitForExistence(timeout: 8))
        XCTAssertLessThan(
            app.buttons["provider-group-codex"].frame.minY,
            app.buttons["provider-group-antigravity"].frame.minY)
        app.buttons["usage-edit-order"].tap()
        XCTAssertTrue(app.navigationBars["Edit Order"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["sort-default-toggle"].value as? String, "0")
        XCTAssertEqual(self.rowOrder(app, keys: manualKeys), ["provider:codex", "provider:antigravity"])
    }

    // MARK: - Visual capture (iPhone and iPad, run once per appearance)

    @MainActor
    func testCaptureOrganizationScreensOnCurrentDevice() {
        let app = self.makeApp(reset: true)
        app.launch()
        let device = app.frame.width < 600 ? "iPhone" : "iPad"
        XCTAssertTrue(app.buttons["provider-group-codex"].waitForExistence(timeout: 8))
        self.capture("\(device) grouped")

        self.openDetail("provider-group-codex", title: "Codex", in: app)
        self.openMenuItem("provider-menu-settings", in: app)
        self.setSwitch(app.switches["provider-settings-expand-accounts"], on: true)
        self.capture("\(device) provider settings")
        app.buttons["provider-settings-done"].tap()
        self.returnToListIfNeeded(app)

        self.openDetail("provider-account-card-codex-2", title: "Codex", in: app)
        self.openMenuItem("provider-menu-pin", in: app)
        self.returnToListIfNeeded(app)
        self.scrollToTop(app)
        XCTAssertTrue(app.staticTexts["usage-section-pinned"].waitForExistence(timeout: 5))
        self.capture("\(device) expanded and pinned")

        app.buttons["usage-edit-order"].tap()
        XCTAssertTrue(app.navigationBars["Edit Order"].waitForExistence(timeout: 5))
        self.capture("\(device) edit order manual")
        self.setSwitch(app.switches["sort-default-toggle"], on: true)
        app.buttons["Weekly Reset (Soonest First)"].firstMatch.tap()
        self.capture("\(device) edit order weekly")
        app.buttons["sort-editor-done"].tap()
    }
}
