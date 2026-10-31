import CodexBarSync
import Foundation
import Intents
import SwiftUI
import Testing
import WidgetKit
@testable import CodexBarMobile

/// Issue #223 — the overview widget chooses a quota window per provider slot
/// and can count used or remaining quota.
@Suite("Overview widget quota windows")
struct OverviewQuotaWindowTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Fictional Claude account: Session 80% (resets in 1 hour), Weekly 35%.
    private static func claude() -> CodexBarWidgetProviderSummary {
        let windows = [
            SyncRateWindow(
                id: "primary", label: "Session", usedPercent: 80, windowMinutes: 300,
                resetsAt: Self.now.addingTimeInterval(3600), resetDescription: nil),
            SyncRateWindow(
                id: "secondary", label: "Weekly", usedPercent: 35, windowMinutes: 10080,
                resetsAt: Self.now.addingTimeInterval(50 * 3600), resetDescription: nil),
        ]
        let provider = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: nil, secondary: nil,
            accountEmail: "fictional@example.invalid", loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: Self.now, rateWindows: windows)
        return CodexBarWidgetSnapshotBuilder.summary(for: provider, now: Self.now)
    }

    private static func summary(
        _ id: String, name: String, windows: [SyncRateWindow]) -> CodexBarWidgetProviderSummary
    {
        CodexBarWidgetSnapshotBuilder.summary(for: ProviderUsageSnapshot(
            providerID: id, providerName: name, primary: nil, secondary: nil,
            accountEmail: "\(id)@example.invalid", loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: Self.now, rateWindows: windows), now: Self.now)
    }

    /// Claude on its session, Codex and Kiro on their defaults: the issue's widget.
    @MainActor
    @Test(arguments: [WidgetOverviewQuotaDisplay.used, .remaining])
    func `mixed windows render with a label on every tile`(display: WidgetOverviewQuotaDisplay) throws {
        let codex = Self.summary("codex", name: "Codex", windows: [
            SyncRateWindow(
                id: "secondary", label: "Weekly", usedPercent: 41, windowMinutes: 10080,
                resetsAt: Self.now.addingTimeInterval(80 * 3600), resetDescription: nil),
        ])
        let kiro = Self.summary("kiro", name: "Kiro", windows: [
            SyncRateWindow(
                id: "primary", label: "Credits", usedPercent: 12, windowMinutes: nil,
                resetsAt: Self.now.addingTimeInterval(9 * 86400), resetDescription: nil),
        ])
        let providers = [Self.claude(), codex, kiro]
        let snapshot = CodexBarWidgetSnapshot(
            state: .loaded, generatedAt: Self.now, latestSyncAt: Self.now, deviceCount: 1,
            providerCount: providers.count, errorCount: 0, todayCostUSD: nil, thirtyDayCostUSD: nil,
            todayTokens: nil, maxUsagePercent: 80, topProviders: providers, message: nil, isStale: false)
        let entry = CodexBarWidgetEntry(
            date: Self.now,
            configuration: .init(
                mode: .overview, colorStyle: .colorful,
                providers: providers.map { WidgetProviderEntity(id: $0.providerID, name: $0.providerName) }),
            snapshot: snapshot,
            overviewQuota: WidgetOverviewQuotaOptions(windowChoices: ["claude|primary"], display: display))
        let directory = ProcessInfo.processInfo.environment["CODEXBAR_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
        let families: [(WidgetFamily, CGSize)] = [
            (.systemSmall, .init(width: 170, height: 170)),
            (.systemMedium, .init(width: 364, height: 170)),
            (.systemLarge, .init(width: 364, height: 382)),
        ]
        for (family, size) in families {
            for scheme in [ColorScheme.light, .dark] {
                let view = CodexBarWidgetView(entry: entry, previewFamily: family)
                    .environment(\.colorScheme, scheme)
                    .frame(width: size.width, height: size.height)
                    .background(scheme == .dark ? Color.black : Color.white)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let image = try #require(renderer.uiImage)
                #expect(image.size == size)
                if let directory {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try #require(image.pngData()).write(to: directory.appendingPathComponent(
                        "overview-\(display)-\(family)-\(scheme).png"))
                }
            }
        }
    }

    @Test func `a chosen session window replaces the weekly figures and names itself`() {
        let summary = Self.claude()
        let weekly = WidgetProviderSelection.overviewFigures(for: summary, selection: .manual, now: Self.now)
        #expect(weekly.usagePercent == 35)
        #expect(weekly.resetsAt == Self.now.addingTimeInterval(50 * 3600))
        #expect(weekly.windowTitle == String(localized: "Weekly"))

        let session = WidgetProviderSelection.overviewFigures(
            for: summary, selection: .manual, windowID: "primary", now: Self.now)
        #expect(session.usagePercent == 80)
        #expect(session.resetsAt == Self.now.addingTimeInterval(3600))
        #expect(session.windowTitle == summary.quotaPace?.windows.first { $0.id == "primary" }?
            .widgetTitle(providerID: "claude"))
        #expect(session.windowTitle != weekly.windowTitle)

        // A window the provider no longer reports keeps the weekly figures.
        let gone = WidgetProviderSelection.overviewFigures(
            for: summary, selection: .manual, windowID: "retired", now: Self.now)
        #expect(gone.usagePercent == 35 && gone.windowTitle == weekly.windowTitle)
    }

    @Test func `a provider without a weekly window names its fractional most-used window`() {
        let kiro = Self.summary("kiro", name: "Kiro", windows: [
            SyncRateWindow(
                id: "primary", label: "Credits", usedPercent: 12.3, windowMinutes: nil,
                resetsAt: Self.now.addingTimeInterval(9 * 86400), resetDescription: nil),
        ])
        let figures = WidgetProviderSelection.overviewFigures(for: kiro, selection: .manual, now: Self.now)
        #expect(figures.usagePercent == 12.3)
        #expect(figures.windowTitle == kiro.quotaPace?.windows.first?.widgetTitle(providerID: "kiro"))
        #expect(figures.windowTitle != nil)
    }

    @Test func `a session that reset after the last sync shows no stale usage`() {
        let later = Self.now.addingTimeInterval(2 * 3600)
        let session = WidgetProviderSelection.overviewFigures(
            for: Self.claude(), selection: .manual, windowID: "primary", now: later)
        #expect(session.usagePercent == nil)
        #expect(session.resetsAt == nil)
        #expect(session.windowTitle != nil)
    }

    @Test func `window choices resolve per provider and ignore other providers`() {
        let options = WidgetOverviewQuotaOptions(windowChoices: ["claude|primary", "codex|secondary"])
        #expect(options.windowID(for: "claude") == "primary")
        #expect(options.windowID(for: "codex") == "secondary")
        #expect(options.windowID(for: "kiro") == nil)
        #expect(WidgetOverviewQuotaOptions().display == .used)
    }

    @Test func `SiriKit slots keep only windows of their own provider`() {
        let intent = SelectStatusWidgetIntent()
        intent.provider1 = StatusWidgetProvider(identifier: "claude", display: "Claude")
        intent.window1 = QuotaPaceWindowOption(identifier: "claude|primary", display: "Session")
        // Slot 2 changed provider after a Claude window was chosen: the stale choice is dropped.
        intent.provider2 = StatusWidgetProvider(identifier: "codex", display: "Codex")
        intent.window2 = QuotaPaceWindowOption(identifier: "claude|secondary", display: "Weekly")
        intent.provider3 = StatusWidgetProvider(identifier: "kiro", display: "Kiro")
        intent.window3 = QuotaPaceWindowOption(
            identifier: QuotaPaceWindowChoice.defaultIdentifier, display: "Default (Weekly)")
        intent.quotaDisplay = .remaining
        let quota = StatusWidgetConfigurationAdapter.overviewQuota(from: intent)
        #expect(quota.windowChoices == ["claude|primary"])
        #expect(quota.display == .remaining)

        // Widgets placed before issue #223 keep weekly usage.
        let legacy = StatusWidgetConfigurationAdapter.overviewQuota(from: SelectStatusWidgetIntent())
        #expect(legacy == WidgetOverviewQuotaOptions())
    }

    @available(iOS 27.0, *)
    @Test func `App Intents slots read the same choices as SiriKit`() {
        let intent = StatusWidgetAppIntent(
            mode: .overview,
            providers: [
                StatusWidgetProviderAppEntity(id: "claude", displayString: "Claude"),
                StatusWidgetProviderAppEntity(id: "codex", displayString: "Codex"),
            ],
            quotaDisplay: .remaining,
            windows: [
                QuotaPaceWindowOptionAppEntity(id: "claude|primary", displayString: "Session"),
                QuotaPaceWindowOptionAppEntity(id: "claude|secondary", displayString: "Weekly"),
            ])
        let quota = StatusWidgetConfigurationAdapter.overviewQuota(from: intent)
        #expect(quota.windowChoices == ["claude|primary"])
        #expect(quota.display == .remaining)
        #expect(StatusWidgetConfigurationAdapter.overviewQuota(from: StatusWidgetAppIntent()) == .init())
    }
}
