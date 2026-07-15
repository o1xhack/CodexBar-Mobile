import Foundation
import Testing
@testable import CodexBarCore

/// Pins the generic fallback algorithm against a synthetic provider so
/// the algorithm can be reasoned about independently of the Claude or
/// Codex grammars (those land in P2 with their own per-resolver suites).
///
/// Mock model name shape: `family-MAJOR[-MINOR][-YYYYMMDD]`. Anything
/// that doesn't fit that grammar parses to nil — the resolver caller
/// treats nil as "this provider doesn't know this string", which falls
/// outside the fallback ladder entirely.
@Suite("ModelFamilyResolver fallback algorithm")
struct ModelFamilyResolverTests {
    private struct MockPricing: Equatable {
        let value: Int
    }

    private struct MockResolver: ModelFamilyResolver {
        typealias Pricing = MockPricing
        let providerKey = "mock"
        let pinnedFamilyDefault: String?
        let pinnedProviderDefault: String?

        func parse(_ raw: String) -> ParsedModel? {
            let parts = raw.split(separator: "-").map(String.init)
            guard parts.count >= 2 else { return nil }
            let family = parts[0]
            guard !family.isEmpty else { return nil }
            guard let major = Int(parts[1]) else { return nil }

            var minor: Int?
            var date: String?

            // parts[2] could be either a minor number or an 8-digit date.
            if parts.count >= 3 {
                if Self.isDateSuffix(parts[2]) {
                    date = parts[2]
                } else if let parsed = Int(parts[2]) {
                    minor = parsed
                } else {
                    return nil
                }
            }
            // parts[3] is always a date suffix when present.
            if parts.count == 4 {
                guard date == nil, Self.isDateSuffix(parts[3]) else { return nil }
                date = parts[3]
            }
            if parts.count > 4 { return nil }

            return ParsedModel(
                providerKey: self.providerKey,
                family: family,
                majorVersion: major,
                minorVersion: minor,
                dateSuffix: date,
                raw: raw)
        }

        func familyDefault(family _: String, in known: [String: MockPricing])
            -> (key: String, pricing: MockPricing)?
        {
            guard let key = pinnedFamilyDefault, let pricing = known[key] else { return nil }
            return (key, pricing)
        }

        func providerDefault(in known: [String: MockPricing])
            -> (key: String, pricing: MockPricing)?
        {
            guard let key = pinnedProviderDefault, let pricing = known[key] else { return nil }
            return (key, pricing)
        }

        private static func isDateSuffix(_ token: String) -> Bool {
            token.count == 8 && token.allSatisfy(\.isNumber)
        }
    }

    private static func makeResolver(
        familyDefault: String? = nil,
        providerDefault: String? = nil) -> MockResolver
    {
        MockResolver(
            pinnedFamilyDefault: familyDefault,
            pinnedProviderDefault: providerDefault)
    }

    // MARK: - Parser

    @Test
    func `Parser extracts family + major + minor from family-M-m`() {
        let parsed = Self.makeResolver().parse("opus-4-7")
        #expect(parsed?.family == "opus")
        #expect(parsed?.majorVersion == 4)
        #expect(parsed?.minorVersion == 7)
        #expect(parsed?.dateSuffix == nil)
        #expect(parsed?.raw == "opus-4-7")
    }

    @Test
    func `Parser handles family-M with no minor as minor=nil (base of major)`() {
        let parsed = Self.makeResolver().parse("opus-4")
        #expect(parsed?.family == "opus")
        #expect(parsed?.majorVersion == 4)
        #expect(parsed?.minorVersion == nil)
    }

    @Test
    func `Parser captures 8-digit date suffix`() {
        let parsed = Self.makeResolver().parse("opus-4-7-20260101")
        #expect(parsed?.dateSuffix == "20260101")
        #expect(parsed?.minorVersion == 7)
    }

    @Test
    func `Parser distinguishes date-only family-M-YYYYMMDD from minor`() {
        let parsed = Self.makeResolver().parse("opus-4-20260101")
        #expect(parsed?.dateSuffix == "20260101")
        #expect(parsed?.minorVersion == nil)
    }

    @Test
    func `Parser returns nil for unparseable input`() {
        #expect(Self.makeResolver().parse("totally garbage") == nil)
        #expect(Self.makeResolver().parse("") == nil)
        #expect(Self.makeResolver().parse("opus") == nil)
        #expect(Self.makeResolver().parse("opus-not-a-number") == nil)
    }

    // MARK: - Fallback algorithm

