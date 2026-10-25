import CodexBarSync
import SwiftUI

/// One clock is supplied by Summary. Inspection changes neither live values nor saved selection.
struct UsageQuotaDetailView: View {
    @ObservedObject var store: UsageQuotaOverviewStore
    @ObservedObject var summaryPreferences: SummaryPreferencesStore
    let accounts: [ProviderUsageSnapshot]
    let sourceSnapshots: [SyncedUsageSnapshot]
    let isDemoMode: Bool
    let now: Date
    var providerFilterID: String?
    var body: some View {
        // Resolve source identity and merge history only when source/clock inputs change.
        // Interaction state belongs to the child, so scrubbing and sheet/navigation taps
        // cannot re-enter the projection through a computed property or Binding getter.
        let snapshot = UsageQuotaDetailSnapshot(
            overview: self.store.overview(accounts: self.accounts, now: self.now),
            providerFilterID: self.providerFilterID)
        UsageQuotaDetailContent(
            snapshot: snapshot, quotaPreferences: self.store.preferences, isReadOnly: self.store.isReadOnly,
            summaryPreferences: self.summaryPreferences.preferences, store: self.store,
            accounts: self.accounts, sourceSnapshots: self.sourceSnapshots,
            isDemoMode: self.isDemoMode, now: self.now)
    }
}

