import CodexBarCore
import Foundation

extension UsageStore {
    /// Ollama's API-key strategy deliberately returns an empty usage snapshot:
    /// `/api/tags` proves the key works but does not contain Cloud quota
    /// windows. In automatic mode this is the fallback after the browser
    /// session failed. Treating that response as authoritative would erase the
    /// previous web snapshot locally, and the sync coordinator would then
    /// delete the previous iPhone record as a ghost.
    func applyPreservedOllamaSnapshotIfNeeded(
        provider: UsageProvider,
        result: ProviderFetchResult,
        usage: UsageSnapshot,
        attempts: [ProviderFetchAttempt],
        generation: UInt64) -> Bool
    {
        guard provider == .ollama,
              result.strategyKind == .apiToken,
              usage.primary == nil,
              usage.secondary == nil,
              usage.tertiary == nil,
              usage.extraRateWindows?.isEmpty ?? true,
              usage.providerCost == nil,
              self.isCurrentProviderRefreshGeneration(provider, generation: generation),
              let previous = self.snapshots[provider],
              previous.hasRateLimitWindows
        else {
            return false
        }

        self.lastFetchAttempts[provider] = attempts
        self.lastSourceLabels[provider] = result.sourceLabel
        self.errors[provider] = nil
        self.diagnostics[provider] = result.diagnostic ?? OllamaAPIUsageSnapshot.cloudQuotaDiagnostic
        self.failureGates[provider]?.recordSuccess()
        // The API is a credential/model probe, not a quota authority. A
        // successful empty response must not erase the last browser quota
        // sample or publish a ghost to the iPhone sync bridge.
        self.finalizeProviderRefreshSuccessPublication(
            provider: provider,
            snapshot: previous,
            generation: generation)
        return true
    }
}
