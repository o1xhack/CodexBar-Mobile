import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Reset dates and reader-local Codex pace")
struct ResetAndPacePresentationTests {
    private let captured = Date(timeIntervalSince1970: 1_791_000_000)

    private func context(delta: Double? = -0.151, label: String = "节奏：余量 15% · 持续到重置 · 1.5 倍余量")
        -> SyncCodexWorkspaceContext
    {
        .init(
            workspaceID: nil,
            workspaceName: nil,
            weeklyPaceDelta: delta,
            weeklyPaceLabel: label,
            updatedAt: self.captured)
    }

    private func window(used: Double = 72, remainingFraction: Double = 0.129) -> SyncRateWindow {
        .init(
            usedPercent: used,
            windowMinutes: 10080,
            resetsAt: self.captured.addingTimeInterval(604_800 * remainingFraction),
            resetDescription: nil)
    }

    @Test func `Reset dates use Gregorian month day and a fixed 24 hour clock in the reader time zone`() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-03T00:05:00Z"))
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(QuotaResetDateText.compact(date, timeZone: zone) == "10.2 17:05")
        #expect(try QuotaResetDateText.compact(date, timeZone: #require(TimeZone(secondsFromGMT: 0))) == "10.3 00:05")
        let winter = try #require(ISO8601DateFormatter().date(from: "2027-01-01T07:02:00Z"))
        #expect(QuotaResetDateText.compact(winter, timeZone: zone) == "12.31 23:02")
    }

    @Test func `Chinese producer copy never leaks into English reader pace`() throws {
        let pace = try #require(CodexPacePresentation(
            context: self.context(), window: self.window(), referenceDate: self.captured))
        #expect(abs(pace.deltaPercentagePoints + 15.1) < 0.0001)
        #expect(pace.forecast == .lastsUntilReset(headroom: true))
        let summary = pace.summary(locale: Locale(identifier: "en_US"))
        #expect(summary ==
            "15 percentage points below even pace · Estimated to last until reset · At least 1.5× pace headroom")
        #expect(!summary.contains("节奏"))
        #expect(!summary.contains("15%"))
    }

    @Test func `All four reader languages localize independently of the producer language`() throws {
        let pace = try #require(CodexPacePresentation(
            context: self.context(label: "Fixture foreign producer wording"),
            window: self.window(),
            referenceDate: self.captured))
        for (language, fragment) in [
            ("en", "15 percentage points below even pace"),
            ("zh-Hans", "低 15 个百分点"),
            ("zh-Hant", "低 15 個百分點"),
            ("ja", "15 ポイント低い"),
        ] {
            let text = pace.summary(locale: Locale(identifier: language))
            #expect(text.contains(fragment))
            #expect(!text.contains("Fixture"))
        }
    }

    @Test func `A fast observation forecasts depletion and near even pace retains its tolerance`() throws {
        let pace = try #require(CodexPacePresentation(
            context: self.context(delta: 0.22),
            window: self.window(used: 72, remainingFraction: 0.5),
            referenceDate: self.captured))
        #expect(pace.forecast == .emptyAt(self.captured.addingTimeInterval(28 * 302_400 / 72)))
        #expect(pace.summary(locale: Locale(identifier: "en")).contains("22 percentage points above"))
        let even = try #require(CodexPacePresentation(
            context: self.context(delta: 0.01), window: nil, referenceDate: self.captured))
        #expect(even.summary(locale: Locale(identifier: "en")) == "On even pace")
    }

    @Test func `Headroom is a threshold and is not shown for zero use or exactly fifteen points`() throws {
        let exact = try #require(CodexPacePresentation(
            context: self.context(delta: -0.15), window: self.window(), referenceDate: self.captured))
        #expect(exact.forecast == .lastsUntilReset(headroom: false))
        let zero = try #require(CodexPacePresentation(
            context: self.context(), window: self.window(used: 0), referenceDate: self.captured))
        #expect(zero.forecast == .lastsUntilReset(headroom: false))
    }

    @Test func `Invalid missing future or expired pace observations do not produce a translated prediction`() throws {
        for delta in [Double.nan, .infinity, -1.1, 1.1] {
            #expect(CodexPacePresentation(
                context: self.context(delta: delta),
                window: nil,
                referenceDate: self.captured) == nil)
        }
        #expect(CodexPacePresentation(
            context: self.context(delta: nil),
            window: nil,
            referenceDate: self.captured) == nil)
        #expect(CodexPacePresentation(
            context: self.context(),
            window: self.window(),
            referenceDate: self.captured.addingTimeInterval(-1)) == nil)
        let reset = try #require(self.window().resetsAt)
        #expect(CodexPacePresentation(context: self.context(), window: self.window(), referenceDate: reset) == nil)
        let unknown = SyncRateWindow(
            usedPercent: 72,
            usageKnown: false,
            windowMinutes: 10080,
            resetsAt: reset,
            resetDescription: nil)
        #expect(CodexPacePresentation(
            context: self.context(),
            window: unknown,
            referenceDate: self.captured)?.forecast == nil)
    }
}
