import CodexBarSync
import Foundation

/// Actual account/window observations only. No rate extrapolation or synthetic cycle endpoints.
enum UsageQuotaProjection {
    static func catalog(
        accounts: [ProviderUsageSnapshot],
        preferences: UsageQuotaPreferences) -> [UsageQuotaCandidate]
    {
        let bindings = SummaryCardResolver.accountBindings(
            accounts: accounts,
            preferences: preferences.identityPreferences)
        return SummaryCardResolver.catalog(accounts: accounts, preferences: preferences.identityPreferences)
            .compactMap { item in
                guard case let .quota(windowID) = item.metric, item.supportsCountdown else { return nil }
                return UsageQuotaCandidate(
                    providerID: item.providerID, providerName: item.providerName,
                    accountAnchorID: item.accountAnchorID, windowID: windowID,
                    accountTitle: item.accountTitle, metricTitle: item.metricTitle,
                    providerTintHex: bindings
                        .first { $0.0 == item.accountAnchorID && $0.1.providerID == item.providerID }?
                        .1.providerIconTintHex)
            }
    }

    static func overview(
        accounts: [ProviderUsageSnapshot], preferences: UsageQuotaPreferences,
        histories: [UsageQuotaHistory], linkages: [ProviderAccountLinkage],
        sourceSnapshots: [SyncedUsageSnapshot]? = nil,
        quotaSources: [String: SyncProviderQuotaSource]? = nil, now: Date) -> UsageQuotaOverview
    {
        var summary = preferences.identityPreferences
        summary.cards = preferences.selections.map { selection in
            SummaryCardConfiguration(
                id: selection.id, accountAnchorID: selection.accountAnchorID,
                providerID: selection.providerID, metric: .quota(windowID: selection.windowID),
                accountTitle: selection.accountTitle, metricTitle: selection.metricTitle)
        }
        let resolved = SummaryCardResolver.resolve(
            accounts: accounts, preferences: summary, linkages: linkages, now: now)
        let bindings = SummaryCardResolver.accountBindings(accounts: accounts, preferences: summary)
        let lines = zip(preferences.selections, resolved).map { selection, mergedCard in
            let card = UsageQuotaSourceResolver.resolve(
                mergedCard, sourceSnapshots: sourceSnapshots, quotaSources: quotaSources, now: now)
            let canonical = bindings
                .first { $0.0 == selection.accountAnchorID && $0.1.providerID == selection.providerID }
            // A linkage may make an old selection resolve to a different canonical account. Its
            // previous local history must not be transplanted to that account's current quota.
            let owner = card.provider.flatMap {
                self.historyOwner(
                    $0, anchorID: selection.accountAnchorID, accounts: accounts,
                    preferences: preferences, linkages: linkages)
            }
            let storedHistory = histories.first { $0.binding == selection.binding }
            let verifiedOwner = storedHistory.map {
                self.historyMatchesAnchor($0, preferences: preferences) && self.history($0, isOwnedBy: owner)
            } == true
            let history = canonical == nil || owner == nil || !verifiedOwner ? [] : storedHistory?.observations ?? []
            let singleProviderAccount = accounts.filter { $0.providerID == selection.providerID }.count == 1
            let synced = canonical == nil || owner == nil || !singleProviderAccount ? [] : self.syncedObservations(
                card: card, windowID: selection.windowID,
                sourceSnapshots: sourceSnapshots, quotaSources: quotaSources, now: now)
            // Local receipts supersede an older synced value at the same timestamp. The
            // current authoritative source reading is applied last by observedSamples.
            // A conflicting provider-wide sample must not erase verified local receipts
            // through the replenishment/decreasing-usage reset rule below.
            let compatibleSynced = synced.filter { sample in
                !history.contains { local in
                    abs(local.resetDate.timeIntervalSince(sample.resetDate)) <= 120
                        && local.windowDuration == sample.windowDuration
                        && ((local.capturedAt < sample.capturedAt && local.usedPercent > sample.usedPercent)
                            || (local.capturedAt > sample.capturedAt && local.usedPercent < sample.usedPercent))
                }
            }
            var combined = Dictionary(
                compatibleSynced.map { ($0.capturedAt, $0) },
                uniquingKeysWith: { _, latest in latest })
            for observation in history {
                combined[observation.capturedAt] = observation
            }
            let samples = self.observedSamples(card: card, observations: Array(combined.values), now: now)
            return UsageQuotaResolvedLine(
                selection: selection, provider: card.provider, accountTitle: card.accountTitle,
                compactAccountTitle: card.compactAccountTitle, privateAccountTitle: card.privateAccountTitle,
                metricTitle: card.metricTitle, state: card.state, isStale: card.isStale,
                currentRemainingPercent: card.usedPercent.map { 100 - $0 },
                observedAt: card.observedAt, resetDate: card.resetDate,
                observedSamples: samples, localObservationCount: history.count,
                usesSyncedProviderHistory: compatibleSynced.contains { $0.capturedAt < (card.observedAt ?? now) })
        }
        // The calendar is shared by all providers, not resized to selected lines or
        // this iPhone's available samples. The nearest future valid Weekly reset anchors it.
        // Keep the full seven-day validity bound even though the displayed span is six days.
        let week: TimeInterval = 7 * 86400
        let resets = accounts.flatMap { account -> [Date] in
            guard !account.isError, account.sourceReport?.allFailed != true else { return [] }
            return QuotaPaceWindowSelection.candidates(for: account).compactMap { candidate in
                guard let evidence = UsageQuotaSourceResolver.evidence(
                    account: account, windowID: candidate.id,
                    sourceSnapshots: sourceSnapshots, quotaSources: quotaSources),
                    !evidence.account.isError, evidence.account.sourceReport?.allFailed != true,
                    evidence.capturedAt <= now,
                    now.timeIntervalSince(evidence.capturedAt) <= ProviderSourceStatus.staleInterval,
                    QuotaPaceWindowSelection.isWeekly(evidence.window, observedAt: evidence.capturedAt)
                else { return nil }
                let window = evidence.window
                guard window.usageKnown, window.usedPercent.isFinite, window.usedPercent >= 0,
                      window.blockingQuota == nil, let reset = window.resetsAt,
                      reset.timeIntervalSince1970.isFinite, reset > now,
                      reset.timeIntervalSince(now) <= week else { return nil }
                return reset
            }
        }
        let end = resets.min() ?? now
        return UsageQuotaOverview(start: end.addingTimeInterval(-6 * 86400), end: end, lines: lines)
    }

