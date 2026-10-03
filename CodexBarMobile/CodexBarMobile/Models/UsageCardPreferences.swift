import CodexBarSync
import Foundation

// MARK: - Usage card presentation preferences (iOS 2.5.0, Research/064)

//
// Device-local presentation state for the Usage list: which multi-account
// providers are expanded into one card per account, which cards are pinned,
// and how cards are ordered. Stored in this iPhone's UserDefaults only — it is
// never written to CloudKit or KVS and never reaches the Mac.
//
// Card keys:
//   provider:<providerID>   one card for a whole provider (default)
//   account:<anchorID>      one card per account of an expanded provider
//
// Account cards are keyed by a local anchor instead of `accountRecordKey`
// because the merged snapshot's record key is "latest non-nil across Macs"
// and can flip between per-install token UUIDs. An anchor remembers every
// identity token it has been matched with, so the same logical account keeps
// its pin and manual position across refreshes, renames, extra Macs and
// confirmed linkages.

enum UsageDefaultSortRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case alphabeticalAscending
    case alphabeticalDescending
    case weeklyReset

    var id: String {
        self.rawValue
    }
}

struct UsageAccountAnchor: Codable, Equatable, Sendable {
    let id: String
    let providerID: String
    /// Sorted, de-duplicated identity tokens (see `UsageAccountIdentity`).
    var tokens: [String]
}

enum UsageCardKey {
    static let providerPrefix = "provider:"
    static let accountPrefix = "account:"

    static func provider(_ providerID: String) -> String {
        "\(self.providerPrefix)\(providerID)"
    }

    static func account(anchorID: String) -> String {
        "\(self.accountPrefix)\(anchorID)"
    }

    static func isAccount(_ key: String) -> Bool {
        key.hasPrefix(self.accountPrefix)
    }
}

/// Identity tokens used to match an account snapshot to its local anchor.
enum UsageAccountIdentity {
    /// The merger's effective identities plus the per-install record key, so an
    /// editable label never counts as identity when real identities exist. The
    /// merger's shared "no identity" placeholder is dropped because it is not
    /// specific to one account; a snapshot with nothing else uses its card key.
    static func tokens(for snapshot: ProviderUsageSnapshot) -> Set<String> {
        let placeholder = "\(snapshot.providerID):legacy-no-identity"
        var tokens = Set(ProviderSnapshotMerger.effectiveIdentifiers(for: snapshot))
        tokens.remove(placeholder)
        if let recordKey = snapshot.accountRecordKey, !recordKey.isEmpty {
            tokens.insert("\(snapshot.providerID):record:\(recordKey)")
        }
        if tokens.isEmpty {
            tokens.insert("\(snapshot.providerID):card:\(snapshot.cardIdentityKey)")
        }
        return tokens
    }

    /// Record keys (per-install token UUIDs, reusable slots) and card-key
    /// fallbacks are weak evidence; account, organization and email
    /// identities are stable.
    static func isStable(_ token: String) -> Bool {
        !token.contains(":record:") && !token.contains(":card:")
    }

    /// Match score between an account and an anchor. Stable overlap dominates.
    /// When both sides carry stable identities that do not overlap they are
    /// different accounts, even if they share a record slot. Weak-only
    /// overlap counts only when one side has no stable identity (legacy data).
    static func score(account: Set<String>, anchor: Set<String>) -> Int {
        let accountStable = account.filter(Self.isStable)
        let anchorStable = anchor.filter(Self.isStable)
        let stableOverlap = accountStable.intersection(anchorStable).count
        let weakOverlap = account.intersection(anchor).count - stableOverlap
        if stableOverlap > 0 {
            // Personal email identities break ties against shared
            // organization/workspace identities the anchor once saw.
            let emailOverlap = accountStable.intersection(anchorStable).filter { $0.contains(":email:") }.count
            return stableOverlap * 100 + emailOverlap * 10 + weakOverlap
        }
        if !accountStable.isEmpty, !anchorStable.isEmpty {
            return 0
        }
        return weakOverlap
    }

    /// Anchor ID minted for a snapshot that has no anchor yet. Matches the key
    /// the Usage list renders before reconciliation, so a card does not change
    /// identity the moment its anchor is persisted.
    static func proposedAnchorID(for snapshot: ProviderUsageSnapshot) -> String {
        snapshot.cardIdentityKey
    }
}

