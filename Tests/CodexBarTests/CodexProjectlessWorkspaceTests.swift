import Foundation
import Testing
@testable import CodexBarCore
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

struct CodexProjectlessWorkspaceTests {
    @Test
    func `assignment migration flags do not hide unrelated independent chats`() throws {
        try Self.withHome { home in
            try Data(#"""
            {"projectless-thread-ids":["chat","assigned"],"thread-project-assignments":{
                "assigned":{"projectId":"real-project","projectKind":"local","pendingCoreUpdate":false}}}
            """#.utf8)
                .write(to: home.appendingPathComponent(".codex-global-state.json"))
            let result = Self.overlay(
                home,
                projects: [Self.project("/chat"), Self.project("/assigned")],
                sessions: [Self.session("chat", path: "/chat"), Self.session("assigned", path: "/assigned")])
            #expect(result.projects.map(\.isProjectless) == [true, false])
            #expect(result.sessions.map(\.projectName) == [nil, "assigned"])
        }
    }

    @Test
    func `explicit chats use saved titles without changing ledger values or CLI folders`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat", "attachment"])
            let projects = [Self.project("/chat"), Self.project("/attachment"), Self.project("/cli")]
            let sessions = [
                Self.session("chat", path: "/chat", title: "Repair the local service"),
                Self.session("attachment", path: "/attachment", title: "# Files mentioned by the user:\nattachment"),
                Self.session("cli", path: "/cli", title: "A real code project"),
            ]
            let result = Self.overlay(home, projects: projects, sessions: sessions)
            var expected = projects
            expected[0].isProjectless = true
            expected[0].name = "Repair the local service"
            expected[1].isProjectless = true
            expected[1].name = "Independent chat"
            #expect(result.projects == expected)
            var expectedSessions = sessions
            expectedSessions[0].projectName = nil
            expectedSessions[1].projectName = nil
            #expect(result.sessions == expectedSessions)
            #expect(result.projects.map(\.path) == projects.map(\.path))
            #expect(result.projects.map(\.daily) == projects.map(\.daily))
        }
    }

    @Test
    func `mixed directory ownership and unproven worktree sources keep project classification`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat", "second"])
            let shared = Self.project("/shared")
            let worktree = Self.project("/canonical", sources: ["/chat", "/missing"])
            let sessions = [
                Self.session("chat", path: "/shared"), Self.session("cli", path: "/shared"),
                Self.session("second", path: "/chat"),
            ]
            #expect(Self.overlay(home, projects: [shared, worktree], sessions: sessions).projects == [shared, worktree])
            let unknown = Self.project("/unknown", sources: [])
            #expect(Self.overlay(home, projects: [unknown], sessions: []).projects == [unknown])
        }
    }

    @Test
    func `multiple independent sessions in one directory keep a neutral label and their accounting`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["first", "second"])
            let project = Self.project("/shared")
            let result = Self.overlay(home, projects: [project], sessions: [
                Self.session("first", path: "/shared", title: "First topic"),
                Self.session("second", path: "/shared", title: "Second topic"),
            ])
            var expected = project
            expected.name = "Independent chats"
            expected.isProjectless = true
            #expect(result.projects == [expected])
        }
    }

    @Test
    func `missing malformed oversized and unrelated home metadata never infer ownership from a folder name`() throws {
        try Self.withHome { home in
            let path = "/files-mentioned-by-the-user-codex"
            let projects = [Self.project(path)]
            let sessions = [Self.session("chat", path: path)]
            let state = home.appendingPathComponent(".codex-global-state.json")
            #expect(Self.overlay(home, projects: projects, sessions: sessions).projects == projects)
            #expect(!FileManager.default.fileExists(atPath: state.path))
            for invalid in [Data("{".utf8), Data(repeating: 32, count: 8 * 1024 * 1024 + 1)] {
                try invalid.write(to: state)
                #expect(Self.overlay(home, projects: projects, sessions: sessions).projects == projects)
                #expect(try Data(contentsOf: state) == invalid)
            }
            try Self.writeState(home, ids: ["unrelated"])
            #expect(Self.overlay(home, projects: projects, sessions: sessions).projects == projects)
        }
    }

    @Test
    func `merged project copies preserve classification conservatively without changing totals`() throws {
        var chat = Self.project("/shared")
        chat.isProjectless = true
        chat.name = "Chat title"
        let named = Self.project("/shared")
        let classified = try #require(CostUsageFetcher.mergedProjectBreakdowns([chat, chat]).first)
        let mixed = try #require(CostUsageFetcher.mergedProjectBreakdowns([chat, named]).first)
        #expect(classified.isProjectless)
        #expect(!mixed.isProjectless)
        #expect(mixed.name == named.name)
        #expect(CostUsageFetcher.mergedProjectBreakdowns([named, chat]).first?.name == named.name)
        #expect(classified.totalTokens == mixed.totalTokens)
        #expect(classified.totalCostUSD == mixed.totalCostUSD)
        #expect(classified.daily == mixed.daily)
        #expect(classified.path == mixed.path)
    }

    #if canImport(SQLite3) || canImport(CSQLite3)
    @Test(arguments: [false, true])
    func `a null project id in an unregistered CLI folder still requires an explicit marker`(_ marked: Bool) throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: marked ? ["chat"] : [])
            try Self.execute(home.appendingPathComponent("state_5.sqlite"), """
            CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, project_id TEXT);
            INSERT INTO threads VALUES ('chat', 'Saved title', NULL);
            """)
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [Self.session("chat", path: "/cli")],
                projects: [Self.project("/cli")],
                projectSessionIDs: ["/cli": ["chat"]],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: [:])
            #expect(result.projects[0].isProjectless == marked)
            #expect(result.projects[0].name == (marked ? "Saved title" : "cli"))
        }
    }

    @Test(arguments: [4096, 4097])
    func `candidate budget never classifies a partial ownership lookup`(_ count: Int) throws {
        try Self.withHome { home in
            let ids = Set((0..<count).map { "thread-\($0)" })
            try Self.writeState(home, ids: Array(ids))
            try Self.execute(
                home.appendingPathComponent("state_5.sqlite"),
                "CREATE TABLE threads (id TEXT PRIMARY KEY, project_id TEXT)")
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [],
                projects: [Self.project("/chat")],
                projectSessionIDs: ["/chat": ids],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: [:])
            #expect(result.projects[0].isProjectless == (count <= 4096))
        }
    }

    @Test(arguments: [
        "CREATE TABLE projects (id TEXT, name TEXT);",
        """
        CREATE TABLE projects (id TEXT, name TEXT);
        CREATE TABLE project_roots (project_id TEXT, path TEXT);
        INSERT INTO project_roots VALUES ('missing', 'relative/path');
        """,
        """
        CREATE TABLE projects (id TEXT, name TEXT);
        CREATE TABLE project_roots (project_id TEXT, path TEXT);
        WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1025)
        INSERT INTO project_roots SELECT 'missing', '/work/' || x FROM n;
        """,
    ])
    func `incomplete malformed or over budget roots cannot establish independent ownership`(_ schema: String) throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat"])
            try Self.execute(
                home.appendingPathComponent("state_5.sqlite"),
                "CREATE TABLE threads (id TEXT, project_id TEXT);" + schema)
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [],
                projects: [Self.project("/chat")],
                projectSessionIDs: ["/chat": ["chat"]],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: [:])
            #expect(!result.projects[0].isProjectless)
        }
    }

    @Test(arguments: ["('chat', '')", "('chat', '  ')", "('chat', NULL), ('chat', 'project')"])
    func `malformed or conflicting current assignments cannot establish independent ownership`(_ rows: String) throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat"])
            try Self.execute(home.appendingPathComponent("state_5.sqlite"), """
            CREATE TABLE threads (id TEXT, project_id TEXT);
            INSERT INTO threads VALUES \(rows);
            """)
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [],
                projects: [Self.project("/chat")],
                projectSessionIDs: ["/chat": ["chat"]],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: [:])
            #expect(!result.projects[0].isProjectless)
        }
    }

    @Test
    func `registered project roots veto stale chat markers even without a thread assignment`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat", "blank", "conflict"])
            try Self.execute(home.appendingPathComponent("state_5.sqlite"), """
            CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, project_id TEXT);
            INSERT INTO threads VALUES ('chat', 'Saved chat title', NULL);
            CREATE TABLE projects (id TEXT, name TEXT);
            CREATE TABLE project_roots (project_id TEXT, path TEXT);
            INSERT INTO projects VALUES ('a', 'Real project'), ('b', '  '), ('c', 'Other project');
            INSERT INTO project_roots VALUES ('a', '/chat'), ('b', '/blank'),
                ('a', '/conflict'), ('c', '/conflict');
            """)
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [Self.session("chat", path: "/chat/src")],
                projects: [
                    Self.project("/chat/src"),
                    Self.project("/blank"),
                    Self.project("/conflict"),
                ],
                projectSessionIDs: ["/chat/src": ["chat"], "/blank": ["blank"], "/conflict": ["conflict"]],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: [:])
            #expect(result.projects.map(\.isProjectless) == [false, false, false])
            #expect(result.projects.map(\.name) == ["Real project", "blank", "conflict"])
            #expect(result.sessions[0].projectName == "Real project")
        }
    }

    @Test(arguments: [["projectKind": "local"], ["projectId": "saved-project"], [:]])
    func `legacy assignments veto chat markers even when incomplete`(_ assignment: [String: String]) throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat"], assignments: ["chat": assignment])
            let projects = [Self.project("/chat")]
            #expect(Self.overlay(home, projects: projects, sessions: [Self.session("chat", path: "/chat")])
                .projects == projects)
        }
    }

    @Test
    func `missing corrupt locked and unsupported databases preserve project presentation`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat"])
            let database = home.appendingPathComponent("state_5.sqlite")
            let project = Self.project("/chat")
            let session = Self.session("chat", path: "/chat")
            func remainsProject() -> Bool {
                let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                    [session],
                    projects: [project],
                    projectSessionIDs: ["/chat": ["chat"]],
                    sessionsRoot: home.appendingPathComponent("sessions"),
                    environment: [:])
                return result.projects[0].isProjectless == false && result.sessions[0].projectName == "chat"
            }
            #expect(remainsProject())
            #expect(!FileManager.default.fileExists(atPath: database.path))
            try Data("invalid database".utf8).write(to: database)
            #expect(remainsProject())
            try FileManager.default.removeItem(at: database)
            try Self.execute(database, "CREATE TABLE unrelated (id TEXT)")
            #expect(remainsProject())
            try Self.execute(database, "CREATE TABLE threads (id TEXT, title TEXT, agent_path TEXT, project_id TEXT)")
            var handle: OpaquePointer?
            #expect(sqlite3_open(database.path, &handle) == SQLITE_OK)
            let locked = try #require(handle)
            defer { sqlite3_close(locked) }
            #expect(sqlite3_exec(locked, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
            defer { sqlite3_exec(locked, "ROLLBACK", nil, nil, nil) }
            #expect(remainsProject())
        }
    }

    @Test
    func `supported legacy thread tables still classify explicit desktop chats`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat"])
            let database = home.appendingPathComponent("state_5.sqlite")
            try Self.execute(database, "CREATE TABLE threads (id TEXT, title TEXT, agent_path TEXT)")
            let result = CostUsageFetcher.codexBreakdownsWithMetadata(
                [Self.session("chat", path: "/chat")],
                projects: [Self.project("/chat")],
                projectSessionIDs: ["/chat": ["chat"]],
                sessionsRoot: home.appendingPathComponent("sessions"),
                environment: [:])
            #expect(result.projects[0].isProjectless)
        }
    }

    @Test
    func `directory membership includes older contributing files when a thread moves directories`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat"])
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
            let range = CostUsageScanner.CostUsageDayRange(since: day, until: day, calendar: calendar)
            var cache = CostUsageCache()
            for (filename, id, path, modified) in [
                ("chat", "chat", "/shared", Int64(1)),
                ("older", "cli", "/shared", Int64(2)),
                ("latest", "cli", "/elsewhere", Int64(3)),
            ] {
                var usage = CostUsageFileUsage(
                    mtimeUnixMs: modified,
                    size: 1,
                    days: ["2026-01-01": ["gpt-5": [10, 2, 3]]])
                usage.sessionId = id
                usage.projectPath = path
                usage.canonicalProjectPath = path
                cache.files["/synthetic/sessions/\(filename).jsonl"] = usage
            }
            let view = CostUsageStoreReadView(cache: cache, purpose: .report)
            let projects = view.projects(range: range, cacheRoot: home)
            let memberships = view.projectSessionIDs(range: range)
            let sessions = CostUsageScanner.buildCodexSessionBreakdownsFromCache(
                cache: cache, range: range, modelsDevCatalog: ModelsDevCatalog(providers: [:]))
            #expect(sessions.count == 2)
            #expect(sessions.first { $0.sessionID == "cli" }?.workingDirectory == "/elsewhere")
            let shared = try #require(projects.first { $0.path == "/shared" })
            #expect(memberships["/shared"] == ["chat", "cli"])
            #expect(shared.totalTokens == 26)
            let result = Self.overlay(home, projects: projects, sessions: sessions, projectSessionIDs: memberships)
            #expect(result.projects == projects)
        }
    }

    @Test
    func `fresh and cached metadata overlays pick up chat renames and current database assignments`() throws {
        try Self.withHome { home in
            try Self.writeState(home, ids: ["chat", "assigned"])
            let database = home.appendingPathComponent("state_5.sqlite")
            try Self.execute(database, """
            CREATE TABLE threads (id TEXT, title TEXT, agent_path TEXT, project_id TEXT);
            INSERT INTO threads VALUES ('chat', 'Raw old title', NULL, NULL),
                ('assigned', 'Assigned title', NULL, 'project');
            """)
            let projects = [Self.project("/chat"), Self.project("/assigned")]
            let sessions = [Self.session("chat", path: "/chat"), Self.session("assigned", path: "/assigned")]
            var lookupCount = 0
            func overlay() -> (projects: [CostUsageProjectBreakdown], sessions: [CostUsageSessionBreakdown]) {
                CostUsageFetcher.codexBreakdownsWithMetadata(
                    sessions,
                    projects: projects,
                    projectSessionIDs: ["/chat": ["chat"], "/assigned": ["assigned"]],
                    sessionsRoot: home.appendingPathComponent("sessions"),
                    environment: [:],
                    projectMetadataLookup: { database, paths, ids in
                        lookupCount += 1
                        #expect(paths == ["/chat", "/assigned"])
                        #expect(ids == ["chat", "assigned"])
                        return CodexThreadMetadataReader(databaseURL: database).projectMetadata(
                            for: paths,
                            sessionIDs: ids)
                    })
            }
            let index = home.appendingPathComponent("session_index.jsonl")
            try Data("{\"id\":\"chat\",\"thread_name\":\"Saved title\",\"updated_at\":\"2026-01-01T00:00:00Z\"}\n".utf8)
                .write(to: index)
            let first = overlay()
            #expect(lookupCount == 1)
            #expect(first.projects.map(\.isProjectless) == [true, false])
            #expect(first.projects[0].name == "Saved title")
            try Data("{\"id\":\"chat\",\"thread_name\":\"Renamed title\",\"updated_at\":\"2026-01-02T00:00:00Z\"}\n"
                .utf8)
                .write(to: index)
            let renamed = overlay()
            #expect(lookupCount == 2)
            #expect(renamed.projects[0].name == "Renamed title")
            #expect(renamed.projects[0].path == first.projects[0].path)
            #expect(renamed.projects[0].daily == first.projects[0].daily)
            #expect(renamed.projects[0].sources == first.projects[0].sources)
        }
    }

    private static func execute(_ url: URL, _ sql: String) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        let handle = try #require(database)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }
    #endif

    private static func withHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private static func writeState(
        _ home: URL, ids: [String], assignments: [String: [String: String]] = [:]) throws
    {
        let state: [String: Any] = ["projectless-thread-ids": ids, "thread-project-assignments": assignments]
        try JSONSerialization.data(withJSONObject: state)
            .write(to: home.appendingPathComponent(".codex-global-state.json"))
    }

    private static func overlay(
        _ home: URL,
        projects: [CostUsageProjectBreakdown],
        sessions: [CostUsageSessionBreakdown],
        projectSessionIDs: [String: Set<String>]? = nil)
        -> (projects: [CostUsageProjectBreakdown], sessions: [CostUsageSessionBreakdown])
    {
        let memberships = projectSessionIDs ?? Dictionary(grouping: sessions, by: { $0.workingDirectory ?? "" })
            .mapValues { Set($0.map(\.sessionID)) }
        return CostUsageFetcher.codexBreakdownsWithProjectlessMetadata(
            projects: projects,
            sessions: sessions,
            projectSessionIDs: memberships,
            metadata: CodexProjectlessWorkspaceMetadata.load(codexHomeDirectory: home),
            assignedSessionIDs: [])
    }

    private static func session(
        _ id: String, path: String, title: String? = "Chat title") -> CostUsageSessionBreakdown
    {
        var session = CostUsageSessionBreakdown(
            sessionID: id,
            lastActivity: Date(timeIntervalSince1970: 0),
            inputTokens: 10,
            cachedInputTokens: 2,
            outputTokens: 3,
            totalTokens: 13,
            requestCount: 1,
            costUSD: 1,
            modelBreakdowns: [],
            projectPath: path,
            projectName: URL(fileURLWithPath: path).lastPathComponent,
            title: title)
        session.workingDirectory = path
        return session
    }

    private static func project(
        _ path: String, sources: [String]? = nil) -> CostUsageProjectBreakdown
    {
        let daily = [CostUsageDailyReport.Entry(
            date: "2026-01-01",
            inputTokens: 10,
            outputTokens: 3,
            totalTokens: 13,
            costUSD: 1,
            modelsUsed: nil,
            modelBreakdowns: nil)]
        return CostUsageProjectBreakdown(
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            totalTokens: 13,
            totalCostUSD: 1,
            daily: daily,
            modelBreakdowns: [],
            sources: (sources ?? [path]).map {
                CostUsageProjectSourceBreakdown(
                    name: URL(fileURLWithPath: $0).lastPathComponent,
                    path: $0,
                    totalTokens: 13,
                    totalCostUSD: 1,
                    daily: daily,
                    modelBreakdowns: [])
            })
    }
}
