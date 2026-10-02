import Foundation
import Testing

/// Lexical tripwire for environment dictionary declarations, including optional and multiline spellings.
/// It deliberately checks locals too: only exact, reviewed transient declarations may bypass storage protection.
struct ProcessEnvironmentStorageTests {
    @Test
    func `shipped environment dictionary storage uses the redacting wrapper`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        // This dictionary exists only while constructing the hook's child process environment.
        let transientLocals = ["Sources/CodexBarCore/Hooks/HookEvent.swift": "var env: [String: String] = ["]
        var usedExceptions: Set<String> = []
        for directory in ["Sources", "WidgetExtension"] {
            let enumerator = try #require(FileManager.default.enumerator(
                at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let path = String(url.path.dropFirst(root.path.count + 1))
                guard path != "Sources/CodexBarCore/ProcessEnvironment.swift" else { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                for declaration in try Self.unprotectedDeclarations(in: source) {
                    if transientLocals[path] == declaration {
                        #expect(usedExceptions.insert(path).inserted, "Duplicate transient exception: \(path)")
                    } else {
                        Issue.record("Unprotected environment storage: \(path): \(declaration)")
                    }
                }
            }
        }
        #expect(usedExceptions == Set(transientLocals.keys), "Remove stale transient exceptions")
    }

    @Test
    func `scanner recognizes storage spellings without flagging parameters or wrapped properties`() throws {
        let source = """
        struct Example {
            let environment: [String: String]
            private var baseEnvironment:
                [String: String]?
            var env: Dictionary<String, String> = [:]
            @ProcessEnvironment private var protectedEnvironment: [String: String]
            @ProcessEnvironment
            public private(set) var anotherEnvironment: [String: String]?
            var computedEnvironment: [String: String] { [:] }
            var anotherComputedEnvironment: [String: String]
            { [:] }
            var observedEnvironment: [String: String] { didSet {} }
            var initializedEnvironment: [String: String] = { [:] }()
            lazy var lazyEnvironment: [String: String] = [:]
            nonisolated(unsafe) static var sharedEnvironment: [String: String] = [:]
            func run(environment: [String: String]) {}
        }
        """
        #expect(try Self.unprotectedDeclarations(in: source) == [
            "let environment: [String: String]",
            "private var baseEnvironment: [String: String]?",
            "var env: Dictionary<String, String> = [:]",
            "var observedEnvironment: [String: String] { didSet {} }",
            "var initializedEnvironment: [String: String] = { [:] }()",
            "lazy var lazyEnvironment: [String: String] = [:]",
            "nonisolated(unsafe) static var sharedEnvironment: [String: String] = [:]",
        ])
    }

    private static func unprotectedDeclarations(in source: String) throws -> [String] {
        let pattern = #"(?m)^[\t ]*((?:@\w+(?:\([^\n]*\))?\s+)*"# +
            #"(?:(?:public|private|internal|fileprivate|package|static|lazy|nonisolated|final)"# +
            #"(?:\((?:set|unsafe)\))?\s+)*"# +
            #"(?:let|var)\s+\w*[Ee]nv\w*\s*:\s*"# +
            #"(?:\[\s*String\s*:\s*String\s*\]|Dictionary\s*<\s*String\s*,\s*String\s*>)\??[^\n]*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            let declaration = String(source[range])
            guard !declaration.contains("@ProcessEnvironment") else { return nil }
            // Getters are transient; observers and initializer closures still have stored backing values.
            if !declaration.contains("=") {
                let body = declaration.firstIndex(of: "{").map { String(declaration[$0...]) }
                    ?? String(source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if body.hasPrefix("{"),
                   body.range(of: #"^\{\s*(?:didSet|willSet)\b"#, options: .regularExpression) == nil
                {
                    return nil
                }
            }
            return declaration.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }
}
