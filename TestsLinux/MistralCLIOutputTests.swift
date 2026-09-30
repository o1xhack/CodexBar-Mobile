import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct MistralCLIOutputTests {
    @Test(arguments: [false, true])
    func `Monthly Plan text golden preserves amounts and JSON`(hasReset: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_790_809_200)
        let reset = hasReset ? now.addingTimeInterval(3600) : nil
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 75,
                windowMinutes: nil,
                resetsAt: reset,
                resetDescription: "€19.17 / €25.50 · €6.33 left"),
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "mistral-monthly-plan",
                    title: "Monthly Plan",
                    window: RateWindow(
                        usedPercent: 13,
                        windowMinutes: nil,
                        resetsAt: reset,
                        resetDescription: "€34.07 / €255.00 · €220.93 left")),
                NamedRateWindow(
                    id: "unrelated-window",
                    title: "Unrelated",
                    window: RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: nil, resetDescription: nil)),
            ],
            updatedAt: Date(timeIntervalSince1970: 1))

        let output = CLIRenderer.renderText(
            provider: .mistral,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Mistral",
                status: nil,
                useColor: false,
                resetStyle: .countdown),
            now: now)

        let resetLines = hasReset ? ["Resets in 1h"] : []
        let expected = ["== Mistral ==", "Included API: 25% left [===---------]"] + resetLines
            + ["€19.17 / €25.50 · €6.33 left", "Monthly Plan: 87% left [==========--]"] + resetLines
            + ["€34.07 / €255.00 · €220.93 left"]
        #expect(output == expected.joined(separator: "\n"))

        let data = try JSONEncoder().encode(snapshot)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let extras = try #require(json["extraRateWindows"] as? [[String: Any]])
        #expect(extras.compactMap { $0["id"] as? String } == ["mistral-monthly-plan", "unrelated-window"])
        #expect(extras.first?["title"] as? String == "Monthly Plan")
        let window = try #require(extras.first?["window"] as? [String: Any])
        #expect(window["usedPercent"] as? Double == 13)
        #expect(window["resetDescription"] as? String == "€34.07 / €255.00 · €220.93 left")
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        #expect(decoded.extraRateWindows == snapshot.extraRateWindows)
        #expect(decoded.primary == snapshot.primary)
    }
}
