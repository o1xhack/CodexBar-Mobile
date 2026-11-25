import CodexBarSync
import Foundation

/// Pure data projection shared by the picker and the board; does not touch CloudKit or credentials.
enum SummaryCardResolver {
    static func accountBindings(
        accounts: [ProviderUsageSnapshot],
        preferences: SummaryPreferences) -> [(String, ProviderUsageSnapshot)]
    {
        var identity = UsageCardPreferences()
        identity.accountAnchors = preferences.accountAnchors
        return accounts.groupedByProvider().flatMap { group in
            zip(identity.anchorIDs(forAccounts: group.accounts), group.accounts).map { ($0, $1) }
        }
    }

    static func catalog(
        accounts: [ProviderUsageSnapshot],
        preferences: SummaryPreferences,
        now _: Date = .now) -> [SummaryMetricCandidate]
    {
        self.accountBindings(accounts: accounts, preferences: preferences).flatMap { anchorID, account in
            let accountTitle = self.accountTitle(
                account,
                anchorID: anchorID,
                preferences: preferences,
                accounts: accounts)
            func candidate(_ metric: SummaryCardMetric, title: String, countdown: Bool = false)
                -> SummaryMetricCandidate
            {
                SummaryMetricCandidate(
                    accountAnchorID: anchorID,
                    providerID: account.providerID,
                    providerName: self.providerName(account),
                    accountTitle: accountTitle,
                    metric: metric,
                    metricTitle: title,
                    supportsCountdown: countdown)
            }
            var result: [SummaryMetricCandidate] = []
            for window in QuotaPaceWindowSelection.candidates(for: account) {
                let title = QuotaPaceWindowSelection.title(of: window, providerID: account.providerID)
                let reset = window.window.resetsAt.map(\.timeIntervalSince1970.isFinite) == true
                result.append(candidate(.quota(windowID: window.id), title: title, countdown: reset))
                // Offer only windows supported by the existing forecast engine, even when a
                // temporary failure/expired observation prevents a forecast right now.
                if reset, QuotaPace.allowsPace(for: account),
                   QuotaPace.duration(
                       of: window.window, providerID: account.providerID, capturedAt: self.quotaCapturedAt(account)) !=
                   nil
                {
                    let format = String(localized: "Estimated depletion · %@")
                    result.append(candidate(
                        .depletion(windowID: window.id), title: String(format: format, title)))
                }
            }
            if self.balance(for: account) != nil { result.append(candidate(
                .balance,
                title: String(localized: "Balance"))) }
            if account.claudeExtraUsage != nil {
                result.append(candidate(.extraUsage, title: String(localized: "Extra usage")))
            }
            return result
        }
    }

    static func defaultCandidates(
        _ candidates: [SummaryMetricCandidate],
        accounts: [ProviderUsageSnapshot],
        preferences: SummaryPreferences,
        now: Date) -> [SummaryMetricCandidate]
    {
        var result: [SummaryMetricCandidate] = []
        for (anchorID, account) in self.accountBindings(accounts: accounts, preferences: preferences)
            where !account.isError && account.sourceReport?.allFailed != true
        {
            let windows = QuotaPaceWindowSelection.candidates(for: account)
            let current = windows.filter {
                QuotaPaceWindowSelection.remainingPercent(of: $0.window, now: now) != nil
                    && $0.window.blockingQuota == nil
            }
            let session = current.first {
                $0.window.period == .session || ($0.window.windowMinutes.map { $0 > 0 && $0 < 1440 } == true)
            }
            let weekly = current.first {
                QuotaPaceWindowSelection.isWeekly($0.window, observedAt: self.quotaCapturedAt(account))
                    && QuotaPaceWindowSelection.isAccountWeeklyCandidate($0, providerID: account.providerID)
            }
            var selectedIDs = [session?.id, weekly?.id].compactMap(\.self)
            if selectedIDs.isEmpty, let first = current.first { selectedIDs = [first.id] }
            let accountCandidates = candidates.filter { candidate in
                candidate.providerID == account.providerID && candidate.accountAnchorID == anchorID
            }
            for id in selectedIDs {
                if let candidate = accountCandidates.first(where: { $0.metric == .quota(windowID: id) }),
                   !result.contains(where: { $0.id == candidate.id })
                {
                    result.append(candidate)
                }
            }
            if result.count >= 6 { return Array(result.prefix(6)) }
        }
        if result.isEmpty {
            return Array(candidates.filter {
                if case .balance = $0.metric {
                    true
                } else {
                    false
                }
            }.prefix(2))
        }
        return result
    }

