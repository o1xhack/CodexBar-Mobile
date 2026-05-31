import CodexBarCore
import CodexBarSync
import Foundation
import Observation
import SweetCookieKit

// MARK: - Observation helpers

@MainActor
extension UsageStore {
    var menuObservationToken: Int {
        _ = self.snapshots
        _ = self.errors
        _ = self.lastSourceLabels
        _ = self.lastFetchAttempts
        _ = self.accountSnapshots
        _ = self.codexAccountSnapshots
        _ = self.kiloScopeSnapshots
        _ = self.tokenSnapshots
        _ = self.tokenErrors
        _ = self.tokenRefreshInFlight
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.openAIDashboardAttachmentRevision
        _ = self.versions
        _ = self.isRefreshing
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
        _ = self.errors
        _ = self.credits
        _ = self.lastCreditsError
        _ = self.openAIDashboard
        _ = self.lastOpenAIDashboardError
        _ = self.openAIDashboardRequiresLogin
        _ = self.refreshingProviders
        _ = self.statuses
        _ = self.historicalPaceRevision
        return 0
    }

    func observeSettingsChanges() {
        withObservationTracking {
            _ = self.settings.refreshFrequency
            _ = self.settings.statusChecksEnabled
            _ = self.settings.sessionQuotaNotificationsEnabled
            _ = self.settings.quotaWarningNotificationsEnabled
            _ = self.settings.quotaWarningThresholds
            _ = self.settings.quotaWarningThresholds(.session)
            _ = self.settings.quotaWarningThresholds(.weekly)
            _ = self.settings.quotaWarningSoundEnabled
            _ = self.settings.usageBarsShowUsed
            _ = self.settings.costUsageEnabled
            _ = self.settings.costUsageHistoryDays
            _ = self.settings.randomBlinkEnabled
            _ = self.settings.configRevision
            for implementation in ProviderCatalog.all {
                implementation.observeSettings(self.settings)
            }
            _ = self.settings.multiAccountMenuLayout
            _ = self.settings.tokenAccountsByProvider
            _ = self.settings.mergeIcons
            _ = self.settings.selectedMenuProvider
            _ = self.settings.debugLoadingPattern
            _ = self.settings.debugKeepCLISessionsAlive
            _ = self.settings.historicalTrackingEnabled
            _ = self.settings.providerStorageFootprintsEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSettingsChanges()
                self.invalidateProviderAvailabilityCache()
                self.probeLogs = [:]
                guard self.startupBehavior.automaticallyStartsBackgroundWork else { return }
                self.startTimer()
                self.updateProviderRuntimes()
                await self.refreshHistoricalDatasetIfNeeded()
                await self.refresh()
            }
        }
    }

    var attachedOpenAIDashboardSnapshot: OpenAIDashboardSnapshot? {
        guard self.openAIDashboardAttachmentAuthorized else { return nil }
        return self.openAIDashboard
    }
}

@MainActor
@Observable
final class UsageStore {
    private struct ProviderAvailabilityCacheEntry {
        let available: Bool
        let configRevision: Int
        let expiresAt: Date

        func isValid(now: Date, configRevision: Int) -> Bool {
            self.configRevision == configRevision && self.expiresAt > now
        }
    }

    enum CodexCreditsSource {
        case none
        case api
        case dashboardWeb
    }

    var snapshots: [UsageProvider: UsageSnapshot] = [:]
    var errors: [UsageProvider: String] = [:]
    var lastSourceLabels: [UsageProvider: String] = [:]
    var lastFetchAttempts: [UsageProvider: [ProviderFetchAttempt]] = [:]
    var accountSnapshots: [UsageProvider: [TokenAccountUsageSnapshot]] = [:]
    var codexAccountSnapshots: [CodexAccountUsageSnapshot] = []
    var kiloScopeSnapshots: [KiloScopeSnapshot] = []
    var tokenSnapshots: [UsageProvider: CostUsageTokenSnapshot] = [:]
    var tokenErrors: [UsageProvider: String] = [:]
    var tokenRefreshInFlight: Set<UsageProvider> = []
    var credits: CreditsSnapshot?
    var lastCreditsError: String?
    var openAIDashboard: OpenAIDashboardSnapshot?
    var lastOpenAIDashboardError: String?
    var openAIDashboardRequiresLogin: Bool = false
    var openAIDashboardCookieImportStatus: String?
    var openAIDashboardCookieImportDebugLog: String?
    var versions: [UsageProvider: String] = [:]
    var isRefreshing = false
    var refreshingProviders: Set<UsageProvider> = []
    var debugForceAnimation = false
    var pathDebugInfo: PathDebugSnapshot = .empty
    var statuses: [UsageProvider: ProviderStatus] = [:]
    var probeLogs: [UsageProvider: String] = [:]
    var historicalPaceRevision: Int = 0
    var planUtilizationHistoryRevision: Int = 0
    var providerStorageFootprints: [UsageProvider: ProviderStorageFootprint] = [:]
    @ObservationIgnored var lastCreditsSnapshot: CreditsSnapshot?
    @ObservationIgnored var lastCreditsSnapshotAccountKey: String?
    @ObservationIgnored var lastCreditsSource: CodexCreditsSource = .none
    @ObservationIgnored var creditsFailureStreak: Int = 0
    @ObservationIgnored var openAIDashboardAttachmentAuthorized: Bool = false {
        didSet {
            guard self.openAIDashboardAttachmentAuthorized != oldValue else { return }
            self.openAIDashboardAttachmentRevision &+= 1
        }
    }

