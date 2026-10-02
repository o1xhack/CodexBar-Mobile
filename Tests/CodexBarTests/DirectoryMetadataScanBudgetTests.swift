import Foundation
import Testing
@testable import CodexBarCore

struct DirectoryMetadataScanBudgetTests {
    private let urls = ["first.jsonl", "skip.txt", "last.jsonl"].map {
        URL(fileURLWithPath: "/synthetic-sessions/\($0)")
    }

    @Test
    func `expired enumeration budget does not start file enrichment`() {
        let budget = DirectoryMetadataScanBudget(
            maxEntryCount: 512,
            maxDepth: 1,
            timeLimit: 1,
            startedAt: .distantPast)
        var enriched: [URL] = []
        let results = budget.compactMapWhileTimeRemains(self.urls) { url in
            enriched.append(url)
            return url
        }

        #expect(enriched.isEmpty)
        #expect(results.isEmpty)
    }

    @Test
    func `enrichment stops between files when the shared deadline expires`() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        let budget = DirectoryMetadataScanBudget(
            maxEntryCount: 512,
            maxDepth: 1,
            timeLimit: 1,
            startedAt: startedAt)
        var now = startedAt
        var enriched: [URL] = []
        let results = budget.compactMapWhileTimeRemains(self.urls, clock: { now }, transform: { url in
            enriched.append(url)
            now = startedAt.addingTimeInterval(2)
            return url
        })

        #expect(enriched == [self.urls[0]])
        #expect(results == [self.urls[0]])
    }

    @Test
    func `live budget preserves enrichment filtering and input order`() {
        let budget = DirectoryMetadataScanBudget(
            maxEntryCount: 512,
            maxDepth: 1,
            timeLimit: 1,
            startedAt: .distantFuture)
        let results = budget.compactMapWhileTimeRemains(self.urls) { url in
            url.pathExtension == "jsonl" ? url.lastPathComponent : nil
        }

        #expect(results == ["first.jsonl", "last.jsonl"])
    }

    @Test(arguments: [0.149, 0.15, 0.151])
    func `adaptive entry retention honors the injected deadline`(elapsed: TimeInterval) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryMetadataScanBudgetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: root.appendingPathComponent("entry.jsonl"))
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        var budget = DirectoryMetadataScanBudget(
            maxEntryCount: 1,
            maxDepth: 1,
            timeLimit: SessionScanConfig().adaptiveDirectoryScanBudget,
            startedAt: startedAt)
        var clockReads = 0

        let files = budget.files(in: root, clock: {
            clockReads += 1
            return startedAt.addingTimeInterval(clockReads < 3 ? 0 : elapsed)
        })

        #expect(clockReads == 3)
        #expect(files.count == (elapsed < 0.15 ? 1 : 0))
    }

    @Test(arguments: [false, true])
    func `desktop root discovery honors the shared deadline`(expired: Bool) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopRootScanBudgetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent(
            "Library/Application Support/Claude/claude-code-sessions/.claude/projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        var budget = DirectoryMetadataScanBudget(
            maxEntryCount: 512,
            maxDepth: 1,
            timeLimit: 1,
            startedAt: expired ? .distantPast : .distantFuture)

        let roots = ClaudeDesktopProjectsLocator.roots(
            homeDirectory: root,
            fileManager: .default,
            budget: &budget)

        #expect(roots == (expired ? [] : [projects]))
    }
}
