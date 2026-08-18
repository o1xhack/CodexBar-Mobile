// swiftlint:disable file_length type_body_length
//
// `type_body_length` bumped past the 800-line default in iOS 1.8.0
// build 134 when 5 v0.27 existing-provider mappers were added
// (claude admin + claude extra + opencodego zen + minimax billing +
// codex workspace). The class is a single-responsibility envelope
// assembler — pulling the mappers into a separate type would just
// split the dispatch logic across files without changing the
// structure. Scoped suppression matches the same pattern already
// used in MockProviderInjector. The file-length rule is paired with the
// existing type suppression because this fork-owned assembler also contains
// the protocol-specific Mac-to-iOS mappers.
import CodexBarCore
import CodexBarSync
import Foundation
import Observation

enum SyncPhase: String, Sendable {
    case idle
    case preparing
    case legacyUpload = "legacy upload"
    case providerUpload = "provider upload"
    case cleanup
    case reconciling

    var localizedLabel: String {
        switch self {
        case .idle: L("icloud_sync_phase_idle")
        case .preparing: L("icloud_sync_phase_preparing")
        case .legacyUpload: L("icloud_sync_phase_legacy_upload")
        case .providerUpload: L("icloud_sync_phase_provider_upload")
        case .cleanup: L("icloud_sync_phase_cleanup")
        case .reconciling: L("icloud_sync_phase_reconciling")
        }
    }
}

/// Observes `UsageStore` changes and pushes usage snapshots to iCloud via `CloudSyncManager`.
///
/// This class bridges the existing Mac app data to the shared iCloud layer without
/// modifying any existing source files. It uses Swift Observation to track `UsageStore.snapshots`.
@MainActor
@Observable
final class SyncCoordinator {
    private static let logger = CodexBarLog.logger(LogCategories.iCloudSync)
    private let store: UsageStore
    private let settings: SettingsStore
    private let syncManager: any SyncPushing
    private var isObserving = false

    // Observable sync status for UI
    private(set) var lastSyncTime: Date?
    private(set) var lastSyncSucceeded: Bool = true
    private(set) var lastSyncMessage: String?
    private(set) var lastFailedPhase: SyncPhase?
    private(set) var isSyncing: Bool = false
    private(set) var syncPhase: SyncPhase = .idle
    private(set) var syncStartedAt: Date?
    private(set) var lastSyncDuration: TimeInterval?
    private(set) var recentSyncEvents: [String] = []
    private var syncRequestedWhileRunning = false

    /// Stable device UUID for this Mac, persisted across app launches.
    private let deviceID: String

    /// Per-provider content-hash cache (P4). Keyed by composite
    /// `providerID|accountEmail`, value is a stable hash of the provider's
    /// encoded JSON. Used to diff incoming pushes so `pushPerProviderRecords`
    /// only uploads providers whose data actually changed.
    ///
    /// In-memory only — rebuilt on every process launch. The cost of
    /// rebuilding is one extra full upload on Mac startup, which is fine; the
    /// alternative (persisting to UserDefaults) risks the cache drifting out of
    /// sync with what's actually on CloudKit.
    private var lastProviderHashes: [String: Int] = [:]

    /// Composite recordNames pushed to `DeviceProvidersZone` last cycle.
    /// Used to detect provider-disable transitions and account-identity
    /// drift: anything in `lastPushedRecordNames` that is NOT in this
    /// cycle's set of pushed composites must be deleted from CloudKit so
    /// stale records don't accumulate.
    ///
    /// L1 ghost-records cleanup — closes the user-reported iOS-1.3.0 bug
    /// at the data layer. iOS 1.3.1's `dropOrphansAndStale` filter (Build
    /// 94) is the L2 backup that hides any ghost that does slip through.
    ///
    /// In-memory only, like `lastProviderHashes`. On Mac process restart,
    /// this set is empty: the first push cycle re-establishes the
    /// "current" composites without producing spurious deletes (we don't
    /// emit deletes on the first cycle because we don't know yet what
    /// was previously there). Subsequent cycles compare reliably.
    private var lastPushedRecordNames: Set<String> = []

    /// Tracks whether `lastPushedRecordNames` has been seeded by at least
    /// one successful push. Until that's true, we don't emit deletes —
    /// otherwise the first cycle after Mac restart would interpret the
    /// empty set as "nothing was previously enabled" and skip deletion.
    /// After the first successful push, real disabled-or-drifted
    /// composites can be detected.
    private var pushHistorySeeded: Bool = false

    /// Per-record consecutive-missing counter for the L1 ghost-records
    /// cleanup's two-cycle confirmation. Multi-account expansion may
    /// transiently shrink the emit set (Codex active-account switch race,
    /// token "Show all" toggle, etc.) and we don't want a single missing
    /// cycle to trigger a CloudKit delete. A record stays in this dict
    /// while it's missing from `currentRecordNames`; once its counter
    /// reaches 2 OR its providerID disappears entirely from the cycle's
    /// emit set (whole-provider gone, e.g. user disabled the provider),
    /// the delete fires. Counter is reset to 0 (entry removed) when the
    /// record reappears.
    ///
    /// R3 P1: see `Research/020-multi-account-comprehensive.md` H6.
    private var consecutiveMissingCount: [String: Int] = [:]

    /// Per-account snapshot cache for multi-account providers. Captures the
    /// active account's snapshot on every push so previously-active accounts
    /// remain visible on iOS as the user switches between them. Solves the
    /// "3 Codex accounts on Mac, only 1 shows on iOS" issue without touching
    /// upstream's account-scoped refresh machinery. See
    /// `Research/020-multi-account-comprehensive.md` and
    /// `SyncMultiAccountSnapshotCache.swift`.
    private let multiAccountCache = SyncMultiAccountSnapshotCache()

    /// Stable encoder used for the per-provider diff. Sorted keys so byte-level
    /// hashing is insensitive to encoding key order. Built on top of the
    /// project-wide factory so date strategy stays consistent.
    private let providerDiffEncoder: JSONEncoder = {
        let e = CloudSyncConstants.makeJSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    /// Optional injector for synthetic mock provider data (debug
    /// feature). Default reads global `MockProviderInjector.isEnabled`
    /// state (env var or UserDefaults). Tests should pass a closure
    /// returning a fixed array (or empty) so they don't depend on
    /// process-global state, which doesn't isolate across parallel
    /// `@MainActor` test suites.
    private let mockInjector: @MainActor () -> [ProviderUsageSnapshot]

    /// **Default**: empty closure. The default is intentionally NOT
    /// `MockProviderInjector.injectedSnapshots()` so test suites that
    /// don't care about mock injection never accidentally pick it up
    /// from process-global UserDefaults — preserving cross-suite test
    /// isolation. Production callers (`CodexbarApp.swift`) pass an
    /// explicit closure that delegates to `MockProviderInjector` so the
    /// debug feature still activates via env var or `defaults write` in
    /// the real app. Tests that exercise mock activation pass
    /// `{ MockProviderInjector.allMocks() }` to bypass the global
    /// activation check entirely.
    init(
        store: UsageStore,
        settings: SettingsStore,
        syncManager: any SyncPushing = CloudSyncManager.shared,
        mockInjector: @escaping @MainActor () -> [ProviderUsageSnapshot] = { [] })
    {
        self.store = store
        self.settings = settings
        self.syncManager = syncManager
        self.mockInjector = mockInjector
        self.deviceID = Self.stableDeviceID()
    }

    /// Starts observing `UsageStore` snapshot changes.
    /// Each time the snapshots dictionary changes, a new `SyncedUsageSnapshot` is pushed to iCloud.
    func startObserving() {
        guard !self.isObserving else { return }
        self.isObserving = true
        // Reconcile lastPushedRecordNames with CloudKit's actual state for
        // this device, so L1 cleanup can detect records pushed by previous
        // Mac process incarnations (mock toggle off → restart Mac scenario).
        // Fire-and-forget — observeLoop runs immediately after; if the
        // reconcile finishes mid-loop, the very next push cycle picks up
        // the seeded set and emits deletes for stranded records.
        Task { @MainActor [weak self] in
            await self?.reconcileLastPushedRecordNamesWithCloudKit()
        }
        self.observeLoop()
    }

    /// One-shot startup reconcile. Replaces the in-memory empty
    /// `lastPushedRecordNames` with whatever CloudKit reports for this
    /// device, then flips `pushHistorySeeded = true` so the next push
    /// cycle's diff is meaningful.
    ///
    /// Why this matters: pre-fix, `lastPushedRecordNames` was in-memory
    /// only, which meant L1 ghost-records cleanup couldn't see records
    /// pushed by previous Mac process incarnations. The classic failure
    /// mode is: user toggles mocks off on Mac, restarts Mac (or Mac was
    /// already restarted between mocks-on and mocks-off), the new Mac
    /// process never knew about the stranded mock records, and they
    /// surfaced on iOS forever. Discovered 2026-05-05 user QA.
    private func reconcileLastPushedRecordNamesWithCloudKit() async {
        guard self.settings.iCloudSyncEnabled else { return }
        let ownsPhase = !self.isSyncing
        if ownsPhase { self.syncPhase = .reconciling }
        let result = await self.syncManager
            .fetchPerProviderRecordNames(forDeviceID: self.deviceID)
        guard case let .success(recordNames) = result else {
            if case let .failure(message) = result {
                self.recordSyncEvent("Startup reconcile failed: \(message)", isError: true)
            }
            if ownsPhase, !self.isSyncing { self.syncPhase = .idle }
            return
        }
        // If the in-memory set has already been seeded by a push that
        // ran before the reconcile completed, merge rather than replace —
        // CloudKit's view of the world plus anything we've already pushed
        // this session covers all candidates the next L1 diff should see.
        self.lastPushedRecordNames = self.lastPushedRecordNames.union(recordNames)
        self.pushHistorySeeded = true
        self.recordSyncEvent(
            "Startup reconcile found \(recordNames.count) provider record(s)")
        if ownsPhase, !self.isSyncing { self.syncPhase = .idle }
    }

    private func observeLoop() {
        withObservationTracking {
            _ = self.store.snapshots
            _ = self.store.errors
            _ = self.store.tokenSnapshots
            _ = self.settings.iCloudSyncEnabled
            // Multi-account: re-push when the active Codex managed account
            // changes (user switches accounts in menu) so the new active
            // account's data lands on iOS quickly. The previously-active
            // account's snapshot is preserved in `multiAccountCache`.
            _ = self.settings.codexAccountReconciliationSnapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObserving else { return }
                // Re-arm before awaiting CloudKit. Otherwise changes that
                // arrive during a long write are invisible and cannot set the
                // single-flight pending flag for one newest-state follow-up.
                self.observeLoop()
                await self.pushCurrentSnapshot()
            }
        }
    }

    /// Builds and pushes the current state to iCloud.
    func pushCurrentSnapshot() async {
        guard self.settings.iCloudSyncEnabled else { return }
        self.syncRequestedWhileRunning = true
        guard !self.isSyncing else {
            self.recordSyncEvent("Queued a newer snapshot while sync was running")
            return
        }

        self.isSyncing = true
        self.syncStartedAt = Date()
        self.recordSyncEvent("Sync started")
        defer {
            if let started = self.syncStartedAt {
                self.lastSyncDuration = Date().timeIntervalSince(started)
                self.recordSyncEvent(
                    "Sync attempt ended after "
                        + String(format: "%.1f seconds", self.lastSyncDuration ?? 0))
            }
            self.syncStartedAt = nil
            self.syncPhase = .idle
            self.isSyncing = false
            self.syncRequestedWhileRunning = false
        }

        // Bound each flight to the initial write plus one newest-state catch-up.
        // A failed write must end the flight immediately: otherwise periodic
        // UsageStore changes can keep setting the pending flag while CloudKit
        // repeatedly times out, leaving Settings stuck on "Syncing" forever.
        var pushesRemaining = 2
        while pushesRemaining > 0 {
            self.syncRequestedWhileRunning = false
            let succeeded = await self.performPushCurrentSnapshot()
            pushesRemaining -= 1

            guard succeeded else { return }
            guard self.syncRequestedWhileRunning,
                  self.settings.iCloudSyncEnabled
            else { return }

            if pushesRemaining > 0 {
                self.recordSyncEvent("Running one coalesced newer snapshot")
            }
        }

        if self.syncRequestedWhileRunning {
            self.recordSyncEvent(
                "A newer snapshot arrived during catch-up; scheduled as a new sync")
            Task { @MainActor [weak self] in
                // Let this bounded flight run its defer first so the next one
                // starts with a fresh duration and visible idle transition.
                await Task.yield()
                await self?.pushCurrentSnapshot()
            }
        }
    }

