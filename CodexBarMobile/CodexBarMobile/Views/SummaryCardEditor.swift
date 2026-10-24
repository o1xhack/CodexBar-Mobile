import CodexBarSync
import SwiftUI

struct SummaryAddFlow: View {
    @ObservedObject var preferences: SummaryPreferencesStore
    let accounts: [ProviderUsageSnapshot]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidesPersonalInfo = false
    @State private var providerID = ""
    @State private var metric: SummaryCardMetric = .quota(windowID: "primary")
    @State private var accountID = ""
    @State private var configuration: SummaryCardConfiguration?

    private var candidates: [SummaryMetricCandidate] {
        self.preferences.catalog(accounts: self.accounts)
    }

    private var providerIDs: [String] {
        Array(Set(self.candidates.map(\.providerID))).sorted()
    }

    private var metrics: [SummaryMetricCandidate] {
        var seen = Set<SummaryCardMetric>()
        return self.candidates.filter { $0.providerID == self.providerID && seen.insert($0.metric).inserted }
    }

    private var accountChoices: [SummaryMetricCandidate] {
        self.candidates.filter { $0.providerID == self.providerID && $0.metric == self.metric }
    }

    private var selected: SummaryMetricCandidate? {
        self.accountChoices.first { $0.accountAnchorID == self.accountID }
    }

    var body: some View {
        NavigationStack {
            if let configuration = self.configuration {
                SummaryCardEditor(
                    configuration: configuration, preferences: self.preferences,
                    accounts: self.accounts, isNew: true)
            } else {
                Form {
                    Section {
                        Button(String(localized: "Remaining Quota")) {
                            self.preferences.addQuotaModule()
                            self.dismiss()
                        }
                        .disabled(self.preferences.preferences.quotaModule != nil)
                        .accessibilityIdentifier("summary-add-quota-module")
                    } footer: {
                        Text(String(localized: "Add a four-tile chart to compare your remaining quotas."))
                    }
                    if self.candidates.isEmpty {
                        Text(String(localized: "No metrics available. Wait for your Mac to sync usage data."))
                    } else {
                        Section {
                            Picker(String(localized: "Provider"), selection: self.$providerID) {
                                ForEach(self.providerIDs, id: \.self) { id in
                                    Text(SummaryPresentation.providerName(id: id, accounts: self.accounts)).tag(id)
                                }
                            }
                            .accessibilityIdentifier("summary-add-provider")
                            Picker(String(localized: "Metric"), selection: self.$metric) {
                                ForEach(self.metrics) { candidate in
                                    Text(candidate.metricTitle).tag(candidate.metric)
                                }
                            }
                            .accessibilityIdentifier("summary-add-metric")
                            Picker(String(localized: "Account"), selection: self.$accountID) {
                                ForEach(self.accountChoices) { candidate in
                                    Text(SummaryPresentation.redact(
                                        candidate.accountTitle,
                                        enabled: self.hidesPersonalInfo))
                                        .tag(candidate.accountAnchorID)
                                }
                            }
                            .accessibilityIdentifier("summary-add-account")
                        } footer: {
                            Text(String(localized: "Choose a provider, a metric, then the account to follow."))
                        }
                        .listRowBackground(MobileSurfaceStyle.rowBackground)
                        Section {
                            Button(String(localized: "Next · Customize")) {
                                self.configuration = self.selected?.configuration()
                            }
                            .disabled(self.selected == nil || self.preferences.isReadOnly)
                            .accessibilityIdentifier("summary-add-next")
                        }
                        .listRowBackground(MobileSurfaceStyle.rowBackground)
                    }
                }
                .mobilePageSurface()
                .navigationTitle(String(localized: "Add metric"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { self.dismiss() }
                    }
                }
                .onAppear { self.reconcileChoices() }
                .onChange(of: self.providerID) { _, _ in self.reconcileChoices() }
                .onChange(of: self.metric) { _, _ in self.reconcileChoices() }
                .onChange(of: self.candidates) { _, _ in self.reconcileChoices() }
            }
        }
    }

    private func reconcileChoices() {
        if !self.providerIDs.contains(self.providerID) { self.providerID = self.providerIDs.first ?? "" }
        if !self.metrics.contains(where: { $0.metric == self.metric }), let first = self.metrics.first {
            self.metric = first.metric
        }
        if !self.accountChoices.contains(where: { $0.accountAnchorID == self.accountID }) {
            self.accountID = self.accountChoices.first?.accountAnchorID ?? ""
        }
    }
}

struct SummaryCardEditor: View {
    @ObservedObject var preferences: SummaryPreferencesStore
    let accounts: [ProviderUsageSnapshot]
    let isNew: Bool
    @State private var configuration: SummaryCardConfiguration
    @State private var displayName: String
    @State private var accountAlias: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidesPersonalInfo = false

    init(
        configuration: SummaryCardConfiguration, preferences: SummaryPreferencesStore,
        accounts: [ProviderUsageSnapshot], isNew: Bool)
    {
        self.preferences = preferences
        self.accounts = accounts
        self.isNew = isNew
        _configuration = State(initialValue: configuration)
        _displayName = State(initialValue: configuration.title ?? "")
        _accountAlias = State(initialValue: preferences.preferences.accountAliases[configuration.accountAnchorID] ?? "")
    }

    private var draft: SummaryCardConfiguration {
        var value = self.configuration
        let name = self.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.title = name.isEmpty ? nil : name
        return value
    }

