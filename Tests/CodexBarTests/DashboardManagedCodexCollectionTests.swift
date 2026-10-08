import CodexBarCore
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI

struct DashboardManagedCodexCollectionTests {
    @Test
    func `dashboard CLI emits redacted managed accounts from an isolated home`() throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        let appDirectory = fixture.root.appendingPathComponent("Library/Application Support/CodexBar")
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        for url in [fixture.accountsURL, fixture.cacheURL] {
            try FileManager.default.copyItem(at: url, to: appDirectory.appendingPathComponent(url.lastPathComponent))
        }
        let configURL = fixture.root.appendingPathComponent("config.json")
        try CodexBarConfigStore(fileURL: configURL).save(fixture.config)
        let process = Process()
        process.executableURL = TestBuildProducts.executableURL(named: "CodexBarCLI")
        process.arguments = ["dashboard", "--identity", "redacted", "--timeout", "10"]
        process.environment = try CodexCredentialFileAccess.FixtureScope(roots: [fixture.root]).childEnvironment(base: [
            "HOME": fixture.root.path,
            "CFFIXED_USER_HOME": fixture.root.path,
            "CODEX_HOME": fixture.root.appendingPathComponent(".codex").path,
            "CODEXBAR_CONFIG": configURL.path,
            "PATH": "/usr/bin:/bin",
            "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
            "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
            "CODEXBAR_DISABLE_KEYCHAIN_ACCESS": "1",
        ])
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let bytes = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(bytes.last == 0x0A)
        let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        let provider = try #require((json["providers"] as? [[String: Any]])?.first)
        let accounts = try #require(provider["accounts"] as? [[String: Any]])
        #expect(accounts.count == 2)
        #expect(accounts[0]["id"] as? String == "codex-managed:\(fixture.accounts[0].id.uuidString.lowercased())")
        #expect(accounts[0]["active"] as? Bool == true)
        #expect((accounts[0]["identity"] as? [String: Any])?["accountEmail"] as? String == "redacted@example.com")
        #expect((accounts[0]["windows"] as? [[String: Any]])?.first?["usedPercent"] as? Double == 42)
        let encodedAccounts = try JSONSerialization.data(withJSONObject: accounts)
        let text = try #require(String(data: encodedAccounts, encoding: .utf8))
        #expect(!text.contains("first@"))
        #expect(!text.contains("second@"))
        #expect(!text.contains("/synthetic/private"))
    }

    @Test
    func `reads app written snapshots with stable IDs and independent errors`() throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        let before = try Data(contentsOf: fixture.accountsURL)
        let collection = try #require(fixture.collect())
        let accounts = try #require(collection.accounts)
        #expect(collection.adapterError == nil)
        #expect(accounts.map(\.id.opaqueID) == fixture.accounts.map { $0.id.uuidString.lowercased() })
        #expect(accounts.map(\.isActive) == [true, false])
        #expect(accounts[0].snapshot?.primary?.usedPercent == 42)
        #expect(accounts[0].snapshot?.updatedAt == fixture.updatedAt)
        #expect(accounts[0].error == nil)
        #expect(accounts[1].snapshot == nil)
        #expect(accounts[1].error == "Saved usage refresh failed. Refresh this account in CodexBar.")
        #expect(accounts[1].displayLabel == "second@example.net — Personal")
        #expect(try Data(contentsOf: fixture.accountsURL) == before)
    }

    @Test(arguments: ["email", "workspace", "uuid"])
    func `rejects saved usage belonging to another account`(field: String) throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.cacheURL))
            as? [String: Any])
        var records = try #require(payload["records"] as? [[String: Any]])
        var identity = try #require(records[0]["accountIdentity"] as? [String: Any])
        switch field {
        case "email": identity["normalizedEmail"] = "foreign@example.com"
        case "workspace": identity["workspaceAccountID"] = "other-workspace"
        default: identity["storedAccountID"] = UUID().uuidString
        }
        records[0]["accountIdentity"] = identity
        payload["records"] = records
        try JSONSerialization.data(withJSONObject: payload).write(to: fixture.cacheURL)
        let accounts = try #require(fixture.collect()?.accounts)
        #expect(accounts[0].snapshot == nil)
        #expect(accounts[0].error != nil)
        #expect(accounts[1].error != nil)
    }

    @Test
    func `missing saved usage keeps identities and stable IDs without ambient fallback`() throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.cacheURL)
        let accounts = try #require(fixture.collect()?.accounts)
        #expect(accounts.count == 2)
        #expect(accounts.allSatisfy { $0.snapshot == nil && $0.error != nil })
        #expect(accounts[0].accountEmail == "first@example.com")
    }

    @Test(arguments: ["metadata", "cache", "version"])
    func `whole adapter failures expose fixed diagnostics`(failure: String) throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        let path = failure == "metadata" ? fixture.accountsURL : fixture.cacheURL
        let bytes = failure == "version" ? "{\"version\":999,\"records\":[]}" : "invalid private-path@example.com"
        try Data(bytes.utf8).write(to: path)
        let collection = try #require(fixture.collect())
        #expect(collection.accounts == nil)
        #expect(collection.adapterError != nil)
        #expect(collection.adapterError?.contains("private-path") == false)
    }

    @Test
    func `absent managed accounts and disabled Codex omit enrichment`() throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        #expect(DashboardManagedCodexAccounts.collect(
            config: CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: false)]),
            accountStoreURL: fixture.accountsURL) == nil)
        try FileManager.default.removeItem(at: fixture.accountsURL)
        #expect(fixture.collect() == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.accountsURL.path))
    }

    @Test
    func `system and profile selections do not mark managed rows active`() throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        for source in [CodexActiveSource.liveSystem, .profileHome(path: "/synthetic/profile")] {
            var config = fixture.config
            config.providers[0].codexActiveSource = source
            let collection = DashboardManagedCodexAccounts.collect(config: config, accountStoreURL: fixture.accountsURL)
            #expect(collection?.accounts?.allSatisfy { !$0.isActive } == true)
        }
    }

    @Test
    func `legacy metadata projection never hydrates credentials or rewrites files`() throws {
        let fixture = try ManagedDashboardFixture()
        defer { fixture.remove() }
        let legacy = ManagedCodexAccountSet(version: 1, accounts: fixture.accounts)
        try JSONEncoder().encode(legacy).write(to: fixture.accountsURL)
        let home = URL(fileURLWithPath: fixture.accounts[0].managedHomePath)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let auth = home.appendingPathComponent("auth.json")
        try Data("synthetic credential sentinel".utf8).write(to: auth)
        let before = try Data(contentsOf: fixture.accountsURL)
        try CodexCredentialFileAccess.withFixtureScope(.init(roots: [fixture.root])) {
            let metadata = try FileManagedCodexAccountStore(fileURL: fixture.accountsURL).loadAccountMetadata()
            #expect(metadata.version == 1)
            #expect(metadata.accounts.allSatisfy { $0.authFingerprint == nil })
            #expect(fixture.collect()?.accounts?.count == 2)
        }
        #expect(try Data(contentsOf: fixture.accountsURL) == before)
        #expect(try String(contentsOf: auth, encoding: .utf8) == "synthetic credential sentinel")
    }
}