    private func performPushCurrentSnapshot() async -> Bool {
        guard self.settings.iCloudSyncEnabled else { return false }

        let enabledProviders = self.store.enabledProviders()
        guard !enabledProviders.isEmpty else { return true }
        self.syncPhase = .preparing

        var providerSnapshots: [ProviderUsageSnapshot] = []

        for instanceID in enabledProviders {
            let snapshot = self.store.snapshots[instanceID]
            let error = self.store.errors[instanceID]

            guard let provider = instanceID.firstPartyProvider else {
                providerSnapshots.append(self.buildPluginProviderUsageSnapshot(
                    instanceID: instanceID,
                    snapshot: snapshot,
                    error: error))
                continue
            }
            let meta = self.store.providerMetadata[provider]

            // Per-provider shared data (computed once, reused across all
            // account snapshots for this provider during multi-account
            // expansion). Cost JSONL scanner and utilization history are
            // currently provider-level (not split per account); future
            // refinement (R5+) may push these per-account when the data
            // source allows.
            let sharedCostSummary = self.makeCostSummary(for: provider)
            let sharedUtilizationHistory = self.makeUtilizationHistory(for: provider)
            if let uh = sharedUtilizationHistory {
                let totalEntries = uh.reduce(0) { $0 + $1.entries.count }
                print("[CodexBar Sync] \(provider.rawValue): \(uh.count) utilization series, \(totalEntries) entries")
            } else {
                print("[CodexBar Sync] \(provider.rawValue): no utilization history")
            }

            let providerSnapshot = self.buildProviderUsageSnapshot(
                for: provider,
                snapshot: snapshot,
                error: error,
                metadata: meta,
                sharedCostSummary: sharedCostSummary,
                sharedUtilizationHistory: sharedUtilizationHistory,
                accountRecordKey: self.settings.effectiveSelectedTokenAccount(for: provider)
                    .map(Self.tokenAccountRecordKey))

            providerSnapshots.append(providerSnapshot)
        }

        // Multi-account capture + expand. Records the active account's
        // freshly-built snapshot into `multiAccountCache`, then appends every
        // cached non-active snapshot for that provider to `providerSnapshots`
        // so the push covers all known accounts. iOS merges by
        // (providerID, accountEmail), so distinct emails produce distinct
        // cards. See `SyncMultiAccountSnapshotCache.swift` for rationale.
        let enabledSet = Set(enabledProviders.compactMap(\.firstPartyProvider))
        self.captureAndExpandMultiAccountSnapshots(
            into: &providerSnapshots, enabledSet: enabledSet)

        // Mock provider injection (debug-only). Append synthetic
        // ProviderUsageSnapshot entries when the injector closure
        // returns non-empty. Default closure reads
        // `MockProviderInjector.isEnabled` (env var / UserDefaults).
        // Tests inject a fixed closure to avoid process-global state
        // leaking across parallel suites.
        let mockSnapshots = self.mockInjector()
        if !mockSnapshots.isEmpty {
            providerSnapshots.append(contentsOf: mockSnapshots)
        }
        let deviceName = Host.current().localizedName ?? "Mac"
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let mobileVersion = Bundle.main.object(forInfoDictionaryKey: "CodexMobileVersion") as? String
        let synced = SyncedUsageSnapshot(
            providers: providerSnapshots,
            syncTimestamp: Date(),
            deviceName: deviceName,
            deviceID: self.deviceID,
            appVersion: appVersion,
            mobileVersion: mobileVersion)

        self.syncPhase = .legacyUpload
        let legacyResult = await self.syncManager.pushSnapshot(synced)

        // P4: additive per-provider write to DeviceProvidersZone. Diff against
        // the in-memory hash cache so unchanged providers are skipped. Failure
        // here is logged but does NOT override `lastSyncSucceeded` — the
        // legacy-zone write is still authoritative while iOS readers haven't
        // migrated yet (see Research/010). A failure is now surfaced as the
        // overall attempt result so Settings cannot show a false green state.
        let (envelopes, hashUpdates) = self.buildPerProviderDelta(
            from: providerSnapshots, synced: synced)
        self.syncPhase = .providerUpload
        if !envelopes.isEmpty {
            let perProviderResult =
                await self.syncManager.pushPerProviderRecords(envelopes)
            if perProviderResult.succeeded {
                for (key, hash) in hashUpdates {
                    self.lastProviderHashes[key] = hash
                }
            } else {
                let message = perProviderResult.message ?? "Unknown provider upload failure"
                self.finishSyncAttempt(succeeded: false, message: message)
                self.recordSyncEvent("Provider upload failed: \(message)", isError: true)
                return false
            }
        }

        // L1 ghost-records cleanup. Compute the composites we just pushed
        // (i.e. all currently-enabled, non-ghost providers regardless of
        // whether their hash changed this cycle) vs the composites we
        // pushed last cycle. The difference represents:
        //   (a) providers the user disabled — Mac stopped including them
        //       (whole-provider gone → 1-cycle delete: matches existing
        //       L1 contract)
        //   (b) accounts whose identity drifted (composite key changed)
        //   (c) accounts that disappeared from a multi-account provider
        //       (partial shrink → 2-cycle confirmation: defends against
        //       transient cache shrinkage during Codex active-account
        //       switch invalidation race; see Research/020 H6)
        // First-cycle-after-restart guard: don't emit deletes until
        // `pushHistorySeeded == true`; otherwise we'd interpret the empty
        // initial set as "nothing was enabled" and miss real disable events
        // that happened before this Mac session started — but more
        // importantly we'd issue spurious deletes for anything iOS already
        // sees from previous Mac sessions, since we don't yet know what
        // composites are truly current.
        let currentRecordNames = self.computeCurrentRecordNames(
            from: providerSnapshots)
        self.syncPhase = .cleanup
        if self.pushHistorySeeded {
            let staleRecordNames = self.computeStaleRecordNames(
                currentRecordNames: currentRecordNames)
            if !staleRecordNames.isEmpty {
                let deleteResult = await self.syncManager
                    .deletePerProviderRecords(recordNames: Array(staleRecordNames))
                if deleteResult.succeeded {
                    for record in staleRecordNames {
                        self.consecutiveMissingCount.removeValue(forKey: record)
                    }
                    print(
                        "[CodexBar Sync] cleaned up \(staleRecordNames.count)" +
                            " stale per-provider record(s) from CloudKit")
                } else {
                    let message = deleteResult.message ?? "Unknown stale-record cleanup failure"
                    self.finishSyncAttempt(succeeded: false, message: message)
                    self.recordSyncEvent("Cleanup failed: \(message)", isError: true)
                    // Don't update lastPushedRecordNames if delete failed —
                    // retry next cycle.
                    return false
                }
            }
        }
        self.lastPushedRecordNames = currentRecordNames
        self.pushHistorySeeded = true
        self.finishSyncAttempt(
            succeeded: legacyResult.succeeded,
            message: legacyResult.message,
            failurePhase: .legacyUpload)
        if legacyResult.succeeded {
            self.recordSyncEvent("Sync completed")
        } else {
            self.recordSyncEvent(
                "Legacy upload failed: \(legacyResult.message ?? "Unknown error")",
                isError: true)
        }
        return legacyResult.succeeded
    }

    private func finishSyncAttempt(
        succeeded: Bool,
        message: String?,
        failurePhase: SyncPhase? = nil)
    {
        self.lastSyncTime = Date()
        self.lastSyncSucceeded = succeeded
        self.lastSyncMessage = message
        self.lastFailedPhase = succeeded ? nil : (failurePhase ?? self.syncPhase)
    }

    private func recordSyncEvent(_ message: String, isError: Bool = false) {
        let line = "\(Date().formatted(.iso8601)) [\(self.syncPhase.rawValue)] \(message)"
        self.recentSyncEvents.append(line)
        if self.recentSyncEvents.count > 30 {
            self.recentSyncEvents.removeFirst(self.recentSyncEvents.count - 30)
        }
        if isError {
            Self.logger.error(message, metadata: ["phase": self.syncPhase.rawValue])
        } else {
            Self.logger.info(message, metadata: ["phase": self.syncPhase.rawValue])
        }
    }

    var syncDiagnosticText: String {
        let status = self.isSyncing ? "syncing" : (self.lastSyncSucceeded ? "success" : "failure")
        let duration = self.lastSyncDuration.map { String(format: "%.1fs", $0) } ?? "n/a"
        let lastSync = self.lastSyncTime?.formatted(.iso8601) ?? "never"
        let message = self.lastSyncMessage ?? "none"
        let events = self.recentSyncEvents.isEmpty ? "none" : self.recentSyncEvents.joined(separator: "\n")
        return """
        CodexBar iCloud Sync Diagnostics
        Status: \(status)
        Phase: \(self.syncPhase.rawValue)
        Last sync: \(lastSync)
        Last duration: \(duration)
        Message: \(message)
        File log: \(CodexBarLog.fileLogURL.path)

        Recent events:
        \(events)
        """
    }

    /// Determine which records must be deleted from CloudKit this cycle.
    ///
    /// Three delete paths:
    /// 1. **Whole-provider gone (1-cycle)** — the record's providerID is
    ///    no longer present anywhere in `currentRecordNames`. Matches
    ///    "user disabled provider" contract.
    /// 2. **Account-identity drift (1-cycle)** — count of composites for
    ///    this providerID stayed the same OR grew, but a specific record
    ///    disappeared. That's a 1-1 swap (e.g., email changed when login
    ///    completed) or a growth (drift + add) — not a real shrink, safe
    ///    to delete the old composite immediately. Matches the existing
    ///    L1 drift test.
    /// 3. **Real shrink (2-cycle)** — count of composites for the
    ///    providerID actually decreased. Could be a real account
    ///    removal OR a transient cache shrinkage (Codex active-account
    ///    switch race, etc.). Require the record to be missing for 2
    ///    consecutive cycles before deletion (R3 P1, Research/020 H6).
    ///
    /// Side effect: maintains `consecutiveMissingCount` — increments for
    /// records still missing this cycle, removes for records that
    /// reappeared.
    private func computeStaleRecordNames(
        currentRecordNames: Set<String>) -> Set<String>
    {
        // Records currently emitted: reset their missing counter.
        for record in currentRecordNames {
            self.consecutiveMissingCount.removeValue(forKey: record)
        }

        // Records that were emitted last cycle OR are still in the
        // missing-counter dict from earlier cycles, but are missing now.
        let trackedRecords = self.lastPushedRecordNames
            .union(self.consecutiveMissingCount.keys)
        let missingThisCycle = trackedRecords.subtracting(currentRecordNames)

        // Increment missing counter for each.
        for record in missingThisCycle {
            self.consecutiveMissingCount[record, default: 0] += 1
        }

        // Per-providerID composite counts (last vs. current) — drives the
        // drift-vs-shrink distinction.
        let lastCountsByProvider = Self.composeCountsByProvider(
            from: self.lastPushedRecordNames)
        let currentCountsByProvider = Self.composeCountsByProvider(
            from: currentRecordNames)

        var stale: Set<String> = []
        for record in missingThisCycle {
            guard let providerID = Self.extractProviderID(from: record)
            else {
                // Can't parse — conservative: don't delete.
                continue
            }
            let currentCount = currentCountsByProvider[providerID] ?? 0
            let lastCount = lastCountsByProvider[providerID] ?? 0

            if currentCount == 0 {
                // Whole-provider gone — 1-cycle delete.
                stale.insert(record)
            } else if currentCount >= lastCount {
                // Drift (composite swapped or new added while old removed)
                // — 1-cycle delete is safe and matches existing L1 contract.
                stale.insert(record)
            } else if (self.consecutiveMissingCount[record] ?? 0) >= 2 {
                // Real shrink (count decreased) — confirmed missing for
                // 2 consecutive cycles → delete.
                stale.insert(record)
            }
            // Else: real shrink, only 1 cycle missing — wait for
            // confirmation next cycle (defends against transient cache
            // shrinkage from Codex active-account switch race).
        }
        return stale
    }

