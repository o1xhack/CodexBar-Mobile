import Foundation
import Testing
@testable import CodexBarCore

struct OneConsoleJSONTests {
    @Test
    func `object lookup checks the current dictionary before descendants`() {
        let value: [String: Any] = ["quota": 1, "data": ["quota": 2]]
        let result = OneConsoleJSON.findObject(containingAnyOf: ["quota"], in: value)

        #expect(result?["quota"] as? Int == 1)
    }

    @Test
    func `object lookup traverses nested arrays with exact key matching`() {
        let value: [Any] = ["ignored", ["QUOTA": 1], [["quota": 2]]]
        let result = OneConsoleJSON.findObject(containingAnyOf: ["quota"], in: value)

        #expect(result?["quota"] as? Int == 2)
        #expect(OneConsoleJSON.findObject(containingAnyOf: [], in: value) == nil)
    }

    @Test
    func `raw lookup matches keys case insensitively and retains null values`() {
        let value: [String: Any] = ["COUNT": NSNull(), "data": ["count": 42]]

        #expect(OneConsoleJSON.findFirstValue(forKeys: ["count"], in: value) is NSNull)
        #expect(OneConsoleJSON.findFirstInt(forKeys: ["count"], in: value) == 42)
    }

    @Test
    func `converted lookup traverses arrays and skips invalid scalar values`() {
        let value: [Any] = ["ignored", ["COUNT": "invalid"], [["Count": "42"]]]

        #expect(OneConsoleJSON.findFirstInt(forKeys: ["count"], in: value) == 42)
        #expect(OneConsoleJSON.findFirstValue(forKeys: ["missing"], in: value) == nil)
        #expect(OneConsoleJSON.findFirstString(forKeys: [], in: value) == nil)
    }

    @Test
    func `string lookup honors caller key priority across the full tree`() {
        let value: [String: Any] = [
            "token": "generic-token",
            "data": [
                "secToken": "preferred-sec-token",
            ],
        ]

        let result = OneConsoleJSON.findFirstString(
            forKeys: ["secToken", "token"],
            in: value)

        #expect(result == "preferred-sec-token")
    }

    @Test
    func `lookup skips invalid values before a nested valid value`() {
        let value: [String: Any] = [
            "count": "not-a-number",
            "data": [
                "count": "42",
            ],
        ]

        #expect(OneConsoleJSON.findFirstInt(forKeys: ["count"], in: value) == 42)
    }

    @Test
    func `array lookup preserves key priority and skips invalid values`() {
        let value: [String: Any] = [
            "fallback": [1],
            "preferred": "not-an-array",
            "data": [
                "preferred": [2, 3],
            ],
        ]

        let result = OneConsoleJSON.findFirstArray(
            forKeys: ["preferred", "fallback"],
            in: value) as? [Int]

        #expect(result == [2, 3])
    }

    @Test
    func `date only string round trips`() throws {
        let date = try #require(OneConsoleJSON.date("2026-07-28"))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        #expect(formatter.string(from: date) == "2026-07-28")
    }

    @Test
    func `numeric zero date is treated as missing`() {
        #expect(OneConsoleJSON.date(0) == nil)
    }
}
