import Foundation
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif
import Testing

#if canImport(SQLite3) || canImport(CSQLite3)
struct CodexProjectDisplayNameTests {
    @Test
    func `saved names match the nearest root without prefix collisions or ambiguous ownership`() throws {
        try Self.withDatabase { url in
            try Self.execute(url, """
            INSERT INTO projects VALUES ('outer', 'My Workspace'), ('inner', 'Nested Project'),
                ('other', 'Other'), ('blank', '  ');
            INSERT INTO project_roots VALUES ('outer', '/work'), ('inner', '/work/nested'),
                ('other', '/ambiguous'), ('outer', '/ambiguous'), ('blank', '/blank');
            """)
            let paths: Set = ["/work", "/work/sub", "/work/nested/src", "/worker", "/ambiguous", "/blank"]
            let reader = CodexThreadMetadataReader(databaseURL: url)
            #expect(reader.projectMetadata(for: paths).names == [
                "/work": "My Workspace", "/work/sub": "My Workspace", "/work/nested/src": "Nested Project",
            ])
            try Self.execute(url, "UPDATE projects SET name = 'Renamed' WHERE id = 'outer'")
            #expect(reader.projectMetadata(for: ["/work"]).names["/work"] == "Renamed")
        }
    }

    @Test
    func `project and session overlays preserve ledger values and unknown folders`() throws {
        try Self.withDatabase { url in
            try Self.execute(url, """
            INSERT INTO projects VALUES ('project', 'Workspace Label');
            INSERT INTO project_roots VALUES ('project', '/work');
            """)
            let projects = [Self.project("/work"), Self.project("/unmatched")]
            let sessionsRoot = url.deletingLastPathComponent().appendingPathComponent("sessions")
            var session = CostUsageSessionBreakdown(
                sessionID: "test",
                lastActivity: Date(timeIntervalSince1970: 0),
                inputTokens: 10,
                cachedInputTokens: 2,
                outputTokens: 3,
                totalTokens: 13,
                requestCount: 1,
                costUSD: 1,
                modelBreakdowns: [],
                projectPath: "/work",
                projectName: "work",
                title: "Existing title")
            session.workingDirectory = "/work"
            var lookups: [URL: Set<String>] = [:]
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [session],
                projects: projects,
                sessionsRoot: sessionsRoot,
                environment: [:],
                projectMetadataLookup: { database, paths, sessionIDs in
                    #expect(lookups[database] == nil)
                    lookups[database] = paths
                    return CodexThreadMetadataReader(databaseURL: database).projectMetadata(
                        for: paths,
                        sessionIDs: sessionIDs)
                })
            var expectedProject = projects[0]
            expectedProject.name = "Workspace Label"
            var expectedSession = session
            expectedSession.projectName = "Workspace Label"
            #expect(result.projects == [expectedProject, projects[1]])
            #expect(result.sessions == [expectedSession])
            #expect(Dictionary(uniqueKeysWithValues: lookups.map {
                ($0.key.resolvingSymlinksInPath(), $0.value)
            }) == [url.resolvingSymlinksInPath(): ["/work", "/unmatched"]])
            #expect(CostUsageFetcher.codexBreakdownsWithMetadata(
                [], projects: projects, sessionsRoot: nil, environment: [:]).projects == projects)
        }
    }

    @Test
    func `relative database homes use original worktree paths and conflicting labels fall back`() throws {
        try Self.withDatabase { url in
            let home = url.deletingLastPathComponent()
            var sources: [CostUsageProjectSourceBreakdown] = []
            for label in ["First", "Second"] {
                let cwd = home.appendingPathComponent(label)
                let state = cwd.appendingPathComponent("state")
                try FileManager.default.createDirectory(
                    at: state,
                    withIntermediateDirectories: true)
                try Self.execute(state.appendingPathComponent("state_5.sqlite"), """
                CREATE TABLE projects (id TEXT, name TEXT);
                CREATE TABLE project_roots (project_id TEXT, path TEXT);
                INSERT INTO projects VALUES ('project', '\(label)');
                INSERT INTO project_roots VALUES ('project', '/work'), ('project', '\(cwd.path)');
                """)
                sources.append(CostUsageProjectSourceBreakdown(
                    name: label,
                    path: cwd.path,
                    totalTokens: 13,
                    totalCostUSD: 1,
                    daily: [],
                    modelBreakdowns: []))
            }
            func project(
                _ sources: [CostUsageProjectSourceBreakdown], path: String = "/work") -> CostUsageProjectBreakdown
            {
                CostUsageProjectBreakdown(
                    name: "work",
                    path: path,
                    totalTokens: 26,
                    totalCostUSD: 2,
                    daily: [],
                    modelBreakdowns: [],
                    sources: sources)
            }
            let first = project([sources[0]])
            let combined = project(sources)
            let unknown = CostUsageProjectSourceBreakdown(
                name: "Unknown", path: nil, totalTokens: nil, totalCostUSD: nil, daily: [], modelBreakdowns: nil)
            let mixed = project([sources[0], unknown])
            let unproven = try project([], path: #require(sources[0].path))
            let renamed = CostUsageFetcher.codexBreakdownsWithMetadata(
                [],
                projects: [first, combined, mixed, unproven],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: ["CODEX_SQLITE_HOME": "state"]).projects
            var expected = first
            expected.name = "First"
            #expect(renamed == [expected, combined, mixed, unproven])
        }
    }

    @Test
    func `missing and legacy databases preserve labels and never create state files`() throws {
        try Self.withDatabase { url in
            try Self.execute(url, "DROP TABLE project_roots; DROP TABLE projects;")
            #expect(CodexThreadMetadataReader(databaseURL: url).projectMetadata(for: ["/work"]).names.isEmpty)
            let missing = url.deletingLastPathComponent().appendingPathComponent("missing.sqlite")
            #expect(CodexThreadMetadataReader(databaseURL: missing).projectMetadata(for: ["/work"]).names.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }
    }

    private static func project(_ path: String) -> CostUsageProjectBreakdown {
        CostUsageProjectBreakdown(
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            totalTokens: 13,
            totalCostUSD: 1,
            daily: [],
            modelBreakdowns: [],
            sources: [CostUsageProjectSourceBreakdown(
                name: "Source", path: path, totalTokens: 13, totalCostUSD: 1, daily: [], modelBreakdowns: [])])
    }

    private static func withDatabase(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state_5.sqlite")
        try self.execute(url, """
        CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT);
        CREATE TABLE project_roots (project_id TEXT, path TEXT);
        """)
        try body(url)
    }

    private static func execute(_ url: URL, _ sql: String) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        let handle = try #require(database)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }
}
#endif