    /// Builds `[providerID: count]` for the given record names. Records
    /// with unparseable composite keys contribute to no provider.
    private static func composeCountsByProvider(
        from recordNames: Set<String>) -> [String: Int]
    {
        var counts: [String: Int] = [:]
        for record in recordNames {
            guard let providerID = Self.extractProviderID(from: record)
            else { continue }
            counts[providerID, default: 0] += 1
        }
        return counts
    }

    /// Extracts `providerID` from a per-provider record name composite
    /// `{deviceID}|{providerID}|{accountEmailOrSentinel}`. Returns nil if
    /// the format is unexpected; callers must treat that as "unknown" and
    /// not act on the record.
    private static func extractProviderID(from recordName: String) -> String? {
        let parts = recordName.split(
            separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        return String(parts[1])
    }

    /// Token-based providers that share `UsageStore.accountSnapshots` for
    /// multi-account data. When `showAllTokenAccountsInMenu` is on **and**
    /// the user has 2+ token accounts configured, each provider's
    /// `accountSnapshots[provider]` array is populated with every account's
    /// usage; SyncCoordinator emits one CKRecord per entry.
    ///
    /// Identical pattern to Codex (R1) but with one important difference:
    /// for token providers the per-account data is **co-resident in memory**
    /// once the user enables "Show all" — unlike Codex which only ever
    /// retains the active account's snapshot. As a result we don't need
    /// observation-cache cold-start mitigation here; we read the live list
    /// and emit immediately.
    ///
    /// **Source of truth** is `TokenAccountSupportCatalog.allProviders`
    /// (Phase G fix — previously this list was hardcoded and drifted
    /// behind upstream catalog updates by 7 providers: openai, deepseek,
    /// antigravity, manus, copilot, venice, stepfun). Reading the catalog
    /// directly means any future upstream-added token provider is
    /// automatically picked up; `TokenAccountSyncCoverageTests` enforces
    /// the equality so a drift fails the build.
    private static var tokenBasedMultiAccountProviders: [UsageProvider] {
        TokenAccountSupportCatalog.allProviders
    }

    /// Testing-only mirror of `tokenBasedMultiAccountProviders` — same
    /// value, package-internal access for `TokenAccountSyncCoverageTests`.
    /// Production code should use the private accessor above.
    static var tokenBasedMultiAccountProvidersForTesting: [UsageProvider] {
        tokenBasedMultiAccountProviders
    }

    // swiftlint:disable function_parameter_count
    /// Builds a `ProviderUsageSnapshot` from a `UsageSnapshot` plus shared
    /// per-provider data (cost / utilization). Pure function over inputs —
    /// used by both the active-account main loop and the multi-account
    /// expansion path. Extraction made multi-account expansion possible
    /// without code duplication; see R2 in
    /// `Research/020-multi-account-comprehensive.md`.
    /// Threads the Antigravity Google-OAuth account list into the wire envelope
    /// (gap B). iOS already ships the `AntigravityAccountSwitcher` renderer
    /// (gated on > 1 account); this populates the field the construction-site
    /// TODO left as nil since iOS 1.7.0. Built from the configured token
    /// accounts — `label` is the display email, and `ProviderTokenAccount`
    /// carries no token-expiry so `expiresAt` is nil. Emitted only for > 1
    /// account, matching the iOS switcher's display condition.
    private func mapAntigravityAccounts(provider: UsageProvider) -> SyncMultiAccountList? {
        guard provider == .antigravity,
              let data = self.settings.tokenAccountsData(for: .antigravity),
              data.accounts.count > 1
        else { return nil }
        let activeIndex = data.clampedActiveIndex()
        let entries = data.accounts.enumerated().map { index, account in
            SyncMultiAccountEntry(
                email: account.label,
                isActive: index == activeIndex,
                expiresAt: nil)
        }
        return SyncMultiAccountList(accounts: entries, activeIndex: activeIndex)
    }

    private static func mapCodexResetCredits(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncCodexResetCredits?
    {
        guard provider == .codex,
              let resetCredits = snapshot?.codexResetCredits
        else { return nil }

        return SyncCodexResetCredits(
            availableCount: resetCredits.availableCount,
            nextExpiresAt: resetCredits.nextExpiringAvailableCredit?.expiresAt,
            credits: resetCredits.credits.map { credit in
                SyncCodexResetCredit(
                    id: credit.id,
                    resetType: credit.resetType,
                    status: credit.status.rawValue,
                    grantedAt: credit.grantedAt,
                    expiresAt: credit.expiresAt,
                    redeemStartedAt: credit.redeemStartedAt,
                    redeemedAt: credit.redeemedAt,
                    title: credit.title,
                    detail: credit.description)
            },
            updatedAt: resetCredits.updatedAt)
    }

    private static func mapUsageDataConfidence(snapshot: UsageSnapshot?) -> String? {
        guard let confidence = snapshot?.dataConfidence, confidence != .unknown else {
            return nil
        }
        return confidence.rawValue
    }

    private static func syncRateWindow(
        id: String?,
        label: String?,
        window: RateWindow,
        usageKnown: Bool = true) -> SyncRateWindow
    {
        SyncRateWindow(
            id: id,
            label: label,
            usedPercent: window.usedPercent,
            usageKnown: usageKnown,
            windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt,
            resetDescription: window.resetDescription,
            nextRegenPercent: window.nextRegenPercent,
            isSyntheticPlaceholder: window.isSyntheticPlaceholder)
    }

    static func mapDetails(_ sections: [ProviderDetailSection]) -> [SyncProviderDetailSection] {
        sections.map { section in
            let chart = section.chart.map { chart in
                let kind: SyncProviderDetailSection.Chart.Kind = switch chart.kind {
                case .bars: .bars
                case .line: .line
                }
                return SyncProviderDetailSection.Chart(
                    kind: kind,
                    title: chart.title,
                    unit: chart.unit,
                    points: chart.points.map {
                        SyncProviderDetailSection.Chart.Point(label: $0.label, value: $0.value)
                    })
            }
            return SyncProviderDetailSection(
                title: section.title,
                rows: section.rows.map {
                    SyncProviderDetailSection.Row(
                        label: $0.label,
                        value: $0.value,
                        secondaryValue: $0.secondaryValue)
                },
                chart: chart)
        }
    }

    private func buildPluginProviderUsageSnapshot(
        instanceID: ProviderInstanceID,
        snapshot: UsageSnapshot?,
        error: String?) -> ProviderUsageSnapshot
    {
        Self.mapPluginProviderUsageSnapshot(
            instanceID: instanceID,
            snapshot: snapshot,
            error: error,
            deviceID: self.deviceID,
            plugin: UserProviderPluginRegistry.plugin(for: instanceID))
    }

    static func mapPluginProviderUsageSnapshot(
        instanceID: ProviderInstanceID,
        snapshot: UsageSnapshot?,
        error: String?,
        deviceID: String,
        plugin: UserProviderPlugin? = nil) -> ProviderUsageSnapshot
    {
        var rateWindows: [SyncRateWindow] = []
        if let window = snapshot?.primary {
            rateWindows.append(Self.syncRateWindow(
                id: "primary",
                label: Self.additionalWindowLabel(windowMinutes: window.windowMinutes),
                window: window))
        }
        if let window = snapshot?.secondary {
            rateWindows.append(Self.syncRateWindow(
                id: "secondary",
                label: Self.additionalWindowLabel(windowMinutes: window.windowMinutes),
                window: window))
        }
        if let window = snapshot?.tertiary {
            rateWindows.append(Self.syncRateWindow(
                id: "tertiary",
                label: Self.additionalWindowLabel(windowMinutes: window.windowMinutes),
                window: window))
        }
        for extra in snapshot?.extraRateWindows ?? [] {
            rateWindows.append(Self.syncRateWindow(
                id: extra.id,
                label: extra.title,
                window: extra.window,
                usageKnown: extra.usageKnown))
        }

        let providerCost = snapshot?.providerCost
        let budget: SyncBudgetSnapshot? = providerCost.flatMap { cost in
            guard cost.limit > 0 else { return nil }
            return SyncBudgetSnapshot(
                usedAmount: cost.used,
                limitAmount: cost.limit,
                currencyCode: cost.currencyCode,
                period: cost.period,
                resetsAt: cost.resetsAt)
        }
        let providerAmount: SyncProviderAmount? = providerCost.flatMap { cost in
            let kind: String
            let amount: Double
            if let balance = cost.balance {
                kind = "balance"
                amount = balance
            } else {
                guard cost.limit <= 0 else { return nil }
                kind = "spend"
                amount = cost.used
            }
            let confidence = snapshot?.dataConfidence ?? .unknown
            return SyncProviderAmount(
                kind: kind,
                amount: amount,
                currencyCode: cost.currencyCode,
                period: cost.period,
                isEstimated: confidence == .estimated || confidence == .percentOnly)
        }

        let accountRecordKey = "device-\(deviceID.lowercased())"
        let accountIdentities: [String] = {
            let recordIdentity = "\(instanceID.rawValue):record:\(accountRecordKey)"
            if let accountID = AccountIdentityComputer.normalize(snapshot?.identity?.accountID) {
                return ["\(instanceID.rawValue):account:\(accountID)", recordIdentity]
            }
            if snapshot?.identity?.accountEmailIsFallbackLabel != true,
               let email = AccountIdentityComputer.normalize(snapshot?.identity?.accountEmail)
            {
                return ["\(instanceID.rawValue):email:\(email)", recordIdentity]
            }
            return [recordIdentity]
        }()
        return ProviderUsageSnapshot(
            providerID: instanceID.rawValue,
            providerName: plugin?.manifest.name ?? instanceID.rawValue,
            primary: rateWindows.first,
            secondary: rateWindows.dropFirst().first,
            accountEmail: snapshot?.identity?.accountEmail,
            loginMethod: snapshot?.identity?.loginMethod,
            statusMessage: error,
            isError: error != nil,
            lastUpdated: snapshot?.updatedAt ?? Date(),
            budget: budget,
            subscriptionExpiresAt: snapshot?.subscriptionExpiresAt,
            subscriptionRenewsAt: snapshot?.subscriptionRenewsAt,
            rateWindows: rateWindows,
            accountIdentities: accountIdentities,
            usageDataConfidence: Self.mapUsageDataConfidence(snapshot: snapshot),
            providerAmount: providerAmount,
            accountRecordKey: accountRecordKey,
            accountOrganization: snapshot?.identity?.accountOrganization,
            details: Self.mapDetails(snapshot?.details ?? []),
            providerIconMonogram: plugin?.manifest.icon.monogram,
            providerIconTintHex: plugin?.manifest.icon.tint)
    }

    // swiftlint:disable:next function_body_length
    private func buildProviderUsageSnapshot(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        error: String?,
        metadata: ProviderMetadata?,
        sharedCostSummary: SyncCostSummary?,
        sharedUtilizationHistory: [SyncUtilizationSeries]?,
        accountRecordKey requestedAccountRecordKey: String? = nil) -> ProviderUsageSnapshot
    {
        // Build dynamic rate windows array with labels from metadata.
        var rateWindows: [SyncRateWindow] = []
        var semanticWindows: (primary: SyncRateWindow?, secondary: SyncRateWindow?) = (nil, nil)
        if let p = snapshot?.primary {
            let label: String? = if provider == .alibabatokenplan {
                AlibabaTokenPlanProviderDescriptor.rateWindowLabel(
                    window: p,
                    fallback: metadata?.sessionLabel ?? "Credits")
            } else if provider == .grok {
                GrokProviderDescriptor.displayLabel(window: p) ?? metadata?.sessionLabel
            } else {
                metadata?.sessionLabel
            }
            let window = Self.syncRateWindow(id: "primary", label: label, window: p)
            rateWindows.append(window)
            semanticWindows.primary = window
        }
        if let s = snapshot?.secondary {
            let label = provider == .alibabatokenplan
                ? AlibabaTokenPlanProviderDescriptor.rateWindowLabel(
                    window: s,
                    fallback: metadata?.weeklyLabel ?? "Usage")
                : metadata?.weeklyLabel
            let window = Self.syncRateWindow(id: "secondary", label: label, window: s)
            rateWindows.append(window)
            semanticWindows.secondary = window
        }
        if let t = snapshot?.tertiary {
            let label: String? = if provider == .alibabatokenplan {
                AlibabaTokenPlanProviderDescriptor.rateWindowLabel(
                    window: t,
                    fallback: "Credits")
            } else if let metadata, metadata.supportsOpus {
                metadata.opusLabel ?? "Sonnet"
            } else {
                Self.additionalWindowLabel(windowMinutes: t.windowMinutes)
            }
            rateWindows.append(Self.syncRateWindow(id: "tertiary", label: label, window: t))
        }
        // Extra (named) rate windows from upstream — Claude Designs / Daily
        // Routines / Web Sonnet, Cursor Extra usage, etc.
        for extra in snapshot?.extraRateWindows ?? [] {
            rateWindows.append(Self.syncRateWindow(
                id: extra.id,
                label: extra.title,
                window: extra.window,
                usageKnown: extra.usageKnown))
        }

        // Legacy primary/secondary for backward compat with older iOS builds.
        let primaryWindow = provider == .alibabatokenplan ? semanticWindows.primary : rateWindows.first
        let secondaryWindow = provider == .alibabatokenplan ? semanticWindows.secondary : rateWindows.dropFirst().first

        // Provider budget / spend (per-account when snapshot.providerCost is
        // set per-account by upstream; otherwise shared with active).
        let providerCost = snapshot?.providerCost
        let budgetSnap: SyncBudgetSnapshot? = providerCost.flatMap { pc in
            guard pc.limit > 0 else { return nil }
            return SyncBudgetSnapshot(
                usedAmount: pc.used,
                limitAmount: pc.limit,
                currencyCode: pc.currencyCode,
                period: pc.period,
                resetsAt: pc.resetsAt)
        }

        // Perplexity rich structured credit breakdown (only for Perplexity).
        let perplexityCredits: SyncPerplexityCreditSummary? = {
            guard provider == .perplexity,
                  let p = snapshot?.perplexityUsage
            else { return nil }
            return SyncPerplexityCreditSummary(
                recurringTotalCents: p.recurringTotal > 0 ? p.recurringTotal : nil,
                recurringUsedCents: p.recurringTotal > 0 ? p.recurringUsed : nil,
                promoTotalCents: p.promoTotal > 0 ? p.promoTotal : nil,
                promoUsedCents: p.promoTotal > 0 ? p.promoUsed : nil,
                promoExpiresAt: p.promoExpiration,
                purchasedTotalCents: p.purchasedTotal > 0 ? p.purchasedTotal : nil,
                purchasedUsedCents: p.purchasedTotal > 0 ? p.purchasedUsed : nil,
                renewalAt: p.renewalDate,
                planName: p.planName,
                balanceCents: p.balanceCents)
        }()

        // Per-account stable identifier set for cross-Mac union-find merging.
        // See `Research/019-account-identity-multi-version-merge.md`.
        let accountRecordKey = provider == .wayfinder
            ? "device-\(self.deviceID.lowercased())"
            : requestedAccountRecordKey
        let accountIdentities = Self.syncAccountIdentities(
            provider: provider,
            identity: snapshot?.identity,
            accountRecordKey: accountRecordKey)

        // iOS 1.7.0 / Mac 0.26.2 — v0.26 envelope extensions. Populated
        // only for the relevant providerID so iOS can dispatch via
        // `let dashboard = snapshot.openAIAPIDashboard { ... }`.
        let openAIAPIDashboard = Self.mapOpenAIAPIDashboard(provider: provider, snapshot: snapshot)
        let zaiHourlyUsage = Self.mapZaiHourlyUsage(provider: provider, snapshot: snapshot)
        let kiroCredits = Self.mapKiroCredits(provider: provider, snapshot: snapshot)
        // Bedrock region lives in `SettingsStore.bedrockRegion`, NOT in
        // the upstream `UsageSnapshot` (the BedrockUsageSnapshot.region
        // field is dropped when toUsageSnapshot() flattens it). Read
        // settings directly so iOS gets the actual AWS region, not the
        // composite display string in `loginMethod`.
        let bedrockRegion: String? = provider == .bedrock ? {
            let value = self.settings.bedrockRegion
            return value.isEmpty ? nil : value
        }() : nil
        let bedrockCost = Self.mapBedrockCost(
            provider: provider,
            snapshot: snapshot,
            providerCost: providerCost,
            region: bedrockRegion)
        let moonshotBalance = Self.mapMoonshotBalance(
            provider: provider,
            snapshot: snapshot,
            primaryWindow: primaryWindow)

        // iOS 1.8.0 / Mac 0.27.0 — v0.27 envelope extensions. Populated
        // only for the matching provider so iOS can dispatch via
        // `if let billing = snapshot.grokBilling { ... }` etc.
        let grokBilling = Self.mapGrokBilling(provider: provider, snapshot: snapshot)
        let elevenLabsCredits = Self.mapElevenLabsCredits(provider: provider, snapshot: snapshot)
        let deepgramUsage = Self.mapDeepgramUsage(provider: provider, snapshot: snapshot)
        let groqMetrics = Self.mapGroqMetrics(provider: provider, snapshot: snapshot)
        let llmProxyStats = Self.mapLLMProxyStats(provider: provider, snapshot: snapshot)

        // iOS 1.8.0 build 134 — v0.27 existing-provider extensions.
        // `mapClaudeAdminUsage` covers Anthropic Admin API spend tile.
        // `mapClaudeExtraUsage` heuristically detects Web spend-limit
        // accounts; OAuth flows still surface via primary RateWindow.
        // `mapOpenCodeGoZenBalance` parses Zen workspace balance from
        // the existing providerCost lane. `mapMiniMaxBilling` ships
        // the 30-day chart from `MiniMaxUsageSnapshot.billingSummary`.
        // `mapCodexWorkspace` reads active-account workspace metadata
        // from `SettingsStore.codexAccountReconciliationSnapshot` and
        // computes weekly pace via `UsagePace.weekly(window:)`.
        let claudeAdminUsage = Self.mapClaudeAdminUsage(provider: provider, snapshot: snapshot)
        let claudeExtraUsage = Self.mapClaudeExtraUsage(
            provider: provider,
            snapshot: snapshot,
            providerCost: providerCost)
        let openCodeGoWorkspaceID: String? = provider == .opencodego ? {
            let value = self.settings.opencodegoWorkspaceID
            return value.isEmpty ? nil : value
        }() : nil
        let openCodeGoZenBalance = Self.mapOpenCodeGoZenBalance(
            provider: provider,
            snapshot: snapshot,
            providerCost: providerCost,
            workspaceID: openCodeGoWorkspaceID)
        let minimaxBilling = Self.mapMiniMaxBilling(provider: provider, snapshot: snapshot)
        let codexWorkspace = self.mapCodexWorkspace(provider: provider, snapshot: snapshot)
        let codexResetCredits = Self.mapCodexResetCredits(provider: provider, snapshot: snapshot)
        let wayfinderUsage = Self.mapWayfinderUsage(provider: provider, snapshot: snapshot)
        let sub2APIUsage = Self.mapSub2APIUsage(provider: provider, snapshot: snapshot)
        let zoomMateCredits = Self.mapZoomMateCredits(provider: provider, snapshot: snapshot)
        let providerAmount = Self.mapProviderAmount(
            provider: provider,
            snapshot: snapshot,
            providerCost: providerCost)
        return ProviderUsageSnapshot(
            providerID: provider.rawValue,
            providerName: metadata?.displayName ?? provider.rawValue.capitalized,
            primary: primaryWindow,
            secondary: secondaryWindow,
            accountEmail: snapshot?.identity?.accountEmail,
            loginMethod: snapshot?.identity?.loginMethod,
            statusMessage: error,
            isError: error != nil,
            lastUpdated: snapshot?.updatedAt ?? Date(),
            costSummary: sharedCostSummary
                ?? Self.mapMistralCostSummary(provider: provider, snapshot: snapshot)
                ?? Self.mapXAICostSummary(provider: provider, snapshot: snapshot),
            budget: budgetSnap,
            subscriptionExpiresAt: snapshot?.subscriptionExpiresAt,
            subscriptionRenewsAt: snapshot?.subscriptionRenewsAt,
            rateWindows: rateWindows,
            utilizationHistory: sharedUtilizationHistory,
            perplexityCredits: perplexityCredits,
            accountIdentities: accountIdentities,
            openAIAPIDashboard: openAIAPIDashboard,
            zaiHourlyUsage: zaiHourlyUsage,
            kiroCredits: kiroCredits,
            bedrockCost: bedrockCost,
            moonshotBalance: moonshotBalance,
            // gap B: thread the Antigravity Google-OAuth account list so the
            // iOS AntigravityAccountSwitcher (shipped since 1.7.0) lights up.
            // Resolves the long-standing nil TODO. See mapAntigravityAccounts.
            antigravityAccounts: self.mapAntigravityAccounts(provider: provider),
            grokBilling: grokBilling,
            elevenLabsCredits: elevenLabsCredits,
            deepgramUsage: deepgramUsage,
            groqMetrics: groqMetrics,
            llmProxyStats: llmProxyStats,
            claudeAdminUsage: claudeAdminUsage,
            claudeExtraUsage: claudeExtraUsage,
            openCodeGoZenBalance: openCodeGoZenBalance,
            minimaxBilling: minimaxBilling,
            codexWorkspace: codexWorkspace,
            openRouterStats: Self.mapOpenRouter(provider: provider, snapshot: snapshot),
            azureOpenAIInfo: Self.mapAzureOpenAIInfo(provider: provider, snapshot: snapshot),
            alibabaTokenPlan: Self.mapAlibabaTokenPlan(provider: provider, snapshot: snapshot),
            deepSeekUsage: Self.mapDeepSeekUsage(provider: provider, snapshot: snapshot),
            codexResetCredits: codexResetCredits,
            usageDataConfidence: Self.mapUsageDataConfidence(snapshot: snapshot),
            // Retained in the shared envelope for old-Mac/new-iOS compatibility.
            // Upstream removed the CrossModel provider in v0.42.0, so new Mac
            // builds no longer have a native snapshot to populate here.
            crossModelUsage: nil,
            wayfinderUsage: wayfinderUsage,
            sub2APIUsage: sub2APIUsage,
            providerAmount: providerAmount,
            accountRecordKey: accountRecordKey,
            accountOrganization: snapshot?.identity?.accountOrganization,
            zoomMateCredits: zoomMateCredits,
            details: Self.mapDetails(snapshot?.details ?? []))
    }

    static func syncAccountIdentities(
        provider: UsageProvider,
        identity: ProviderIdentitySnapshot?,
        accountRecordKey: String?) -> [String]?
    {
        var values = AccountIdentityComputer.compute(provider: provider, identity: identity)
        if accountRecordKey != nil,
           values == nil,
           identity?.accountEmailIsFallbackLabel != true,
           let normalizedEmail = AccountIdentityComputer.normalize(identity?.accountEmail)
        {
            // Preserve the pre-1.19 real-email cross-Mac merge behavior for
            // non-Tier-A token providers. Editable label fallbacks are marked
            // at their source and deliberately excluded.
            values = ["\(provider.rawValue):email:\(normalizedEmail)"]
        }
        if let accountRecordKey {
            let recordIdentity = "\(provider.rawValue):record:\(accountRecordKey)"
            var resolved = values ?? []
            if !resolved.contains(recordIdentity) {
                resolved.append(recordIdentity)
            }
            values = resolved
        }
        return values
    }

    static func additionalWindowLabel(windowMinutes: Int?) -> String {
        switch windowMinutes {
        case 1440: "Daily"
        case 10080: "Weekly"
        case 43200: "Monthly"
        default: "Additional"
        }
    }

    static func tokenAccountRecordKey(_ account: ProviderTokenAccount) -> String {
        "token-\(account.id.uuidString.lowercased())"
    }

    static func mapProviderAmount(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?) -> SyncProviderAmount?
    {
        guard let providerCost else { return nil }
        let kind: String
        let amount: Double
        switch provider {
        case .neuralwatt, .zenmux:
            guard providerCost.limit <= 0 else { return nil }
            kind = "balance"
            amount = providerCost.used
        case .aiand, .fireworks:
            guard providerCost.limit <= 0 else { return nil }
            kind = "spend"
            amount = providerCost.used
        case .claude:
            guard let balance = providerCost.balance else { return nil }
            kind = "balance"
            amount = balance
        case .xai:
            kind = "balance"
            amount = providerCost.balance ?? providerCost.used
        default:
            return nil
        }
        let confidence = snapshot?.dataConfidence ?? .unknown
        return SyncProviderAmount(
            kind: kind,
            amount: amount,
            currencyCode: providerCost.currencyCode,
            period: providerCost.period,
            isEstimated: confidence == .estimated || confidence == .percentOnly)
    }

    static func mapSub2APIUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncSub2APIUsage?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    static func mapWayfinderUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncWayfinderUsage?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    // MARK: - v0.26 envelope mappers (private)

    static func mapOpenAIAPIDashboard(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncOpenAIAPIDashboard?
    {
        guard provider == .openai, let openai = snapshot?.openAIAPIUsage else { return nil }

        func summary(_ s: OpenAIAPIUsageSnapshot.Summary) -> SyncOpenAISummary {
            SyncOpenAISummary(
                totalCostUSD: s.costUSD,
                totalRequests: s.requests,
                totalTokens: s.totalTokens)
        }

        let dailyBuckets: [SyncOpenAIDailyBucket] = openai.daily.map { bucket in
            SyncOpenAIDailyBucket(
                dayKey: bucket.day,
                costUSD: bucket.costUSD,
                requests: bucket.requests,
                inputTokens: bucket.inputTokens,
                cachedInputTokens: bucket.cachedInputTokens,
                outputTokens: bucket.outputTokens,
                totalTokens: bucket.totalTokens)
        }

        // Top models — cost is not always exposed per-model by Admin
        // API; iOS can still rank by request count. Cap at 8 to keep
        // payload bounded.
        let topModels: [SyncOpenAIModelBreakdown] = Array(openai.topModels.prefix(8)).map { m in
            SyncOpenAIModelBreakdown(
                modelName: m.name,
                requests: m.requests,
                totalTokens: m.totalTokens,
                costUSD: 0)
        }

        let topLineItems: [SyncOpenAILineItem] = Array(openai.topLineItems.prefix(8)).map { li in
            SyncOpenAILineItem(name: li.name, costUSD: li.costUSD)
        }

        return SyncOpenAIAPIDashboard(
            last30Days: summary(openai.last30Days),
            last7Days: summary(openai.last7Days),
            latestDay: openai.daily.isEmpty ? nil : summary(openai.latestDay),
            dailyBuckets: dailyBuckets,
            topModels: topModels,
            topLineItems: topLineItems,
            historyDays: openai.historyDays)
    }

    static func mapZaiHourlyUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncZaiHourlyUsage?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    static func mapZoomMateCredits(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncZoomMateCredits?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    static func mapKiroCredits(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncKiroCredits?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    static func mapBedrockCost(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?,
        region: String? = nil) -> SyncBedrockCost?
    {
        // Bedrock data arrives via the generic `providerCost` lane —
        // there is no dedicated `bedrockUsage` snapshot field on
        // `UsageSnapshot`. The upstream `BedrockUsageSnapshot.toUsageSnapshot()`
        // packs region + spend + tokens into `loginMethod` as a single
        // composite display string ("Spend: $X - Budget: $Y - Tokens: $Z"),
        // so we CANNOT read region from there. The caller passes
        // `region` from `SettingsStore.bedrockRegion` for that.
        guard provider == .bedrock, let pc = providerCost else { return nil }
        let percent: Double? = pc.limit > 0
            ? min(max((pc.used / pc.limit) * 100, 0), 100)
            : nil
        return SyncBedrockCost(
            monthlySpendUSD: pc.used,
            monthlyBudgetUSD: pc.limit > 0 ? pc.limit : nil,
            inputTokens: nil,
            outputTokens: nil,
            region: region,
            budgetUsedPercent: percent,
            updatedAt: snapshot?.updatedAt ?? Date())
    }

    static func mapMoonshotBalance(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        primaryWindow: SyncRateWindow?) -> SyncMoonshotBalance?
    {
        // Moonshot's upstream fetcher emits the API balance via
        // `loginMethod` as a localized string like "Balance: $58.40"
        // (or "Balance: $58.40 · $5 in deficit"). `providerCost` and
        // `primary` are BOTH nil in production — see
        // `MoonshotUsageSummary.toUsageSnapshot()`. We parse the
        // dollar amount out of loginMethod; fall back to nil when the
        // format drifts so iOS hides the card rather than show "0.00".
        guard provider == .moonshot else { return nil }
        let loginMethod = snapshot?.identity?.loginMethod ?? ""
        let parsed = Self.parseMoonshotBalance(from: loginMethod)
        // Fallback: if loginMethod isn't parseable (upstream changed
        // the format), keep trying providerCost / primaryWindow so a
        // future Moonshot version that exposes balance via providerCost
        // can land without a fork update.
        let amount = parsed?.amount
            ?? snapshot?.providerCost?.used
            ?? primaryWindow?.usedPercent
        guard let amount, amount > 0 else { return nil }
        return SyncMoonshotBalance(
            balanceAmount: amount,
            balanceCurrency: parsed?.currency ?? snapshot?.providerCost?.currencyCode,
            region: nil,
            updatedAt: snapshot?.updatedAt ?? Date())
    }

    /// Parses Moonshot's `loginMethod` display string into a structured
    /// (amount, currency) pair. The upstream string format is:
    ///
    ///     "Balance: $58.40"
    ///     "Balance: $58.40 · $5.00 in deficit"
    ///
    /// `UsageFormatter.usdString(58.40)` produces "$58.40" with a
    /// leading dollar sign. We strip the prefix label and currency
    /// symbol and parse the number. Returns nil for unrecognized
    /// formats (future-proof against upstream relabeling).
    static func parseMoonshotBalance(from loginMethod: String) -> (amount: Double, currency: String)? {
        // Match the first "Balance: <symbol><digits>.<digits>" token.
        // Range-bounded so we ignore the deficit suffix.
        guard let prefixRange = loginMethod.range(of: "Balance: ") else { return nil }
        let after = loginMethod[prefixRange.upperBound...]
        // Take up to the first separator (space, middle-dot, comma).
        let stopChars: Set<Character> = [" ", "·", ",", "\t"]
        let amountString = String(after.prefix(while: { !stopChars.contains($0) }))
        // Strip the leading currency symbol if present (USD only today).
        var currency = "USD"
        var digits = amountString
        if let first = digits.first, !first.isNumber, first != "-", first != "+" {
            switch first {
            case "$": currency = "USD"
            case "¥": currency = "CNY"
            case "€": currency = "EUR"
            default: break
            }
            digits.removeFirst()
        }
        guard let amount = Double(digits) else { return nil }
        return (amount, currency)
    }

    // MARK: - v0.27 envelope mappers (private)

    static func mapGrokBilling(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncGrokBilling?
    {
        guard provider == .grok, let g = snapshot?.grokUsage else { return nil }
        // Prefer Grok CLI billing (richer — has cents-precise spend
        // and exact billing-period boundaries); fall back to grok.com
        // web billing if Mac took the web fallback path.
        let cliPercent = g.billing?.monthlyUsedPercent
        let webPercent = g.webBilling?.usedPercent
        let percent = cliPercent ?? webPercent
        // CLI exposes monthly cap + used-so-far as cents; convert to
        // USD here so iOS doesn't have to know about the cents wire
        // format. Web billing surfaces only a percentage so this lane
        // stays nil for web-billing-only Macs.
        let spend = g.billing?.usage?.totalUsed?.val.map { Double($0) / 100.0 }
        let limit = g.billing?.monthlyLimit?.val.map { Double($0) / 100.0 }
        let resetAt = g.billing?.billingPeriodEndDate
            ?? g.webBilling?.resetsAt
        // Upstream Grok does not surface a plan-tier string today;
        // wire field is reserved for a future Mac fetcher addition.
        let tier: String? = nil
        // Skip if no useful data — iOS will fall back to the generic
        // primary rate window.
        guard percent != nil || spend != nil else { return nil }
        return SyncGrokBilling(
            monthlyUsedPercent: percent,
            monthlySpendUSD: spend,
            monthlyLimitUSD: limit,
            billingPeriodEndDate: resetAt,
            planTier: tier,
            updatedAt: g.updatedAt)
    }

    static func mapElevenLabsCredits(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncElevenLabsCredits?
    {
        guard provider == .elevenlabs, let e = snapshot?.elevenLabsUsage else { return nil }
        return SyncElevenLabsCredits(
            tier: e.tier,
            characterCount: e.characterCount,
            characterLimit: e.characterLimit,
            usedPercent: e.usedPercent,
            voiceSlotsUsed: e.voiceSlotsUsed,
            voiceLimit: e.voiceLimit,
            professionalVoiceSlotsUsed: e.professionalVoiceSlotsUsed,
            professionalVoiceLimit: e.professionalVoiceLimit,
            resetsAt: e.resetsAt,
            updatedAt: e.updatedAt)
    }

    static func mapDeepgramUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncDeepgramUsage?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    static func mapGroqMetrics(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncGroqMetrics?
    {
        guard provider == .groq, let g = snapshot?.groqUsage else { return nil }
        return SyncGroqMetrics(
            requestsPerMinute: g.requestsPerMinute,
            tokensPerMinute: g.tokensPerMinute,
            cacheHitsPerMinute: g.cacheHitsPerMinute,
            updatedAt: g.updatedAt)
    }

    static func mapLLMProxyStats(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncLLMProxyStats?
    {
        guard provider == .llmproxy, let l = snapshot?.llmProxyUsage else { return nil }
        let topProviders = l.topProviders.prefix(3).map { p in
            SyncLLMProxyProviderSummary(
                name: p.name,
                requests: p.requests,
                tokens: p.tokens,
                approximateCostUSD: p.approximateCostUSD)
        }
        return SyncLLMProxyStats(
            providerCount: l.providerCount,
            credentialCount: l.credentialCount,
            activeCredentialCount: l.activeCredentialCount,
            exhaustedCredentialCount: l.exhaustedCredentialCount,
            totalRequests: l.totalRequests,
            totalTokens: l.totalTokens,
            approximateCostUSD: l.approximateCostUSD,
            minimumRemainingPercent: l.minimumRemainingPercent,
            nextResetAt: l.nextResetAt,
            topProviders: Array(topProviders),
            updatedAt: l.updatedAt)
    }

    // MARK: - v0.27 existing-provider extensions (private)

    static func mapClaudeAdminUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncClaudeAdminUsage?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    static func mapClaudeExtraUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?) -> SyncClaudeExtraUsage?
    {
        guard provider == .claude else { return nil }
        // Claude extra-usage / spend-limit reaches `UsageSnapshot` via
        // two paths today and neither is structured:
        //   - OAuth → a RateWindow with `primaryWindowKind = .spendLimit`
        //     inside `ClaudeUsageFetcher` that gets flattened to the
        //     primary RateWindow before it lands on `UsageSnapshot`.
        //   - Web cookies → a `providerCost` with USD currency and
        //     `period` like "Last month" / "This month".
        //
        // We heuristically synthesise an envelope from `providerCost`
        // when both used + limit + USD currency are present. The
        // brittle OAuth path is deferred to a follow-up that adds a
        // structured field on `UsageSnapshot` to avoid string sniffing.
        // Until then, OAuth-only Claude accounts continue to surface
        // the spend-limit metric via the existing primary RateWindow.
        guard let cost = providerCost,
              cost.limit > 0,
              cost.currencyCode == "USD"
        else { return nil }

        let utilization = min(max((cost.used / cost.limit) * 100, 0), 100)
        let planTier: String? = {
            let login = snapshot?.identity?.loginMethod ?? ""
            if login.localizedCaseInsensitiveContains("enterprise") { return "Enterprise" }
            if login.localizedCaseInsensitiveContains("team") { return "Team" }
            if login.localizedCaseInsensitiveContains("max") { return "Max" }
            if login.localizedCaseInsensitiveContains("pro") { return "Pro" }
            return nil
        }()
        return SyncClaudeExtraUsage(
            utilization: utilization,
            monthlySpendUSD: cost.used,
            monthlyLimitUSD: cost.limit,
            isEnabled: true,
            planTier: planTier,
            updatedAt: snapshot?.updatedAt ?? cost.updatedAt)
    }

    static func mapOpenCodeGoZenBalance(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        providerCost: ProviderCostSnapshot?,
        workspaceID: String?) -> SyncOpenCodeGoZenBalance?
    {
        // Mac packs the Zen balance into `providerCost` with
        // `period = "Zen balance"` and currency USD (see
        // `OpenCodeGoUsageSnapshot.toUsageSnapshot()`). We detect that
        // signature rather than reading from a dedicated field so we
        // don't need to extend `UsageSnapshot` for this drop.
        guard provider == .opencodego,
              let cost = providerCost,
              cost.period == "Zen balance",
              cost.currencyCode == "USD"
        else { return nil }
        return SyncOpenCodeGoZenBalance(
            balanceUSD: cost.used,
            workspaceID: workspaceID,
            updatedAt: snapshot?.updatedAt ?? cost.updatedAt)
    }

    static func mapMiniMaxBilling(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncMiniMaxBillingHistory?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    func mapCodexWorkspace(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncCodexWorkspaceContext?
    {
        guard provider == .codex else { return nil }
        // Instance method only because it needs `self.settings`. The
        // pure-function part lives in `buildCodexWorkspaceContext`
        // below so unit tests can exercise the envelope-shape logic
        // (nil-pruning, pace computation, weekly-window selection)
        // without spinning up a full SyncCoordinator + SettingsStore
        // fixture.
        return Self.buildCodexWorkspaceContext(
            activeAccount: self.settings.codexAccountReconciliationSnapshot.activeStoredAccount,
            snapshot: snapshot)
    }

    /// Pure-function envelope builder extracted from `mapCodexWorkspace`
    /// for testability. Combines:
    ///   1) Workspace metadata from the active Codex account
    ///      (`workspaceLabel` + `workspaceAccountID`, set when
    ///      ManagedCodexAccountService resolves a ChatGPT-Account-Id
    ///      during sign-in).
    ///   2) Weekly pace derived from the snapshot's weekly RateWindow
    ///      via `UsagePace.weekly(window:)`. Mac uses the same code
    ///      path for its menu-bar pace caption so iOS sees identical
    ///      computation.
    ///
    /// Multi-account fan-out: the mapper is only called for the
    /// ACTIVE account's freshly-built snapshot. `expandCodexMultiAccount`
    /// caches that ProviderUsageSnapshot under the active account's
    /// UUID and later re-emits the cached value when the user looks at
    /// a different active account. So each cached snapshot's
    /// `codexWorkspace` reflects whatever was active at the time of
    /// build — correct per-account labelling without needing to
    /// thread account context into the mapper.
    static func buildCodexWorkspaceContext(
        activeAccount: ManagedCodexAccount?,
        snapshot: UsageSnapshot?) -> SyncCodexWorkspaceContext?
    {
        let workspaceLabel = activeAccount?.workspaceLabel
        let workspaceID = activeAccount?.workspaceAccountID

        let paceWindow = Self.codexWeeklyWindow(snapshot: snapshot)
        let pace = paceWindow.flatMap { UsagePace.weekly(window: $0) }
        let paceDelta: Double? = pace.map { $0.deltaPercent / 100.0 }
        let paceLabel: String? = pace.map { UsagePaceText.weeklySummary(provider: .codex, pace: $0) }

        // Skip emitting an empty envelope so iOS doesn't render a
        // ghost row — every reader checks the optional.
        if workspaceLabel == nil, workspaceID == nil, paceDelta == nil {
            return nil
        }

        return SyncCodexWorkspaceContext(
            workspaceID: workspaceID,
            workspaceName: workspaceLabel,
            weeklyPaceDelta: paceDelta,
            weeklyPaceLabel: paceLabel,
            updatedAt: snapshot?.updatedAt ?? Date())
    }

    /// Picks the weekly-shaped rate window from a Codex snapshot.
    /// Codex builds put the weekly bucket in `secondary` today; fall
    /// back to scanning `primary` + `tertiary` if a future refactor
    /// shuffles the slots so the badge keeps rendering.
    private static func codexWeeklyWindow(snapshot: UsageSnapshot?) -> RateWindow? {
        let candidates: [RateWindow?] = [snapshot?.secondary, snapshot?.tertiary, snapshot?.primary]
        for window in candidates {
            guard let window else { continue }
            guard let minutes = window.windowMinutes else { continue }
            // Weekly window is 7 × 24 × 60 = 10080. Treat ≥ 1 day as
            // candidate so unusual upstream slots (5-day, 14-day, etc.)
            // still surface a pace badge.
            if minutes >= 24 * 60 { return window }
        }
        return nil
    }

    // swiftlint:enable function_parameter_count

    /// For multi-account providers (Codex via observation-cache + token-based
    /// providers via direct read of `accountSnapshots`), records each account's
    /// snapshot into `multiAccountCache`, then appends cached / live non-active
    /// snapshots to `providerSnapshots`. Also purges cache entries for accounts
    /// the user has removed from Mac since the last push.
    ///
    /// **Why this works.** Mac's `UsageStore.snapshots[.codex]` only ever
    /// holds one account's data (whichever is active). On switch, the
    /// previous account's snapshot is wiped. By capturing each account's
    /// data the moment it becomes active and stashing it under the
    /// managed-account UUID, the cache fills up over the session and we
    /// can emit one CKRecord per known account on each push without
    /// touching upstream's account-scoped refresh machinery.
    ///
    /// **Cold start.** A fresh process knows the active account on first
    /// push; non-active accounts populate as the user switches between
    /// them. Until then, iOS sees the active account only — same as
    /// pre-fix behavior, never worse.
    private func captureAndExpandMultiAccountSnapshots(
        into providerSnapshots: inout [ProviderUsageSnapshot],
        enabledSet: Set<UsageProvider>)
    {
        // Codex (R1) — observation-based cache. Self-contained block so its
        // early-exits don't bypass the token-provider loop below.
        if enabledSet.contains(.codex) {
            self.expandCodexMultiAccount(into: &providerSnapshots)
        } else {
            // Codex disabled — purge cache to avoid emitting stale
            // multi-account records if the user later re-enables Codex
            // (R3 P1: disabled-provider leak guard, see Research/020 H5).
            self.multiAccountCache.purgeStaleAccounts(
                providerID: UsageProvider.codex.rawValue,
                livingAccountIDs: [])
        }

        // Token-based multi-account providers (R2). Phase G: now reads
        // `TokenAccountSupportCatalog.allProviders` so every catalog
        // entry (18 today; auto-grows as upstream adds new token
        // providers) shares
        // `UsageStore.accountSnapshots: [UsageProvider: [TokenAccountUsageSnapshot]]`
        // when the user has enabled "Show all token accounts in menu" AND
        // configured 2+ accounts. Unlike Codex, the data is co-resident in
        // memory so we read live and emit per-account immediately. Cache is
        // populated alongside for future resilience (e.g., if user toggles
        // "Show all" off later mid-session — though current cache lookup
        // path doesn't yet read from cache for token providers; that's an
        // R3 hardening item).
        for tokenProvider in Self.tokenBasedMultiAccountProviders {
            guard enabledSet.contains(tokenProvider) else {
                // Provider disabled — purge any cached entries so a
                // re-enable starts clean (R3 P1: disabled-provider
                // leak guard, see Research/020 H5).
                self.multiAccountCache.purgeStaleAccounts(
                    providerID: tokenProvider.rawValue,
                    livingAccountIDs: [])
                continue
            }
            guard let entries = self.store.accountSnapshots[tokenProvider.instanceID],
                  entries.count >= 2
            else { continue }

            let providerID = tokenProvider.rawValue
            let meta = self.store.providerMetadata[tokenProvider]
            let sharedCostSummary = self.makeCostSummary(for: tokenProvider)
            let sharedUtilizationHistory = self.makeUtilizationHistory(
                for: tokenProvider)
            let livingIDs = Set(entries.map(\.account.id.uuidString))

            // Remove the active-only entry that the main loop appended for
            // this provider — we replace it with the full per-account list
            // built from `accountSnapshots`. The active account is included
            // via its corresponding entry in `entries`, so we don't lose
            // any data.
            providerSnapshots.removeAll { $0.providerID == providerID }

            for entry in entries {
                let perAccount = self.buildProviderUsageSnapshot(
                    for: tokenProvider,
                    snapshot: entry.snapshot,
                    error: entry.error,
                    metadata: meta,
                    sharedCostSummary: sharedCostSummary,
                    sharedUtilizationHistory: sharedUtilizationHistory,
                    accountRecordKey: Self.tokenAccountRecordKey(entry.account))
                self.multiAccountCache.record(
                    perAccount,
                    providerID: providerID,
                    accountID: entry.account.id.uuidString)
                providerSnapshots.append(perAccount)
            }

            // Drop cache entries for accounts the user removed since last push.
            self.multiAccountCache.purgeStaleAccounts(
                providerID: providerID,
                livingAccountIDs: livingIDs)
        }
    }

    /// Codex multi-account expansion (R1). Captures the active managed
    /// account's freshly-built snapshot into `multiAccountCache`, then
    /// appends every cached non-active snapshot so the push covers all
    /// known managed accounts. Pure side-effect on the in/out
    /// `providerSnapshots` and the cache; safe to call even when no Codex
    /// multi-account configuration exists (early-exits without mutation).
    private func expandCodexMultiAccount(
        into providerSnapshots: inout [ProviderUsageSnapshot])
    {
        let codexProviderID = UsageProvider.codex.rawValue
        let reconciliation = self.settings.codexAccountReconciliationSnapshot
        let storedAccounts = reconciliation.storedAccounts
        let livingIDs = Set(storedAccounts.map(\.id.uuidString))

        // Always purge stale entries first so a removed account never keeps
        // shipping after the user deletes it on Mac. (Runs even when count
        // < 2 to handle the "user removed all but one" case cleanly.)
        self.multiAccountCache.purgeStaleAccounts(
            providerID: codexProviderID,
            livingAccountIDs: livingIDs)

        // Single managed account or none → original single-snapshot path is
        // sufficient; nothing to expand.
        guard storedAccounts.count >= 2 else { return }

        // Active managed account ID (only `.managedAccount(id)` participates;
        // `.liveSystem` is treated as "no managed account active" and
        // contributes only via the regular single-snapshot path).
        guard let activeAccount = reconciliation.activeStoredAccount else {
            return
        }
        let activeAccountID = activeAccount.id.uuidString

        // The active Codex snapshot built by the main loop (if codex is
        // enabled). When codex isn't enabled we have nothing to capture.
        guard let activeIndex = providerSnapshots.firstIndex(where: {
            $0.providerID == codexProviderID
        })
        else {
            return
        }

        // R3 P2 (Research/020 H7): don't pollute the cache with a ghost
        // (placeholder) snapshot — that's the post-switch invalidation
        // window where `prepareCodexAccountScopedRefreshIfNeeded` wiped
        // `snapshots[.codex]` but the new account's data hasn't loaded yet.
        // Recording the ghost would overwrite the previous (real) value
        // for `activeAccountID` with garbage. We still append cached
        // non-active snapshots below so `currentRecordNames` retains the
        // codex composites and the L1 ghost-cleanup logic doesn't see a
        // whole-provider disappearance.
        let activeSnap = providerSnapshots[activeIndex]
        let isActiveGhost = Self.isGhostProvider(activeSnap)
        if !isActiveGhost {
            self.multiAccountCache.record(
                activeSnap,
                providerID: codexProviderID,
                accountID: activeAccountID)
        }

        // Append every cached non-active Codex snapshot so this push covers
        // all known accounts in one go. iOS merges by (providerID,
        // accountEmail) so distinct emails produce distinct cards. Done
        // even when `isActiveGhost == true` to preserve provider presence
        // in the L1 cleanup diff during the refresh race window.
        let cachedNonActive = self.multiAccountCache.cachedSnapshots(
            providerID: codexProviderID,
            excludingAccountID: activeAccountID)
        providerSnapshots.append(contentsOf: cachedNonActive)
    }

    /// All composite recordNames the current snapshot list will push. Used
    /// to compute the disabled/identity-drifted set against
    /// `lastPushedRecordNames`.
    private func computeCurrentRecordNames(
        from providerSnapshots: [ProviderUsageSnapshot]) -> Set<String>
    {
        var result: Set<String> = []
        for provider in providerSnapshots where !Self.isGhostProvider(provider) {
            result.insert(CloudSyncManager.perProviderRecordName(
                deviceID: self.deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey))
        }
        return result
    }

    /// Produces the envelopes that should be uploaded this cycle plus the
    /// hash-cache updates to apply on success. Pure function over
    /// `providerSnapshots` and the in-memory hash state.
    ///
    /// Ghost providers (no rate / cost / budget / error / status and no
    /// accountEmail) are filtered here — Mac may build them during early
    /// startup before OAuth / cookies have loaded. Writing them to
    /// `DeviceProvidersZone` would produce a CKRecord keyed by
    /// `{deviceID}|{providerID}|_` which is NEVER overwritten by the later
    /// real push (that one goes to `...|user@...` — different recordName),
    /// leaving stale empty records on the server. iOS 1.3.0 has a defensive
    /// filter too, but skipping here is the root-cause fix.
    private func buildPerProviderDelta(
        from providerSnapshots: [ProviderUsageSnapshot],
        synced: SyncedUsageSnapshot) -> (envelopes: [ProviderUsageEnvelope], hashUpdates: [String: Int])
    {
        var envelopes: [ProviderUsageEnvelope] = []
        var updates: [String: Int] = [:]

        for provider in providerSnapshots {
            // Skip "ghost" providers — see doc comment.
            if Self.isGhostProvider(provider) {
                continue
            }
            let key = Self.perProviderHashKey(
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey)
            // iOS 1.6.0 / Mac 0.25.2 — resolve per-provider quota warning
            // config and inject it into the snapshot so iOS renders the
            // same warning markers Mac shows in its menu bar. nil when
            // providerID isn't a known UsageProvider (mock fallback or
            // future upstream provider) — iOS falls back to
            // SyncQuotaWarningConfig.macDefaults. Hashing the enriched
            // snapshot means a quota config change re-emits the envelope
            // even when usage data is unchanged.
            let quotaWarnings = self.resolvedQuotaWarnings(for: provider.providerID)
            let enrichedProvider = provider.with(quotaWarnings: quotaWarnings)
            guard let data = try? providerDiffEncoder.encode(enrichedProvider) else {
                // Encode fallback: include anyway so we don't silently drop a
                // provider just because its JSON encoding briefly failed.
                envelopes.append(ProviderUsageEnvelope(
                    deviceID: self.deviceID,
                    deviceName: synced.deviceName,
                    appVersion: synced.appVersion,
                    mobileVersion: synced.mobileVersion,
                    syncTimestamp: synced.syncTimestamp,
                    notificationPushEnabled: synced.notificationPushEnabled,
                    provider: enrichedProvider))
                continue
            }
            let hash = Self.stableHash(for: data)
            if self.lastProviderHashes[key] == hash {
                continue // unchanged — skip
            }
            envelopes.append(ProviderUsageEnvelope(
                deviceID: self.deviceID,
                deviceName: synced.deviceName,
                appVersion: synced.appVersion,
                mobileVersion: synced.mobileVersion,
                syncTimestamp: synced.syncTimestamp,
                notificationPushEnabled: synced.notificationPushEnabled,
                provider: enrichedProvider))
            updates[key] = hash
        }
        return (envelopes, updates)
    }

    /// Resolves Mac's per-provider quota warning config into the wire
    /// format (`SyncQuotaWarningConfig`). Returns `nil` only when the
    /// `providerID` string doesn't map to a known `UsageProvider` enum
    /// case (e.g. mock-fallback IDs like `_mock_*` or a future provider
    /// added upstream after this Mac release). In that case iOS
    /// gracefully falls back to `SyncQuotaWarningConfig.macDefaults`.
    ///
    /// **Why resolved values (not just overrides)**: iOS as a pure
    /// receiver shouldn't have to re-implement Mac's threshold
    /// resolution chain (override → global → defaults). Mac sends the
    /// effective values that its own notification engine uses, so
    /// iOS markers and Mac local notifications agree byte-for-byte.
    private func resolvedQuotaWarnings(for providerID: String) -> SyncQuotaWarningConfig? {
        guard let usageProvider = UsageProvider(rawValue: providerID) else {
            return nil
        }
        return SyncQuotaWarningConfig(
            sessionThresholds: self.settings.resolvedQuotaWarningThresholds(
                provider: usageProvider, window: .session),
            sessionEnabled: self.settings.quotaWarningEnabled(
                provider: usageProvider, window: .session),
            weeklyThresholds: self.settings.resolvedQuotaWarningThresholds(
                provider: usageProvider, window: .weekly),
            weeklyEnabled: self.settings.quotaWarningEnabled(
                provider: usageProvider, window: .weekly))
    }

    /// Matches `SnapshotCache.isGhost` on the iOS side: a provider with NO
    /// usable signal in any field. Mac filter prevents ghost records from
    /// being created in `DeviceProvidersZone` in the first place.
    private static func isGhostProvider(_ provider: ProviderUsageSnapshot) -> Bool {
        !provider.hasUsableSignal
    }

    /// Key used by the in-memory diff cache — same (providerID, accountEmail)
    /// composite as `CloudSyncManager.perProviderRecordName`, but local-only
    /// (never serialized to CloudKit). The `"_"` sentinel for nil
    /// `accountEmail` **must match 4 peer sites byte-for-byte**:
    /// `CloudSyncManager.perProviderRecordName` (record name on CloudKit),
    /// iOS `SnapshotCache.compositeKey`, iOS
    /// `ProviderSnapshotModel.makeCompositeKey`, and any delete-by-
    /// recordName parser. Build 67 drift discovery: an earlier build
    /// used `""` at one of those four sites, silently breaking delete
    /// cascades. If you change the sentinel, change **all four sites**
    /// in the same commit.
    private static func perProviderHashKey(
        providerID: String,
        accountEmail: String?,
        accountRecordKey: String?) -> String
    {
        "\(providerID)|\(accountRecordKey ?? accountEmail ?? "_")"
    }

    /// Deterministic hash of a provider's encoded JSON. Uses FNV-1a (64-bit)
    /// so it's cheap, stable across process launches, and collision-free in
    /// the range we care about (≤100 providers × app lifetime).
    ///
    /// `0xCBF2_9CE4_8422_2325` is the canonical FNV-1a **64-bit offset
    /// basis**; `0x100_0000_01B3` is the canonical **64-bit FNV prime**.
    /// These two values are the FNV-1a standard and must not be changed —
    /// altering them would invalidate every cached provider hash and force
    /// a full re-upload from every user's Mac on next startup (the diff
    /// cache would see every provider as "changed" because the new hash
    /// wouldn't match the cached old one).
    private static func stableHash(for data: Data) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    func stopObserving() {
        self.isObserving = false
    }

    private func makeCostSummary(for provider: UsageProvider) -> SyncCostSummary? {
        let tokenSnapshot = self.store.tokenSnapshots[provider.instanceID]
        let serviceBreakdownsByDay = self.dashboardServiceBreakdowns(for: provider)

        guard tokenSnapshot != nil || !serviceBreakdownsByDay.isEmpty else { return nil }

        let tokenEntriesByDay = Dictionary(
            uniqueKeysWithValues: (tokenSnapshot?.daily ?? []).map { ($0.date, $0) })
        let allDayKeys = Set(tokenEntriesByDay.keys).union(serviceBreakdownsByDay.keys).sorted()
        let daily = allDayKeys.map { dayKey -> SyncDailyPoint in
            let entry = tokenEntriesByDay[dayKey]
            let modelBreakdowns = self.modelBreakdowns(from: entry, provider: provider)
            let serviceBreakdowns = serviceBreakdownsByDay[dayKey] ?? []

            let fallbackCost =
                entry?.costUSD
                    ?? self.breakdownTotal(modelBreakdowns)
                    ?? self.breakdownTotal(serviceBreakdowns)
                    ?? 0

            // Day is estimated iff any of its model breakdowns is. Service
            // breakdowns never go through the fallback resolver (they come
            // from the upstream API directly), so they're excluded from the
            // OR aggregation.
            let dayIsEstimated = modelBreakdowns.contains(where: { $0.isEstimated == true })
            return SyncDailyPoint(
                dayKey: dayKey,
                costUSD: fallbackCost,
                totalTokens: entry?.totalTokens ?? 0,
                modelBreakdowns: modelBreakdowns,
                serviceBreakdowns: serviceBreakdowns,
                isEstimated: dayIsEstimated ? true : nil)
        }

        let totalDailyCost = daily.reduce(0) { $0 + $1.costUSD }
        let summaryIsEstimated = daily.contains(where: { $0.isEstimated == true })

        return SyncCostSummary(
            sessionCostUSD: tokenSnapshot?.sessionCostUSD,
            sessionTokens: tokenSnapshot?.sessionTokens,
            last30DaysCostUSD: tokenSnapshot?.last30DaysCostUSD ?? (daily.isEmpty ? nil : totalDailyCost),
            last30DaysTokens: tokenSnapshot?.last30DaysTokens,
            daily: daily,
            isEstimated: summaryIsEstimated ? true : nil,
            historyDays: tokenSnapshot?.historyDays,
            sessionRequests: tokenSnapshot?.sessionRequests,
            last30DaysRequests: tokenSnapshot?.last30DaysRequests,
            currencyCode: tokenSnapshot?.currencyCode)
    }

    /// Builds a cost summary for Mistral from its native daily usage buckets
    /// (gap C). Mistral spend is API-billing based (no local token DB), so the
    /// generic token-DB `makeCostSummary` returns nil for it — without this,
    /// iOS only ever saw the one-line "API spend: $X" loginMethod. Feeding a
    /// SyncCostSummary lets iOS reuse the existing Cost dashboard (30-day chart
    /// + Model Mix) for Mistral, exactly like Codex/Claude. No envelope or iOS
    /// change needed — pure bridge plumbing.
    static func mapMistralCostSummary(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncCostSummary?
    {
        guard provider == .mistral, let m = snapshot?.mistralUsage, !m.daily.isEmpty else {
            return nil
        }
        let daily: [SyncDailyPoint] = m.daily.map { bucket in
            SyncDailyPoint(
                dayKey: bucket.day,
                costUSD: bucket.cost,
                totalTokens: bucket.totalTokens,
                modelBreakdowns: bucket.models
                    .filter { $0.cost > 0 }
                    .map { SyncCostBreakdown(label: $0.name, costUSD: $0.cost) }
                    .sorted { $0.costUSD > $1.costUSD },
                serviceBreakdowns: [],
                isEstimated: nil)
        }
        return SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: m.totalCost,
            last30DaysTokens: m.totalInputTokens + m.totalOutputTokens + m.totalCachedTokens,
            daily: daily,
            isEstimated: nil,
            currencyCode: m.currency)
    }

    /// xAI's Management API exposes prepaid balance plus daily USD spend.
    /// Reuse the existing cost-summary wire type so old iOS builds ignore the
    /// additive data and iOS 1.20.0 gets the normal 30-day chart.
    static func mapXAICostSummary(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncCostSummary?
    {
        // Upstream v0.48 migrated xAI's rich history to the generic details lane.
        nil
    }

    /// Maps OpenRouter's native balance/credits + per-key usage windows into
    /// the wire envelope (gap D). Before this, all of OpenRouter's
    /// /api/v1/credits + /api/v1/key data collapsed to a "Balance: $X"
    /// loginMethod line on iOS.
    static func mapOpenRouter(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncOpenRouterStats?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    /// Maps Azure OpenAI deployment identity into the wire envelope (gap E).
    /// Azure is a deployment-validation provider; before this the endpoint host
    /// was dropped (envelope has no accountOrganization) and the deployment
    /// only reached iOS as a loginMethod string.
    static func mapAzureOpenAIInfo(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncAzureOpenAIInfo?
    {
        guard provider == .azureopenai, let a = snapshot?.azureOpenAIUsage else { return nil }
        return SyncAzureOpenAIInfo(
            endpointHost: a.endpointHost,
            deploymentName: a.deploymentName,
            model: a.model,
            apiVersion: a.apiVersion,
            updatedAt: a.updatedAt)
    }

    /// Maps Alibaba Token Plan (Bailian) structured credit quota into the wire
    /// envelope (gap G). The quota % + a "credits used" string already cross via
    /// the generic RateWindow; this adds the structured numbers for a proper card.
    static func mapAlibabaTokenPlan(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncAlibabaTokenPlan?
    {
        guard provider == .alibabatokenplan, let a = snapshot?.alibabaTokenPlanUsage else { return nil }
        let hasCreditProgress = (a.totalQuota ?? 0) > 0 &&
            (a.usedQuota != nil || a.remainingQuota != nil)
        let hasRemainingCredits = a.remainingQuota != nil
        guard hasCreditProgress || hasRemainingCredits else { return nil }
        return SyncAlibabaTokenPlan(
            planName: a.planName,
            usedCredits: a.usedQuota,
            totalCredits: a.totalQuota,
            remainingCredits: a.remainingQuota,
            resetsAt: a.resetsAt,
            updatedAt: a.updatedAt)
    }

    /// Maps DeepSeek web-session usage + cost summary into the wire envelope
    /// (upstream v0.30.0 #1166). Balance stays on the generic primary
    /// RateWindow (a formatted string built in `toUsageSnapshot()`), so only
    /// the new usage/cost numbers cross here.
    static func mapDeepSeekUsage(
        provider: UsageProvider,
        snapshot: UsageSnapshot?) -> SyncDeepSeekUsage?
    {
        // Upstream v0.48 migrated this provider to the generic details lane.
        nil
    }

    private func modelBreakdowns(
        from entry: CostUsageDailyReport.Entry?,
        provider: UsageProvider) -> [SyncCostBreakdown]
    {
        guard let breakdowns = entry?.modelBreakdowns else { return [] }
        return breakdowns
            .compactMap { breakdown in
                guard let cost = breakdown.costUSD, cost > 0 else { return nil }
                let estimated = Self.isModelEstimated(modelName: breakdown.modelName, provider: provider)
                return SyncCostBreakdown(
                    label: breakdown.modelName,
                    costUSD: cost,
                    isEstimated: estimated ? true : nil,
                    // Carry the Codex standard/fast (priority) split through to
                    // iOS (#1070). nil for providers/builds without the split.
                    standardCostUSD: breakdown.standardCostUSD,
                    priorityCostUSD: breakdown.priorityCostUSD,
                    standardTokens: breakdown.standardTokens,
                    priorityTokens: breakdown.priorityTokens)
            }
            .sorted { lhs, rhs in
                if lhs.costUSD == rhs.costUSD {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.costUSD > rhs.costUSD
            }
    }

    /// `true` when `modelName` is NOT in the local pricing table for its
    /// provider — meaning the cost was computed via a fallback resolver
    /// row. Used to flag `isEstimated` on the outbound `SyncCostBreakdown`
    /// so iOS can render the estimated badge (P5).
    private static func isModelEstimated(modelName: String, provider: UsageProvider) -> Bool {
        switch provider {
        case .claude, .vertexai:
            !ModelFallbackPricing.isClaudeModelKnown(modelName)
        case .codex:
            !ModelFallbackPricing.isCodexModelKnown(modelName)
        case .zai, .gemini, .antigravity, .cursor, .opencode, .opencodego, .alibaba, .factory, .copilot, .devin,
             .minimax, .kilo, .kiro, .kimi, .augment, .jetbrains, .amp, .ollama, .synthetic,
             .openrouter, .warp, .perplexity, .abacus, .mistral,
             // Upstream 0.24–0.25.1 providers — pre-computed costs from
             // their own APIs, never go through the local Codex/Claude
             // pricing tables, so never "estimated".
             .openai, .manus, .windsurf, .mimo, .doubao, .deepseek,
             .codebuff, .crof, .venice, .commandcode, .stepfun,
             // Upstream v0.26.0 new providers. Moonshot/Kimi API balance
             // and Bedrock Cost Explorer numbers come from their own APIs,
             // never via the local pricing tables.
             .moonshot, .bedrock,
             // Upstream v0.27.0 new providers. Grok (web billing + CLI),
             // GroqCloud (Prometheus), ElevenLabs (API key), Deepgram
             // (project API), LLM Proxy (quota stats) all surface
             // pre-computed numbers from their own APIs — never via the
             // local Codex/Claude pricing tables.
             .grok, .groq, .elevenlabs, .deepgram, .llmproxy,
             // Upstream v0.28.0–v0.29.0 new providers. Azure OpenAI
             // (deployment validation), Alibaba Token Plan (Bailian quota),
             // and T3 Chat (web session) all surface pre-computed numbers
             // from their own APIs — never via the local pricing tables.
             .azureopenai, .alibabatokenplan, .t3chat,
             // Upstream v0.36.0–v0.36.1 new providers. LiteLLM, Poe,
             // Chutes, and Zed surface provider-computed usage/quota
             // values (or no USD cost), not local Codex/Claude model
             // pricing table estimates.
             .litellm, .poe, .chutes, .zed,
             // Upstream v0.38.0–v0.39.0 new providers. Sakana, Qoder,
             // and ClawRouter surface provider-computed
             // values (or no USD cost), not local Codex/Claude model
             // pricing table estimates.
             .sakana, .qoder, .clawrouter,
             // Upstream v0.42.0–v0.45.2 providers likewise expose
             // provider-computed quota, balance, or spend values.
             .clinepass, .deepinfra, .neuralwatt, .longcat, .sub2api, .wayfinder, .zenmux, .aiand,
             // Upstream v0.46.0-v0.47.0 providers expose provider-computed
             // quota, credit, balance, or workspace allowance values.
             .qwencloud, .zoommate, .xai, .notion, .fireworks, .ibmbob:
            // These providers never reach the local pricing table — their
            // costs come pre-computed from upstream APIs (or don't exist).
            // No fallback applies, so they are never "estimated".
            false
        }
    }

    private func dashboardServiceBreakdowns(for provider: UsageProvider) -> [String: [SyncCostBreakdown]] {
        guard provider == .codex else { return [:] }
        guard let usageBreakdown = self.store.openAIDashboard?.usageBreakdown else { return [:] }

        return Dictionary(uniqueKeysWithValues: usageBreakdown.map { daily in
            let services = daily.services
                .filter { $0.creditsUsed > 0 }
                .map { service in
                    SyncCostBreakdown(
                        label: Self.displayServiceName(service.service),
                        costUSD: service.creditsUsed)
                }
                .sorted { lhs, rhs in
                    if lhs.costUSD == rhs.costUSD {
                        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    }
                    return lhs.costUSD > rhs.costUSD
                }
            return (daily.day, services)
        })
    }

    private func makeUtilizationHistory(for provider: UsageProvider) -> [SyncUtilizationSeries]? {
        let buckets = self.store.planUtilizationHistory[provider.instanceID]
        guard let buckets, !buckets.isEmpty else { return nil }

        // Use preferred account or unscoped history
        let histories: [PlanUtilizationSeriesHistory]
        if let key = buckets.preferredAccountKey, let accountHistories = buckets.accounts[key],
           !accountHistories.isEmpty
        {
            histories = accountHistories
        } else if !buckets.unscoped.isEmpty {
            histories = buckets.unscoped
        } else if let mostRecent = buckets.accounts.values
            .filter({ !$0.isEmpty })
            .max(by: {
                ($0.compactMap(\.latestCapturedAt).max() ?? .distantPast) <
                    ($1.compactMap(\.latestCapturedAt).max() ?? .distantPast)
            })
        {
            histories = mostRecent
        } else {
            return nil
        }

        // Cap entries per series to keep CloudKit payload within CKRecord limits.
        // 730 hourly samples ≈ 1 month of data, ~70KB per series.
        let maxEntriesPerSeries = 730

        return histories.map { series in
            let capped = series.entries.suffix(maxEntriesPerSeries)
            return SyncUtilizationSeries(
                name: series.name.rawValue,
                windowMinutes: series.windowMinutes,
                entries: capped.map { entry in
                    SyncUtilizationEntry(
                        capturedAt: entry.capturedAt,
                        usedPercent: entry.usedPercent,
                        resetsAt: entry.resetsAt)
                })
        }
    }

    private func breakdownTotal(_ breakdowns: [SyncCostBreakdown]) -> Double? {
        guard !breakdowns.isEmpty else { return nil }
        return breakdowns.reduce(0) { $0 + $1.costUSD }
    }

    private static func displayServiceName(_ rawName: String) -> String {
        switch rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cli":
            "Codex Run"
        default:
            rawName
        }
    }

    /// Returns a stable UUID for this Mac, creating and persisting one if needed.
    private static func stableDeviceID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: CloudSyncConstants.deviceIDKey) {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: CloudSyncConstants.deviceIDKey)
        return newID
    }
}

// swiftlint:enable file_length type_body_length
