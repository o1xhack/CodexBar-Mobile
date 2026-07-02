import XCTest

final class CodexBarMobileUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUsageSettingsSwitchBetweenUsedAndRemainingPercentages() {
        let app = self.makeApp()
        app.launch()

        app.tabBars.buttons["Setting"].tap()
        app.staticTexts["Usage Setting"].tap()
        let remainingToggle = app.switches["show-remaining-usage-toggle"]
        XCTAssertTrue(remainingToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(remainingToggle.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Usage"].exists)
        XCTAssertTrue(app.staticTexts["Charts"].exists)
        XCTAssertTrue(app.staticTexts["Privacy"].exists)
        XCTAssertTrue(app.staticTexts["Show remaining usage"].exists)
        XCTAssertTrue(
            app.staticTexts["Display the quota you have left instead of the quota you have used on usage cards."]
                .exists)
    }

    @MainActor
    func testCostTabShowsDailySpendCurrencyUnitInTitle() {
        let app = self.makeApp()
        app.launch()

        app.tabBars.buttons["Cost"].tap()

        XCTAssertTrue(app.staticTexts["Daily Spend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["(USD)"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCostTabCapturesRenderingScreenshot() {
        let app = self.makeApp()
        app.launch()

        app.tabBars.buttons["Cost"].tap()

        XCTAssertTrue(app.staticTexts["Provider Share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Model Mix"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Cost Tab Rendering"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSpringBoardWidgetConfigurationPanelOpens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UI_TEST_SPRINGBOARD_WIDGET"] == "1"
            || environment["TEST_RUNNER_UI_TEST_SPRINGBOARD_WIDGET"] == "1" else {
            throw XCTSkip("Requires a simulator Home Screen with a placed CodexBar widget.")
        }

        let app = self.makeApp()
        app.launch()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))

        self.openSpringBoardWidgetConfigurationPanel(on: springboard)

        let openedAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        openedAttachment.name = "SpringBoard Widget Configuration Panel"
        openedAttachment.lifetime = .keepAlways
        add(openedAttachment)

        // The system-hosted configuration UI is not consistently exposed through
        // XCTest accessibility on iOS 26 simulators, so use normalized screen
        // coordinates after proving the configuration extension is foreground.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.43)).tap()
        Thread.sleep(forTimeInterval: 0.5)

        let modePickerAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        modePickerAttachment.name = "SpringBoard Widget Type Picker"
        modePickerAttachment.lifetime = .keepAlways
        add(modePickerAttachment)

        self.selectSpringBoardWidgetMode(
            on: springboard,
            name: "Today Cost",
            pickerRowY: 0.56
        )
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_PREVIEW_DATA",
            "UI_TEST_SKIP_ONBOARDING",
            "UI_TEST_RESET_DEFAULTS",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        return app
    }

    @MainActor
    private func firstExistingElement(in app: XCUIApplication, labels: [String]) -> XCUIElement {
        for label in labels {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 0.5) {
                return button
            }
        }
        return app.buttons[labels[0]]
    }

    @MainActor
    private func openSpringBoardWidgetConfigurationPanel(on springboard: XCUIApplication) {
        let widget = springboard.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "CodexBar"))
            .firstMatch
        if widget.waitForExistence(timeout: 3) {
            widget.press(forDuration: 1.2)
        } else {
            // XCTest can miss WidgetKit host views even when SpringBoard exposes
            // them to the runtime accessibility snapshot. Fall back to the
            // release-gate simulator layout: a medium CodexBar widget centered
            // near the top of the first Home Screen page.
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.20))
                .press(forDuration: 1.2)
        }

        let editWidget = self.firstExistingElement(
            in: springboard,
            labels: ["Edit Widget", "编辑小组件", "編輯小工具", "ウィジェットを編集"]
        )
        XCTAssertTrue(editWidget.waitForExistence(timeout: 5), "SpringBoard did not expose the Edit Widget action.")
        editWidget.tap()

        let configurationExtension = XCUIApplication(
            bundleIdentifier: "com.apple.WorkflowUI.WidgetConfigurationExtension"
        )
        XCTAssertTrue(
            configurationExtension.wait(for: .runningForeground, timeout: 5),
            "SpringBoard did not foreground the widget configuration extension."
        )
    }

    @MainActor
    private func selectSpringBoardWidgetMode(
        on springboard: XCUIApplication,
        name: String,
        pickerRowY: CGFloat
    ) {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.46, dy: pickerRowY)).tap()
        Thread.sleep(forTimeInterval: 1.0)

        let selectionAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        selectionAttachment.name = "SpringBoard \(name) Configuration Selected"
        selectionAttachment.lifetime = .keepAlways
        add(selectionAttachment)

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2.0)

        let widgetAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        widgetAttachment.name = "SpringBoard \(name) Widget"
        widgetAttachment.lifetime = .keepAlways
        add(widgetAttachment)
    }
}
