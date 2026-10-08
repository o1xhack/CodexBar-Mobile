import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized, CostUsageClaudeCacheFixtures())
struct CostUsageClaudeRowCapacityTests {
    private typealias Row = CostUsageScanner.ClaudeUsageRow

    private func expectTight(_ rows: [Row]) {
        var reserved: [Row] = []
        reserved.reserveCapacity(rows.count)
        // Array exposes allocator rounding even when requesting exactly count elements.
        #expect(rows.capacity == reserved.capacity)
        #expect(MemoryLayout<Row>.stride == 160)
    }

    @Test(arguments: [0, 1, 8, 100, 5000, 10000])
    func `file decode reserves the final row count without growth`(count: Int) throws {
        let row = #"{"d":"2026-10-04","m":"synthetic-model","b":false,"p":"parent","in":1,"cr":0,"cc":0,"out":2,"c":3}"#
        let encodedRows = Array(repeating: row, count: count).joined(separator: ",")
        let bytes = Data("{\"mtimeUnixMs\":1,\"size\":2,\"days\":{},\"claudeRows\":[\(encodedRows)]}".utf8)
        let file = try JSONDecoder().decode(CostUsageFileUsage.self, from: bytes)
        let rows = try #require(file.claudeRows)
        #expect(rows.count == count)
        self.expectTight(rows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(file) == encoder.encode(JSONDecoder().decode(LegacyFile.self, from: bytes)))
    }

    private struct LegacyFile: Codable {
        let mtimeUnixMs: Int64
        let size: Int64
        let days: [String: [String: [Int]]]
        let claudeRows: [Row]?
    }

    @Test(arguments: ["", ",\"claudeRows\":null", ",\"claudeRows\":[]"])
    func `optional rows preserve absent null and empty encoding`(field: String) throws {
        let bytes = Data("{\"mtimeUnixMs\":1,\"size\":2,\"days\":{}\(field)}".utf8)
        let file = try JSONDecoder().decode(CostUsageFileUsage.self, from: bytes)
        let legacy = try JSONDecoder().decode(LegacyFile.self, from: bytes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(file.claudeRows == legacy.claudeRows)
        #expect(try encoder.encode(file) == encoder.encode(legacy))
    }

    @Test
    func `parse and incremental merge retain only the final allocation`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 10, day: 4)
        let timestamp = env.isoString(for: day)
        func lines(_ indices: Range<Int>) -> String {
            indices.map { index in
                // Mix keyed and unkeyed rows, exercising both parts of the final array.
                let identity = index.isMultiple(of: 3) ? "" : "\"id\":\"message-\(index)\","
                return """
                {"type":"assistant","timestamp":"\(timestamp)","sessionId":"synthetic-session",\
                "message":{\(identity)"model":"synthetic-model","usage":{"input_tokens":1,"output_tokens":2}}}
                """
            }.joined(separator: "\n") + "\n"
        }
        let file = try env.writeClaudeProjectFile(relativePath: "project/rows.jsonl", contents: lines(0..<5000))
        let parsed = CostUsageScanner.parseClaudeFile(
            fileURL: file,
            range: .init(since: day, until: day),
            providerFilter: .all,
            modelsDevCatalog: ModelsDevCatalog(providers: [:]))
        #expect(parsed.rows.count == 5000)
        self.expectTight(parsed.rows)
        var options = CostUsageScanner.Options()
        options.claudeProjectsRoots = [env.claudeProjectsRoot]
        options.cacheRoot = env.cacheRoot
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(provider: .claude, since: day, until: day, now: day, options: options)
        let initial = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: env.cacheRoot)
        let path = try #require(initial.usage.files.keys.first)
        #expect(initial.usage.files.count == 1)
        try self.expectTight(#require(initial.usage.files[path]?.claudeRows))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines(5000..<10000).utf8))
        try handle.close()
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
            CostUsageScanner.loadDailyReport(provider: .claude, since: day, until: day, now: day, options: options)
        }
        #expect(recorder.snapshot().incrementalTranscriptParses == 1)
        #expect(report.summary?.totalInputTokens == 10000)
        let merged = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: env.cacheRoot)
        let rows = try #require(merged.usage.files[path]?.claudeRows)
        #expect(rows.count == 10000)
        self.expectTight(rows)
        let reparsed = CostUsageScanner.parseClaudeFile(
            fileURL: file,
            range: .init(since: day, until: day),
            providerFilter: .all,
            modelsDevCatalog: ModelsDevCatalog(providers: [:]))
        #expect(rows == reparsed.rows)
    }
}
