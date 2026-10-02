import CodexBarSync
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SyncV070LiveDetailsTests {
    @Test
    func `Claude live reset inventory never enters persistent mobile details`() throws {
        let chart = ProviderDetailSection.Chart.makeChart(
            kind: .line,
            points: [(label: "Recorded", value: 10)])
        let sections: [ProviderDetailSection] = [
            .makeSection(rows: [.makeRow(label: "Limit Reset Credits", value: "2 available")]),
            .makeSection(
                title: "Usage",
                rows: [
                    .makeRow(label: "Limit Reset Credits", value: "1 available"),
                    .makeRow(label: "Plan", value: "Synthetic plan"),
                ],
                chart: chart),
        ]
        let mapped = SyncCoordinator.mapSyncedDetails(sections, provider: .claude)
        #expect(mapped.count == 1)
        #expect(mapped.first?.rows.map(\.label) == ["Plan"])
        #expect(mapped.first?.chart?.points.first?.value == 10)
        let data = try CloudSyncConstants.makeJSONEncoder().encode(mapped)
        let wire = try CloudSyncConstants.makeJSONDecoder().decode([SyncProviderDetailSection].self, from: data)
        #expect(wire == mapped)
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(!json.contains("available"))
        #expect(SyncCoordinator.mapSyncedDetails(sections, provider: .codex).count == 2)
        // User plugin detail labels are arbitrary and bypass the native filter.
        #expect(SyncCoordinator.mapDetails(sections).count == 2)
    }
}
