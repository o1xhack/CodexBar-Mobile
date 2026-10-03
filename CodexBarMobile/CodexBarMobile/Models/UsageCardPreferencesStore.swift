import CodexBarSync
import Combine
import Foundation

/// Observable owner of `UsageCardPreferences`. The live store persists to this
/// iPhone's `UserDefaults` as versioned JSON; the demo store keeps everything
/// in memory so trying the demo never changes the user's real layout.
@MainActor
final class UsageCardPreferencesStore: ObservableObject {
    static let defaultsKey = "usageCardPreferences.v1"

    @Published private(set) var preferences: UsageCardPreferences

    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        self.preferences = Self.load(from: defaults)
    }

    static func live() -> UsageCardPreferencesStore {
        UsageCardPreferencesStore(defaults: .standard)
    }

    static func inMemory() -> UsageCardPreferencesStore {
        UsageCardPreferencesStore(defaults: nil)
    }

    /// Unreadable or newer-schema data falls back to defaults without being
    /// deleted, so a downgrade cannot wipe what a newer build stored.
    static func load(from defaults: UserDefaults?) -> UsageCardPreferences {
        guard let data = defaults?.data(forKey: self.defaultsKey),
              let decoded = try? JSONDecoder().decode(UsageCardPreferences.self, from: data),
              decoded.schemaVersion <= UsageCardPreferences.currentSchemaVersion
        else {
            return UsageCardPreferences()
        }
        return decoded
    }

    private var isWritable: Bool {
        guard let data = self.defaults?.data(forKey: Self.defaultsKey) else { return true }
        let version = (try? JSONDecoder().decode(SchemaProbe.self, from: data))?.schemaVersion ?? 0
        return version <= UsageCardPreferences.currentSchemaVersion
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int?
    }

    private func update(_ change: (inout UsageCardPreferences) -> Void) {
        var next = self.preferences
        change(&next)
        guard next != self.preferences else { return }
        self.preferences = next
        guard let defaults = self.defaults, self.isWritable,
              let data = try? JSONEncoder().encode(next)
        else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    // MARK: Actions

    func reconcileAnchors(groups: [ProviderAccountGroup], linkages: [ProviderAccountLinkage] = []) {
        self.update { $0.reconcileAnchors(groups: groups, linkages: linkages) }
    }

    func setExpanded(_ expanded: Bool, group: ProviderAccountGroup) {
        self.update { preferences in
            if expanded {
                // Anchor first so the keys handed to the migration are the
                // keys the expanded cards will render with.
                preferences.expandedProviderIDs.insert(group.providerID)
                preferences.reconcileAnchors(groups: [group])
                preferences.expandedProviderIDs.remove(group.providerID)
            }
            let keys = UsageCardBuilder.accountKeys(for: group, preferences: preferences)
            preferences.setExpanded(expanded, providerID: group.providerID, accountKeys: keys)
        }
    }

    func setPinned(_ pinned: Bool, cardKey: String, displayedOrder: [String]) {
        self.update { $0.setPinned(pinned, cardKey: cardKey, displayedOrder: displayedOrder) }
    }

    func setUsesDefaultSort(_ usesDefault: Bool, displayedOrder: [String]) {
        self.update { $0.setUsesDefaultSort(usesDefault, displayedOrder: displayedOrder) }
    }

    func setDefaultSortRule(_ rule: UsageDefaultSortRule) {
        self.update { $0.defaultSortRule = rule }
    }

    func setManualOrder(pinned: [String], others: [String]) {
        self.update { $0.setManualOrder(pinned: pinned, others: others) }
    }
}
