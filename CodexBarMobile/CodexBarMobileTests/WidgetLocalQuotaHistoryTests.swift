import CodexBarSync
import Foundation
import SwiftUI
import Testing
import WidgetKit
@testable import CodexBarMobile

@Suite("Quota Pace widget charts from the phone's own readings")
struct WidgetLocalQuotaHistoryTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let reset = Self.now.addingTimeInterval(5 * 86400)

    private static func grok(email: String? = nil, used: Double = 40) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "grok", providerName: "Grok", primary: nil, secondary: nil,
            accountEmail: email, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: Self.now.addingTimeInterval(-60),
            rateWindows: [SyncRateWindow(
                usedPercent: used, windowMinutes: nil, resetsAt: Self.reset, resetDescription: nil)])
    }

    private static func history(
        providerID: String = "grok", windowID: String = "primary", reset: Date = Self.reset,
        used: [Double] = [10, 20, 30]) -> WidgetLocalQuotaHistory
    {
        WidgetLocalQuotaHistory(streams: [WidgetLocalQuotaHistory.Stream(
            providerID: providerID,
            windowID: windowID,
            windowDuration: 7 * 86400,
            entries: used.enumerated().map { index, percent in
                SyncUtilizationEntry(
                    capturedAt: Self.now.addingTimeInterval(Double(index - used.count) * 3600),
                    usedPercent: percent,
                    resetsAt: reset)
            })])
    }

    private static func pace(
        _ providers: [ProviderUsageSnapshot], history: WidgetLocalQuotaHistory?,
        linkages: [ProviderAccountLinkage] = []) -> CodexBarWidgetPaceSummary?
    {
        let snapshot = SyncedUsageSnapshot(
            providers: providers, syncTimestamp: Self.now.addingTimeInterval(-60),
            deviceName: "Fictional Mac", deviceID: "fictional-mac")
        return CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: [snapshot], providerLinkages: linkages, localHistory: history, now: Self.now)
            .topProviders.first { $0.providerID == "grok" }?.quotaPace
    }

    @Test
    func `a single account provider gets a chart from verified local readings`() throws {
        let windowID = try #require(QuotaPaceWindowSelection.candidates(for: Self.grok()).first?.id)
        let pace = try #require(Self.pace([Self.grok()], history: Self.history(windowID: windowID)))
        let lane = try #require(pace.lanes.first)
        #expect(pace.lanes.count == 1)
        #expect(lane.seriesName == "local:\(windowID)")
        #expect(lane.points.map(\.remainingPercent) == [90, 80, 70, 60])
        #expect(lane.start == Self.reset.addingTimeInterval(-7 * 86400))
        #expect(lane.reset == Self.reset)
        #expect(pace.windows.first?.laneSeriesName == lane.seriesName)
        #expect(pace.hasChart)

        let configured = pace.configured(windowID: windowID)
        #expect(configured.primaryLane == lane)
        #expect(configured.hasChart)
        // Without a choice (Grok's window is not recognisably weekly) the chart is the default.
        let unchosen = pace.configured(windowID: nil)
        #expect(unchosen.primaryLane == lane)
        #expect(unchosen.paceRemainingPercent == 60)
    }

    @Test
    func `readings without a single owner or from another cycle draw no chart`() throws {
        let windowID = try #require(QuotaPaceWindowSelection.candidates(for: Self.grok()).first?.id)
        let second = Self.grok(email: "second@example.com", used: 70)
        #expect(Self.pace([Self.grok(), second], history: Self.history(windowID: windowID))?.lanes.isEmpty == true)

        // The app was not running to withdraw the readings: the widget itself refuses a
        // replacement account that has a name or a credential slot, or a linked provider.
        #expect(Self.pace([second], history: Self.history(windowID: windowID))?.lanes.isEmpty == true)
        let slotted = ProviderUsageSnapshot(
            providerID: "grok", providerName: "Grok", primary: nil, secondary: nil, accountEmail: nil,
            loginMethod: nil, statusMessage: nil, isError: false, lastUpdated: Self.now.addingTimeInterval(-60),
            rateWindows: Self.grok().rateWindows, accountRecordKey: "install-b")
        #expect(Self.pace([slotted], history: Self.history(windowID: windowID))?.lanes.isEmpty == true)
        let link = ProviderAccountLinkage(
            providerID: "grok", linkedIdentifiers: ["grok:account:other", "grok:legacy-no-identity"],
            confirmedFromDeviceID: "fictional-phone")
        #expect(Self.pace([Self.grok()], history: Self.history(windowID: windowID), linkages: [link])?
            .lanes.isEmpty == true)

        let oldCycle = Self.history(windowID: windowID, reset: Self.reset.addingTimeInterval(-7 * 86400))
        #expect(Self.pace([Self.grok()], history: oldCycle)?.lanes.isEmpty == true)

        // A usage drop is a replenishment: only the current reading remains.
        let dropped = Self.history(windowID: windowID, used: [10, 60])
        #expect(Self.pace([Self.grok()], history: dropped)?.lanes.isEmpty == true)

        #expect(Self.pace([Self.grok()], history: Self.history(windowID: "other"))?.lanes.isEmpty == true)
        #expect(Self.pace([Self.grok()], history: nil)?.lanes.isEmpty == true)
    }

    /// Writes PNGs when `CODEXBAR_RENDER_DIR` is set, for a visual check.
    @MainActor
    @Test
    func `the Quota Pace widget draws the local Grok curve in every size`() throws {
        let windowID = try #require(QuotaPaceWindowSelection.candidates(for: Self.grok()).first?.id)
        let readings = [2.0, 4, 9, 11, 17, 22, 26, 31, 35]
        let history = WidgetLocalQuotaHistory(streams: [WidgetLocalQuotaHistory.Stream(
            providerID: "grok", windowID: windowID, windowDuration: 7 * 86400,
            entries: readings.enumerated().map { index, percent in
                SyncUtilizationEntry(
                    capturedAt: Self.now.addingTimeInterval(Double(index - readings.count) * 5 * 3600),
                    usedPercent: percent, resetsAt: Self.reset)
            })])
        let synced = SyncedUsageSnapshot(
            providers: [Self.grok()], syncTimestamp: Self.now.addingTimeInterval(-60),
            deviceName: "Fictional Mac", deviceID: "fictional-mac")
        let snapshot = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [synced], localHistory: history, now: Self.now)
        #expect(snapshot.topProviders.first?.quotaPace?.lanes.first?.points.count == readings.count + 1)
        let entry = CodexBarWidgetEntry(
            date: Self.now,
            configuration: .init(
                mode: .quotaPace, colorStyle: .colorful,
                providers: [WidgetProviderEntity(id: "grok", name: "Grok")]),
            snapshot: snapshot)
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
                        "grok-pace-\(family)-\(scheme).png"))
                }
            }
        }
    }

    @Test
    func `the current reading stamped earlier by the app is not a second point`() throws {
        let windowID = try #require(QuotaPaceWindowSelection.candidates(for: Self.grok()).first?.id)
        let duplicate = Self.history(windowID: windowID, used: [20, 40])
        let lane = try #require(Self.pace([Self.grok()], history: duplicate)?.lanes.first)
        #expect(lane.points.map(\.remainingPercent) == [80, 60])
        #expect(lane.points.last?.date == Self.now.addingTimeInterval(-60))

        let onlyCurrent = Self.history(windowID: windowID, used: [40])
        #expect(Self.pace([Self.grok()], history: onlyCurrent)?.lanes.isEmpty == true)
    }

    @Test
    func `a local chart never drives automatic selection or ranking`() throws {
        let windowID = try #require(QuotaPaceWindowSelection.candidates(for: Self.grok()).first?.id)
        let pace = try #require(Self.pace([Self.grok()], history: Self.history(windowID: windowID)))
        #expect(pace.hasChart)
        #expect(!pace.hasPublishedChart)
        #expect(pace.isAutomaticCandidate == (pace.pace != nil))
        #expect(!pace.configured(windowID: nil).hasPublishedChart)
    }

    @Test
    func `providers with Mac lanes never take local readings`() {
        #expect(!WidgetLocalQuotaHistory.appliesTo(providerID: "codex"))
        #expect(!WidgetLocalQuotaHistory.appliesTo(providerID: "claude"))
        #expect(WidgetLocalQuotaHistory.appliesTo(providerID: "grok"))
    }

    @Test
    func `the shared file round trips and rejects another schema`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetLocalQuotaHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(WidgetLocalQuotaHistoryStore.filename)
        let history = Self.history()
        try WidgetLocalQuotaHistoryStore.write(history, to: url)
        #expect(WidgetLocalQuotaHistoryStore.read(from: url) == history)

        var future = history
        future.version = WidgetLocalQuotaHistory.schemaVersion + 1
        try WidgetLocalQuotaHistoryStore.write(future, to: url)
        #expect(WidgetLocalQuotaHistoryStore.read(from: url) == nil)
        #expect(WidgetLocalQuotaHistoryStore.read(from: directory.appendingPathComponent("missing.json")) == nil)
    }
}
