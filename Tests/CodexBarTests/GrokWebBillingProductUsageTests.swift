import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct GrokWebBillingProductUsageTests {
    private static let now = Date(timeIntervalSince1970: 1_790_456_400)
    private static let periodStart: UInt64 = 1_789_929_765
    private static let periodEnd: UInt64 = 1_790_534_565

    @Test
    func `live grok dot com billing frame decodes the product breakdown`() throws {
        let hex = """
        000000005f0a5d0d0000c04012001a00220c08a5d2c0d5061088ccb580022a0c08a5c7e5d5061088ccb58002
        3a07080415000080403a0708021500000040421e0802120c08a5d2c0d5061088ccb580021a0c08a5c7e5d506
        1088ccb58002580162006801800000000f677270632d7374617475733a300d0a
        """
        let data = try #require(Self.data(hex: hex))
        let parsed = try GrokWebBillingFetcher.parseGRPCWebResponse(data, now: Self.now)

        #expect(parsed.usedPercent == 6)
        #expect(parsed.usedPercentIsWirePublished)
        #expect(parsed.productUsage == [
            GrokProductUsage(product: "GrokChat", usedPercent: 4),
            GrokProductUsage(product: "GrokBuild", usedPercent: 2),
        ])

        let usage = GrokUsageSnapshot(
            billing: nil,
            webBilling: parsed,
            credentials: nil,
            localSummary: nil,
            cliVersion: nil,
            updatedAt: Self.now).toUsageSnapshot()
        let section = try #require(usage.details.first)
        #expect(usage.primary?.usedPercent == 6)
        #expect(usage.details.count == 1)
        #expect(section.title == "Usage breakdown")
        #expect(section.rows.map(\.label) == ["Grok Chat", "Grok Build"])
        #expect(section.rows.map(\.value) == ["4%", "2%"])
        #expect(section.rows.allSatisfy { $0.progress == nil })
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)

        let payload = ProviderPayload(
            provider: .grok,
            account: nil,
            version: nil,
            source: "fixture",
            status: nil,
            usage: usage,
            credits: nil,
            antigravityPlanInfo: nil,
            openaiDashboard: nil,
            error: nil)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        let encodedUsage = try #require(object["usage"] as? [String: Any])
        let details = try #require(encodedUsage["details"] as? [[String: Any]])
        let rows = try #require(details.first?["rows"] as? [[String: Any]])
        #expect(details.first?["title"] as? String == "Usage breakdown")
        #expect(rows.compactMap { $0["label"] as? String } == ["Grok Chat", "Grok Build"])
        #expect(rows.compactMap { $0["value"] as? String } == ["4%", "2%"])
    }

    @Test
    func `unnamed products keep only complete named shares`() throws {
        let named = [Self.entry(id: 4, percent: 4), Self.entry(id: 2, percent: 2)]
        let baseline = Self.frame(Self.payload(aggregate: 6))
        try Self.expectSameBilling(
            Self.frame(Self.payload(aggregate: 6, entries: named + [Self.entry(id: 7, percent: 1)])),
            baseline: baseline,
            products: [])
        try Self.expectSameBilling(
            Self.frame(Self.payload(aggregate: 6, entries: [Self.entry(id: 7)] + named)),
            baseline: baseline,
            products: [
                GrokProductUsage(product: "GrokChat", usedPercent: 4),
                GrokProductUsage(product: "GrokBuild", usedPercent: 2),
            ])
    }

    @Test
    func `missing duplicate and malformed product ids drop the breakdown`() throws {
        let baseline = Self.frame(Self.payload(aggregate: 6))
        let invalidEntries: [[Data]] = [
            [Self.entry(id: nil, percent: 4)],
            [Self.entry(id: 4, percent: 4), Self.entry(id: 4, percent: 2)],
            [Data([0x08])], // Truncated field 1 varint inside an entry.
            [Self.fixed32(1, 4), Self.entry(id: 2, percent: 6)],
            [Self.entry(id: 4) + Self.varintField(2, 1), Self.entry(id: 2, percent: 6)],
        ]
        for entries in invalidEntries {
            try Self.expectSameBilling(
                Self.frame(Self.payload(aggregate: 6, entries: entries)),
                baseline: baseline,
                products: [])
        }
        try Self.expectSameBilling(
            Self.frame(Self.payload(aggregate: 6, extra: Self.varintField(7, 4))),
            baseline: baseline,
            products: [])
    }

    @Test
    func `omitted percentages default to zero and unknown entry fields are skipped`() throws {
        let baseline = Self.frame(Self.payload(aggregate: 6))
        var chat = Self.entry(id: 4, percent: 6)
        chat.append(Self.varintField(3, 42))
        chat.append(Self.message(4, Data([0xFF])))
        chat.append(Self.fixed32(5, 3))
        chat.append(contentsOf: [0x31] + Array(repeating: 0, count: 8)) // Field 6, fixed64.
        try Self.expectSameBilling(
            Self.frame(Self.payload(aggregate: 6, entries: [chat, Self.entry(id: 2)])),
            baseline: baseline,
            products: [
                GrokProductUsage(product: "GrokChat", usedPercent: 6),
                GrokProductUsage(product: "GrokBuild", usedPercent: 0),
            ])
    }

    @Test
    func `invalid or noncomposing percentages drop the breakdown`() throws {
        let baseline = Self.frame(Self.payload(aggregate: 6))
        let cases: [[Data]] = [
            [Self.entry(id: 4, percent: -1), Self.entry(id: 2, percent: 7)],
            [Self.entry(id: 4, percent: .nan), Self.entry(id: 2, percent: 2)],
            [Self.entry(id: 2, percent: 2)],
        ]
        for entries in cases {
            try Self.expectSameBilling(
                Self.frame(Self.payload(aggregate: 6, entries: entries)),
                baseline: baseline,
                products: [])
        }
    }

    @Test
    func `products require one complete payload with a published config aggregate`() throws {
        let named = [Self.entry(id: 4, percent: 4), Self.entry(id: 2, percent: 2)]
        let baseline = Self.frame(Self.payload(aggregate: 6))
        try Self.expectSameBilling(baseline, baseline: baseline, products: [])

        let implicitZero = Self.frame(Self.payload(aggregate: nil, entries: [Self.entry(id: 4)]))
        let implicitBaseline = Self.frame(Self.payload(aggregate: nil))
        let implicitSnapshot = try GrokWebBillingFetcher.parseGRPCWebResponse(implicitBaseline, now: Self.now)
        #expect(implicitSnapshot.usedPercent == 0)
        #expect(implicitSnapshot.usedPercentIsImplicitZero)
        try Self.expectSameBilling(
            implicitZero,
            baseline: implicitBaseline,
            products: [])

        let twoFrames = Self.frame(Self.payload(aggregate: 6, entries: named))
            + Self.frame(Self.payload(aggregate: 6))
        let twoFramesBaseline = Self.frame(Self.payload(aggregate: 6))
            + Self.frame(Self.payload(aggregate: 6))
        try Self.expectSameBilling(twoFrames, baseline: twoFramesBaseline, products: [])

        let nestedAggregate = Self.message(2, Self.fixed32(1, 6))
        try Self.expectSameBilling(
            Self.frame(Self.payload(aggregate: nil, entries: named, extra: nestedAggregate)),
            baseline: Self.frame(Self.payload(aggregate: nil, extra: nestedAggregate)),
            products: [])

        let malformedOtherField = Data([0x62, 0x02, 0x08])
        try Self.expectSameBilling(
            Self.frame(Self.payload(aggregate: 6, entries: named, extra: malformedOtherField)),
            baseline: Self.frame(Self.payload(aggregate: 6, extra: malformedOtherField)),
            products: [])
    }

    @Test
    func `cookie fallback shows decoded product rows`() async throws {
        let liveHex = """
        000000005f0a5d0d0000c04012001a00220c08a5d2c0d5061088ccb580022a0c08a5c7e5d5061088ccb58002
        3a07080415000080403a0708021500000040421e0802120c08a5d2c0d5061088ccb580021a0c08a5c7e5d506
        1088ccb58002580162006801800000000f677270632d7374617475733a300d0a
        """
        let live = try #require(Self.data(hex: liveHex))
        var strategy = GrokWebFetchStrategy()
        strategy.loadCredentials = { _ in .failure(GrokWebBillingError.missingCredentials) }
        strategy.localSummary = { _ in nil }
        strategy.cliVersion = { _ in nil }
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-GrokProductUsage-\(UUID().uuidString)", isDirectory: true)
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let context = ProviderFetchContext(
            runtime: .cli,
            sourceMode: .web,
            includeCredits: true,
            includeOptionalUsage: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: ["GROK_HOME": home.path],
            settings: nil,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
        let result = try await strategy.fetch(
            context,
            webBilling: { _ in
                try GrokWebBillingResult(
                    snapshot: GrokWebBillingFetcher.parseGRPCWebResponse(live, now: Self.now),
                    sourceLabel: "Chrome",
                    authContext: .cookie("sso=test"))
            },
            settingsTier: { _ in nil },
            remainingResets: { _, _, _ in .empty })

        #expect(result.usage.primary?.usedPercent == 6)
        #expect(result.usage.details.count == 1)
        #expect(result.usage.details.first?.title == "Usage breakdown")
        #expect(result.usage.details.first?.rows.map(\.label) == ["Grok Chat", "Grok Build"])
        #expect(result.usage.details.first?.rows.map(\.value) == ["4%", "2%"])
    }

    @Test
    func `duplicate scalar fields cannot relabel or reweight product shares`() throws {
        let baseline = Self.frame(Self.payload(aggregate: 6))
        let duplicatedID = Self.entry(id: 2, percent: 6) + Self.varintField(1, 4)
        let duplicatedPercent = Self.entry(id: 4, percent: 1) + Self.fixed32(2, 6)
        for entry in [duplicatedID, duplicatedPercent] {
            try Self.expectSameBilling(
                Self.frame(Self.payload(aggregate: 6, entries: [entry])), baseline: baseline, products: [])
        }
        let repeatedAggregate = Self.frame(Self.payload(
            aggregate: 6, entries: [Self.entry(id: 4, percent: 6)], extra: Self.fixed32(1, 6)))
        #expect(try GrokWebBillingFetcher.parseGRPCWebResponse(repeatedAggregate, now: Self.now).productUsage.isEmpty)
    }

    @Test(arguments: [UInt8(1), 2, 3, 0x81])
    func `compressed or reserved frame flags fail closed`(flag: UInt8) {
        var frame = Self.frame(Self.payload(aggregate: 6, entries: [Self.entry(id: 4, percent: 6)]))
        frame[0] = flag
        #expect(throws: GrokWebBillingError.self) {
            try GrokWebBillingFetcher.parseGRPCWebResponse(frame, now: Self.now)
        }
    }

    @Test
    func `truncated framing and overflowing product values cannot supply shares`() throws {
        let valid = Self.frame(Self.payload(aggregate: 6, entries: [Self.entry(id: 4, percent: 6)]))
        for suffix in [Data([0]), Data([0, 0xFF, 0xFF, 0xFF, 0xFF])] {
            #expect(throws: GrokWebBillingError.self) {
                try GrokWebBillingFetcher.parseGRPCWebResponse(valid + suffix, now: Self.now)
            }
        }
        let overflow = Data([0x08] + Array(repeating: UInt8(0xFF), count: 9) + [0x02])
        let oversizedLength = Data([0x12]) + Self.varint(.max)
        for entry in [overflow, oversizedLength] {
            let parsed = try GrokWebBillingFetcher.parseGRPCWebResponse(
                Self.frame(Self.payload(aggregate: 6, entries: [entry])), now: Self.now)
            #expect(parsed.usedPercent == 6)
            #expect(parsed.productUsage.isEmpty)
        }
    }

    private static func expectSameBilling(
        _ data: Data,
        baseline: Data,
        products: [GrokProductUsage]) throws
    {
        let actual = try GrokWebBillingFetcher.parseGRPCWebResponse(data, now: Self.now)
        let withoutProducts = try GrokWebBillingFetcher.parseGRPCWebResponse(baseline, now: Self.now)
        #expect(actual.usedPercent == withoutProducts.usedPercent)
        #expect(actual.resetsAt == withoutProducts.resetsAt)
        #expect(actual.usedPercentIsWirePublished == withoutProducts.usedPercentIsWirePublished)
        #expect(actual.usedPercentIsImplicitZero == withoutProducts.usedPercentIsImplicitZero)
        #expect(actual.productUsage == products)
    }

    private static func payload(aggregate: Float?, entries: [Data] = [], extra: Data = Data()) -> Data {
        var config = Data()
        if let aggregate { config.append(Self.fixed32(1, aggregate)) }
        config.append(Self.message(5, Self.varintField(1, Self.periodEnd)))
        var currentPeriod = Self.varintField(1, 2)
        currentPeriod.append(Self.message(2, Self.varintField(1, Self.periodStart)))
        currentPeriod.append(Self.message(3, Self.varintField(1, Self.periodEnd)))
        config.append(Self.message(8, currentPeriod))
        for entry in entries {
            config.append(Self.message(7, entry))
        }
        config.append(extra)
        return Self.message(1, config)
    }

    private static func entry(id: UInt64?, percent: Float? = nil) -> Data {
        var data = Data()
        if let id { data.append(Self.varintField(1, id)) }
        if let percent { data.append(Self.fixed32(2, percent)) }
        return data
    }

    private static func varintField(_ number: UInt64, _ value: UInt64) -> Data {
        var data = Self.varint(number << 3)
        data.append(Self.varint(value))
        return data
    }

    private static func fixed32(_ number: UInt64, _ value: Float) -> Data {
        var data = Self.varint((number << 3) | 5)
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        return data
    }

    private static func message(_ number: UInt64, _ value: Data) -> Data {
        var data = Self.varint((number << 3) | 2)
        data.append(Self.varint(UInt64(value.count)))
        data.append(value)
        return data
    }

    private static func varint(_ value: UInt64) -> Data {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining != 0
        return Data(bytes)
    }

    private static func frame(_ payload: Data) -> Data {
        var data = Data([0])
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    private static func data(hex: String) -> Data? {
        let digits = hex.filter { !$0.isWhitespace }
        guard digits.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
