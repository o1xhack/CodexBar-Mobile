#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif
import Foundation

extension CodexThreadMetadataReader {
    typealias ProjectMetadata = (names: [String: String], ownedPaths: Set<String>, assignedSessionIDs: Set<String>)

    /// Names and ownership share one bounded snapshot; uncertainty keeps the Projects fallback.
    func projectMetadata(for paths: Set<String>, sessionIDs: Set<String> = []) -> ProjectMetadata {
        let fallback: ProjectMetadata = ([:], paths, sessionIDs)
        guard !paths.isEmpty || !sessionIDs.isEmpty else { return fallback }
        #if canImport(SQLite3) || canImport(CSQLite3)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(self.databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database = handle
        else {
            if let handle { sqlite3_close(handle) }
            return fallback
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        sqlite3_progress_handler(database, 100_000, { _ in 1 }, nil)
        guard sqlite3_exec(database, "BEGIN", nil, nil, nil) == SQLITE_OK else { return fallback }
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
        guard let roots = Self.projectRoots(database) else { return fallback }
        var names: [String: String] = [:]
        var ownedPaths: Set<String> = []
        for path in paths where (path as NSString).isAbsolutePath {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            let matches = roots.filter {
                normalized == $0.path || normalized.hasPrefix($0.path == "/" ? "/" : $0.path + "/")
            }
            guard let length = matches.map(\.path.count).max() else { continue }
            ownedPaths.insert(path)
            let closest = matches.filter { $0.path.count == length }
            guard let first = closest.first, first.id != nil,
                  Set(closest.map(\.id)).count == 1 else { continue }
            names[path] = first.name
        }
        return (names, ownedPaths, Self.assignedProjectSessionIDs(database, for: sessionIDs) ?? sessionIDs)
        #else
        return fallback
        #endif
    }

    #if canImport(SQLite3) || canImport(CSQLite3)
    private static func projectRoots(_ database: OpaquePointer) -> [(id: String?, name: String?, path: String)]? {
        let query = """
        SELECT p.id, p.name, r.path FROM project_roots r
        LEFT JOIN projects p ON r.project_id = p.id LIMIT 1025
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            // Only the absence of both tables is a supported legacy schema.
            var schema: OpaquePointer?
            let query = "SELECT COUNT(*) FROM sqlite_master WHERE name IN ('projects', 'project_roots')"
            guard sqlite3_prepare_v2(database, query, -1, &schema, nil) == SQLITE_OK, let schema else { return nil }
            defer { sqlite3_finalize(schema) }
            return sqlite3_step(schema) == SQLITE_ROW && sqlite3_column_int(schema, 0) == 0 ? [] : nil
        }
        defer { sqlite3_finalize(statement) }
        var roots: [(id: String?, name: String?, path: String)] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return roots }
            guard status == SQLITE_ROW, roots.count < 1024,
                  let rawPath = Self.string(statement, column: 2),
                  (rawPath as NSString).isAbsolutePath else { return nil }
            roots.append((
                Self.string(statement, column: 0),
                Self.string(statement, column: 1),
                URL(fileURLWithPath: rawPath).standardizedFileURL.path))
        }
    }

    private static func assignedProjectSessionIDs(
        _ database: OpaquePointer,
        for sessionIDs: Set<String>) -> Set<String>?
    {
        guard !sessionIDs.isEmpty else { return [] }
        guard sessionIDs.count <= 4096 else { return nil }
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &schema, nil) == SQLITE_OK,
              let schema else { return nil }
        defer { sqlite3_finalize(schema) }
        var columns: Set<String> = []
        while true {
            let status = sqlite3_step(schema)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { return nil }
            if let name = Self.string(schema, column: 1) { columns.insert(name) }
        }
        guard columns.contains("id") else { return nil }
        guard columns.contains("project_id") else { return [] }
        var statement: OpaquePointer?
        let query = "SELECT project_id FROM threads WHERE id = ?1"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        var result: Set<String> = []
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for sessionID in sessionIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            guard sqlite3_bind_text(statement, 1, sessionID, -1, transient) == SQLITE_OK else { return nil }
            let status = sqlite3_step(statement)
            guard status == SQLITE_ROW || status == SQLITE_DONE else { return nil }
            if status == SQLITE_ROW {
                // Any non-null assignment, including malformed values, vetoes a stale marker.
                if sqlite3_column_type(statement, 0) != SQLITE_NULL { result.insert(sessionID) }
                guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
            }
        }
        return result
    }
    #endif
}
