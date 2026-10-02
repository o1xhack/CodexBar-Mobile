import CodexBarSync
import Foundation
import Testing
import UIKit
@testable import CodexBarMobile

@Suite("v0.70 observation-based presentation")
struct V070PresentationTests {
    private let captured = Date(timeIntervalSince1970: 1_791_000_000)

    private func window(
        percent: Double = 25,
        known: Bool = true,
        synthetic: Bool = false,
        blocking: SyncBlockingQuota? = nil) -> SyncRateWindow
    {
        .init(
            usedPercent: percent,
            usageKnown: known,
            windowMinutes: 60,
            resetsAt: self.captured.addingTimeInterval(1800),
            resetDescription: nil,
            isSyntheticPlaceholder: synthetic,
            blockingQuota: blocking)
    }

    @Test func `Upstream grouped windows and fixed labels localize in four languages`() {
        for (language, weekly, session, monthly, fuel) in [
            ("en", "Weekly", "Session", "Monthly Plan", "Fuel Pack"),
            ("zh-Hans", "每周", "当前周期", "月度套餐", "加量包"),
            ("zh-Hant", "每週", "當前週期", "每月方案", "加量包"),
            ("ja", "週間", "セッション", "月次プラン", "追加パック"),
        ] {
            let locale = Locale(identifier: language)
            #expect(ProviderWindowLabel.localized(
                "Fixture Model weekly", fallback: "", providerID: "antigravity", locale: locale)
                == "Fixture Model · " + weekly)
            #expect(ProviderWindowLabel.localized("Monthly Plan", fallback: "", locale: locale) == monthly)
            #expect(ProviderWindowLabel.localized("Fuel Pack", fallback: "", locale: locale) == fuel)
            #expect(ProviderDetailLocalization.localized("Session", providerID: "codex", locale: locale) == session)
        }
    }

    @Test func `Every updated brand remains readable in both modes and preserves synced fallback consistency`() {
        #expect(ProviderColorPalette.upstreamV070BrandTints.count == 16)
        for (provider, hex) in ProviderColorPalette.upstreamV070BrandTints {
            let fallback = UIColor(ProviderColorPalette.color(for: provider))
            let synced = UIColor(ProviderColorPalette.color(for: provider, tintHex: hex))
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                let resolved = fallback.resolvedColor(with: traits)
                let expected = synced.resolvedColor(with: traits)
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                #expect(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                let luminance = ProviderColorPalette.relativeLuminance(red: red, green: green, blue: blue)
                if style == .light {
                    #expect(luminance <= ProviderColorPalette.maximumSyncedLightModeLuminance + 0.001)
                } else {
                    #expect(luminance >= ProviderColorPalette.minimumDarkModeLuminance - 0.001)
                }
                var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
                #expect(expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea))
                #expect(abs(red - er) + abs(green - eg) + abs(blue - eb) < 0.001)
            }
        }
    }

    @Test func `Advancing the quota clock admits a fresh capture and expires it at reset`() {
        let window = self.window()
        #expect(MobileQuotaBurndown(
            series: nil,
            window: window,
            capturedAt: self.captured,
            referenceDate: self.captured.addingTimeInterval(-60)) == nil)
        let fresh = MobileQuotaBurndown(
            series: nil,
            window: window,
            capturedAt: self.captured,
            referenceDate: self.captured.addingTimeInterval(60))
        #expect(fresh?.samples.last?.date == self.captured)
        #expect(MobileQuotaBurndown(
            series: nil,
            window: window,
            capturedAt: self.captured,
            referenceDate: self.captured.addingTimeInterval(1800)) == nil)
    }

    @Test func `Native lane identities map weekly and opus history even without period metadata`() {
        for (index, id, label, expected) in [
            (0, "primary", "Session", "session"),
            (1, "secondary", "Weekly", "weekly"),
            (1, "secondary", "Sonnet", "weekly"),
            (2, "tertiary", "Opus", "opus"),
        ] {
            let window = SyncRateWindow(
                id: id,
                label: label,
                usedPercent: 25,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: nil)
            #expect(MobileQuotaBurndown.historySeriesName(for: window, index: index) == expected)
        }
        let unknown = SyncRateWindow(
            id: "fixture-extra",
            label: "Fixture lane",
            usedPercent: 25,
            windowMinutes: 60,
            resetsAt: nil,
            resetDescription: nil)
        #expect(MobileQuotaBurndown.historySeriesName(for: unknown, index: 3) == nil)
    }

    @Test func `Burndown uses capture time and latest declining segment without future samples`() throws {
        let reset = self.captured.addingTimeInterval(1800)
        let series = SyncUtilizationSeries(name: "session", windowMinutes: 60, entries: [
            .init(capturedAt: self.captured.addingTimeInterval(-600), usedPercent: 80, resetsAt: reset),
            .init(capturedAt: self.captured.addingTimeInterval(-300), usedPercent: 20, resetsAt: reset),
            .init(capturedAt: self.captured.addingTimeInterval(60), usedPercent: 99, resetsAt: reset),
            .init(
                capturedAt: self.captured.addingTimeInterval(-100),
                usedPercent: 90,
                resetsAt: reset.addingTimeInterval(600)),
        ])
        let model = try #require(MobileQuotaBurndown(
            series: series,
            window: self.window(),
            capturedAt: self.captured,
            referenceDate: self.captured.addingTimeInterval(120)))
        #expect(model.samples.map(\.remainingPercent) == [80, 75])
        #expect(model.samples.last?.date == self.captured)
        #expect(model.ideal.map(\.remainingPercent) == [100, 0])
        #expect(model.start == reset.addingTimeInterval(-3600))
    }

    @Test func `Expired unknown synthetic blocked and nonfinite windows do not manufacture a curve`() {
        let quota = SyncBlockingQuota(
            windowID: "monthly",
            rawUsedPercent: 25,
            rawResetsAt: nil,
            rawResetDescription: nil,
            rawNextRegenPercent: nil)
        for window in [
            self.window(known: false),
            self.window(synthetic: true),
            self.window(blocking: quota),
            self.window(percent: .nan),
            self.window(percent: 101),
        ] {
            #expect(MobileQuotaBurndown(
                series: nil,
                window: window,
                capturedAt: self.captured,
                referenceDate: self.captured) == nil)
        }
        #expect(MobileQuotaBurndown(
            series: nil,
            window: self.window(),
            capturedAt: self.captured,
            referenceDate: self.captured.addingTimeInterval(1800)) == nil)
        #expect(MobileQuotaBurndown(
            series: nil,
            window: self.window(),
            capturedAt: self.captured,
            referenceDate: self.captured.addingTimeInterval(-1)) == nil)
    }

    @Test func `Same-capture current observation wins and reset tolerance remains two minutes`() throws {
        let reset = self.captured.addingTimeInterval(1800)
        let history = SyncUtilizationSeries(name: "session", windowMinutes: 60, entries: [
            .init(
                capturedAt: self.captured.addingTimeInterval(-300),
                usedPercent: 20,
                resetsAt: reset.addingTimeInterval(120)),
            .init(capturedAt: self.captured, usedPercent: 90, resetsAt: reset),
        ])
        let model = try #require(MobileQuotaBurndown(
            series: history, window: self.window(), capturedAt: self.captured, referenceDate: self.captured))
        #expect(model.samples.map(\.remainingPercent) == [80, 75])
        #expect(model.samples.count == 2)
    }

    @Test func `Expired blocking observations retain effective unavailability and explain raw use`() {
        let quota = SyncBlockingQuota(
            windowID: "monthly",
            rawUsedPercent: 25,
            rawResetsAt: nil,
            rawResetDescription: nil,
            rawNextRegenPercent: 5)
        let window = self.window(percent: 100, blocking: quota)
        let presentation = UsageWindowPresentation(window: window)
        #expect(presentation.isBlocked)
        #expect(presentation.rawUsedPercent == 25)
        #expect(presentation.hasExpiredObservation(at: self.captured.addingTimeInterval(1801)))
        #expect(presentation.window.remainingPercent == 0)
    }

    @Test @MainActor
    func `Only native Claude inventory rows are hidden from legacy cached details`() {
        let section = SyncProviderDetailSection(title: "Fixture details", rows: [
            .init(label: "Limit Reset Credits", value: "3"),
            .init(label: "Plan", value: "Fixture Plan"),
        ])
        let native = ProviderDetailsView.visibleSections(providerID: "claude", sections: [section])
        #expect(native.first?.rows.map(\.label) == ["Plan"])
        #expect(ProviderDetailsView.visibleSections(providerID: "fixture-plugin", sections: [section]) == [section])
        #expect(ProviderDetailsView.visibleSections(providerID: "claude", sections: [
            .init(rows: [.init(label: "Limit Reset Credits", value: "3")]),
        ]).isEmpty)
    }
}
