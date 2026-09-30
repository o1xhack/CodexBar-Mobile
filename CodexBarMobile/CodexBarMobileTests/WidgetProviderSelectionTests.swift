import CodexBarSync
import SwiftUI
import WidgetKit
import XCTest
@testable import CodexBarMobile

@MainActor
final class WidgetProviderSelectionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAutomaticDefaultsAndExplicitSelection() {
        let providers = CodexBarWidgetSnapshot.placeholder(now: self.now).topProviders
        XCTAssertEqual(
            WidgetProviderSelection.resolve(from: providers, selected: nil, family: .systemSmall, now: self.now).count,
            2)
        XCTAssertEqual(
            WidgetProviderSelection.resolve(from: providers, selected: [], family: .systemMedium, now: self.now).count,
            4)
        let selected = [
            WidgetProviderEntity(id: "claude", name: "Claude"),
            WidgetProviderEntity(id: "codex", name: "Codex"),
        ]
        XCTAssertEqual(
            WidgetProviderSelection.resolve(from: providers, selected: selected, family: .systemLarge, now: self.now)
                .map(\.providerID),
            ["claude", "codex"])
        XCTAssertEqual(
            WidgetProviderSelection
                .resolve(from: providers, selected: selected + selected, family: .systemSmall, now: self.now).count,
            2)
    }

    func testSelectionCapsAtFourAndThreeSmallItemsUseTwoColumns() {
        let providers = CodexBarWidgetSnapshot.placeholder(now: self.now).topProviders
        let selected = providers.map { WidgetProviderEntity(id: $0.providerID, name: $0.providerName) }
            + [WidgetProviderEntity(id: "fifth", name: "Fifth")]
        let result = WidgetProviderSelection.resolve(
            from: providers,
            selected: selected,
            family: .systemSmall,
            now: self.now)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map(\.providerID), Array(selected.prefix(4)).map(\.id))
        XCTAssertEqual(WidgetProviderSelection.columns(count: 3, family: .systemSmall), 2)
        XCTAssertEqual(WidgetProviderSelection.columns(count: 2, family: .systemSmall), 1)
    }

    func testMissingProviderNeverSubstitutesAnotherProvider() {
        let providers = CodexBarWidgetSnapshot.placeholder(now: self.now).topProviders
        let result = WidgetProviderSelection.resolve(
            from: providers,
            selected: [.init(id: "missing", name: "Missing")],
            family: .systemMedium,
            now: self.now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.providerID, "missing")
        XCTAssertNil(result.first?.usagePercent)
        XCTAssertNil(result.first?.resetsAt)
    }

    func testResetCountdownIsFractionalAndNeverNegative() {
        XCTAssertNil(WidgetProviderResetText.days(nil, now: self.now))
        XCTAssertEqual(
            WidgetProviderResetText.days(self.now.addingTimeInterval(3.7 * 86400), now: self.now),
            String(format: String(localized: "%@d"), "3.7"))
        XCTAssertEqual(
            WidgetProviderResetText.days(self.now.addingTimeInterval(0.6 * 86400), now: self.now),
            String(format: String(localized: "%@d"), "0.6"))
        XCTAssertEqual(
            WidgetProviderResetText.days(self.now.addingTimeInterval(60), now: self.now),
            String(localized: "<0.1d"))
        XCTAssertEqual(
            WidgetProviderResetText.days(self.now.addingTimeInterval(-1), now: self.now),
            String(localized: "Now"))
    }

    func testUsageAndResetComeFromTheSameKnownWindow() {
        let firstReset = self.now.addingTimeInterval(86400)
        let secondReset = self.now.addingTimeInterval(3.7 * 86400)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: firstReset, resetDescription: nil),
            secondary: SyncRateWindow(
                usedPercent: 70,
                windowMinutes: 10080,
                resetsAt: secondReset,
                resetDescription: nil),
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now)
        let source = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Fixture Mac",
            deviceID: "fixture")
        let summary = CodexBarWidgetSnapshotBuilder.makeSnapshot(from: [source], now: self.now).topProviders.first
        XCTAssertEqual(summary?.usagePercent, 70)
        XCTAssertEqual(summary?.resetsAt, secondReset)
    }

    func testLegacySummaryDecodesWithoutResetAndCatalogueRoundTrips() throws {
        let summary = CodexBarWidgetSnapshot.placeholder(now: self.now).topProviders[0]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        object.removeValue(forKey: "resetsAt")
        let legacy = try JSONDecoder().decode(
            CodexBarWidgetProviderSummary.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.resetsAt)
        let directory = URL(
            fileURLWithPath: "/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/WidgetOverview224-fixtures",
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("catalogue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try WidgetProviderCatalogue.write(
            [.init(id: "codex", name: "Codex"), .init(id: "codex", name: "Codex")],
            to: url)
        XCTAssertEqual(try WidgetProviderCatalogue.read(from: url).map(\.id), ["codex"])
    }

    func testOverviewSelectionLayoutsRenderAndExport() throws {
        let snapshot = CodexBarWidgetSnapshot.placeholder(now: self.now)
        let choices = snapshot.topProviders.map { WidgetProviderEntity(id: $0.providerID, name: $0.providerName) }
        let families: [(WidgetFamily, CGSize)] = [
            (.systemSmall, .init(width: 158, height: 158)),
            (.systemMedium, .init(width: 338, height: 162)),
            (.systemLarge, .init(width: 338, height: 354)),
            (.systemExtraLarge, .init(width: 560, height: 274)),
        ]
        for (family, size) in families {
            for count in 1...4 {
                for scheme in [ColorScheme.light, .dark] {
                    for style in [CodexBarWidgetColorStyle.mono, .colorful] {
                        let view = CodexBarWidgetView(
                            entry: .init(
                                date: now,
                                configuration: .init(
                                    mode: .overview,
                                    colorStyle: style,
                                    providers: Array(choices.prefix(count))),
                                snapshot: snapshot),
                            previewFamily: family)
                            .environment(\.colorScheme, scheme)
                            .frame(width: size.width, height: size.height)
                            .background(scheme == .dark ? Color.black : Color.white)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        let image = try XCTUnwrap(renderer.uiImage)
                        XCTAssertEqual(image.size.width, size.width)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "Overview-\(family)-\(count)-\(scheme)-\(style)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }
}