struct UsageCardPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    /// Providers whose accounts render as separate cards. Default: none.
    var expandedProviderIDs: Set<String> = []
    var pinnedCardKeys: Set<String> = []
    /// `false` (the upgrade default) is manual order. With no stored manual
    /// order this is exactly the pre-2.5 Mac provider order.
    var usesDefaultSort = false
    var defaultSortRule: UsageDefaultSortRule = .alphabeticalAscending
    /// Full manual order across both sections. Cards missing from it keep their
    /// source order after the ordered ones.
    var manualOrder: [String] = []
    var accountAnchors: [UsageAccountAnchor] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, expandedProviderIDs, pinnedCardKeys, usesDefaultSort
        case defaultSortRule, manualOrder, accountAnchors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.expandedProviderIDs = try container.decodeIfPresent(Set<String>.self, forKey: .expandedProviderIDs) ?? []
        self.pinnedCardKeys = try container.decodeIfPresent(Set<String>.self, forKey: .pinnedCardKeys) ?? []
        self.usesDefaultSort = try container.decodeIfPresent(Bool.self, forKey: .usesDefaultSort) ?? false
        let rawRule = try container.decodeIfPresent(String.self, forKey: .defaultSortRule)
        self.defaultSortRule = rawRule.flatMap(UsageDefaultSortRule.init(rawValue:)) ?? .alphabeticalAscending
        self.manualOrder = try container.decodeIfPresent([String].self, forKey: .manualOrder) ?? []
        self.accountAnchors = try container.decodeIfPresent([UsageAccountAnchor].self, forKey: .accountAnchors) ?? []
    }

    func isExpanded(_ providerID: String) -> Bool {
        self.expandedProviderIDs.contains(providerID)
    }

    func isPinned(_ key: String) -> Bool {
        self.pinnedCardKeys.contains(key)
    }
}

// MARK: - Account anchors

