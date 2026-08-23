import CodexBarCore

extension UsageStore {
    var menuObservationToken: Int {
        _ = self.snapshots
        _ = self.errors
        _ = self.diagnostics
        _ = self.knownLimitsAvailabilityByProvider
        _ = self.lastSourceLabels
        _ = self.lastFetchAttempts
        _ = (self.accountSnapshots, self.tokenAccountLiveStateProviders, self.codexAccountSnapshots)
        _ = self.kiloScopeSnapshots
        _ = self.claudeSwapAccountSnapshots
        _ = self.claudeSwapLastError
        _ = self.claudeSwapRevision
        _ = self.tokenSnapshots
        _ = self.tokenErrors
        _ = self.tokenRefreshInFlight
        _ = self.codexCostCatchUpActivity
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.openAIDashboardAttachmentRevision
        _ = self.versions
        _ = self.isRefreshing
        _ = self.hasForcedRefreshEnrichmentInFlight
        _ = self.refreshingProviders
        _ = self.pathDebugInfo
        _ = self.statuses
        _ = self.probeLogs
        _ = self.historicalPaceRevision
        _ = self.planUtilizationHistoryRevision
        _ = self.providerStorageFootprints
        return 0
    }

    var iconObservationToken: Int {
        _ = self.snapshots
        _ = self.claudeSwapAccountSnapshots
        _ = self.claudeSwapRevision
        _ = self.errors
        _ = self.diagnostics
        _ = self.knownLimitsAvailabilityByProvider
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.refreshingProviders
        _ = self.statuses
        _ = self.tokenSnapshotPublications
        _ = self.spendDashboardTokenPublications
        _ = self.spendDashboardPublication.revision
        _ = self.historicalPaceRevision
        return 0
    }

    var backgroundWorkSettingsObservationToken: Int {
        _ = self.settings.backgroundWorkSettingsRevision
        return 0
    }

    var attachedOpenAIDashboardSnapshot: OpenAIDashboardSnapshot? {
        guard self.openAIDashboardAttachmentAuthorized else { return nil }
        return self.openAIDashboard
    }

    /// Returns the login method (plan type) for the specified provider, if available.
    private func loginMethod(for provider: UsageProvider) -> String? {
        self.snapshots[provider.instanceID]?.loginMethod(for: provider)
    }

    /// Returns true if the Claude account appears to be a subscription (Max, Pro, Ultra, Team).
    /// Returns false for API users or when plan cannot be determined.
    func isClaudeSubscription() -> Bool {
        // Provider-specific by design: Claude subscription plans choose its consumer dashboard account action.
        Self.isSubscriptionPlan(self.loginMethod(for: .claude))
    }

    /// Determines if a login method string indicates a Claude subscription plan.
    /// Known subscription indicators: Max, Pro, Ultra, Team (case-insensitive).
    nonisolated static func isSubscriptionPlan(_ loginMethod: String?) -> Bool {
        ClaudePlan.isSubscriptionLoginMethod(loginMethod)
    }

    var preferredSnapshot: UsageSnapshot? {
        for provider in self.enabledProviders() {
            if let snap = self.snapshots[provider] {
                return snap
            }
        }
        return nil
    }
}
