import Foundation
import Testing
@testable import CodexBarCore

/// Old fork stores must take the upstream revision-14 reparse for resumed Fast tiers.
/// Validate the scoped cache and final history rather than bypassing newer pricing semantics.
struct CostUsageForkParserRevisionTests {
    @Test(arguments: [false, true])
    func `revision 12 files reparse to current pricing without losing completed history`(growing: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 10, day: 7)
        let model = "gpt-5.6-luna"
        func header(_ id: String, creator: String?) throws -> String {
            var payload: [String: Any] = ["id": id]
            if let creator { payload["creator_account_id"] = creator }
            return try env.jsonl([
                ["type": "session_meta", "timestamp": env.isoString(for: day), "payload": payload],
                ["type": "turn_context", "timestamp": env.isoString(for: day), "payload": ["model": model]],
            ]) + "\n"
        }
        func event(_ input: Int, second: Double) throws -> String {
            try env.jsonl([[
                "type": "event_msg",
                "timestamp": env.isoString(for: day.addingTimeInterval(second)),
                "payload": [
                    "type": "token_count",
                    "info": ["total_token_usage": [
                        "input_tokens": input,
                        "cached_input_tokens": 0,
                        "output_tokens": 0,
                    ]],
                ],
            ]]) + "\n"
        }
        _ = try env.writeCodexSessionFile(
            day: day,
            filename: "chatgpt.jsonl",
            contents: header("chatgpt", creator: "acct_fixture") + event(100, second: 1) + event(200, second: 2))
        _ = try env.writeCodexSessionFile(
            day: day, filename: "apikey.jsonl", contents: header("apikey", creator: nil) + event(50, second: 1))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 0
        options.preferNewestCodexSessionsFirst = false
        let clean = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day, options: options)
        #expect(clean.summary?.totalTokens == 250)

        // Age the store to the 0.74.1.1 shape: revision 12 rows that never recorded the creator account.
        var legacy = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        let chatgptPath = try #require(legacy.files.keys.first { $0.hasSuffix("/chatgpt.jsonl") })
        let apikeyPath = try #require(legacy.files.keys.first { $0.hasSuffix("/apikey.jsonl") })
        for path in [chatgptPath, apikeyPath] {
            legacy.files[path]?.codexParserRevision = CostUsageScanner.codexCreatorAccountParserRevision - 1
            legacy.files[path]?.codexSession?.hasCreatorAccount = nil
        }
        let cachedRows = try #require(legacy.files[chatgptPath]?.codexRows?.map(\.input))
        #expect(cachedRows == [100, 100])
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, home: env.codexStoreHome, cache: legacy)
        if growing {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: chatgptPath))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(event(300, second: 3).utf8))
            try handle.close()
        }

        // Revision 14 changes resumed Fast pricing. Revision 12 cannot use the old metadata-only
        // adoption shortcut: a bounded scan remains incomplete until it can re-read the source.
        options.maxCodexScanBytesPerRefresh = 1
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day.addingTimeInterval(3), options: options)
        let pending = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        #expect(pending.codexScanCatchUpPending == true)

        options.maxCodexScanBytesPerRefresh = 512 * 1024 * 1024
        let final = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day.addingTimeInterval(4), options: options)
        var referenceOptions = options
        referenceOptions.cacheRoot = env.root.appendingPathComponent("reference-cache")
        let expected = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day.addingTimeInterval(4), options: referenceOptions)
        #expect(final.data == expected.data)
        #expect(final.summary?.totalTokens == (growing ? 350 : 250))
        let reopened = CostUsageStore(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
            .syncLoadCodexCache(calendar: .current)
        #expect(reopened.files[chatgptPath]?.codexRows?.map(\.input) == (growing ? [100, 100, 100] : [100, 100]))
        #expect(reopened.files[chatgptPath]?.codexSession?.hasCreatorAccount == true)
        // The completed migration must restore persisted token history for fork-child baselines.
        #expect(reopened.files[chatgptPath]?.codexTokenSnapshots?.compactMap { $0.total?.input }
            == (growing ? [100, 200, 300] : [100, 200]))
        #expect(reopened.files[chatgptPath]?.codexTokenCheckpoints?.isEmpty == false)
        #expect(reopened.files[apikeyPath]?.codexTokenSnapshots?.compactMap { $0.total?.input } == [50])
    }

    @Test(arguments: [false, true])
    func `a reparsed legacy parent still resolves a fork child that appears later`(parentGrows: Bool) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 10, day: 7)
        let model = "gpt-5.6-luna"
        func event(_ input: Int, second: Double) throws -> String {
            try env.jsonl([[
                "type": "event_msg",
                "timestamp": env.isoString(for: day.addingTimeInterval(second)),
                "payload": [
                    "type": "token_count",
                    "info": ["total_token_usage": [
                        "input_tokens": input, "cached_input_tokens": 0, "output_tokens": 0,
                    ]],
                ],
            ]]) + "\n"
        }
        let parentHeader = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": env.isoString(for: day),
                "payload": ["id": "parent", "creator_account_id": "acct_fixture"],
            ],
            ["type": "turn_context", "timestamp": env.isoString(for: day), "payload": ["model": model]],
        ]) + "\n"
        let parentPath = try env.writeCodexSessionFile(
            day: day,
            filename: "parent.jsonl",
            contents: parentHeader + event(100, second: 1) + event(300, second: 2))
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 0
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageScanner.loadDailyReport(provider: .codex, since: day, until: day, now: day, options: options)

        var legacy = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        let parentKey = try #require(legacy.files.keys.first { $0.hasSuffix("/" + parentPath.lastPathComponent) })
        legacy.files[parentKey]?.codexParserRevision = CostUsageScanner.codexCreatorAccountParserRevision - 1
        legacy.files[parentKey]?.codexSession?.hasCreatorAccount = nil
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, home: env.codexStoreHome, cache: legacy)
        // Reparse the unchanged parent to the current pricing revision.
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day.addingTimeInterval(3), options: options)
        let adopted = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot, home: env.codexStoreHome)
        #expect(adopted.files[parentKey]?.hasCurrentCodexParser == true)
        #expect(adopted.files[parentKey]?.codexTokenSnapshots?.compactMap { $0.total?.input } == [100, 300])
        if parentGrows {
            // The parent keeps running after the fork point; its tail must not be copied into the child.
            let handle = try FileHandle(forWritingTo: parentPath)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(event(400, second: 6).utf8))
            try handle.close()
        }

        // A child forked from the parent's first turn appears afterwards; it must inherit the baseline.
        let childHeader = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": env.isoString(for: day.addingTimeInterval(1.5)),
                "payload": ["id": "child", "forked_from_id": "parent", "creator_account_id": "acct_fixture"],
            ],
            [
                "type": "turn_context",
                "timestamp": env.isoString(for: day.addingTimeInterval(1.5)),
                "payload": ["model": model],
            ],
        ]) + "\n"
        _ = try env.writeCodexSessionFile(
            day: day,
            filename: "child.jsonl",
            contents: childHeader + event(100, second: 1) + event(150, second: 4))
        let final = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day.addingTimeInterval(5), options: options)
        var referenceOptions = options
        referenceOptions.cacheRoot = env.root.appendingPathComponent("reference-cache")
        let expected = CostUsageScanner.loadDailyReport(
            provider: .codex, since: day, until: day, now: day.addingTimeInterval(5), options: referenceOptions)
        #expect(final.data == expected.data)
        #expect(final.summary?.totalTokens == expected.summary?.totalTokens)
        // Parent 300 (+100 when it grows) plus the child's own 50 after the fork point.
        #expect(final.summary?.totalTokens == (parentGrows ? 450 : 350))
    }

    @Test
    func `older revisions and current files are left to the upstream path`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let url = env.root.appendingPathComponent("missing.jsonl")
        var usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1, size: 1, days: [:], parsedBytes: 1, codexRows: [], codexScanComplete: true)
        usage.codexParserRevision = CostUsageScanner.codexCreatorAccountParserRevision - 2
        #expect(CostUsageScanner.codexFileUsageAdoptingCreatorAccountRevision(usage, fileURL: url) == nil)
        usage.codexParserRevision = CostUsageScanner.codexCreatorAccountParserRevision
        #expect(CostUsageScanner.codexFileUsageAdoptingCreatorAccountRevision(usage, fileURL: url) == nil)
        #expect(CostUsageScanner.codexFileUsageAdoptingCreatorAccountRevision(nil, fileURL: url) == nil)
        // A revision-12 file that cannot be read, or has no session_meta, is handed to the upstream path.
        usage.codexParserRevision = CostUsageScanner.codexCreatorAccountParserRevision - 1
        #expect(!CostUsageScanner.codexFileUsageNeedsCreatorAccountRevision(usage))
        #expect(CostUsageScanner.codexFileUsageAdoptingCreatorAccountRevision(usage, fileURL: url) == nil)
        let bare = env.root.appendingPathComponent("bare.jsonl")
        try Data("{\"type\":\"event_msg\"}\n".utf8).write(to: bare)
        #expect(CostUsageScanner.codexFileUsageAdoptingCreatorAccountRevision(usage, fileURL: bare) == nil)
        // A readable leaf must also take revision 14's semantic reparse, not just stamp metadata.
        let apiKey = env.root.appendingPathComponent("apikey.jsonl")
        try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"api\"}}\n".utf8).write(to: apiKey)
        #expect(CostUsageScanner.codexFileUsageAdoptingCreatorAccountRevision(usage, fileURL: apiKey) == nil)
    }
}