extension UsageCardPreferences {
    /// Assigns each account of one provider to an anchor without mutating the
    /// preferences. Assignment is global: every (account, anchor) pair is
    /// scored with `UsageAccountIdentity.score` and the best pairs are taken
    /// first (ties: stored anchor order, then account order), so an earlier
    /// account cannot take an anchor that fits a later one better. Unmatched
    /// accounts get their proposed anchor ID (suffixed if taken).
    func anchorIDs(forAccounts accounts: [ProviderUsageSnapshot]) -> [String] {
        let tokens = accounts.map(UsageAccountIdentity.tokens(for:))
        var pairs: [(score: Int, anchor: Int, account: Int)] = []
        for (anchorIndex, anchor) in self.accountAnchors.enumerated() {
            let anchorTokens = Set(anchor.tokens)
            for (accountIndex, account) in accounts.enumerated() where anchor.providerID == account.providerID {
                let score = UsageAccountIdentity.score(account: tokens[accountIndex], anchor: anchorTokens)
                if score > 0 {
                    pairs.append((score, anchorIndex, accountIndex))
                }
            }
        }
        pairs.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.anchor != rhs.anchor { return lhs.anchor < rhs.anchor }
            return lhs.account < rhs.account
        }
        var assigned = [Int: String]()
        var claimed = Set<String>()
        for pair in pairs where assigned[pair.account] == nil {
            let id = self.accountAnchors[pair.anchor].id
            guard !claimed.contains(id) else { continue }
            assigned[pair.account] = id
            claimed.insert(id)
        }
        return accounts.indices.map { index in
            if let id = assigned[index] { return id }
            let id = self.unusedAnchorID(
                proposed: UsageAccountIdentity.proposedAnchorID(for: accounts[index]),
                claimed: claimed)
            claimed.insert(id)
            return id
        }
    }

    private func unusedAnchorID(proposed: String, claimed: Set<String>) -> String {
        let existing = Set(self.accountAnchors.map(\.id)).union(claimed)
        guard existing.contains(proposed) else { return proposed }
        var suffix = 2
        while existing.contains("\(proposed)#\(suffix)") {
            suffix += 1
        }
        return "\(proposed)#\(suffix)"
    }

    /// Persists anchors for the accounts of expanded providers: creates missing
    /// anchors, folds newly seen identity tokens into matched ones (for example
    /// a second Mac's record key), and absorbs leftover anchors that now
    /// describe the same account (a confirmed linkage): the kept card inherits
    /// their pin and the earlier manual position. Returns `true` on change.
    ///
    /// Confirmed linkages (`ProviderAccountLinkage`, not unmerged) also absorb
    /// the legacy card's anchor into the named account, whichever Mac
    /// published last: the merged snapshot does not always carry the legacy
    /// side's tokens, and an identity-less legacy card never does.
    @discardableResult
    mutating func reconcileAnchors(
        groups: [ProviderAccountGroup],
        linkages: [ProviderAccountLinkage] = []) -> Bool
    {
        let before = self
        for group in groups where self.isExpanded(group.providerID) {
            let ids = self.anchorIDs(forAccounts: group.accounts)
            let assignedIDs = Set(ids)
            let groupLinkages = UsageCardLinkages.effective(linkages).filter { $0.providerID == group.providerID }
            for (account, id) in zip(group.accounts, ids) {
                let tokens = UsageAccountIdentity.tokens(for: account)
                if let index = self.accountAnchors.firstIndex(where: { $0.id == id }) {
                    self.accountAnchors[index].tokens = Set(self.accountAnchors[index].tokens).union(tokens).sorted()
                } else {
                    self.accountAnchors.append(UsageAccountAnchor(
                        id: id,
                        providerID: group.providerID,
                        tokens: tokens.sorted()))
                }
                let stable = tokens.filter(UsageAccountIdentity.isStable)
                let absorbed = self.accountAnchors.filter { anchor in
                    guard anchor.providerID == group.providerID, !assignedIDs.contains(anchor.id) else {
                        return false
                    }
                    let anchorTokens = Set(anchor.tokens)
                    let anchorStable = anchorTokens.filter(UsageAccountIdentity.isStable)
                    if !anchorStable.isDisjoint(with: stable) { return true }
                    return anchorStable.isEmpty && !anchorTokens.isDisjoint(with: tokens)
                }
                for leftover in absorbed {
                    self.absorb(anchorID: leftover.id, into: id)
                }
                let identities = Set(ProviderSnapshotMerger.effectiveIdentifiers(for: account))
                let legacyPlaceholder = "\(group.providerID):legacy-no-identity"
                // An identity-less legacy card can only have this token.
                let legacyCardToken = "\(group.providerID):card:\(group.providerID)|"
                for linkage in groupLinkages {
                    let linked = Set(linkage.linkedIdentifiers)
                    // Only the named side absorbs; the legacy card itself shares
                    // the placeholder and must not swallow other anchors.
                    guard !identities.isDisjoint(with: linked.subtracting([legacyPlaceholder])) else { continue }
                    let linkedAnchors = self.accountAnchors.filter { anchor in
                        guard anchor.providerID == group.providerID, !assignedIDs.contains(anchor.id) else {
                            return false
                        }
                        if !linked.isDisjoint(with: anchor.tokens) { return true }
                        return linked.contains(legacyPlaceholder) && anchor.tokens.contains(legacyCardToken)
                    }
                    for leftover in linkedAnchors {
                        self.absorb(anchorID: leftover.id, into: id)
                    }
                }
            }
        }
        return self != before
    }

    private mutating func absorb(anchorID: String, into keptID: String) {
        guard let leftover = self.accountAnchors.first(where: { $0.id == anchorID }),
              let keptIndex = self.accountAnchors.firstIndex(where: { $0.id == keptID })
        else { return }
        self.accountAnchors[keptIndex].tokens = Set(self.accountAnchors[keptIndex].tokens)
            .union(leftover.tokens).sorted()
        self.accountAnchors.removeAll { $0.id == anchorID }
        let leftoverKey = UsageCardKey.account(anchorID: anchorID)
        let keptKey = UsageCardKey.account(anchorID: keptID)
        if self.pinnedCardKeys.remove(leftoverKey) != nil {
            self.pinnedCardKeys.insert(keptKey)
        }
        if let leftoverIndex = self.manualOrder.firstIndex(of: leftoverKey) {
            let keptIndexInOrder = self.manualOrder.firstIndex(of: keptKey)
            if keptIndexInOrder == nil || leftoverIndex < keptIndexInOrder! {
                self.manualOrder[leftoverIndex] = keptKey
                var seen = false
                self.manualOrder.removeAll { key in
                    guard key == keptKey else { return false }
                    defer { seen = true }
                    return seen
                }
            } else {
                self.manualOrder.remove(at: leftoverIndex)
            }
        }
    }
}

