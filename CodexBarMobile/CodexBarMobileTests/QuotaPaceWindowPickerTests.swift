import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Research/071 — choosing which quota window the Quota pace widget follows.
@Suite("Quota pace window picker")
@MainActor
struct QuotaPaceWindowPickerTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let captured = now.addingTimeInterval(-60)

    private static func window(
        _ id: String?,
        _ label: String?,
        used: Double,
        minutes: Int?,
        resetIn: TimeInterval,
        known: Bool = true) -> SyncRateWindow
    {
        SyncRateWindow(
            id: id,
            label: label,
            usedPercent: used,
            usageKnown: known,
            windowMinutes: minutes,
            resetsAt: self.now.addingTimeInterval(resetIn),
            resetDescription: nil)
    }

    private static func provider(
        _ providerID: String,
        _ windows: [SyncRateWindow],
        history: [SyncUtilizationSeries]? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerID == "museai" ? "muse.ai" : providerID.capitalized,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.captured,
            rateWindows: windows,
            utilizationHistory: history)
    }

    private static let claudeSession = window("primary", "Session", used: 20, minutes: 300, resetIn: 3 * 3600)
    private static let claudeWeekly = window("secondary", "Weekly", used: 40, minutes: 10080, resetIn: 3 * 86400)
    private static let claudeFable = window(
        "claude-weekly-scoped-fable", "Fable only", used: 70, minutes: 10080, resetIn: 3 * 86400)

    private static func claude(history: Bool = false) -> ProviderUsageSnapshot {
        let series: [SyncUtilizationSeries]? = history ? [
            SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [
                SyncUtilizationEntry(capturedAt: now.addingTimeInterval(-3600), usedPercent: 10, resetsAt: nil),
            ]),
            SyncUtilizationSeries(name: "weekly", windowMinutes: 10080, entries: [
                SyncUtilizationEntry(capturedAt: self.now.addingTimeInterval(-86400), usedPercent: 25, resetsAt: nil),
            ]),
        ] : nil
        return self.provider("claude", [self.claudeSession, self.claudeWeekly, self.claudeFable], history: series)
    }

    private static let antigravityWindows = [
        window(
            "antigravity-quota-summary-gemini-weekly",
            "Gemini weekly",
            used: 30,
            minutes: 10080,
            resetIn: 4 * 86400),
        window("antigravity-quota-summary-gemini-5h", "Gemini 5-hour", used: 10, minutes: 300, resetIn: 3600),
        window(
            "antigravity-quota-summary-3p-weekly",
            "Claude/GPT weekly",
            used: 55,
            minutes: 10080,
            resetIn: 2 * 86400),
        window("antigravity-quota-summary-3p-5h", "Claude/GPT 5-hour", used: 5, minutes: 300, resetIn: 7200),
        window("gemini-3-pro-image", "Gemini 3 Pro Image", used: 50, minutes: 1440, resetIn: 6 * 3600),
        window("antigravity-claude-gpt", "Claude/GPT", used: 0, minutes: 300, resetIn: 3600, known: false),
    ]

    private static func options(
        _ provider: ProviderUsageSnapshot,
        localization: String = "en") -> [QuotaPaceWindowChoice.Option]
    {
        let record = WidgetActivityPublisher.catalogueEntities(from: [provider], now: Self.now).first
        return QuotaPaceWindowChoice.options(
            for: record,
            preferredLocalizations: [localization],
            defaultTitle: "Default (Weekly)",
            durationText: { "\($0 / 60)h" })
    }

    // MARK: Options

    @Test
    func `Claude offers session, weekly and the Fable-only window by id`() {
        let options = Self.options(Self.claude())
        #expect(options.map(\.identifier) == [
            QuotaPaceWindowChoice.defaultIdentifier,
            "claude|primary",
            "claude|secondary",
            "claude|claude-weekly-scoped-fable",
        ])
        #expect(options.map(\.title) == ["Default (Weekly)", "Session", "Weekly", "Fable only"])
        #expect(options.dropFirst().map(\.subtitle) == ["5h", "168h", "168h"])

        let zh = Self.options(Self.claude(), localization: "zh-Hans").map(\.title)
        #expect(zh.dropFirst() == ["当前周期", "每周", "仅 Fable"])
        let ja = Self.options(Self.claude(), localization: "ja").map(\.title)
        #expect(ja.dropFirst() == ["セッション", "週次", "Fable のみ"])
        let hant = Self.options(Self.claude(), localization: "zh-Hant").map(\.title)
        #expect(hant.dropFirst() == ["當前週期", "每週", "僅 Fable"])
    }

    @Test
    func `Single-window providers such as Codex and muse.ai have nothing to choose`() {
        let codex = Self.provider(
            "codex",
            [Self.window("secondary", "Weekly", used: 30, minutes: 10080, resetIn: 86400)])
        let muse = Self.provider("museai", [Self.window("primary", nil, used: 12, minutes: 10080, resetIn: 86400)])
        for provider in [codex, muse] {
            #expect(Self.options(provider).map(\.identifier) == [QuotaPaceWindowChoice.defaultIdentifier])
            #expect(QuotaPaceWindowSelection.catalogueWindows(for: provider).count == 1)
        }
    }

    @Test
    func `A single short or unsized window is listed so it can be chosen`() {
        let short = Self.provider("zai", [Self.window("primary", "5 hours", used: 50, minutes: 300, resetIn: 3600)])
        let unsized = Self.provider(
            "fictitious",
            [Self.window("credits", "Credits", used: 20, minutes: nil, resetIn: 3600)])
        #expect(Self.options(short).map(\.identifier) == [QuotaPaceWindowChoice.defaultIdentifier, "zai|primary"])
        #expect(Self.options(unsized).map(\.identifier) == [
            QuotaPaceWindowChoice.defaultIdentifier, "fictitious|credits",
        ])

        // End to end: the option the picker offers is the window the widget shows.
        let providers = Self.summaries([short])
        let entity = [WidgetProviderEntity(id: "zai", name: "Zai")]
        let automatic = WidgetProviderSelection.pace(from: providers, selected: entity, limit: 1, now: Self.now)
        #expect(automatic.first?.quotaPace == nil) // Nothing by default, as before.
        let chosen = WidgetProviderSelection.pace(
            from: providers,
            selected: entity,
            limit: 1,
            windowChoice: Self.options(short)[1].identifier,
            now: Self.now)
        #expect(chosen.first?.quotaPace?.windowID == "primary")
        #expect(chosen.first?.quotaPace?.paceRemainingPercent == 50)
        #expect(chosen.first?.quotaPace?.pace == nil)
    }

    @Test
    func `A single window the default does not reach is listed`() {
        // Claude reporting only a carve-out: the default never follows it.
        let sonnet = Self.window("tertiary", "Sonnet", used: 10, minutes: 10080, resetIn: 3 * 86400)
        for window in [sonnet, Self.claudeFable] {
            let provider = Self.provider("claude", [window])
            #expect(QuotaPaceWindowSelection.defaultWindowID(for: provider, now: Self.now) == nil)
            #expect(Self.options(provider).map(\.identifier) == [
                QuotaPaceWindowChoice.defaultIdentifier, "claude|\(window.id ?? "")",
            ])
        }
    }

    @Test
    func `The widget names an unlabeled weekly window Weekly`() throws {
        let en = Locale(identifier: "en")
        // muse.ai: configured with its single unlabeled weekly window. The
        // picker keeps the card's name; the widget never says "Session".
        let muse = try #require(CodexBarWidgetPaceSummary(
            provider: Self.provider("museai", [Self.window("primary", nil, used: 12, minutes: 10080, resetIn: 86400)]),
            now: Self.now)).configured(windowID: nil)
        #expect(muse.windowSource == .defaultWindow)
        #expect(muse.namesWindow == false)
        #expect(muse.heroLabel(providerID: "museai", locale: en) == nil)
        #expect(muse.selectedWindow?.title(providerID: "museai", locale: en) == "Session")
        #expect(muse.selectedWindow?.widgetTitle(providerID: "museai", locale: en) == "Weekly")
        #expect(muse.selectedWindow?.widgetTitle(providerID: "museai", locale: Locale(identifier: "zh-Hans"))
            == "每周")

        // Chosen explicitly next to another window, the hero says Weekly.
        let pair = try #require(CodexBarWidgetPaceSummary(
            provider: Self.provider("fictitious", [
                Self.window(nil, nil, used: 12, minutes: 10080, resetIn: 86400),
                Self.window(nil, nil, used: 40, minutes: 300, resetIn: 3600),
            ]),
            now: Self.now))
        #expect(pair.configured(windowID: "primary").heroLabel(providerID: "fictitious", locale: en) == "Weekly")
        #expect(pair.configured(windowID: "secondary").heroLabel(providerID: "fictitious", locale: en) == "Weekly")
    }

    @Test
    func `Unlabeled windows are named like the provider card`() {
        let windows = [
            Self.window(nil, nil, used: 10, minutes: 10080, resetIn: 86400),
            Self.window(nil, nil, used: 10, minutes: 300, resetIn: 3600),
            Self.window(nil, nil, used: 10, minutes: 1440, resetIn: 3600),
        ]
        let titles = QuotaPaceWindowSelection.catalogueWindows(for: Self.provider("fictitious", windows))
        #expect(titles.map(\.id) == ["primary", "secondary", "tertiary"])
        #expect(titles.map { $0.titles?["en"] } == ["Session", "Weekly", "Limit 3"])
        #expect(titles.map { $0.titles?["zh-Hans"] } == ["当前周期", "每周", "限额 3"])
        let aixy = QuotaPaceWindowSelection.catalogueWindows(for: Self.provider("aixy", Array(windows.prefix(2))))
        #expect(aixy.map { $0.titles?["en"] } == ["Budget", "Secondary budget"])

        // Legacy payloads without rate windows keep the slot they came from.
        let legacy = ProviderUsageSnapshot(
            providerID: "fictitious", providerName: "Fictitious", primary: nil,
            secondary: Self.window(nil, nil, used: 10, minutes: 10080, resetIn: 86400),
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: Self.captured)
        #expect(QuotaPaceWindowSelection.candidates(for: legacy).map(\.id) == ["secondary"])
    }

    @Test
    func `Antigravity lists every window with known usage in card order`() {
        let provider = Self.provider("antigravity", Self.antigravityWindows)
        let options = Self.options(provider)
        #expect(options.count == 1 + 5)
        #expect(options.dropFirst().map(\.identifier) == Self.antigravityWindows.prefix(5).map {
            "antigravity|\($0.id ?? "")"
        })
        #expect(options[1].title == "Gemini · Weekly")
        #expect(Self.options(provider, localization: "zh-Hans")[1].title == "Gemini · 每周")
        #expect(Self.options(provider, localization: "ja")[2].title == "Gemini · 5時間")
    }

    @Test
    func `Equal titles are told apart by window length`() {
        let record = WidgetProviderRecord(id: "fictitious", name: "Fictitious", windows: [
            .init(id: "a", label: "Usage", windowMinutes: 300, titles: ["en": "Usage"]),
            .init(id: "b", label: "Usage", windowMinutes: 10080, titles: ["en": "Usage"]),
        ])
        let options = QuotaPaceWindowChoice.options(
            for: record,
            preferredLocalizations: ["en"],
            defaultTitle: "Default",
            durationText: { "\($0)m" })
        #expect(options.dropFirst().map(\.title) == ["Usage · 300m", "Usage · 10080m"])
    }

    @Test
    func `No provider, an unknown provider and an old catalogue offer only the default`() throws {
        let legacy = try JSONDecoder().decode(
            [WidgetProviderRecord].self,
            from: Data(#"[{"id":"claude","name":"Claude"}]"#.utf8))
        #expect(legacy.first?.windows == nil)
        for record in [nil, legacy.first] {
            let options = QuotaPaceWindowChoice.options(
                for: record,
                preferredLocalizations: ["en"],
                defaultTitle: "Default",
                durationText: { _ in nil })
            #expect(options.map(\.identifier) == [QuotaPaceWindowChoice.defaultIdentifier])
        }
    }

    @Test
    func `Several accounts of one provider contribute the union of their windows`() throws {
        let first = WidgetProviderRecord(id: "claude", name: "Claude", windows: [
            .init(id: "primary", label: "Session", windowMinutes: 300),
            .init(id: "secondary", label: "Weekly", windowMinutes: 10080),
        ])
        let second = WidgetProviderRecord(id: "claude", name: "Claude", windows: [
            .init(id: "secondary", label: "Weekly", windowMinutes: 10080),
            .init(id: "claude-weekly-scoped-fable", label: "Fable only", windowMinutes: 10080),
        ])
        let merged = WidgetProviderCatalogue.merged([first, .init(id: "codex", name: "Codex"), second])
        #expect(merged.map(\.id) == ["claude", "codex"])
        #expect(merged.first?.windows?.map(\.id) == ["primary", "secondary", "claude-weekly-scoped-fable"])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-window-catalogue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("catalogue.json")
        try WidgetProviderCatalogue.write([first, second], to: url)
        #expect(try WidgetProviderCatalogue.read(from: url).first?.windows?.count == 3)

        // An unchanged catalogue is not rewritten; a changed one is.
        let past = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        try WidgetProviderCatalogue.write([first, second], to: url)
        func modified() throws -> Date? {
            try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        }
        #expect(try modified() == past)
        try WidgetProviderCatalogue.write([first], to: url)
        #expect(try modified() != past)
        #expect(try WidgetProviderCatalogue.read(from: url).first?.windows?.count == 2)
    }

    // MARK: Default window

    @Test
    func `A configured provider without a choice follows its weekly window`() throws {
        let claude = try #require(CodexBarWidgetPaceSummary(provider: Self.claude(), now: Self.now))
            .configured(windowID: nil)
        #expect(claude.windowID == "secondary")
        #expect(claude.windowSource == .defaultWindow)
        #expect(claude.isExplicitWindow == false)
        #expect(claude.namesWindow == false) // Same window as before: same hero.
        #expect(claude.paceRemainingPercent == 60)
        // Same pace as the provider detail page's pace badge.
        #expect(claude.pace == QuotaPace(provider: Self.claude(), referenceDate: Self.now))

        let codex = Self.provider("codex", [
            Self.window("primary", "Weekly", used: 30, minutes: 10080, resetIn: 86400),
        ])
        #expect(CodexBarWidgetPaceSummary(provider: codex, now: Self.now)?.configured(windowID: nil).windowID
            == "primary")

        // Antigravity has no native slot: the most constrained weekly window,
        // as the Mac's weekly switcher.
        let antigravity = try #require(CodexBarWidgetPaceSummary(
            provider: Self.provider("antigravity", Self.antigravityWindows),
            now: Self.now)).configured(windowID: nil)
        #expect(antigravity.windowID == "antigravity-quota-summary-3p-weekly")
        #expect(antigravity.paceRemainingPercent == 45)
        #expect(antigravity.pace != nil)
        #expect(antigravity.namesWindow)
    }

    @Test
    func `Antigravity defaults to its most constrained quota-summary bucket`() {
        let windows = [
            Self.window("gemini-3-pro", "Gemini 3 Pro", used: 90, minutes: 10080, resetIn: 86400),
            Self.window("antigravity-quota-summary-b-weekly", "B weekly", used: 40, minutes: 10080, resetIn: 86400),
            Self.window("antigravity-quota-summary-a-weekly", "A weekly", used: 40, minutes: 10080, resetIn: 86400),
        ]
        // Model rows only count without summary buckets; ties take the smaller id.
        #expect(QuotaPaceWindowSelection.defaultWindowID(for: Self.provider("antigravity", windows), now: Self.now)
            == "antigravity-quota-summary-a-weekly")
        #expect(QuotaPaceWindowSelection.defaultWindowID(
            for: Self.provider("antigravity", Array(windows.prefix(1))),
            now: Self.now) == "gemini-3-pro")
    }

    @Test
    func `The default never lands on a Claude carve-out`() throws {
        let expiredWeekly = Self.window("secondary", "Weekly", used: 40, minutes: 10080, resetIn: -3600)
        let sonnet = Self.window("tertiary", "Sonnet", used: 10, minutes: 10080, resetIn: 3 * 86400)
        for windows in [
            [Self.claudeSession, expiredWeekly, sonnet, Self.claudeFable],
            [Self.claudeSession, sonnet, Self.claudeFable], // No account Weekly at all.
        ] {
            let provider = Self.provider("claude", windows)
            let summary = try #require(CodexBarWidgetPaceSummary(provider: provider, now: Self.now))
            #expect(QuotaPaceWindowSelection.defaultWindowID(for: provider, now: Self.now) == nil)
            let configured = summary.configured(windowID: nil)
            #expect(configured.windowID != "tertiary")
            #expect(configured.windowID != "claude-weekly-scoped-fable")
            #expect(configured.primaryLane?.seriesName != "opus")
            // It follows the charted session window instead.
            #expect(configured.windowID == "primary")
            #expect(configured.paceRemainingPercent == 80)
        }
        // Routines are a carve-out too; a non-carve-out extra weekly window is not.
        let routines = Self.window("claude-routines", "Daily Routines", used: 90, minutes: 10080, resetIn: 86400)
        let design = Self.window("claude-design", "Designs", used: 15, minutes: 10080, resetIn: 86400)
        let provider = Self.provider("claude", [Self.claudeSession, routines, design])
        #expect(QuotaPaceWindowSelection.defaultWindowID(for: provider, now: Self.now) == "claude-design")
    }

    @Test
    func `A followed window never borrows another window's chart`() throws {
        // Default lands on an extra weekly window while only the session is charted.
        let design = Self.window("claude-design", "Designs", used: 15, minutes: 10080, resetIn: 86400)
        let summary = try #require(CodexBarWidgetPaceSummary(
            provider: Self.provider("claude", [Self.claudeSession, design]),
            now: Self.now))
        #expect(summary.lanes.map(\.seriesName) == ["session"])
        let configured = summary.configured(windowID: nil)
        #expect(configured.windowID == "claude-design")
        #expect(configured.paceRemainingPercent == 85)
        #expect(configured.primaryLane == nil)
        #expect(configured.displayLanes.isEmpty)
        #expect(configured.hasChart == false)
        #expect(configured.namesWindow)
    }

    @Test
    func `Without a weekly window the Research 065 behavior is kept`() throws {
        // Monthly only: the native pace window, as before.
        let monthly = Self.provider("zai", [
            Self.window("primary", "Monthly", used: 25, minutes: 43200, resetIn: 10 * 86400),
        ])
        let summary = try #require(CodexBarWidgetPaceSummary(provider: monthly, now: Self.now))
        #expect(summary.configured(windowID: nil).windowID == "primary")
        #expect(summary.configured(windowID: nil).pace == QuotaPace(provider: monthly, referenceDate: Self.now))

        // A short window alone has nothing to show by default and stays out
        // of automatic selection; choosing it shows its remaining quota.
        let short = Self.provider("zai", [Self.window("primary", "5 hours", used: 50, minutes: 300, resetIn: 3600)])
        let shortSummary = try #require(CodexBarWidgetPaceSummary(provider: short, now: Self.now))
        #expect(shortSummary.configured(windowID: nil).hasDisplayableData == false)
        #expect(shortSummary.isAutomaticCandidate == false)
        let chosen = shortSummary.configured(windowID: "primary")
        #expect(chosen.hasDisplayableData)
        #expect(chosen.paceRemainingPercent == 50)
        #expect(chosen.pace == nil)
    }

    // MARK: Automatic selection

    private static func summary(_ provider: ProviderUsageSnapshot, account: String) throws
        -> CodexBarWidgetProviderSummary
    {
        try CodexBarWidgetProviderSummary(
            id: "\(provider.providerID)|\(account)",
            providerName: provider.providerName,
            providerID: provider.providerID,
            loginMethod: nil,
            usagePercent: nil,
            todayCostUSD: nil,
            thirtyDayCostUSD: nil,
            tokensToday: nil,
            isError: false,
            statusMessage: nil,
            lastUpdated: provider.lastUpdated,
            quotaPace: #require(CodexBarWidgetPaceSummary(provider: provider, now: self.now)))
    }

    @Test
    func `Automatic selection keeps the Research 065 data for every provider`() throws {
        let minimaxLike = Self.provider("minimax", [
            Self.window("primary", "5 hours", used: 30, minutes: 300, resetIn: 3600),
            Self.window("secondary", "Today", used: 60, minutes: 1440, resetIn: 6 * 3600),
            Self.window("tertiary", "Weekly", used: 20, minutes: 10080, resetIn: 4 * 86400),
        ])
        let codex = Self.provider("codex", [
            Self.window("primary", "Session", used: 10, minutes: 300, resetIn: 3600),
            Self.window("secondary", "Weekly", used: 30, minutes: 10080, resetIn: 86400),
        ])
        for provider in [codex, Self.claude(history: true), minimaxLike] {
            let summary = try #require(CodexBarWidgetPaceSummary(provider: provider, now: Self.now))
            // What the widget showed before window selection existed.
            let legacyWindow = try #require(QuotaPace.window(for: provider))
            #expect(summary.windowSource == .automatic)
            #expect(summary.pace == QuotaPace(provider: provider, referenceDate: Self.now))
            #expect(summary.paceRemainingPercent == 100 - legacyWindow.usedPercent)
            #expect(summary.paceResetsAt == legacyWindow.resetsAt)
            #expect(summary.isAutomaticCandidate)
        }
        // Configured, the MiniMax-like provider moves to its weekly window.
        let minimax = try #require(CodexBarWidgetPaceSummary(provider: minimaxLike, now: Self.now))
        #expect(minimax.windowID == "secondary")
        #expect(minimax.configured(windowID: nil).windowID == "tertiary")
        #expect(minimax.configured(windowID: nil).paceRemainingPercent == 80)
    }

    @Test
    func `Antigravity does not join automatic selection through an extra weekly window`() throws {
        // Claude with only a chart (weekly usage unknown, session charted).
        let unknownWeekly = Self.window("secondary", "Weekly", used: 0, minutes: 10080, resetIn: 86400, known: false)
        let chartOnly = try Self.summary(Self.provider("claude", [Self.claudeSession, unknownWeekly]), account: "a")
        let antigravity = try Self.summary(Self.provider("antigravity", Self.antigravityWindows), account: "a")
        #expect(antigravity.quotaPace?.pace == nil)
        #expect(antigravity.quotaPace?.isAutomaticCandidate == false)
        let picked = WidgetProviderSelection.pace(from: [antigravity, chartOnly], selected: nil, limit: 2)
        #expect(picked.map(\.providerID) == ["claude"])
        // Chosen by hand, Antigravity shows its default weekly window with a pace.
        let configured = WidgetProviderSelection.pace(
            from: [antigravity, chartOnly],
            selected: [WidgetProviderEntity(id: "antigravity", name: "Antigravity")],
            limit: 1,
            now: Self.now)
        #expect(configured.first?.quotaPace?.windowID == "antigravity-quota-summary-3p-weekly")
        #expect(configured.first?.quotaPace?.pace != nil)
    }

    @Test
    func `With several accounts the chosen window comes from the account that has it`() throws {
        // B has a charted weekly window and would outrank A on its default.
        let a = try Self.summary(Self.claude(), account: "a")
        let b = try Self.summary(
            Self.provider(
                "claude",
                [Self.claudeSession, Self.claudeWeekly],
                history: Self.claude(history: true)
                    .utilizationHistory),
            account: "b")
        let claude = [WidgetProviderEntity(id: "claude", name: "Claude")]
        for order in [[a, b], [b, a]] {
            let picked = WidgetProviderSelection.pace(
                from: order,
                selected: claude,
                limit: 1,
                windowChoice: "claude|claude-weekly-scoped-fable",
                now: Self.now)
            #expect(picked.first?.id == "claude|a")
            #expect(picked.first?.quotaPace?.windowID == "claude-weekly-scoped-fable")
            #expect(picked.first?.quotaPace?.hasChart == false)
        }
        // A window no account reports falls back to every account's default.
        let fallback = WidgetProviderSelection.pace(
            from: [a, b], selected: claude, limit: 1, windowChoice: "claude|gone", now: Self.now)
        #expect(fallback.first?.quotaPace?.windowID == "secondary")
    }

    // MARK: Choosing a window

    @Test
    func `A chosen window drives the pace, remaining quota and chart`() throws {
        let provider = Self.claude(history: true)
        let summary = try #require(CodexBarWidgetPaceSummary(provider: provider, now: Self.now))
        #expect(summary.primaryLane?.seriesName == "weekly")
        #expect(summary.configured(windowID: nil).primaryLane?.seriesName == "weekly")
        #expect(summary.configured(windowID: nil).displayLanes.map(\.seriesName) == ["session", "weekly"])
        #expect(summary.displayLanes.map(\.seriesName) == ["session", "weekly"])

        let session = summary.configured(windowID: "primary")
        #expect(session.isExplicitWindow)
        #expect(session.paceRemainingPercent == 80)
        #expect(session.pace == nil) // Pace needs a window of at least one day, as in the app.
        #expect(session.primaryLane?.seriesName == "session")
        #expect(session.displayLanes.map(\.seriesName) == ["session", "weekly"])
        #expect(session.selectedWindow?.title(providerID: "claude", locale: Locale(identifier: "en")) == "Session")

        let fable = summary.configured(windowID: "claude-weekly-scoped-fable")
        #expect(fable.paceRemainingPercent == 30)
        #expect(fable.paceResetsAt == Self.claudeFable.resetsAt)
        #expect(fable.pace == QuotaPace(
            window: Self.claudeFable,
            capturedAt: Self.captured,
            referenceDate: Self.now,
            providerID: "claude"))
        #expect(fable.pace?.trend == .ahead)
        // No observed history exists for a model-only window: no chart.
        #expect(fable.primaryLane == nil)
        #expect(fable.displayLanes.isEmpty)
        #expect(fable.selectedWindow?.title(providerID: "claude", locale: Locale(identifier: "zh-Hans")) == "仅 Fable")
    }

    private static func summaries(_ providers: [ProviderUsageSnapshot]) -> [CodexBarWidgetProviderSummary] {
        let source = SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: Self.captured,
            deviceName: "Fixture Mac",
            deviceID: "fixture")
        return CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [source], now: Self.now).topProviders
    }

    @Test
    func `The widget snapshot carries every window and the selection applies it`() throws {
        let providers = Self.summaries([Self.claude(), Self.provider("antigravity", Self.antigravityWindows)])
        let claudeSummary = try #require(providers.first { $0.providerID == "claude" })
        #expect(claudeSummary.quotaPace?.windows.map(\.id) == [
            "primary", "secondary", "claude-weekly-scoped-fable",
        ])
        let claude = [WidgetProviderEntity(id: "claude", name: "Claude")]
        let picked = WidgetProviderSelection.pace(
            from: providers,
            selected: claude,
            limit: 1,
            windowChoice: "claude|claude-weekly-scoped-fable",
            now: Self.now)
        #expect(picked.first?.quotaPace?.windowID == "claude-weekly-scoped-fable")
        #expect(picked.first?.quotaPace?.paceRemainingPercent == 30)

        let antigravity = [WidgetProviderEntity(id: "antigravity", name: "Antigravity")]
        let pickedModel = WidgetProviderSelection.pace(
            from: providers,
            selected: antigravity,
            limit: 1,
            windowChoice: "antigravity|gemini-3-pro-image",
            now: Self.now)
        #expect(pickedModel.first?.quotaPace?.windowID == "gemini-3-pro-image")
        #expect(pickedModel.first?.quotaPace?.paceRemainingPercent == 50)
    }

    @Test
    func `A vanished or foreign choice falls back to the weekly window`() {
        let providers = Self.summaries([Self.claude()])
        let claude = [WidgetProviderEntity(id: "claude", name: "Claude")]
        for choice in [
            "claude|claude-weekly-scoped-retired",
            "codex|primary",
            QuotaPaceWindowChoice.defaultIdentifier,
        ] {
            let picked = WidgetProviderSelection.pace(
                from: providers, selected: claude, limit: 1, windowChoice: choice, now: Self.now)
            #expect(picked.first?.quotaPace?.windowID == "secondary")
            #expect(picked.first?.quotaPace?.isExplicitWindow == false)
        }
        // Automatic provider selection ignores the choice.
        let automatic = WidgetProviderSelection.pace(
            from: providers, selected: nil, limit: 1, windowChoice: "claude|primary", now: Self.now)
        #expect(automatic.first?.quotaPace?.windowID == "secondary")
        #expect(automatic.first?.quotaPace?.windowSource == .automatic)
    }

    @Test
    func `A chosen window without data shows the provider as unavailable`() {
        let provider = Self.provider("antigravity", Self.antigravityWindows)
        let providers = Self.summaries([provider])
        let picked = WidgetProviderSelection.pace(
            from: providers,
            selected: [WidgetProviderEntity(id: "antigravity", name: "Antigravity")],
            limit: 1,
            windowChoice: "antigravity|antigravity-claude-gpt",
            now: Self.now)
        #expect(picked.first?.providerID == "antigravity")
        #expect(picked.first?.quotaPace == nil)
    }

    // MARK: Compatibility

    @Test
    func `Choice identifiers are scoped to their provider`() {
        let id = QuotaPaceWindowChoice.identifier(providerID: "claude", windowID: "claude-weekly-scoped-fable")
        #expect(QuotaPaceWindowChoice.windowID(from: id, providerID: "claude") == "claude-weekly-scoped-fable")
        #expect(QuotaPaceWindowChoice.windowID(from: id, providerID: "codex") == nil)
        #expect(QuotaPaceWindowChoice.windowID(from: nil, providerID: "claude") == nil)
        #expect(QuotaPaceWindowChoice
            .windowID(from: QuotaPaceWindowChoice.defaultIdentifier, providerID: "claude") == nil)
        #expect(QuotaPaceWindowChoice.windowID(from: "claude|", providerID: "claude") == nil)
    }

    @Test
    func `Widgets added before the window parameter keep the default`() {
        // Such widgets keep their stored schema and never carry the parameter.
        let legacy = SelectQuotaPaceWidgetIntent()
        legacy.provider = StatusWidgetProvider(identifier: "claude", display: "Claude")
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(from: legacy) == nil)

        let defaulted = SelectQuotaPaceWidgetIntent()
        defaulted.quotaWindow = QuotaPaceWindowOption(
            identifier: QuotaPaceWindowChoice.defaultIdentifier,
            display: "Default (Weekly)")
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(from: defaulted) == nil)

        let chosen = SelectQuotaPaceWidgetIntent()
        chosen.provider = StatusWidgetProvider(identifier: "claude", display: "Claude")
        chosen.quotaWindow = QuotaPaceWindowOption(identifier: "claude|primary", display: "Session")
        #expect(StatusWidgetConfigurationAdapter.paceWindowChoice(from: chosen) == "claude|primary")
        #expect(StatusWidgetConfigurationAdapter.configuration(from: chosen).providers?.map(\.id) == ["claude"])
    }

    @Test
    func `Pace summaries encoded before window selection still decode`() throws {
        let summary = try #require(CodexBarWidgetPaceSummary(provider: Self.claude(), now: Self.now))
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        for key in ["windows", "windowID", "windowSource", "automaticWindowID", "defaultWindowID"] {
            object.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(
            CodexBarWidgetPaceSummary.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.windows.isEmpty)
        #expect(legacy.windowID == nil)
        #expect(legacy.paceRemainingPercent == 60)
        #expect(legacy.windowSource == .automatic)
        #expect(legacy.configured(windowID: "primary").windowID == nil)
    }

    @Test
    func `The placeholder offers Claude's three windows for previews`() throws {
        let claude = try #require(CodexBarWidgetSnapshot.placeholder(now: Self.now).topProviders
            .first { $0.providerID == "claude" })
        #expect(claude.quotaPace?.windows.map(\.id) == ["primary", "secondary", "claude-weekly-scoped-fable"])
        #expect(claude.quotaPace?.windowID == "secondary")
        #expect(claude.quotaPace?.configured(windowID: "claude-weekly-scoped-fable").paceRemainingPercent == 29)
    }
}
