import CodexBarSync
import SwiftUI

/// Research 080: a personally selected set of metrics, separate from full account details.
struct SummaryTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool
    @ObservedObject var preferences: SummaryPreferencesStore
    @ObservedObject var quotaStore: UsageQuotaOverviewStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.mobileAdaptiveLayout) private var layout
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidesPersonalInfo = false
    @State private var timelineStart = Date.now
    @State private var selectedProviderID: String?
    @State private var detailPath: [UUID] = []
    @State private var editing = false
    @State private var showingAdd = false
    @State private var showingOrder = false
    @State private var showingInfo = false
    @State private var editingCard: SummaryCardConfiguration?

    private var usesDemoData: Bool {
        self.isDemoMode || ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA")
    }

    private var accounts: [ProviderUsageSnapshot] {
        let snapshot = self.isDemoMode ? PreviewData.sampleSnapshot : self.usageData.snapshot
        return snapshot.map { MockProviderDetector.filteredProviders(from: $0) }
            .map { $0.filter { !$0.isProviderLevelCostEnvelope } } ?? []
    }

    private var revision: String {
        "\(self.isDemoMode)|\(self.usageData.publicationRevision)|" + self.accounts.map {
            "\($0.cardIdentityKey)|\($0.lastUpdated.timeIntervalSince1970)|\(UsageAccountIdentity.tokens(for: $0).sorted())"
        }.joined(separator: ";") + self.usageData.providerLinkages.map { "\($0.recordID)|\($0.unmerge)" }.sorted()
            .joined(separator: ";")
    }

    var body: some View {
        TimelineView(.periodic(from: self.timelineStart, by: 30)) { context in
            self.workspace(now: context.date)
        }
        .task(id: self.revision) {
            self.preferences.reconcile(
                accounts: self.accounts, linkages: self.usesDemoData ? [] : self.usageData.providerLinkages)
            self.reconcileSelection()
        }
        .onChange(of: self.quotaStore.preferences.selections) { _, _ in self.reconcileSelection() }
        .onChange(of: self.preferences.preferences.quotaModule) { _, _ in self.reconcileSelection() }
        .onChange(of: self.preferences.preferences.cards) { _, _ in self.reconcileSelection() }
        .onChange(of: self.selectedProviderID) { _, _ in self.reconcileSelection() }
        .sheet(isPresented: self.$showingAdd) {
            SummaryAddFlow(preferences: self.preferences, accounts: self.accounts)
        }
        .sheet(item: self.$editingCard) { configuration in
            NavigationStack {
                SummaryCardEditor(
                    configuration: configuration, preferences: self.preferences,
                    accounts: self.accounts, isNew: false)
            }
        }
        .sheet(isPresented: self.$showingOrder) {
            SummaryOrderEditor(preferences: self.preferences, accounts: self.accounts)
        }
        .sheet(isPresented: self.$showingInfo) { SummaryInfoView() }
    }

    private func workspace(now: Date) -> some View {
        let cards = self.preferences.resolvedCards(accounts: self.accounts, now: now)
        let filtered = cards
            .filter { self.selectedProviderID == nil || $0.configuration.providerID == self.selectedProviderID }
        let hasModule = self.preferences.preferences.quotaModule != nil
        return NavigationStack(path: self.$detailPath) {
            VStack(spacing: 0) {
                // In a short landscape window, chrome scrolls away so a complete four-tile
                // chart can fit between native navigation and the tab bar without shrinking it.
                if !self.layout.usesShortHeight || (cards.isEmpty && !hasModule) {
                    self.dataBanner
                    if !cards.isEmpty || hasModule { self.providerFilters(cards: cards) }
                }
                if self.preferences.isReadOnly {
                    ContentUnavailableView(
                        String(localized: "Summary settings unavailable"), systemImage: "exclamationmark.triangle",
                        description: Text(
                            String(
                                localized: "Saved Summary settings could not be read. They have been kept unchanged.")))
                } else if self.accounts.isEmpty, cards.isEmpty, !hasModule {
                    EmptyStateView(
                        title: "Waiting for Mac Sync",
                        message: "Open CodexBar on your Mac and enable iCloud Sync to bring usage data to this iPhone.",
                        onDemo: { self.isDemoMode = true })
                } else if cards.isEmpty, !hasModule {
                    ContentUnavailableView {
                        Label(String(localized: "Your Summary"), systemImage: "square.grid.2x2")
                    } description: {
                        Text(String(localized: "Choose the metrics you want to see at a glance."))
                    } actions: {
                        Button(String(localized: "Add metric")) { self.showingAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    self.grid(cards: filtered, filterCards: cards, total: cards.count, now: now)
                }
            }
            .navigationTitle(String(localized: "Summary"))
            .background(MobileSurfaceStyle.pageBackground)
            .toolbar {
                if self.isDemoMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "Exit Demo")) { self.isDemoMode = false }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !cards.isEmpty || hasModule {
                        Button(self.editing ? String(localized: "Done") : String(localized: "Edit")) {
                            self.editing.toggle()
                        }
                        .accessibilityIdentifier("summary-edit")
                        Menu {
                            Button(String(localized: "Edit Order"), systemImage: "arrow.up.arrow.down") {
                                self.showingOrder = true
                            }
                            Button(String(localized: "About Summary"), systemImage: "info.circle") {
                                self.showingInfo = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(String(localized: "Summary options"))
                        .accessibilityIdentifier("summary-more")
                    }
                    Button {
                        self.showingAdd = true
                    } label: {
                        Label(String(localized: "Add metric"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("summary-add")
                }
            }
            .disabled(self.preferences.isReadOnly)
            .navigationDestination(for: UUID.self) { id in
                if id == self.preferences.preferences.quotaModule?.id {
                    UsageQuotaDetailView(
                        store: self.quotaStore, summaryPreferences: self.preferences,
                        accounts: self.accounts, sourceSnapshots: self.usageData.deviceSnapshots,
                        isDemoMode: self.usesDemoData, now: now, providerFilterID: self.selectedProviderID)
                } else if let card = cards.first(where: { $0.id == id }), let provider = card.provider {
                    ProviderDetailView(
                        group: ProviderAccountGroup(
                            providerID: provider.providerID, providerName: provider.providerName, accounts: [provider]),
                        sourceSnapshots: self.usageData.deviceSnapshots,
                        isDemoMode: self.isDemoMode)
                        .id(provider.cardIdentityKey)
                        .accessibilityIdentifier("summary-selected-detail-" + provider.providerID)
                }
            }
        }
    }

    private func grid(
        cards: [SummaryResolvedCard],
        filterCards: [SummaryResolvedCard],
        total: Int,
        now: Date) -> some View
    {
        GeometryReader { geometry in
            let count = SummaryModulePacking.columnCount(
                width: geometry.size.width, shortHeight: self.layout.usesShortHeight,
                accessibility: self.dynamicTypeSize.isAccessibilitySize)
            let moduleCount = self.preferences.preferences.quotaModule == nil ? 0 : 1
            let visibleModuleCount = moduleCount == 1 &&
                (self.selectedProviderID == nil || self.quotaStore.preferences.selections.contains {
                    $0.providerID == self.selectedProviderID
                }) ? 1 : 0
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if self.layout.usesShortHeight {
                        self.dataBanner.frame(maxWidth: .infinity)
                        self.providerFilters(cards: filterCards, horizontalPadding: 0)
                    }
                    Text(String(
                        format: String(localized: "%lld of %lld pinned"),
                        Int64(cards.count + visibleModuleCount),
                        Int64(total + moduleCount)))
                        .font(.caption2).foregroundStyle(.secondary)
                        // A Layout is not an accessibility container: its identifier would
                        // propagate onto every metric and module. Mark this standalone label.
                        .accessibilityIdentifier("summary-grid-columns-\(count)")
                    SummaryModuleGrid(columns: count) {
                        ForEach(self.preferences.preferences.orderedItemIDs, id: \.self) { id in
                            if id == self.preferences.preferences.quotaModule?.id {
                                if self.selectedProviderID == nil || self.quotaStore.preferences.selections
                                    .contains(where: {
                                        $0.providerID == self.selectedProviderID
                                    })
                                {
                                    self.quotaModule(now: now)
                                        .layoutValue(key: SummaryModuleSpan.self, value: true)
                                }
                            } else if let card = cards.first(where: { $0.id == id }) {
                                self.metricButton(card: card, now: now)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .accessibilityIdentifier("summary-grid")
            .refreshable {
                if !self.isDemoMode, !ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA") {
                    await self.usageData.refresh()
                }
            }
        }
    }

    private func quotaModule(now: Date) -> some View {
        UsageQuotaOverviewView(
            store: self.quotaStore, accounts: self.accounts,
            linkages: self.usesDemoData ? [] : self.usageData.providerLinkages,
            sourceSnapshots: self.usesDemoData ? nil : self.usageData.deviceSnapshots,
            quotaSources: self.usesDemoData ? nil : self.usageData.snapshot?.providerQuotaSources,
            publicationRevision: self.revision, isSummaryModule: true, reconcileOnAppearance: false,
            providerFilterID: self.selectedProviderID, referenceDate: now,
            openDetail: {
                if !self.editing, let id = self.preferences.preferences.quotaModule?.id { self.detailPath = [id] }
            })
            .overlay(alignment: .topLeading) {
                if self.editing {
                    Button(role: .destructive) {
                        if let id = self.preferences.preferences.quotaModule?.id { self.preferences.removeItem(id: id) }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title3)
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .red)
                    }
                    .accessibilityLabel(String(localized: "Unpin"))
                    .accessibilityIdentifier("summary-remove-quota-module")
                    .offset(x: -6, y: -6)
                }
            }
            .contextMenu {
                Button(String(localized: "Unpin"), systemImage: "pin.slash", role: .destructive) {
                    if let id = self.preferences.preferences.quotaModule?.id { self.preferences.removeItem(id: id) }
                }.accessibilityIdentifier("summary-remove-quota-module")
            }
    }

    private func metricButton(card: SummaryResolvedCard, now: Date) -> some View {
        Button {
            if self.editing { self.editingCard = card.configuration }
            else if card.provider != nil { self.detailPath = [card.id] }
            else { self.editingCard = card.configuration }
        } label: {
            SummaryMetricTile(card: card, now: now, editing: self.editing)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("summary-card-\(card.configuration.providerID)-\(card.id.uuidString)")
        .contextMenu {
            Button(String(localized: "Customize card"), systemImage: "pencil") {
                self.editingCard = card.configuration
            }
            Button(String(localized: "Unpin"), systemImage: "pin.slash", role: .destructive) {
                self.preferences.remove(id: card.id)
            }
        }
    }

    @ViewBuilder private var dataBanner: some View {
        if self.usesDemoData {
            Label(String(localized: "Showing demo data"), systemImage: "sparkles")
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
        } else {
            MockProviderBanner(snapshot: self.usageData.snapshot)
        }
    }

    private func providerFilters(cards: [SummaryResolvedCard], horizontalPadding: CGFloat = 16) -> some View {
        let moduleProviders = self.preferences.preferences.quotaModule == nil ? [] : self.quotaStore.preferences
            .selections.map(\.providerID)
        let ids = Array(Set(cards.map(\.configuration.providerID) + moduleProviders)).sorted()
        return ScrollView(.horizontal) {
            HStack(spacing: 7) {
                self.providerButton(nil, title: String(localized: "All providers"))
                ForEach(ids, id: \.self) { id in
                    self.providerButton(id, title: SummaryPresentation.providerName(id: id, accounts: self.accounts))
                }
            }
            .padding(.horizontal, horizontalPadding).padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("summary-provider-filters")
    }

    private func providerButton(_ id: String?, title: String) -> some View {
        Button { self.selectedProviderID = id } label: {
            Text(SummaryPresentation.redact(title, enabled: self.hidesPersonalInfo)).font(.caption).lineLimit(1)
                .padding(.horizontal, 10).frame(minHeight: 34)
                .foregroundStyle(Color.primary)
                .background(
                    self.selectedProviderID == id ? Color.accentColor
                        .opacity(0.15) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(self.selectedProviderID == id ? .isSelected : [])
        .accessibilityIdentifier("summary-filter-\(id ?? "all")")
    }

    private func reconcileSelection() {
        let cards = self.preferences.preferences.cards
        let resolved = self.preferences.resolvedCards(accounts: self.accounts)
        if let id = self.selectedProviderID, !cards.contains(where: { $0.providerID == id }),
           !(self.preferences.preferences.quotaModule != nil && self.quotaStore.preferences.selections.contains(where: {
               $0.providerID == id
           }))
        {
            self.selectedProviderID = nil
        }
        if let id = self.detailPath.last, id != self.preferences.preferences.quotaModule?.id,
           !resolved.contains(where: { $0.id == id && $0.provider != nil
                   && (self.selectedProviderID == nil || $0.configuration.providerID == self.selectedProviderID)
           })
        {
            self.detailPath = []
        }
    }
}

struct SummaryMetricTile: View {
    let card: SummaryResolvedCard
    let now: Date
    var editing = false
    var editingTitle: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidesPersonalInfo = false

    private var displayTitle: String {
        self.editingTitle ?? SummaryPresentation.redact(
            self.hidesPersonalInfo ? self.card.privateTitle : self.card.compactTitle,
            enabled: self.hidesPersonalInfo)
    }

    private var mayShowValue: Bool {
        self.card.state == .available || self.card.state == .stale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(self.displayTitle).font(.caption.weight(.medium))
                    .lineLimit(self.dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(self.card.configuration.title == nil ? .middle : .tail)
                if self.editing { Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary) }
            }
            if !self.mayShowValue {
                Text(SummaryPresentation.stateTitle(self.card.state))
                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(self.card.metricTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                self.valueContent
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(12)
        .background(
            self.card.configuration.color == .white
                ? AnyShapeStyle(MobileSurfaceStyle.cardMaterial)
                : AnyShapeStyle(SummaryPresentation.background(self.card.configuration.color)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityDescription)
        .accessibilityHint(self
            .editing ? String(localized: "Customize this card") : String(localized: "Open account details"))
    }

    @ViewBuilder private var valueContent: some View {
        switch self.card.configuration.metric {
        case .depletion:
            switch self.card.forecast {
            case let .emptyAt(date):
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(date, format: .dateTime.month(.abbreviated).day()).font(.subheadline)
                        Text(date, format: .dateTime.hour().minute()).font(.title2.weight(.semibold))
                    }
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                .monospacedDigit()
            case .lastsUntilReset:
                Text(String(localized: "Lasts until reset")).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                Text(String(localized: "Not enough recent data")).font(.caption).foregroundStyle(.secondary)
            }
            Text(self.depletionTitle).font(.caption2).foregroundStyle(.secondary)
            if self.card.isStale { self.staleLabel }
        case .quota:
            self.valueRow(title: self.card.metricTitle, value: self.primaryValue)
            HStack(spacing: 3) {
                if self.card.isStale { self.staleLabel }
                else if self.card.effectiveEmphasis == .countdown {
                    Text(String(localized: "to reset") + " · "
                        + SummaryPresentation.percent(self.card.usedPercent) + " " + String(localized: "used"))
                } else if let reset = self.card.resetDate {
                    Text(String(
                        format: String(localized: "Resets in %@"),
                        SummaryPresentation.countdown(to: reset, now: self.now)))
                    Spacer(minLength: 0)
                } else {
                    Text(String(localized: "used"))
                }
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .balance:
            self.valueRow(title: self.card.metricTitle, value: SummaryPresentation.amount(self.card.amount))
            if self.card.isStale { self.staleLabel }
            else { Text(String(localized: "Last observed")).font(.caption2).foregroundStyle(.secondary) }
        case .extraUsage:
            self.valueRow(
                title: self.card.metricTitle,
                value: self.card.amount != nil
                    ? SummaryPresentation.amount(self.card.amount) : SummaryPresentation.percent(self.card.usedPercent))
            if self.card.isStale { self.staleLabel }
            else if self.card.usedPercent != nil {
                Text(SummaryPresentation.percent(self.card.usedPercent) + " " + String(localized: "used"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func valueRow(title: String, value: String) -> some View {
        if self.dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title).font(.caption).foregroundStyle(.secondary).fixedSize()
                    Spacer(minLength: 0)
                    Text(value).font(.title2.weight(.semibold)).monospacedDigit().fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var depletionTitle: String {
        guard let provider = self.card.provider,
              let candidate = QuotaPaceWindowSelection.candidates(for: provider)
                  .first(where: { $0.id == self.card.configuration.metric.windowID })
        else { return self.card.metricTitle }
        let window = QuotaPaceWindowSelection.title(of: candidate, providerID: provider.providerID)
        return String(format: String(localized: "%@ · Est. empty"), window)
    }

    private var primaryValue: String {
        if self.card.effectiveEmphasis == .countdown, let reset = self.card.resetDate {
            return SummaryPresentation.countdown(to: reset, now: self.now)
        }
        return SummaryPresentation.percent(self.card.usedPercent)
    }

    private var staleLabel: some View {
        Label(String(localized: "Out of date"), systemImage: "clock.badge.exclamationmark")
            .font(.caption2).foregroundStyle(.orange)
    }

    private var accessibilityDescription: String {
        let value: String = if !self.mayShowValue {
            SummaryPresentation.stateTitle(self.card.state)
        } else if case .depletion = self.card.configuration.metric {
            switch self.card.forecast {
            case let .emptyAt(date): date.formatted(date: .abbreviated, time: .shortened)
            case .lastsUntilReset: String(localized: "Lasts until reset")
            case nil: String(localized: "Not enough recent data")
            }
        } else if case .quota = self.card.configuration.metric {
            (self.card.effectiveEmphasis == .countdown ? String(
                format: String(localized: "Resets in %@"),
                self.primaryValue) + ", " : "")
                + SummaryPresentation.percent(self.card.usedPercent) + " " + String(localized: "used")
        } else if case .extraUsage = self.card.configuration.metric {
            SummaryPresentation.extraUsageDescription(amount: self.card.amount, usedPercent: self.card.usedPercent)
        } else {
            SummaryPresentation.amount(self.card.amount)
        }
        return [
            SummaryPresentation.redact(
                SummaryPresentation.providerName(
                    id: self.card.configuration.providerID,
                    accounts: self.card.provider.map { [$0] } ?? []),
                enabled: self.hidesPersonalInfo),
            self.displayTitle,
            self.card.accountTitle == self.displayTitle ? ""
                : SummaryPresentation.redact(self.card.accountTitle, enabled: self.hidesPersonalInfo),
            self.card.metricTitle,
            value,
            self.card.isStale ? String(localized: "Out of date") : "",
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum SummaryPresentation {
    static func extraUsageDescription(amount: SummaryCardAmount?, usedPercent: Double?) -> String {
        [amount.map(Self.amount) ?? "", usedPercent.map { Self.percent($0) + " " + String(localized: "used") } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func providerName(id: String, accounts: [ProviderUsageSnapshot]) -> String {
        let names = [
            "claude": "Claude",
            "codex": "Codex",
            "openai": "OpenAI API",
            "grok": "Grok",
            "muse": "Muse Code",
            "openrouter": "OpenRouter",
            "gemini": "Gemini",
            "cursor": "Cursor",
        ]
        return names[id] ?? accounts.first(where: { $0.providerID == id }).map {
            $0.providerName.components(separatedBy: " · ").first ?? id
        } ?? id
    }

    static func redact(_ value: String, enabled: Bool) -> String {
        ProviderUsageView.visibleOrganization(value, hidePersonalInfo: enabled) ?? value
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func countdown(to reset: Date, now: Date) -> String {
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return String(localized: "Waiting for update") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 86400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, seconds)) ?? String(localized: "Waiting for update")
    }

    static func amount(_ amount: SummaryCardAmount?) -> String {
        guard let amount, amount.value.isFinite else { return "—" }
        let value: String = if let currency = amount.currencyCode,
                               currency.caseInsensitiveCompare("Credits") == .orderedSame
        {
            ProviderAmountCard.formattedAmount(amount.value, currencyCode: "Credits")
        } else if let currency = amount.currencyCode,
                  Locale.commonISOCurrencyCodes.contains(currency.uppercased())
        {
            amount.value.formatted(.currency(code: currency.uppercased()).precision(.fractionLength(0...2)))
        } else {
            amount.value.formatted(.number.precision(.fractionLength(0...2)))
                + (amount.currencyCode.map { " " + $0 } ?? "")
        }
        return (amount.isEstimated ? "~" : "") + value
    }

    static func stateTitle(_ state: SummaryCardState) -> String {
        switch state {
        case .available: ""
        case .stale: String(localized: "Out of date")
        case .unknown: String(localized: "Unknown usage")
        case .resetPassed: String(localized: "Waiting for update")
        case .blocked: String(localized: "Blocked by another quota")
        case .missingAccount: String(localized: "Account unavailable")
        case .missingMetric: String(localized: "Metric unavailable")
        case .unavailable: String(localized: "Unavailable")
        case .disabled: String(localized: "Disabled")
        }
    }

    static func background(_ color: SummaryCardColor) -> Color {
        switch color {
        case .white: Color(.secondarySystemFill)
        case .blue: Color.blue.opacity(0.12)
        case .green: Color.green.opacity(0.12)
        case .orange: Color.orange.opacity(0.12)
        case .purple: Color.purple.opacity(0.12)
        case .pink: Color.pink.opacity(0.12)
        }
    }

    static func colorName(_ color: SummaryCardColor) -> String {
        switch color {
        case .white: String(localized: "Default")
        case .blue: String(localized: "Blue")
        case .green: String(localized: "Green")
        case .orange: String(localized: "Orange")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        }
    }
}
