import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Quota detail actual observation inspection")
struct UsageQuotaDetailPresentationTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `inspection snaps only inside a real segment and reports the actual sample time`() {
        let samples = [
            UsageQuotaPoint(date: self.start, remainingPercent: 80),
            UsageQuotaPoint(date: self.start.addingTimeInterval(600), remainingPercent: 72),
        ]
        let reading = UsageQuotaDetailPresentation.observation(at: self.start.addingTimeInterval(400), samples: samples)
        #expect(reading == samples[1])
        #expect(reading?.date != self.start.addingTimeInterval(400))
        #expect(UsageQuotaDetailPresentation
            .observation(at: self.start.addingTimeInterval(-1), samples: samples) == nil)
        #expect(UsageQuotaDetailPresentation
            .observation(at: self.start.addingTimeInterval(601), samples: samples) == nil)
    }

    @Test
    func `gaps and isolated points never become carried or interpolated quota readings`() {
        let samples = [
            UsageQuotaPoint(date: self.start, remainingPercent: 80, segment: 0),
            UsageQuotaPoint(date: self.start.addingTimeInterval(300), remainingPercent: 78, segment: 0),
            UsageQuotaPoint(date: self.start.addingTimeInterval(1200), remainingPercent: 72, segment: 1),
        ]
        #expect(UsageQuotaDetailPresentation
            .observation(at: self.start.addingTimeInterval(600), samples: samples) == nil)
        #expect(UsageQuotaDetailPresentation
            .observation(at: self.start.addingTimeInterval(1199), samples: samples) == nil)
        #expect(UsageQuotaDetailPresentation.observation(at: samples[2].date, samples: samples) == samples[2])
        #expect(UsageQuotaDetailPresentation.observation(at: self.start, samples: []) == nil)
    }

    @Test
    func `equal distance ties use the earlier real observation and invalid samples are ignored`() {
        let first = UsageQuotaPoint(date: self.start, remainingPercent: 80)
        let last = UsageQuotaPoint(date: self.start.addingTimeInterval(600), remainingPercent: 72)
        let samples = [last, first, UsageQuotaPoint(date: self.start.addingTimeInterval(300), remainingPercent: .nan)]
        #expect(UsageQuotaDetailPresentation
            .observation(at: self.start.addingTimeInterval(300), samples: samples) == first)
    }

    @Test
    func `idle shows each series latest observation but explicit selection never carries older readings`() {
        let end = self.start.addingTimeInterval(100)
        let first = UsageQuotaPoint(date: end, remainingPercent: 70)
        let second = UsageQuotaPoint(date: self.start.addingTimeInterval(90), remainingPercent: 80)
        let domain = self.start...end
        #expect(UsageQuotaDetailPresentation.reading(selectedDate: nil, samples: [first], domain: domain) == first)
        #expect(UsageQuotaDetailPresentation.reading(selectedDate: nil, samples: [second], domain: domain) == second)
        #expect(UsageQuotaDetailPresentation.reading(selectedDate: end, samples: [second], domain: domain) == nil)
        #expect(UsageQuotaDetailPresentation.reading(selectedDate: end, samples: [first], domain: domain) == first)
        // Clearing the selection restores idle, while out-of-domain or invalid points cannot become latest.
        let future = UsageQuotaPoint(date: end.addingTimeInterval(1), remainingPercent: 65)
        let invalid = UsageQuotaPoint(date: end, remainingPercent: .nan)
        #expect(UsageQuotaDetailPresentation.reading(
            selectedDate: nil, samples: [future, second, invalid], domain: domain) == second)
        #expect(UsageQuotaDetailPresentation.reading(selectedDate: nil, samples: [], domain: domain) == nil)
        #expect(UsageQuotaDetailPresentation.reading(
            selectedDate: nil, samples: [second], domain: self.start.addingTimeInterval(91)...end) == nil)
    }

    private func line(
        id: UUID = UUID(),
        anchor: String = "one",
        state: SummaryCardState = .available,
        reset: Date?,
        remaining: Double = 40,
        stale: Bool = false) -> UsageQuotaResolvedLine
    {
        UsageQuotaResolvedLine(
            selection: UsageQuotaSelection(
                id: id,
                providerID: "codex",
                accountAnchorID: anchor,
                windowID: "secondary",
                colorHex: "000000"),
            provider: nil, accountTitle: "Fictional account", compactAccountTitle: nil, privateAccountTitle: nil,
            metricTitle: "Weekly", state: state, isStale: stale, currentRemainingPercent: remaining,
            observedAt: self.start, resetDate: reset, observedSamples: [], localObservationCount: 0)
    }

    @Test
    func `current values respect unavailable stale blocked and expired states independently of history inspection`() {
        let reset = self.start.addingTimeInterval(600)
        for state: SummaryCardState in [
            .stale,
            .blocked,
            .resetPassed,
            .missingAccount,
            .missingMetric,
            .unknown,
            .unavailable,
        ] {
            #expect(UsageQuotaDetailPresentation.currentRemaining(
                self.line(state: state, reset: reset),
                now: self.start) == nil)
        }
        #expect(UsageQuotaDetailPresentation.currentRemaining(self.line(reset: reset), now: self.start) == 40)
        #expect(UsageQuotaDetailPresentation.currentRemaining(self.line(reset: reset), now: reset) == nil)
        #expect(UsageQuotaDetailPresentation
            .currentRemaining(self.line(reset: reset, stale: true), now: self.start) == nil)
    }

    @Test
    func `current rows order by next reset while retaining separate same provider accounts and windows`() throws {
        let later = self.line(anchor: "work", reset: self.start.addingTimeInterval(1200))
        let earlier = self.line(anchor: "personal", reset: self.start.addingTimeInterval(300))
        let missing = self.line(anchor: "retired", state: .missingAccount, reset: nil)
        let expired = self.line(anchor: "expired", state: .resetPassed, reset: self.start.addingTimeInterval(-60))
        let rows = UsageQuotaDetailPresentation.currentLines([later, missing, earlier, expired], now: self.start)
        #expect(rows.map(\.id) == [earlier.id, later.id, missing.id, expired.id])
        #expect(try UsageQuotaDetailPresentation.currentLines([later, earlier], now: #require(earlier.resetDate)).first?
            .id == later.id)
        #expect(UsageQuotaDetailPresentation.currentLines([later], now: self.start).map(\.id) == [later.id])
    }
}