    static func hasUnambiguousHistorySource(
        _ account: ProviderUsageSnapshot, anchorID: String, preferences: UsageQuotaPreferences,
        linkages: [ProviderAccountLinkage]) -> Bool
    {
        let stable = UsageAccountIdentity.tokens(for: account).filter(UsageAccountIdentity.isStable)
        guard !stable.isEmpty else { return false }
        let identifiers = Set(ProviderSnapshotMerger.effectiveIdentifiers(for: account))
        var reachable = identifiers
        var remainingLinks = UsageCardLinkages.effective(linkages).filter { $0.providerID == account.providerID }
        var affectedLinks: [ProviderAccountLinkage] = []
        // Weak aliases also connect links. A second known owner reached through an
        // anonymous/record/card alias is just as ambiguous as a direct account linkage.
        while let index = remainingLinks.firstIndex(where: { !reachable.isDisjoint(with: $0.linkedIdentifiers) }) {
            let link = remainingLinks.remove(at: index)
            affectedLinks.append(link)
            reachable.formUnion(link.linkedIdentifiers)
        }
        if !affectedLinks.isEmpty {
            // Old anonymous publications may be linked to one known owner. They must not
            // disable that owner's real sampling; the source resolver still rejects anonymous
            // writers as proof of a named account. Two distinct stable owners remain ambiguous.
            let owners = Set(affectedLinks.flatMap(\.linkedIdentifiers).filter {
                UsageAccountIdentity.isStable($0) && $0 != "\(account.providerID):legacy-no-identity"
            })
            guard owners.count == 1, owners.isSubset(of: stable) else { return false }
        }
        let matches = preferences.accountAnchors.filter {
            $0.providerID == account.providerID
                && !stable.isDisjoint(with: $0.tokens.filter(UsageAccountIdentity.isStable))
        }
        return matches.count == 1 && matches.first?.id == anchorID
    }