    private var resolved: SummaryResolvedCard {
        self.preferences.resolve(self.draft, accounts: self.accounts, accountAlias: self.accountAlias)
    }

    var body: some View {
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    SummaryMetricTile(
                        card: self.preferences.resolve(
                            self.draft, accounts: self.accounts, accountAlias: self.accountAlias, now: context.date),
                        now: context.date,
                        editingTitle: self.draft.title ?? (self.accountAlias.isEmpty ? nil : self.accountAlias))
                        .frame(maxWidth: 240)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("summary-card-preview")
            }
            Section {
                if self.resolved.supportsCountdown {
                    Picker(String(localized: "Emphasize"), selection: self.$configuration.emphasis) {
                        Text(String(localized: "Usage %")).tag(SummaryCardEmphasis.percent)
                        Text(String(localized: "Time to reset")).tag(SummaryCardEmphasis.countdown)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("summary-emphasis")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Card display name")).font(.caption).foregroundStyle(.secondary)
                    TextField("", text: self.$displayName, prompt: Text(SummaryPresentation.redact(
                        self.resolved.compactAccountTitle ?? self.resolved.accountTitle,
                        enabled: self.hidesPersonalInfo)))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel(String(localized: "Card display name"))
                        .accessibilityIdentifier("summary-card-name")
                }
                DisclosureGroup {
                    Text(SummaryPresentation.redact(self.resolved.accountTitle, enabled: self.hidesPersonalInfo))
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("", text: self.$accountAlias)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel(String(localized: "Account alias"))
                        .accessibilityIdentifier("summary-account-alias")
                } label: {
                    Text(String(localized: "Account alias · Shared by this account’s cards"))
                        .accessibilityIdentifier("summary-account-alias-disclosure")
                }
            } header: {
                Text(String(localized: "Display"))
            } footer: {
                Text(
                    String(
                        localized: "The account alias is shared by its cards. A card display name overrides only this card's title."))
            }
            .listRowBackground(MobileSurfaceStyle.rowBackground)
            Section(String(localized: "Card color")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                    ForEach(SummaryCardColor.allCases) { color in
                        Button { self.configuration.color = color } label: {
                            Circle().fill(SummaryPresentation.background(color))
                                .overlay(Circle().strokeBorder(
                                    self.configuration.color == color ? Color.primary : .secondary.opacity(0.3),
                                    lineWidth: self.configuration.color == color ? 2 : 1))
                                .overlay {
                                    if self.configuration
                                        .color == color { Image(systemName: "checkmark").font(.caption) }
                                }
                                .frame(width: 32, height: 32)
                                .frame(minWidth: 36, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(SummaryPresentation.colorName(color))
                        .accessibilityAddTraits(self.configuration.color == color ? .isSelected : [])
                        .accessibilityIdentifier("summary-color-\(color.rawValue)")
                    }
                }
            }
            .listRowBackground(MobileSurfaceStyle.rowBackground)
            if case .depletion = self.configuration.metric {
                Section {
                    Text(
                        String(
                            localized: "This predicts when the selected quota may run out at its observed usage rate. It is separate from the reset time."))
                }
                .listRowBackground(MobileSurfaceStyle.rowBackground)
            }
            if !self.isNew {
                Section {
                    Button(String(localized: "Unpin"), role: .destructive) {
                        self.preferences.remove(id: self.configuration.id)
                        self.dismiss()
                    }
                    .accessibilityIdentifier("summary-unpin")
                }
                .listRowBackground(MobileSurfaceStyle.rowBackground)
            }
        }
        .mobilePageSurface()
        .navigationTitle(self.isNew ? String(localized: "Create card") : String(localized: "Customize card"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { self.dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(self.isNew ? String(localized: "Add card") : String(localized: "Save card")) {
                    self.preferences.setAccountAlias(
                        self.accountAlias,
                        accountAnchorID: self.configuration.accountAnchorID)
                    if self.isNew { self.preferences.add(self.draft) } else { self.preferences.update(self.draft) }
                    self.dismiss()
                }
                .disabled(self.preferences.isReadOnly)
                .accessibilityIdentifier("summary-save")
            }
        }
    }
}

struct SummaryOrderEditor: View {
    @ObservedObject var preferences: SummaryPreferencesStore
    let accounts: [ProviderUsageSnapshot]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidesPersonalInfo = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(self.preferences.preferences.orderedItemIDs, id: \.self) { id in
                    if id == self.preferences.preferences.quotaModule?.id {
                        Label(String(localized: "Remaining Quota"), systemImage: "chart.xyaxis.line")
                            .accessibilityIdentifier("summary-order-quota-module")
                    } else if let card = self.preferences.resolvedCards(accounts: self.accounts).first(where: {
                        $0.id == id
                    }) {
                        VStack(alignment: .leading) {
                            Text(SummaryPresentation.redact(
                                self.hidesPersonalInfo ? card.privateTitle : card.compactTitle,
                                enabled: self.hidesPersonalInfo))
                            Text(card.metricTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { indices, destination in
                    var ids = self.preferences.preferences.orderedItemIDs
                    ids.move(fromOffsets: indices, toOffset: destination)
                    self.preferences.reorderItems(ids: ids)
                }
                .onDelete { indices in
                    let ids = self.preferences.preferences.orderedItemIDs
                    for index in indices {
                        self.preferences.removeItem(id: ids[index])
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(String(localized: "Edit Order"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { self.dismiss() }
                        .accessibilityIdentifier("summary-order-done")
                }
            }
        }
    }
}
