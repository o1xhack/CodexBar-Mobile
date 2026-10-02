import XCTest

final class CodexBarMobileUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testV070QuotaPaceRendersInFourLanguages() {
        XCUIDevice.shared.orientation = .portrait
        for (language, title) in [
            ("en", "Quota pace"),
            ("zh-Hans", "额度消耗趋势"),
            ("zh-Hant", "額度消耗趨勢"),
            ("ja", "クォータ消費の推移"),
        ] {
            let app = XCUIApplication()
            app.launchArguments = [
                "UI_TEST_PREVIEW_DATA", "UI_TEST_SKIP_ONBOARDING", "UI_TEST_RESET_DEFAULTS",
                "-cwlEnabled", "NO", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
            ]
            app.launch()
            let provider = app.buttons["provider-group-claude"]
            XCTAssertTrue(provider.waitForExistence(timeout: 10))
            for _ in 0..<6 where !provider.isHittable {
                app.swipeUp()
            }
            provider.tap()
            XCTAssertTrue(app.navigationBars["Claude"].waitForExistence(timeout: 5))
            let heading = app.staticTexts[title].firstMatch
            for _ in 0..<14 where !heading.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(heading.isHittable, "Quota heading must be visible in \(language)")
            let chart = app.descendants(matching: .any)["quota-burndown-lane-0"].firstMatch
            // A visible section heading can sit above a chart that is still
            // below the viewport or behind the tab bar. Scroll the chart into
            // view before requiring its accessibility element to be mounted.
            for _ in 0..<8 where !chart.exists || !chart.isHittable {
                app.swipeUp()
            }
            if !chart.exists {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Quota chart accessibility hierarchy \(language)"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertTrue(chart.waitForExistence(timeout: 5), "Real production chart must exist in \(language)")
            XCTAssertTrue(chart.isHittable, "Chart must be visible before capture in \(language)")
            XCTAssertGreaterThan(chart.frame.height, 0)
            XCTAssertTrue(chart.label.contains(title))
            XCTAssertTrue((chart.value as? String)?.contains("87%") == true)
            self.captureScreen(app, name: "v070 quota pace \(language)")
            app.terminate()
        }
    }

    @MainActor
    func testResetDatesAndCodexPaceUseTheReaderLanguage() {
        XCUIDevice.shared.orientation = .portrait
        for (language, fragment, explanation) in [
            ("en", "16 percentage points below even pace", "Weekly pace estimate"),
            ("zh-Hans", "低 16 个百分点", "每周用量估算"),
            ("zh-Hant", "低 16 個百分點", "每週用量估算"),
            ("ja", "16 ポイント低い", "週間使用ペースの推定"),
        ] {
            let app = XCUIApplication()
            app.launchArguments = [
                "UI_TEST_PREVIEW_DATA", "UI_TEST_SKIP_ONBOARDING", "UI_TEST_RESET_DEFAULTS",
                "-cwlEnabled", "NO", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
            ]
            app.launch()
            let provider = app.buttons["provider-group-codex"]
            XCTAssertTrue(provider.waitForExistence(timeout: 10))
            for _ in 0..<6 where !provider.isHittable {
                app.swipeUp()
            }
            provider.tap()
            XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
            let absolute = app.staticTexts.matching(identifier: "usage.reset.absolute").firstMatch
            XCTAssertTrue(absolute.waitForExistence(timeout: 5))
            XCTAssertTrue(absolute.isHittable)
            let pace = app.staticTexts["codex-pace-summary"]
            for _ in 0..<10 where !pace.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(pace.waitForExistence(timeout: 5))
            XCTAssertTrue(pace.label.contains(fragment))
            if language == "en" { XCTAssertFalse(pace.label.contains("节奏")) }
            self.captureScreen(app, name: "Reset dates and Codex pace \(language)")
            let info = app.buttons["codex-pace-info"]
            XCTAssertTrue(info.isHittable)
            info.tap()
            XCTAssertTrue(app.alerts[explanation].waitForExistence(timeout: 5))
            self.captureScreen(app, name: "Pace explanation \(language)")
            app.terminate()
        }
    }