/// Linkages the cross-Mac merger actually applies: merge records that no
/// later "unmerge" record suppresses (unmerging appends an inverse record).
enum UsageCardLinkages {
    static func effective(_ linkages: [ProviderAccountLinkage]) -> [ProviderAccountLinkage] {
        let partition = ProviderSnapshotMerger.partitionLinkages(linkages)
        let suppressed = ProviderSnapshotMerger.suppressedEdges(unmergeLinkages: partition.unmerges)
        return partition.merges.filter { !ProviderSnapshotMerger.isLinkageSuppressed($0, by: suppressed) }
    }
}

// MARK: - Mutations

extension UsageCardPreferences {
    /// Expands or collapses a provider and migrates its pin and manual position:
    /// expanding hands the provider card's pin and slot to every account card
    /// (in account order); collapsing gives the provider card the slot of its
    /// highest-ranked account card and keeps it pinned if any visible account was.
    mutating func setExpanded(_ expanded: Bool, providerID: String, accountKeys: [String]) {
        let providerKey = UsageCardKey.provider(providerID)
        let anchorKeys = self.accountAnchors
            .filter { $0.providerID == providerID }
            .map { UsageCardKey.account(anchorID: $0.id) }
        if expanded {
            guard !self.isExpanded(providerID) else { return }
            self.expandedProviderIDs.insert(providerID)
            if self.pinnedCardKeys.remove(providerKey) != nil {
                self.pinnedCardKeys.formUnion(accountKeys)
            }
            if let index = self.manualOrder.firstIndex(of: providerKey) {
                let incoming = Set(accountKeys)
                var order = self.manualOrder
                order.remove(at: index)
                let insertAt = order[..<index].filter { !incoming.contains($0) }.count
                order.removeAll { incoming.contains($0) }
                order.insert(contentsOf: accountKeys, at: insertAt)
                self.manualOrder = order
            }
        } else {
            guard self.isExpanded(providerID) else { return }
            self.expandedProviderIDs.remove(providerID)
            // Only accounts on screen hand their pin to the provider card; pins
            // of accounts that are currently missing stay dormant on their key.
            let current = Set(accountKeys)
            let outgoing = current.union(anchorKeys)
            if !self.pinnedCardKeys.isDisjoint(with: current) {
                self.pinnedCardKeys.insert(providerKey)
            }
            self.pinnedCardKeys.subtract(current)
            if let index = self.manualOrder.firstIndex(where: { outgoing.contains($0) }) {
                var order = self.manualOrder
                order[index] = providerKey
                let keep = order.enumerated().filter { offset, key in
                    offset == index || (!outgoing.contains(key) && key != providerKey)
                }
                self.manualOrder = keep.map(\.element)
            }
        }
    }

    /// Pins or unpins one card. In manual mode the visible order is
    /// materialized first so the card lands at the top of its new section;
    /// default sorting places it by the active rule.
    mutating func setPinned(_ pinned: Bool, cardKey: String, displayedOrder: [String]) {
        guard self.isPinned(cardKey) != pinned else { return }
        if pinned {
            self.pinnedCardKeys.insert(cardKey)
        } else {
            self.pinnedCardKeys.remove(cardKey)
        }
        guard !self.usesDefaultSort else { return }
        var order = self.materializedOrder(displayedOrder: displayedOrder)
        order.removeAll { $0 == cardKey }
        if pinned {
            order.insert(cardKey, at: 0)
        } else {
            let lastPinned = order.lastIndex(where: { self.pinnedCardKeys.contains($0) && displayedOrder.contains($0) })
            order.insert(cardKey, at: lastPinned.map { $0 + 1 } ?? 0)
        }
        self.manualOrder = order
    }

    /// Switching to manual order starts from what the user currently sees.
    mutating func setUsesDefaultSort(_ usesDefault: Bool, displayedOrder: [String]) {
        guard self.usesDefaultSort != usesDefault else { return }
        if !usesDefault {
            self.manualOrder = self.materializedOrder(displayedOrder: displayedOrder)
        }
        self.usesDefaultSort = usesDefault
    }

    /// Stores a new manual order from the two edited sections.
    mutating func setManualOrder(pinned: [String], others: [String]) {
        let edited = pinned + others
        let editedSet = Set(edited)
        self.manualOrder = edited + self.manualOrder.filter { !editedSet.contains($0) }
        self.usesDefaultSort = false
    }

    /// Displayed cards first, then remembered keys for cards that are not on
    /// screen right now (an offline Mac, an active search) so they keep a slot.
    private func materializedOrder(displayedOrder: [String]) -> [String] {
        let displayed = Set(displayedOrder)
        return displayedOrder + self.manualOrder.filter { !displayed.contains($0) }
    }
}
