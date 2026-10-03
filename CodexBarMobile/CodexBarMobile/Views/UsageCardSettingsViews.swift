import CodexBarSync
import SwiftUI

// MARK: - Provider settings (iOS 2.5.0, Research/064)

/// Per-provider settings opened from the detail view's `…` menu. Every provider
/// gets this entry so later per-provider options have a home. Everything here
/// is stored on this device only.
struct ProviderSettingsView: View {
    let group: ProviderAccountGroup
    @ObservedObject var store: UsageCardPreferencesStore
    @Environment(\.dismiss) private var dismiss

    private var isExpanded: Bool {
        self.store.preferences.isExpanded(self.group.providerID)
    }

    private var canExpand: Bool {
        self.group.hasMultipleAccounts || self.isExpanded
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        String(localized: "Show Accounts as Separate Cards"),
                        isOn: Binding(
                            get: { self.isExpanded },
                            set: { self.store.setExpanded($0, group: self.group) }))
                        .disabled(!self.canExpand)
                        .accessibilityIdentifier("provider-settings-expand-accounts")
                } header: {
                    Text("Accounts")
                } footer: {
                    if self.canExpand {
                        Text("Each account gets its own card in Usage instead of tabs inside one card.")
                    } else {
                        Text("Only one account of this provider is synced right now.")
                    }
                }

                Section {
                    Label(
                        String(localized: "Saved on this device only. Not synced to your Mac."),
                        systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(self.group.providerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        self.dismiss()
                    }
                    .accessibilityIdentifier("provider-settings-done")
                }
            }
        }
        .accessibilityIdentifier("provider-settings-\(self.group.providerID)")
    }
}

// MARK: - Edit order

/// Edit Order sheet opened from the Usage page. Pinned and regular cards are
/// two sections; both reorder by drag in manual mode. The default order
/// switch replaces manual order with one of three rules.
struct UsageSortEditorView: View {
    let cards: [UsageCard]
    let now: Date
    @ObservedObject var store: UsageCardPreferencesStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false

    private var arrangement: UsageCardArrangement {
        UsageCardOrdering.arrange(
            self.cards.map { UsageCardOrdering.descriptor(for: $0, now: self.now) },
            preferences: self.store.preferences)
    }