    /// The proof a new observation of this account is stored under, or nil when its samples
    /// cannot be attributed to one account. Weak record slots stay excluded: a reusable
    /// credential slot can hold a different account between readings.
    static func historyOwner(
        _ account: ProviderUsageSnapshot, anchorID: String, accounts: [ProviderUsageSnapshot],
        preferences: UsageQuotaPreferences, linkages: [ProviderAccountLinkage]) -> UsageQuotaHistoryOwner?
    {
        if self.hasUnambiguousHistorySource(account, anchorID: anchorID, preferences: preferences, linkages: linkages) {
            let stable = preferences.accountAnchors.first { $0.id == anchorID }?
                .tokens.filter(UsageAccountIdentity.isStable).sorted() ?? []
            return stable.isEmpty ? nil : .stable(stable)
        }
        return self.anonymousSingletonToken(
            account, anchorID: anchorID, accounts: accounts, preferences: preferences, linkages: linkages)
            .map(UsageQuotaHistoryOwner.anonymousSingleton)
    }

    /// Card key of a provider's only account when it carries no identity at all, such as Grok
    /// read through browser cookies. A second account of the provider, any linkage involving
    /// the provider, or an anchor that once learned a stable owner withdraws the proof.
    static func anonymousSingletonToken(
        _ account: ProviderUsageSnapshot, anchorID: String, accounts: [ProviderUsageSnapshot],
        preferences: UsageQuotaPreferences, linkages: [ProviderAccountLinkage]) -> String?
    {
        let tokens = UsageAccountIdentity.tokens(for: account)
        guard tokens.count == 1, let token = tokens.first, token.hasPrefix("\(account.providerID):card:"),
              accounts.filter({ $0.providerID == account.providerID }).count == 1,
              !UsageCardLinkages.effective(linkages).contains(where: { $0.providerID == account.providerID }),
              let anchor = preferences.accountAnchors.first(where: {
                  $0.id == anchorID && $0.providerID == account.providerID
              }),
              !anchor.tokens.contains(where: UsageAccountIdentity.isStable), anchor.tokens.contains(token)
        else { return nil }
        return token
    }

    static func historyMatchesAnchor(_ history: UsageQuotaHistory, preferences: UsageQuotaPreferences) -> Bool {
        guard let anchor = preferences.accountAnchors.first(where: {
            $0.id == history.binding.accountAnchorID && $0.providerID == history.binding.providerID
        }) else { return false }
        let stable = Set(anchor.tokens.filter(UsageAccountIdentity.isStable))
        if let token = history.anonymousSingletonToken {
            return stable.isEmpty && history.stableAccountTokens == nil && anchor.tokens.contains(token)
        }
        return !stable.isEmpty && Set(history.stableAccountTokens ?? []) == stable
    }

    /// Whether the stored stream was recorded under the same kind of owner as the current reading.
    /// Stable token equality itself is established by `historyMatchesAnchor`.
    static func history(_ history: UsageQuotaHistory, isOwnedBy owner: UsageQuotaHistoryOwner?) -> Bool {
        switch owner {
        case .stable: history.stableAccountTokens != nil && history.anonymousSingletonToken == nil
        case let .anonymousSingleton(token): history.anonymousSingletonToken == token
        case nil: false
        }
    }

    static func duration(window: SyncRateWindow, providerID: String, capturedAt: Date) -> TimeInterval? {
        if let duration = QuotaPace.duration(of: window, providerID: providerID, capturedAt: capturedAt) {
            return duration
        }
        guard let minutes = window.windowMinutes, minutes > 0, minutes < 1440 else { return nil }
        return Double(minutes) * 60
    }

