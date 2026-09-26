import Foundation
import Testing
@testable import CodexBarCore

struct CreditUsageTests {
    @Test(arguments: [
        CreditCase(used: nil, total: nil, remaining: nil, percent: nil),
        CreditCase(used: 10, total: nil, remaining: 90, percent: 10),
        CreditCase(used: nil, total: 100, remaining: 30, percent: 70),
        CreditCase(used: 120, total: 100, remaining: 50, percent: 100),
        CreditCase(used: -10, total: nil, remaining: 30, percent: 0),
        CreditCase(used: nil, total: 100, remaining: 150, percent: 0),
        CreditCase(used: 0, total: 0, remaining: 0, percent: 100),
    ])
    func `provider windows retain explicit and inferred counter precedence`(fixture: CreditCase) {
        let codebuff = CodebuffUsageSnapshot(
            creditsUsed: fixture.used, creditsTotal: fixture.total, creditsRemaining: fixture.remaining)
        let kilo = Self.kilo(used: fixture.used, total: fixture.total, remaining: fixture.remaining)
        #expect(codebuff.toUsageSnapshot().primary?.usedPercent == fixture.percent)
        #expect(kilo.toUsageSnapshot().primary?.usedPercent == fixture.percent)
        #expect(kilo.toUsageSnapshot().secondary?.usedPercent == fixture.percent)
    }

    @Test
    func `missing total and overflow retain provider specific presentation`() {
        #expect(CodebuffUsageSnapshot(creditsRemaining: 5).toUsageSnapshot().primary?.usedPercent == 100)
        #expect(Self.kilo(used: nil, total: nil, remaining: 5).toUsageSnapshot().primary == nil)
        let overflow = CreditUsage(used: .greatestFiniteMagnitude, total: nil, remaining: .greatestFiniteMagnitude)
        #expect(overflow.total == .infinity)
        #expect(Self.kilo(used: .greatestFiniteMagnitude, total: nil, remaining: .greatestFiniteMagnitude)
            .toUsageSnapshot().primary == nil)
        let nonfinite = CreditUsage(used: .nan, total: .nan, remaining: nil)
        #expect(nonfinite.used == 0)
        #expect(nonfinite.total == 0)
        #expect(CreditUsage(used: .infinity, total: 100, remaining: nil).used == .infinity)
    }

    @Test
    func `credit labels and pass bonus formatting remain provider owned`() {
        let codebuff = CodebuffUsageSnapshot(creditsUsed: 25, creditsTotal: 100, creditsRemaining: 75)
        let kilo = Self.kilo(used: 25, total: 100, remaining: 75)
        #expect(codebuff.toUsageSnapshot().primary?.resetDescription == nil)
        #expect(codebuff.toUsageSnapshot().identity?.loginMethod == "75 remaining")
        #expect(kilo.toUsageSnapshot().primary?.resetDescription == "25/100 credits")
        #expect(kilo.toUsageSnapshot().secondary?.resetDescription == "$25.00 / $90.00 (+ $10.00 bonus)")
    }

    private static func kilo(used: Double?, total: Double?, remaining: Double?) -> KiloUsageSnapshot {
        KiloUsageSnapshot(
            creditsUsed: used,
            creditsTotal: total,
            creditsRemaining: remaining,
            passUsed: used,
            passTotal: total,
            passRemaining: remaining,
            passBonus: 10,
            planName: nil,
            autoTopUpEnabled: nil,
            autoTopUpMethod: nil,
            updatedAt: Date())
    }

    struct CreditCase: Sendable {
        let used: Double?
        let total: Double?
        let remaining: Double?
        let percent: Double?
    }
}