    private var cardsByKey: [String: UsageCard] {
        Dictionary(self.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let arrangement = self.arrangement
        let usesDefault = self.store.preferences.usesDefaultSort
        NavigationStack {
            List {
                Section {
                    Toggle(
                        String(localized: "Default Order"),
                        isOn: Binding(
                            get: { usesDefault },
                            set: { self.store.setUsesDefaultSort($0, displayedOrder: arrangement.all) }))
                        .accessibilityIdentifier("sort-default-toggle")
                    if usesDefault {
                        Picker(
                            String(localized: "Order By"),
                            selection: Binding(
                                get: { self.store.preferences.defaultSortRule },
                                set: { self.store.setDefaultSortRule($0) }))
                        {
                            ForEach(UsageDefaultSortRule.allCases) { rule in
                                Text(Self.title(for: rule)).tag(rule)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .accessibilityIdentifier("sort-default-rule-picker")
                    }
                } footer: {
                    if usesDefault {
                        Text(Self.footer(for: self.store.preferences.defaultSortRule))
                    } else {
                        Text("Manual order: drag cards to arrange pinned and other cards.")
                    }
                }

                Section {
                    if arrangement.pinned.isEmpty {
                        Text("Pin a card from its … menu to keep it on top.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(arrangement.pinned, id: \.self) { key in
                        self.row(for: key)
                    }
                    .onMove { offsets, destination in
                        var pinned = arrangement.pinned
                        pinned.move(fromOffsets: offsets, toOffset: destination)
                        self.store.setManualOrder(pinned: pinned, others: arrangement.others)
                    }
                    .moveDisabled(usesDefault)
                } header: {
                    Text("Pinned")
                }

                Section {
                    ForEach(arrangement.others, id: \.self) { key in
                        self.row(for: key)
                    }
                    .onMove { offsets, destination in
                        var others = arrangement.others
                        others.move(fromOffsets: offsets, toOffset: destination)
                        self.store.setManualOrder(pinned: arrangement.pinned, others: others)
                    }
                    .moveDisabled(usesDefault)
                } header: {
                    Text("Other Cards")
                }
            }
            .overlay(alignment: .topLeading) {
                // UI tests read the full order here; List rows off screen
                // are not in the accessibility tree.
                if Self.exposesOrderForUITests {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityIdentifier("sort-order-state")
                        .accessibilityValue(arrangement.all.joined(separator: ","))
                }
            }
            .environment(\.editMode, .constant(usesDefault ? .inactive : .active))
            .animation(.default, value: arrangement)
            .navigationTitle(String(localized: "Edit Order"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        self.dismiss()
                    }
                    .accessibilityIdentifier("sort-editor-done")
                }
            }
        }
        .accessibilityIdentifier("usage-sort-editor")
    }

    @ViewBuilder
    private func row(for key: String) -> some View {
        if let card = self.cardsByKey[key] {
            HStack(spacing: 10) {
                Circle()
                    .fill(ProviderColorPalette.color(for: card.snapshot))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.snapshot.providerName)
                        .font(.body)
                    if let subtitle = UsageCardPresentation.accountSubtitle(
                        for: card,
                        hidePersonalInfo: self.hidePersonalInfo)
                    {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if self.store.preferences.usesDefaultSort,
                   self.store.preferences.defaultSortRule == .weeklyReset
                {
                    if let reset = UsageCardOrdering.weeklyResetDate(for: card.snapshot, now: self.now) {
                        Text(reset, format: .relative(presentation: .numeric))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No weekly reset")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sort-row-\(key)")
        }
    }

    private static let exposesOrderForUITests =
        ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA")

    static func title(for rule: UsageDefaultSortRule) -> String {
        switch rule {
        case .alphabeticalAscending: String(localized: "Name (A to Z)")
        case .alphabeticalDescending: String(localized: "Name (Z to A)")
        case .weeklyReset: String(localized: "Weekly Reset (Soonest First)")
        }
    }

    static func footer(for rule: UsageDefaultSortRule) -> String {
        switch rule {
        case .alphabeticalAscending, .alphabeticalDescending:
            String(localized: "Pinned and other cards are each sorted by name.")
        case .weeklyReset:
            String(localized: "Cards without a weekly reset, such as API providers, follow by name.")
        }
    }
}

// MARK: - Shared presentation helpers

enum UsageCardPresentation {
    /// Account line for account cards: the visible email, then organization,
    /// then "Codex 2". Provider cards return the representative's visible email.
    static func accountSubtitle(for card: UsageCard, hidePersonalInfo: Bool) -> String? {
        if let email = ProviderUsageView.visibleAccountEmail(
            card.snapshot.accountEmail,
            hidePersonalInfo: hidePersonalInfo)
        {
            return email
        }
        guard let ordinal = card.accountOrdinal else { return nil }
        if let organization = ProviderUsageView.visibleOrganization(
            card.snapshot.accountOrganization,
            hidePersonalInfo: hidePersonalInfo)
        {
            return organization
        }
        let template = String(localized: "provider-account-ordinal")
        return String(format: template, card.snapshot.providerName, ordinal)
    }

    /// Provider cards offer the provider's first active linkage (pre-2.5
    /// behavior). An account card only offers a linkage that includes one of
    /// its own identities, so Unmerge never acts on a sibling account.
    static func activeLinkage(
        for card: UsageCard,
        in linkagesByProviderID: [String: [ProviderAccountLinkage]]) -> ProviderAccountLinkage?
    {
        let linkages = linkagesByProviderID[card.providerID] ?? []
        guard card.isAccountCard else { return linkages.first }
        let identities = Set(ProviderSnapshotMerger.effectiveIdentifiers(for: card.snapshot))
        return linkages.first { !identities.isDisjoint(with: $0.linkedIdentifiers) }
    }
}