    var openAIDashboardAttachmentRevision = 0
    @ObservationIgnored var lastOpenAIDashboardSnapshot: OpenAIDashboardSnapshot?
    @ObservationIgnored var lastOpenAIDashboardAttachmentAuthorized: Bool = false
    @ObservationIgnored var lastOpenAIDashboardTargetEmail: String?
    @ObservationIgnored var lastOpenAIDashboardAttemptAt: Date?
    @ObservationIgnored var lastOpenAIDashboardCookieImportAttemptAt: Date?
    @ObservationIgnored var lastOpenAIDashboardCookieImportEmail: String?
    @ObservationIgnored var lastCodexAccountScopedRefreshGuard: CodexAccountScopedRefreshGuard?
    @ObservationIgnored var lastKnownLiveSystemCodexEmail: String?
    @ObservationIgnored var openAIWebAccountDidChange: Bool = false
    @ObservationIgnored var creditsRefreshTask: Task<Void, Never>?
    @ObservationIgnored var creditsRefreshTaskKey: String?
    @ObservationIgnored var openAIDashboardBackgroundRefreshTask: Task<Void, Never>?
    @ObservationIgnored var openAIDashboardBackgroundRefreshTaskKey: String?
    @ObservationIgnored var openAIDashboardRefreshTask: Task<Void, Never>?
    @ObservationIgnored var openAIDashboardRefreshTaskKey: String?
    @ObservationIgnored var openAIDashboardRefreshTaskToken: UUID?
    @ObservationIgnored var _test_openAIDashboardCookieImportOverride: (@MainActor (
        String?,
        Bool,
        ProviderCookieSource,
        CookieHeaderCache.Scope?,
        @escaping (String) -> Void) async throws -> OpenAIDashboardBrowserCookieImporter.ImportResult)?
    @ObservationIgnored var _test_openAIDashboardLoaderOverride: (@MainActor (
        String?,
        @escaping (String) -> Void,
        Bool,
        TimeInterval) async throws -> OpenAIDashboardSnapshot)?
    @ObservationIgnored var _test_codexCreditsLoaderOverride: (@MainActor () async throws -> CreditsSnapshot)?
    @ObservationIgnored var _test_widgetSnapshotSaveOverride: (@MainActor (WidgetSnapshot) async -> Void)?
    @ObservationIgnored var _test_providerRefreshOverride: (@MainActor (UsageProvider) async -> Void)?
    @ObservationIgnored var _test_tokenUsageRefreshOverride: (@MainActor (UsageProvider, Bool) async -> Void)?
    @ObservationIgnored var _test_providerStatusFetchOverride: (@MainActor (
        UsageProvider) async throws -> ProviderStatus)?
    @ObservationIgnored var _test_startupConnectivityRetryScheduled: (@MainActor (Int, TimeInterval) -> Void)?
    @ObservationIgnored var _test_startupConnectivityRetrySleepOverride: (@MainActor (
        TimeInterval) async throws -> Void)?
    @ObservationIgnored var widgetSnapshotPersistTask: Task<Void, Never>?

    @ObservationIgnored let codexFetcher: UsageFetcher
    @ObservationIgnored let claudeFetcher: any ClaudeUsageFetching
    @ObservationIgnored let costUsageFetcher: CostUsageFetcher
    @ObservationIgnored let browserDetection: BrowserDetection
    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let environmentBase: [String: String]
    @ObservationIgnored private let sessionQuotaNotifier: any SessionQuotaNotifying
    @ObservationIgnored private let quotaTransitionWriter: any QuotaTransitionWriting
    @ObservationIgnored private let sessionQuotaLogger = CodexBarLog.logger(LogCategories.sessionQuota)
    @ObservationIgnored let openAIWebLogger = CodexBarLog.logger(LogCategories.openAIWeb)
    @ObservationIgnored private let tokenCostLogger = CodexBarLog.logger(LogCategories.tokenCost)
    @ObservationIgnored let augmentLogger = CodexBarLog.logger(LogCategories.augment)
    @ObservationIgnored let providerLogger = CodexBarLog.logger(LogCategories.providers)
    @ObservationIgnored var openAIWebDebugLines: [String] = []
    @ObservationIgnored var failureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    @ObservationIgnored var tokenFailureGates: [UsageProvider: ConsecutiveFailureGate] = [:]
    @ObservationIgnored var providerSpecs: [UsageProvider: ProviderSpec] = [:]
    @ObservationIgnored let providerMetadata: [UsageProvider: ProviderMetadata]
    @ObservationIgnored var providerRuntimes: [UsageProvider: any ProviderRuntime] = [:]
    @ObservationIgnored private var providerAvailabilityCache: [UsageProvider: ProviderAvailabilityCacheEntry] = [:]
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var tokenTimerTask: Task<Void, Never>?
    @ObservationIgnored private var tokenRefreshSequenceTask: Task<Void, Never>?
    @ObservationIgnored var memoryPressureReliefTask: Task<Void, Never>?
    @ObservationIgnored var startupConnectivityRetryTask: Task<Void, Never>?
    @ObservationIgnored var startupConnectivityRetryNeeded = false
    @ObservationIgnored var startupConnectivityRetryRefreshActive = false
    @ObservationIgnored var storageRefreshTask: Task<Void, Never>?
    @ObservationIgnored var storageRefreshGeneration: UInt64 = 0
    @ObservationIgnored var storageRefreshInFlightSignature: String?
    @ObservationIgnored var lastStorageRefreshSignature: String?
    @ObservationIgnored var lastStorageRefreshAt: Date?
    @ObservationIgnored var managedCodexAccountsForStorageOverride: [ManagedCodexAccount]?
    @ObservationIgnored private var pathDebugRefreshTask: Task<Void, Never>?
    @ObservationIgnored var codexPlanHistoryBackfillTask: Task<Void, Never>?
    @ObservationIgnored let historicalUsageHistoryStore: HistoricalUsageHistoryStore
    @ObservationIgnored let planUtilizationHistoryStore: PlanUtilizationHistoryStore
    @ObservationIgnored let codexAccountUsageSnapshotStore: (any CodexAccountUsageSnapshotStoring)?
    @ObservationIgnored var codexHistoricalDataset: CodexHistoricalDataset?
    @ObservationIgnored var codexHistoricalDatasetAccountKey: String?
    @ObservationIgnored var lastKnownResetSnapshots: [UsageProvider: UsageSnapshot] = [:]
    @ObservationIgnored var lastKnownSessionRemaining: [UsageProvider: Double] = [:]
    @ObservationIgnored var lastKnownSessionWindowSource: [UsageProvider: SessionQuotaWindowSource] = [:]
    @ObservationIgnored var quotaWarningState: [QuotaWarningStateKey: QuotaWarningState] = [:]
    @ObservationIgnored var lastPermissionPromptNotificationAt: [UsageProvider: Date] = [:]
    @ObservationIgnored var lastTokenFetchAt: [UsageProvider: Date] = [:]
    @ObservationIgnored var lastTokenFetchScope: [UsageProvider: String] = [:]
    @ObservationIgnored var planUtilizationHistory: [UsageProvider: PlanUtilizationHistoryBuckets] = [:]
    @ObservationIgnored var weeklyLimitResetDetectorStates: [String: WeeklyLimitResetDetectorState] = [:]
    @ObservationIgnored private var hasCompletedInitialRefresh: Bool = false
    @ObservationIgnored private let providerAvailabilityCacheTTL: TimeInterval = 1
    @ObservationIgnored private let tokenFetchTTL: TimeInterval = 60 * 60
    @ObservationIgnored private let tokenFetchTimeout: TimeInterval = 10 * 60
    @ObservationIgnored let startupBehavior: StartupBehavior
    @ObservationIgnored let planUtilizationPersistenceCoordinator: PlanUtilizationHistoryPersistenceCoordinator

