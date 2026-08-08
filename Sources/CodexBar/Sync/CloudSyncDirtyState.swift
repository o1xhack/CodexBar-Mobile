import CodexBarCore
import CodexBarSync
import Foundation

enum CloudSyncDirtyState {
    private static let providerIntentPrefix = "intent-"

    static func configurationRecordNamesToQueue(
        envelope: CloudSyncPersistence.Envelope,
        configuredProviders: [UsageProvider]) -> Set<String>
    {
        var recordNames = Set(configuredProviders.compactMap { provider in
            envelope.dirtyProviders.contains(provider.rawValue)
                ? ProviderIntentPayload.recordName(for: provider)
                : nil
        })
        if envelope.preferencesDirty {
            recordNames.insert(PreferencesSyncPayload.recordName)
        }
        return recordNames
    }

    static func markBootstrapDirtyIfNeeded(
        configuredProviders: [UsageProvider],
        envelope: inout CloudSyncPersistence.Envelope)
    {
        guard !envelope.recordMetadata.keys.contains(where: { $0.hasPrefix(self.providerIntentPrefix) }) else {
            return
        }
        envelope.dirtyProviders.formUnion(configuredProviders.map(\.rawValue))
        envelope.preferencesDirty = true
    }

    static func clearSavedRecords(
        _ recordNames: some Sequence<String>,
        envelope: inout CloudSyncPersistence.Envelope)
    {
        for recordName in recordNames {
            if recordName == PreferencesSyncPayload.recordName {
                envelope.preferencesDirty = false
            } else if recordName.hasPrefix(self.providerIntentPrefix) {
                envelope.dirtyProviders.remove(String(recordName.dropFirst(self.providerIntentPrefix.count)))
            }
        }
    }

    static func providerSyncContentChanged(
        from previous: ProviderConfig,
        previousSuppressedEnableIntents: Set<String>,
        to current: ProviderConfig,
        currentSuppressedEnableIntents: Set<String>) throws -> Bool
    {
        let previousPayload = CloudSyncEngine.providerIntentPayload(
            config: previous,
            suppressedEnableIntents: previousSuppressedEnableIntents)
        let currentPayload = CloudSyncEngine.providerIntentPayload(
            config: current,
            suppressedEnableIntents: currentSuppressedEnableIntents)
        guard try CanonicalSyncJSON.encode(previousPayload) == CanonicalSyncJSON.encode(currentPayload) else {
            return true
        }
        let previousSecrets = try ProviderIntentPayload.secretFields(for: previous, includeSecrets: true)
        let currentSecrets = try ProviderIntentPayload.secretFields(for: current, includeSecrets: true)
        return previousSecrets != currentSecrets
    }
}
