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
        let record = WidgetActivityPublisher.catalogueEntities(from: [provider]).first
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
        // An unlabeled weekly window is named by its length, not its slot.
        #expect(QuotaPaceWindowSelection.catalogueWindows(for: muse).first?.titles?["en"] == "Weekly")
        #expect(QuotaPaceWindowSelection.catalogueWindows(for: muse).first?.titles?["zh-Hans"] == "每周")
        // Same wording as a labeled "Weekly" window.
        #expect(QuotaPaceWindowSelection.catalogueWindows(for: muse).first?.titles?["ja"] == "週次")
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
    }

    // MARK: Default window

    @Test
    func `Without a choice every provider follows its weekly window`() throws {
        let claude = try #require(CodexBarWidgetPaceSummary(provider: Self.claude(), now: Self.now))
        #expect(claude.windowID == "secondary")
        #expect(claude.isExplicitWindow == false)
        #expect(claude.paceRemainingPercent == 60)
        // Same pace as the provider detail page's pace badge.
        #expect(claude.pace == QuotaPace(provider: Self.claude(), referenceDate: Self.now))

        let codex = Self.provider("codex", [
            Self.window("primary", "Weekly", used: 30, minutes: 10080, resetIn: 86400),
        ])
        #expect(CodexBarWidgetPaceSummary(provider: codex, now: Self.now)?.windowID == "primary")

        // Antigravity has no native slot; its first weekly window is the default.
        let antigravity = try #require(CodexBarWidgetPaceSummary(
            provider: Self.provider("antigravity", Self.antigravityWindows),
            now: Self.now))
        #expect(antigravity.windowID == "antigravity-quota-summary-gemini-weekly")
        #expect(antigravity.pace != nil)
        #expect(antigravity.paceRemainingPercent == 70)
        #expect(antigravity.isAutomaticCandidate)
    }

    @Test
    func `Without a weekly window the Research 065 behavior is kept`() throws {
        // Monthly only: the native pace window, as before.
        let monthly = Self.provider("zai", [
            Self.window("primary", "Monthly", used: 25, minutes: 43200, resetIn: 10 * 86400),
        ])
        let summary = try #require(CodexBarWidgetPaceSummary(provider: monthly, now: Self.now))
        #expect(summary.windowID == "primary")
        #expect(summary.pace == QuotaPace(provider: monthly, referenceDate: Self.now))

        // A short window alone has nothing to show by default and stays out
        // of automatic selection, but remains choosable.
        let short = Self.provider("zai", [Self.window("primary", "5 hours", used: 50, minutes: 300, resetIn: 3600)])
        let shortSummary = try #require(CodexBarWidgetPaceSummary(provider: short, now: Self.now))
        #expect(shortSummary.windowID == nil)
        #expect(shortSummary.hasDisplayableData == false)
        #expect(shortSummary.isAutomaticCandidate == false)
        let chosen = shortSummary.selecting(windowID: "primary")
        #expect(chosen.hasDisplayableData)
        #expect(chosen.paceRemainingPercent == 50)
        #expect(chosen.pace == nil)
    }

    // MARK: Choosing a window

    @Test
    func `A chosen window drives the pace, remaining quota and chart`() throws {
        let provider = Self.claude(history: true)
        let summary = try #require(CodexBarWidgetPaceSummary(provider: provider, now: Self.now))
        #expect(summary.primaryLane?.seriesName == "weekly")
        #expect(summary.displayLanes.map(\.seriesName) == ["session", "weekly"])

        let session = summary.selecting(windowID: "primary")
        #expect(session.isExplicitWindow)
        #expect(session.paceRemainingPercent == 80)
        #expect(session.pace == nil) // Pace needs a window of at least one day, as in the app.
        #expect(session.primaryLane?.seriesName == "session")
        #expect(session.displayLanes.map(\.seriesName) == ["session", "weekly"])
        #expect(session.selectedWindow?.title(providerID: "claude", locale: Locale(identifier: "en")) == "Session")

        let fable = summary.selecting(windowID: "claude-weekly-scoped-fable")
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
        // Automatic provider selection always uses the default window.
        let automatic = WidgetProviderSelection.pace(
            from: providers, selected: nil, limit: 1, windowChoice: "claude|primary", now: Self.now)
        #expect(automatic.first?.quotaPace?.windowID == "secondary")
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
        for key in ["windows", "windowID", "isExplicitWindow"] {
            object.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(
            CodexBarWidgetPaceSummary.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.windows.isEmpty)
        #expect(legacy.windowID == nil)
        #expect(legacy.paceRemainingPercent == 60)
        #expect(legacy.selecting(windowID: "primary") == legacy)
    }

    @Test
    func `The placeholder offers Claude's three windows for previews`() throws {
        let claude = try #require(CodexBarWidgetSnapshot.placeholder(now: Self.now).topProviders
            .first { $0.providerID == "claude" })
        #expect(claude.quotaPace?.windows.map(\.id) == ["primary", "secondary", "claude-weekly-scoped-fable"])
        #expect(claude.quotaPace?.windowID == "secondary")
        #expect(claude.quotaPace?.selecting(windowID: "claude-weekly-scoped-fable").paceRemainingPercent == 29)
    }
}
