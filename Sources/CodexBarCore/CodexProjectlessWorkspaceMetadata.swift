import Foundation

/// Only explicit desktop ownership can classify a working directory as an independent chat.
/// A missing project id, an unregistered root, or a generated-looking name is not evidence.
struct CodexProjectlessWorkspaceMetadata: Decodable {
    private struct Assignment: Decodable {
        let projectId: String?
    }

    let threadIDs: Set<String>
    let assignedThreadIDs: Set<String>

    private enum CodingKeys: String, CodingKey {
        case threadIDs = "projectless-thread-ids"
        case assignments = "thread-project-assignments"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadIDs = try Set(container.decodeIfPresent([String].self, forKey: .threadIDs) ?? [])
        let assignments = try container.decodeIfPresent([String: Assignment].self, forKey: .assignments) ?? [:]
        self.assignedThreadIDs = Set(assignments.keys)
    }

    static func load(codexHomeDirectory: URL) -> Self? {
        let url = codexHomeDirectory.appendingPathComponent(".codex-global-state.json")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let limit = 8 * 1024 * 1024
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func contains(_ sessionID: String, assignedSessionIDs: Set<String>) -> Bool {
        self.threadIDs.contains(sessionID)
            && !self.assignedThreadIDs.contains(sessionID)
            && !assignedSessionIDs.contains(sessionID)
    }
}