    static func resolve(
        accounts: [ProviderUsageSnapshot], preferences: SummaryPreferences,
        linkages: [ProviderAccountLinkage] = [], now: Date = .now) -> [SummaryResolvedCard]
    {
        let bindings = self.accountBindings(accounts: accounts, preferences: preferences)
        let candidates = self.catalog(accounts: accounts, preferences: preferences, now: now)
        return preferences.cards.map { configuration in
            let account = bindings.first {
                $0.0 == configuration.accountAnchorID && $0.1.providerID == configuration.providerID
            }?.1 ?? self.bridgedAccount(
                configuration, accounts: accounts, preferences: preferences, linkages: linkages)
            let candidate = candidates.first {
                $0.accountAnchorID == configuration.accountAnchorID && $0.providerID == configuration.providerID
                    && $0.metric == configuration.metric
            } ?? account.flatMap { account in
                let canonicalAnchor = bindings.first { $0.1 == account }?.0
                return candidates.first {
                    $0.accountAnchorID == canonicalAnchor && $0.providerID == configuration.providerID
                        && $0.metric == configuration.metric
                }
            }
            var window: SyncRateWindow?
            var usedPercent: Double?
            var reset: Date?
            var forecast: QuotaPace.Forecast?
            var amount: SummaryCardAmount?
            var observedAt = account.map(self.quotaCapturedAt)
            var state: SummaryCardState = account == nil ? .missingAccount : .available
            if let account {
                switch configuration.metric {
                case let .quota(windowID), let .depletion(windowID):
                    window = QuotaPaceWindowSelection.candidates(for: account)
                        .first(where: { $0.id == windowID })?.window
                    if let window {
                        let presentation = UsageWindowPresentation(window: window)
                        reset = presentation.resetDate
                        if presentation.isBlocked { state = .blocked }
                        else if !window.usageKnown || !window.usedPercent.isFinite || window.usedPercent < 0 {
                            state = .unknown
                        } else if presentation.hasExpiredObservation(at: now) { state = .resetPassed }
                        else {
                            usedPercent = min(100, window.usedPercent)
                            if case .depletion = configuration.metric {
                                if QuotaPace.allowsPace(for: account) {
                                    forecast = QuotaPace(
                                        window: window, capturedAt: self.quotaCapturedAt(account),
                                        referenceDate: now, providerID: account.providerID)?.forecast
                                }
                                if forecast == nil { state = .unavailable }
                            }
                        }
                    } else { state = .missingMetric }
                case .balance:
                    amount = self.balance(for: account)
                    observedAt = amount?.observedAt
                    if amount == nil { state = .missingMetric }
                    else if amount?.value.isFinite != true { state = .unknown; amount = nil }
                case .extraUsage:
                    if let extra = account.claudeExtraUsage {
                        observedAt = extra.updatedAt
                        if !extra.isEnabled { state = .disabled }
                        else {
                            let limit = extra.monthlyLimitUSD
                            let fraction = extra.utilization ?? limit.flatMap { limit in
                                guard limit.isFinite, limit > 0, let spend = extra.monthlySpendUSD else { return nil }
                                return spend / limit * 100
                            }
                            if let fraction, fraction.isFinite, fraction >= 0 { usedPercent = min(100, fraction) }
                            if let spend = extra.monthlySpendUSD, spend.isFinite {
                                amount = SummaryCardAmount(
                                    value: spend, currencyCode: "USD", observedAt: extra.updatedAt, isEstimated: false)
                            }
                            if usedPercent == nil, amount == nil { state = .unknown }
                        }
                    } else { state = .missingMetric }
                }
                if account.isError || account.sourceReport?.allFailed == true {
                    state = .unavailable
                    usedPercent = nil
                    amount = nil
                    forecast = nil
                }
            }
            let validObservation = observedAt.map { $0.timeIntervalSince1970.isFinite && $0 <= now } == true
            let stale = observedAt.map { now.timeIntervalSince($0) > ProviderSourceStatus.staleInterval } ?? false
            if state == .available {
                if !validObservation { state = .unknown; usedPercent = nil; amount = nil; forecast = nil }
                else if stale { state = .stale }
            }
            return SummaryResolvedCard(
                configuration: configuration, provider: account,
                accountTitle: account.map {
                    self.accountTitle(
                        $0, anchorID: configuration.accountAnchorID, preferences: preferences, accounts: accounts)
                } ?? preferences.accountAliases[configuration.accountAnchorID] ?? configuration.accountTitle,
                metricTitle: candidate?.metricTitle ?? configuration.metricTitle,
                state: state, isStale: stale, observedAt: observedAt, window: window,
                usedPercent: usedPercent, resetDate: reset, forecast: forecast, amount: amount,
                compactAccountTitle: account.map {
                    self.compactAccountTitle(
                        $0, anchorID: configuration.accountAnchorID, preferences: preferences)
                } ?? preferences.accountAliases[configuration.accountAnchorID]
                    ?? SummaryPresentation.providerName(id: configuration.providerID, accounts: []),
                privateAccountTitle: account.map {
                    self.compactAccountTitle(
                        $0, anchorID: configuration.accountAnchorID, preferences: preferences)
                } ?? preferences.accountAliases[configuration.accountAnchorID]
                    ?? SummaryPresentation.providerName(id: configuration.providerID, accounts: []))
        }
    }

