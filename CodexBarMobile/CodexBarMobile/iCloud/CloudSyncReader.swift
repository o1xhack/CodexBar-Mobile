import CloudKit
import CodexBarSync
import Foundation
import SwiftData

/// iOS-side reader that fetches usage snapshots from CloudKit (all devices)
/// and falls back to legacy KVS for older Mac app versions.
final class CloudSyncReader: @unchecked Sendable {
    private let syncManager: CloudSyncManager

    init(syncManager: CloudSyncManager = .shared) {
        self.syncManager = syncManager
    }

    // MARK: - CloudKit (primary)

    /// Fetches snapshots from all devices via CloudKit.
    func fetchAllDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchAllDeviceSnapshots()
    }

    // MARK: - Cache-based flow (v2 — Research/011)

    /// Per-provider zone only. Caller owns the priority-merge decision.
    func fetchPerProviderDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchPerProviderDeviceSnapshots()
    }

    /// Legacy zones only (custom zone + default zone).
    func fetchLegacyDeviceSnapshots() async -> MultiDeviceSyncResult {
        await syncManager.fetchLegacyDeviceSnapshots()
    }

    /// Incremental change-token fetch for the per-provider zone.
    func fetchPerProviderZoneChanges(
        since token: CKServerChangeToken?
    ) async -> CloudSyncManager.PerProviderZoneChanges {
        await syncManager.fetchPerProviderZoneChanges(since: token)
    }

    // MARK: - Account linkage (Research/019 §7)

    /// Fetch all `ProviderAccountLinkage` records from CloudKit. Returns
    /// empty when the zone or record type doesn't exist yet (= no user
    /// has confirmed a merge on this iCloud account).
    func fetchProviderAccountLinkages() async -> [ProviderAccountLinkage] {
        await syncManager.fetchProviderAccountLinkages()
    }

    /// Save a user-confirmed merge or unmerge to CloudKit.
    @discardableResult
    func saveProviderAccountLinkage(
        _ linkage: ProviderAccountLinkage
    ) async -> SyncPushResult {
        await syncManager.saveProviderAccountLinkage(linkage)
    }

    /// Stable iPhone UUID for stamping LinkageRecord `confirmedFromDeviceID`.
    func currentDeviceID() -> String {
        syncManager.stableDeviceID()
    }

    // MARK: - Legacy KVS (backward compatibility)

    /// Returns the most recently synced snapshot from KVS (fallback).
    func latestKVSSnapshot() -> SyncedUsageSnapshot? {
        syncManager.fetchKVSSnapshot()
    }

    /// Starts observing KVS changes (backward compat with older Mac apps).
    func startKVSObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        syncManager.startKVSObserving(handler: handler)
    }

    @discardableResult
    func synchronizeKVS() -> Bool {
        syncManager.synchronizeKVSStore()
    }

    func stopKVSObserving() {
        syncManager.stopKVSObserving()
    }

    // MARK: - Deprecated shims (keep callers compiling during transition)

    func latestSnapshot() -> SyncedUsageSnapshot? {
        syncManager.fetchKVSSnapshot()
    }

    func startObserving(handler: @escaping @MainActor (SyncResult) -> Void) {
        syncManager.startKVSObserving(handler: handler)
    }

    @discardableResult
    func synchronize() -> Bool {
        syncManager.synchronizeKVSStore()
    }

    func stopObserving() {
        syncManager.stopKVSObserving()
    }

    // MARK: - SwiftData parallel write (P2a)

    /// Mirrors the raw per-device CloudKit snapshots into the SwiftData store.
    ///
    /// P2a is additive: the old `@Observable` path continues to drive views.
    /// This method exists so `SyncedUsageData` can call it right after
    /// `mergeSnapshots(...)` completes, keeping the two sources in lockstep.
    ///
    /// Writes ONLY per-device rows. The merged snapshot is not persisted —
    /// P2b's @Query-based views will re-derive the merged view on the fly
    /// from per-device rows, so storing a separate merged row would be
    /// redundant duplication. Codex review (P2) also flagged that the
    /// synthetic "legacy:<deviceName>" key for merged snapshots shifts
    /// whenever the set of contributing devices changes, which would
    /// orphan prior merged rows. Per-device rows are keyed by stable
    /// deviceID, so they accumulate cleanly.
    static func persistToSwiftData(
        deviceSnapshots: [SyncedUsageSnapshot],
        merged _: SyncedUsageSnapshot?,
        context: ModelContext
    ) {
        do {
            try SwiftDataBridge.upsert(deviceSnapshots: deviceSnapshots, into: context)
        } catch {
            // P2a is parallel-write; failures here must never break the
            // legacy path. Log and move on.
            print("[CodexBar SwiftData] Parallel-write upsert failed: \(error)")
        }
    }

    // MARK: - Multi-device merge

    /// Providers whose cost data comes from LOCAL files (per-machine CLI history).
    /// Cost data from these providers must be SUMMED across devices, not deduplicated.
    /// All other providers read cost from account-level web APIs → safe to deduplicate.
    ///
    /// **Why these three specifically:**
    /// - `claude` reads `~/.claude/history.jsonl` on each Mac — two Macs each
    ///   hold their own history; summing gives total spend across machines.
    /// - `codex` reads Codex CLI's per-Mac JSONL — same reasoning.
    /// - `vertexai` reads `gcloud` auth cache + request logs — per-Mac.
    /// All other providers (Cursor, Augment, Perplexity, JetBrains AI, …)
    /// report cost from an account-level web API — both Macs see the same
    /// server-authoritative number, so `latestNonNil` is correct and SUM
    /// would double-count. **Adding a new local-CLI provider here is a
    /// behavior change.** Test multi-device Cost tab before and after to
    /// verify the summed value matches user expectation.
    private static let localCostProviders: Set<String> = ["claude", "codex", "vertexai"]

    /// Merges snapshots from multiple devices into a single unified snapshot.
    ///
    /// **Merge strategy (Research/019 architecture):**
    /// 1. Each `ProviderUsageSnapshot` produces an *effective identifier set*:
    ///    - If `accountIdentities` is non-nil and non-empty → use it directly
    ///      (this is what Mac ≥ 0.23 with the multi-version-merge work writes).
    ///    - Else if `accountEmail` is non-empty → synthesize
    ///      `["{providerID}:email:{normalized}"]`. This bridges
    ///      old-Mac-with-email and new-Mac-with-explicit-email-identifier
    ///      automatically (they share the same string).
    ///    - Else → synthesize `["{providerID}:legacy-no-identity"]`
    ///      (preserves the prior `(providerID, "")` grouping where nil-email
    ///      snapshots from multiple devices merged into one card).
    /// 2. Build the identifier graph: each snapshot is a node; edges connect
    ///    snapshots that share at least one identifier string.
    /// 3. Connected components = merge groups. Each component reduces via
    ///    `mergeProviderEntries` (cost SUMs for local-cost providers, take-newest
    ///    for everything else).
    ///
    /// Identifier strings are `{providerID}:{scheme}:{value}` so two providers
    /// can never share an identifier (different prefix) — cross-provider
    /// false merges are structurally impossible.
    static func mergeSnapshots(
        _ snapshots: [SyncedUsageSnapshot],
        linkages: [ProviderAccountLinkage] = []
    ) -> SyncedUsageSnapshot? {
        guard !snapshots.isEmpty else { return nil }

        // 1. Flatten to (entry index → ProviderUsageSnapshot)
        // Drop extinct mock zombies (CKRecords from earlier mock-injector
        // designs that are no longer emitted by current Mac code but
        // linger in CloudKit). They'd otherwise show as duplicate cards
        // alongside the current mock design's records.
        var allProviders: [ProviderUsageSnapshot] = []
        for snapshot in snapshots {
            allProviders.append(contentsOf: MockProviderDetector.filteredProviders(from: snapshot))
        }

        // 2. Compute effective identifiers per provider snapshot
        let effectiveIdentifiers: [[String]] = allProviders.map(Self.effectiveIdentifiers(for:))

        // 3. Union-find across shared identifiers (L1+L2)
        var uf = MergeUnionFind(count: allProviders.count)
        var firstSeenByIdentifier: [String: Int] = [:]
        for (idx, ids) in effectiveIdentifiers.enumerated() {
            for id in ids {
                if let prior = firstSeenByIdentifier[id] {
                    uf.union(prior, idx)
                } else {
                    firstSeenByIdentifier[id] = idx
                }
            }
        }

        // 3b. Apply user-confirmed LinkageRecords (L3, Research/019 §7).
        // Each non-unmerge linkage adds a virtual edge between any pair of
        // snapshots whose effective identifiers share at least one of the
        // listed `linkedIdentifiers` for the same providerID. Order-
        // independent because edges are symmetric; idempotent because
        // repeating the same edge in union-find is a no-op.
        //
        // Unmerge records (`unmerge=true`) are applied AFTER all merges.
        // They DON'T tear apart a union directly (you can't "un-union" in
        // a standard union-find); instead they prevent the edge from
        // being added at all, by suppressing it from the linkage set
        // before the merge pass. This matches §7.4 semantics — the
        // inverse record nullifies the original merge edge.
        let (mergeLinkages, unmergeLinkages) = Self.partitionLinkages(linkages)
        let suppressedLinkageEdges = Self.suppressedEdges(unmergeLinkages: unmergeLinkages)
        for linkage in mergeLinkages {
            // Skip linkages whose providerID doesn't match any snapshot —
            // they're either for a provider the user hasn't synced or
            // they refer to a deleted account. No-op (union-find is empty
            // for that subset anyway).
            let candidateIndices = Self.indices(
                forProviderID: linkage.providerID,
                in: allProviders)
            guard !candidateIndices.isEmpty else { continue }

            // Skip if this entire linkage was suppressed by an unmerge.
            if Self.isLinkageSuppressed(linkage, by: suppressedLinkageEdges) {
                continue
            }

            // Add an edge between any pair of candidate snapshots whose
            // effective identifiers contain at least one of the linked
            // identifier strings. Pairwise so we union every transitive
            // pair, but in practice the candidate set is small (usually
            // 2 snapshots) so this is O(linkedIDs · candidates²) and
            // negligible.
            var matching: [Int] = []
            for candidate in candidateIndices {
                let ids = effectiveIdentifiers[candidate]
                if ids.contains(where: { linkage.linkedIdentifiers.contains($0) }) {
                    matching.append(candidate)
                }
            }
            guard matching.count >= 2 else { continue }
            let anchor = matching[0]
            for other in matching.dropFirst() {
                uf.union(anchor, other)
            }
        }

        // 4. Group by root, merge each group
        var groupedIndices: [Int: [Int]] = [:]
        for idx in 0..<allProviders.count {
            let root = uf.find(idx)
            groupedIndices[root, default: []].append(idx)
        }

        var mergedProviders: [ProviderUsageSnapshot] = []
        for (_, indices) in groupedIndices {
            let group = indices.map { allProviders[$0] }
            if group.count == 1 {
                mergedProviders.append(group[0])
            } else {
                mergedProviders.append(mergeProviderEntries(group))
            }
        }

        // Sort providers by name for stable UI ordering
        mergedProviders.sort { $0.providerName < $1.providerName }

        // Use the most recent sync timestamp across all devices
        let latestTimestamp = snapshots.map(\.syncTimestamp).max() ?? Date()

        // Build device name list for display. Sort first so the combined string is stable
        // across fetches regardless of server iteration order — without this, SwiftDataBridge's
        // deviceID fallback (`"legacy:" + deviceName`) would see "Mac A, Mac B" at one moment
        // and "Mac B, Mac A" at another, producing duplicate merged-device rows in the local
        // store. Flagged in Codex review (P2).
        let deviceNames = snapshots.map(\.deviceName).sorted()
        let combinedDeviceName = deviceNames.count == 1
            ? deviceNames[0]
            : deviceNames.joined(separator: ", ")

        // notificationPushEnabled merge semantics (deterministic across
        // CloudKit iteration order):
        //   1. If ANY device explicitly set it to false → false
        //      (conservative: respect the off-signal).
        //   2. Else if ANY device explicitly set it to true → true.
        //   3. Else nil (no device has an opinion yet — fresh install,
        //      or every snapshot predates the field).
        // Prior code (`snapshots.first?.notificationPushEnabled`) fell through
        // to whichever snapshot CloudKit returned first, which flipped between
        // `true` and `nil` across refreshes when one Mac had pushed the field
        // and another hadn't.
        let pushEnabled: Bool? = {
            if snapshots.contains(where: { $0.notificationPushEnabled == false }) {
                return false
            }
            if snapshots.contains(where: { $0.notificationPushEnabled == true }) {
                return true
            }
            return nil
        }()

        // Pick the *highest* app/mobile version across devices so the merged
        // "Mac App" / "Synced Mobile Version" row reflects the most up-to-date
        // client, regardless of which snapshot CloudKit happened to iterate
        // first. Prior code used `snapshots.first?.appVersion`, which flipped
        // non-deterministically for users running two Macs on different
        // CodexBar versions and showed whichever arrived first.
        let appVersion = snapshots.compactMap(\.appVersion).max(by: Self.semverLessThan)
        let mobileVersion = snapshots.compactMap(\.mobileVersion).max(by: Self.semverLessThan)

        return SyncedUsageSnapshot(
            providers: mergedProviders,
            syncTimestamp: latestTimestamp,
            deviceName: combinedDeviceName,
            deviceID: nil,
            appVersion: appVersion,
            mobileVersion: mobileVersion,
            notificationPushEnabled: pushEnabled)
    }

    /// Builds the effective identifier set for a single `ProviderUsageSnapshot`.
    /// See `mergeSnapshots` doc comment for the synthesis rules. Returned list
    /// is **never empty** — every snapshot gets at least a legacy bucket key
    /// so it ends up in some group.
    static func effectiveIdentifiers(for provider: ProviderUsageSnapshot) -> [String] {
        if let explicit = provider.accountIdentities, !explicit.isEmpty {
            return explicit
        }
        // Synthesize the same scheme Mac ≥ 0.23 writes for email. Critical
        // to use `AccountIdentityNormalize` (NFC + percent-encode + length
        // cap) — *not* `lowercased + trim` — so the bytes match what
        // `AccountIdentityComputer.normalize` produces on the Mac side.
        // Otherwise non-ASCII emails (e.g. `café@…`) split into two cards
        // when one Mac is on 0.23+ and another is on 0.20.x. Caught in
        // 0.23.3 code review as P1-3.
        if let normalized = AccountIdentityNormalize.normalize(provider.accountEmail) {
            return ["\(provider.providerID):email:\(normalized)"]
        }
        // Fully legacy: nil identifiers + nil/empty accountEmail. Bucket
        // all such snapshots for the same provider together (preserves the
        // pre-019 `(providerID, "")` grouping behavior so users on two
        // legacy Macs still see one card).
        return ["\(provider.providerID):legacy-no-identity"]
    }

    /// Orders two semver-ish strings like `"0.20.3"` / `"1.2.0"` so `max(by:)`
    /// returns the highest. Falls back to string comparison for non-numeric
    /// segments (e.g. `"0.20.0-beta"`). Strictly lower; ties are `false`.
    static func semverLessThan(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map(String.init)
        let rhsParts = rhs.split(separator: ".").map(String.init)
        let count = max(lhsParts.count, rhsParts.count)
        for i in 0 ..< count {
            let l = i < lhsParts.count ? lhsParts[i] : "0"
            let r = i < rhsParts.count ? rhsParts[i] : "0"
            if let li = Int(l), let ri = Int(r) {
                if li != ri { return li < ri }
            } else if l != r {
                return l < r
            }
        }
        return false
    }

    /// For an **account-level optional field** (budget, perplexityCredits,
    /// non-local-cost `costSummary`, etc.) — returns the value from the most
    /// recent device that actually has it populated. Falls through older
    /// devices if the newer ones don't (yet) have data for this field.
    ///
    /// This is the right semantics when two Macs running different CodexBar
    /// versions sync to the same iCloud account: the older Mac may never
    /// populate a newly-added field (e.g. 0.20.2 doesn't know about
    /// `perplexityCredits`), but the newer Mac does — naive take-latest on
    /// `lastUpdated` would drop the data to `nil` every time the older Mac
    /// happened to refresh last. With `latestNonNil`, the iPhone renders
    /// the richer data as long as ANY synced device has it, regardless of
    /// refresh timing.
    ///
    /// Returns nil only when every entry has nil for the keypath.
    private static func latestNonNil<T>(
        _ entries: [ProviderUsageSnapshot],
        _ keyPath: KeyPath<ProviderUsageSnapshot, T?>
    ) -> T? {
        entries
            .sorted(by: { $0.lastUpdated > $1.lastUpdated })
            .first(where: { $0[keyPath: keyPath] != nil })?[keyPath: keyPath]
    }

    /// Merges multiple entries of the same provider+account from different devices.
    ///
    /// Field-by-field semantics:
    ///   - Identity (`providerID` / `providerName` / `accountEmail`): same
    ///     across all entries by construction — take from base.
    ///   - Status (`statusMessage` / `isError`): take from latest entry;
    ///     "most recent status" is the meaningful user-facing signal.
    ///   - Rate windows (`primary` / `secondary` / `rateWindows`): take from
    ///     latest entry — these are always populated on every provider
    ///     refresh, so the newer timestamp's data is the current quota state.
    ///   - Cost (`costSummary`): SUM across devices for local-cost providers
    ///     (claude / codex / vertexai, which read per-Mac CLI files), take
    ///     **latestNonNil** otherwise (account-level API data; old-Mac
    ///     version-drift protection).
    ///   - Utilization history: MERGE across devices and dedup by hour.
    ///   - Account-level structured data (`budget`, `perplexityCredits`,
    ///     `subscriptionExpiresAt`, `subscriptionRenewsAt`, provider-specific
    ///     rich payloads, etc.): **latestNonNil** — both Macs observe the same
    ///     account-level pool, but only Macs running the version that knows a
    ///     field will populate it. Take any non-nil from newest down so
    ///     cross-version pairs don't flicker.
    private static func mergeProviderEntries(_ entries: [ProviderUsageSnapshot]) -> ProviderUsageSnapshot {
        // Take the most recent entry as the base (for rate limits + status)
        let base = entries.max(by: { $0.lastUpdated < $1.lastUpdated })!

        // Cost: sum for local-cost providers, otherwise latestNonNil (account-level).
        // `compactMap(\.costSummary)` drops devices whose costSummary is nil
        // before summing. This is intentional: a Mac that doesn't run a CLI
        // provider yet (e.g. Claude Code not installed) reports costSummary
        // as nil — summing over an empty prefix is 0, which is the right
        // answer. `flatMap` here would trap on nil; `compactMap` is required
        // for cross-version / partial-install robustness.
        let isLocalCost = localCostProviders.contains(base.providerID)
        let mergedCost: SyncCostSummary?
        if isLocalCost {
            mergedCost = mergeCostSummaries(entries.compactMap(\.costSummary))
        } else {
            mergedCost = Self.latestNonNil(entries, \.costSummary)
        }

        // Utilization history: merge across ALL devices, dedup by hour.
        // Same `compactMap` reasoning — a device that doesn't have
        // utilization tracking yet (pre-1.2.0 iOS, or a Mac with that
        // provider not yet enabled) has nil `utilizationHistory`, and we
        // want to fall through to the other device's data rather than lose
        // everything. See Build 77 cross-version merge fix.
        let mergedUtilization = Self.mergeUtilizationHistories(
            entries.compactMap(\.utilizationHistory))

        return ProviderUsageSnapshot(
            providerID: base.providerID,
            providerName: base.providerName,
            primary: base.primary,
            secondary: base.secondary,
            accountEmail: base.accountEmail,
            loginMethod: Self.latestNonNil(entries, \.loginMethod),
            statusMessage: base.statusMessage,
            isError: base.isError,
            lastUpdated: base.lastUpdated,
            costSummary: mergedCost,
            budget: Self.latestNonNil(entries, \.budget),
            subscriptionExpiresAt: Self.latestNonNil(entries, \.subscriptionExpiresAt),
            subscriptionRenewsAt: Self.latestNonNil(entries, \.subscriptionRenewsAt),
            rateWindows: base.rateWindows,
            utilizationHistory: mergedUtilization,
            perplexityCredits: Self.latestNonNil(entries, \.perplexityCredits),
            accountIdentities: Self.latestNonNil(entries, \.accountIdentities),
            quotaWarnings: Self.latestNonNil(entries, \.quotaWarnings),
            openAIAPIDashboard: Self.latestNonNil(entries, \.openAIAPIDashboard),
            zaiHourlyUsage: Self.latestNonNil(entries, \.zaiHourlyUsage),
            kiroCredits: Self.latestNonNil(entries, \.kiroCredits),
            bedrockCost: Self.latestNonNil(entries, \.bedrockCost),
            moonshotBalance: Self.latestNonNil(entries, \.moonshotBalance),
            antigravityAccounts: Self.latestNonNil(entries, \.antigravityAccounts),
            grokBilling: Self.latestNonNil(entries, \.grokBilling),
            elevenLabsCredits: Self.latestNonNil(entries, \.elevenLabsCredits),
            deepgramUsage: Self.latestNonNil(entries, \.deepgramUsage),
            groqMetrics: Self.latestNonNil(entries, \.groqMetrics),
            llmProxyStats: Self.latestNonNil(entries, \.llmProxyStats),
            claudeAdminUsage: Self.latestNonNil(entries, \.claudeAdminUsage),
            claudeExtraUsage: Self.latestNonNil(entries, \.claudeExtraUsage),
            openCodeGoZenBalance: Self.latestNonNil(entries, \.openCodeGoZenBalance),
            minimaxBilling: Self.latestNonNil(entries, \.minimaxBilling),
            codexWorkspace: Self.latestNonNil(entries, \.codexWorkspace),
            openRouterStats: Self.latestNonNil(entries, \.openRouterStats),
            azureOpenAIInfo: Self.latestNonNil(entries, \.azureOpenAIInfo),
            alibabaTokenPlan: Self.latestNonNil(entries, \.alibabaTokenPlan),
            deepSeekUsage: Self.latestNonNil(entries, \.deepSeekUsage))
    }

    /// Sums cost data from multiple devices.
    /// Daily points are merged by dayKey (costs summed), then totals are recalculated.
    private static func mergeCostSummaries(_ summaries: [SyncCostSummary]) -> SyncCostSummary? {
        guard !summaries.isEmpty else { return nil }
        if summaries.count == 1 { return summaries[0] }

        // Merge daily points by dayKey, summing costs and tokens
        var dailyByKey: [String: (costUSD: Double, totalTokens: Int, modelBreakdowns: [SyncCostBreakdown])] = [:]

        for summary in summaries {
            for point in summary.daily {
                if var existing = dailyByKey[point.dayKey] {
                    existing.costUSD += point.costUSD
                    existing.totalTokens += point.totalTokens
                    // Combine model breakdowns (merge by label, sum costs)
                    var breakdownByLabel: [String: Double] = [:]
                    for b in existing.modelBreakdowns { breakdownByLabel[b.label, default: 0] += b.costUSD }
                    for b in point.modelBreakdowns { breakdownByLabel[b.label, default: 0] += b.costUSD }
                    existing.modelBreakdowns = breakdownByLabel
                        .map { SyncCostBreakdown(label: $0.key, costUSD: $0.value) }
                        .sorted { $0.costUSD > $1.costUSD }
                    dailyByKey[point.dayKey] = existing
                } else {
                    dailyByKey[point.dayKey] = (point.costUSD, point.totalTokens, point.modelBreakdowns)
                }
            }
        }

        let mergedDaily = dailyByKey.keys.sorted().map { dayKey in
            let entry = dailyByKey[dayKey]!
            return SyncDailyPoint(
                dayKey: dayKey,
                costUSD: entry.costUSD,
                totalTokens: entry.totalTokens,
                modelBreakdowns: entry.modelBreakdowns)
        }

        // Recalculate totals from merged daily data
        let totalCost = mergedDaily.reduce(0) { $0 + $1.costUSD }
        let totalTokens = mergedDaily.reduce(0) { $0 + $1.totalTokens }

        // Sum session costs across devices (each device has its own session)
        let sessionCost = summaries.compactMap(\.sessionCostUSD).reduce(0, +)
        let sessionTokens = summaries.compactMap(\.sessionTokens).reduce(0, +)

        return SyncCostSummary(
            sessionCostUSD: sessionCost > 0 ? sessionCost : nil,
            sessionTokens: sessionTokens > 0 ? sessionTokens : nil,
            last30DaysCostUSD: mergedDaily.isEmpty ? nil : totalCost,
            last30DaysTokens: mergedDaily.isEmpty ? nil : totalTokens,
            daily: mergedDaily)
    }

    // MARK: - Utilization History Merge + Hourly Dedup

    /// Merges utilization histories from multiple devices.
    /// Session quota is account-level, so entries from different Macs
    /// are observations of the SAME metric at different times.
    ///
    /// Steps:
    /// 1. Collect entries from all devices per series **name** (not per
    ///    (name, windowMinutes)). Cross-version Macs may report the same
    ///    logical series with a drifted `windowMinutes` (e.g. a fallback
    ///    classification on an older build); splitting on that leaves two
    ///    "session" series in the merged list and makes downstream pickers
    ///    like `history.first(where: { $0.name == "session" })` hit the
    ///    stale/empty variant non-deterministically. The entries describe
    ///    the same account-level pool regardless, so unioning them is safe.
    /// 2. Dedup by hour: group by floor(capturedAt / 1h), take average
    /// 3. Keep the winning series' `windowMinutes` from the entry that
    ///    captured most recently — that's the newest-Mac reading
    /// 4. Result: clean hourly data regardless of device count
    private static func mergeUtilizationHistories(
        _ histories: [[SyncUtilizationSeries]]
    ) -> [SyncUtilizationSeries]? {
        let allSeries = histories.flatMap { $0 }
        guard !allSeries.isEmpty else { return nil }

        var entriesByName: [String: [SyncUtilizationEntry]] = [:]
        // Remember the latest windowMinutes per name so we can pick the
        // freshest reading when two devices disagree.
        var freshestWindowByName: [String: (capturedAt: Date, windowMinutes: Int)] = [:]

        for series in allSeries {
            entriesByName[series.name, default: []].append(contentsOf: series.entries)
            if let latestCaptured = series.entries.map(\.capturedAt).max() {
                let current = freshestWindowByName[series.name]
                if current == nil || latestCaptured > current!.capturedAt {
                    freshestWindowByName[series.name] = (latestCaptured, series.windowMinutes)
                }
            } else if freshestWindowByName[series.name] == nil {
                // Empty series: record its windowMinutes as a fallback in case
                // no other device has entries for this name.
                //
                // `.distantPast` is an intentional sentinel — any real
                // `latestCaptured` will compare greater (`> .distantPast`)
                // in the outer branch, which overrides this value as soon
                // as a device with entries is processed. Order doesn't
                // matter: real-data-device-first keeps the real value; empty-
                // first lets the real value override. The only case where
                // `.distantPast` sticks is "every device has an empty
                // series for this name" — at which point downstream
                // consumers see `(empty entries, some windowMinutes)` and
                // skip the series at the `guard !deduped.isEmpty` below.
                freshestWindowByName[series.name] = (.distantPast, series.windowMinutes)
            }
        }

        // Dedup each series by hour
        var result: [SyncUtilizationSeries] = []

        for (name, entries) in entriesByName {
            let deduped = Self.dedupByHour(entries)
            guard !deduped.isEmpty else { continue }
            let windowMinutes = freshestWindowByName[name]?.windowMinutes ?? 0
            result.append(SyncUtilizationSeries(
                name: name,
                windowMinutes: windowMinutes,
                entries: deduped))
        }

        // Sort: session first, then weekly, then others
        result.sort { lhs, rhs in
            let order = ["session": 0, "weekly": 1, "opus": 2]
            return (order[lhs.name] ?? 99) < (order[rhs.name] ?? 99)
        }

        return result.isEmpty ? nil : result
    }

    /// Groups entries by hour + reset segment, averages within each bucket.
    /// Keeps reset boundaries separate to avoid mixing pre/post-reset samples.
    private static func dedupByHour(_ entries: [SyncUtilizationEntry]) -> [SyncUtilizationEntry] {
        guard !entries.isEmpty else { return [] }

        let hourInterval: TimeInterval = 3600

        // Key: (hourSlot, resetBoundary) — different reset windows in the same hour stay separate
        struct BucketKey: Hashable {
            let hourSlot: Int
            let resetEpoch: Int  // floor(resetsAt / hourInterval), or -1 if nil
        }

        var buckets: [BucketKey: (totalPercent: Double, count: Int, latestReset: Date?, latestCaptured: Date)] = [:]

        for entry in entries {
            let hourSlot = Int(floor(entry.capturedAt.timeIntervalSince1970 / hourInterval))
            // `-1` is an out-of-band sentinel — every real `resetsAt` is
            // positive, so `-1` can never collide with a real reset epoch.
            // This keeps entries with `resetsAt == nil` in their own bucket
            // (separate from entries that happen to share the same hourSlot
            // but have a real reset window), which is the **whole reason
            // `resetEpoch` is part of the key**: Build 77 learned that
            // mixing pre-reset (e.g. 90% quota used) and post-reset
            // (e.g. 5% fresh window) samples into one bucket averages them
            // to 47.5%, a meaningless number. Dropping `resetEpoch` from
            // BucketKey is the regression guarded against by the
            // `mergedUtilizationCrossResetBoundarySeparatesBuckets` test.
            let resetEpoch = entry.resetsAt.map { Int(floor($0.timeIntervalSince1970 / hourInterval)) } ?? -1
            let key = BucketKey(hourSlot: hourSlot, resetEpoch: resetEpoch)

            if var bucket = buckets[key] {
                bucket.totalPercent += entry.usedPercent
                bucket.count += 1
                if entry.capturedAt > bucket.latestCaptured {
                    bucket.latestCaptured = entry.capturedAt
                    bucket.latestReset = entry.resetsAt ?? bucket.latestReset
                }
                buckets[key] = bucket
            } else {
                buckets[key] = (
                    totalPercent: entry.usedPercent,
                    count: 1,
                    latestReset: entry.resetsAt,
                    latestCaptured: entry.capturedAt)
            }
        }

        // Convert back to entries, sorted by time
        return buckets.keys
            .sorted { $0.hourSlot < $1.hourSlot || ($0.hourSlot == $1.hourSlot && $0.resetEpoch < $1.resetEpoch) }
            .map { key in
                let bucket = buckets[key]!
                let avg = bucket.totalPercent / Double(bucket.count)
                return SyncUtilizationEntry(
                    capturedAt: bucket.latestCaptured,
                    usedPercent: min(100, max(0, avg)),
                    resetsAt: bucket.latestReset)
            }
    }

    // MARK: - LinkageRecord application helpers (Research/019 §7)

    /// Splits the linkage list into merge edges and unmerge edges.
    static func partitionLinkages(
        _ linkages: [ProviderAccountLinkage]
    ) -> (merges: [ProviderAccountLinkage], unmerges: [ProviderAccountLinkage]) {
        var merges: [ProviderAccountLinkage] = []
        var unmerges: [ProviderAccountLinkage] = []
        for linkage in linkages {
            if linkage.unmerge {
                unmerges.append(linkage)
            } else {
                merges.append(linkage)
            }
        }
        return (merges, unmerges)
    }

    /// Build the set of suppressed merge keys from unmerge records.
    /// A merge linkage is suppressed if some unmerge record names the same
    /// `(providerID, linkedIdentifiers-as-Set)` pair. Order of identifiers
    /// in the merge vs unmerge is normalized via Set comparison so
    /// "[a,b]" matches "[b,a]".
    ///
    /// Returned key shape: `"providerID|sorted-linked-ids-joined"`.
    static func suppressedEdges(
        unmergeLinkages: [ProviderAccountLinkage]
    ) -> Set<String> {
        var keys = Set<String>()
        for record in unmergeLinkages {
            keys.insert(Self.linkageKey(record))
        }
        return keys
    }

    /// True if a merge linkage is suppressed by an unmerge record with the
    /// same provider + linkedIdentifiers set.
    static func isLinkageSuppressed(
        _ linkage: ProviderAccountLinkage,
        by suppressedKeys: Set<String>
    ) -> Bool {
        suppressedKeys.contains(Self.linkageKey(linkage))
    }

    /// Canonicalize a linkage's content for set-equality comparison
    /// across merge/unmerge pairs.
    private static func linkageKey(_ linkage: ProviderAccountLinkage) -> String {
        let sorted = linkage.linkedIdentifiers.sorted()
        return "\(linkage.providerID)|\(sorted.joined(separator: ","))"
    }

    /// Return indices of providers in `allProviders` whose providerID matches.
    static func indices(
        forProviderID providerID: String,
        in allProviders: [ProviderUsageSnapshot]
    ) -> [Int] {
        var indices: [Int] = []
        for (idx, provider) in allProviders.enumerated()
            where provider.providerID == providerID
        {
            indices.append(idx)
        }
        return indices
    }
}

/// Minimal union-find for merging provider snapshots in `mergeSnapshots`.
/// Path-compression on `find`; union-by-attach (parent of root A becomes
/// root B). Sufficient for our scale (typically <100 entries) — no need
/// for rank-based union.
struct MergeUnionFind {
    private var parent: [Int]

    init(count: Int) {
        self.parent = Array(0..<count)
    }

    mutating func find(_ x: Int) -> Int {
        if self.parent[x] != x {
            self.parent[x] = self.find(self.parent[x])
        }
        return self.parent[x]
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = self.find(a)
        let rb = self.find(b)
        if ra != rb {
            self.parent[ra] = rb
        }
    }
}