private struct UsageQuotaDetailContent: View {
    let snapshot: UsageQuotaDetailSnapshot
    let quotaPreferences: UsageQuotaPreferences
    let isReadOnly: Bool
    let summaryPreferences: SummaryPreferences
    // A command target for the editor, not an observation source for interaction state.
    let store: UsageQuotaOverviewStore
    let accounts: [ProviderUsageSnapshot]
    let sourceSnapshots: [SyncedUsageSnapshot]
    let isDemoMode: Bool
    let now: Date
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidesPersonalInfo = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.mobileAdaptiveLayout) private var layout
    @State private var focusedID: UUID?
    @State private var selectedDate: Date?
    @State private var showingEditor = false
    @State private var selectedAccountID: UUID?
    @State private var showingAccount = false

    private var overview: UsageQuotaOverview {
        self.snapshot.overview
    }

    private var displayed: UsageQuotaOverview {
        self.snapshot.displayed(focusedID: self.focusedID)
    }

    private var sliderDate: Date? {
        self.selectedDate ?? self.snapshot.latestDate(focusedID: self.focusedID)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 32)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if self.isReadOnly {
                        ContentUnavailableView(
                            String(localized: "Unavailable"), systemImage: "exclamationmark.triangle",
                            description: Text(
                                String(
                                    localized: "Saved quota settings could not be read. They have been kept unchanged.")))
                    } else if self.overview.lines.isEmpty {
                        ContentUnavailableView {
                            Label(String(localized: "Remaining Quota"), systemImage: "chart.xyaxis.line")
                        } description: {
                            Text(
                                String(
                                    localized: "Choose up to 5 account quotas to compare their remaining quota history."))
                        } actions: {
                            Button(String(localized: "Choose quota lines")) { self.showingEditor = true }
                        }
                    } else {
                        self.historyCard(width: contentWidth)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "Current quotas")).font(.headline)
                            Text(String(localized: "Ordered by next reset")).font(.caption).foregroundStyle(.secondary)
                            ForEach(UsageQuotaDetailPresentation.currentLines(
                                self.overview.lines,
                                now: self.now))
                            { line in
                                self.currentRow(line)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(
                                String(
                                    localized: "Blank intervals have no observations. Displayed values retain their original observation times."))
                            if self.overview.lines.contains(where: \.usesSyncedProviderHistory) {
                                Text(
                                    String(
                                        localized: "The chart combines readings saved on this iPhone with available provider history shown in the details. Provider history is not account-verified and is omitted when multiple accounts or conflicting sources make it ambiguous. Missing or outdated readings are not new activity."))
                            }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("quota-detail-history-notice")
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(16)
                // Leave readable breathing room above the home indicator/native tab surface
                // when the last explanatory lines reach the end of the scroll content.
                .padding(.bottom, max(16, geometry.safeAreaInsets.bottom))
            }
            .accessibilityIdentifier("quota-detail-scroll")
        }
        .background(MobileSurfaceStyle.pageBackground)
        .navigationTitle(String(localized: "Remaining Quota"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { self.showingEditor = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(self.isReadOnly)
                .accessibilityLabel(String(localized: "Choose quota lines"))
                .accessibilityIdentifier("quota-detail-edit")
            }
        }
        .sheet(isPresented: self.$showingEditor) {
            UsageQuotaEditor(store: self.store, accounts: self.accounts)
        }
        .navigationDestination(isPresented: self.$showingAccount) {
            if let id = self.selectedAccountID,
               let line = self.overview.lines.first(where: { $0.id == id }), let provider = line.provider
            {
                ProviderDetailView(
                    group: ProviderAccountGroup(
                        providerID: provider.providerID,
                        providerName: provider.providerName,
                        accounts: [provider]),
                    sourceSnapshots: self.sourceSnapshots, isDemoMode: self.isDemoMode)
                    .id(provider.cardIdentityKey)
                    .accessibilityIdentifier("quota-detail-account-" + id.uuidString)
            } else {
                ContentUnavailableView(
                    String(localized: "Account unavailable"),
                    systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .onChange(of: self.overview.lines.map(\.id)) { _, ids in
            if let focusedID = self.focusedID, !ids.contains(focusedID) { self.focusedID = nil }
            if let selectedAccountID = self.selectedAccountID,
               !ids.contains(selectedAccountID) { self.showingAccount = false }
        }
        .onChange(of: self.overview.start) { _, _ in self.selectedDate = nil }
    }

    private func historyCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text((self.overview.start..<self.overview.end).formatted(.interval.month(.abbreviated).day()))
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("quota-detail-period")
            VStack(spacing: 0) {
                UsageQuotaHistoryChart(
                    overview: self.displayed, height: self.layout.usesShortHeight ? 180 : 240,
                    identifier: "quota-detail-chart", selection: Binding(
                        get: { self.selectedDate }, set: { if let date = $0 { self.selectedDate = date } }),
                    focusedLineID: self.focusedID)
            }
            .frame(width: max(0, width - 32))
            // Charts' synthetic AX nodes extend beyond the plot. Keep an actual layout
            // container separately identifiable without merging its accessible chart children.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quota-detail-chart-container")
            self.focusLegend
            self.readout
            Slider(
                value: Binding(
                    get: { (self.sliderDate ?? self.overview.start).timeIntervalSince1970 },
                    set: { self.selectedDate = Date(timeIntervalSince1970: $0) }),
                in: self.overview.start.timeIntervalSince1970...self.overview.end.timeIntervalSince1970)
                .accessibilityLabel(String(localized: "Inspect quota history"))
                .accessibilityValue((self.sliderDate ?? self.overview.start).formatted(
                    date: .abbreviated,
                    time: .shortened))
                .accessibilityIdentifier("quota-detail-scrubber")
            Text(String(localized: "Drag to inspect real observations. Tap a legend to focus one line."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(MobileSurfaceStyle.cardMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var focusLegend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button(String(localized: "Show all")) { self.focusedID = nil }
                    .buttonStyle(.bordered)
                    .accessibilityAddTraits(self.focusedID == nil ? .isSelected : [])
                    .accessibilityIdentifier("quota-detail-show-all")
                ForEach(self.overview.lines) { line in
                    Button {
                        self.focusedID = self.focusedID == line.id ? nil : line.id
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(self.color(line)).frame(width: 7, height: 7)
                            Text(self.title(line)).font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(self.focusedID == line.id ? self.color(line) : .secondary)
                    .accessibilityAddTraits(self.focusedID == line.id ? .isSelected : [])
                    .accessibilityIdentifier("quota-detail-line-" + line.id.uuidString)
                }
            }
        }.scrollIndicators(.hidden)
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let date = self.selectedDate {
                Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Latest observations"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(self.displayed.lines) { line in
                VStack(alignment: .leading, spacing: 3) {
                    if let point = UsageQuotaDetailPresentation.reading(
                        selectedDate: self.selectedDate, samples: line.observedSamples,
                        domain: self.overview.start...self.overview.end)
                    {
                        self.readingLayout {
                            Text(self.title(line)).font(.caption.weight(.medium))
                            if !self.dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 6) }
                            Text(SummaryPresentation.percent(point.remainingPercent))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        Text(String(
                            format: String(localized: "Observed %@"),
                            point.date.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        self.readingLayout {
                            Text(self.title(line)).font(.caption.weight(.medium))
                            if !self.dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 6) }
                            Text(String(localized: "No observation at this time")).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }.accessibilityElement(children: .combine)
            }
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("quota-detail-history-readout")
    }

    private var readingLayout: AnyLayout {
        self.dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    private var currentLayout: AnyLayout {
        self.dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private func currentRow(_ line: UsageQuotaResolvedLine) -> some View {
        Button {
            self.selectedAccountID = line.id
            self.showingAccount = true
        } label: {
            self.currentLayout {
                VStack(alignment: .leading, spacing: 5) {
                    Text(self.title(line)).font(.subheadline.weight(.semibold))
                    Text(self.accountTitle(line)).font(.caption).foregroundStyle(.secondary)
                    if let reset = line.resetDate, reset > self.now {
                        Text(String(
                            format: String(localized: "Resets in %@"),
                            SummaryPresentation.countdown(to: reset, now: self.now)))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(
                            format: String(localized: "Resets %@"),
                            reset.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let observed = line.observedAt {
                        Text(String(
                            format: String(localized: "Observed %@"),
                            observed.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if line.usesSyncedProviderHistory {
                        Text(String(localized: "Includes synced provider history")).font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if line.state != .available {
                        Text(SummaryPresentation.stateTitle(line.state)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !self.dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                VStack(alignment: self.dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                    Text(SummaryPresentation.percent(UsageQuotaDetailPresentation.currentRemaining(
                        line,
                        now: self.now)))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text(String(localized: "remaining")).font(.caption2).foregroundStyle(.secondary)
                }
                if line.provider != nil, !self.dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MobileSurfaceStyle.cardMaterial, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(line.provider == nil)
        .accessibilityValue(UsageQuotaDetailPresentation.currentRemaining(line, now: self.now).map {
            SummaryPresentation.percent($0)
        } ?? SummaryPresentation.stateTitle(line.state))
        .accessibilityIdentifier("quota-detail-current-" + line.id.uuidString)
    }

    private func title(_ line: UsageQuotaResolvedLine) -> String {
        UsageQuotaPresentation.shortTitle(
            line, providerName: SummaryPresentation.providerName(
                id: line.selection.providerID,
                accounts: self.accounts),
            preferences: self.quotaPreferences, hidesPersonalInfo: self.hidesPersonalInfo)
    }

    private func accountTitle(_ line: UsageQuotaResolvedLine) -> String {
        if !self.hidesPersonalInfo, let provider = line.provider {
            let stable = UsageAccountIdentity.tokens(for: provider).filter(UsageAccountIdentity.isStable)
            let matches = self.summaryPreferences.accountAnchors.filter {
                $0.providerID == line.selection.providerID && !stable
                    .isDisjoint(with: $0.tokens.filter(UsageAccountIdentity.isStable))
            }
            if matches.count == 1, let anchor = matches.first,
               let alias = self.summaryPreferences.accountAliases[anchor.id] { return alias }
        }
        return UsageQuotaPresentation.accountLabel(
            self.hidesPersonalInfo ? (line.privateAccountTitle ?? line.selection.providerID) : line.accountTitle,
            providerID: line.selection.providerID, anchorID: line.selection.accountAnchorID,
            preferences: self.quotaPreferences, hidesPersonalInfo: self.hidesPersonalInfo)
    }

    private func color(_ line: UsageQuotaResolvedLine) -> Color {
        ProviderColorPalette.color(for: line.selection.providerID, tintHex: line.selection.colorHex)
    }
}
