import CodexBarCore
import Foundation

struct SpendDashboardCodexCostCatchUpContext: Sendable {
    let token: UUID
    let accounts: [CodexSpendScanRequest]
    let historyDays: Int
    let providerConfigRevision: UInt64
    let costUsageSettingsRevision: UInt64
}

extension UsageStore {
    func refreshSpendDashboard(accounts: [CodexSpendScanRequest]) {
        self.sharedSpendDashboardController().refresh()
        guard self.spendDashboardCodexCostCatchUpActivity?.requiresExplicitResume == true else { return }
        self.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: .automatic)
    }

    func synchronizeSpendDashboardCodexCostCatchUp(
        accounts: [CodexSpendScanRequest],
        preferredMode: CodexCostCatchUpMode? = nil)
    {
        let accounts = self.enabledSpendDashboardCodexAccounts(accounts)
        guard !accounts.isEmpty else {
            self.cancelSpendDashboardCodexCostCatchUp()
            return
        }
        // Observation-driven reloads must not undo a stop or repeatedly retry a stalled/failed pass.
        // Explicit Refresh uses startSpendDashboardCodexCostCatchUpIfNeeded directly.
        guard !self.spendDashboardCodexCostCatchUpStopRequested else { return }
        if self.spendDashboardCodexCostCatchUpActivity?.requiresExplicitResume == true {
            self.checkSpendDashboardCodexCostCatchUpCompletion(accounts: accounts)
            return
        }
        var mode = preferredMode
            ?? (self.spendDashboardCodexCostCatchUpTask == nil ? .automatic : self.spendDashboardCodexCostCatchUpMode)
        if preferredMode == .accelerated,
           self.spendDashboardCodexCostCatchUpTask == nil
           || self.spendDashboardCodexCostCatchUpMode != .accelerated,
           case .pause = self.codexCostCatchUpDecision(
               mode: .automatic,
               previousActiveDuration: nil,
               resourceState: self._test_spendDashboardCodexCostCatchUpResourceStateOverride?()).action
        {
            mode = .automatic
        }
        self.startSpendDashboardCodexCostCatchUpIfNeeded(accounts: accounts, mode: mode)
    }

    func startSpendDashboardCodexCostCatchUpIfNeeded(
        accounts: [CodexSpendScanRequest],
        mode: CodexCostCatchUpMode = .automatic)
    {
        let accounts = self.enabledSpendDashboardCodexAccounts(accounts)
        guard !accounts.isEmpty else {
            self.cancelSpendDashboardCodexCostCatchUp()
            return
        }

        let historyDays = max(SpendDashboardSource.scanDays, self.settings.costUsageHistoryDays)
        let accountScopeSignature = accounts
            .map { "\($0.id)|\($0.cacheIdentity)" }
            .joined(separator: "\u{0}")
        let scopeSignature = "\(historyDays)\u{0}\(accountScopeSignature)"
        if self.spendDashboardCodexCostCatchUpTask != nil,
           self.spendDashboardCodexCostCatchUpScopeSignature == scopeSignature
        {
            if self.spendDashboardCodexCostCatchUpMode == mode {
                // A dashboard reload can discover fresh tail work while the previous task is
                // completing. Queue one restart so that the new pending status retains a worker.
                self.spendDashboardCodexCostCatchUpRestartRequested = true
                return
            }
            self.spendDashboardCodexCostCatchUpMode = mode
            // A bounded parser pass may be committing a resume checkpoint. Let it finish and
            // apply the new mode before scheduling the next account instead of cancelling it.
            if self.spendDashboardCodexCostCatchUpPassIsRunning {
                return
            }
        }

        self.cancelSpendDashboardCodexCostCatchUp()
        let token = UUID()
        let context = SpendDashboardCodexCostCatchUpContext(
            token: token,
            accounts: accounts,
            historyDays: historyDays,
            providerConfigRevision: self.settings.providerConfigRevision(for: .codex),
            costUsageSettingsRevision: self.settings.costUsageSettingsRevision)
        self.spendDashboardCodexCostCatchUpToken = token
        self.spendDashboardCodexCostCatchUpScopeSignature = scopeSignature
        self.spendDashboardCodexCostCatchUpMode = mode
        self.spendDashboardCodexCostCatchUpStopRequested = false
        self.spendDashboardCodexCostCatchUpPassIsRunning = false
        let priority: TaskPriority = mode == .accelerated ? .utility : .background
        self.spendDashboardCodexCostCatchUpTask = Task(priority: priority) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishSpendDashboardCodexCostCatchUp(context: context) }
            await self.runSpendDashboardCodexCostCatchUp(context: context)
        }
    }

    private func finishSpendDashboardCodexCostCatchUp(context: SpendDashboardCodexCostCatchUpContext) {
        guard self.spendDashboardCodexCostCatchUpToken == context.token else { return }
        // Scope invalidation can exit without publishing a terminal activity.
        if self.spendDashboardCodexCostCatchUpActivity?.phase == .indexing {
            self.spendDashboardCodexCostCatchUpActivity = nil
        }
        self.spendDashboardCodexCostCatchUpTask = nil
        self.spendDashboardCodexCostCatchUpToken = nil
        self.spendDashboardCodexCostCatchUpScopeSignature = nil
        let restartRequested = self.spendDashboardCodexCostCatchUpRestartRequested
        self.spendDashboardCodexCostCatchUpRestartRequested = false
        if restartRequested, self.spendDashboardCodexCostCatchUpActivity?.requiresExplicitResume != true {
            self.startSpendDashboardCodexCostCatchUpIfNeeded(
                accounts: context.accounts,
                mode: self.spendDashboardCodexCostCatchUpMode)
        }
    }

    func stopSpendDashboardCodexCostCatchUp() {
        guard self.spendDashboardCodexCostCatchUpTask != nil else { return }
        self.spendDashboardCodexCostCatchUpStopRequested = true
        self.spendDashboardCodexCostCatchUpRestartRequested = false
        guard !self.spendDashboardCodexCostCatchUpPassIsRunning else { return }
        self.spendDashboardCodexCostCatchUpActivity?.phase = .paused
        self.spendDashboardCodexCostCatchUpActivity?.pauseReason = .user
        self.spendDashboardCodexCostCatchUpTask?.cancel()
        self.spendDashboardCodexCostCatchUpTask = nil
        self.spendDashboardCodexCostCatchUpToken = nil
        self.spendDashboardCodexCostCatchUpScopeSignature = nil
    }

    func cancelSpendDashboardCodexCostCatchUp() {
        self.spendDashboardCodexCostCatchUpPausedContext = nil
        self.spendDashboardCodexCostCatchUpTask?.cancel()
        self.spendDashboardCodexCostCatchUpTask = nil
        self.spendDashboardCodexCostCatchUpToken = nil
        self.spendDashboardCodexCostCatchUpScopeSignature = nil
        self.spendDashboardCodexCostCatchUpStopRequested = false
        self.spendDashboardCodexCostCatchUpPassIsRunning = false
        self.spendDashboardCodexCostCatchUpRestartRequested = false
        self.spendDashboardCodexCostCatchUpActivity = nil
    }

    private func runSpendDashboardCodexCostCatchUp(
        context: SpendDashboardCodexCostCatchUpContext) async
    {
        var statuses = await self.loadSpendDashboardCodexCostCatchUpStatuses(context.accounts)
        func publish(_ phase: CodexCostCatchUpActivity.Phase, _ reason: CodexCostCatchUpPauseReason? = nil) {
            self.publishSpendDashboardCodexCostCatchUpActivity(
                statuses: statuses, context: context, phase: phase, pauseReason: reason)
        }
        guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
        publish(statuses.values.contains(where: \.pending) ? .indexing : .complete)

        var didChangeCache = false
        func checkContinuation() throws {
            guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { throw CancellationError() }
            if self.spendDashboardCodexCostCatchUpStopRequested {
                publish(.paused, .user)
                self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                throw CancellationError()
            }
        }
        var previousActiveDuration: TimeInterval?
        var completedPasses = 0
        var recoveredCaches: Set<String> = []
        var (stalledCacheIdentities, seenKeysByCache) =
            (Set<String>(), statuses.mapValues { Set([$0.progressKey]) })
        while statuses.values.contains(where: \.pending) {
            do {
                try checkContinuation()

                guard let account = context.accounts.first(where: {
                    statuses[$0.cacheIdentity]?.pending == true
                        && !stalledCacheIdentities.contains($0.cacheIdentity)
                }) else {
                    publish(.paused, .noProgress)
                    self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                    CodexBarLog.logger(LogCategories.tokenCost).warning(
                        "Spend Dashboard Codex cost catch-up stopped because all pending account caches stalled")
                    return
                }

                let decision = self.codexCostCatchUpDecision(
                    mode: self.spendDashboardCodexCostCatchUpMode,
                    previousActiveDuration: previousActiveDuration,
                    completedPasses: completedPasses,
                    resourceState: self._test_spendDashboardCodexCostCatchUpResourceStateOverride?())
                switch decision.action {
                case let .pause(delay, reason):
                    publish(.paused, reason)
                    try await self.sleepBetweenCodexCostCatchUpPasses(seconds: delay, dashboard: true)
                    continue
                case let .runAfter(delay):
                    publish(.indexing)
                    if delay > 0 || self.spendDashboardCodexCostCatchUpMode == .accelerated {
                        previousActiveDuration = nil
                        completedPasses = 0
                    }
                    try await self.sleepBetweenCodexCostCatchUpPasses(seconds: delay, dashboard: true)
                }

                try checkContinuation()

                let previousStatus = statuses[account.cacheIdentity]
                let result = try await self.advanceSpendDashboardCodexCostCatchUp(
                    account: account,
                    historyDays: context.historyDays,
                    previousActiveDuration: previousActiveDuration)
                let nextStatus = result.value
                previousActiveDuration = (previousActiveDuration ?? 0) + result.activeDuration
                completedPasses += 1
                didChangeCache = didChangeCache || nextStatus.progressKey != previousStatus?.progressKey
                statuses[account.cacheIdentity] = nextStatus
                if nextStatus.pending,
                   !seenKeysByCache[account.cacheIdentity, default: []].insert(nextStatus.progressKey).inserted
                {
                    if nextStatus.progressKey == previousStatus?.progressKey,
                       nextStatus.yieldedBeforeFileAttempt,
                       recoveredCaches.insert(account.cacheIdentity).inserted
                    {
                        previousActiveDuration = max(
                            previousActiveDuration ?? 0,
                            CodexCostCatchUpPolicy.automaticBurstDuration)
                    } else {
                        stalledCacheIdentities.insert(account.cacheIdentity)
                    }
                } else {
                    stalledCacheIdentities.remove(account.cacheIdentity)
                }

                guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
                let isPending = statuses.values.contains(where: \.pending)
                publish(isPending ? .indexing : .complete)
                try checkContinuation()
            } catch is CancellationError {
                return
            } catch {
                guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context) else { return }
                publish(.paused, .error(error.localizedDescription))
                self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
                CodexBarLog.logger(LogCategories.tokenCost).warning(
                    "Spend Dashboard Codex cost catch-up stopped after error: \(error.localizedDescription)")
                return
            }
        }

        self.publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(didChangeCache)
    }

    private func spendDashboardCodexCostCatchUpContextIsCurrent(
        _ context: SpendDashboardCodexCostCatchUpContext) -> Bool
    {
        !Task.isCancelled
            && self.spendDashboardCodexCostCatchUpToken == context.token
            && self.spendDashboardCodexCostCatchUpConfigurationIsCurrent(context)
    }

    private func spendDashboardCodexCostCatchUpConfigurationIsCurrent(
        _ context: SpendDashboardCodexCostCatchUpContext) -> Bool
    {
        self.settings.providerConfigRevision(for: .codex) == context.providerConfigRevision
            && self.settings.costUsageSettingsRevision == context.costUsageSettingsRevision
            && max(SpendDashboardSource.scanDays, self.settings.costUsageHistoryDays) == context.historyDays
            && self.settings.isCostUsageEffectivelyEnabled(for: .codex)
            && self.isEnabled(.codex)
            && context.accounts.allSatisfy(SpendDashboardSource.codexAuthFingerprintMatches)
    }

    private func checkSpendDashboardCodexCostCatchUpCompletion(accounts: [CodexSpendScanRequest]) {
        guard let context = self.spendDashboardCodexCostCatchUpPausedContext else { return }
        guard context.accounts == accounts else {
            self.spendDashboardCodexCostCatchUpTask?.cancel()
            return
        }
        guard self.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress,
              self.spendDashboardCodexCostCatchUpTask == nil,
              self.spendDashboardCodexCostCatchUpConfigurationIsCurrent(context)
        else { return }
        self.spendDashboardCodexCostCatchUpToken = context.token
        // Reuse worker ownership for a read-only check; this task never advances the scanner.
        self.spendDashboardCodexCostCatchUpTask = Task(priority: .background) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishSpendDashboardCodexCostCatchUp(context: context) }
            let statuses = await self.loadSpendDashboardCodexCostCatchUpStatuses(
                accounts, historyDays: context.historyDays)
            guard self.spendDashboardCodexCostCatchUpContextIsCurrent(context),
                  !self.spendDashboardCodexCostCatchUpStopRequested,
                  self.spendDashboardCodexCostCatchUpActivity?.pauseReason == .noProgress,
                  accounts.allSatisfy({ account in
                      let status = statuses[account.cacheIdentity]
                      return status?.pending == false && status?.completionIsConfirmed == true
                  })
            else { return }
            self.publishSpendDashboardCodexCostCatchUpActivity(
                statuses: statuses, context: context, phase: .complete)
            self.spendDashboardCodexCostCatchUpPausedContext = nil
            self.spendDashboardCodexCostCatchUpRevision &+= 1
        }
    }

    private func loadSpendDashboardCodexCostCatchUpStatuses(
        _ accounts: [CodexSpendScanRequest],
        historyDays: Int? = nil) async -> [String: CostUsageFetcher.CodexScanCatchUpStatus]
    {
        var statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus] = [:]
        for account in accounts {
            if let override = self._test_spendDashboardCodexCostCatchUpStatusOverride {
                statuses[account.cacheIdentity] = await override(account)
            } else {
                statuses[account.cacheIdentity] = await CostUsageFetcher(
                    cacheRoot: SpendDashboardSource.codexCacheRoot(for: account),
                    calendar: self.settings.costUsageBucketCalendar)
                    .codexScanCatchUpStatus(
                        codexHomePath: account.homePath,
                        historyDays: historyDays)
            }
        }
        return statuses
    }

    private func advanceSpendDashboardCodexCostCatchUp(
        account: CodexSpendScanRequest,
        historyDays: Int,
        previousActiveDuration: TimeInterval?) async throws
        -> CostUsageScanExecutor.TimedResult<CostUsageFetcher.CodexScanCatchUpStatus>
    {
        let durationBudget = self.spendDashboardCodexCostCatchUpMode
            .scanDurationPerRefresh(after: previousActiveDuration)
        self._test_codexCostCatchUpBudgetObserver?(durationBudget)
        let token = self.spendDashboardCodexCostCatchUpToken
        self.spendDashboardCodexCostCatchUpPassIsRunning = true
        defer {
            if self.spendDashboardCodexCostCatchUpToken == token {
                self.spendDashboardCodexCostCatchUpPassIsRunning = false
            }
        }
        if let override = self._test_spendDashboardCodexCostCatchUpAdvanceOverride {
            return try await .init(
                value: override(account, Date(), historyDays),
                activeDuration: self._test_spendDashboardCodexCostCatchUpActiveDuration)
        }
        return try await CostUsageFetcher(
            cacheRoot: SpendDashboardSource.codexCacheRoot(for: account),
            calendar: self.settings.costUsageBucketCalendar)
            .advanceCodexScanCatchUp(
                codexHomePath: account.homePath,
                historyDays: historyDays,
                scanDurationPerRefresh: durationBudget)
    }

    private func publishSpendDashboardCodexCostCatchUpActivity(
        statuses: [String: CostUsageFetcher.CodexScanCatchUpStatus],
        context: SpendDashboardCodexCostCatchUpContext,
        phase: CodexCostCatchUpActivity.Phase,
        pauseReason: CodexCostCatchUpPauseReason? = nil)
    {
        guard self.spendDashboardCodexCostCatchUpToken == context.token else { return }
        if phase == .paused, pauseReason == .noProgress {
            self.spendDashboardCodexCostCatchUpPausedContext = context
        }
        let values = context.accounts.compactMap { statuses[$0.cacheIdentity] }
        let hasIndeterminatePendingStatus = values.contains {
            $0.pending && $0.totalBytes == 0 && $0.totalFiles == 0
        }
        self.spendDashboardCodexCostCatchUpActivity = CodexCostCatchUpActivity(
            phase: phase,
            mode: self.spendDashboardCodexCostCatchUpMode,
            processedBytes: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.processedBytes },
            totalBytes: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.totalBytes },
            completedFiles: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.completedFiles },
            totalFiles: hasIndeterminatePendingStatus ? 0 : values.reduce(0) { $0 + $1.totalFiles },
            pauseReason: pauseReason,
            staleSnapshotUpdatedAt: values.compactMap(\.staleSnapshotUpdatedAt).min())
    }

    private func publishSpendDashboardCodexCostCatchUpRevisionIfNeeded(_ didChangeCache: Bool) {
        guard didChangeCache else { return }
        self.spendDashboardCodexCostCatchUpRevision &+= 1
    }

    private func enabledSpendDashboardCodexAccounts(
        _ accounts: [CodexSpendScanRequest]) -> [CodexSpendScanRequest]
    {
        guard self.settings.isCostUsageEffectivelyEnabled(for: .codex), self.isEnabled(.codex) else { return [] }
        var seen: Set<String> = []
        return accounts.filter { seen.insert($0.cacheIdentity).inserted }
    }
}
