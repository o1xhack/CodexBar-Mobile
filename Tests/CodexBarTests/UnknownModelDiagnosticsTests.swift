import Foundation
import Testing
@testable import CodexBarCore

/// Pins the diagnostic recorder semantics that the Mac Debug pane
/// relies on. The actor is the canonical source for "what did the
/// fallback resolver substitute this session" and tests below lock
/// in dedup, count bumps, and ordering invariants.
@Suite("UnknownModelDiagnostics")
struct UnknownModelDiagnosticsTests {
    @Test
    func `First record creates an entry with count 1`() async {
        let diag = UnknownModelDiagnostics()
        await diag.record(
            providerKey: "claude",
            rawModel: "claude-opus-4-99",
            fallbackKey: "claude-opus-4-7",
            strategyName: "sameFamilyMinorBelow")
        let snapshot = await diag.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot[0].rawModel == "claude-opus-4-99")
        #expect(snapshot[0].fallbackKey == "claude-opus-4-7")
        #expect(snapshot[0].occurrenceCount == 1)
    }

    @Test
    func `Repeat record on same (provider, raw) bumps count, keeps single entry`() async {
        let diag = UnknownModelDiagnostics()
        for _ in 0..<5 {
            await diag.record(
                providerKey: "codex",
                rawModel: "gpt-5.6",
                fallbackKey: "gpt-5.5",
                strategyName: "sameFamilyMinorBelow")
        }
        let snapshot = await diag.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot[0].occurrenceCount == 5)
    }

    @Test
    func `Distinct (provider, raw) pairs each get their own entry`() async {
        let diag = UnknownModelDiagnostics()
        await diag.record(
            providerKey: "claude",
            rawModel: "claude-opus-4-99",
            fallbackKey: "claude-opus-4-7",
            strategyName: "sameFamilyMinorBelow")
        await diag.record(
            providerKey: "codex",
            rawModel: "gpt-5.6",
            fallbackKey: "gpt-5.5",
            strategyName: "sameFamilyMinorBelow")
        let snapshot = await diag.snapshot()
        #expect(snapshot.count == 2)
    }

    @Test
    func `Same raw name across different providers tracks separately`() async {
        // Defensive — `claude-opus-4-99` shouldn't ever appear under
        // codex in practice, but if it did the dedup should NOT collapse
        // the rows because the fallback target may differ per provider.
        let diag = UnknownModelDiagnostics()
        await diag.record(
            providerKey: "claude",
            rawModel: "weird-name",
            fallbackKey: "claude-opus-4-7",
            strategyName: "providerDefault")
        await diag.record(
            providerKey: "codex",
            rawModel: "weird-name",
            fallbackKey: "gpt-5",
            strategyName: "providerDefault")
        let snapshot = await diag.snapshot()
        #expect(snapshot.count == 2)
    }

    @Test
    func `Snapshot orders by recency, then count, then provider/raw alphabetical`() async {
        let diag = UnknownModelDiagnostics()
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        // Same `firstSeenAt` → tiebreaker chain should pick most-bumped
        // first, then alphabetical by provider, then alphabetical by raw.
        await diag.record(
            providerKey: "codex",
            rawModel: "gpt-5.6",
            fallbackKey: "gpt-5.5",
            strategyName: "sameFamilyMinorBelow",
            now: pinnedDate)
        await diag.record(
            providerKey: "claude",
            rawModel: "claude-opus-4-99",
            fallbackKey: "claude-opus-4-7",
            strategyName: "sameFamilyMinorBelow",
            now: pinnedDate)
        // bump claude entry's count so it should sort first under the
        // count tiebreaker.
        await diag.record(
            providerKey: "claude",
            rawModel: "claude-opus-4-99",
            fallbackKey: "claude-opus-4-7",
            strategyName: "sameFamilyMinorBelow",
            now: pinnedDate)
        let snapshot = await diag.snapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot[0].rawModel == "claude-opus-4-99")
        #expect(snapshot[0].occurrenceCount == 2)
        #expect(snapshot[1].rawModel == "gpt-5.6")
    }

    @Test
    func `Reset clears entries and log counter`() async {
        let diag = UnknownModelDiagnostics()
        await diag.record(
            providerKey: "claude",
            rawModel: "x",
            fallbackKey: "y",
            strategyName: "providerDefault")
        await diag.reset()
        let snapshot = await diag.snapshot()
        #expect(snapshot.isEmpty)
    }
}