    @Test
    func `Step 1: closest minor below requested, same family + major`() throws {
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [
            "opus-4-3": .init(value: 3),
            "opus-4-5": .init(value: 5),
            "opus-4-7": .init(value: 7),
        ]
        let parsed = try #require(resolver.parse("opus-4-8"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "opus-4-7")
        #expect(result?.pricing.value == 7)
        #expect(result?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Step 1: prefers closest minor, not just any below`() throws {
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [
            "opus-4-3": .init(value: 3),
            "opus-4-5": .init(value: 5),
            "opus-4-7": .init(value: 7),
        ]
        let parsed = try #require(resolver.parse("opus-4-6"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "opus-4-5")
        #expect(result?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Step 2: closest minor above when nothing at-or-below exists`() throws {
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [
            "opus-4-5": .init(value: 5),
            "opus-4-7": .init(value: 7),
        ]
        let parsed = try #require(resolver.parse("opus-4-2"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "opus-4-5")
        #expect(result?.strategy == .sameFamilyMinorAbove)
    }

    @Test
    func `Step 3: same family, older major, top minor of newest available major`() throws {
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [
            "opus-3-1": .init(value: 31),
            "opus-3-5": .init(value: 35),
            "opus-4-7": .init(value: 47),
        ]
        let parsed = try #require(resolver.parse("opus-5-2"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "opus-4-7")
        #expect(result?.strategy == .sameFamilyOlderMajor)
    }

    @Test
    func `Step 4: family default activates when no family entries exist in table`() throws {
        let resolver = Self.makeResolver(familyDefault: "sonnet-4-5")
        let table: [String: MockPricing] = [
            "sonnet-4-5": .init(value: 45),
        ]
        let parsed = try #require(resolver.parse("opus-4-7"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "sonnet-4-5")
        #expect(result?.strategy == .familyDefault)
    }

    @Test
    func `Step 5: provider default activates when family default is nil`() throws {
        let resolver = Self.makeResolver(providerDefault: "anything-1-1")
        let table: [String: MockPricing] = [
            "anything-1-1": .init(value: 11),
        ]
        let parsed = try #require(resolver.parse("newexotic-2-1"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "anything-1-1")
        #expect(result?.strategy == .providerDefault)
    }

    @Test
    func `Returns nil when nothing matches and no defaults are set`() throws {
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [:]
        let parsed = try #require(resolver.parse("opus-4-7"))
        #expect(resolver.findFallback(for: parsed, in: table) == nil)
    }

    @Test
    func `Family default takes priority over provider default when both set`() throws {
        let resolver = Self.makeResolver(
            familyDefault: "sonnet-4-5",
            providerDefault: "fallback-1-1")
        let table: [String: MockPricing] = [
            "sonnet-4-5": .init(value: 45),
            "fallback-1-1": .init(value: 11),
        ]
        let parsed = try #require(resolver.parse("opus-4-7"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "sonnet-4-5")
        #expect(result?.strategy == .familyDefault)
    }

    @Test
    func `Step 1 satisfies on equal minor (same key as input — protects fast path)`() throws {
        // findFallback is normally called only when the dictionary lookup
        // missed; pin behaviour for the boundary case where the key is
        // present but the caller still walks the ladder. The "≤ requested"
        // rule must include equality so refactors don't accidentally make
        // the ladder skip exact matches.
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [
            "opus-4-7": .init(value: 7),
        ]
        let parsed = try #require(resolver.parse("opus-4-7"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "opus-4-7")
        #expect(result?.strategy == .sameFamilyMinorBelow)
    }

    @Test
    func `Requested has no minor (treated as 0): finds same-major minor=0 if present`() throws {
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [
            "opus-4-5": .init(value: 5),
            "opus-4-7": .init(value: 7),
        ]
        // "opus-4" has no minor → treated as 0 → 0 ≤ 5 false, 0 ≤ 7 false
        // Step 1 finds nothing; Step 2 picks smallest minor above (5).
        let parsed = try #require(resolver.parse("opus-4"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "opus-4-5")
        #expect(result?.strategy == .sameFamilyMinorAbove)
    }

    @Test
    func `Step 3 prefers newest older major, not oldest`() throws {
        let resolver = Self.makeResolver()
        let table: [String: MockPricing] = [
            "opus-2-1": .init(value: 21),
            "opus-3-5": .init(value: 35),
            "opus-4-7": .init(value: 47),
        ]
        // Requesting 5-x with no major-5 entries; should pick highest of
        // 4-* — `opus-4-7` — not 2-1 or 3-5.
        let parsed = try #require(resolver.parse("opus-5-0"))
        let result = resolver.findFallback(for: parsed, in: table)
        #expect(result?.key == "opus-4-7")
        #expect(result?.strategy == .sameFamilyOlderMajor)
    }
}