    init(
        fetcher: UsageFetcher,
        browserDetection: BrowserDetection,
        claudeFetcher: (any ClaudeUsageFetching)? = nil,
        costUsageFetcher: CostUsageFetcher = CostUsageFetcher(),
        settings: SettingsStore,
        registry: ProviderRegistry = .shared,
        historicalUsageHistoryStore: HistoricalUsageHistoryStore = HistoricalUsageHistoryStore(),
        planUtilizationHistoryStore: PlanUtilizationHistoryStore = .defaultAppSupport(),
        codexAccountUsageSnapshotStore: (any CodexAccountUsageSnapshotStoring)? = nil,
        sessionQuotaNotifier: any SessionQuotaNotifying = SessionQuotaNotifier(),
        quotaTransitionWriter: any QuotaTransitionWriting = QuotaTransitionWriter(),
        startupBehavior: StartupBehavior = .automatic,
        environmentBase: [String: String] = ProcessInfo.processInfo.environment)
    {
        self.codexFetcher = fetcher
        self.browserDetection = browserDetection
        self.claudeFetcher = claudeFetcher ?? ClaudeUsageFetcher(browserDetection: browserDetection)
        self.costUsageFetcher = costUsageFetcher
        self.settings = settings
        self.registry = registry
        self.environmentBase = environmentBase
        self.historicalUsageHistoryStore = historicalUsageHistoryStore
        self.planUtilizationHistoryStore = planUtilizationHistoryStore
        self.sessionQuotaNotifier = sessionQuotaNotifier
        self.quotaTransitionWriter = quotaTransitionWriter
        self.startupBehavior = startupBehavior.resolved(isRunningTests: Self.isRunningTestsProcess())
        self.codexAccountUsageSnapshotStore = codexAccountUsageSnapshotStore ??
            (self.startupBehavior.automaticallyStartsBackgroundWork ? FileCodexAccountUsageSnapshotStore() : nil)
        self.planUtilizationPersistenceCoordinator = PlanUtilizationHistoryPersistenceCoordinator(
            store: planUtilizationHistoryStore)
        self.providerMetadata = registry.metadata
        self
            .failureGates = Dictionary(
                uniqueKeysWithValues: UsageProvider.allCases
                    .map { ($0, ConsecutiveFailureGate()) })
        self.tokenFailureGates = Dictionary(
            uniqueKeysWithValues: UsageProvider.allCases
                .map { ($0, ConsecutiveFailureGate()) })
        self.providerSpecs = registry.specs(
            settings: settings,
            metadata: self.providerMetadata,
            codexFetcher: fetcher,
            claudeFetcher: self.claudeFetcher,
            browserDetection: browserDetection,
            environmentBase: environmentBase)
        self.providerRuntimes = Dictionary(uniqueKeysWithValues: ProviderCatalog.all.compactMap { implementation in
            implementation.makeRuntime().map { (implementation.id, $0) }
        })
        self.planUtilizationHistory = planUtilizationHistoryStore.load()
        self.weeklyLimitResetDetectorStates = Self.loadWeeklyLimitResetDetectorStates(from: settings.userDefaults)
        if let codexAccountUsageSnapshotStore = self.codexAccountUsageSnapshotStore {
            self.codexAccountSnapshots = codexAccountUsageSnapshotStore.load(
                for: settings.codexVisibleAccountProjection.visibleAccounts)
        }
        self.logStartupState()
        self.bindSettings()
        self.pathDebugInfo = PathDebugSnapshot(
            codexBinary: nil,
            claudeBinary: nil,
            geminiBinary: nil,
            effectivePATH: PathBuilder.effectivePATH(purposes: [.rpc, .tty, .nodeTooling]),
            loginShellPATH: LoginShellPathCache.shared.current?.joined(separator: ":"))
        guard self.startupBehavior.automaticallyStartsBackgroundWork else { return }
        self.hydrateCachedTokenSnapshots()
        self.detectVersions()
        self.updateProviderRuntimes()
        Task { @MainActor [weak self] in
            self?.schedulePathDebugInfoRefresh()
        }
        LoginShellPathCache.shared.captureOnce { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePathDebugInfoRefresh()
            }
        }
        Task { @MainActor [weak self] in
            await self?.refreshHistoricalDatasetIfNeeded()
        }
        Task { await self.refresh() }
        self.startTimer()
        self.startTokenTimer()
    }

    private static func isRunningTestsProcess() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        if environment["SWIFT_TESTING_ENABLED"] != nil { return true }
        return CommandLine.arguments.contains { argument in
            argument.contains("xctest") || argument.contains("swift-testing")
        }
    }

    /// Returns the login method (plan type) for the specified provider, if available.
    private func loginMethod(for provider: UsageProvider) -> String? {
        self.snapshots[provider]?.loginMethod(for: provider)
    }

    /// Returns true if the Claude account appears to be a subscription (Max, Pro, Ultra, Team).
    /// Returns false for API users or when plan cannot be determined.
    func isClaudeSubscription() -> Bool {
        Self.isSubscriptionPlan(self.loginMethod(for: .claude))
    }

    /// Determines if a login method string indicates a Claude subscription plan.
    /// Known subscription indicators: Max, Pro, Ultra, Team (case-insensitive).
    nonisolated static func isSubscriptionPlan(_ loginMethod: String?) -> Bool {
        ClaudePlan.isSubscriptionLoginMethod(loginMethod)
    }

    func version(for provider: UsageProvider) -> String? {
        self.versions[provider]
    }

    var preferredSnapshot: UsageSnapshot? {
        for provider in self.enabledProviders() {
            if let snap = self.snapshots[provider] { return snap }
        }
        return nil
    }

    var iconStyle: IconStyle {
        let enabled = self.enabledProviders()
        if enabled.count > 1 { return .combined }
        if let provider = enabled.first {
            return self.style(for: provider)
        }
        return .codex
    }

    var isStale: Bool {
        for provider in self.enabledProviders() where self.errors[provider] != nil {
            return true
        }
        return false
    }

    func enabledProviders() -> [UsageProvider] {
        // Use cached enablement to avoid repeated UserDefaults lookups in animation ticks.
        let enabled = self.settings.enabledProvidersOrdered(metadataByProvider: self.providerMetadata)
        let now = Date()
        return enabled.filter { self.isProviderAvailable($0, now: now) }
    }

    /// Enabled providers without availability filtering. Used for display (switcher, merge-icons).
    func enabledProvidersForDisplay() -> [UsageProvider] {
        self.settings.enabledProvidersOrdered(metadataByProvider: self.providerMetadata)
    }

    /// Providers that should actually participate in background refresh/status/token work.
    func enabledProvidersForBackgroundWork() -> [UsageProvider] {
        self.enabledProviders()
    }

    var statusChecksEnabled: Bool {
        self.settings.statusChecksEnabled
    }

    func metadata(for provider: UsageProvider) -> ProviderMetadata {
        self.providerMetadata[provider]!
    }

    var codexBrowserCookieOrder: BrowserCookieImportOrder {
        self.metadata(for: .codex).browserCookieOrder ?? Browser.defaultImportOrder
    }

    func snapshot(for provider: UsageProvider) -> UsageSnapshot? {
        self.snapshots[provider]
    }

    func sourceLabel(for provider: UsageProvider) -> String {
        var label = self.lastSourceLabels[provider] ?? ""
        if label.isEmpty {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let modes = descriptor.fetchPlan.sourceModes
            if modes.count == 1, let mode = modes.first {
                label = mode.rawValue
            } else {
                let context = ProviderSourceLabelContext(
                    provider: provider,
                    settings: self.settings,
                    store: self,
                    descriptor: descriptor)
                label = ProviderCatalog.implementation(for: provider)?
                    .defaultSourceLabel(context: context)
                    ?? "auto"
            }
        }

        let context = ProviderSourceLabelContext(
            provider: provider,
            settings: self.settings,
            store: self,
            descriptor: ProviderDescriptorRegistry.descriptor(for: provider))
        return ProviderCatalog.implementation(for: provider)?
            .decorateSourceLabel(context: context, baseLabel: label)
            ?? label
    }

    func fetchAttempts(for provider: UsageProvider) -> [ProviderFetchAttempt] {
        self.lastFetchAttempts[provider] ?? []
    }

    func style(for provider: UsageProvider) -> IconStyle {
        self.providerSpecs[provider]?.style ?? .codex
    }

    func isStale(provider: UsageProvider) -> Bool {
        self.errors[provider] != nil
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        let enabled = self.settings.isProviderEnabledCached(
            provider: provider,
            metadataByProvider: self.providerMetadata)
        guard enabled else { return false }
        return self.isProviderAvailable(provider)
    }

    func isProviderAvailable(_ provider: UsageProvider) -> Bool {
        self.isProviderAvailable(provider, now: Date())
    }

    private func isProviderAvailable(_ provider: UsageProvider, now: Date) -> Bool {
        guard provider != .codex else { return true }

        let configRevision = self.settings.configRevision
        if let cached = self.providerAvailabilityCache[provider],
           cached.isValid(now: now, configRevision: configRevision)
        {
            return cached.available
        }

        // Availability should mirror the effective fetch environment, including token-account overrides.
        // Otherwise providers (notably token-account-backed API providers) can fetch successfully but be
        // hidden from the menu because their credentials are not in ProcessInfo's environment.
        let environment = ProviderRegistry.makeEnvironment(
            base: self.environmentBase,
            provider: provider,
            settings: self.settings,
            tokenOverride: nil)
        let context = ProviderAvailabilityContext(
            provider: provider,
            settings: self.settings,
            environment: environment)
        let available = ProviderCatalog.implementation(for: provider)?
            .isAvailable(context: context)
            ?? true
        self.providerAvailabilityCache[provider] = ProviderAvailabilityCacheEntry(
            available: available,
            configRevision: configRevision,
            expiresAt: now.addingTimeInterval(self.providerAvailabilityCacheTTL))
        return available
    }

    private func invalidateProviderAvailabilityCache() {
        self.providerAvailabilityCache.removeAll(keepingCapacity: true)
    }

    func performRuntimeAction(_ action: ProviderRuntimeAction, for provider: UsageProvider) async {
        guard let runtime = self.providerRuntimes[provider] else { return }
        let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
        await runtime.perform(action: action, context: context)
    }

    private func updateProviderRuntimes() {
        for (provider, runtime) in self.providerRuntimes {
            let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
            if self.isEnabled(provider) {
                runtime.start(context: context)
            } else {
                runtime.stop(context: context)
            }
            runtime.settingsDidChange(context: context)
        }
    }

    func refresh(forceTokenUsage: Bool = false) async {
        await self.runRefresh(forceTokenUsage: forceTokenUsage, startupConnectivityRetryAttempt: nil)
    }

    func runRefresh(
        forceTokenUsage: Bool = false,
        startupConnectivityRetryAttempt: Int?)
        async
    {
        guard !self.isRefreshing else { return }
        self.prepareRefreshState()
        let refreshPhase = Self.refreshPhase(hasCompletedInitialRefresh: self.hasCompletedInitialRefresh)
        let openAIWebRefreshPhase = Self.openAIWebRefreshPhase(
            providerRefreshPhase: refreshPhase,
            startupConnectivityRetryAttempt: startupConnectivityRetryAttempt)
        let allowsStartupConnectivityRetry = refreshPhase == .startup || startupConnectivityRetryAttempt != nil
        self.startupConnectivityRetryRefreshActive = allowsStartupConnectivityRetry
        self.startupConnectivityRetryNeeded = false
        let displayEnabledProviders = self.enabledProvidersForDisplay()
        let enabledProviderSet = Set(displayEnabledProviders)
        let refreshProviders = self.enabledProvidersForBackgroundWork()
        let availableRefreshProviders = Set(self.enabledProviders())
        let refreshStartedAt = Date()

        await ProviderRefreshContext.$current.withValue(refreshPhase) {
            self.isRefreshing = true
            defer {
                self.isRefreshing = false
                self.hasCompletedInitialRefresh = true
                self.startupConnectivityRetryRefreshActive = false
            }

            self.clearDisabledProviderState(enabledProviders: enabledProviderSet)
            self.clearUnavailableProviderState(
                displayEnabledProviders: enabledProviderSet,
                availableProviders: availableRefreshProviders)
            self.scheduleStorageFootprintRefresh(for: displayEnabledProviders)

            await withTaskGroup(of: Void.self) { group in
                for provider in refreshProviders {
                    group.addTask { await self.refreshProvider(provider) }
                    if availableRefreshProviders.contains(provider) {
                        group.addTask { await self.refreshStatus(provider) }
                    }
                }
                if forceTokenUsage {
                    group.addTask { await self.refreshCreditsNow(minimumSnapshotUpdatedAt: refreshStartedAt) }
                }
            }

            if !forceTokenUsage {
                self.scheduleCreditsRefreshIfNeeded(minimumSnapshotUpdatedAt: refreshStartedAt)
            }

            if forceTokenUsage {
                await self.refreshTokenUsageSequenceNow(force: true)
            } else {
                // Token-cost usage can be slow; run it outside regular/menu-open refreshes so we don't block UI.
                self.scheduleTokenRefresh(force: false)
            }

            // OpenAI web scrape depends on the current Codex account email (which can change after login/account
            // switch). Run this after Codex usage refresh so we don't accidentally scrape with stale credentials.
            self.syncOpenAIWebState()
            let refreshPolicy = OpenAIWebRefreshPolicyContext(
                accessEnabled: self.isEnabled(.codex) &&
                    self.settings.openAIWebAccessEnabled &&
                    self.settings.codexCookieSource.isEnabled,
                batterySaverEnabled: self.settings.openAIWebBatterySaverEnabled,
                force: forceTokenUsage,
                refreshPhase: openAIWebRefreshPhase)
            let shouldRefreshOpenAIWeb = Self.shouldRunOpenAIWebRefresh(refreshPolicy)
            self.openAIWebLogger.debug(
                "OpenAI web refresh gate",
                metadata: [
                    "allowed": shouldRefreshOpenAIWeb ? "1" : "0",
                    "accessEnabled": refreshPolicy.accessEnabled ? "1" : "0",
                    "batterySaverEnabled": refreshPolicy.batterySaverEnabled ? "1" : "0",
                    "force": refreshPolicy.force ? "1" : "0",
                    "interaction": ProviderInteractionContext.current == .userInitiated ? "user" : "background",
                    "phase": openAIWebRefreshPhase == .startup ? "startup" : "regular",
                ])
            if shouldRefreshOpenAIWeb {
                let codexDashboardGuard = self.currentCodexOpenAIWebRefreshGuard()
                if forceTokenUsage {
                    await self.refreshOpenAIDashboardIfNeeded(
                        force: true,
                        expectedGuard: codexDashboardGuard)
                } else {
                    self.scheduleOpenAIDashboardRefreshIfNeeded(expectedGuard: codexDashboardGuard)
                }
            }

            if forceTokenUsage, self.openAIDashboardRequiresLogin {
                await self.refreshProvider(.codex)
                await self.refreshCreditsNow(minimumSnapshotUpdatedAt: refreshStartedAt)
            }

            self.persistWidgetSnapshot(reason: "refresh")
        }

        if allowsStartupConnectivityRetry {
            self.completeStartupConnectivityRetryPass(currentAttempt: startupConnectivityRetryAttempt ?? 0)
        }
        if refreshPhase == .startup {
            self.scheduleMemoryPressureRelief()
        }
    }

    /// For demo/testing: drop the snapshot so the loading animation plays, then restore the last snapshot.
    func replayLoadingAnimation(duration: TimeInterval = 3) {
        let current = self.preferredSnapshot
        self.snapshots.removeAll()
        self.debugForceAnimation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if let current, let provider = self.enabledProviders().first {
                self.snapshots[provider] = current
            }
            self.debugForceAnimation = false
        }
    }

    // MARK: - Private

    private func bindSettings() {
        self.observeSettingsChanges()
    }

    private func startTimer() {
        self.timerTask?.cancel()
        guard let wait = self.settings.refreshFrequency.seconds else { return }

        // Background poller so the menu stays responsive; canceled when settings change or store deallocates.
        self.timerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                await self?.refresh()
            }
        }
    }

    private func startTokenTimer() {
        self.tokenTimerTask?.cancel()
        let wait = self.tokenFetchTTL
        self.tokenTimerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                await self?.scheduleTokenRefresh(force: false)
            }
        }
    }

    private func scheduleTokenRefresh(force: Bool) {
        if force {
            self.tokenRefreshSequenceTask?.cancel()
            self.tokenRefreshSequenceTask = nil
        } else if self.tokenRefreshSequenceTask != nil {
            return
        }

        self.tokenRefreshSequenceTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.tokenRefreshSequenceTask = nil
                }
            }
            await self.refreshTokenUsageSequence(force: force)
        }
    }

    private func refreshTokenUsageSequenceNow(force: Bool) async {
        if force, let existing = self.tokenRefreshSequenceTask {
            existing.cancel()
            await existing.value
            self.tokenRefreshSequenceTask = nil
        }

        await self.refreshTokenUsageSequence(force: force)
    }

    private func refreshTokenUsageSequence(force: Bool) async {
        for provider in self.enabledProvidersForBackgroundWork() {
            if Task.isCancelled { break }
            await self.refreshTokenUsage(provider, force: force)
        }
        self.scheduleMemoryPressureRelief()
    }

    deinit {
        self.timerTask?.cancel()
        self.tokenTimerTask?.cancel()
        self.tokenRefreshSequenceTask?.cancel()
        self.memoryPressureReliefTask?.cancel()
        self.startupConnectivityRetryTask?.cancel()
        self.storageRefreshTask?.cancel()
        self.codexPlanHistoryBackfillTask?.cancel()
    }

    enum SessionQuotaWindowSource: String {
        case primary
        case copilotSecondaryFallback
    }

    struct QuotaWarningStateKey: Hashable {
        let provider: UsageProvider
        let window: QuotaWarningWindow
    }

    struct QuotaWarningState {
        var lastRemaining: Double?
        var firedThresholds: Set<Int> = []
    }

    private func sessionQuotaWindow(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> (window: RateWindow, source: SessionQuotaWindowSource)?
    {
        if let primary = snapshot.primary, Self.isSessionWindow(primary) {
            return (primary, .primary)
        }
        if provider == .copilot, let secondary = snapshot.secondary {
            return (secondary, .copilotSecondaryFallback)
        }
        return nil
    }

    private static func isSessionWindow(_ window: RateWindow) -> Bool {
        guard let minutes = window.windowMinutes else { return true }
        return minutes <= 6 * 60
    }

    func handleSessionQuotaTransition(provider: UsageProvider, snapshot: UsageSnapshot) {
        // Capture account identity up front so both the depleted/restored
        // and warning paths can attribute the push to the triggering
        // account on multi-account providers. Mirrors `handleQuotaWarningTransitions`.
        let accountDisplayName = self.quotaWarningAccountDisplayName(provider: provider, snapshot: snapshot)

        // Session quota notifications are tied to the primary session window. Copilot free plans can
        // expose only chat quota, so allow Copilot to fall back to secondary for transition tracking.
        guard let sessionWindow = self.sessionQuotaWindow(provider: provider, snapshot: snapshot) else {
            self.lastKnownSessionRemaining.removeValue(forKey: provider)
            self.lastKnownSessionWindowSource.removeValue(forKey: provider)
            return
        }
        let currentRemaining = sessionWindow.window.remainingPercent
        let currentSource = sessionWindow.source
        let previousRemaining = self.lastKnownSessionRemaining[provider]
        let previousSource = self.lastKnownSessionWindowSource[provider]

        if let previousSource, previousSource != currentSource {
            let providerText = provider.rawValue
            self.sessionQuotaLogger.debug(
                "session window source changed: provider=\(providerText) prevSource=\(previousSource.rawValue) " +
                    "currSource=\(currentSource.rawValue) curr=\(currentRemaining)")
            self.lastKnownSessionRemaining[provider] = currentRemaining
            self.lastKnownSessionWindowSource[provider] = currentSource
            return
        }

        defer {
            self.lastKnownSessionRemaining[provider] = currentRemaining
            self.lastKnownSessionWindowSource[provider] = currentSource
        }

        // Compute the transition first, BEFORE any notification gates. This is essential
        // so the Mac-local notification path and the iOS-push path can be controlled
        // independently — a user may turn off Mac local notifications but still want
        // iOS push, or vice versa.
        let transition: SessionQuotaTransition
        if previousRemaining == nil {
            // Startup case: if we observe a depleted state on the very first sample,
            // synthesize a `.depleted` transition (preserving the original behaviour).
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) {
                let providerText = provider.rawValue
                self.sessionQuotaLogger.info(
                    "startup depleted: provider=\(providerText) curr=\(currentRemaining)")
                transition = .depleted
            } else {
                transition = .none
            }
        } else {
            transition = SessionQuotaNotificationLogic.transition(
                previousRemaining: previousRemaining,
                currentRemaining: currentRemaining)
        }

        if transition == .none {
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let providerText = provider.rawValue
                self.sessionQuotaLogger.debug(
                    "no transition: provider=\(providerText) " +
                        "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
            }
            return
        }

        let providerText = provider.rawValue
        let transitionText = String(describing: transition)
        self.sessionQuotaLogger.info(
            "transition \(transitionText): provider=\(providerText) " +
                "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")

        // Branch A — Mac local notification (existing behaviour, unchanged gate).
        if self.settings.sessionQuotaNotificationsEnabled {
            self.sessionQuotaNotifier.post(transition: transition, provider: provider, badge: nil)
        }

        // Branch B — iOS push via CloudKit alert push (independent gate). The writer
        // turns the transition into a CKRecord; CloudKit fires a visible push to all
        // devices subscribed to the user's iCloud account.
        if self.settings.notificationPushToiOSEnabled {
            self.quotaTransitionWriter.write(
                transition: transition,
                provider: provider,
                accountDisplayName: accountDisplayName)
        }
    }

    func handleQuotaWarningTransitions(provider: UsageProvider, snapshot: UsageSnapshot) {
        guard self.settings.quotaWarningNotificationsEnabled else { return }

        let accountDisplayName = self.quotaWarningAccountDisplayName(provider: provider, snapshot: snapshot)
        self.handleQuotaWarningTransition(
            provider: provider,
            window: .session,
            rateWindow: snapshot.primary,
            accountDisplayName: accountDisplayName)
        self.handleQuotaWarningTransition(
            provider: provider,
            window: .weekly,
            rateWindow: snapshot.secondary,
            accountDisplayName: accountDisplayName)
    }

    private func handleQuotaWarningTransition(
        provider: UsageProvider,
        window: QuotaWarningWindow,
        rateWindow: RateWindow?,
        accountDisplayName: String?)
    {
        let key = QuotaWarningStateKey(provider: provider, window: window)
        guard self.settings.quotaWarningEnabled(provider: provider, window: window) else {
            self.quotaWarningState.removeValue(forKey: key)
            return
        }
        guard let rateWindow else {
            self.quotaWarningState.removeValue(forKey: key)
            return
        }

        let thresholds = self.settings.resolvedQuotaWarningThresholds(provider: provider, window: window)
        let currentRemaining = rateWindow.remainingPercent
        var state = self.quotaWarningState[key] ?? QuotaWarningState()
        let cleared = QuotaWarningNotificationLogic.thresholdsToClear(
            currentRemaining: currentRemaining,
            alreadyFired: state.firedThresholds)
        state.firedThresholds.subtract(cleared)

        if let threshold = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: state.lastRemaining,
            currentRemaining: currentRemaining,
            thresholds: thresholds,
            alreadyFired: state.firedThresholds)
        {
            state.firedThresholds.formUnion(QuotaWarningNotificationLogic.firedThresholdsAfterWarning(
                threshold: threshold,
                thresholds: thresholds))
            self.sessionQuotaNotifier.postQuotaWarning(
                event: QuotaWarningEvent(
                    window: window,
                    threshold: threshold,
                    currentRemaining: currentRemaining,
                    accountDisplayName: accountDisplayName),
                provider: provider,
                soundEnabled: self.settings.quotaWarningSoundEnabled)

            // iOS 1.6.0 / Mac 0.25.2 — also fire a CKRecord so iPhones
            // subscribed to the warning zone get a visible push. Gated
            // by the same push-toggle that controls depleted/restored.
            // The writer debounces independently per (provider, window,
            // threshold) so it doesn't suppress a 20% push if 50% just
            // fired seconds earlier.
            if self.settings.notificationPushToiOSEnabled {
                self.quotaTransitionWriter.writeQuotaWarning(
                    provider: provider,
                    window: window,
                    threshold: threshold,
                    accountDisplayName: accountDisplayName)
            }
        }

        state.lastRemaining = currentRemaining
        self.quotaWarningState[key] = state
    }

    private func quotaWarningAccountDisplayName(provider: UsageProvider, snapshot: UsageSnapshot) -> String? {
        guard !self.settings.hidePersonalInfo else { return nil }
        let account = snapshot.accountEmail(for: provider)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account, !account.isEmpty else { return nil }
        return account
    }

    private func refreshStatus(_ provider: UsageProvider) async {
        guard self.settings.statusChecksEnabled else { return }
        guard let meta = self.providerMetadata[provider] else { return }

        do {
            let status: ProviderStatus
            if let override = self._test_providerStatusFetchOverride {
                status = try await override(provider)
            } else if let urlString = meta.statusPageURL, let baseURL = URL(string: urlString) {
                status = try await Self.fetchStatus(from: baseURL)
            } else if let productID = meta.statusWorkspaceProductID {
                status = try await Self.fetchWorkspaceStatus(productID: productID)
            } else {
                return
            }
            await MainActor.run { self.statuses[provider] = status }
        } catch {
            self.recordStartupConnectivityRetryableFailure(error)
            // Keep the previous status to avoid flapping when the API hiccups.
            await MainActor.run {
                if self.statuses[provider] == nil {
                    self.statuses[provider] = ProviderStatus(
                        indicator: .unknown,
                        description: error.localizedDescription,
                        updatedAt: nil)
                }
            }
        }
    }
}

