import CloudKit
import CodexBarCore
import Foundation
import Observation

@MainActor
final class CloudSyncCoordinator {
    let state: CloudSyncState

    private let settings: SettingsStore
    private let engine: CloudSyncEngine
    private var configObserver: NSObjectProtocol?
    private var externalConfigObserver: NSObjectProtocol?
    private var localFileConfigObserver: NSObjectProtocol?
    private var snapshotObserver: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private var resumeTask: Task<Void, Never>?
    private var observedEnabled: Bool

    init(
        settings: SettingsStore,
        state: CloudSyncState = CloudSyncState(),
        persistence: CloudSyncPersistence = CloudSyncPersistence())
    {
        self.settings = settings
        self.state = state
        self.observedEnabled = settings.macFleetSyncEnabled
        self.engine = CloudSyncEngine(
            settings: settings,
            state: self.state,
            persistence: persistence,
            initialConfiguration: settings.configSnapshot,
            initialConfigurationRevision: settings.configRevision,
            initialPreferences: settings.syncedPreferences,
            initialIncludeSecrets: settings.macFleetSyncIncludeSecrets)
    }

    func start(startEngine: Bool = true) {
        self.observeSettings()
        self.configObserver = NotificationCenter.default.addObserver(
            forName: .codexbarProviderConfigDidChange,
            object: self.settings,
            queue: .main)
        { [weak self] notification in
            let notificationRevision = notification.userInfo?["revision"] as? Int
            MainActor.assumeIsolated {
                self?.configurationDidChangeLocally(revision: notificationRevision)
            }
        }
        self.localFileConfigObserver = NotificationCenter.default.addObserver(
            forName: .codexbarLocalConfigFileDidChange,
            object: self.settings,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.configurationDidChangeLocally()
            }
        }
        self.externalConfigObserver = NotificationCenter.default.addObserver(
            forName: .codexbarExternalProviderConfigDidChange,
            object: self.settings,
            queue: .main)
        { [weak self] notification in
            let event = notification.userInfo?["event"] as? ExternalProviderConfigDidChangeEvent
            MainActor.assumeIsolated {
                guard let self, let event else { return }
                let deviceID = self.settings.macFleetSyncDeviceID
                Task {
                    await self.engine.externalConfigurationDidChange(
                        previousConfig: event.previousConfig,
                        currentConfig: event.currentConfig,
                        revision: event.revision,
                        deviceID: deviceID)
                }
            }
        }
        self.snapshotObserver = NotificationCenter.default.addObserver(
            forName: .codexbarUsageSnapshotsDidChange,
            object: nil,
            queue: .main)
        { [weak self] notification in
            guard let event = notification.object as? UsageSnapshotsDidChangeEvent else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.engine.queueSnapshots(
                    event.snapshots,
                    authoritativeProviders: event.authoritativeProviders,
                    sourceProviderConfigRevisions: event.providerConfigRevisions,
                    sourceProviderPublicationGenerations: event.providerPublicationGenerations,
                    tokenAccountIDsByRecordName: event.tokenAccountIDsByRecordName)
            }
        }
        self.accountObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.CKAccountChanged,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleResume(debounce: true)
            }
        }
        if startEngine {
            Task { await self.engine.start(enabled: self.settings.macFleetSyncEnabled) }
        }
    }

    func applicationDidBecomeActive() {
        self.scheduleResume(debounce: false)
    }

    private func configurationDidChangeLocally(revision: Int? = nil) {
        let config = self.settings.configSnapshot
        let resolvedRevision = revision ?? self.settings.configRevision
        let deviceID = self.settings.macFleetSyncDeviceID
        Task {
            await self.engine.localUserConfigurationDidChange(
                config,
                revision: resolvedRevision,
                deviceID: deviceID)
            await self.engine.scheduleConfigurationPush()
        }
    }

    func stop() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        if let externalConfigObserver {
            NotificationCenter.default.removeObserver(externalConfigObserver)
        }
        if let localFileConfigObserver {
            NotificationCenter.default.removeObserver(localFileConfigObserver)
        }
        if let snapshotObserver {
            NotificationCenter.default.removeObserver(snapshotObserver)
        }
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
        self.resumeTask?.cancel()
        self.configObserver = nil
        self.externalConfigObserver = nil
        self.localFileConfigObserver = nil
        self.snapshotObserver = nil
        self.accountObserver = nil
        self.resumeTask = nil
        Task { await self.engine.stop() }
    }

    private func scheduleResume(debounce: Bool) {
        self.resumeTask?.cancel()
        self.resumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await self.engine.resumeOrFetch(enabled: self.settings.macFleetSyncEnabled)
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = self.settings.macFleetSyncEnabled
            _ = self.settings.macFleetSyncIncludeSecrets
            _ = self.settings.macFleetSyncSnapshotsEnabled
            _ = self.settings.syncedPreferences
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSettings()
                let enabled = self.settings.macFleetSyncEnabled
                if enabled != self.observedEnabled {
                    self.observedEnabled = enabled
                    await self.engine.setEnabled(enabled)
                } else {
                    await self.engine.localUserPreferencesDidChange(self.settings.syncedPreferences)
                    await self.engine.localIncludeSecretsDidChange(
                        self.settings.macFleetSyncIncludeSecrets,
                        config: self.settings.configSnapshot)
                    await self.engine.scheduleConfigurationPush()
                }
            }
        }
    }
}
