import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Reset dates and reader-local quota pace")
struct ResetAndPacePresentationTests {
    private let captured = Date(timeIntervalSince1970: 1_791_000_000)

    private func window(
        used: Double = 72,
        remainingFraction: Double = 0.129,
        minutes: Int = 10080,
        usageKnown: Bool = true) -> SyncRateWindow
    {
        .init(
            usedPercent: used,
            usageKnown: usageKnown,
            windowMinutes: minutes,
            resetsAt: self.captured.addingTimeInterval(Double(minutes) * 60 * remainingFraction),
            resetDescription: nil)
    }

    private func pace(_ window: SyncRateWindow?, reference: Date? = nil) -> QuotaPace? {
        QuotaPace(window: window, capturedAt: self.captured, referenceDate: reference ?? self.captured)
    }

    @Test func `Reset dates use Gregorian month day and a fixed 24 hour clock in the reader time zone`() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-03T00:05:00Z"))
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(QuotaResetDateText.compact(date, timeZone: zone) == "10.2 17:05")
        #expect(try QuotaResetDateText.compact(date, timeZone: #require(TimeZone(secondsFromGMT: 0))) == "10.3 00:05")
        let winter = try #require(ISO8601DateFormatter().date(from: "2027-01-01T07:02:00Z"))
        #expect(QuotaResetDateText.compact(winter, timeZone: zone) == "12.31 23:02")
    }

    @Test func `Linear pace matches the Mac formula at the observation time`() throws {
        let pace = try #require(self.pace(self.window()))
        // 87.1% of the week elapsed, 72% used.
        #expect(abs(pace.deltaPercentagePoints + 15.1) < 0.0001)
        #expect(pace.forecast == .lastsUntilReset(headroom: true))
        #expect(pace.trend == .behind)
        #expect(pace.summary(locale: Locale(identifier: "en_US")) ==
            "15 percentage points below even pace · Estimated to last until reset · At least 1.5× pace headroom")
    }

    @Test func `All four reader languages localize the pace`() throws {
        let pace = try #require(self.pace(self.window()))
        for (language, fragment) in [
            ("en", "15 percentage points below even pace"),
            ("zh-Hans", "低 15 个百分点"),
            ("zh-Hant", "低 15 個百分點"),
            ("ja", "15 ポイント低い"),
        ] {
            #expect(pace.summary(locale: Locale(identifier: language)).contains(fragment))
        }
    }

    @Test func `A fast observation forecasts depletion and near even pace retains its tolerance`() throws {
        let fast = try #require(self.pace(self.window(used: 72, remainingFraction: 0.5)))
        #expect(fast.forecast == .emptyAt(self.captured.addingTimeInterval(28 * 302_400 / 72)))
        #expect(fast.trend == .ahead)
        #expect(fast.summary(locale: Locale(identifier: "en")).contains("22 percentage points above"))
        let even = try #require(self.pace(self.window(used: 51, remainingFraction: 0.5)))
        #expect(even.deltaText(locale: Locale(identifier: "en")) == "On even pace")
        #expect(even.trend == .onPace)
    }

    @Test func `Headroom needs more than fifteen points of slack and is not shown for zero use`() throws {
        let under = try #require(self.pace(self.window(used: 73, remainingFraction: 0.121)))
        #expect(under.deltaPercentagePoints > -15)
        #expect(under.forecast == .lastsUntilReset(headroom: false))
        let zero = try #require(self.pace(self.window(used: 0)))
        #expect(zero.forecast == .lastsUntilReset(headroom: false))
    }

    @Test func `Invalid windows and expired or future observations produce no pace`() throws {
        #expect(self.pace(nil) == nil)
        #expect(self.pace(self.window(usageKnown: false)) == nil)
        #expect(self.pace(self.window(minutes: 300)) == nil)
        #expect(self.pace(self.window(used: .nan)) == nil)
        // The observation is later than the reader's clock.
        #expect(self.pace(self.window(), reference: self.captured.addingTimeInterval(-1)) == nil)
        // The window has already reset.
        let reset = try #require(self.window().resetsAt)
        #expect(self.pace(self.window(), reference: reset) == nil)
        // The reset is further away than one window: the observation predates it.
        #expect(self.pace(self.window(remainingFraction: 1.2)) == nil)
        // A brand-new window with usage has no pace yet.
        #expect(self.pace(self.window(used: 5, remainingFraction: 1)) == nil)
        let blocked = SyncRateWindow(
            usedPercent: 100,
            windowMinutes: 10080,
            resetsAt: reset,
            resetDescription: nil,
            blockingQuota: SyncBlockingQuota(
                windowID: "monthly", rawUsedPercent: 40, rawResetsAt: reset,
                rawResetDescription: nil, rawNextRegenPercent: nil))
        #expect(self.pace(blocked) == nil)
    }

    @Test func `Pace comes from the provider weekly window without any Mac pace field`() throws {
        func snapshot(_ providerID: String) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: providerID,
                providerName: providerID.capitalized,
                primary: SyncRateWindow(
                    usedPercent: 90,
                    windowMinutes: 300,
                    resetsAt: self.captured.addingTimeInterval(3600),
                    resetDescription: nil),
                secondary: self.window(),
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.captured)
        }
        for providerID in ["codex", "claude"] {
            let provider = snapshot(providerID)
            #expect(QuotaPace.window(for: provider)?.windowMinutes == 10080)
            let pace = try #require(QuotaPace(provider: provider, referenceDate: self.captured.addingTimeInterval(60)))
            #expect(abs(pace.deltaPercentagePoints + 15.1) < 0.0001)
            #expect(pace.capturedAt == self.captured)
        }
    }

    @Test func `Pace stays anchored to the observation as the reader clock moves`() throws {
        let early = try #require(self.pace(self.window()))
        let later = try #require(self.pace(self.window(), reference: self.captured.addingTimeInterval(3600)))
        #expect(early == later)
    }

    @Test func `Over-limit usage clamps to empty now and a window that has not started has no forecast`() throws {
        let over = try #require(self.pace(self.window(used: 130, remainingFraction: 0.4)))
        #expect(over.forecast == .emptyAt(self.captured))
        #expect(abs(over.deltaPercentagePoints - 40) < 0.0001)
        let fresh = try #require(self.pace(self.window(used: 0, remainingFraction: 1)))
        #expect(fresh.forecast == nil)
    }

    @Test func `The monthly sentinel follows each provider's Mac rule`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let marchReset = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 1)))
        let augustReset = try #require(calendar.date(from: DateComponents(year: 2027, month: 8, day: 1)))
        func monthly(_ reset: Date, minutes: Int? = 43200, description: String? = nil) -> SyncRateWindow {
            SyncRateWindow(usedPercent: 2, windowMinutes: minutes, resetsAt: reset, resetDescription: description)
        }
        // Calendar-month providers: February and July.
        #expect(QuotaPace.duration(of: monthly(marchReset), providerID: "alibaba") == TimeInterval(28 * 86400))
        #expect(QuotaPace.duration(of: monthly(augustReset), providerID: "ollama") == TimeInterval(31 * 86400))
        // Codex's 43200 minutes is a real rolling 30-day window.
        #expect(QuotaPace.duration(of: monthly(marchReset), providerID: "codex") == TimeInterval(30 * 86400))
        // Zai only for its MCP window; Copilot when the length is missing.
        #expect(QuotaPace.duration(of: monthly(marchReset, description: "MCP"), providerID: "zai")
            == TimeInterval(28 * 86400))
        #expect(QuotaPace.duration(of: monthly(marchReset), providerID: "zai") == TimeInterval(30 * 86400))
        #expect(QuotaPace.duration(of: monthly(augustReset, minutes: nil), providerID: "copilot")
            == TimeInterval(31 * 86400))
        #expect(QuotaPace.duration(of: monthly(augustReset, minutes: nil), providerID: "codex") == nil)
        #expect(QuotaPace.duration(of: monthly(augustReset, minutes: 300), providerID: "codex") == nil)
        // Day one of a 31-day month still produces a pace.
        let captured = augustReset.addingTimeInterval(-30.5 * 86400)
        let pace = try #require(QuotaPace(
            window: monthly(augustReset), capturedAt: captured, referenceDate: captured, providerID: "ollama"))
        #expect(abs(pace.deltaPercentagePoints - (2 - 0.5 / 31 * 100)) < 0.0001)
    }

    @Test func `Only native slots carry the pace and extra named windows never do`() {
        func snapshot(windows: [SyncRateWindow], providerID: String = "codex") -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: providerID,
                providerName: providerID,
                primary: windows.first,
                secondary: windows.dropFirst().first,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.captured,
                rateWindows: windows)
        }
        let reset = self.captured.addingTimeInterval(86400)
        let weeklyPrimary = SyncRateWindow(
            id: "primary", usedPercent: 40, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)
        let spark = SyncRateWindow(
            id: "codex-spark", label: "Spark", usedPercent: 90, windowMinutes: 10080, resetsAt: reset,
            resetDescription: nil)
        // The legacy `secondary` field is Spark here; the pace must use primary.
        #expect(QuotaPace.window(for: snapshot(windows: [weeklyPrimary, spark])) == weeklyPrimary)
        // A Claude model lane alone never becomes the pace window.
        let session = SyncRateWindow(
            id: "primary", usedPercent: 10, windowMinutes: 300, resetsAt: reset, resetDescription: nil)
        let opus = SyncRateWindow(
            id: "claude-opus", label: "Opus", usedPercent: 10, windowMinutes: 10080, resetsAt: reset,
            resetDescription: nil)
        #expect(QuotaPace.window(for: snapshot(windows: [session, opus], providerID: "claude")) == nil)
        // A native slot that keeps a provider-defined id (Aixy budget) still counts.
        let budget = SyncRateWindow(
            id: "aixy-budget-123", usedPercent: 20, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)
        let daily = SyncRateWindow(
            id: "secondary", usedPercent: 5, windowMinutes: 300, resetsAt: reset, resetDescription: nil)
        #expect(QuotaPace.window(for: snapshot(windows: [budget, daily], providerID: "aixy")) == budget)
        // Only provider-defined ids: the legacy slots decide.
        let monthlyBudget = SyncRateWindow(
            id: "aixy-budget-456", usedPercent: 20, windowMinutes: 43200, resetsAt: reset, resetDescription: nil)
        #expect(QuotaPace.window(for: snapshot(windows: [monthlyBudget], providerID: "aixy")) == monthlyBudget)
    }

    @Test func `OpenCodeGo estimated usage has no pace like the Mac`() {
        let provider = ProviderUsageSnapshot(
            providerID: "opencodego",
            providerName: "OpenCode Go",
            primary: nil,
            secondary: self.window(),
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.captured,
            usageDataConfidence: "estimated")
        #expect(QuotaPace(provider: provider, referenceDate: self.captured) == nil)
    }
}