private struct ManagedDashboardFixture {
    let root: URL
    let accountsURL: URL
    let cacheURL: URL
    let accounts: [ManagedCodexAccount]
    let config: CodexBarConfig
    let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.root = root
        self.accountsURL = self.root.appendingPathComponent("managed-codex-accounts.json")
        self.cacheURL = self.root.appendingPathComponent("codex-account-snapshots.json")
        self.accounts = ["first@example.com", "second@example.net"].enumerated().map { index, email in
            ManagedCodexAccount(
                id: UUID(),
                email: email,
                workspaceLabel: index == 0 ? "Work" : "Personal",
                workspaceAccountID: "workspace-\(index)",
                managedHomePath: root.appendingPathComponent("home-\(index)").path,
                createdAt: 100,
                updatedAt: 200,
                lastAuthenticatedAt: nil)
        }
        var provider = ProviderConfig(id: .codex, enabled: true, source: .oauth)
        provider.codexActiveSource = .managedAccount(id: self.accounts[0].id)
        self.config = CodexBarConfig(providers: [provider])
        try FileManagedCodexAccountStore(fileURL: self.accountsURL).storeAccounts(
            ManagedCodexAccountSet(version: 3, accounts: self.accounts))
        let usage = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 42,
                windowMinutes: 300,
                resetsAt: self.updatedAt.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: self.updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "first@example.com",
                accountOrganization: nil,
                loginMethod: "plus"))
        let snapshots = self.accounts.enumerated().map { index, account in
            CodexAccountUsageSnapshot(
                account: CodexVisibleAccount(
                    id: account.email,
                    email: account.email,
                    workspaceAccountID: account.workspaceAccountID,
                    storedAccountID: account.id,
                    selectionSource: .managedAccount(id: account.id),
                    isActive: index == 0,
                    isLive: false,
                    canReauthenticate: false,
                    canRemove: false),
                snapshot: index == 0 ? usage : nil,
                error: index == 0 ? nil : "Refresh failed for private@example.com at /synthetic/private/auth.json",
                sourceLabel: "oauth")
        }
        FileCodexAccountUsageSnapshotStore(fileURL: self.cacheURL).store(snapshots)
    }

    func collect() -> DashboardAccountsInput? {
        DashboardManagedCodexAccounts.collect(config: self.config, accountStoreURL: self.accountsURL)
    }

    func remove() { try? FileManager.default.removeItem(at: self.root) }
}