    @MainActor
    func testVersionUpdateShowsReleaseNotesAndSetupGuideOnDemand() {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_PREVIEW_DATA",
            "UI_TEST_RESET_DEFAULTS",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let setup = app.buttons["release-notes-setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 8))
        XCTAssertEqual(setup.label, "Setup")
        XCTAssertTrue(app.navigationBars["Release Notes"].exists)
        self.captureScreen(app, name: "2.2 update notes on launch")
        setup.tap()
        XCTAssertTrue(app.navigationBars["Setup Guide"].waitForExistence(timeout: 5))
        self.captureScreen(app, name: "Setup Guide opened from update notes")
        app.buttons["setup-guide-done"].tap()
        XCTAssertTrue(app.buttons["release-notes-done"].waitForExistence(timeout: 5))
        app.buttons["release-notes-done"].tap()
        XCTAssertTrue(app.buttons["provider-group-codex"].waitForExistence(timeout: 8))

        app.terminate()
        app.launchArguments = ["UI_TEST_PREVIEW_DATA", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertFalse(setup.waitForExistence(timeout: 2), "Release notes should appear only once per app version.")
        XCTAssertTrue(app.buttons["provider-group-codex"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testChoosingDemoFromSetupGuideDismissesFirstLaunchReleaseNotes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_PREVIEW_DATA",
            "UI_TEST_RESET_DEFAULTS",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()

        let setup = app.buttons["release-notes-setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 8))
        setup.tap()

        let demoPreview = app.buttons["Preview with Demo Data"]
        XCTAssertTrue(app.navigationBars["Setup Guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(demoPreview.waitForExistence(timeout: 5))
        demoPreview.tap()

        XCTAssertTrue(app.navigationBars["CodexBar (Demo)"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Exit Demo"].exists)
        XCTAssertFalse(app.buttons["release-notes-done"].exists)
    }

    @MainActor
    func testPhoneNavigationSafeAreaAndRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = self.makeApp()
        app.launchArguments += ["-cwlEnabled", "NO"]
        app.launch()
        try XCTSkipUnless(app.frame.width < 600, "Requires a compact phone")
        self.captureNavigation(app, name: "Phone Usage portrait")
        let provider = app.buttons["provider-group-codex"]
        for _ in 0..<4 where !provider.isHittable {
            app.swipeUp()
        }
        provider.tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Cost"].tap()
        app.tabBars.buttons["Usage"].tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        // Select again after returning: catches a stale compact-column binding.
        for _ in 0..<4 where !provider.isHittable {
            app.swipeUp()
        }
        provider.tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForOrientation(app, landscape: true)
        XCTAssertTrue(app.navigationBars["Codex"].exists)
        XCTAssertFalse(app.buttons["adaptive-tab-cost"].exists)
        self.captureNavigation(app, name: "Phone provider landscape")
        XCUIDevice.shared.orientation = .portrait
        self.waitForOrientation(app, landscape: false)
        app.navigationBars.buttons.firstMatch.tap()
        // Scroll completely to the end; final content must clear the tab buttons.
        for _ in 0..<16 {
            app.swipeUp(velocity: .fast)
        }
        let footer = app.otherElements["usage-scroll-footer"].firstMatch
        XCTAssertTrue(footer.exists)
        XCTAssertLessThanOrEqual(footer.frame.maxY, app.tabBars.buttons["Usage"].frame.minY)
        self.captureNavigation(app, name: "Phone Usage bottom clearance")
        app.tabBars.buttons["Setting"].tap()
        app.staticTexts["Usage Setting"].tap()
        XCTAssertTrue(app.switches["show-remaining-usage-toggle"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["Cost Setting"].tap()
        self.captureNavigation(app, name: "Phone Cost settings")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Cost"].tap()
        let overview = app.buttons["token-overview-link"]
        for _ in 0..<8 where !overview.isHittable {
            app.swipeUp()
        }
        overview.tap()
        XCTAssertTrue(app.navigationBars["Token Activity"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Setting"].tap()
        app.tabBars.buttons["Cost"].tap()
        XCTAssertTrue(app.navigationBars["Token Activity"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        self.captureNavigation(app, name: "Phone Cost restored")
    }

    @MainActor
    func testTabletColumnsSearchAndSettingsSelectionSurviveResize() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = self.makeApp()
        app.launchArguments += ["-cwlEnabled", "NO"]
        app.launch()
        try XCTSkipUnless(app.frame.width >= 600, "Requires an iPad")
        let claude = app.buttons["provider-group-claude"]
        let codex = app.buttons["provider-group-codex"]
        XCTAssertTrue(claude.waitForExistence(timeout: 8))
        XCTAssertEqual(claude.frame.minY, codex.frame.minY, accuracy: 4)
        XCTAssertLessThan(claude.frame.maxX, codex.frame.minX)
        self.assertBottomTabs(app)
        self.captureNavigation(app, name: "iPad portrait two columns")
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Codex")
        XCTAssertTrue(codex.exists)
        XCTAssertFalse(claude.exists)
        codex.tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForOrientation(app, landscape: true)
        self.assertBottomTabs(app)
        XCTAssertTrue(app.navigationBars["Codex"].exists)
        self.captureNavigation(app, name: "iPad landscape selected Codex")
        app.searchFields.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["adaptive-tab-settings"].exists)
        XCTAssertTrue(app.navigationBars["Codex"].exists)
        XCTAssertTrue(app.buttons["provider-group-codex"].exists, "Keyboard must retain the sidebar and detail")
        self.captureNavigation(app, name: "iPad landscape keyboard keeps navigation")
        app.buttons["provider-group-codex"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        self.assertBottomTabs(app)
        app.tabBars.buttons["Setting"].tap()
        app.staticTexts["Usage Setting"].tap()
        let toggle = app.switches["show-remaining-usage-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        self.captureNavigation(app, name: "iPad landscape Settings detail")
        XCUIDevice.shared.orientation = .portrait
        self.waitForOrientation(app, landscape: false)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        self.captureNavigation(app, name: "iPad portrait retained Settings detail")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Cost Setting"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Cost"].tap()
        self.captureNavigation(app, name: "iPad portrait Cost")
        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForOrientation(app, landscape: true)
        self.assertBottomTabs(app)
        self.captureNavigation(app, name: "iPad landscape Cost")
    }

    @MainActor
    private func assertBottomTabs(_ app: XCUIApplication) {
        let usage = app.tabBars.buttons["Usage"]
        let cost = app.tabBars.buttons["Cost"]
        let setting = app.tabBars.buttons["Setting"]
        XCTAssertTrue(setting.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["adaptive-tab-cost"].exists)
        XCTAssertFalse(app.otherElements["adaptive-trailing-navigation"].exists)
        XCTAssertGreaterThan(usage.frame.midY, app.frame.minY + app.frame.height * 0.8)
        XCTAssertEqual(usage.frame.midY, cost.frame.midY, accuracy: 4)
        XCTAssertEqual(cost.frame.midY, setting.frame.midY, accuracy: 4)
        XCTAssertLessThan(usage.frame.midX, cost.frame.midX)
        XCTAssertLessThan(cost.frame.midX, setting.frame.midX)
    }

    @MainActor
    private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let predicate = NSPredicate { _, _ in
            landscape ? app.frame.width > app.frame.height : app.frame.height > app.frame.width
        }
        expectation(for: predicate, evaluatedWith: app)
        waitForExpectations(timeout: 8)
    }

    @MainActor
    private func captureNavigation(_ app: XCUIApplication, name: String) {
        // Capture the display after the compositor finishes orientation changes;
        // app.screenshot() can crop with stale geometry immediately after rotation.
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testRoomyNavigationPreservesProviderThroughPortraitResize() throws {
        let app = self.makeApp()
        app.launchArguments += ["-cwlEnabled", "NO"]
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        try XCTSkipUnless(min(app.frame.width, app.frame.height) >= 600, "Requires a roomy simulator window")
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        self.assertBottomTabs(app)
        let provider = app.buttons["provider-group-codex"]
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        provider.tap()
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        let portrait = NSPredicate { _, _ in app.frame.height > app.frame.width }
        expectation(for: portrait, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["adaptive-tab-cost"].exists)
        XCTAssertTrue(app.navigationBars["Codex"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Setting"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Setting"].tap()
        app.staticTexts["Usage Setting"].tap()
        XCTAssertTrue(app.switches["show-remaining-usage-toggle"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: landscape, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        self.assertBottomTabs(app)
        app.tabBars.buttons["Cost"].tap()
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Generic iPad resize validation - not a Duo device"
        shot.lifetime = .keepAlways
        add(shot)
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
    func testCostShareEditorUsesPreviewFirstTemplatesAndHeatmapControls() {
        let app = self.makeApp()
        app.launch()
        app.tabBars.buttons["Cost"].tap()
        let share = app.buttons["cost-share-button"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()

        XCTAssertTrue(app.navigationBars["Create Share Card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["share-card-preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["share-style-classic"].exists)
        XCTAssertTrue(app.buttons["share-style-cyber"].exists)
        let heatmap = app.buttons["share-style-heatmap"]
        XCTAssertTrue(heatmap.exists)
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)

        heatmap.tap()
        XCTAssertTrue(app.buttons["share-range-picker"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["share-provider-picker"].exists)
        let action = app.buttons["share-card-action"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: action)
        waitForExpectations(timeout: 8)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Cost share editor - Heatmap"
        shot.lifetime = .keepAlways
        add(shot)
        action.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testCostShareEditorUsesTwoColumnsOnWideIPad() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = self.makeApp()
        app.launch()
        try XCTSkipUnless(app.frame.width >= 700, "Requires a wide iPad window")

        app.tabBars.buttons["Cost"].tap()
        let share = app.buttons["cost-share-button"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()

        let preview = app.otherElements["share-card-preview"]
        let period = app.buttons["share-period-picker"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        XCTAssertLessThan(preview.frame.maxX, period.frame.minX)
        XCTAssertTrue(app.buttons["share-card-action"].isHittable)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Cost share editor - iPad landscape"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testSpringBoardWidgetCanSelectOverview() throws {
        try self.runSpringBoardWidgetModeSelection(
            name: "Overview",
            pickerLabels: ["Overview", "概览", "概覽", "概要"],
            pickerRowY: 0.44)
    }

    @MainActor
    func testSpringBoardWidgetCanSelectProviderFocus() throws {
        try self.runSpringBoardWidgetModeSelection(
            name: "Provider Focus",
            pickerLabels: ["Provider Focus", "提供商焦点", "供應商焦點", "プロバイダーフォーカス"],
            pickerRowY: 0.50)
    }

    @MainActor
    func testSpringBoardWidgetCanSelectTodayCost() throws {
        try self.runSpringBoardWidgetModeSelection(
            name: "Today Cost",
            pickerLabels: ["Today Cost", "今日成本", "今日成本", "今日のコスト"],
            pickerRowY: 0.56)
    }

    @MainActor
    func testSpringBoardWidgetCanSelectSyncHealth() throws {
        try self.runSpringBoardWidgetModeSelection(
            name: "Sync Health",
            pickerLabels: ["Sync Health", "同步健康", "同步健康", "同期の健全性"],
            pickerRowY: 0.64)
    }

    @MainActor
    private func runSpringBoardWidgetModeSelection(
        name: String,
        pickerLabels: [String],
        pickerRowY: CGFloat) throws
    {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UI_TEST_SPRINGBOARD_WIDGET"] == "1"
            || environment["TEST_RUNNER_UI_TEST_SPRINGBOARD_WIDGET"] == "1"
        else {
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
            name: name,
            pickerLabels: pickerLabels,
            pickerRowY: pickerRowY)
    }

    @MainActor
    func testTokenActivityOverviewScrollsAndSelectsDay() throws {
        let app = self.makeApp()
        // Preview snapshots are intentionally not persisted to the real ledger.
        app.launchArguments += ["-cwlEnabled", "NO"]
        app.launch()
        app.tabBars.buttons["Cost"].tap()
        let overview = app.buttons["token-overview-link"]
        for _ in 0..<5 where !overview.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["token-overview-heatmap"].exists)
        XCTAssertFalse(app.buttons["Show all providers"].exists)
        let summary = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        summary.name = "Cost combined token summary"
        summary.lifetime = .keepAlways
        add(summary)
        overview.tap()
        XCTAssertTrue(app.navigationBars["Token Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily Tokens Overview"].exists)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let key = try formatter.string(from: XCTUnwrap(Calendar.current.date(byAdding: .day, value: -7, to: Date())))
        let day = app.buttons["token-day-" + key].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 3))
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "Token cells before selection"
        before.lifetime = .keepAlways
        add(before)
        day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7)
        let selected = app.staticTexts["selected-token-day"]
        for _ in 0..<3 where !selected.exists {
            app.swipeUp()
        }
        XCTAssertTrue(selected.waitForExistence(timeout: 3))
        XCTAssertEqual(selected.label, key)
        XCTAssertTrue(app.buttons["Back to today"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "2.0 Token Overview"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(app.staticTexts["Codex Service Mix"].exists)
    }

    @MainActor
    func testProviderTokenActivityReplacesDailyList() {
        let app = self.makeApp()
        // Preview snapshots are intentionally not persisted to the real ledger.
        app.launchArguments += ["-cwlEnabled", "NO"]
        app.launch()
        app.buttons["provider-group-codex"].tap()
        let title = app.staticTexts["Token Activity"]
        for _ in 0..<10 where !title.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.buttons["Show all days"].exists)
        let move = max(0, title.frame.minY - 130) / app.frame.height
        if move > 0 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
                .press(
                    forDuration: 0.1,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: max(0.15, 0.8 - move))),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.5)
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: Date())
        let today = app.buttons["token-day-" + todayKey].firstMatch
        XCTAssertTrue(today.exists)
        let originalX = today.frame.midX
        let y = today.frame.midY / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: y))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: y)),
                withVelocity: .slow,
                thenHoldForDuration: 0.5)
        XCTAssertTrue(!today.isHittable || today.frame.midX > originalX + 100)
        let history = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        history.name = "2.0 Provider older history after horizontal swipe"
        history.lifetime = .keepAlways
        add(history)
        app.buttons["Back to today"].firstMatch.tap()
        XCTAssertTrue(today.isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "2.0 Provider Token Activity"
        attachment.lifetime = .keepAlways
        add(attachment)
        let serviceMix = app.staticTexts["Codex Service Mix"]
        for _ in 0..<5 where !serviceMix.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(serviceMix.exists)
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
    private func captureScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
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
            labels: ["Edit Widget", "编辑小组件", "編輯小工具", "ウィジェットを編集"])
        XCTAssertTrue(editWidget.waitForExistence(timeout: 5), "SpringBoard did not expose the Edit Widget action.")
        editWidget.tap()

        let configurationExtension = XCUIApplication(
            bundleIdentifier: "com.apple.WorkflowUI.WidgetConfigurationExtension")
        XCTAssertTrue(
            configurationExtension.wait(for: .runningForeground, timeout: 5),
            "SpringBoard did not foreground the widget configuration extension.")
    }

    @MainActor
    private func selectSpringBoardWidgetMode(
        on springboard: XCUIApplication,
        name: String,
        pickerLabels: [String],
        pickerRowY: CGFloat)
    {
        let configurationExtension = XCUIApplication(
            bundleIdentifier: "com.apple.WorkflowUI.WidgetConfigurationExtension")
        if !self.tapFirstExistingPickerLabel(in: configurationExtension, labels: pickerLabels),
           !self.tapFirstExistingPickerLabel(in: springboard, labels: pickerLabels)
        {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.46, dy: pickerRowY)).tap()
        }
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

    @MainActor
    private func tapFirstExistingPickerLabel(in app: XCUIApplication, labels: [String]) -> Bool {
        for label in labels {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 0.2), button.isHittable {
                button.tap()
                return true
            }

            let staticText = app.staticTexts[label]
            if staticText.waitForExistence(timeout: 0.2), staticText.isHittable {
                staticText.tap()
                return true
            }

            let otherElement = app.otherElements[label]
            if otherElement.waitForExistence(timeout: 0.2), otherElement.isHittable {
                otherElement.tap()
                return true
            }
        }
        return false
    }
}