    /// Read-only provider history, matching the detail chart's legacy wire semantics.
    /// The raw writer proves the current reading, NOT ownership of historical entries:
    /// legacy producers can attach provider-wide history to an account publication.
    /// Never persist these entries as verified local account observations, and suppress
    /// them when multiple known accounts or conflicting current writers make attribution ambiguous.
    private static func syncedObservations(
        card: SummaryResolvedCard, windowID: String,
        sourceSnapshots: [SyncedUsageSnapshot]?, quotaSources: [String: SyncProviderQuotaSource]?, now: Date)
        -> [UsageQuotaObservation]
    {
        guard card.state == .available, !card.isStale, let account = card.provider,
              let evidence = UsageQuotaSourceResolver.evidence(
                  account: account, windowID: windowID,
                  sourceSnapshots: sourceSnapshots, quotaSources: quotaSources),
              evidence.capturedAt == card.observedAt,
              let lane = MobileQuotaBurndown.nativeLanes(for: evidence.account).first(where: {
                  $0.window == evidence.window
              }),
              let series = evidence.account.utilizationHistory?.filter({
                  $0.name == lane.seriesName && $0.windowMinutes == evidence.window.windowMinutes
              }), series.count == 1,
              let model = MobileQuotaBurndown(
                  series: series[0], window: evidence.window,
                  capturedAt: evidence.capturedAt, referenceDate: now),
              let duration = self.duration(
                  window: evidence.window, providerID: account.providerID, capturedAt: evidence.capturedAt)
        else { return [] }
        // Equal-time writers can agree on current quota while disagreeing on history.
        // Do not let source array order choose which historical curve is presented.
        if let sourceSnapshots {
            let stable = UsageAccountIdentity.tokens(for: evidence.account).filter(UsageAccountIdentity.isStable)
            let conflictingOwner = sourceSnapshots.flatMap(\.providers).contains { raw in
                guard raw.providerID == account.providerID else { return false }
                let rawStable = UsageAccountIdentity.tokens(for: raw).filter(UsageAccountIdentity.isStable)
                return !rawStable.isEmpty && stable.isDisjoint(with: rawStable)
            }
            guard !conflictingOwner else { return [] }
            for snapshot in sourceSnapshots {
                guard let peer = UsageQuotaSourceResolver.evidence(
                    account: account, windowID: windowID,
                    sourceSnapshots: [snapshot], quotaSources: quotaSources),
                    peer.capturedAt == evidence.capturedAt, !peer.account.isError else { continue }
                let peerSeries = peer.account.utilizationHistory?.filter {
                    $0.name == lane.seriesName && $0.windowMinutes == evidence.window.windowMinutes
                } ?? []
                guard peerSeries == series else { return [] }
            }
        }
        return model.samples.map {
            UsageQuotaObservation(
                capturedAt: $0.date, usedPercent: 100 - $0.remainingPercent,
                resetDate: model.reset, windowDuration: duration, startsSegment: false)
        }
    }

    private static func observedSamples(
        card: SummaryResolvedCard, observations: [UsageQuotaObservation], now: Date) -> [UsageQuotaPoint]
    {
        guard card.state == .available, !card.isStale,
              let window = card.window, let used = card.usedPercent,
              let captured = card.observedAt, let reset = card.resetDate,
              let provider = card.provider, captured <= now, captured < reset, now < reset
        else { return [] }
        let duration = self.duration(window: window, providerID: provider.providerID, capturedAt: captured)
        let cycleStart = duration.map { reset.addingTimeInterval(-$0) }
        var compatible = observations.filter {
            $0.capturedAt <= captured && abs($0.resetDate.timeIntervalSince(reset)) <= 120
                && $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                && $0.windowDuration == duration
                && (cycleStart == nil || $0.capturedAt >= cycleStart!)
        }.sorted { $0.capturedAt < $1.capturedAt }
        // The current source reading is itself an observation, including when no prior
        // account-owned history is available. Its timestamp must never be moved to now.
        let storedCurrent = compatible.last { $0.capturedAt == captured }
        let latestContinuity = storedCurrent?.startsSegment
        if let storedCurrent, used < storedCurrent.usedPercent { compatible.removeAll() }
        compatible.removeAll { $0.capturedAt == captured }
        compatible.append(UsageQuotaObservation(
            capturedAt: captured, usedPercent: used, resetDate: reset,
            windowDuration: duration, startsSegment: latestContinuity))
        var samples: [UsageQuotaPoint] = []
        var previous: UsageQuotaObservation?
        var segment = 0
        let maximumGap = UsageQuotaObservation.maximumContinuousGap(windowDuration: duration)
        for observation in compatible {
            if let previous {
                // A replenishment/correction starts a new cycle even if the reset date is unchanged.
                if observation.usedPercent < previous.usedPercent { samples.removeAll(); segment = 0 }
                else if observation.startsSegment == true ||
                    (observation.startsSegment == nil
                        && observation.capturedAt.timeIntervalSince(previous.capturedAt) > maximumGap) { segment += 1 }
                if observation.capturedAt == previous.capturedAt, !samples.isEmpty { samples.removeLast() }
            }
            samples.append(UsageQuotaPoint(
                date: observation.capturedAt, remainingPercent: 100 - observation.usedPercent, segment: segment))
            previous = observation
        }
        return samples
    }
}
