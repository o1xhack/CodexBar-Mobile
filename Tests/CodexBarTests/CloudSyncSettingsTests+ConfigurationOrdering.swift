import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension CloudSyncSettingsTests {
    @Test
    func `newer external revision preserves an overtaken local provider edit`() async throws {
        let fixture = try self.makeFixture("external-overtakes-local")
        let persistence = self.makePersistence("external-overtakes-local")
        let initial = fixture.store.configSnapshot
        let engine = CloudSyncEngine(
            settings: fixture.store,
            state: CloudSyncState(),
            persistence: persistence,
            initialConfiguration: initial,
            initialConfigurationRevision: 0,
            initialPreferences: fixture.store.syncedPreferences,
            initialIncludeSecrets: fixture.store.macFleetSyncIncludeSecrets)
        var localConfig = initial
        var claude = try #require(localConfig.providerConfig(for: .claude))
        claude.extrasEnabled = !(claude.extrasEnabled ?? false)
        localConfig.setProviderConfig(claude)
        var combinedConfig = localConfig
        var openAI = try #require(combinedConfig.providerConfig(for: .openai))
        openAI.workspaceID = "remote-workspace"
        combinedConfig.setProviderConfig(openAI)

        await engine.externalConfigurationDidChange(
            previousConfig: localConfig,
            currentConfig: combinedConfig,
            revision: 2,
            deviceID: fixture.store.macFleetSyncDeviceID)
        await engine.localUserConfigurationDidChange(
            localConfig,
            revision: 1,
            deviceID: fixture.store.macFleetSyncDeviceID)

        #expect(persistence.load().dirtyProviders == [UsageProvider.claude.rawValue])
    }

    @Test
    func `invalid startup config cannot authorize snapshot deletion repair`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncInvalidStartupConfig-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.json")
        try Data("{not-valid-json".utf8).write(to: configURL)
        let config = CloudSyncStartupSnapshotDeletionAuthority.loadConfiguration(
            from: CodexBarConfigStore(fileURL: configURL))
        let snapshot = Self.snapshot(
            provider: .openai,
            accountKey: "preserved",
            deviceID: "this-mac")

        let plan = CloudSyncSnapshotConfigurationReconciliation.plan(
            previousConfigs: [:],
            currentConfig: CodexBarConfig.makeDefault(),
            authoritativeProviders: Set(config?.providers.map(\.id) ?? []),
            state: .init(
                candidateSnapshots: [snapshot.recordName: snapshot],
                ownershipKnownRecordNames: [snapshot.recordName],
                tokenAccountIDsByRecordName: [snapshot.recordName: UUID()],
                deviceID: "this-mac",
                pendingRecordNames: []))

        #expect(config == nil)
        #expect(plan.pendingRecordNames.isEmpty)
        #expect(plan.recordNamesToDelete.isEmpty)
    }
}
