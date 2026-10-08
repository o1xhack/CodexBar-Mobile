import Foundation
import Testing
@testable import CodexBarCore

struct JetBrainsIDEDetectorTests {
    @Test
    func `parses IDE directory case insensitive`() {
        let info = JetBrainsIDEDetector._parseIDEDirectoryForTesting(
            dirname: "Webstorm2024.1",
            basePath: "/test")

        #expect(info?.name == "WebStorm")
        #expect(info?.version == "2024.1")
        #expect(info?.basePath == "/test/Webstorm2024.1")
    }

    @Test
    func `latest IDE uses readable modification dates and stable fallback`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ides = (0..<3).map { index in
            JetBrainsIDEInfo(
                name: "IDE",
                version: "\(index)",
                basePath: root.path,
                quotaFilePath: root.appendingPathComponent("quota-\(index).xml").path)
        }
        #expect(JetBrainsIDEDetector.latestIDE(in: []) == nil)
        #expect(JetBrainsIDEDetector.latestIDE(in: ides) == ides[0])
        for index in 1..<3 {
            try Data().write(to: URL(fileURLWithPath: ides[index].quotaFilePath))
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(index) * 1000)],
                ofItemAtPath: ides[index].quotaFilePath)
        }
        #expect(JetBrainsIDEDetector.latestIDE(in: ides) == ides[2])
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: ides[2].quotaFilePath)
        #expect(JetBrainsIDEDetector.latestIDE(in: ides) == ides[1])
    }
}