    /// A confirmed cross-Mac merge may combine two previously separate anchors. Keep both
    /// user-owned bindings alive without duplicating the account in the picker. Weak record/card
    /// slots never bridge, and ties stay missing rather than choosing an arbitrary account.
    private static func bridgedAccount(
        _ configuration: SummaryCardConfiguration,
        accounts: [ProviderUsageSnapshot],
        preferences: SummaryPreferences,
        linkages: [ProviderAccountLinkage]) -> ProviderUsageSnapshot?
    {
        guard let anchor = preferences.accountAnchors.first(where: {
            $0.id == configuration.accountAnchorID && $0.providerID == configuration.providerID
        }) else { return nil }
        let stable = Set(anchor.tokens.filter(UsageAccountIdentity.isStable))
        let anchorTokens = Set(anchor.tokens)
        // Explicit links also cover identity-less old Macs. Evaluate live links, never add
        // their identities to the anchor: an inverse unmerge must undo the bridge immediately.
        let legacyCard = "\(configuration.providerID):card:\(configuration.providerID)|"
        let legacyPlaceholder = "\(configuration.providerID):legacy-no-identity"
        let explicitLinks = UsageCardLinkages.effective(linkages).filter { linkage in
            guard linkage.providerID == configuration.providerID else { return false }
            let linked = Set(linkage.linkedIdentifiers.filter { $0.hasPrefix("\(configuration.providerID):") })
            return !linked.isDisjoint(with: anchorTokens)
                || (anchorTokens.contains(legacyCard) && linked.contains(legacyPlaceholder))
        }
        let scores = accounts.filter { $0.providerID == configuration.providerID }.compactMap { account in
            let tokens = UsageAccountIdentity.tokens(for: account)
            let hasStableOverlap = !stable.isDisjoint(with: tokens.filter(UsageAccountIdentity.isStable))
            let identifiers = Set(ProviderSnapshotMerger.effectiveIdentifiers(for: account))
            let explicitlyLinked = explicitLinks.contains { link in
                let named = Set(link.linkedIdentifiers.filter {
                    $0.hasPrefix("\(configuration.providerID):") && $0 != legacyPlaceholder
                })
                return !named.isDisjoint(with: identifiers)
            }
            guard hasStableOverlap || explicitlyLinked else { return nil as (Int, ProviderUsageSnapshot)? }
            if explicitlyLinked { return (10000, account) }
            return (UsageAccountIdentity.score(account: tokens, anchor: Set(anchor.tokens)), account)
        }
        guard let best = scores.map(\.0).max(), scores.filter({ $0.0 == best }).count == 1 else { return nil }
        return scores.first { $0.0 == best }?.1
    }

