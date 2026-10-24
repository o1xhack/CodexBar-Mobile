import CodexBarSync
import Combine
import Foundation

@MainActor
protocol SummaryPreferencesPersistence {
    func load() -> Data?
    func save(_ data: Data)
}

@MainActor
struct SummaryDefaultsPersistence: SummaryPreferencesPersistence {
    static let key = "summaryCardPreferences.v1"
    let defaults: UserDefaults

    func load() -> Data? { self.defaults.data(forKey: Self.key) }
    func save(_ data: Data) { self.defaults.set(data, forKey: Self.key) }
}

/// Device-local preferences. Injecting nil persistence makes demos and tests fully isolated.
@MainActor
final class SummaryPreferencesStore: ObservableObject {
    @Published private(set) var preferences: SummaryPreferences
    @Published private var linkages: [ProviderAccountLinkage] = []
    /// Corrupt or newer-schema preferences are preserved verbatim, including during reconciliation.
    let isReadOnly: Bool
    private let persistence: (any SummaryPreferencesPersistence)?

    init(persistence: (any SummaryPreferencesPersistence)? = nil) {
        self.persistence = persistence
        if let data = persistence?.load() {
            if let decoded = try? JSONDecoder().decode(SummaryPreferences.self, from: data),
               decoded.schemaVersion == SummaryPreferences.currentSchemaVersion,
               Set(decoded.cards.map(\.id)).count == decoded.cards.count,
               Set(decoded.orderedItemIDs).count == decoded.orderedItemIDs.count,
               Set(decoded.accountAnchors.map(\.id)).count == decoded.accountAnchors.count
            {
                self.preferences = decoded
                self.isReadOnly = false
            } else {
                self.preferences = SummaryPreferences()
                self.isReadOnly = true
            }
        } else {
            self.preferences = SummaryPreferences()
            self.isReadOnly = false
        }
    }

    static func live() -> SummaryPreferencesStore {
        SummaryPreferencesStore(persistence: SummaryDefaultsPersistence(defaults: .standard))
    }

    static func inMemory() -> SummaryPreferencesStore { SummaryPreferencesStore() }

    private func update(_ change: (inout SummaryPreferences) -> Void) {
        guard !self.isReadOnly else { return }
        var next = self.preferences
        change(&next)
        guard next != self.preferences else { return }
        self.preferences = next
        if let data = try? JSONEncoder().encode(next) { self.persistence?.save(data) }
    }

    /// The registry is independent of Usage's expansion state. Preserve retired anchors and their
    /// bindings; a missing account must never silently turn into a different account in the same slot.
    func reconcile(
        accounts: [ProviderUsageSnapshot],
        linkages: [ProviderAccountLinkage] = [],
        now: Date = .now)
    {
        if self.linkages != linkages { self.linkages = linkages }
        self.update { preferences in
            let assigned = SummaryCardResolver.accountBindings(accounts: accounts, preferences: preferences)
            for (anchorID, account) in assigned {
                let tokens = UsageAccountIdentity.tokens(for: account)
                if let index = preferences.accountAnchors.firstIndex(where: { $0.id == anchorID }) {
                    let existing = Set(preferences.accountAnchors[index].tokens)
                    // A merged display snapshot is not evidence that another account's stable
                    // identities belong to this anchor forever. Establish its own stable set once;
                    // thereafter only learn per-install weak keys. Linkages remain reversible.
                    let hasStableIdentity = existing.contains(where: UsageAccountIdentity.isStable)
                    let learnable = hasStableIdentity ? tokens.filter { !UsageAccountIdentity.isStable($0) } : tokens
                    preferences.accountAnchors[index].tokens = existing.union(learnable).sorted()
                } else {
                    preferences.accountAnchors.append(UsageAccountAnchor(
                        id: anchorID, providerID: account.providerID, tokens: tokens.sorted()))
                }
            }
            guard !preferences.hasInitialized else { return }
            let candidates = SummaryCardResolver.catalog(accounts: accounts, preferences: preferences, now: now)
            let defaults = SummaryCardResolver.defaultCandidates(
                candidates, accounts: accounts, preferences: preferences, now: now)
            // Empty initial syncs must not consume the first meaningful layout.
            guard !defaults.isEmpty else { return }
            preferences.cards = defaults.map { $0.configuration() }
            preferences.hasInitialized = true
        }
    }

    func catalog(accounts: [ProviderUsageSnapshot], now: Date = .now) -> [SummaryMetricCandidate] {
        SummaryCardResolver.catalog(accounts: accounts, preferences: self.preferences, now: now)
    }

