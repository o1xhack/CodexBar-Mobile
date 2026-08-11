import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarSync

@MainActor
@Suite("SyncCoordinator generic details bridge")
struct SyncCoordinatorV047MapperTests {
    @Test
    func `details mapper preserves rows chart kind and finite points`() throws {
        let source = try ProviderDetailSection(
            title: "Billing",
            rows: [
                .init(label: "Balance", value: "$81.25", secondaryValue: "USD"),
            ],
            chart: .init(
                kind: .line,
                title: "Daily spend",
                unit: "USD",
                points: [
                    .init(label: "2026-08-10", value: 1.25),
                    .init(label: "2026-08-11", value: 2.75),
                ]))

        let mapped = SyncCoordinator.mapDetails([source])

        #expect(mapped.count == 1)
        #expect(mapped[0].title == "Billing")
        #expect(mapped[0].rows[0].value == "$81.25")
        #expect(mapped[0].chart?.kind == .line)
        #expect(mapped[0].chart?.points.map(\.value) == [1.25, 2.75])
    }

    @Test
    func `old provider payload defaults generic details and plugin branding to absent`() throws {
        let data = Data(#"{"providerID":"xai","providerName":"xAI","isError":false,"lastUpdated":0}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decoded = try decoder.decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.details.isEmpty)
        #expect(decoded.providerIconMonogram == nil)
        #expect(decoded.providerIconTintHex == nil)
    }

    @Test
    func `new provider payload round trips details and plugin branding`() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "acme-ai",
            providerName: "Acme AI",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 42),
            details: [
                .init(title: "Credits", rows: [.init(label: "Remaining", value: "750")]),
            ],
            providerIconMonogram: "AC",
            providerIconTintHex: "#336699")

        let decoded = try JSONDecoder().decode(
            ProviderUsageSnapshot.self,
            from: JSONEncoder().encode(provider))

        #expect(decoded.hasUsableSignal)
        #expect(decoded.details.first?.rows.first?.value == "750")
        #expect(decoded.providerIconMonogram == "AC")
        #expect(decoded.providerIconTintHex == "#336699")
    }
}