extension UsageStore {
    private func detectVersions() {
        let implementations = ProviderCatalog.all
        let browserDetection = self.browserDetection
        Task { @MainActor [weak self] in
            let resolved = await Task.detached { () -> [UsageProvider: String] in
                var resolved: [UsageProvider: String] = [:]
                await withTaskGroup(of: (UsageProvider, String?).self) { group in
                    for implementation in implementations {
                        let context = ProviderVersionContext(
                            provider: implementation.id,
                            browserDetection: browserDetection)
                        group.addTask {
                            await (implementation.id, implementation.detectVersion(context: context))
                        }
                    }
                    for await (provider, version) in group {
                        guard let version, !version.isEmpty else { continue }
                        resolved[provider] = version
                    }
                }
                return resolved
            }.value
            self?.versions = resolved
        }
    }

    @MainActor
    private func schedulePathDebugInfoRefresh() {
        self.pathDebugRefreshTask?.cancel()
        self.pathDebugRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            await self?.refreshPathDebugInfo()
        }
    }

    private func runBackgroundSnapshot(
        _ snapshot: @escaping @Sendable () async -> PathDebugSnapshot) async
    {
        let result = await snapshot()
        await MainActor.run {
            self.pathDebugInfo = result
        }
    }

    private func refreshPathDebugInfo() async {
        await self.runBackgroundSnapshot {
            await PathBuilder.debugSnapshotAsync(purposes: [.rpc, .tty, .nodeTooling])
        }
    }

    func clearCostUsageCache() async -> String? {
        let errorMessage: String? = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let cacheDirs = [
                Self.costUsageCacheDirectory(fileManager: fm),
            ]

            for cacheDir in cacheDirs {
                do {
                    try fm.removeItem(at: cacheDir)
                } catch let error as NSError {
                    if error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError { continue }
                    return error.localizedDescription
                }
            }
            return nil
        }.value

        guard errorMessage == nil else { return errorMessage }

        self.tokenSnapshots.removeAll()
        self.tokenErrors.removeAll()
        self.lastTokenFetchAt.removeAll()
        self.lastTokenFetchScope.removeAll()
        self.tokenFailureGates[.codex]?.reset()
        self.tokenFailureGates[.claude]?.reset()
        return nil
    }

    private func refreshTokenUsage(_ provider: UsageProvider, force: Bool) async {
        guard ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.supportsTokenCost else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            self.lastTokenFetchScope.removeValue(forKey: provider)
            return
        }

        if let override = self._test_tokenUsageRefreshOverride {
            await override(provider, force)
            return
        }

        if Self.tokenCostRequiresProviderSnapshot(provider) {
            if let snapshot = self.tokenSnapshot(fromProviderSnapshot: self.snapshots[provider], provider: provider) {
                self.tokenSnapshots[provider] = snapshot
                self.tokenErrors[provider] = nil
                self.tokenFailureGates[provider]?.recordSuccess()
                self.persistWidgetSnapshot(reason: "token-usage")
            } else {
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = nil
                self.tokenFailureGates[provider]?.reset()
            }
            return
        }

        guard self.settings.costUsageEnabled else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            self.lastTokenFetchScope.removeValue(forKey: provider)
            return
        }

        guard self.isEnabled(provider) else {
            self.tokenSnapshots.removeValue(forKey: provider)
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.reset()
            self.lastTokenFetchAt.removeValue(forKey: provider)
            self.lastTokenFetchScope.removeValue(forKey: provider)
            return
        }

        guard !self.tokenRefreshInFlight.contains(provider) else { return }

        let now = Date()
        let historyDays = self.settings.costUsageHistoryDays
        let costScope = self.tokenCostScope(for: provider)
        let costScopeSignature = "\(costScope.signature)|historyDays=\(historyDays)"
        if !force,
           let last = self.lastTokenFetchAt[provider],
           self.lastTokenFetchScope[provider] == costScopeSignature,
           now.timeIntervalSince(last) < self.tokenFetchTTL
        {
            return
        }
        self.lastTokenFetchAt[provider] = now
        self.lastTokenFetchScope[provider] = costScopeSignature
        self.tokenRefreshInFlight.insert(provider)
        defer { self.tokenRefreshInFlight.remove(provider) }

        let startedAt = Date()
        let providerText = provider.rawValue
        self.tokenCostLogger
            .debug("cost usage start provider=\(providerText) force=\(force)")

        do {
            let fetcher = self.costUsageFetcher
            let timeoutSeconds = self.tokenFetchTimeout
            let environment = provider == .bedrock
                ? ProviderRegistry.makeEnvironment(
                    base: self.environmentBase,
                    provider: provider,
                    settings: self.settings,
                    tokenOverride: nil)
                : self.environmentBase
            // Codex cost usage scans local session logs from this machine. That data is
            // intentionally presented as provider-level local telemetry rather than managed-account
            // remote state, so managed Codex account selection does not retarget that fetch.
            // If the UI later needs account-scoped token history, it should label and source that
            // separately instead of silently changing the meaning of this section.
            let snapshot = try await withThrowingTaskGroup(of: CostUsageTokenSnapshot.self) { group in
                group.addTask(priority: .utility) {
                    try await fetcher.loadTokenSnapshot(
                        provider: provider,
                        environment: environment,
                        now: now,
                        forceRefresh: force,
                        allowVertexClaudeFallback: !self.isEnabled(.claude),
                        codexHomePath: costScope.codexHomePath,
                        historyDays: historyDays)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw CostUsageError.timedOut(seconds: Int(timeoutSeconds))
                }
                defer { group.cancelAll() }
                guard let snapshot = try await group.next() else { throw CancellationError() }
                return snapshot
            }

            guard !snapshot.daily.isEmpty else {
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = Self.tokenCostNoDataMessage(for: provider)
                self.tokenFailureGates[provider]?.recordSuccess()
                return
            }
            let duration = Date().timeIntervalSince(startedAt)
            let sessionCost = snapshot.sessionCostUSD
                .map { UsageFormatter.currencyString($0, currencyCode: snapshot.currencyCode) } ?? "—"
            let monthCost = snapshot.last30DaysCostUSD
                .map { UsageFormatter.currencyString($0, currencyCode: snapshot.currencyCode) } ?? "—"
            let durationText = String(format: "%.2f", duration)
            let message =
                "cost usage success provider=\(providerText) " +
                "duration=\(durationText)s " +
                "today=\(sessionCost) " +
                "historyDays=\(historyDays) windowCost=\(monthCost)"
            self.tokenCostLogger.info(message)
            self.tokenSnapshots[provider] = snapshot
            self.tokenErrors[provider] = nil
            self.tokenFailureGates[provider]?.recordSuccess()
            self.persistWidgetSnapshot(reason: "token-usage")
        } catch {
            if error is CancellationError { return }
            let duration = Date().timeIntervalSince(startedAt)
            let msg = error.localizedDescription
            let durationText = String(format: "%.2f", duration)
            let message = "cost usage failed provider=\(providerText) duration=\(durationText)s error=\(msg)"
            self.tokenCostLogger.error(message)
            let hadPriorData = self.tokenSnapshots[provider] != nil
            let shouldSurface = self.tokenFailureGates[provider]?
                .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
            if shouldSurface {
                self.tokenErrors[provider] = error.localizedDescription
                self.tokenSnapshots.removeValue(forKey: provider)
            } else {
                self.tokenErrors[provider] = nil
            }
        }
    }
}