    func resolvedCards(accounts: [ProviderUsageSnapshot], now: Date = .now) -> [SummaryResolvedCard] {
        SummaryCardResolver.resolve(
            accounts: accounts, preferences: self.preferences, linkages: self.linkages, now: now)
    }

    func resolve(
        _ configuration: SummaryCardConfiguration,
        accounts: [ProviderUsageSnapshot],
        accountAlias: String? = nil,
        now: Date = .now) -> SummaryResolvedCard
    {
        var preview = self.preferences
        preview.cards = [configuration]
        if let accountAlias {
            let trimmed = accountAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            preview.accountAliases[configuration.accountAnchorID] = trimmed.isEmpty ? nil : trimmed
        }
        return SummaryCardResolver.resolve(
            accounts: accounts, preferences: preview, linkages: self.linkages, now: now)[0]
    }

    func add(_ configuration: SummaryCardConfiguration) {
        self.update {
            $0.hasInitialized = true
            guard !$0.cards.contains(where: { $0.id == configuration.id }) else { return }
            $0.cards.append(configuration)
        }
    }

    func update(_ configuration: SummaryCardConfiguration) {
        self.update { preferences in
            guard let index = preferences.cards.firstIndex(where: { $0.id == configuration.id }) else { return }
            preferences.cards[index] = configuration
        }
    }

    func remove(id: UUID) {
        self.update {
            $0.hasInitialized = true
            if let index = $0.cards.firstIndex(where: { $0.id == id }),
               let position = $0.quotaModule?.position, index < position
            {
                $0.quotaModule?.position = max(0, position - 1)
            }
            $0.cards.removeAll { $0.id == id }
        }
    }

    /// Reorders the listed cards without dropping cards hidden by a Provider filter.
    func move(id: UUID, before destinationID: UUID?) {
        self.update { preferences in
            guard id != destinationID, let index = preferences.cards.firstIndex(where: { $0.id == id }) else { return }
            let card = preferences.cards.remove(at: index)
            let destination = destinationID.flatMap { target in preferences.cards.firstIndex { $0.id == target } }
            preferences.cards.insert(card, at: destination ?? preferences.cards.endIndex)
        }
    }

    /// Applies a visible list's new order in its original slots. Unlisted (filtered-out)
    /// cards keep both their data and positions; duplicate/unknown ids are ignored.
    func reorder(ids: [UUID]) {
        self.update { preferences in
            let known = Set(preferences.cards.map(\.id))
            var seen = Set<UUID>()
            let ordered = ids.filter { known.contains($0) && seen.insert($0).inserted }
            let selected = Set(ordered)
            let cards = Dictionary(uniqueKeysWithValues: preferences.cards.map { ($0.id, $0) })
            var next = ordered.makeIterator()
            preferences.cards = preferences.cards.map { card in
                guard selected.contains(card.id), let id = next.next(), let reordered = cards[id] else { return card }
                return reordered
            }
        }
    }

    func addQuotaModule() {
        self.update {
            guard $0.quotaModule == nil else { return }
            $0.hasInitialized = true
            $0.quotaModule = SummaryQuotaModule(position: $0.cards.count)
        }
    }

    func removeItem(id: UUID) {
        if self.preferences.quotaModule?.id == id {
            self.update { $0.quotaModule = nil }
        } else {
            self.remove(id: id)
        }
    }

    /// Reorder modules and metrics together, preserving any filtered-out items in place.
    func reorderItems(ids: [UUID]) {
        self.update { preferences in
            let current = preferences.orderedItemIDs
            let known = Set(current)
            var seen = Set<UUID>()
            let ordered = ids.filter { known.contains($0) && seen.insert($0).inserted }
            let selected = Set(ordered)
            var iterator = ordered.makeIterator()
            let next = current.map { selected.contains($0) ? iterator.next()! : $0 }
            let cards = Dictionary(uniqueKeysWithValues: preferences.cards.map { ($0.id, $0) })
            preferences.cards = next.compactMap { cards[$0] }
            if let id = preferences.quotaModule?.id {
                preferences.quotaModule?.position = next.firstIndex(of: id) ?? preferences.cards.count
            }
        }
    }

    func setAccountAlias(_ alias: String?, accountAnchorID: String) {
        self.update {
            let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.accountAliases[accountAnchorID] = trimmed?.isEmpty == false ? trimmed : nil
        }
    }
}
