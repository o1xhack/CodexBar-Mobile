import CodexBarSync
import Foundation

/// Shared provider merge engine for every iOS surface that renders synced usage.
///
/// This intentionally lives outside `CloudSyncReader`: the reader owns CloudKit
/// fetch/persistence, while this type owns the pure snapshot reduction. Widgets,
/// app screens, tests, and future previews must call this same code path so
/// multi-device local cost totals cannot drift between surfaces.
enum ProviderSnapshotMerger {
    typealias ProviderFilter = (SyncedUsageSnapshot) -> [ProviderUsageSnapshot]

    /// Providers whose cost data comes from LOCAL files (per-machine CLI history).
    /// Cost data from these providers must be SUMMED across devices, not deduplicated.
    /// All other providers read cost from account-level web APIs, so the latest
    /// non-nil account-level value is the safe merge.
    private static let localCostProviders: Set<String> = ["claude", "codex", "grok", "opencodego", "vertexai"]

    static func usesLocalCostMerge(providerID: String) -> Bool {
        self.localCostProviders.contains(providerID)
    }

    static func mergeSnapshots(
        _ snapshots: [SyncedUsageSnapshot],
        linkages: [ProviderAccountLinkage] = [],
        sumLocalCostsAcrossDevices: Bool = true,
        providerFilter: ProviderFilter? = nil) -> SyncedUsageSnapshot?
    {
        guard !snapshots.isEmpty else { return nil }

        let providersForSnapshot = providerFilter ?? { $0.providers }
        var allProviders: [ProviderUsageSnapshot] = []
        var sourceAppVersions: [String?] = []
        var sourceDeviceIDs: [String] = []
        var sourceSyncTimestamps: [Date] = []
        for snapshot in snapshots {
            let providers = providersForSnapshot(snapshot)
            allProviders.append(contentsOf: providers)
            sourceAppVersions.append(contentsOf: repeatElement(snapshot.appVersion, count: providers.count))
            let deviceID = snapshot.deviceID ?? "legacy:\(snapshot.deviceName)"
            sourceDeviceIDs.append(contentsOf: repeatElement(deviceID, count: providers.count))
            sourceSyncTimestamps.append(contentsOf: providers.map { snapshot.publicationTimestamp(for: $0) })
        }

        let effectiveIdentifiers: [[String]] = allProviders.map(Self.effectiveIdentifiers(for:))

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

        let (mergeLinkages, unmergeLinkages) = Self.partitionLinkages(linkages)
        let suppressedLinkageEdges = Self.suppressedEdges(unmergeLinkages: unmergeLinkages)
        for linkage in mergeLinkages {
            let candidateIndices = Self.indices(
                forProviderID: linkage.providerID,
                in: allProviders)
            guard !candidateIndices.isEmpty else { continue }
            if Self.isLinkageSuppressed(linkage, by: suppressedLinkageEdges) {
                continue
            }

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

        var groupedIndices: [Int: [Int]] = [:]
        for idx in 0..<allProviders.count {
            let root = uf.find(idx)
            groupedIndices[root, default: []].append(idx)
        }

        var mergedProviders: [(provider: ProviderUsageSnapshot, sortIdentity: String, publicationTimestamp: Date)] = []
        for (_, indices) in groupedIndices {
            let group = indices.map { allProviders[$0] }
            let sortIdentity = Set(indices.flatMap { effectiveIdentifiers[$0] })
                .sorted()
                .joined(separator: "|")
            if group.count == 1 {
                mergedProviders.append((group[0], sortIdentity, sourceSyncTimestamps[indices[0]]))
            } else {
                mergedProviders.append((
                    self.mergeProviderEntries(
                        group,
                        sourceAppVersions: indices.map { sourceAppVersions[$0] },
                        sourceDeviceIDs: indices.map { sourceDeviceIDs[$0] },
                        sourceSyncTimestamps: indices.map { sourceSyncTimestamps[$0] },
                        sumLocalCosts: sumLocalCostsAcrossDevices),
                    sortIdentity,
                    indices.map { sourceSyncTimestamps[$0] }.max() ?? sourceSyncTimestamps[indices[0]]))
            }
        }

        mergedProviders.sort { lhs, rhs in
            if lhs.provider.providerName != rhs.provider.providerName {
                return lhs.provider.providerName < rhs.provider.providerName
            }
            if lhs.provider.providerID != rhs.provider.providerID {
                return lhs.provider.providerID < rhs.provider.providerID
            }
            return lhs.sortIdentity < rhs.sortIdentity
        }

        let latestTimestamp = snapshots.map(\.syncTimestamp).max() ?? Date()
        let deviceNames = snapshots.map(\.deviceName).sorted()
        let combinedDeviceName = deviceNames.count == 1
            ? deviceNames[0]
            : deviceNames.joined(separator: ", ")

        let pushEnabled: Bool? = {
            if snapshots.contains(where: { $0.notificationPushEnabled == false }) {
                return false
            }
            if snapshots.contains(where: { $0.notificationPushEnabled == true }) {
                return true
            }
            return nil
        }()

        let appVersion = snapshots.compactMap(\.appVersion).max(by: Self.semverLessThan)
        let mobileVersion = snapshots.compactMap(\.mobileVersion).max(by: Self.semverLessThan)
        let providerPublicationTimestamps = Dictionary(
            mergedProviders.map {
                (SyncedUsageSnapshot.providerPublicationKey(for: $0.provider), $0.publicationTimestamp)
            },
            uniquingKeysWith: max)

        return SyncedUsageSnapshot(
            providers: mergedProviders.map(\.provider),
            syncTimestamp: latestTimestamp,
            deviceName: combinedDeviceName,
            deviceID: nil,
            appVersion: appVersion,
            mobileVersion: mobileVersion,
            notificationPushEnabled: pushEnabled,
            providerPublicationTimestamps: providerPublicationTimestamps)
    }

    static func effectiveIdentifiers(for provider: ProviderUsageSnapshot) -> [String] {
        if let explicit = provider.accountIdentities, !explicit.isEmpty {
            // Real account/org/email identities merge the same account across
            // Macs. A per-install token UUID remains available for record,
            // cache and card uniqueness but must not split that stable group.
            // When the Mac only had an editable label fallback it emits no
            // email identity, so the record identity becomes authoritative.
            let recordPrefix = "\(provider.providerID):record:"
            let stable = explicit.filter { !$0.hasPrefix(recordPrefix) }
            return stable.isEmpty ? explicit : stable
        }
        if let accountRecordKey = provider.accountRecordKey, !accountRecordKey.isEmpty {
            return ["\(provider.providerID):record:\(accountRecordKey)"]
        }
        if let normalized = AccountIdentityNormalize.normalize(provider.accountEmail) {
            return ["\(provider.providerID):email:\(normalized)"]
        }
        return ["\(provider.providerID):legacy-no-identity"]
    }

    static func semverLessThan(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map(String.init)
        let rhsParts = rhs.split(separator: ".").map(String.init)
        let count = max(lhsParts.count, rhsParts.count)
        for i in 0..<count {
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

    static func partitionLinkages(
        _ linkages: [ProviderAccountLinkage]) -> (merges: [ProviderAccountLinkage], unmerges: [
        ProviderAccountLinkage
    ]) {
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

    static func suppressedEdges(
        unmergeLinkages: [ProviderAccountLinkage]) -> Set<String>
    {
        var keys = Set<String>()
        for record in unmergeLinkages {
            keys.insert(Self.linkageKey(record))
        }
        return keys
    }

    static func isLinkageSuppressed(
        _ linkage: ProviderAccountLinkage,
        by suppressedKeys: Set<String>) -> Bool
    {
        suppressedKeys.contains(self.linkageKey(linkage))
    }

    static func indices(
        forProviderID providerID: String,
        in allProviders: [ProviderUsageSnapshot]) -> [Int]
    {
        var indices: [Int] = []
        for (idx, provider) in allProviders.enumerated()
            where provider.providerID == providerID
        {
            indices.append(idx)
        }
        return indices
    }

    private static func linkageKey(_ linkage: ProviderAccountLinkage) -> String {
        let sorted = linkage.linkedIdentifiers.sorted()
        return "\(linkage.providerID)|\(sorted.joined(separator: ","))"
    }

    private static func latestNonNil<T>(
        _ entries: [ProviderUsageSnapshot],
        sourceDeviceIDs: [String],
        _ keyPath: KeyPath<ProviderUsageSnapshot, T?>) -> T?
    {
        precondition(entries.count == sourceDeviceIDs.count)
        return entries.indices
            .sorted { lhs, rhs in
                if entries[lhs].lastUpdated != entries[rhs].lastUpdated {
                    return entries[lhs].lastUpdated > entries[rhs].lastUpdated
                }
                return sourceDeviceIDs[lhs] > sourceDeviceIDs[rhs]
            }
            .first(where: { entries[$0][keyPath: keyPath] != nil })
            .flatMap { entries[$0][keyPath: keyPath] }
    }

    /// A pre-v0.41 Mac reports both Claude Max tiers as a generic label. During
    /// a rolling upgrade, keep the specific label from a v0.41+ Mac only when
    /// the freshest generic writer is provably old. A current or unknown-version
    /// generic value remains authoritative so a real plan change cannot go stale.
    private static func mergedLoginMethod(
        _ entries: [ProviderUsageSnapshot],
        sourceAppVersions: [String?],
        sourceDeviceIDs: [String]) -> String?
    {
        precondition(entries.count == sourceDeviceIDs.count)
        let newestNonNilIndex = entries.indices
            .sorted { lhs, rhs in
                if entries[lhs].lastUpdated != entries[rhs].lastUpdated {
                    return entries[lhs].lastUpdated > entries[rhs].lastUpdated
                }
                return sourceDeviceIDs[lhs] > sourceDeviceIDs[rhs]
            }
            .first(where: { entries[$0].loginMethod != nil })
        guard let newestNonNilIndex else { return nil }

        let latest = entries[newestNonNilIndex].loginMethod
        guard entries[newestNonNilIndex].providerID == "claude",
              latest == "Claude Max" || latest == "Max",
              let sourceVersion = sourceAppVersions[newestNonNilIndex],
              Self.semverLessThan(sourceVersion, "0.41.0")
        else {
            return latest
        }

        let specificMaxLabels: Set = ["Claude Max 5x", "Claude Max 20x"]
        return entries.indices
            .sorted { lhs, rhs in
                if entries[lhs].lastUpdated != entries[rhs].lastUpdated {
                    return entries[lhs].lastUpdated > entries[rhs].lastUpdated
                }
                return sourceDeviceIDs[lhs] > sourceDeviceIDs[rhs]
            }
            .compactMap { entries[$0].loginMethod }
            .first(where: specificMaxLabels.contains) ?? latest
    }

    /// Kimi, Claude, and Alibaba Token Plan added named lanes over several Mac
    /// releases. Preserve a lane supplied by any active writer while taking
    /// overlapping values from the freshest writer. Providers with fixed lane
    /// semantics then restore their canonical mobile order; Claude keeps
    /// freshest-writer order followed by missing lanes.
    private static func mergedRateWindows(
        _ entries: [ProviderUsageSnapshot],
        base: ProviderUsageSnapshot) -> [SyncRateWindow]
    {
        guard base.providerID == "kimi"
            || base.providerID == "claude"
            || base.providerID == "alibabatokenplan"
        else {
            return base.rateWindows
        }

        var merged = base.rateWindows
        var seenLabels = Set(merged.compactMap(Self.normalizedRateWindowLabel))
        for entry in entries.sorted(by: { $0.lastUpdated > $1.lastUpdated }) {
            for window in entry.rateWindows {
                guard let label = Self.normalizedRateWindowLabel(window),
                      seenLabels.insert(label).inserted
                else {
                    continue
                }
                merged.append(window)
            }
        }

        let preferredOrder: [String: Int]
        switch base.providerID {
        case "kimi":
            preferredOrder = [
                "weekly": 0,
                "rate limit": 1,
                "monthly": 2,
                "code 7-day": 3,
            ]
        case "alibabatokenplan":
            preferredOrder = [
                "5-hour": 0,
                "weekly": 1,
                "credits": 2,
            ]
        default:
            return merged
        }
        return merged.enumerated().sorted { lhs, rhs in
            let lhsRank = Self.normalizedRateWindowLabel(lhs.element)
                .flatMap { preferredOrder[$0] } ?? Int.max
            let rhsRank = Self.normalizedRateWindowLabel(rhs.element)
                .flatMap { preferredOrder[$0] } ?? Int.max
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.element)
    }

    /// A pre-v0.48 writer decodes the additive `details` field as an empty
    /// array, so it must not erase data from a newer Mac during a rolling
    /// upgrade. Conversely, an empty array emitted by a v0.48+ writer is an
    /// authoritative clear and must not revive stale detail cards.
    private static func mergedDetails(
        _ entries: [ProviderUsageSnapshot],
        sourceAppVersions: [String?],
        sourceDeviceIDs: [String]) -> [SyncProviderDetailSection]
    {
        precondition(entries.count == sourceAppVersions.count)
        precondition(entries.count == sourceDeviceIDs.count)

        let detailsCapableIndices = entries.indices.filter { index in
            if !entries[index].details.isEmpty {
                // Non-empty wire data proves capability even when legacy
                // records omitted or misreported the app version.
                return true
            }
            guard let sourceVersion = sourceAppVersions[index] else {
                return false
            }
            return !Self.semverLessThan(sourceVersion, "0.48.0")
        }

        return detailsCapableIndices.max { lhs, rhs in
            if entries[lhs].lastUpdated != entries[rhs].lastUpdated {
                return entries[lhs].lastUpdated < entries[rhs].lastUpdated
            }
            return sourceDeviceIDs[lhs] < sourceDeviceIDs[rhs]
        }.map { entries[$0].details } ?? []
    }

    private static func normalizedRateWindowLabel(_ window: SyncRateWindow) -> String? {
        guard let label = window.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty
        else {
            return nil
        }
        return label.lowercased()
    }

    private static func mergeProviderEntries(
        _ entries: [ProviderUsageSnapshot],
        sourceAppVersions: [String?],
        sourceDeviceIDs: [String],
        sourceSyncTimestamps: [Date],
        sumLocalCosts: Bool = true) -> ProviderUsageSnapshot
    {
        precondition(entries.count == sourceDeviceIDs.count)
        precondition(entries.count == sourceSyncTimestamps.count)
        let baseIndex = entries.indices.max { lhs, rhs in
            if entries[lhs].lastUpdated != entries[rhs].lastUpdated {
                return entries[lhs].lastUpdated < entries[rhs].lastUpdated
            }
            return sourceDeviceIDs[lhs] < sourceDeviceIDs[rhs]
        }!
        let base = entries[baseIndex]
        let isLocalCost = Self.usesLocalCostMerge(providerID: base.providerID)
        let costState: (summary: SyncCostSummary?, cleared: Bool?) = if isLocalCost, sumLocalCosts {
            if let summary = self.mergeCostSummaries(entries, sourceSyncTimestamps: sourceSyncTimestamps) {
                (summary, nil)
            } else {
                (nil, entries.contains(where: { $0.costSummaryCleared == true }) ? true : nil)
            }
        } else {
            Self.latestCostState(
                entries,
                sourceDeviceIDs: sourceDeviceIDs,
                sourceSyncTimestamps: sourceSyncTimestamps)
        }

        let mergedUtilization = Self.mergeUtilizationHistories(
            entries.compactMap(\.utilizationHistory))

        return ProviderUsageSnapshot(
            providerID: base.providerID,
            providerName: base.providerName,
            primary: base.primary,
            secondary: base.secondary,
            accountEmail: base.accountEmail,
            loginMethod: Self.mergedLoginMethod(
                entries,
                sourceAppVersions: sourceAppVersions,
                sourceDeviceIDs: sourceDeviceIDs),
            statusMessage: base.statusMessage,
            isError: base.isError,
            lastUpdated: base.lastUpdated,
            costSummary: costState.summary,
            costSummaryCleared: costState.cleared,
            budget: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.budget),
            subscriptionExpiresAt: Self.latestNonNil(
                entries, sourceDeviceIDs: sourceDeviceIDs, \.subscriptionExpiresAt),
            subscriptionRenewsAt: Self.latestNonNil(
                entries, sourceDeviceIDs: sourceDeviceIDs, \.subscriptionRenewsAt),
            rateWindows: Self.mergedRateWindows(entries, base: base),
            utilizationHistory: mergedUtilization,
            perplexityCredits: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.perplexityCredits),
            accountIdentities: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.accountIdentities),
            quotaWarnings: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.quotaWarnings),
            openAIAPIDashboard: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.openAIAPIDashboard),
            zaiHourlyUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.zaiHourlyUsage),
            kiroCredits: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.kiroCredits),
            bedrockCost: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.bedrockCost),
            moonshotBalance: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.moonshotBalance),
            antigravityAccounts: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.antigravityAccounts),
            grokBilling: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.grokBilling),
            elevenLabsCredits: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.elevenLabsCredits),
            deepgramUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.deepgramUsage),
            groqMetrics: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.groqMetrics),
            llmProxyStats: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.llmProxyStats),
            claudeAdminUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.claudeAdminUsage),
            claudeExtraUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.claudeExtraUsage),
            openCodeGoZenBalance: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.openCodeGoZenBalance),
            minimaxBilling: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.minimaxBilling),
            codexWorkspace: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.codexWorkspace),
            openRouterStats: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.openRouterStats),
            azureOpenAIInfo: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.azureOpenAIInfo),
            alibabaTokenPlan: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.alibabaTokenPlan),
            deepSeekUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.deepSeekUsage),
            codexResetCredits: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.codexResetCredits),
            usageDataConfidence: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.usageDataConfidence),
            crossModelUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.crossModelUsage),
            wayfinderUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.wayfinderUsage),
            sub2APIUsage: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.sub2APIUsage),
            providerAmount: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.providerAmount),
            accountRecordKey: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.accountRecordKey),
            accountOrganization: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.accountOrganization),
            zoomMateCredits: Self.latestNonNil(entries, sourceDeviceIDs: sourceDeviceIDs, \.zoomMateCredits),
            details: Self.mergedDetails(
                entries,
                sourceAppVersions: sourceAppVersions,
                sourceDeviceIDs: sourceDeviceIDs),
            providerIconMonogram: Self.latestNonNil(
                entries, sourceDeviceIDs: sourceDeviceIDs, \.providerIconMonogram),
            providerIconTintHex: Self.latestNonNil(
                entries, sourceDeviceIDs: sourceDeviceIDs, \.providerIconTintHex))
    }

    /// Select non-additive cost data by the cost source's own freshness.
    /// Provider `lastUpdated` describes the quota/usage card and can advance
    /// independently of billing data, so it must not decide which cost wins.
    private static func latestCostState(
        _ entries: [ProviderUsageSnapshot],
        sourceDeviceIDs: [String],
        sourceSyncTimestamps: [Date]) -> (summary: SyncCostSummary?, cleared: Bool?)
    {
        precondition(entries.count == sourceDeviceIDs.count)
        precondition(entries.count == sourceSyncTimestamps.count)
        let candidates = entries.indices.filter {
            entries[$0].costSummary != nil || entries[$0].costSummaryCleared == true
        }
        guard let winner = candidates.max(by: { lhs, rhs in
                let lhsFreshness = entries[lhs].costSummary?.sourceUpdatedAt
                    ?? sourceSyncTimestamps[lhs]
                let rhsFreshness = entries[rhs].costSummary?.sourceUpdatedAt
                    ?? sourceSyncTimestamps[rhs]
                if lhsFreshness != rhsFreshness {
                    return lhsFreshness < rhsFreshness
                }
                if sourceSyncTimestamps[lhs] != sourceSyncTimestamps[rhs] {
                    return sourceSyncTimestamps[lhs] < sourceSyncTimestamps[rhs]
                }
                return sourceDeviceIDs[lhs] < sourceDeviceIDs[rhs]
            })
        else { return (nil, nil) }
        // A contradictory entry fails closed: a clear tombstone is
        // authoritative over a simultaneously supplied legacy summary.
        guard entries[winner].costSummaryCleared != true else { return (nil, true) }
        return (entries[winner].costSummary, nil)
    }

    private static func mergeCostSummaries(
        _ providers: [ProviderUsageSnapshot],
        sourceSyncTimestamps: [Date]) -> SyncCostSummary?
    {
        precondition(providers.count == sourceSyncTimestamps.count)
        let sources = providers.indices.compactMap { index -> CostSummarySource? in
            let provider = providers[index]
            guard let summary = provider.costSummary else { return nil }
            return CostSummarySource(
                summary: summary,
                snapshotPublishedAt: sourceSyncTimestamps[index])
        }
        let summaries = sources.map(\.summary)
        guard !sources.isEmpty else { return nil }
        if summaries.count == 1 { return summaries[0] }

        let explicitBucketTimeZones = summaries.compactMap(\.bucketTimeZoneIdentifier)
        let dayBucketsAreCompatible = summaries.allSatisfy { !$0.hasInvalidBucketTimeZoneIdentifier } &&
            (explicitBucketTimeZones.isEmpty ||
                (explicitBucketTimeZones.count == summaries.count && Set(explicitBucketTimeZones).count == 1))
        let mergedBucketTimeZoneIdentifier = dayBucketsAreCompatible
            ? explicitBucketTimeZones.first
            : nil

        var dailyByKey: [String: DailyCostAccumulator] = [:]

        for summary in summaries {
            for point in summary.daily {
                dailyByKey[point.dayKey, default: .init(dayKey: point.dayKey)].ingest(point)
            }
        }

        // A modern source that is incomplete or older than its publishing
        // envelope cannot silently contribute an assumed zero for a day
        // reported by a sibling Mac. Preserve that missing-source uncertainty
        // on the merged day so every downstream consumer sees the same
        // lower-bound status. A complete, current modern source may omit a
        // zero-usage day, while a legacy nil keeps its historical behavior.
        let mergedDayKeys = Array(dailyByKey.keys)
        for source in sources {
            let summary = source.summary
            let reportedDayKeys = Set(summary.daily.map(\.dayKey))
            // `SyncedUsageSnapshot.syncTimestamp` is the actual publication
            // time. The provider usage timestamp is refreshed independently
            // and can be older than cost, so it is not a valid window anchor.
            // The producer's source date defines where its scanned window
            // starts. A later CloudKit publication only extends the interval
            // whose missing rows remain uncertain; it must not shift the
            // already-scanned window forward.
            let sourceAnchorKey = summary.sourceDayKey
                ?? summary.sourceUpdatedAt.map(summary.costDayKey)
                ?? summary.costDayKey(for: source.snapshotPublishedAt)
            let coverageEndKey = max(
                summary.costDayKey(for: source.snapshotPublishedAt),
                sourceAnchorKey)
            let coverageStartKey = Self.logicalDayKey(
                byAdding: -(max(1, min(summary.historyDays ?? 30, 365)) - 1),
                to: sourceAnchorKey) ?? sourceAnchorKey
            let sessionDayKey = summary.sessionDayKey
                ?? summary.sourceDayKey
                ?? summary.sourceUpdatedAt.map(summary.costDayKey)
            for dayKey in mergedDayKeys
                where dayKey >= coverageStartKey && dayKey <= coverageEndKey &&
                !reportedDayKeys.contains(dayKey)
            {
                // A non-nil session amount is the source's explicit Today
                // fallback. Fold it into the sibling's dated Today row so the
                // merged daily-preferred consumer retains both contributions.
                if dayKey == sessionDayKey,
                   summary.sessionCostIsKnown == true,
                   let sessionCost = summary.sessionCostUSD
                {
                    dailyByKey[dayKey]?.ingest(SyncDailyPoint(
                        dayKey: dayKey,
                        costUSD: sessionCost,
                        totalTokens: summary.sessionTokens ?? 0,
                        costIsKnown: true))
                    continue
                }
                let scanIsIncomplete = summary.historyCoverageIsEstablished == false
                let costSourceIsOlder = sessionDayKey.map { dayKey > $0 } ?? false
                if scanIsIncomplete || costSourceIsOlder {
                    dailyByKey[dayKey]?.ingestMissingIncompleteContribution()
                }
            }
        }

        let mergedDaily = dailyByKey.values
            .sorted { $0.dayKey < $1.dayKey }
            .map { $0.toDailyPoint(forceUnavailable: !dayBucketsAreCompatible) }

        let availableMergedDailyCost = mergedDaily.filter { $0.costIsKnown != false }
        let fallbackDailyCost = availableMergedDailyCost.isEmpty
            ? nil
            : availableMergedDailyCost.reduce(0) { $0 + $1.costUSD }
        let fallbackDailyTokens = mergedDaily.reduce(0) { $0 + $1.totalTokens }

        let windowCosts = summaries.compactMap { summary -> Double? in
            if let cost = summary.last30DaysCostUSD { return cost }
            let availableDaily = summary.daily.filter { $0.costIsKnown != false }
            return availableDaily.isEmpty ? nil : availableDaily.reduce(0) { $0 + $1.costUSD }
        }
        let windowTokens = summaries.compactMap { summary -> Int? in
            if let tokens = summary.last30DaysTokens { return tokens }
            return summary.daily.isEmpty ? nil : summary.daily.reduce(0) { $0 + $1.totalTokens }
        }
        let totalCost = windowCosts.isEmpty ? fallbackDailyCost : windowCosts.reduce(0, +)
        let totalTokens = windowTokens.isEmpty ? fallbackDailyTokens : windowTokens.reduce(0, +)

        let sessionFallback = Self.mergedSessionFallback(
            summaries,
            dayBucketsAreCompatible: dayBucketsAreCompatible)
        let windowRequests = summaries.compactMap(\.last30DaysRequests).reduce(0, +)
        // A missing historyDays is the legacy/default 30-day window. Normalize
        // it before comparison so old+new 30-day writers remain compatible,
        // while an explicit 7-day + 30-day fleet cannot certify completeness.
        let normalizedHistoryDays = summaries.map { max(1, min($0.historyDays ?? 30, 365)) }
        let historyWindowsAreCompatible = Set(normalizedHistoryDays).count == 1
        // Preserve a fully legacy nil label, but when mixed windows disagree,
        // report the widest normalized window instead of labelling a 30d + 7d
        // subtotal as a complete 7-day amount.
        let historyDays = historyWindowsAreCompatible
            ? summaries.compactMap(\.historyDays).max()
            : normalizedHistoryDays.max()
        let historyTotalsAreComparable = historyWindowsAreCompatible && dayBucketsAreCompatible
        let currencies = Set(summaries.compactMap(\.currencyCode))
        let currencyCode = currencies.count == 1 ? currencies.first : nil
        let hasCompleteProvenance = summaries.allSatisfy { $0.costProvenance != nil }
        let meteredCosts = summaries.compactMap(\.meteredCostUSD)
        let hasCompleteMeteredCost = meteredCosts.count == summaries.count
        let historyCoverageIsEstablished: Bool? = if !dayBucketsAreCompatible || summaries.contains(where: {
            $0.historyCoverageIsEstablished == false
        }) {
            false
        } else if summaries.allSatisfy({ $0.historyCoverageIsEstablished == true }) {
            true
        } else {
            nil
        }
        // The merged summary is only as fresh as its oldest dated source.
        // Keeping the minimum prevents a current sibling from hiding a stale
        // dashboard-only Mac. Producer day keys avoid re-bucketing those
        // sources in the iPhone's current time zone.
        let sourceUpdatedAt = summaries.compactMap(\.sourceUpdatedAt).min()
        let sourceDayKey = summaries.compactMap { summary in
            summary.sourceDayKey ?? summary.sourceUpdatedAt.map(summary.costDayKey)
        }.min()
        return SyncCostSummary(
            sessionCostUSD: sessionFallback.costUSD,
            sessionTokens: sessionFallback.tokens,
            last30DaysCostUSD: totalCost,
            last30DaysTokens: windowTokens.isEmpty && mergedDaily.isEmpty ? nil : totalTokens,
            daily: mergedDaily,
            isEstimated: summaries.contains(where: { $0.isEstimated == true }) ? true : nil,
            historyDays: historyDays,
            sessionRequests: sessionFallback.requests,
            last30DaysRequests: windowRequests > 0 ? windowRequests : nil,
            currencyCode: currencyCode,
            meteredCostUSD: !historyTotalsAreComparable || !hasCompleteProvenance || !hasCompleteMeteredCost
                ? nil
                : meteredCosts.reduce(0, +),
            costProvenance: Self.mergedCostProvenance(summaries),
            coverage: historyTotalsAreComparable ? Self.mergedCostCoverage(summaries) : nil,
            tokenMix: historyTotalsAreComparable ? Self.mergedCostTokenMix(summaries) : nil,
            sourceUpdatedAt: sourceUpdatedAt,
            sourceDayKey: sourceDayKey,
            sessionDayKey: sessionFallback.dayKey,
            bucketTimeZoneIdentifier: mergedBucketTimeZoneIdentifier,
            sessionCostIsKnown: sessionFallback.costIsKnown,
            historyCoverageIsEstablished: historyCoverageIsEstablished,
            historyWindowIsComparable: historyTotalsAreComparable)
    }

    /// Session fallback fields are local-day values, not timeless counters.
    /// Sum only sources from the newest represented cost day so an offline
    /// Mac's yesterday amount can never be relabelled as today's spend. Fully
    /// legacy inputs retain the pre-metadata behavior; a mixed dated/undated
    /// fleet is suppressed because its day alignment cannot be proven.
    private static func mergedSessionFallback(
        _ summaries: [SyncCostSummary],
        dayBucketsAreCompatible: Bool) -> (
        costUSD: Double?, tokens: Int?, requests: Int?, dayKey: String?, costIsKnown: Bool?)
    {
        let candidates = summaries.filter {
            $0.sessionCostUSD != nil || $0.sessionTokens != nil || $0.sessionRequests != nil
        }
        guard !candidates.isEmpty else { return (nil, nil, nil, nil, nil) }

        let dated = candidates.compactMap { summary -> (summary: SyncCostSummary, dayKey: String)? in
            guard let dayKey = summary.sessionDayKey
                ?? summary.sourceDayKey
                ?? summary.sourceUpdatedAt.map(summary.costDayKey)
            else { return nil }
            return (summary, dayKey)
        }
        let selected: [SyncCostSummary]
        let selectedDayKey: String?
        let allSourceDayKeys = summaries.compactMap { summary in
            summary.sourceDayKey
                ?? summary.sourceUpdatedAt.map(summary.costDayKey)
                ?? summary.daily.map(\.dayKey).max()
        }
        let hasUnalignedLegacySource = !allSourceDayKeys.isEmpty && allSourceDayKeys.count != summaries.count
        let hasOlderDatedSource: Bool
        if let newestDayKey = dated.map(\.dayKey).max() {
            selected = dated.filter { $0.dayKey == newestDayKey }.map(\.summary)
            selectedDayKey = newestDayKey
            // `sourceDayKey` can advance independently when a dashboard
            // refresh contributes cost rows while the token-backed session
            // remains on an older producer day. Both clocks must participate:
            // otherwise the older Mac's unresolved Today contribution can be
            // hidden behind equal, fresh source-day keys.
            hasOlderDatedSource = allSourceDayKeys.contains { $0 != newestDayKey } ||
                dated.contains { $0.dayKey != newestDayKey }
        } else {
            selected = candidates
            selectedDayKey = nil
            hasOlderDatedSource = false
        }

        let costs = selected.compactMap(\.sessionCostUSD)
        let tokens = selected.compactMap(\.sessionTokens)
        let requests = selected.compactMap(\.sessionRequests)
        let costIsKnown: Bool? = if !dayBucketsAreCompatible || hasUnalignedLegacySource ||
            hasOlderDatedSource || selected.contains(where: {
                $0.sessionCostIsKnown == false
            })
        {
            false
        } else if !costs.isEmpty, selected.allSatisfy({ $0.sessionCostIsKnown == true }) {
            true
        } else {
            nil
        }
        return (
            costs.isEmpty ? nil : costs.reduce(0, +),
            tokens.isEmpty ? nil : tokens.reduce(0, +),
            requests.isEmpty ? nil : requests.reduce(0, +),
            selectedDayKey,
            costIsKnown)
    }

    private static func mergedCostProvenance(_ summaries: [SyncCostSummary]) -> SyncCostProvenance? {
        let values = summaries.compactMap(\.costProvenance)
        guard !values.isEmpty, values.count == summaries.count else { return nil }
        if values.contains(.unknown) { return .unknown }
        if values.contains(.mixed) { return .mixed }
        return Set(values).count == 1 ? values.first : .mixed
    }

    private static func mergedCostCoverage(_ summaries: [SyncCostSummary]) -> SyncCostCoverage? {
        let values = summaries.compactMap(\.coverage)
        guard !values.isEmpty, values.count == summaries.count else { return nil }
        return SyncCostCoverage(
            priced: SyncCounterMath.saturatingSum(values.map(\.priced)),
            unpriced: SyncCounterMath.saturatingSum(values.map(\.unpriced)),
            unmetered: SyncCounterMath.saturatingSum(values.map(\.unmetered)),
            estimated: SyncCounterMath.saturatingSum(values.map(\.estimated)))
    }

    private static func mergedCostTokenMix(_ summaries: [SyncCostSummary]) -> SyncCostTokenMix? {
        // Do not manufacture a zero-valued mix when every source is idle.
        // At least one writer must have reported an actual token class.
        guard summaries.contains(where: { $0.tokenMix?.hasAnyValue == true }) else { return nil }

        func sum(_ keyPath: KeyPath<SyncCostTokenMix, Int?>) -> Int? {
            let contributions = summaries.compactMap { summary -> Int? in
                if let value = summary.tokenMix?[keyPath: keyPath] { return value }
                // A modern writer that established an empty token window is a
                // known-zero contribution, not missing legacy metadata.
                if summary.historyCoverageIsEstablished == true,
                   summary.last30DaysTokens == 0
                {
                    return 0
                }
                return nil
            }
            guard contributions.count == summaries.count else { return nil }
            return SyncCounterMath.saturatingSum(contributions)
        }

        let result = SyncCostTokenMix(
            inputTokens: sum(\.inputTokens),
            outputTokens: sum(\.outputTokens),
            cacheReadTokens: sum(\.cacheReadTokens),
            cacheCreationTokens: sum(\.cacheCreationTokens),
            reasoningTokens: sum(\.reasoningTokens))
        return result.hasAnyValue ? result : nil
    }

    private struct CostSummarySource {
        let summary: SyncCostSummary
        let snapshotPublishedAt: Date
    }

    private static func logicalDayKey(byAdding days: Int, to dayKey: String) -> String? {
        let formatter = self.logicalDayFormatter()
        guard let date = formatter.date(from: dayKey),
              let shifted = formatter.calendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return formatter.string(from: shifted)
    }

    private static func logicalDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Day keys are logical producer dates. UTC makes day arithmetic stable
        // without reinterpreting them in the iPhone's current time zone.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private struct DailyCostAccumulator {
        let dayKey: String
        var costUSD: Double = 0
        var totalTokens: Int = 0
        var modelBreakdowns: [String: CostBreakdownAccumulator] = [:]
        var serviceBreakdowns: [String: CostBreakdownAccumulator] = [:]
        var isEstimated = false
        var sawKnownCost = false
        var sawUnknownCost = false
        var sawUnavailableCost = false

        mutating func ingest(_ point: SyncDailyPoint) {
            self.costUSD += point.costUSD
            self.totalTokens += point.totalTokens
            if point.isEstimated == true {
                self.isEstimated = true
            }
            switch point.costIsKnown {
            case true: self.sawKnownCost = true
            case false: self.sawUnavailableCost = true
            case nil: self.sawUnknownCost = true
            }
            for breakdown in point.modelBreakdowns {
                self.modelBreakdowns[breakdown.label, default: .init()].ingest(breakdown)
            }
            for breakdown in point.serviceBreakdowns {
                self.serviceBreakdowns[breakdown.label, default: .init()].ingest(breakdown)
            }
        }

        mutating func ingestMissingIncompleteContribution() {
            self.sawUnavailableCost = true
        }

        func toDailyPoint(forceUnavailable: Bool = false) -> SyncDailyPoint {
            SyncDailyPoint(
                dayKey: self.dayKey,
                costUSD: self.costUSD,
                totalTokens: self.totalTokens,
                modelBreakdowns: Self.sortedBreakdowns(self.modelBreakdowns),
                serviceBreakdowns: Self.sortedBreakdowns(self.serviceBreakdowns),
                isEstimated: self.isEstimated ? true : nil,
                costIsKnown: forceUnavailable ? false : self.mergedCostIsKnown)
        }

        private var mergedCostIsKnown: Bool? {
            if self.sawUnavailableCost { return false }
            if self.sawUnknownCost { return nil }
            return self.sawKnownCost ? true : nil
        }

        private static func sortedBreakdowns(
            _ values: [String: CostBreakdownAccumulator]) -> [SyncCostBreakdown]
        {
            values
                .map { label, accumulator in accumulator.toBreakdown(label: label) }
                .sorted { lhs, rhs in
                    if lhs.costUSD == rhs.costUSD {
                        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    }
                    return lhs.costUSD > rhs.costUSD
                }
        }
    }

    private struct CostBreakdownAccumulator {
        var costUSD: Double = 0
        var isEstimated = false
        var standardCostUSD: Double = 0
        var priorityCostUSD: Double = 0
        var standardTokens: Int = 0
        var priorityTokens: Int = 0
        var hasStandardCost = false
        var hasPriorityCost = false
        var hasStandardTokens = false
        var hasPriorityTokens = false

        mutating func ingest(_ breakdown: SyncCostBreakdown) {
            self.costUSD += breakdown.costUSD
            if breakdown.isEstimated == true {
                self.isEstimated = true
            }
            if let value = breakdown.standardCostUSD {
                self.standardCostUSD += value
                self.hasStandardCost = true
            }
            if let value = breakdown.priorityCostUSD {
                self.priorityCostUSD += value
                self.hasPriorityCost = true
            }
            if let value = breakdown.standardTokens {
                self.standardTokens += value
                self.hasStandardTokens = true
            }
            if let value = breakdown.priorityTokens {
                self.priorityTokens += value
                self.hasPriorityTokens = true
            }
        }

        func toBreakdown(label: String) -> SyncCostBreakdown {
            SyncCostBreakdown(
                label: label,
                costUSD: self.costUSD,
                isEstimated: self.isEstimated ? true : nil,
                standardCostUSD: self.hasStandardCost ? self.standardCostUSD : nil,
                priorityCostUSD: self.hasPriorityCost ? self.priorityCostUSD : nil,
                standardTokens: self.hasStandardTokens ? self.standardTokens : nil,
                priorityTokens: self.hasPriorityTokens ? self.priorityTokens : nil)
        }
    }

    private static func mergeUtilizationHistories(
        _ histories: [[SyncUtilizationSeries]]) -> [SyncUtilizationSeries]?
    {
        let allSeries = histories.flatMap(\.self)
        guard !allSeries.isEmpty else { return nil }

        var entriesByName: [String: [SyncUtilizationEntry]] = [:]
        var freshestWindowByName: [String: (capturedAt: Date, windowMinutes: Int)] = [:]

        for series in allSeries {
            entriesByName[series.name, default: []].append(contentsOf: series.entries)
            if let latestCaptured = series.entries.map(\.capturedAt).max() {
                let current = freshestWindowByName[series.name]
                if current == nil || latestCaptured > current!.capturedAt {
                    freshestWindowByName[series.name] = (latestCaptured, series.windowMinutes)
                }
            } else if freshestWindowByName[series.name] == nil {
                freshestWindowByName[series.name] = (.distantPast, series.windowMinutes)
            }
        }

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

        result.sort { lhs, rhs in
            let order = ["session": 0, "weekly": 1, "opus": 2]
            return (order[lhs.name] ?? 99) < (order[rhs.name] ?? 99)
        }

        return result.isEmpty ? nil : result
    }

    private static func dedupByHour(_ entries: [SyncUtilizationEntry]) -> [SyncUtilizationEntry] {
        guard !entries.isEmpty else { return [] }

        let hourInterval: TimeInterval = 3600

        struct BucketKey: Hashable {
            let hourSlot: Int
            let resetEpoch: Int
        }

        var buckets: [BucketKey: (totalPercent: Double, count: Int, latestReset: Date?, latestCaptured: Date)] = [:]

        for entry in entries {
            let hourSlot = Int(floor(entry.capturedAt.timeIntervalSince1970 / hourInterval))
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
}

private struct MergeUnionFind {
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
