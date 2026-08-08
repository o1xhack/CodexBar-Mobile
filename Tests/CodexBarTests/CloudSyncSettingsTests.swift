import CloudKit
import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct CloudSyncSettingsTests {
    @Test
    func `fleet sync uses the fork CloudKit container and state namespace`() {
        #expect(CloudSyncEngine.containerIdentifier == CloudSyncConstants.containerIdentifier)
        #expect(CloudSyncEngine.containerIdentifier == "iCloud.com.o1xhack.codexbar")
        #expect(CloudSyncPersistence.defaultFileURL().path.contains("/com.o1xhack.codexbar/sync/"))
    }

    @Test
    func `sync settings use strict opt in defaults and stay local`() throws {
        let fixture = try self.makeFixture("local-defaults")
        let store = fixture.store

        #expect(!store.macFleetSyncEnabled)
        #expect(store.macFleetSyncIncludeSecrets)
        #expect(store.macFleetSyncSnapshotsEnabled)
        #expect(store.macFleetSyncShowFleetAccounts)
        #expect(UUID(uuidString: store.macFleetSyncDeviceID) != nil)
        #expect(fixture.defaults.string(forKey: "com.codexbar.sync.deviceID") == store.macFleetSyncDeviceID)
        #expect(fixture.defaults.object(forKey: "iCloudSyncDeviceID") == nil)

        store.macFleetSyncEnabled = true
        store.macFleetSyncIncludeSecrets = false
        #expect(fixture.defaults.bool(forKey: "macFleetSyncEnabled"))
        #expect(!fixture.defaults.bool(forKey: "macFleetSyncIncludeSecrets"))
    }

    @Test
    func `preferences subset applies through settings without touching excluded keys`() throws {
        let fixture = try self.makeFixture("preferences")
        let store = fixture.store
        store.debugMenuEnabled = true
        store.macFleetSyncEnabled = true
        var remote = store.syncedPreferences
        remote.statusChecksEnabled = false
        remote.usageBarsShowUsed = true
        remote.costUsageEnabled = true
        remote.preferredCurrencyCode = "EUR"
        remote.refreshFrequency = RefreshFrequency.thirtyMinutes.rawValue

        store.applySyncedPreferences(remote)

        #expect(!store.statusChecksEnabled)
        #expect(store.usageBarsShowUsed)
        #expect(store.costUsageEnabled)
        #expect(store.preferredCurrencyCode == "EUR")
        #expect(store.refreshFrequency == .thirtyMinutes)
        #expect(store.debugMenuEnabled)
        #expect(store.macFleetSyncEnabled)
    }

    @Test
    func `config watcher suppresses self writes and observes external atomic replacement`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigFileWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let original = Data("{\"value\":1}".utf8)
        try original.write(to: url, options: .atomic)
        let changes = LockedCounter()
        let watcher = ConfigFileWatcher(fileURL: url) { changes.increment() }
        watcher.start()
        try await Task.sleep(for: .milliseconds(150))

        let ownWrite = Data("{\"value\":2}".utf8)
        watcher.noteAppWrite(data: ownWrite)
        try ownWrite.write(to: url, options: .atomic)
        try await Task.sleep(for: .milliseconds(350))
        #expect(changes.value == 0)

        try Data("{\"value\":3}".utf8).write(to: url, options: .atomic)
        try await Task.sleep(for: .milliseconds(500))
        watcher.stop()
        #expect(changes.value >= 1)
    }

    @Test
    func `sync persistence never writes encrypted provider secrets and uses private permissions`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("engine-state.json")
        let persistence = CloudSyncPersistence(fileURL: fileURL)
        let config = ProviderConfig(id: .openai, apiKey: "SENTINEL-SECRET")
        let recordID = CKRecord.ID(
            recordName: ProviderIntentPayload.recordName(for: config.id),
            zoneID: CloudSyncEngine.zoneID)
        let record = CKRecord(recordType: SyncRecordType.providerIntent.rawValue, recordID: recordID)
        record["payload"] = try CanonicalSyncJSON.string(ProviderIntentPayload(config: config)) as CKRecordValue
        record.encryptedValues[ProviderIntentSecretField.apiKey.rawValue] = config.apiKey as CKRecordValue?

        var envelope = CloudSyncPersistence.Envelope(stateSerialization: nil, encodedSystemFields: [:])
        CloudSyncPersistence.cacheSystemFields(of: record, in: &envelope)
        try persistence.save(envelope)
        let loaded = persistence.load()
        let bytes = try Data(contentsOf: fileURL)
        let contents = try #require(String(bytes: bytes, encoding: .utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        #expect(!contents.contains("SENTINEL-SECRET"))
        #expect(loaded.encodedSystemFields[recordID.recordName] != nil)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test
    func `legacy sync persistence defaults dirty state to clean`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncPersistenceLegacyTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("engine-state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("""
        {
          "encodedSystemFields": {},
          "recordMetadata": {},
          "suppressedEnableIntents": [],
          "fleetDevices": {},
          "fleetSnapshots": {}
        }
        """.utf8).write(to: fileURL)

        let envelope = CloudSyncPersistence(fileURL: fileURL).load()

        #expect(envelope.dirtyProviders.isEmpty)
        #expect(!envelope.preferencesDirty)
        #expect(envelope.snapshotDeletionRecordNames.isEmpty)
        #expect(envelope.snapshotOwnershipKnownRecordNames.isEmpty)
        #expect(envelope.snapshotTokenAccountIDs.isEmpty)
    }

    @Test
    func `relaunch with cached fleet records and clean dirty set queues no configuration records`() {
        let metadata = CloudSyncPersistence.RecordMetadata(
            recordType: SyncRecordType.providerIntent.rawValue,
            schemaVersion: CodexBarSyncSchema.currentVersion,
            editCount: 4,
            modifiedAt: Date())
        let envelope = CloudSyncPersistence.Envelope(
            stateSerialization: nil,
            encodedSystemFields: [:],
            recordMetadata: [ProviderIntentPayload.recordName(for: .claude): metadata])

        let recordNames = CloudSyncDirtyState.configurationRecordNamesToQueue(
            envelope: envelope,
            configuredProviders: [.claude, .codex])

        #expect(recordNames.isEmpty)
    }

    @Test
    func `local provider edit queues exactly that provider`() async throws {
        let fixture = try self.makeFixture("dirty-provider")
        let persistence = self.makePersistence("dirty-provider")
        let initial = fixture.store.configSnapshot
        let engine = CloudSyncEngine(
            settings: fixture.store,
            state: CloudSyncState(),
            persistence: persistence,
            initialConfiguration: initial,
            initialPreferences: fixture.store.syncedPreferences,
            initialIncludeSecrets: fixture.store.macFleetSyncIncludeSecrets)
        var updated = initial
        var claude = try #require(updated.providerConfig(for: .claude))
        claude.extrasEnabled = !(claude.extrasEnabled ?? false)
        updated.setProviderConfig(claude)

        await engine.localUserConfigurationDidChange(updated)

        let envelope = persistence.load()
        let recordNames = CloudSyncDirtyState.configurationRecordNamesToQueue(
            envelope: envelope,
            configuredProviders: updated.providers.map(\.id))
        #expect(recordNames == [ProviderIntentPayload.recordName(for: .claude)])
    }

    @Test
    func `machine local provider edit does not become dirty`() async throws {
        let fixture = try self.makeFixture("machine-local-provider")
        let persistence = self.makePersistence("machine-local-provider")
        let initial = fixture.store.configSnapshot
        let engine = CloudSyncEngine(
            settings: fixture.store,
            state: CloudSyncState(),
            persistence: persistence,
            initialConfiguration: initial,
            initialPreferences: fixture.store.syncedPreferences,
            initialIncludeSecrets: fixture.store.macFleetSyncIncludeSecrets)
        var updated = initial
        var claude = try #require(updated.providerConfig(for: .claude))
        claude.claudeSwapExecutablePath = "/machine-only/claude-swap"
        updated.setProviderConfig(claude)

        await engine.localUserConfigurationDidChange(updated)

        #expect(persistence.load().dirtyProviders.isEmpty)
    }

    @Test
    func `empty fleet bootstrap dirties every configured provider and preferences`() {
        var envelope = CloudSyncPersistence.Envelope(stateSerialization: nil, encodedSystemFields: [:])

        CloudSyncDirtyState.markBootstrapDirtyIfNeeded(
            configuredProviders: [.claude, .codex],
            envelope: &envelope)

        #expect(envelope.dirtyProviders == [UsageProvider.claude.rawValue, UsageProvider.codex.rawValue])
        #expect(envelope.preferencesDirty)
    }

    @Test
    func `successful saves clear dirty while failed saves keep it`() {
        var envelope = CloudSyncPersistence.Envelope(
            stateSerialization: nil,
            encodedSystemFields: [:],
            dirtyProviders: [UsageProvider.claude.rawValue, UsageProvider.codex.rawValue],
            preferencesDirty: true)

        CloudSyncDirtyState.clearSavedRecords(
            [ProviderIntentPayload.recordName(for: .claude), PreferencesSyncPayload.recordName],
            envelope: &envelope)

        #expect(envelope.dirtyProviders == [UsageProvider.codex.rawValue])
        #expect(!envelope.preferencesDirty)
        #expect(envelope.dirtyProviders.contains(UsageProvider.codex.rawValue))
    }

    @Test
    func `remote provider apply does not become dirty`() async throws {
        let fixture = try self.makeFixture("remote-provider")
        let persistence = self.makePersistence("remote-provider")
        let initial = fixture.store.configSnapshot
        let engine = CloudSyncEngine(
            settings: fixture.store,
            state: CloudSyncState(),
            persistence: persistence,
            initialConfiguration: initial,
            initialPreferences: fixture.store.syncedPreferences,
            initialIncludeSecrets: fixture.store.macFleetSyncIncludeSecrets)
        var remoteConfig = try #require(initial.providerConfig(for: .claude))
        remoteConfig.extrasEnabled = !(remoteConfig.extrasEnabled ?? false)
        let recordID = CKRecord.ID(
            recordName: ProviderIntentPayload.recordName(for: .claude),
            zoneID: CloudSyncEngine.zoneID)
        let record = CKRecord(recordType: SyncRecordType.providerIntent.rawValue, recordID: recordID)
        record["payload"] = try CanonicalSyncJSON.string(ProviderIntentPayload(config: remoteConfig)) as CKRecordValue

        await engine.applyFetchedRecords([record])

        #expect(persistence.load().dirtyProviders.isEmpty)
    }

    @Test
    func `missing desired record drains its pending save`() {
        let recordID = CKRecord.ID(recordName: "stale", zoneID: CloudSyncEngine.zoneID)
        let change = CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID)
        var pending: Set<CKSyncEngine.PendingRecordZoneChange> = [change]

        let record = CloudSyncBatchRecordProvider.record(for: recordID, desiredRecords: [:]) {
            pending.remove($0)
        }

        #expect(record == nil)
        #expect(pending.isEmpty)
    }

    @Test
    func `authoritative snapshot reconciliation deletes only stale records from the current device`() {
        let current = Self.snapshot(accountKey: "current", deviceID: "this-mac")
        let stale = Self.snapshot(accountKey: "removed", deviceID: "this-mac")
        let remote = Self.snapshot(accountKey: "remote", deviceID: "other-mac")
        let persisted = [
            current.recordName: current,
            stale.recordName: stale,
            remote.recordName: remote,
        ]

        let plan = CloudSyncSnapshotReconciliation.plan(
            currentSnapshots: [current],
            persistedSnapshots: persisted,
            deviceID: "this-mac",
            enabledProviders: [.codex],
            authoritativeProviders: [.codex])

        #expect(plan.recordNamesToDelete == [stale.recordName])
        #expect(plan.recordNamesToCancelPendingDeletes == [current.recordName])
    }

    @Test
    func `non authoritative empty snapshot publication preserves last good records`() {
        let first = Self.snapshot(accountKey: "first", deviceID: "this-mac")
        let second = Self.snapshot(accountKey: "second", deviceID: "this-mac")
        let remote = Self.snapshot(accountKey: "remote", deviceID: "other-mac")
        let persisted = [
            first.recordName: first,
            second.recordName: second,
            remote.recordName: remote,
        ]

        let plan = CloudSyncSnapshotReconciliation.plan(
            currentSnapshots: [],
            persistedSnapshots: persisted,
            deviceID: "this-mac",
            enabledProviders: [.codex],
            authoritativeProviders: [])

        #expect(plan.recordNamesToDelete.isEmpty)
    }

    @Test
    func `provider refresh failure makes snapshot publication non authoritative`() throws {
        let fixture = try self.makeFixture("snapshot-authority")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: fixture.store)
        let snapshot = Self.snapshot(provider: .openai, accountKey: "current", deviceID: "this-mac")

        #expect(store.cloudSyncAuthoritativeSnapshotProviders([snapshot], reason: "refresh") == [.openai])

        store.errors[.openai] = "transient network failure"
        #expect(store.cloudSyncAuthoritativeSnapshotProviders([snapshot], reason: "refresh").isEmpty)

        store.errors[.openai] = nil
        #expect(store.cloudSyncAuthoritativeSnapshotProviders([snapshot], reason: "settings-display").isEmpty)
    }

    @Test
    func `snapshot publication carries local token account ownership without changing the wire payload`() throws {
        let fixture = try self.makeFixture("snapshot-token-owner")
        fixture.store.addTokenAccount(provider: .openai, label: "person@example.com", token: "test-token")
        let account = try #require(fixture.store.tokenAccounts(for: .openai).first)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: fixture.store)
        let usage = UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1000),
            identity: ProviderIdentitySnapshot(
                providerID: .openai,
                accountEmail: account.label,
                accountOrganization: nil,
                loginMethod: nil))
        store.accountSnapshots[.openai] = [TokenAccountUsageSnapshot(
            account: account,
            snapshot: usage,
            error: nil,
            sourceLabel: nil,
            cacheKey: "test")]

        let publication = store.cloudSyncAccountSnapshotPublication()
        let payload = try #require(publication.snapshots.first)

        #expect(publication.tokenAccountIDsByRecordName[payload.recordName] == account.id)
        #expect(payload.displayLabel == account.displayName)
    }

    @Test
    func `removing and restoring a token account scopes the durable deletion intent to its record`() {
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "removed@example.com",
            token: "test-token",
            addedAt: 1000,
            lastUsed: nil)
        let populatedConfig = ProviderConfig(
            id: .openai,
            enabled: true,
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))
        let emptyConfig = ProviderConfig(id: .openai, enabled: true)
        let removedSnapshot = Self.snapshot(
            provider: .openai,
            accountKey: "removed",
            deviceID: "this-mac",
            displayLabel: account.label)
        let fallbackSnapshot = Self.snapshot(
            provider: .openai,
            accountKey: "fallback",
            deviceID: "this-mac",
            displayLabel: account.label)
        let persisted = [
            removedSnapshot.recordName: removedSnapshot,
            fallbackSnapshot.recordName: fallbackSnapshot,
        ]

        let removed = CloudSyncSnapshotConfigurationReconciliation.plan(
            previousConfigs: [.openai: populatedConfig],
            currentConfig: CodexBarConfig(providers: [emptyConfig]),
            state: .init(
                candidateSnapshots: persisted,
                ownershipKnownRecordNames: Set(persisted.keys),
                tokenAccountIDsByRecordName: [removedSnapshot.recordName: account.id],
                deviceID: "this-mac",
                pendingRecordNames: []))
        #expect(removed.pendingRecordNames == [removedSnapshot.recordName])
        #expect(removed.recordNamesToDelete == [removedSnapshot.recordName])
        #expect(removed.recordNamesToCancel.isEmpty)
        #expect(!removed.recordNamesToDelete.contains(fallbackSnapshot.recordName))

        let restored = CloudSyncSnapshotConfigurationReconciliation.plan(
            previousConfigs: [.openai: emptyConfig],
            currentConfig: CodexBarConfig(providers: [populatedConfig]),
            state: .init(
                candidateSnapshots: persisted,
                ownershipKnownRecordNames: Set(persisted.keys),
                tokenAccountIDsByRecordName: [removedSnapshot.recordName: account.id],
                deviceID: "this-mac",
                pendingRecordNames: removed.pendingRecordNames))
        #expect(restored.pendingRecordNames.isEmpty)
        #expect(restored.recordNamesToDelete.isEmpty)
        #expect(restored.recordNamesToCancel == [removedSnapshot.recordName])
    }

    @Test
    func `legacy ownership backfill uses a unique display label and preserves fallback records`() {
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Primary account",
            token: "test-token",
            addedAt: 1000,
            lastUsed: nil)
        let populatedConfig = ProviderConfig(
            id: .claude,
            enabled: true,
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))
        let removedSnapshot = Self.snapshot(
            provider: .claude,
            accountKey: AccountSnapshotSyncPayload.accountKey(for: "actual-account-id-from-provider"),
            deviceID: "this-mac",
            displayLabel: account.label)
        let fallbackSnapshot = Self.snapshot(
            provider: .claude,
            accountKey: "oauth-fallback",
            deviceID: "this-mac",
            displayLabel: "oauth@example.com")

        let plan = CloudSyncSnapshotConfigurationReconciliation.plan(
            previousConfigs: [.claude: populatedConfig],
            currentConfig: CodexBarConfig(providers: [ProviderConfig(id: .claude, enabled: true)]),
            state: .init(
                candidateSnapshots: [
                    removedSnapshot.recordName: removedSnapshot,
                    fallbackSnapshot.recordName: fallbackSnapshot,
                ],
                ownershipKnownRecordNames: [],
                tokenAccountIDsByRecordName: [:],
                deviceID: "this-mac",
                pendingRecordNames: []))

        #expect(plan.recordNamesToDelete == [removedSnapshot.recordName])
        #expect(!plan.recordNamesToDelete.contains(fallbackSnapshot.recordName))
        #expect(plan.ownershipKnownRecordNames.contains(removedSnapshot.recordName))
        #expect(plan.tokenAccountIDsByRecordName[removedSnapshot.recordName] == account.id)
    }

    @Test
    func `queued snapshot is tombstoned when its account is removed before the throttle publishes`() {
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Queued account",
            token: "test-token",
            addedAt: 1000,
            lastUsed: nil)
        let queuedSnapshot = Self.snapshot(
            provider: .openai,
            accountKey: "queued",
            deviceID: "this-mac",
            displayLabel: account.label)
        let previous = ProviderConfig(
            id: .openai,
            enabled: true,
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))

        let plan = CloudSyncSnapshotConfigurationReconciliation.plan(
            previousConfigs: [.openai: previous],
            currentConfig: CodexBarConfig(providers: [ProviderConfig(id: .openai, enabled: true)]),
            state: .init(
                candidateSnapshots: [queuedSnapshot.recordName: queuedSnapshot],
                ownershipKnownRecordNames: [queuedSnapshot.recordName],
                tokenAccountIDsByRecordName: [queuedSnapshot.recordName: account.id],
                deviceID: "this-mac",
                pendingRecordNames: []))

        #expect(plan.pendingRecordNames == [queuedSnapshot.recordName])
        #expect(plan.recordNamesToDelete == [queuedSnapshot.recordName])
    }

    @Test
    func `stale removed account publication stays blocked while fallback snapshot remains publishable`() {
        let removedAccountID = UUID()
        let removedSnapshot = Self.snapshot(
            provider: .claude,
            accountKey: "removed",
            deviceID: "this-mac")
        let fallbackSnapshot = Self.snapshot(
            provider: .claude,
            accountKey: "fallback",
            deviceID: "this-mac")

        let plan = CloudSyncSnapshotDeletionIntentReconciliation.plan(
            snapshots: [removedSnapshot, fallbackSnapshot],
            tokenAccountIDsByRecordName: [removedSnapshot.recordName: removedAccountID],
            authoritativeProviders: [.claude],
            activeTokenAccountIDs: [],
            pendingRecordNames: [removedSnapshot.recordName])

        #expect(plan.pendingRecordNames == [removedSnapshot.recordName])
        #expect(plan.recordNamesToCancel.isEmpty)
        #expect(plan.blockedRecordNames == [removedSnapshot.recordName])
    }

    @Test
    func `disabled provider deletion removes current device records but preserves the fleet`() {
        let first = Self.snapshot(accountKey: "first", deviceID: "this-mac")
        let second = Self.snapshot(accountKey: "second", deviceID: "this-mac")
        let remote = Self.snapshot(accountKey: "remote", deviceID: "other-mac")
        let persisted = [
            first.recordName: first,
            second.recordName: second,
            remote.recordName: remote,
        ]

        let plan = CloudSyncSnapshotReconciliation.plan(
            currentSnapshots: [first],
            persistedSnapshots: persisted,
            deviceID: "this-mac",
            enabledProviders: [],
            authoritativeProviders: [])

        #expect(plan.recordNamesToDelete == [first.recordName, second.recordName])
        #expect(plan.recordNamesToCancelPendingDeletes.isEmpty)
        #expect(!plan.recordNamesToDelete.contains(remote.recordName))
    }

    @Test
    func `quota backoff doubles to one hour and resets after success`() {
        var backoff = CloudSyncQuotaRetryState()

        #expect(backoff.nextDelay(serverRetryAfter: 120) == 120)
        #expect(backoff.nextDelay(serverRetryAfter: 999) == 240)
        #expect(backoff.nextDelay(serverRetryAfter: nil) == 480)
        for _ in 0..<10 {
            _ = backoff.nextDelay(serverRetryAfter: nil)
        }
        #expect(backoff.nextDelay(serverRetryAfter: nil) == 3600)

        backoff.reset()
        #expect(backoff.nextDelay(serverRetryAfter: 30) == 30)
    }

    private func makeFixture(_ name: String) throws -> (store: SettingsStore, defaults: UserDefaults) {
        let suite = "CloudSyncSettingsTests-\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            performInitialProviderDetection: false)
        return (store, defaults)
    }

    private func makePersistence(_ name: String) -> CloudSyncPersistence {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncDirtyTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        return CloudSyncPersistence(fileURL: directory.appendingPathComponent("engine-state.json"))
    }

    private static func snapshot(
        provider: UsageProvider = .codex,
        accountKey: String,
        deviceID: String,
        displayLabel: String = "person@example.com") -> AccountSnapshotSyncPayload
    {
        AccountSnapshotSyncPayload(
            provider: provider,
            deviceID: deviceID,
            accountKey: accountKey,
            fetchedAt: Date(timeIntervalSince1970: 1000),
            displayLabel: displayLabel,
            usage: UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date(timeIntervalSince1970: 1000)))
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        self.lock.withLock { self.storage }
    }

    func increment() {
        self.lock.withLock { self.storage += 1 }
    }
}
