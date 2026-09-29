import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct CodexAppServerDaemonTests {
    @Test
    func `process matching excludes stdio probes and other executables`() {
        #expect(CodexHomeScope.isAppServer(arguments: ["/package/bin/codex", "app-server", "--listen", "unix://"]))
        #expect(!CodexHomeScope.isAppServer(arguments: ["/package/bin/codex", "app-server"]))
        #expect(!CodexHomeScope.isAppServer(arguments: ["/package/bin/node", "app-server", "--listen", "unix://"]))
        #expect(!CodexHomeScope.isAppServer(arguments: ["codex", "exec", "app-server", "--listen", "unix://"]))
        #expect(!CodexHomeScope.isAppServer(arguments: []))
    }

    @Test(arguments: ["daemon.pid", "app-server.pid"], ["plain", "symlink", "resolved-symlink"])
    func `promotion restarts the live home daemon once after publishing auth`(
        _ filename: String, _ socketPath: String) async throws
    {
        let container = try CodexAccountPromotionTestContainer(suiteName: "daemon-promotion")
        defer { container.tearDown() }
        let target = try container.createManagedAccount(
            persistedEmail: "managed@example.com", authAccountID: "acct-managed")
        try container.persistAccounts([target])
        _ = try container.writeLiveOAuthAuthFile(email: "live@example.com", accountID: "acct-live")
        try Self.writePID(home: container.liveHomeURL, filename: filename)
        if socketPath != "plain" { try Self.writeSocketSymlink(home: container.liveHomeURL) }
        var calls: [String] = []
        let daemon = CodexAppServerDaemon(isAppServerProcess: { $0 == 123 }, run: { command, env in
            calls.append(command)
            #expect(env["CODEX_HOME"] == container.liveHomeURL.resolvingSymlinksInPath().path)
            let identity = try container.identityReader.loadAccountIdentity(homePath: container.liveHomeURL.path)
            #expect(identity.email == "managed@example.com")
            return Self.version(home: container.liveHomeURL, resolveSocket: socketPath == "resolved-symlink")
        })
        let result = try await container.makeService(daemon: daemon).promoteManagedAccount(id: target.id)
        #expect(result.outcome == .promoted)
        #expect(result.daemonRestartNote == nil)
        #expect(calls == ["version", "restart"])
    }

    @Test(arguments: [false, true])
    func `absent or stale daemon does not invoke the CLI`(_ stale: Bool) async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "daemon-absent")
        defer { container.tearDown() }
        if stale { try Self.writePID(home: container.liveHomeURL) }
        let daemon = CodexAppServerDaemon(isAppServerProcess: { _ in false }, run: { _, _ in
            Issue.record("Should not invoke the CLI without a matching process")
            return ""
        })
        let note = await daemon.restartIfRunning(homeURL: container.liveHomeURL, environment: [:])
        #expect(note == nil)
    }

    @Test(arguments: ["version", "restart"])
    func `unsupported daemon command or restart failure preserves promotion with a note`(
        _ failure: String) async throws
    {
        let container = try CodexAccountPromotionTestContainer(suiteName: "daemon-failure")
        defer { container.tearDown() }
        let target = try container.createManagedAccount(
            persistedEmail: "managed@example.com", authAccountID: "acct-managed")
        try container.persistAccounts([target])
        try Self.writePID(home: container.liveHomeURL)
        var calls: [String] = []
        let daemon = CodexAppServerDaemon(isAppServerProcess: { _ in true }, run: { command, _ in
            calls.append(command)
            if command == failure {
                throw SubprocessRunnerError.nonZeroExit(code: 2, stderr: "synthetic command failure")
            }
            return Self.version(home: container.liveHomeURL)
        })
        let coordinator = CodexAccountPromotionCoordinator(service: container.makeService(daemon: daemon))
        let result = try await coordinator.promote(managedAccountID: target.id).get()
        #expect(result.outcome == .promoted)
        #expect(result.didMutateLiveAuth)
        #expect(container.settings.codexActiveSource == .liveSystem)
        #expect(result.daemonRestartNote == "Account switched; restart the Codex background server manually.")
        #expect(coordinator.daemonRestartNote == result.daemonRestartNote)
        let menu = MenuDescriptor.build(
            provider: .codex,
            store: container.usageStore,
            settings: container.settings,
            account: AccountInfo(email: nil, plan: nil),
            codexAccountPromotionCoordinator: coordinator,
            updateReady: false)
        #expect(menu.sections.flatMap(\.entries).contains {
            if case let .text(text, _) = $0 { return text == result.daemonRestartNote }
            return false
        })
        #expect(calls == (failure == "version" ? ["version"] : ["version", "restart"]))
    }

    @Test(arguments: ["other-home", "unmanaged", "stopped"], [false, true])
    func `only a managed daemon answering for the promoted home can restart`(
        _ mismatch: String, _ symlinkedSocket: Bool) async throws
    {
        let container = try CodexAccountPromotionTestContainer(suiteName: "daemon-home-match")
        defer { container.tearDown() }
        try Self.writePID(home: container.liveHomeURL)
        if symlinkedSocket {
            try Self.writeSocketSymlink(home: container.liveHomeURL)
            try Self.writeSocketSymlink(home: container.managedHomesURL)
        }
        var calls: [String] = []
        let daemon = CodexAppServerDaemon(isAppServerProcess: { _ in true }, run: { command, env in
            calls.append(command)
            #expect(env["HOME"] == "/synthetic-user")
            let home = mismatch == "other-home" ? container.managedHomesURL : container.liveHomeURL
            return Self.version(
                home: home,
                backend: mismatch == "unmanaged" ? "" : "pid",
                status: mismatch == "stopped" ? "notRunning" : "running")
        })
        let note = await daemon.restartIfRunning(
            homeURL: container.liveHomeURL, environment: ["HOME": "/synthetic-user", "CODEX_HOME": "/wrong-home"])
        #expect(note == nil)
        #expect(calls == ["version"])
    }

    @Test(arguments: [false, true])
    func `symlinked home and outside home socket retain the destination scope`(_ resolveSocket: Bool) async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "daemon-home-symlink")
        defer { container.tearDown() }
        let alias = container.rootURL.appendingPathComponent("home-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: container.liveHomeURL)
        try Self.writePID(home: alias)
        try Self.writeSocketSymlink(home: container.liveHomeURL)
        var calls: [String] = []
        let daemon = CodexAppServerDaemon(isAppServerProcess: { $0 == 123 }, run: { command, env in
            calls.append(command)
            #expect(env["CODEX_HOME"] == container.liveHomeURL.resolvingSymlinksInPath().path)
            #expect(env["HOME"] == "/synthetic-user")
            return Self.version(home: alias, resolveSocket: resolveSocket)
        })
        let note = await daemon.restartIfRunning(
            homeURL: alias, environment: ["HOME": "/synthetic-user", "CODEX_HOME": "/wrong-home"])
        #expect(note == nil)
        #expect(calls == ["version", "restart"])
    }

    @Test(arguments: [false, true])
    func `dangling socket link cannot override a failed CLI probe`(_ probeThrows: Bool) async throws {
        let container = try CodexAccountPromotionTestContainer(suiteName: "daemon-dangling-socket")
        defer { container.tearDown() }
        try Self.writePID(home: container.liveHomeURL)
        try Self.writeSocketSymlink(home: container.liveHomeURL)
        let socket = container.liveHomeURL.appendingPathComponent("app-server-control/app-server-control.sock")
        try FileManager.default.removeItem(at: socket.resolvingSymlinksInPath())
        #expect(!FileManager.default.fileExists(atPath: socket.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: socket.path).hasSuffix("liveHome.sock"))
        var calls: [String] = []
        let daemon = CodexAppServerDaemon(isAppServerProcess: { _ in true }, run: { command, _ in
            calls.append(command)
            if probeThrows {
                throw SubprocessRunnerError.nonZeroExit(code: 1, stderr: "synthetic socket unavailable")
            }
            return Self.version(home: container.liveHomeURL, status: "notRunning")
        })
        let note = await daemon.restartIfRunning(homeURL: container.liveHomeURL, environment: [:])
        #expect((note != nil) == probeThrows)
        #expect(calls == ["version"])
    }

    private static func writePID(home: URL, filename: String = "daemon.pid") throws {
        let directory = home.appendingPathComponent("app-server-daemon")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"pid":123,"processStartTime":"synthetic"}"#.utf8)
            .write(to: directory.appendingPathComponent(filename))
    }

    private static func writeSocketSymlink(home: URL) throws {
        let socket = home.appendingPathComponent("app-server-control/app-server-control.sock")
        let target = home.deletingLastPathComponent().appendingPathComponent("\(home.lastPathComponent).sock")
        // The CLI probe is injected, but path resolution must follow a real filesystem symlink.
        try Data().write(to: target)
        try FileManager.default.createDirectory(
            at: socket.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: socket, withDestinationURL: target)
    }

    private static func version(
        home: URL, backend: String = "pid", status: String = "running", resolveSocket: Bool = false) -> String
    {
        var socket = home.resolvingSymlinksInPath().appendingPathComponent("app-server-control/app-server-control.sock")
        if resolveSocket { socket = socket.resolvingSymlinksInPath().standardizedFileURL }
        return "{\"status\":\"\(status)\",\"backend\":\"\(backend)\",\"socketPath\":\"\(socket.path)\"}"
    }
}