    static func providerName(_ account: ProviderUsageSnapshot) -> String {
        let name = account.providerName.components(separatedBy: " (").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? account.providerID : name
    }

    /// The merger can retain quota from a different/older Mac than the envelope's latest
    /// metadata (for example Kimi). Source age and extrapolation must follow the actual quota.
    static func quotaCapturedAt(_ account: ProviderUsageSnapshot) -> Date {
        account.sourceReport?.sourceCapturedAt ?? account.lastUpdated
    }

    /// Cards use a provider name unless the user supplies an account alias or a card title.
    /// Complete account identity remains in details, accessibility and the account picker.
    static func compactAccountTitle(
        _ account: ProviderUsageSnapshot, anchorID: String,
        preferences: SummaryPreferences) -> String
    {
        preferences.accountAliases[anchorID].flatMap { $0.isEmpty ? nil : $0 } ?? self.providerName(account)
    }

    static func accountTitle(
        _ account: ProviderUsageSnapshot, anchorID: String,
        preferences: SummaryPreferences, accounts: [ProviderUsageSnapshot], locale: Locale = .current) -> String
    {
        var components = [self.providerName(account)]
        let alias = preferences.accountAliases[anchorID].flatMap { $0.isEmpty ? nil : $0 }
        var identity = alias ?? account.accountOrganization.flatMap { $0.isEmpty ? nil : $0 }
            ?? account.accountEmail
        if alias == nil, let organization = account.accountOrganization, !organization.isEmpty,
           accounts.filter({ $0.providerID == account.providerID && $0.accountOrganization == organization }).count > 1
        {
            let anchors = preferences.accountAnchors.filter { $0.providerID == account.providerID }
            let ordinal = (anchors.firstIndex { $0.id == anchorID } ?? 0) + 1
            var label = "\(organization) · \(ordinal)"
            if let email = account.accountEmail, !email.isEmpty, email != organization {
                label += " · " + email
            }
            identity = label
        }
        let login = account.loginMethod.map {
            ProviderDetailLocalization.localizedValue($0, providerID: account.providerID, locale: locale)
        }
        for value in [identity, login].compactMap(\.self) where !value.isEmpty {
            if !components.contains(value) { components.append(value) }
        }
        return components.joined(separator: " ")
    }

    static func balance(for account: ProviderUsageSnapshot) -> SummaryCardAmount? {
        if let value = account.providerAmount, value.kind == "balance" {
            return SummaryCardAmount(
                value: value.amount,
                currencyCode: value.currencyCode,
                observedAt: value.observedAt ?? account.lastUpdated,
                isEstimated: value.isEstimated)
        }
        if let value = account.moonshotBalance {
            return SummaryCardAmount(
                value: value.balanceAmount,
                currencyCode: value.balanceCurrency,
                observedAt: value.updatedAt,
                isEstimated: false)
        }
        if let value = account.openCodeGoZenBalance {
            return SummaryCardAmount(
                value: value.balanceUSD,
                currencyCode: "USD",
                observedAt: value.updatedAt,
                isEstimated: false)
        }
        if let value = account.openRouterStats {
            return SummaryCardAmount(
                value: value.balanceUSD,
                currencyCode: "USD",
                observedAt: value.updatedAt,
                isEstimated: false)
        }
        if let value = account.crossModelUsage {
            return SummaryCardAmount(
                value: value.balance,
                currencyCode: value.currency,
                observedAt: value.updatedAt,
                isEstimated: false)
        }
        if let value = account.sub2APIUsage, let balance = value.balance {
            return SummaryCardAmount(
                value: balance,
                currencyCode: value.unit,
                observedAt: account.lastUpdated,
                isEstimated: false)
        }
        if let balance = account.perplexityCredits?.balanceCents {
            return SummaryCardAmount(
                value: balance / 100,
                currencyCode: "USD",
                observedAt: account.lastUpdated,
                isEstimated: false)
        }
        if let value = account.deepSeekUsage, let balance = value.totalBalanceUSD {
            return SummaryCardAmount(
                value: balance,
                currencyCode: "USD",
                observedAt: value.updatedAt,
                isEstimated: false)
        }
        return nil
    }
}
