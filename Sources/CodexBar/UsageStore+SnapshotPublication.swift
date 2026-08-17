import CodexBarCore
import Foundation

extension UsageStore {
    func markProviderRefreshSuccessful(_ provider: UsageProvider, generation: UInt64) {
        let instanceID = provider.instanceID
        guard self.isCurrentProviderRefreshGeneration(provider, generation: generation),
              var context = self.providerRefreshPublicationContexts[instanceID],
              context.generation == generation
        else { return }
        context.completedSuccessfully = true
        self.providerRefreshPublicationContexts[instanceID] = context
        self.providerSnapshotPublicationSources[instanceID] = ProviderSnapshotPublicationSource(
            provider: instanceID,
            refreshGeneration: generation,
            configRevision: context.configRevision)
    }

    func completedProviderSnapshotPublication(
        for provider: UsageProvider,
        generation: UInt64) -> ProviderSnapshotPublicationSource?
    {
        guard self.providerRefreshPublicationContexts[provider.instanceID]?.completedSuccessfully == true,
              let source = self.providerSnapshotPublicationSources[provider.instanceID],
              source.refreshGeneration == generation
        else { return nil }
        return source
    }

    func isCurrentProviderRefreshGeneration(_ provider: UsageProvider, generation: UInt64?) -> Bool {
        guard let generation else { return true }
        guard self.providerRefreshCoordinator.isCurrent(generation, for: provider.instanceID),
              let context = self.providerRefreshPublicationContexts[provider.instanceID],
              context.generation == generation
        else {
            return false
        }
        return context.enablementRevision == self.settings.providerEnablementRevision(for: provider) &&
            context.configRevision == self.settings.providerConfigRevision(for: provider) &&
            (context.tokenCostScopeSignature == nil ||
                context.tokenCostScopeSignature == self.tokenSnapshotScopeSignature(for: provider))
    }

    func currentProviderRefreshAllowsDisabledPublication(_ provider: UsageProvider) -> Bool {
        guard let context = self.providerRefreshPublicationContexts[provider.instanceID],
              context.allowDisabled,
              let state = self.providerRefreshCoordinator.coalescingState(for: provider.instanceID),
              state.generation == context.generation
        else {
            return false
        }
        return true
    }

    func finalizeProviderRefreshSuccessPublication(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        generation: UInt64)
    {
        guard self.isCurrentProviderRefreshGeneration(provider, generation: generation) else { return }
        if let runtime = self.providerRuntimes[provider.instanceID] {
            let runtimeContext = ProviderRuntimeContext(
                provider: provider, settings: self.settings, store: self)
            runtime.providerDidRefresh(context: runtimeContext, provider: provider)
        }
        if provider == .codex {
            self.recordCodexHistoricalSampleIfNeeded(snapshot: snapshot)
        }
        self.markProviderRefreshSuccessful(provider, generation: generation)
    }
}
