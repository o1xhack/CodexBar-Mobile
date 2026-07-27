import Charts
import CodexBarSync
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

enum CostChartStyle: String, CaseIterable, Identifiable {
    case bars
    case line

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .bars:
            String(localized: "Bar Chart")
        case .line:
            String(localized: "Line Chart")
        }
    }
}

private enum MobileRootTab: Hashable {
    case usage
    case cost
    case settings
}

struct ContentView: View {
    let usageData: SyncedUsageData
    @State private var isDemoMode = false
    @State private var selectedTab: MobileRootTab
    @State private var isWidgetSettingsPresented = false
    @AppStorage("onboardingSeenVersion") private var onboardingSeenVersion = ""

    init(usageData: SyncedUsageData) {
        self.usageData = usageData
        _selectedTab = State(initialValue: UserDefaults.standard
            .bool(forKey: MobileSettingsKeys.openCostByDefault) ? .cost : .usage)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var shouldShowOnboarding: Bool {
        self.onboardingSeenVersion != self.currentVersion
    }

    var body: some View {
        TabView(selection: self.$selectedTab) {
            UsageTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                .tag(MobileRootTab.usage)
                .tabItem {
                    Label("Usage", systemImage: "chart.bar.fill")
                }

            CostTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                .tag(MobileRootTab.cost)
                .tabItem {
                    Label("Cost", systemImage: "dollarsign.circle.fill")
                }

            SettingsTab(usageData: self.usageData)
                .tag(MobileRootTab.settings)
                .tabItem {
                    Label("Setting", systemImage: "gearshape")
                }
        }
        .modifier(TabBarMinimizeModifier())
        .onOpenURL { url in
            self.handleDeepLink(url)
        }
        .fullScreenCover(isPresented: .init(
            get: { self.shouldShowOnboarding },
            set: { if !$0 { self.onboardingSeenVersion = self.currentVersion } }))
        {
            OnboardingSheet(onDismiss: {
                self.onboardingSeenVersion = self.currentVersion
            }, onDemo: {
                self.onboardingSeenVersion = self.currentVersion
                self.isDemoMode = true
            })
        }
        .sheet(isPresented: self.$isWidgetSettingsPresented) {
                NavigationStack {
                    WidgetSettingsView(usageData: self.usageData)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    self.isWidgetSettingsPresented = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                }
            }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "codexbar" else { return }

        switch url.host?.lowercased() {
        case "widgets", "widget-settings":
            self.onboardingSeenVersion = self.currentVersion
            self.selectedTab = .settings
            self.isWidgetSettingsPresented = true
        default:
            break
        }
    }
}

private struct OnboardingSheet: View {
    let onDismiss: () -> Void
    let onDemo: () -> Void

    var body: some View {
        NavigationStack {
            OnboardingView(onDemo: self.onDemo)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            self.onDismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

/// Keeps the tab bar always visible (no auto-minimize on scroll).
private struct TabBarMinimizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

// MARK: - Usage Tab

private struct UsageTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool

    private var displaySnapshot: SyncedUsageSnapshot? {
        if self.isDemoMode {
            return PreviewData.sampleSnapshot
        }
        return self.usageData.snapshot
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = self.displaySnapshot {
                    if MockProviderDetector.filteredProviders(from: snapshot).isEmpty {
                        EmptyStateView(
                            title: "No Providers Enabled",
                            message: "Enable providers in CodexBar on your Mac to see usage data here.",
                            systemImage: "slider.horizontal.3")
                    } else {
                        ProviderListView(
                            snapshot: snapshot,
                            usageData: self.usageData,
                            isDemoMode: self.isDemoMode)
                    }
                } else {
                    OnboardingView(onDemo: { self.isDemoMode = true })
                }
            }
            .navigationTitle(self.isDemoMode ? String(localized: "CodexBar (Demo)") : String(localized: "CodexBar"))
            .toolbar {
                if self.isDemoMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.isDemoMode = false
                        } label: {
                            Text("Exit Demo")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Provider List

private struct ProviderListView: View {
    let snapshot: SyncedUsageSnapshot
    let usageData: SyncedUsageData
    let isDemoMode: Bool
    /// Local per-launch suppression of linkage prompts the user clicked
    /// "Keep separate" on. Persisted only across the current session —
    /// next launch re-evaluates so a user who reconsidered can confirm.
    /// Long-term persistence isn't needed since the candidate goes away
    /// the moment the legacy Mac upgrades (Research/019 §9 logic).
    @State private var dismissedCandidateKeys = Set<String>()
    /// Filters the Usage provider list by name / ID. Helps when many
    /// providers are synced (20+) and scrolling to find one is tedious.
    @State private var searchText = ""

    var body: some View {
        // Drop extinct mock zombies before any rendering so duplicate
        // cards (OLD vs NEW mock-injector designs) don't appear on the
        // Usage list. iOS 1.5.2+: see `MockProviderDetector.extinctMockProviderIDs`.
        let liveProviders = MockProviderDetector.filteredProviders(from: self.snapshot)
        // Compute linkage candidates ONCE per render. The detector handles
        // ambiguity rules (skips multi-account-named scenarios where we
        // can't tell which named card a legacy entry belongs to).
        let allCandidates = MultiAccountLinkageDetector.candidates(
            among: liveProviders,
            appVersionForProvider: { provider in
                // Find which device-snapshot this provider came from to
                // report its CodexBar version in the §9 hint. Falls back
                // to the merged snapshot's appVersion (the highest across
                // devices) — that's at least the "ceiling" of what other
                // Mac versions could be in play.
                let devices = self.usageData.deviceSnapshots
                if let device = devices.first(where: { snap in
                    snap.providers.contains { $0.cardIdentityKey == provider.cardIdentityKey }
                }) {
                    return device.appVersion
                }
                return nil
            })
        let candidatesByLegacyKey = Dictionary(
            uniqueKeysWithValues: allCandidates.map { ($0.legacy.cardIdentityKey, $0) })
        // Live linkages — used to expose an Unmerge context menu on cards
        // that originated from a confirmed merge group.
        let activeLinkagesByProviderID = Dictionary(
            grouping: self.usageData.providerLinkages.filter { !$0.unmerge },
            by: \.providerID)
        // Phase G — group by providerID so multi-account providers
        // (Codex × 3, OpenAI × 2 admins, Claude × 2 sessions, etc.) show
        // as ONE row in the Usage list instead of N. Tapping the row
        // navigates to ProviderDetailView which renders the segmented
        // account tab bar at the top, matching Mac UX. Cross-Mac
        // same-account merging already happened in `mergeSnapshots`
        // upstream of this grouping, so each group's accounts are all
        // distinct (no duplicates within).
        let groups = liveProviders.groupedByProvider()
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredGroups = query.isEmpty ? groups : groups.filter { group in
            group.representative.providerName.localizedCaseInsensitiveContains(query)
                || group.providerID.localizedCaseInsensitiveContains(query)
        }
        return ScrollView {
            LazyVStack(spacing: 16) {
                MockProviderBanner(snapshot: self.snapshot)
                ForEach(filteredGroups) { group in
                    // Within-group linkage candidate: surface on the
                    // group row if ANY account in the group has one
                    // (typically the legacy/missing-identity card).
                    // User confirms once, the underlying union-find
                    // collapses the candidate pair into one snapshot,
                    // and on next render the group shrinks by one.
                    let candidate: MultiAccountLinkageCandidate? = {
                        for account in group.accounts {
                            if let c = candidatesByLegacyKey[account.cardIdentityKey],
                               !self.dismissedCandidateKeys.contains(c.hashKey)
                            {
                                return c
                            }
                        }
                        return nil
                    }()
                    let activeLinkage = activeLinkagesByProviderID[group.providerID]?.first
                    NavigationLink {
                        ProviderDetailView(group: group)
                    } label: {
                        ProviderUsageView(
                            provider: group.representative,
                            duplicateOrdinal: nil,
                            accountCount: group.hasMultipleAccounts ? group.accounts.count : nil,
                            linkageCandidate: candidate,
                            activeLinkage: activeLinkage,
                            onConfirmMerge: { c in
                                Task { @MainActor in
                                    await self.usageData.confirmLinkage(
                                        providerID: c.named.providerID,
                                        linkedIdentifiers: c.linkedIdentifiers)
                                }
                            },
                            onDismissMergeCandidate: { c in
                                self.dismissedCandidateKeys.insert(c.hashKey)
                            },
                            onRevokeLinkage: { linkage in
                                Task { @MainActor in
                                    await self.usageData.revokeLinkage(
                                        providerID: linkage.providerID,
                                        linkedIdentifiers: linkage.linkedIdentifiers)
                                }
                            })
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("provider-group-\(group.providerID)")
                }

                if filteredGroups.isEmpty {
                    EmptyStateView(
                        title: "No matching providers",
                        message: "No provider matches your search. Try a different name.",
                        systemImage: "magnifyingglass")
                        .padding(.vertical, 32)
                }

                // Sync status at scroll bottom
                if self.isDemoMode {
                    Label("Showing demo data", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    SyncStatusBar(usageData: self.usageData)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await self.usageData.refresh()
        }
        .modifier(SoftScrollEdgeModifier())
        .searchable(
            text: self.$searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search providers"))
    }
}

/// Applies `.scrollEdgeEffectStyle(.soft)` on iOS 26+, no-op on older systems.
private struct SoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

// MARK: - Sync Status Bar

private struct SyncStatusBar: View {
    let usageData: SyncedUsageData

    var body: some View {
        VStack(spacing: 4) {
            if let snapshot = self.usageData.snapshot {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.syncTimestamp.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Data pushed by Mac · Pull to check for updates")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
    }
}

// MARK: - Cost Tab

enum CostLedgerDeviceFilter {
    static func activeDeviceIDs(for snapshots: [SyncedUsageSnapshot]) -> Set<String>? {
        let ids = Set(snapshots.map { snapshot in
            snapshot.deviceID ?? SwiftDataBridge.deviceIDFallback(for: snapshot)
        })
        return ids.isEmpty ? nil : ids
    }
}

enum CostLedgerRefreshClock {
    static func currentDayKey(now: Date = Date()) -> String {
        SyncCostSummary.iso8601DayKey(for: now)
    }

    static func nanosecondsUntilNextLocalDay(now: Date = Date()) -> UInt64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startOfDay = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now.addingTimeInterval(60)
        let seconds = max(1, nextDay.timeIntervalSince(now) + 1)
        return UInt64(seconds * 1_000_000_000)
    }
}

enum CostLedgerRefreshSignature {
    static func make(
        isEnabled: Bool,
        windowDays: Int,
        activeDeviceIDs: Set<String>?,
        snapshots: [SyncedUsageSnapshot],
        clearTombstone: Double,
        currentDayKey: String) -> String
    {
        guard isEnabled else {
            return "off"
        }
        let activeDeviceIDs = activeDeviceIDs?.sorted().joined(separator: ",") ?? "_"
        let latestSync = snapshots
            .map(\.syncTimestamp.timeIntervalSince1970)
            .max() ?? 0
        let latestProviderUpdate = snapshots
            .flatMap { $0.providers.map(\.lastUpdated.timeIntervalSince1970) }
            .max() ?? 0
        let providerCount = snapshots.reduce(0) { $0 + $1.providers.count }
        let providerIdentities = snapshots
            .flatMap { snapshot in
                snapshot.providers.map { provider in
                    "\(snapshot.deviceID ?? "_"):\(provider.cardIdentityKey)"
                }
            }
            .sorted()
            .joined(separator: ";")
        return [
            currentDayKey,
            "\(windowDays)",
            activeDeviceIDs,
            "\(latestSync)",
            "\(latestProviderUpdate)",
            "\(providerCount)",
            providerIdentities,
            "\(clearTombstone)",
        ].joined(separator: "|")
    }
}

enum CostTabInsightsResolver {
    static func make(
        snapshot: SyncedUsageSnapshot,
        ledgerAggregation: CostLedgerAggregation?,
        isLedgerEnabled: Bool,
        isDemoMode: Bool,
        localHistoryClearedAt: Date?,
        ledgerWindowDays: Int? = nil) -> CostDashboardInsights?
    {
        let insights = if isLedgerEnabled, !isDemoMode {
            if let aggregation = ledgerAggregation {
                if aggregation.hasDisplayData {
                    CostDashboardInsights.fromLedger(
                        aggregation: aggregation,
                        snapshot: snapshot,
                        snapshotFallbackCutoff: localHistoryClearedAt)
                } else if localHistoryClearedAt != nil {
                    CostDashboardInsights.fromLedger(
                        aggregation: aggregation,
                        snapshot: snapshot,
                        snapshotFallbackCutoff: localHistoryClearedAt)
                } else {
                    CostDashboardInsights(snapshot: snapshot)
                }
            } else if localHistoryClearedAt != nil {
                CostDashboardInsights.fromLedger(
                    aggregation: self.emptyAggregation(windowDays: ledgerWindowDays ?? 30),
                    snapshot: snapshot,
                    snapshotFallbackCutoff: localHistoryClearedAt)
            } else {
                CostDashboardInsights(snapshot: snapshot)
            }
        } else {
            CostDashboardInsights(snapshot: snapshot)
        }
        return insights.hasDisplayData ? insights : nil
    }

    private static func emptyAggregation(windowDays: Int) -> CostLedgerAggregation {
        CostLedgerAggregation(
            windowDays: windowDays,
            totalCostUSD: 0,
            totalTokens: 0,
            activeDayCount: 0,
            providerRollups: [:],
            dailyPoints: [],
            modelMix: [],
            serviceMix: [])
    }
}

enum CostDiagnosticsReportResolver {
    static func make(
        snapshot: SyncedUsageSnapshot,
        ledgerAggregation: CostLedgerAggregation?,
        rawDeviceSnapshots: [SyncedUsageSnapshot],
        activeDeviceSnapshots: [SyncedUsageSnapshot],
        cwlEnabled: Bool,
        cwlWindowDays: Int,
        localHistoryClearedAt: Date?) -> CostDiagnosticsReport?
    {
        guard let insights = CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: ledgerAggregation,
            isLedgerEnabled: cwlEnabled,
            isDemoMode: false,
            localHistoryClearedAt: localHistoryClearedAt,
            ledgerWindowDays: cwlWindowDays)
        else {
            return nil
        }

        let reportsLocalLedger = cwlEnabled && (
            ledgerAggregation?.hasDisplayData == true || localHistoryClearedAt != nil)

        return CostDiagnosticsReport.make(
            insights: insights,
            snapshot: snapshot,
            rawDeviceSnapshots: rawDeviceSnapshots,
            activeDeviceSnapshots: activeDeviceSnapshots,
            cwlEnabled: cwlEnabled,
            cwlWindowDays: cwlWindowDays,
            ledgerAvailable: reportsLocalLedger)
    }
}

enum CostDiagnosticsLedgerAggregationResolver {
    static func make(
        cwlEnabled: Bool,
        cwlWindowDays: Int,
        modelContext: ModelContext,
        activeDeviceIDs: Set<String>?) -> CostLedgerAggregation?
    {
        guard cwlEnabled else { return nil }
        return try? CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: cwlWindowDays,
            in: modelContext,
            activeDeviceIDs: activeDeviceIDs)
    }
}

private struct CostTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool
    @State private var showShareSheet = false
    @State private var cachedLedgerSignature: String?
    @State private var cachedLedgerAggregation: CostLedgerAggregation?

    // Round 6 / P4b — Cost Window Ledger dispatch. When `cwlEnabled` and not
    // in demo mode, the dashboard reads the ledger (re-windowed by
    // `cwlWindowDays`) instead of the blob path.
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MobileSettingsKeys.cwlEnabled) private var cwlEnabled = MobileSettingsDefaults.cwlEnabled
    @AppStorage(MobileSettingsKeys.cwlWindowDays) private var cwlWindowDays = MobileSettingsDefaults.cwlWindowDays
    @AppStorage(MobileSettingsKeys.cwlBlobSeedClearedAt) private var cwlBlobSeedClearedAt: Double = 0
    @State private var ledgerRefreshDayKey = CostLedgerRefreshClock.currentDayKey()

    private var displaySnapshot: SyncedUsageSnapshot? {
        if self.isDemoMode {
            return PreviewData.sampleSnapshot
        }
        return self.usageData.snapshot
    }

    /// Synchronous computed insights. `CostDashboardInsights.init` is O(providers × daily × breakdowns)
    /// which is fine to recompute per render here — Cost tab has no hover/selection state that would
    /// trigger frequent re-renders. (Hover-heavy views UtilizationAggregateView / UtilizationHistoryView
    /// use `@State` + `.task(id:)` caching because hover changes selection state every frame.)
    /// Synchronous compute ensures first render has data for UI tests and user-perceived responsiveness.
    private var currentInsights: CostDashboardInsights? {
        guard let snapshot = self.displaySnapshot else { return nil }
        let aggregation = self.shouldUseLedger && self.cachedLedgerSignature == self.ledgerRefreshSignature
            ? self.cachedLedgerAggregation
            : nil
        return CostTabInsightsResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: self.cwlEnabled,
            isDemoMode: self.isDemoMode,
            localHistoryClearedAt: CostLedgerService.blobSeedClearTombstoneDate(),
            ledgerWindowDays: self.cwlWindowDays)
    }

    private var activeDeviceIDsForLedger: Set<String>? {
        CostLedgerDeviceFilter.activeDeviceIDs(for: self.usageData.deviceSnapshots)
    }

    private var shouldUseLedger: Bool {
        self.cwlEnabled && !self.isDemoMode
    }

    private var ledgerRefreshSignature: String {
        CostLedgerRefreshSignature.make(
            isEnabled: self.shouldUseLedger,
            windowDays: self.cwlWindowDays,
            activeDeviceIDs: self.activeDeviceIDsForLedger,
            snapshots: self.usageData.deviceSnapshots,
            clearTombstone: self.cwlBlobSeedClearedAt,
            currentDayKey: self.ledgerRefreshDayKey)
    }

    @MainActor
    private func refreshLedgerAggregation(for signature: String) {
        guard self.shouldUseLedger else {
            self.cachedLedgerSignature = signature
            self.cachedLedgerAggregation = nil
            return
        }
        self.cachedLedgerAggregation = try? CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: self.cwlWindowDays,
            in: self.modelContext,
            activeDeviceIDs: self.activeDeviceIDsForLedger)
        self.cachedLedgerSignature = signature
    }

    var body: some View {
        NavigationStack {
            Group {
                if self.displaySnapshot != nil {
                    if let insights = self.currentInsights {
                        CostDashboardView(
                            insights: insights,
                            usageData: self.usageData,
                            isDemoMode: self.isDemoMode)
                    } else {
                        EmptyStateView(
                            title: "No Cost Data Yet",
                            message: "Enable cost collection in CodexBar on your Mac to see provider spend, breakdowns, and budgets here.",
                            systemImage: "dollarsign.gauge.chart.lefthalf.righthalf")
                    }
                } else {
                    OnboardingView(onDemo: { self.isDemoMode = true })
                }
            }
            .navigationTitle(self.isDemoMode ? String(localized: "Cost (Demo)") : String(localized: "Cost"))
            .toolbar {
                if self.isDemoMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.isDemoMode = false
                        } label: {
                            Text("Exit Demo")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
                if self.currentInsights != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: self.$showShareSheet) {
                if let insights = self.currentInsights {
                    CostShareSheet(insights: insights)
                }
            }
            .task(id: self.ledgerRefreshSignature) {
                self.refreshLedgerAggregation(for: self.ledgerRefreshSignature)
            }
            .task {
                await self.keepLedgerRefreshDayCurrent()
            }
        }
    }

    @MainActor
    private func keepLedgerRefreshDayCurrent() async {
        while !Task.isCancelled {
            let currentDayKey = CostLedgerRefreshClock.currentDayKey()
            if self.ledgerRefreshDayKey != currentDayKey {
                self.ledgerRefreshDayKey = currentDayKey
            }
            try? await Task.sleep(nanoseconds: CostLedgerRefreshClock.nanosecondsUntilNextLocalDay())
        }
    }
}

private struct CostDashboardView: View {
    let insights: CostDashboardInsights
    let usageData: SyncedUsageData
    let isDemoMode: Bool
    @AppStorage(MobileSettingsKeys.dashboardCostChartStyle) private var chartStyleRawValue = CostChartStyle.line
        .rawValue
    @State private var selectedDay: Date?

    private var chartStyle: CostChartStyle {
        CostChartStyle(rawValue: self.chartStyleRawValue) ?? .line
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MockProviderBanner(snapshot: self.usageData.snapshot)
                self.summarySection

                if !self.insights.spendProviderRows.isEmpty {
                    self.contributionSection(
                        title: "Provider Share",
                        subtitle: self.providerShareSubtitle,
                        rows: self.insights.spendProviderRows.map {
                            // `identityOverride: $0.id` carries the
                            // `providerID|accountEmail` composite key so
                            // multi-account scenarios (e.g. two Codex
                            // accounts surfaced by Mac ≥ 0.25 once email
                            // extraction lands) render as distinct rows
                            // instead of one row drawn twice.
                            CostBreakdownRow(
                                label: $0.provider.providerName,
                                amountUSD: $0.thirtyDayCost,
                                subtitle: self.providerSubtitle(for: $0),
                                color: providerTint(for: $0.provider),
                                identityOverride: $0.id)
                        },
                        total: self.insights.spendProviderRows.reduce(0) { $0 + $1.thirtyDayCost })
                }

                if !self.insights.dailyPoints.isEmpty {
                    self.trendSection
                }

                // Subscription Utilization — independent section
                if let snapshot = self.usageData.snapshot {
                    UtilizationAggregateView(
                        providers: MockProviderDetector.filteredProviders(from: snapshot))
                        .padding(.top, 4)
                }

                if !self.insights.modelRows.isEmpty {
                    self.contributionSection(
                        title: "Model Mix",
                        subtitle: "Top cost drivers across providers that expose model-level billing.",
                        rows: self.insights.modelRows,
                        total: self.insights.modelRows.reduce(0) { $0 + $1.amountUSD })
                }

                if !self.insights.serviceRows.isEmpty {
                    self.contributionSection(
                        title: "Codex Service Mix",
                        subtitle: "Breakdown from Codex Cloud dashboard data, including Codex Run and other billable services.",
                        rows: self.insights.serviceRows,
                        total: self.insights.serviceRows.reduce(0) { $0 + $1.amountUSD })
                }

                if !self.insights.budgetRows.isEmpty {
                    self.budgetSection
                }

                if self.isDemoMode {
                    Label("Showing demo data", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    SyncStatusBar(usageData: self.usageData)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await self.usageData.refresh()
        }
        .modifier(SoftScrollEdgeModifier())
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                CostMetricCard(
                    // Reflect the Mac's configurable 1–365 day window (gap F).
                    title: self.insights.historyDays.flatMap {
                        $0 == 30 ? nil : LocalizedStringResource("\($0) Days")
                    } ?? "30 Days",
                    value: Self.formatUSD(self.insights.total30DayCost),
                    subtitle: self.insights.total30DayTokens > 0 ? Self
                        .formatTokens(self.insights.total30DayTokens) : nil,
                    tintColor: .orange)

                CostMetricCard(
                    title: "Today",
                    value: Self.formatUSD(self.insights.totalTodayCost),
                    subtitle: self.providersActiveSubtitle,
                    tintColor: .mint)

                CostMetricCard(
                    title: "Top Driver",
                    value: Self.formatUSD(self.insights.topProvider?.thirtyDayCost ?? 0),
                    subtitle: self.topDriverSubtitle,
                    tintColor: providerTint(for: self.insights.topProvider?.provider))

                CostMetricCard(
                    title: "Active Days",
                    value: "\(self.insights.activeDayCount)",
                    subtitle: self.activeDaySubtitle,
                    tintColor: .blue)
            }
        }
    }

    /// Visible window on the Cost-tab daily-spend chart. 30 days is the user's
    /// cost-cycle mental model (monthly bills, budget windows) and matches
    /// `UtilizationAggregateView.windowSize` + `UtilizationHistoryView.windowSize`
    /// so every chart in the app tells the same 30-day story. This is the
    /// *maximum* on-screen viewport — `visibleDayCount` caps the visible window
    /// here, and the rest of a longer CWL window (50 / 90 / 365) scrolls
    /// horizontally instead of cramming every day into one screen.
    private static let chartVisibleDays: Int = 30

    /// Leading edge of the initial visible window, placed so the newest point
    /// sits at the right edge for whatever `visibleDayCount` is active. Must
    /// use `visibleDayCount`, not the static 30 — on a wider CWL window a
    /// 30-day anchor would scroll the viewport past the data into empty future
    /// space and hide the older days until the user scrolls back manually.
    private var chartScrollInitialDate: Date {
        guard let last = self.insights.dailyPoints.last?.date else { return Date() }
        return Calendar.current.date(
            byAdding: .day, value: -(self.visibleDayCount - 1), to: last) ?? last
    }

    /// Visible width of the daily-spend chart, in days — the on-screen *viewport*,
    /// NOT the data span. Capped at `chartVisibleDays` (30) so bars stay readable;
    /// the full accumulated history (e.g. a 50/90-day CWL window) scrolls
    /// horizontally via `.chartScrollableAxes`. With fewer than 30 days of data the
    /// window shrinks to the span so the chart isn't padded with empty space.
    /// (Previously this widened to the span — which crammed 50+ overlapping,
    /// non-scrollable bars into one screen; see the cost-chart scroll fix.)
    private var visibleDayCount: Int {
        let points = self.insights.dailyPoints
        guard let first = points.first?.date, let last = points.last?.date else {
            return Self.chartVisibleDays
        }
        let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        return min(Self.chartVisibleDays, span + 1)
    }

    /// Axis label stride in days — weekly for short windows, coarser for long
    /// ones so a 90- or 365-day chart doesn't cram a label every 7 days.
    private var axisStrideDays: Int {
        switch self.visibleDayCount {
        case ...35: 7
        case ...100: 14
        case ...200: 30
        default: 60
        }
    }

    /// Locale-independent "M/d" formatter (e.g. "4/18"), matching
    /// UtilizationHistoryView's axis style. Avoids `.dateTime` which rearranges
    /// to "d/M" on en_GB and similar locales.
    private static func dailyAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private var trendSection: some View {
        // Precompute axis values once per trendSection build. The input is `insights.dailyPoints`
        // which is stable across hover (`selectedDay`) changes, so we avoid recomputing
        // `axisValues(for:)` on every chart re-render triggered by selection.
        let yAxisValues = MobileChartAxisFormatter.axisValues(for: self.insights.dailyPoints.map(\.costUSD))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Daily Spend")
                    .font(.headline)
                Text("(USD)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cost-dashboard-daily-spend-title")

            Chart(self.insights.dailyPoints) { point in
                switch self.chartStyle {
                case .bars:
                    BarMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(Color.orange.gradient)
                        .cornerRadius(4)
                case .line:
                    AreaMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom))
                        .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(Color.orange)
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }

                if let selectedPoint = self.selectedPoint, selectedPoint.id == point.id {
                    RuleMark(x: .value(String(localized: "Selected Date"), selectedPoint.date))
                        .foregroundStyle(Color.orange.opacity(0.35))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value(String(localized: "Selected Date"), selectedPoint.date),
                        y: .value(String(localized: "Selected Cost"), selectedPoint.costUSD))
                        .foregroundStyle(Color.orange)
                        .symbolSize(80)
                }
            }
            .chartXSelection(value: self.$selectedDay)
            .chartScrollableAxes(.horizontal)
            // No extra right-side padding — axis labels use anchor .topTrailing
            // below so the label extends LEFT of the tick (slash just left of
            // the rightmost bar), matching UtilizationHistoryView's style.
            // The latest data is always on the right, so left-anchored labels
            // never clip regardless of how close the last bar is to the edge.
            .chartXVisibleDomain(length: self.visibleDayCount * 24 * 60 * 60)
            .chartScrollPosition(initialX: self.chartScrollInitialDate)
            .chartXAxis {
                // Adaptive weekly→monthly stride (see `axisStrideDays`): a
                // 30-day window keeps the 7-day cadence that matches the
                // share-card's 7-day chart, while 90/365-day windows widen the
                // stride so labels don't crowd. Density scales with the CWL
                // window the user picked.
                AxisMarks(values: .stride(by: .day, count: self.axisStrideDays)) { value in
                    AxisGridLine()
                    // Hard-coded "M/d" (locale-independent, same as
                    // UtilizationHistoryView). Anchor `.top` centers the label
                    // horizontally on the gridline — default axis anchor is
                    // `.topLeading` which extends the label to the right of the
                    // tick (what the user saw as 'wrong-side padding').
                    AxisValueLabel(anchor: .top) {
                        if let date = value.as(Date.self) {
                            Text(Self.dailyAxisLabel(for: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: yAxisValues) {
                    value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(MobileChartAxisFormatter.axisLabel(for: v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let selectedPoint = self.selectedPoint {
                HStack {
                    Text(Self.shortDate(selectedPoint.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatUSD(selectedPoint.costUSD))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.medium)
                    if selectedPoint.totalTokens > 0 {
                        Text("· \(Self.formatTokens(selectedPoint.totalTokens))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            } else {
                HStack(spacing: 12) {
                    Label(
                        "\(String(localized: "Peak")) \(Self.formatUSD(self.insights.highestDay?.costUSD ?? 0))",
                        systemImage: "arrow.up.right.circle.fill")
                    Label(
                        self.insights.highestDay.map { Self.shortDate($0.date) } ?? String(localized: "No data"),
                        systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func contributionSection(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        rows: [CostBreakdownRow],
        total: Double) -> some View
    {
        // iOS 1.9.0+: cap to top 5 + an "Others" row whenever there are 6 or
        // more entries; otherwise show all (a section with 3 real rows just
        // shows 3 — no Others fold below the 6-item threshold). The Others
        // row is wrapped in a NavigationLink that drills into a full list
        // with the same row style. Same cap automatically covers Provider
        // Share, Model Mix, and Codex Service Mix since all three call into
        // this function. Replaces the prior `prefix(6) without Others` which
        // silently dropped low-cost providers (e.g. Mistral at $0.85 in mock
        // would vanish behind 6 higher spenders even though it contributed
        // to the headline 30-day total).
        let cap = 5
        let usesOthers = rows.count >= cap + 1
        let visible: [CostBreakdownRow] = usesOthers ? Array(rows.prefix(cap)) : rows
        let tail: [CostBreakdownRow] = usesOthers ? Array(rows.dropFirst(cap)) : []
        let tailAmount = tail.reduce(0) { $0 + $1.amountUSD }

        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.top, 4)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(visible) { row in
                    CostBreakdownRowView(row: row, total: total)
                }
                if usesOthers {
                    NavigationLink {
                        FullBreakdownListView(
                            title: title,
                            rows: rows,
                            total: total)
                    } label: {
                        OthersBreakdownRowView(
                            count: tail.count,
                            amountUSD: tailAmount,
                            total: total)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var budgetSection: some View {
        // iOS 1.9.0+: cap to top 5 + Others when 6 or more budgets exist;
        // otherwise show all. Same rule as the contribution lists. The Others
        // row has no aggregate metric (summing budgets with different limits /
        // currencies isn't meaningful) — just the count + a chevron, tappable
        // → drills into a FullBudgetListView showing every budget.
        let cap = 5
        let rows = self.insights.budgetRows
        let usesOthers = rows.count >= cap + 1
        let visible: [CostBudgetRow] = usesOthers ? Array(rows.prefix(cap)) : rows
        let tailCount = usesOthers ? rows.count - cap : 0

        return VStack(alignment: .leading, spacing: 10) {
            Text("Budgets")
                .font(.headline)
                .padding(.top, 4)

            Text("Tracked provider budgets and how close they are to their current limit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(visible) { row in
                    BudgetRowView(row: row)
                }
                if usesOthers {
                    NavigationLink {
                        FullBudgetListView(rows: rows)
                    } label: {
                        OthersBudgetRowView(count: tailCount)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var providerShareSubtitle: LocalizedStringResource {
        guard let days = self.insights.historyDays, days != 30 else {
            return "30-day spend contribution across synced providers."
        }
        return "Spend contribution across the selected cost window."
    }

    private func providerSubtitle(for row: CostDashboardInsights.ProviderRow) -> String {
        let today = row.todayCost > 0
            ? "\(String(localized: "Today")) \(Self.formatUSD(row.todayCost))"
            : String(localized: "No spend today")
        let tokens = row.thirtyDayTokens > 0 ? Self
            .formatTokens(row.thirtyDayTokens) : String(localized: "No token data")
        return "\(today) · \(tokens)"
    }

    private var topDriverSubtitle: String? {
        guard let topProvider = self.insights.topProvider else { return nil }
        return "\(topProvider.provider.providerName) · \(Self.formatShare(topProvider.thirtyDayCost, total: self.insights.total30DayCost))"
    }

    private var activeDaySubtitle: String? {
        guard self.insights.activeDayCount > 0 else { return nil }
        let average = self.insights.total30DayCost / Double(self.insights.activeDayCount)
        return "\(String(localized: "Avg")) \(Self.formatUSD(average)) \(String(localized: "per active day"))"
    }

    private var providersActiveSubtitle: String {
        "\(self.insights.providerRows.count(where: { $0.todayCost > 0 }).formatted()) \(String(localized: "providers active"))"
    }

    private var selectedPoint: CostDashboardInsights.DailyPoint? {
        guard let selectedDay else { return nil }
        return self.insights.dailyPoints.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDay)
        })
    }

    private static func safeRatio(_ value: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    private static func formatShare(_ value: Double, total: Double) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", (value / total) * 100)
    }

    private static func formatUSD(_ value: Double) -> String {
        CostFormatting.usd(value)
    }

    private static func formatTokens(_ count: Int) -> String {
        CostFormatting.tokens(count)
    }

    private static func shortDate(_ value: Date) -> String {
        value.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct CostBreakdownMetricColumn: View {
    let amountText: String
    let shareText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(self.amountText)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                Text(self.shareText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .trailing, spacing: 2) {
                Text(self.amountText)
                    .font(.headline.monospacedDigit())
                    .fontWeight(.bold)
                Text(self.shareText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .layoutPriority(1)
    }
}

struct CostDashboardInsights {
    struct DailyPoint: Identifiable {
        let dayKey: String
        let date: Date
        let costUSD: Double
        let totalTokens: Int
        let modelBreakdowns: [SyncCostBreakdown]
        let serviceBreakdowns: [SyncCostBreakdown]

        init(
            dayKey: String,
            date: Date,
            costUSD: Double,
            totalTokens: Int,
            modelBreakdowns: [SyncCostBreakdown] = [],
            serviceBreakdowns: [SyncCostBreakdown] = [])
        {
            self.dayKey = dayKey
            self.date = date
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.modelBreakdowns = modelBreakdowns
            self.serviceBreakdowns = serviceBreakdowns
        }

        var id: String {
            self.dayKey
        }
    }

    struct ProviderRow: Identifiable {
        let provider: ProviderUsageSnapshot
        let thirtyDayCost: Double
        let todayCost: Double
        let thirtyDayTokens: Int
        let todayTokens: Int
        let dailyPoints: [DailyPoint]

        /// Composite key (providerID|accountEmail) so multi-account rows
        /// with the same providerID don't collapse in SwiftUI ForEach.
        /// Hit on user QA 2026-05-04 — see RawSyncDataView fix in same commit.
        var id: String {
            self.provider.cardIdentityKey
        }
    }

    let providerRows: [ProviderRow]
    let dailyPoints: [DailyPoint]
    let modelRows: [CostBreakdownRow]
    let serviceRows: [CostBreakdownRow]
    let budgetRows: [CostBudgetRow]
    /// When CWL is ON, the user-selected window (7/30/90/365) the ledger was
    /// re-aggregated to. nil on the blob path. Drives `historyDays` so the
    /// Overview "N Days" headline reflects the chosen CWL window instead of the
    /// max Mac `historyDays` across providers (e.g. a 90-day mock provider).
    let cwlWindowDays: Int?

    var total30DayCost: Double {
        self.providerRows.reduce(0) { $0 + $1.thirtyDayCost }
    }

    var totalTodayCost: Double {
        self.providerRows.reduce(0) { $0 + $1.todayCost }
    }

    var total30DayTokens: Int {
        self.providerRows.reduce(0) { $0 + $1.thirtyDayTokens }
    }

    var spendProviderRows: [ProviderRow] {
        self.providerRows.filter { $0.thirtyDayCost > 0 }
    }

    /// Cost-history window in days shown in the Overview headline. When CWL is
    /// ON this is the user's selected window (the dashboard re-windows the
    /// ledger to it); when OFF it's the Mac's max configured `historyDays`
    /// (gap F) across providers. nil → caller defaults to 30.
    var historyDays: Int? {
        if let cwlWindowDays = self.cwlWindowDays { return cwlWindowDays }
        return self.providerRows.compactMap { $0.provider.costSummary?.historyDays }.max()
    }

    var topProvider: ProviderRow? {
        self.providerRows.max { $0.thirtyDayCost < $1.thirtyDayCost }
    }

    var highestDay: DailyPoint? {
        self.dailyPoints.max { $0.costUSD < $1.costUSD }
    }

    var activeDayCount: Int {
        self.dailyPoints.count(where: { $0.costUSD > 0 })
    }

    var hasDisplayData: Bool {
        !self.providerRows.isEmpty || !self.dailyPoints.isEmpty || !self.budgetRows.isEmpty
    }

    init(snapshot: SyncedUsageSnapshot) {
        var providerRows: [ProviderRow] = []
        var dailyTotals: [String: DailyAccumulator] = [:]
        var modelTotals: [String: Double] = [:]
        // Codex standard/fast split summed per model across the window, so the
        // Model Mix rows can show a "Std / Fast" sub-line (upstream #1070).
        var modelSplits: [String: (std: Double, fast: Double)] = [:]
        var serviceTotals: [String: Double] = [:]
        var budgetRows: [CostBudgetRow] = []

        // Drop extinct mock zombies before aggregation so the Cost
        // dashboard's totals don't include them. iOS 1.5.2+: see
        // `MockProviderDetector.extinctMockProviderIDs`.
        let liveProviders = MockProviderDetector.filteredProviders(from: snapshot)
        for provider in liveProviders {
            if let budget = provider.budget, budget.limitAmount > 0 {
                budgetRows.append(CostBudgetRow(provider: provider, budget: budget))
            }

            guard let costSummary = provider.costSummary else { continue }

            let thirtyDayCost = costSummary.last30DaysCostUSD
                ?? costSummary.daily.reduce(0) { $0 + $1.costUSD }
            let thirtyDayTokens = costSummary.last30DaysTokens
                ?? costSummary.daily.reduce(0) { $0 + $1.totalTokens }

            let todayTotals = costSummary.todayTotals()
            let todayCost = todayTotals.costUSD ?? 0
            let todayTokens = todayTotals.tokens ?? 0
            let providerDailyPoints = costSummary.daily.compactMap(Self.dailyPoint)

            guard thirtyDayCost > 0 || todayCost > 0 || thirtyDayTokens > 0 || todayTokens > 0 else {
                continue
            }

            providerRows.append(
                ProviderRow(
                    provider: provider,
                    thirtyDayCost: thirtyDayCost,
                    todayCost: todayCost,
                    thirtyDayTokens: thirtyDayTokens,
                    todayTokens: todayTokens,
                    dailyPoints: providerDailyPoints))

            for point in costSummary.daily {
                dailyTotals[point.dayKey, default: .init()].ingest(point)

                for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                    modelTotals[breakdown.label, default: 0] += breakdown.costUSD
                    if breakdown.standardCostUSD != nil || breakdown.priorityCostUSD != nil {
                        modelSplits[breakdown.label, default: (0, 0)].std += breakdown.standardCostUSD ?? 0
                        modelSplits[breakdown.label, default: (0, 0)].fast += breakdown.priorityCostUSD ?? 0
                    }
                }

                for breakdown in point.serviceBreakdowns where breakdown.costUSD > 0 {
                    serviceTotals[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
        }

        self.providerRows = providerRows.sorted { lhs, rhs in
            if lhs.thirtyDayCost == rhs.thirtyDayCost {
                return lhs.provider.providerName
                    .localizedCaseInsensitiveCompare(rhs.provider.providerName) == .orderedAscending
            }
            return lhs.thirtyDayCost > rhs.thirtyDayCost
        }

        self.dailyPoints = dailyTotals.keys.compactMap { dayKey in
            guard let date = Self.dayKeyFormatter.date(from: dayKey),
                  let totals = dailyTotals[dayKey] else { return nil }
            return totals.dailyPoint(dayKey: dayKey, date: date)
        }
        .sorted { $0.date < $1.date }

        self.modelRows = Self.breakdownRows(from: modelTotals, palette: .model, splits: modelSplits)
        self.serviceRows = Self.breakdownRows(from: serviceTotals, palette: .service)
        self.budgetRows = budgetRows.sorted { lhs, rhs in
            let lhsRatio = lhs.budget.limitAmount > 0 ? lhs.budget.usedAmount / lhs.budget.limitAmount : 0
            let rhsRatio = rhs.budget.limitAmount > 0 ? rhs.budget.usedAmount / rhs.budget.limitAmount : 0
            return lhsRatio > rhsRatio
        }
        self.cwlWindowDays = nil
    }

    /// Memberwise init used by `fromLedger` (CWL path) and any future
    /// alternate data source. Callers pass already-sorted arrays — the
    /// blob-backed `init(snapshot:)` above does its own inline sorting.
    init(
        providerRows: [ProviderRow],
        dailyPoints: [DailyPoint],
        modelRows: [CostBreakdownRow],
        serviceRows: [CostBreakdownRow],
        budgetRows: [CostBudgetRow],
        cwlWindowDays: Int? = nil)
    {
        self.providerRows = providerRows
        self.dailyPoints = dailyPoints
        self.modelRows = modelRows
        self.serviceRows = serviceRows
        self.budgetRows = budgetRows
        self.cwlWindowDays = cwlWindowDays
    }

    /// Build insights from the Cost Window Ledger aggregation (CWL ON path,
    /// research doc 024 Round 5 / P4a). Cost fields (provider totals, daily
    /// series, model / service mix) come from the ledger — re-aggregated over
    /// the user's chosen window, which can exceed Mac's historyDays. Provider
    /// metadata (name, color, budget, loginMethod) still comes from the live
    /// snapshot since the ledger stores only IDs + numbers. Fresh snapshot
    /// providers absent from the ledger can fill a missing row, and their
    /// daily/model/service points are folded into the same aggregate so every
    /// Cost surface reads one consistent result. Ledger rollups with no
    /// matching live provider are dropped (stale / removed provider — no
    /// metadata to render).
    static func fromLedger(
        aggregation: CostLedgerAggregation,
        snapshot: SyncedUsageSnapshot,
        snapshotFallbackCutoff: Date? = nil) -> CostDashboardInsights
    {
        let todayKey = Self.dayKeyFormatter.string(from: Date())
        let liveProviders = MockProviderDetector.filteredProviders(from: snapshot)

        var providerRows: [ProviderRow] = []
        var representedProviderKeys = Set<String>()
        var dailyTotals: [String: DailyAccumulator] = [:]
        for point in aggregation.dailyPoints {
            dailyTotals[point.dayKey, default: .init()].ingest(point)
        }
        var modelTotals = Dictionary(
            uniqueKeysWithValues: aggregation.modelMix.map { ($0.label, $0.costUSD) })
        var modelSplits = Dictionary(
            uniqueKeysWithValues: aggregation.modelMix.compactMap {
                bd -> (String, (std: Double, fast: Double))? in
                guard bd.standardCostUSD != nil || bd.priorityCostUSD != nil else { return nil }
                return (bd.label, (bd.standardCostUSD ?? 0, bd.priorityCostUSD ?? 0))
            })
        var serviceTotals = Dictionary(
            uniqueKeysWithValues: aggregation.serviceMix.map { ($0.label, $0.costUSD) })

        for rollup in aggregation.providerRollups.values {
            guard let provider = liveProviders.first(where: {
                guard $0.providerID == rollup.providerID else { return false }
                if rollup.accountIdentityKey != nil {
                    let liveKeys = Set(CostLedgerService.accountIdentityKeys(for: $0))
                    return !liveKeys.isDisjoint(with: rollup.accountIdentityKeys)
                }
                // Pre-1.19 ledger rows have no opaque identity metadata.
                return $0.accountEmail == rollup.accountEmail
            }) else { continue }
            let totals = Self.ledgerDisplayTotals(
                rollup: rollup,
                provider: provider,
                windowDays: aggregation.windowDays)
            let providerDailyPoints = rollup.dailyPoints.compactMap(Self.dailyPoint)
            let todayPoint = providerDailyPoints.first(where: { $0.dayKey == todayKey })
            let fallbackToday = provider.costSummary?.todayTotals()
            let todayCost = todayPoint?.costUSD ?? fallbackToday?.costUSD ?? 0
            let todayTokens = todayPoint?.totalTokens ?? fallbackToday?.tokens ?? 0
            providerRows.append(ProviderRow(
                provider: provider,
                thirtyDayCost: totals.costUSD,
                todayCost: todayCost,
                thirtyDayTokens: totals.tokens,
                todayTokens: todayTokens,
                dailyPoints: providerDailyPoints))
            representedProviderKeys.insert(provider.cardIdentityKey)
        }

        let fallbackCutoffKey = CostLedgerService.cutoffDayKey(
            windowDays: aggregation.windowDays,
            asOf: Date())
        for provider in liveProviders where !representedProviderKeys.contains(provider.cardIdentityKey) {
            if let snapshotFallbackCutoff, provider.lastUpdated <= snapshotFallbackCutoff {
                continue
            }
            guard let costSummary = provider.costSummary else { continue }
            let emptyRollup = CostLedgerProviderRollup(
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountIdentityKey: CostLedgerService.accountIdentityKey(for: provider),
                totalCostUSD: 0,
                totalTokens: 0,
                dailyPoints: [],
                modelBreakdowns: [],
                serviceBreakdowns: [])
            let totals = Self.ledgerDisplayTotals(
                rollup: emptyRollup,
                provider: provider,
                windowDays: aggregation.windowDays)
            let todayTotals = costSummary.todayTotals()
            let todayCost = todayTotals.costUSD ?? 0
            let todayTokens = todayTotals.tokens ?? 0
            let fallbackSyncPoints = costSummary.daily.filter { $0.dayKey >= fallbackCutoffKey }
            let providerDailyPoints = fallbackSyncPoints.compactMap(Self.dailyPoint)
            let fallbackDailyCost = fallbackSyncPoints.reduce(0) { $0 + $1.costUSD }
            let fallbackDailyTokens = fallbackSyncPoints.reduce(0) { $0 + $1.totalTokens }
            let resolvedCost = max(totals.costUSD, max(fallbackDailyCost, todayCost))
            let resolvedTokens = max(totals.tokens, max(fallbackDailyTokens, todayTokens))
            guard resolvedCost > 0 || resolvedTokens > 0 else {
                continue
            }
            providerRows.append(ProviderRow(
                provider: provider,
                thirtyDayCost: resolvedCost,
                todayCost: todayCost,
                thirtyDayTokens: resolvedTokens,
                todayTokens: todayTokens,
                dailyPoints: providerDailyPoints))

            for point in fallbackSyncPoints {
                dailyTotals[point.dayKey, default: .init()].ingest(point)

                for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                    modelTotals[breakdown.label, default: 0] += breakdown.costUSD
                    if breakdown.standardCostUSD != nil || breakdown.priorityCostUSD != nil {
                        modelSplits[breakdown.label, default: (0, 0)].std += breakdown.standardCostUSD ?? 0
                        modelSplits[breakdown.label, default: (0, 0)].fast += breakdown.priorityCostUSD ?? 0
                    }
                }

                for breakdown in point.serviceBreakdowns where breakdown.costUSD > 0 {
                    serviceTotals[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
        }

        var budgetRows: [CostBudgetRow] = []
        for provider in liveProviders {
            if let budget = provider.budget, budget.limitAmount > 0 {
                budgetRows.append(CostBudgetRow(provider: provider, budget: budget))
            }
        }

        let dailyPoints: [DailyPoint] = dailyTotals.keys.compactMap { dayKey in
            guard let date = Self.dayKeyFormatter.date(from: dayKey),
                  let totals = dailyTotals[dayKey] else { return nil }
            return totals.dailyPoint(dayKey: dayKey, date: date)
        }

        return CostDashboardInsights(
            providerRows: providerRows.sorted { lhs, rhs in
                if lhs.thirtyDayCost == rhs.thirtyDayCost {
                    return lhs.provider.providerName
                        .localizedCaseInsensitiveCompare(rhs.provider.providerName) == .orderedAscending
                }
                return lhs.thirtyDayCost > rhs.thirtyDayCost
            },
            dailyPoints: dailyPoints.sorted { $0.date < $1.date },
            modelRows: Self.breakdownRows(from: modelTotals, palette: .model, splits: modelSplits),
            serviceRows: Self.breakdownRows(from: serviceTotals, palette: .service),
            budgetRows: budgetRows.sorted { lhs, rhs in
                let lhsRatio = lhs.budget.limitAmount > 0 ? lhs.budget.usedAmount / lhs.budget.limitAmount : 0
                let rhsRatio = rhs.budget.limitAmount > 0 ? rhs.budget.usedAmount / rhs.budget.limitAmount : 0
                return lhsRatio > rhsRatio
            },
            cwlWindowDays: aggregation.windowDays)
    }

    private static func ledgerDisplayTotals(
        rollup: CostLedgerProviderRollup,
        provider: ProviderUsageSnapshot,
        windowDays: Int) -> (costUSD: Double, tokens: Int)
    {
        guard let summary = provider.costSummary else {
            return (rollup.totalCostUSD, rollup.totalTokens)
        }

        var costUSD = rollup.totalCostUSD
        var tokens = rollup.totalTokens
        let summaryWindowDays = max(1, min(summary.historyDays ?? 30, 365))

        if summaryWindowDays == windowDays {
            costUSD = summary.last30DaysCostUSD ?? costUSD
            tokens = summary.last30DaysTokens ?? tokens
        } else if summaryWindowDays < windowDays {
            if let summaryCost = summary.last30DaysCostUSD {
                costUSD = max(costUSD, summaryCost)
            }
            if let summaryTokens = summary.last30DaysTokens {
                tokens = max(tokens, summaryTokens)
            }
        }

        return (costUSD, tokens)
    }

    private static func breakdownRows(
        from totals: [String: Double],
        palette: BreakdownPalette,
        splits: [String: (std: Double, fast: Double)] = [:]) -> [CostBreakdownRow]
    {
        totals
            .filter { $0.value > 0 }
            .map { label, amount in
                CostBreakdownRow(
                    label: label,
                    amountUSD: amount,
                    subtitle: splits[label].flatMap {
                        CodexCostSplit.subtitle(standardCostUSD: $0.std, priorityCostUSD: $0.fast)
                    },
                    color: palette.color(for: label))
            }
            .sorted { lhs, rhs in
                if lhs.amountUSD == rhs.amountUSD {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.amountUSD > rhs.amountUSD
            }
    }

    private static func dailyPoint(from point: SyncDailyPoint) -> DailyPoint? {
        guard let date = dayKeyFormatter.date(from: point.dayKey) else { return nil }
        return DailyPoint(
            dayKey: point.dayKey,
            date: date,
            costUSD: point.costUSD,
            totalTokens: point.totalTokens,
            modelBreakdowns: point.modelBreakdowns,
            serviceBreakdowns: point.serviceBreakdowns)
    }

    private struct DailyAccumulator {
        var costUSD: Double = 0
        var totalTokens: Int = 0
        var modelBreakdowns: [String: BreakdownAccumulator] = [:]
        var serviceBreakdowns: [String: BreakdownAccumulator] = [:]

        mutating func ingest(_ point: SyncDailyPoint) {
            self.costUSD += point.costUSD
            self.totalTokens += point.totalTokens
            for breakdown in point.modelBreakdowns {
                self.modelBreakdowns[breakdown.label, default: .init()].ingest(breakdown)
            }
            for breakdown in point.serviceBreakdowns {
                self.serviceBreakdowns[breakdown.label, default: .init()].ingest(breakdown)
            }
        }

        func dailyPoint(dayKey: String, date: Date) -> DailyPoint {
            DailyPoint(
                dayKey: dayKey,
                date: date,
                costUSD: self.costUSD,
                totalTokens: self.totalTokens,
                modelBreakdowns: Self.sortedBreakdowns(self.modelBreakdowns),
                serviceBreakdowns: Self.sortedBreakdowns(self.serviceBreakdowns))
        }

        private static func sortedBreakdowns(
            _ totals: [String: BreakdownAccumulator]) -> [SyncCostBreakdown]
        {
            totals
                .map { label, accumulator in accumulator.breakdown(label: label) }
                .sorted { lhs, rhs in
                    if lhs.costUSD == rhs.costUSD {
                        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    }
                    return lhs.costUSD > rhs.costUSD
                }
        }
    }

    private struct BreakdownAccumulator {
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
            self.isEstimated = self.isEstimated || breakdown.isEstimated == true
            if let standardCostUSD = breakdown.standardCostUSD {
                self.standardCostUSD += standardCostUSD
                self.hasStandardCost = true
            }
            if let priorityCostUSD = breakdown.priorityCostUSD {
                self.priorityCostUSD += priorityCostUSD
                self.hasPriorityCost = true
            }
            if let standardTokens = breakdown.standardTokens {
                self.standardTokens += standardTokens
                self.hasStandardTokens = true
            }
            if let priorityTokens = breakdown.priorityTokens {
                self.priorityTokens += priorityTokens
                self.hasPriorityTokens = true
            }
        }

        func breakdown(label: String) -> SyncCostBreakdown {
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

    /// Wire-format `dayKey` formatter used to match records to today's
    /// calendar day when reading `SyncCostSummary.daily`. The format
    /// `yyyy-MM-dd` + `en_US_POSIX` + `gregorian` is pinned here to match
    /// Mac-side `SyncCoordinator.daily[].dayKey` generation; changing any
    /// of the three values would make the keys stop round-tripping across
    /// the sync boundary. Do NOT "localize" this — `dayKey` is a machine
    /// contract, not user-facing text. See `SyncCostSummary+Today.swift`
    /// for the symmetric helper used outside this view.
    ///
    /// Only called from view-body (main-actor) synchronous paths —
    /// DateFormatter's documented thread-unsafety does not apply here.
    /// If a future refactor moves the call into a background Task, switch
    /// to `SyncCostSummary.iso8601DayKey(for:)` (per-call factory).
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Renders one row of the Cost dashboard's contribution lists (Provider Share /
/// Model Mix / Codex Service Mix). Extracted in iOS 1.9.0 so the same row
/// design is shared between the capped section preview (top 5) and the
/// drill-down full-list view that opens when the user taps "Others".
private struct CostBreakdownRowView: View {
    let row: CostBreakdownRow
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(self.row.color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.row.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CostBreakdownMetricColumn(
                    amountText: CostFormatting.usd(self.row.amountUSD),
                    shareText: Self.shareText(self.row.amountUSD, total: self.total))
            }

            ProgressView(value: Self.ratio(self.row.amountUSD, total: self.total))
                .tint(self.row.color)
                .scaleEffect(y: 1.8, anchor: .center)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    fileprivate static func ratio(_ value: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    fileprivate static func shareText(_ value: Double, total: Double) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", value / total * 100)
    }
}

/// Bottom row of a capped contribution list, summarising everything beyond
/// the top 5. Wrapped in a NavigationLink by the caller → drills into the
/// full list. Visually mirrors `CostBreakdownRowView` with a muted grey dot
/// and a trailing chevron to suggest tappability.
private struct OthersBreakdownRowView: View {
    let count: Int
    let amountUSD: Double
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Others")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("+\(self.count) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CostBreakdownMetricColumn(
                    amountText: CostFormatting.usd(self.amountUSD),
                    shareText: CostBreakdownRowView.shareText(self.amountUSD, total: self.total))

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            ProgressView(value: CostBreakdownRowView.ratio(self.amountUSD, total: self.total))
                .tint(Color.secondary.opacity(0.5))
                .scaleEffect(y: 1.8, anchor: .center)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Drill-down view shown when the user taps an Others row on the Cost
/// dashboard. Lists every entry in the section (same `CostBreakdownRowView`
/// style) inside the Cost tab's existing NavigationStack.
private struct FullBreakdownListView: View {
    let title: LocalizedStringResource
    let rows: [CostBreakdownRow]
    let total: Double

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(self.rows) { row in
                    CostBreakdownRowView(row: row, total: self.total)
                }
            }
            .padding()
        }
        .navigationTitle(Text(self.title))
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .background(Color(.systemGroupedBackground))
    }
}

/// Renders one row of the Budgets section. Extracted in iOS 1.9.0 so the
/// same row design is used by the capped preview (top 5) and the drill-down
/// full list (see `FullBudgetListView`).
private struct BudgetRowView: View {
    let row: CostBudgetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(self.row.provider.providerName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let method = row.provider.loginMethod {
                    Text(method)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            BudgetProgressView(
                budget: self.row.budget,
                tintColor: providerTint(for: self.row.provider))
        }
    }
}

/// Bottom Others row of the capped Budgets section. No aggregate metric —
/// summing budgets across different limits / currencies / cycles isn't
/// meaningful — just the count and a chevron. Tappable via the parent
/// NavigationLink → FullBudgetListView.
private struct OthersBudgetRowView: View {
    let count: Int

    var body: some View {
        HStack {
            Text("Others")
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text("+\(self.count) more")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

/// Drill-down view for the Budgets section. Shows every budget in the same
/// row design as the capped preview.
private struct FullBudgetListView: View {
    let rows: [CostBudgetRow]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(self.rows) { row in
                    BudgetRowView(row: row)
                }
            }
            .padding()
        }
        .navigationTitle(Text("Budgets"))
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .background(Color(.systemGroupedBackground))
    }
}

struct CostBreakdownRow: Identifiable {
    let label: String
    let amountUSD: Double
    let subtitle: String?
    let color: Color
    /// Optional override for SwiftUI identity. Defaults to `label` for the
    /// existing Model Mix / Codex Service Mix sites where labels are
    /// guaranteed unique (one row per model name, one per service name).
    /// The Provider Share path on the Cost dashboard supplies a composite
    /// key because two Macs running the same provider with different
    /// `accountEmail` values produce two rows with the same `providerName`
    /// label — ForEach would otherwise collide on the duplicate id, render
    /// both rows with the first row's data, and the second account's $$
    /// vanishes from the UI (1.5.3 fix; see Research/021 §1).
    let identityOverride: String?

    init(
        label: String,
        amountUSD: Double,
        subtitle: String?,
        color: Color,
        identityOverride: String? = nil)
    {
        self.label = label
        self.amountUSD = amountUSD
        self.subtitle = subtitle
        self.color = color
        self.identityOverride = identityOverride
    }

    var id: String {
        self.identityOverride ?? self.label
    }
}

struct CostBudgetRow: Identifiable {
    let provider: ProviderUsageSnapshot
    let budget: SyncBudgetSnapshot

    /// Use the multi-account-aware composite key, not just `providerID`.
    /// Two budgets coming from two Macs on the same provider but different
    /// accounts would otherwise collide and the second budget would render
    /// with the first's data (1.5.3 fix; see Research/021 §1).
    var id: String {
        self.provider.cardIdentityKey
    }
}

/// Deterministic color palette for model / service breakdown chips on the Cost tab.
///
/// The HSB constants below are tuned for two competing requirements:
/// - Labels (e.g. model names like "claude-3-5-sonnet") must get a stable,
///   reproducible color — so we seed from `label` hash and look up HSB from a
///   small constant range rather than choosing randomly.
/// - Adjacent chips in a breakdown list must stay visually distinct — the
///   saturation and brightness ranges are narrow on purpose; widening them
///   introduces grey-ish or washed-out colors that blend into the card
///   material background.
///
/// - `hueBase = 0.08` (model) — warm orange/red family, reserved for model
///   chips (e.g. "claude-3-5-sonnet-20250219").
/// - `hueBase = 0.52` (service) — cool cyan/blue family, reserved for
///   service/deployment chips. The ~0.44 hue gap keeps the two families
///   easily distinguishable even when a user's list mixes both.
/// - Hue variation of `±0.21` (seed % 21 / 100) spreads labels across a
///   slice of the hue wheel without crossing into the other family.
/// - Saturation: 0.62–0.83 — below 0.62 reads as grey on the Cost tab's
///   `.ultraThinMaterial`; above ~0.85 looks harsh on iPad's wider gamut.
/// - Brightness: 0.78–0.93 — ensures WCAG-adjacent contrast on the dark-
///   mode material background; below 0.78 reads as muddy, above 0.93 blows
///   out text legibility overlaid on the chip.
///
/// Do NOT replace with `.random()` or a generic palette API — these
/// specific ranges are load-bearing for the Cost tab's visual clarity.
private enum BreakdownPalette {
    case model
    case service

    func color(for label: String) -> Color {
        let seed = label.lowercased().unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        let hueBase = switch self {
        case .model: 0.08
        case .service: 0.52
        }
        let hue = (hueBase + (Double(seed % 21) / 100)).truncatingRemainder(dividingBy: 1)
        let saturation = 0.62 + Double(seed % 7) * 0.03
        let brightness = 0.78 + Double(seed % 5) * 0.03
        return Color(hue: hue, saturation: min(saturation, 0.95), brightness: min(brightness, 0.98))
    }
}

private func providerTint(for provider: ProviderUsageSnapshot?) -> Color {
    ProviderColorPalette.color(for: provider?.providerID ?? "")
}

// MARK: - Setting Tab

private struct SettingsTab: View {
    let usageData: SyncedUsageData
    @State private var showingSetupGuide = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        self.showingSetupGuide = true
                    } label: {
                        SettingSummaryRow(
                            title: "Setup Guide",
                            symbolName: "sparkles",
                            summary: String(localized: "Walk through how CodexBar syncs from Mac to iPhone"))
                    }
                    .tint(.primary)

                    NavigationLink {
                        AboutSyncDetailView(usageData: self.usageData)
                    } label: {
                        SettingSummaryRow(
                            title: "About & Sync",
                            symbolName: "iphone.and.arrow.forward",
                            summary: "\(String(localized: "iPhone")) \(self.mobileVersionSummary) · \(String(localized: "Mac")) \(self.macVersionSummary)")
                    }

                    NavigationLink {
                        ReleaseNotesView()
                    } label: {
                        SettingSummaryRow(
                            title: "Release Notes",
                            symbolName: "text.document",
                            summary: String(localized: "Latest updates and version history"))
                    }
                }

                Section {
                    NavigationLink {
                        UsageSettingsView()
                    } label: {
                        SettingSummaryRow(
                            title: "Usage Setting",
                            symbolName: "chart.bar.fill",
                            summary: String(localized: "Configure the Usage page"))
                    }

                    NavigationLink {
                        CostSettingsView()
                    } label: {
                        SettingSummaryRow(
                            title: "Cost Setting",
                            symbolName: "dollarsign.circle.fill",
                            summary: String(localized: "Configure the Cost page"))
                    }

                    NavigationLink {
                        WidgetSettingsView(usageData: self.usageData)
                    } label: {
                        SettingSummaryRow(
                            title: "Widget Setting",
                            symbolName: "square.grid.2x2",
                            summary: String(localized: "Preview Home Screen widgets"))
                    }
                }

                Section("Developer") {
                    Link(destination: URL(string: "https://x.com/o1xhack")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Yuxiao")
                                    .fontWeight(.medium)
                                Text("@o1xhack on X")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.fill")
                        }
                    }
                }

                Section("Developer") {
                    NavigationLink {
                        DeveloperToolsView(usageData: self.usageData)
                    } label: {
                        SettingSummaryRow(
                            title: "Developer Tools",
                            symbolName: "wrench.and.screwdriver",
                            summary: String(localized: "Sync inspector, push diagnostic, and more"))
                    }
                }

                if MockProviderDetector.hasAnyMock(in: self.usageData.snapshot) {
                    Section("Diagnostics") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "testtube.2")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mock Data Active")
                                    .fontWeight(.medium)
                                Text(
                                    "\(MockProviderDetector.mockCount(in: self.usageData.snapshot)) synthetic providers from Mac. Toggle off in Mac CodexBar → Settings → Mobile → Debug · Mock Provider Data; iPhone updates within ~30s.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Open Source") {
                    Link(destination: URL(string: "https://github.com/o1xhack/CodexBar-Mobile")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("o1xhack/CodexBar-Mobile")
                                    .fontWeight(.medium)
                                Text("Install the Mac app from this repo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                        }
                    }

                    Link(destination: URL(string: "https://github.com/steipete/CodexBar")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("steipete/CodexBar")
                                    .fontWeight(.medium)
                                Text("Original Mac app — MIT License")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.triangle.branch")
                        }
                    }
                }
            }
            .contentMargins(.top, 12, for: .scrollContent)
            .navigationTitle("Setting")
            .sheet(isPresented: self.$showingSetupGuide) {
                NavigationStack {
                    OnboardingView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    self.showingSetupGuide = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                }
            }
        }
    }

    private var mobileVersionSummary: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var macVersionSummary: String {
        guard let snapshot = self.usageData.snapshot else { return String(localized: "Not synced") }
        return snapshot.appVersion ?? String(localized: "Unknown")
    }
}

private struct SettingSummaryRow: View {
    let title: LocalizedStringResource
    let symbolName: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(self.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AboutSyncDetailView: View {
    let usageData: SyncedUsageData
    @State private var deviceActionSheet: DeviceActionSheet?

    private var appDisplayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("Versions") {
                LabeledContent("iPhone App", value: self.appDisplayVersion)
                if let snapshot = self.usageData.snapshot {
                    LabeledContent("Mac App", value: snapshot.appVersion ?? String(localized: "Unknown"))
                    // When multiple Macs sync and at least one runs an older
                    // CodexBar version than the highest, surface a subtle hint
                    // under the Mac App row. Prompts the user to update the
                    // older Mac so both sides can emit new-schema sync data
                    // (perplexityCredits, loginMethod, budget, etc. — all the
                    // `latestNonNil` fields that silently degrade when an
                    // old Mac refreshes last). Per-device detail appears in
                    // the Devices section below.
                    if self.hasOutdatedMac {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Some Mac devices are on older versions. Update them for complete sync data.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let mobileVersion = snapshot.mobileVersion {
                        LabeledContent("Synced Mobile Version", value: mobileVersion)
                    }
                } else {
                    LabeledContent("Mac App", value: String(localized: "Not synced"))
                }
            }

            // MARK: Mac Update Prompt

            if self.usageData.usingKVSFallback {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mac Update Available")
                                .font(.subheadline.weight(.semibold))
                            Text(
                                "Your Mac is using legacy sync. Update CodexBar on Mac to unlock CloudKit multi-device sync.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://github.com/o1xhack/CodexBar-Mobile/releases")!) {
                        Label("Download Latest Mac Version", systemImage: "arrow.down.circle")
                    }
                }
            }

            // MARK: Sync Status

            Section {
                HStack {
                    self.syncStatusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.syncStatusTitle)
                            .font(.body)
                        if let detail = self.syncStatusDetail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await self.usageData.refresh() }
                    } label: {
                        if case .syncing = self.usageData.syncStatus {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(self.usageData.syncStatus == .syncing)
                }
            } header: {
                Text("Sync Status")
            } footer: {
                if let error = self.usageData.lastSyncError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            // MARK: Devices

            if self.usageData.deviceManagementItems.isEmpty {
                Section {
                    Text("No devices synced yet")
                        .foregroundStyle(.secondary)
                } header: {
                    HStack {
                        Text("Devices")
                        Spacer()
                        Text("0")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                if !self.activeDeviceItems.isEmpty {
                    Section {
                        ForEach(self.activeDeviceItems) { item in
                            self.deviceRow(item)
                        }
                    } header: {
                        HStack {
                            Text("Devices")
                            Spacer()
                            Text("\(self.activeDeviceItems.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !self.archivedDeviceItems.isEmpty {
                    Section {
                        ForEach(self.archivedDeviceItems) { item in
                            self.deviceRow(item)
                        }
                    } header: {
                        HStack {
                            Text("Archived Devices")
                            Spacer()
                            Text("\(self.archivedDeviceItems.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // iOS 1.7.0 — gated by `showProviderChangelogLinks`. Mirrors
            // upstream PR #929; opt-in companion to the Mac menu's
            // changelog links so users on iPhone can jump to the
            // upstream release notes for the providers we sync.
            if self.showProviderChangelogLinks {
                Section {
                    Link(destination: URL(string: "https://github.com/openai/codex/releases")!) {
                        Label("Codex CLI", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/anthropics/claude-code/releases")!) {
                        Label("Claude Code", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/google-gemini/gemini-cli/releases")!) {
                        Label("Gemini CLI", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("provider_changelogs_section")
                } footer: {
                    Text("provider_changelogs_footer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("About & Sync")
        .sheet(item: self.$deviceActionSheet) { sheet in
            switch sheet {
            case let .merge(source):
                DeviceMergeSheet(
                    source: source,
                    targets: self.mergeTargets(for: source),
                    usageData: self.usageData)
            case let .archive(item):
                DeviceLifecycleConfirmationSheet(
                    kind: .archive,
                    item: item,
                    usageData: self.usageData)
            case let .restore(item):
                DeviceLifecycleConfirmationSheet(
                    kind: .restore,
                    item: item,
                    usageData: self.usageData)
            case let .unmerge(item):
                DeviceLifecycleConfirmationSheet(
                    kind: .unmerge,
                    item: item,
                    usageData: self.usageData)
            }
        }
    }

    @AppStorage(MobileSettingsKeys.showProviderChangelogLinks) private var showProviderChangelogLinks = false

    private var activeDeviceItems: [SyncDeviceManagementItem] {
        self.usageData.deviceManagementItems.filter { !$0.isArchived }
    }

    private var archivedDeviceItems: [SyncDeviceManagementItem] {
        self.usageData.deviceManagementItems.filter(\.isArchived)
    }

    private func deviceRow(_ item: SyncDeviceManagementItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isArchived ? "archivebox" : "laptopcomputer")
                .foregroundStyle(item.isArchived ? Color.secondary : Color.accentColor)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.snapshot.deviceName)
                        .font(.body)
                    if item.isMergedAlias {
                        Text("Merged")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    if item.isArchived {
                        Text("Archived")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.snapshot.syncTimestamp.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(item.snapshot.providers.count) providers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.aliasCount > 0 {
                    Text("\(item.sourceDeviceIDs.count.formatted()) \(String(localized: "device identities combined"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if item.isArchived {
                    Text("Kept for history; excluded from active sync warnings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let version = item.snapshot.appVersion {
                    HStack(spacing: 6) {
                        Text("CodexBar \(version)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if self.isDeviceOutdated(item.snapshot), !item.isArchived {
                            Text("· Update available")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            Spacer()
            Menu {
                if item.isArchived {
                    Button("Restore Device") {
                        self.deviceActionSheet = .restore(item)
                    }
                } else {
                    Button("Merge with Another Mac...") {
                        self.deviceActionSheet = .merge(item)
                    }
                    .disabled(self.mergeTargets(for: item).isEmpty)
                    Button("Archive This Device", role: .destructive) {
                        self.deviceActionSheet = .archive(item)
                    }
                    if item.isMergedAlias {
                        Button("Unmerge", role: .destructive) {
                            self.deviceActionSheet = .unmerge(item)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel(Text("Device actions"))
        }
        .padding(.vertical, 2)
    }

    private func mergeTargets(for source: SyncDeviceManagementItem) -> [SyncDeviceManagementItem] {
        self.activeDeviceItems.filter {
            $0.canonicalDeviceID != source.canonicalDeviceID
        }
    }

    private var syncStatusIcon: some View {
        Group {
            switch self.usageData.syncStatus {
            case .synced:
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    .foregroundStyle(.blue)
            case .error:
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundStyle(.red)
            case .noData:
                Image(systemName: "icloud.slash.fill")
                    .foregroundStyle(.orange)
            case .incompatibleData:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.title2)
    }

    private var syncStatusTitle: String {
        switch self.usageData.syncStatus {
        case .synced: String(localized: "Synced")
        case .syncing: String(localized: "Syncing…")
        case .error: String(localized: "Sync Error")
        case .noData: String(localized: "No Data")
        case .incompatibleData: String(localized: "Incompatible Data")
        }
    }

    /// True when 2+ Macs are synced AND at least one runs an older
    /// `appVersion` than the highest-semver one. Drives the orange-tinted
    /// hint under the top-level "Mac App" row. Single-device setups never
    /// trip this (there's nothing to compare against).
    private var hasOutdatedMac: Bool {
        guard self.usageData.deviceSnapshots.count >= 2,
              let latestVersion = self.usageData.snapshot?.appVersion
        else { return false }
        return self.usageData.deviceSnapshots.contains { device in
            guard let deviceVersion = device.appVersion else { return false }
            return CloudSyncReader.semverLessThan(deviceVersion, latestVersion)
        }
    }

    /// True when this specific device's `appVersion` is strictly less than
    /// the highest-semver one across all synced devices. Drives the per-row
    /// "Update available" chip. Uses the same semver comparator as
    /// `CloudSyncReader.mergeSnapshots`'s `max(by:)` selection so the two
    /// views stay in lockstep — no device is both "chosen as the Mac App
    /// version shown at top" AND "flagged as outdated" simultaneously.
    private func isDeviceOutdated(_ device: SyncedUsageSnapshot) -> Bool {
        guard let deviceVersion = device.appVersion,
              let latestVersion = self.usageData.snapshot?.appVersion
        else { return false }
        return CloudSyncReader.semverLessThan(deviceVersion, latestVersion)
    }

    private var syncStatusDetail: String? {
        switch self.usageData.syncStatus {
        case let .synced(ago):
            if ago < 60 { return String(localized: "Last synced just now") }
            if let snapshot = self.usageData.snapshot {
                return String(
                    localized: "Last synced \(snapshot.syncTimestamp.formatted(.relative(presentation: .named)))")
            }
            return nil
        case .syncing: return nil
        case .noData: return String(localized: "Waiting for Mac to push data")
        case .incompatibleData: return String(localized: "Please update CodexBar on Mac")
        case .error: return nil
        }
    }
}

private enum DeviceActionSheet: Identifiable {
    case merge(SyncDeviceManagementItem)
    case archive(SyncDeviceManagementItem)
    case restore(SyncDeviceManagementItem)
    case unmerge(SyncDeviceManagementItem)

    var id: String {
        switch self {
        case let .merge(item):
            "merge-\(item.id)"
        case let .archive(item):
            "archive-\(item.id)"
        case let .restore(item):
            "restore-\(item.id)"
        case let .unmerge(item):
            "unmerge-\(item.id)"
        }
    }
}

private struct DeviceMergeSheet: View {
    let source: SyncDeviceManagementItem
    let targets: [SyncDeviceManagementItem]
    let usageData: SyncedUsageData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeviceActionDeviceSummary(item: self.source)
                }

                Section {
                    ForEach(self.targets) { target in
                        Button {
                            let sourceID = self.source.canonicalDeviceID
                            let targetID = target.canonicalDeviceID
                            self.dismiss()
                            Task {
                                await self.usageData.mergeDevice(sourceDeviceID: sourceID, into: targetID)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                DeviceActionDeviceSummary(item: target)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title3)
                            }
                        }
                    }
                } footer: {
                    Text(
                        "Use this only when both entries are the same physical Mac after reinstall. History is preserved and the merge can be undone.")
                }
            }
            .navigationTitle("Merge with Another Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private enum DeviceLifecycleConfirmationKind: Equatable {
    case archive
    case restore
    case unmerge

    var title: LocalizedStringResource {
        switch self {
        case .archive:
            "Archive This Device?"
        case .restore:
            "Restore This Device?"
        case .unmerge:
            "Unmerge This Device?"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .archive:
            "Archive a real retired Mac. Its history stays available, but it no longer counts as active or triggers sync warnings."
        case .restore:
            "Restore this Mac to the active sync device list."
        case .unmerge:
            "Undo this merge and show the original device identities separately again."
        }
    }

    var buttonTitle: LocalizedStringResource {
        switch self {
        case .archive:
            "Archive Device"
        case .restore:
            "Restore Device"
        case .unmerge:
            "Unmerge"
        }
    }

    var buttonRole: ButtonRole? {
        switch self {
        case .archive, .unmerge:
            .destructive
        case .restore:
            nil
        }
    }

    var buttonTint: Color {
        switch self {
        case .archive, .unmerge:
            .red
        case .restore:
            .accentColor
        }
    }
}

private struct DeviceLifecycleConfirmationSheet: View {
    let kind: DeviceLifecycleConfirmationKind
    let item: SyncDeviceManagementItem
    let usageData: SyncedUsageData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                DeviceActionDeviceSummary(item: self.item)

                Text(self.kind.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button(role: self.kind.buttonRole) {
                        let item = self.item
                        let kind = self.kind
                        self.dismiss()
                        Task {
                            await self.perform(kind, item: item)
                        }
                    } label: {
                        Text(self.kind.buttonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(self.kind.buttonTint)

                    Button("Cancel", role: .cancel) {
                        self.dismiss()
                    }
                    .font(.headline)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .navigationTitle(String(localized: self.kind.title))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func perform(
        _ kind: DeviceLifecycleConfirmationKind,
        item: SyncDeviceManagementItem) async
    {
        switch kind {
        case .archive:
            await self.usageData.archiveDevices(item.sourceDeviceIDs)
        case .restore:
            await self.usageData.restoreDevices(item.sourceDeviceIDs)
        case .unmerge:
            await self.usageData.unmergeDevice(sourceDeviceIDs: item.sourceDeviceIDs)
        }
    }
}

private struct DeviceActionDeviceSummary: View {
    let item: SyncDeviceManagementItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.item.isArchived ? "archivebox" : "laptopcomputer")
                .foregroundStyle(self.item.isArchived ? Color.secondary : Color.accentColor)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.item.snapshot.deviceName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(self.item.snapshot.syncTimestamp.formatted(.relative(presentation: .named)))
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(self.item.snapshot.providers.count) providers")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let version = self.item.snapshot.appVersion {
                    Text("CodexBar \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Raw Sync Data (Developer Debug View)

private struct RawSyncDataView: View {
    let usageData: SyncedUsageData

    var body: some View {
        List {
            if self.usageData.rawDeviceSnapshots.isEmpty {
                Section {
                    Text("No device data available")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(self.usageData.rawDeviceSnapshots.enumerated()), id: \.offset) { _, device in
                    RawDeviceSection(device: device)
                }
            }
        }
        .navigationTitle("Raw Sync Data")
    }
}

private struct RawDeviceSection: View {
    let device: SyncedUsageSnapshot

    var body: some View {
        Section {
            LabeledContent("Device ID", value: self.device.deviceID ?? "N/A")
            LabeledContent("Device Name", value: self.device.deviceName)
            LabeledContent("App Version", value: self.device.appVersion ?? "Unknown")
            LabeledContent(
                "Sync Time",
                value: self.device.syncTimestamp.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Providers", value: "\(self.device.providers.count)")

            // Use cardIdentityKey (providerID|accountEmail) so multi-account
            // and mock-vs-real entries with the SAME providerID don't get
            // collapsed by SwiftUI's diffing. Hit on user QA 2026-05-04 —
            // real `codex|msxiao113@gmail.com` and `codex|alice-mock@codex.test`
            // were rendering as a single row because both had providerID == "codex".
            ForEach(self.device.providers, id: \.cardIdentityKey) { provider in
                RawProviderRow(provider: provider)
            }
        } header: {
            HStack {
                Image(systemName: "laptopcomputer")
                Text(self.device.deviceName)
            }
        }
    }
}

private struct RawProviderRow: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        NavigationLink {
            RawProviderDetailView(provider: self.provider)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.provider.providerName)
                        .fontWeight(.medium)
                    // Email visible at a glance — distinguishes real vs mock
                    // and Codex multi-account on the spot. Hit during user QA
                    // 2026-05-04 (couldn't tell which 'Claude' row was real).
                    if let email = self.provider.accountEmail, !email.isEmpty {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(
                            "(no email)",
                            comment: "Raw Sync Data row subtitle when provider has no account email (e.g. Claude / Ollama / Copilot)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let cost = self.provider.costSummary {
                        // 30-day cost is what iPhone Cost dashboard
                        // aggregates — show it inline so multi-device sync
                        // bugs are visible at a glance instead of needing
                        // a tap into detail.
                        Text(String(
                            format: String(
                                localized: "$%.2f / 30d",
                                comment: "Raw Sync Data row trailing label — 30-day cost"),
                            cost.last30DaysCostUSD ?? 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(
                            format: String(
                                localized: "$%.2f / today",
                                comment: "Raw Sync Data row trailing label — today's cost"),
                            cost.sessionCostUSD ?? 0))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let window = self.provider.allRateWindows.first {
                        Text("\(window.label ?? "Usage"): \(Int(window.usedPercent))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct RawProviderDetailView: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Provider", value: self.provider.providerName)
                LabeledContent("ID", value: self.provider.providerID)
                if let email = self.provider.accountEmail {
                    LabeledContent("Account", value: email)
                }
                if let login = self.provider.loginMethod {
                    LabeledContent("Login", value: login)
                }
                LabeledContent(
                    "Last Updated",
                    value: self.provider.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                if self.provider.isError {
                    LabeledContent("Status", value: self.provider.statusMessage ?? "Error")
                        .foregroundStyle(.red)
                }
            }

            if let cost = self.provider.costSummary {
                Section("Cost Summary") {
                    LabeledContent("Session", value: self.formatCost(cost.sessionCostUSD))
                    LabeledContent("Session Tokens", value: self.formatTokens(cost.sessionTokens))
                    LabeledContent("30 Days", value: self.formatCost(cost.last30DaysCostUSD))
                    LabeledContent("30 Days Tokens", value: self.formatTokens(cost.last30DaysTokens))
                }
            }

            self.rateWindowsSection

            if let cost = self.provider.costSummary, !cost.daily.isEmpty {
                self.dailyCostSection(cost.daily)
            }
        }
        .navigationTitle(self.provider.providerName)
    }

    @ViewBuilder
    private var rateWindowsSection: some View {
        let windows = self.provider.allRateWindows
        if !windows.isEmpty {
            Section("Rate Limits") {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    RawRateWindowRow(window: window)
                }
            }
        }
    }

    @ViewBuilder
    private func dailyCostSection(_ daily: [SyncDailyPoint]) -> some View {
        let sorted = daily.sorted { $0.dayKey > $1.dayKey }
        Section("Daily Cost (\(sorted.count) days)") {
            ForEach(sorted, id: \.dayKey) { day in
                RawDailyPointRow(day: day)
            }
        }
    }

    private func formatCost(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "$%.2f", value)
    }

    private func formatTokens(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }
}

private struct RawRateWindowRow: View {
    let window: SyncRateWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(self.window.label ?? "Rate Limit")
                Spacer()
                Text("\(Int(self.window.usedPercent))% used")
                    .foregroundStyle(self.window.usedPercent > 80 ? .red : .secondary)
            }
            ProgressView(value: min(self.window.usedPercent, 100), total: 100)
                .tint(self.window.usedPercent > 80 ? .red : .blue)
            if let reset = self.window.resetDescription {
                Text("Resets \(reset)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RawDailyPointRow: View {
    let day: SyncDailyPoint

    var body: some View {
        DisclosureGroup {
            self.breakdownContent
        } label: {
            HStack {
                Text(self.day.dayKey)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.2f", self.day.costUSD))
                        .font(.body.monospacedDigit())
                    Text(self.formatTokens(self.day.totalTokens))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var breakdownContent: some View {
        if !self.day.modelBreakdowns.isEmpty {
            ForEach(self.day.modelBreakdowns, id: \.label) { item in
                VStack(alignment: .leading, spacing: 1) {
                    LabeledContent(item.label, value: String(format: "$%.2f", item.costUSD))
                    if let split = CodexCostSplit.subtitle(
                        standardCostUSD: item.standardCostUSD,
                        priorityCostUSD: item.priorityCostUSD)
                    {
                        Text(split)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !self.day.serviceBreakdowns.isEmpty {
            ForEach(self.day.serviceBreakdowns, id: \.label) { item in
                LabeledContent(item.label, value: String(format: "$%.2f", item.costUSD))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTokens(_ value: Int) -> String {
        CostFormatting.tokens(value)
    }
}

// MARK: - Developer Tools (container listing all dev tools)

private struct DeveloperToolsView: View {
    let usageData: SyncedUsageData

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RawSyncDataView(usageData: self.usageData)
                } label: {
                    SettingSummaryRow(
                        title: "Raw Sync Data",
                        symbolName: "doc.text.magnifyingglass",
                        summary: String(localized: "Per-device unmerged data for debugging"))
                }

                NavigationLink {
                    CostDiagnosticsView(usageData: self.usageData)
                } label: {
                    SettingSummaryRow(
                        title: "Cost Diagnostics",
                        symbolName: "dollarsign.gauge.chart.lefthalf.righthalf",
                        summary: String(localized: "Audit Cost totals and merge rules"))
                }

                NavigationLink {
                    PushSetupDiagnosticView()
                } label: {
                    SettingSummaryRow(
                        title: "Push Setup",
                        symbolName: "bell.badge.waveform",
                        summary: "Alert push subscription state")
                }

                NavigationLink {
                    ICloudSyncDiagnosticView(usageData: self.usageData)
                } label: {
                    SettingSummaryRow(
                        title: "iCloud Sync Diagnostics",
                        symbolName: "icloud.and.arrow.up",
                        summary: String(localized: "Read-only account, zone, fallback, and device checks"))
                }
            } footer: {
                Text("These tools may show internal sync state, device identifiers, and account emails for debugging.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Developer Tools")
    }
}

// MARK: - iCloud Sync Diagnostics

private struct ICloudSyncDiagnosticView: View {
    let usageData: SyncedUsageData
    @State private var reportText = String(localized: "No check run yet.")
    @State private var isRunning = false

    var body: some View {
        List {
            Section("Current Reader State") {
                LabeledContent("Status", value: self.readerStatus)
                LabeledContent(
                    "Data source",
                    value: self.usageData.usingKVSFallback
                        ? String(localized: "KVS fallback")
                        : String(localized: "CloudKit"))
                LabeledContent("Mac devices", value: "\(self.usageData.deviceCount)")
                if let error = self.usageData.lastSyncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Read-Only Check") {
                Text("This check never creates, changes, or deletes iCloud records, zones, subscriptions, or schema.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(self.reportText)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)

                Button("Run Read-Only Check") {
                    self.runCheck()
                }
                .disabled(self.isRunning)

                Button("Copy Diagnostic Report") {
                    UIPasteboard.general.string = self.fullReport
                }
            }

            Section("Actions") {
                Button("Refresh Synced Data") {
                    Task { await self.usageData.refresh() }
                }
                .disabled(self.usageData.syncStatus == .syncing)
            }
        }
        .navigationTitle("iCloud Sync Diagnostics")
        .task {
            if self.reportText == String(localized: "No check run yet.") {
                self.runCheck()
            }
        }
    }

    private var readerStatus: String {
        switch self.usageData.syncStatus {
        case let .synced(ago):
            String(format: String(localized: "Synced %lld seconds ago"), Int64(ago))
        case .syncing: String(localized: "Syncing")
        case let .error(message): String(
                format: String(localized: "Error: %@"),
                message)
        case .noData: String(localized: "No Mac data")
        case .incompatibleData: String(localized: "Incompatible data")
        }
    }

    private var fullReport: String {
        let devices = self.usageData.deviceSnapshots
            .sorted { $0.syncTimestamp > $1.syncTimestamp }
            .map { snapshot in
                "- \(snapshot.deviceName): \(snapshot.syncTimestamp.formatted(.iso8601)), "
                    + "Mac \(snapshot.appVersion ?? "unknown")"
            }
            .joined(separator: "\n")
        return """
        \(self.reportText)

        iPhone reader: \(self.readerStatus)
        Data source: \(self.usageData
            .usingKVSFallback ? String(localized: "KVS fallback") : String(localized: "CloudKit"))
        Devices (\(self.usageData.deviceCount)):
        \(devices.isEmpty ? "none" : devices)
        """
    }

    private func runCheck() {
        self.isRunning = true
        self.reportText = String(localized: "Running read-only iCloud checks…")
        Task {
            let report = await CloudSyncManager.shared.runReadOnlyDiagnostic()
            self.reportText = report.text
            self.isRunning = false
        }
    }
}

// MARK: - Cost Diagnostics View

private struct CostDiagnosticsView: View {
    let usageData: SyncedUsageData

    @Environment(\.modelContext) private var modelContext
    @AppStorage(MobileSettingsKeys.cwlEnabled) private var cwlEnabled = MobileSettingsDefaults.cwlEnabled
    @AppStorage(MobileSettingsKeys.cwlWindowDays) private var cwlWindowDays = MobileSettingsDefaults.cwlWindowDays
    @AppStorage(MobileSettingsKeys.cwlBlobSeedClearedAt) private var cwlBlobSeedClearedAt: Double = 0
    @State private var cachedLedgerSignature: String?
    @State private var cachedLedgerAggregation: CostLedgerAggregation?
    @State private var ledgerRefreshDayKey = CostLedgerRefreshClock.currentDayKey()

    var body: some View {
        List {
            if let report = self.report {
                Section("Summary") {
                    LabeledContent("Source", value: self.sourceText(report.dataSource))
                    LabeledContent("Window", value: String(format: String(localized: "%d days"), report.windowDays))
                    LabeledContent("Total Cost", value: CostFormatting.usd(report.totalCostUSD))
                    LabeledContent("Today", value: CostFormatting.usd(report.todayCostUSD))
                    LabeledContent("Active Days", value: "\(report.activeDayCount)")
                    LabeledContent("Top Driver", value: self.topDriverText(report))
                    LabeledContent("Active Devices", value: "\(report.activeDeviceCount)")
                    if report.excludedDeviceCount > 0 {
                        LabeledContent("Excluded Devices", value: "\(report.excludedDeviceCount)")
                    }
                }

                Section("Provider Rules") {
                    ForEach(report.providerRules) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rule.providerName)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(self.mergeRuleText(rule.rule))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let account = rule.accountEmail, !account.isEmpty {
                                Text(account)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("Reconciliation") {
                    ForEach(report.checks) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: self.statusSymbol(item.status))
                                .foregroundStyle(self.statusColor(item.status))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(self.checkTitle(item.kind))
                                    .fontWeight(.medium)
                                Text(self.checkDetail(item.detail))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Raw Inputs") {
                    NavigationLink {
                        RawSyncDataView(usageData: self.usageData)
                    } label: {
                        SettingSummaryRow(
                            title: "Open Raw Sync Data",
                            symbolName: "doc.text.magnifyingglass",
                            summary: String(localized: "Inspect per-device synced rows used as source input"))
                    }
                }
            } else {
                Section {
                    Text("No cost data available")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Cost Diagnostics")
        .task(id: self.ledgerRefreshSignature) {
            self.refreshLedgerAggregation(for: self.ledgerRefreshSignature)
        }
        .task {
            await self.keepLedgerRefreshDayCurrent()
        }
    }

    private var report: CostDiagnosticsReport? {
        guard let snapshot = self.usageData.snapshot else { return nil }
        let aggregation = self.cwlEnabled && self.cachedLedgerSignature == self.ledgerRefreshSignature
            ? self.cachedLedgerAggregation
            : nil

        return CostDiagnosticsReportResolver.make(
            snapshot: snapshot,
            ledgerAggregation: aggregation,
            rawDeviceSnapshots: self.usageData.rawDeviceSnapshots,
            activeDeviceSnapshots: self.usageData.deviceSnapshots,
            cwlEnabled: self.cwlEnabled,
            cwlWindowDays: self.cwlWindowDays,
            localHistoryClearedAt: CostLedgerService.blobSeedClearTombstoneDate())
    }

    private var activeDeviceIDsForLedger: Set<String>? {
        CostLedgerDeviceFilter.activeDeviceIDs(for: self.usageData.deviceSnapshots)
    }

    private var ledgerRefreshSignature: String {
        CostLedgerRefreshSignature.make(
            isEnabled: self.cwlEnabled,
            windowDays: self.cwlWindowDays,
            activeDeviceIDs: self.activeDeviceIDsForLedger,
            snapshots: self.usageData.deviceSnapshots,
            clearTombstone: self.cwlBlobSeedClearedAt,
            currentDayKey: self.ledgerRefreshDayKey)
    }

    @MainActor
    private func refreshLedgerAggregation(for signature: String) {
        guard self.cwlEnabled else {
            self.cachedLedgerSignature = signature
            self.cachedLedgerAggregation = nil
            return
        }
        self.cachedLedgerAggregation = CostDiagnosticsLedgerAggregationResolver.make(
            cwlEnabled: self.cwlEnabled,
            cwlWindowDays: self.cwlWindowDays,
            modelContext: self.modelContext,
            activeDeviceIDs: self.activeDeviceIDsForLedger)
        self.cachedLedgerSignature = signature
    }

    @MainActor
    private func keepLedgerRefreshDayCurrent() async {
        while !Task.isCancelled {
            let currentDayKey = CostLedgerRefreshClock.currentDayKey()
            if self.ledgerRefreshDayKey != currentDayKey {
                self.ledgerRefreshDayKey = currentDayKey
            }
            try? await Task.sleep(nanoseconds: CostLedgerRefreshClock.nanosecondsUntilNextLocalDay())
        }
    }

    private func sourceText(_ source: CostDiagnosticsDataSource) -> String {
        switch source {
        case .localLedger:
            String(localized: "Local Ledger")
        case .syncedSnapshots:
            String(localized: "Synced Snapshots")
        case .syncedSnapshotsAfterLedgerFailure:
            String(localized: "Synced Snapshots (ledger unavailable)")
        }
    }

    private func mergeRuleText(_ rule: CostDiagnosticsMergeRule) -> String {
        switch rule {
        case .sumActiveDevices:
            String(localized: "sum active devices")
        case .latestAccountDay:
            String(localized: "latest account/day row")
        }
    }

    private func checkTitle(_ kind: CostDiagnosticsCheckKind) -> String {
        switch kind {
        case .providerShare:
            String(localized: "Provider Share")
        case .dailySpend:
            String(localized: "Daily Spend")
        case .modelMix:
            String(localized: "Model Mix")
        case .serviceMix:
            String(localized: "Codex Service Mix")
        case .shareCard:
            String(localized: "Share Card")
        }
    }

    private func checkDetail(_ detail: CostDiagnosticsCheckDetail) -> String {
        switch detail {
        case .matchesOverviewTotal:
            String(localized: "Matches Overview total")
        case let .difference(delta):
            String(
                format: String(localized: "Difference %@"),
                CostFormatting.usd(delta))
        case let .covers(fraction):
            String(
                format: String(localized: "Covers %.0f%% of total"),
                fraction * 100)
        case .noCostTotal:
            String(localized: "No cost total")
        case .noBreakdownData:
            String(localized: "No breakdown data")
        case .usesExactProviderDailyPoints:
            String(localized: "Uses exact provider daily points")
        case let .sevenDayProviderDifference(delta):
            String(
                format: String(localized: "7-day provider difference %@"),
                CostFormatting.usd(delta))
        }
    }

    private func topDriverText(_ report: CostDiagnosticsReport) -> String {
        guard let name = report.topDriverName, let cost = report.topDriverCostUSD else {
            return String(localized: "None")
        }
        return "\(name) · \(CostFormatting.usd(cost))"
    }

    private func statusSymbol(_ status: CostDiagnosticsStatus) -> String {
        switch status {
        case .pass:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .unavailable:
            "minus.circle.fill"
        }
    }

    private func statusColor(_ status: CostDiagnosticsStatus) -> Color {
        switch status {
        case .pass:
            .green
        case .warning:
            .orange
        case .unavailable:
            .secondary
        }
    }
}

// MARK: - Push Setup Diagnostic View

private struct PushSetupDiagnosticView: View {
    @State private var diag = PushSetupDiagnostic.shared
    @State private var persistenceTestResult: String?

    var body: some View {
        List {
            Section("Setup Status") {
                self.row("Zone", self.diag.zoneStatus)
                self.row("Depleted Sub", self.diag.depletedSubStatus)
                self.row("Restored Sub", self.diag.restoredSubStatus)
                self.row("Permission", self.diag.notificationPermission)
                self.row("APNs Registration", self.diag.remoteRegistration)
            }

            Section("Subscription List (from iOS)") {
                Text(self.diag.subscriptionList)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)

                Button("Refresh") {
                    Task {
                        await PushSetupDiagnostic.shared.refreshSubscriptionList()
                    }
                }
                .controlSize(.small)
            }

            if let error = self.diag.lastError {
                Section("Last Error") {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Actions") {
                Button("Force Re-run Setup") {
                    Task { @MainActor in
                        await QuotaTransitionSubscriptions.shared.setupIfNeeded()
                    }
                }

                Button("Verify Subscription Persistence") {
                    self.persistenceTestResult = "Running…"
                    Task { @MainActor in
                        let result = await QuotaTransitionSubscriptions.shared.runPersistenceTest()
                        self.persistenceTestResult = result
                    }
                }

                if let result = self.persistenceTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                        .textSelection(.enabled)
                }
            }

            #if DEBUG
            // NSE invocation log was added in build 122 to diagnose the
            // mutable-content / staleness chain. Useful for developers; not
            // shown in RELEASE builds (TestFlight + App Store) — the storage
            // backing (`NSEInvocationLog` → `NSUbiquitousKeyValueStore`) is
            // still active so a future DEBUG build can read prior entries.
            Section("Recent NSE Invocations") {
                NSEInvocationLogSection(entries: self.nseEntries)
                HStack {
                    Button("Refresh") {
                        self.nseEntries = NSEInvocationLog.shared.loadAll()
                    }
                    .controlSize(.small)
                    Button("Clear") {
                        NSEInvocationLog.shared.clear()
                        self.nseEntries = []
                    }
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            #endif

            if let ts = self.diag.lastUpdated {
                Section {
                    Text("Last updated: \(ts.formatted(.dateTime))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Push Setup")
        .onAppear {
            self.nseEntries = NSEInvocationLog.shared.loadAll()
        }
    }

    @State private var nseEntries: [NSEInvocationEntry] = []

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.bold())
            Text(value)
                .font(.caption)
                .foregroundStyle(value.hasPrefix("✓") ? .green :
                    (value.hasPrefix("✗") ? .red : .secondary))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

/// Renders the NSE invocation log (newest first) so a developer can verify
/// end-to-end the warning push pipeline without reading device logs in
/// Console.app. Empty state hints the user how to populate it.
private struct NSEInvocationLogSection: View {
    let entries: [NSEInvocationEntry]

    var body: some View {
        if self.entries.isEmpty {
            Text("No NSE invocations recorded. Trigger a push from the Mac DEV menu, then tap Refresh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(self.entries.reversed().enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.event.rawValue.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(self.color(for: entry.event))
                        Spacer()
                        Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    if let zone = entry.zoneName {
                        Text(zone)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.detail)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func color(for event: NSEInvocationEvent) -> Color {
        switch event {
        case .ok: .green
        case .woke: .blue
        case .zoneNil, .fetchNil: .orange
        case .fetchError: .red
        }
    }
}

private struct ReleaseNotesVersion: Identifiable {
    struct Section: Identifiable {
        let title: String
        let items: [String]

        var id: String {
            self.title
        }
    }

    let version: String
    let status: String
    let summary: String
    let sections: [Section]

    var id: String {
        self.version
    }
}

private enum MobileReleaseNotesCatalog {
    static let versions: [ReleaseNotesVersion] = [
        ReleaseNotesVersion(
            version: "1.19.1",
            status: String(localized: "Latest"),
            summary: String(
                localized: "Fixes for Alibaba Token Plan and Subscription Utilization."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Alibaba Token Plan now shows 5-hour and weekly limits, and Subscription Utilization uses the latest quota history. Update CodexBar on Mac to 0.45.2.2 for the full fix."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.19.0",
            status: "",
            summary: String(
                localized: "iPhone 1.19 adds eight providers, richer quota details, clearer limits, and more reliable iCloud sync."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Eight more providers — ClinePass, DeepInfra, Neuralwatt, LongCat, sub2api, Wayfinder, ZenMux, and ai& now appear with their own colors and detail pages, plus quota alerts when available."),
                        String(
                            localized: "Kimi at a glance — see Weekly, five-hour, Monthly, and Code 7-day limits in one consistent order."),
                        String(
                            localized: "Clearer Claude plans — Max 5x and Max 20x stay distinct, even while your Macs update at different times."),
                        String(
                            localized: "More complete details — sub2api shows account balance and request totals, while Wayfinder shows routing activity and savings."),
                        String(
                            localized: "More reliable quota history — monthly and additional limits stay visible alongside daily and weekly windows, and Subscription Utilization automatically uses the freshest quota history when session history stops updating."),
                        String(
                            localized: "Small percentages — every positive usage value below 1% now displays as <1% instead of rounding to 0% or 1%."),
                        String(
                            localized: "Reliable iCloud sync — stalled Mac uploads now time out with a clear failure instead of spinning forever, and Developer Tools includes a read-only iCloud diagnostic report."),
                        String(
                            localized: "A smoother Mac companion — CodexBar for Mac now recovers sign-ins more safely, reports usage more accurately, and improves performance, menus, and settings."),
                        String(
                            localized: "A more capable Mac companion — customize menu bar layouts, see usage forecasts, use safer refresh controls, and benefit from the latest provider, performance, and security fixes."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "For all new details, update CodexBar on Mac to version 0.45.2.1 or later. iPhone 1.19 still works with data from older Mac versions."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.17.0",
            status: "",
            summary: String(
                localized: "iPhone 1.17 brings the CodexBar 0.39 sync: new provider cards, CrossModel wallet details, expanded quota alerts, and the latest Mac provider fixes."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "New providers — iPhone now recognizes Sakana AI, Qoder, CrossModel, and ClawRouter from Mac sync, with provider colors, quota alerts, mock data, and detail pages included."),
                        String(
                            localized: "CrossModel details — CrossModel now shows balance, uncollected spend, and daily, weekly, and monthly usage on iPhone instead of an empty provider page."),
                        String(
                            localized: "Cost data integrity — Overview, Provider Share, Daily Spend, Model Mix, Codex Service Mix, and share cards now use the same provider-aware cost reducer so local CLI spend is summed across active Macs without double-counting account-level providers."),
                        String(
                            localized: "Cost history defaults — Local cost history now starts on with a 90-day window, and Cost Settings explains how it differs from the synced Mac snapshot path."),
                        String(
                            localized: "Cost diagnostics — Developer Tools can now show the source path, provider rules, and reconciliation checks behind the Cost totals."),
                        String(
                            localized: "Widget polish — updated timestamps are centered across every widget size and mode."),
                        String(
                            localized: "Provider fixes included — the companion app understands the latest Mac data for Sakana AI quotas, Qoder credits, ClawRouter budget usage, CrossModel wallet usage, and upstream menu/provider reliability fixes."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.39.0.1 (fork build 97.1 or later) for the full 1.17 experience. iPhone 1.17.0 still opens older Mac data; new provider details appear after Mac updates."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.16.0",
            status: "",
            summary: String(
                localized: "iPhone 1.16 adds Home Screen widgets for CodexBar usage, cost, and sync health."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Home Screen widgets — add CodexBar widgets in small, medium, large, or iPad extra-large sizes to see provider usage, today’s cost, and sync health at a glance, with layouts tested through SpringBoard on iPhone and iPad and tuned for Light, Dark, and tinted Home Screen appearances."),
                        String(
                            localized: "Widget previews — open Widget Setting in Settings to review every widget mode as individual framed Home Screen previews across small, medium, large, and iPad extra-large sizes, using the same native widget layout and spacing as the real widgets."),
                        String(
                            localized: "Widget appearance — choose Mono or Colorful for each Home Screen widget, and preview both styles in Widget Setting before adding or editing widgets."),
                        String(
                            localized: "Widget polish — Today Cost widgets now use the same merged cost totals as the Cost page, show token usage more clearly, center their updated timestamp, and keep provider rows focused on useful Provider labels instead of account-plan text."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(
                            localized: "Widgets read synced CodexBar data from CloudKit and fall back to older iCloud snapshots when needed, with no App Group setup required."),
                        String(
                            localized: "Cost totals now cross-check the synced provider summary, so the Cost page no longer undercounts spend when daily history is incomplete."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.15.0",
            status: "",
            summary: String(
                localized: "iPhone 1.15 brings the CodexBar 0.37 sync: Codex reset credits, clearer estimated-usage notices, safer provider endpoints, improved diagnostics, and the latest Mac provider fixes."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Codex reset credits — when Mac 0.37.2.1 syncs available manual resets, iPhone shows the count and next expiration on the Codex detail page."),
                        String(
                            localized: "Usage confidence — if Mac only has estimated or percentage-only usage, iPhone now calls that out instead of presenting the data as exact."),
                        String(
                            localized: "Provider updates included — Cursor personal on-demand usage, Mistral Vibe monthly limits, Bedrock CloudWatch activity, MiniMax model names, and CommandCode quota transitions benefit from the latest Mac sync."),
                        String(
                            localized: "Diagnostics and security — Mac 0.37 adds stronger provider endpoint validation, safer Codex OAuth credential permissions, improved CLI diagnostics, and more reliable Claude/Codex web reads."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.37.2.1 (fork build 92.1 or later) for the full 1.15 experience. iPhone 1.15.0 still opens older Mac data; new Codex reset-credit and confidence details appear after Mac updates."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.14.0",
            status: "",
            summary: String(
                localized: "iPhone 1.14 adds Sync Device Management for duplicate or retired Mac devices, with non-destructive merge, archive, restore, and unmerge controls."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Merge duplicate Macs — if reinstalling a Mac creates a second sync device, combine the old and new identities without deleting history."),
                        String(
                            localized: "Archive retired Macs — keep old device history while removing retired Macs from the active device count and stale sync warnings."),
                        String(
                            localized: "Undo when needed — restore archived devices or unmerge device identities from Settings → About & Sync."),
                        String(
                            localized: "Safer local cost totals — merged identities from the same physical Mac no longer count local CLI history as two separate computers."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "No Mac update is required for this iPhone feature. Existing Mac sync data is preserved; a CloudKit schema update may be required before release."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.13.0",
            status: "",
            summary: String(
                localized: "iPhone 1.13 is a larger Mac sync update: more provider coverage, richer quota and renewal details, and steadier Mac-to-iPhone data while you upgrade."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Provider coverage — Devin, LiteLLM, Poe, Chutes, and Zed can now appear on iPhone when your Mac syncs their usage, with quota notifications prepared for the new providers."),
                        String(
                            localized: "Richer cards — MiniMax renewal dates, Copilot budget windows, MiMo balance and token-plan updates, Kimi Code API usage, and Poe point history now travel through the shared sync data where iOS can show them."),
                        String(
                            localized: "Smoother upgrades — iPhone keeps rich provider details when one Mac has updated and another is still catching up, so cards should not flicker back to empty during a rolling upgrade."),
                        String(
                            localized: "Mac improvements included — this release carries the 0.35.0 through 0.36.1 provider accuracy, security, localization, and menu reliability fixes to the companion app."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.36.1.1 (fork build 88.1 or later) for the full 1.13 experience. iPhone 1.13.0 still opens older Mac data, but new provider details appear after Mac updates."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.11.1",
            status: "",
            summary: String(
                localized: "The Daily Spend chart on the Cost tab now scrolls through your full accumulated history instead of cramming every day into one screen."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Daily Spend chart — shows a clean ~30-day window and scrolls left to reveal your full cost history (30 / 90 / 365-day windows); the latest day stays pinned to the right edge."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.11.0",
            status: "",
            summary: String(
                localized: "Quieter, more accurate provider data synced from your Mac — Antigravity quota rows without the noise, correct Copilot usage on zero-entitlement plans, fixed Augment parsing, and steadier Claude readings — from the CodexBar 0.32.4 sync."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Search — filter the Usage list by provider name; handy when many providers are synced."),
                        String(
                            localized: "Antigravity — quota rows are cleaner: image / lite / autocomplete / internal noise rows no longer skew the summary bar."),
                        String(
                            localized: "Copilot — zero-entitlement business tokens no longer show a misleading usage percentage."),
                        String(
                            localized: "Augment — usage parses correctly again after the upstream status-format change."),
                        String(
                            localized: "Claude — a brief sign-in hiccup no longer blanks your usage; the last good reading is kept."),
                        String(
                            localized: "Codex / Claude cost — refreshed by the v0.32 cost-scanner update; your cost cards re-scan to the corrected numbers."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.32.4 (fork build 79.1 or later). iPhone 1.11.0 stays forward-compatible with older Mac builds — these refinements simply arrive once Mac is updated."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.10.0",
            status: "",
            summary: String(
                localized: "DeepSeek web-session usage and cost on your iPhone, Codex Spark and Antigravity per-model quota lanes synced through, and cost cards that show request counts in the right currency — from the CodexBar 0.31.0 sync."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "DeepSeek — usage card with web-session today / this-month tokens, spend, and request counts shown alongside your balance."),
                        String(
                            localized: "Codex Spark — 5-hour and weekly Spark model quota lanes now sync to your iPhone."),
                        String(
                            localized: "Antigravity — full per-model quota lanes now flow through, not just the three-family summary."),
                        String(
                            localized: "Cost cards — now show request counts and format amounts in the synced currency (e.g. EUR / CNY), not just USD."),
                        String(
                            localized: "Upstream fixes flow through automatically — the corrected Claude Enterprise extra-usage amount (no longer 100x too high), Grok / Ollama window labels and pace projection, and the Claude Design lane folded into the main Claude limit."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.31.0 (fork build 73.2 or later) to surface the DeepSeek card and the Codex Spark / Antigravity lanes. iPhone 1.10.0 stays forward-compatible with older Mac builds — the new cards simply stay hidden until Mac is updated."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.9.0",
            status: "",
            summary: String(
                localized: "Three new providers (Azure OpenAI, Alibaba Token Plan, T3 Chat) from the CodexBar 0.29.0 sync — plus richer detail across many providers: the iPhone now surfaces more of what your Mac already tracks."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Azure OpenAI — usage card validating deployment status from your API key, endpoint, and deployment name."),
                        String(
                            localized: "Alibaba Token Plan (Bailian) — monthly token-plan quota card showing used and total credits with the reset date, imported from browser or manual cookies."),
                        String(
                            localized: "T3 Chat — web-session usage card with a 4-hour base window plus a monthly overage window."),
                        String(
                            localized: "Richer detail elsewhere too — Codex standard/fast spend split per model, an OpenRouter balance & credits card, Mistral daily cost in the Cost dashboard, the Antigravity multi-account switcher, and cost summaries that show the real history window (not always 30 days)."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.29.0 (fork build 68.1 or later) to see the three new providers. iPhone 1.9.0 stays forward-compatible with older Mac builds — the new cards simply stay hidden until Mac is on 0.29.0."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.8.0",
            status: "",
            summary: String(
                localized: "Five dedicated provider cards (Grok / ElevenLabs / Deepgram / GroqCloud / LLM Proxy), Kiro overage badge, Anthropic Admin API spend, Claude Enterprise spend-limit, OpenAI history-window picker, OpenCode Go Zen balance, MiniMax 30-day billing, plus quota notifications now include the triggering account and Codex shows the active workspace + weekly pace."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Grok (xAI) — dedicated card showing monthly USD spend, plan tier badge, percent used, and the renewal date. Uses Grok CLI billing when available, falls back to grok.com web billing."),
                        String(
                            localized: "ElevenLabs — dedicated card with character credits primary bar, voice slots and professional voice slots rows when present, tier badge, and renewal date."),
                        String(
                            localized: "Deepgram — dedicated card with speech / agent / total hours breakdown, request count, agent tokens, optional TTS character count, and a project badge with '(of N)' hint when you have multiple projects."),
                        String(
                            localized: "GroqCloud — dedicated card with three live-rate columns (requests/min, tokens/min, cache hits/min) plus the cache-hit percentage as a coloured badge."),
                        String(
                            localized: "LLM Proxy — dedicated card showing lowest-remaining-quota headline, credential pool health (active / exhausted keys), aggregate request and token counts, and the top three upstream providers with per-provider request / token / cost breakdown."),
                        String(
                            localized: "Kiro overage — when your monthly plan is exhausted and you're paying for additional credits, the Kiro card now shows the overage credit count and estimated USD cost as an inline orange badge."),
                        String(
                            localized: "Anthropic Admin API on the Claude detail page — Today / 7d / 30d cost summary, top models, and top cost items when an Admin API key is configured on Mac."),
                        String(
                            localized: "Claude Extra usage (spend-limit) card for Enterprise / Team plans — utilization gauge, monthly spend vs limit, and a plan-tier badge."),
                        String(
                            localized: "OpenAI API Dashboard window picker — switch the chart range between 7 / 30 / 90 / 180 / 365 days, clamped to whatever Mac fetched."),
                        String(
                            localized: "OpenCode Go Zen workspace balance — pay-as-you-go USD balance shown below the rolling / weekly / monthly bars."),
                        String(
                            localized: "MiniMax 30-day billing card — Today + 30-day token and USD totals, a 30-day bar chart, and top-3 method / model breakdowns."),
                        String(
                            localized: "Quota notifications now include the triggering account on multi-account providers — e.g. 'Codex · admin@example.com' instead of bare 'Codex'. Honours the Mac Hide-personal-info toggle."),
                        String(
                            localized: "Codex workspace badge — when your active Codex account belongs to an OpenAI workspace, the workspace name shows as a caption under the account email plus a weekly pace arrow (up = ahead of pace, down = under pace)."),
                        String(
                            localized: "Existing Kiro / AWS Bedrock / Moonshot / z.ai / OpenAI API Dashboard / Antigravity multi-account cards from 1.7.0 keep working with no change."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.27.0 (fork build 65.3 or later) for the full v0.27 surface including the quota account identity push title and Codex workspace badge. iPhone 1.8.0 also remains forward-compatible with Mac 0.26.x and 65.1 / 65.2 — newer tiles just stay hidden / fall back to the older title format until Mac is on 65.3."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.7.0",
            status: "",
            summary: String(
                localized: "Six new dedicated provider cards (Kiro credits, AWS Bedrock cost, Moonshot / Kimi API balance, z.ai hourly chart, OpenAI API Dashboard, Antigravity multi-account) plus two new settings toggles."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "OpenAI Admin API Dashboard on the OpenAI provider page — Today / 7 days / 30 days summary cards, a 30-day spend chart, and top models / top line items lists. Requires Mac 0.26.2 with Admin API access."),
                        String(
                            localized: "Kiro: dedicated credits card with plan tag, primary credit usage progress, and an optional bonus pool with expiry countdown."),
                        String(
                            localized: "AWS Bedrock (NEW): monthly spend + budget card with the active AWS region. Color-coded as approach 75% / 90% of budget."),
                        String(
                            localized: "Moonshot / Kimi API (NEW): clean balance + currency + region card so you can see your top-up at a glance."),
                        String(
                            localized: "z.ai hourly chart: stacked per-model token usage for the last 24 hours, with model legend."),
                        String(
                            localized: "Antigravity multi-account switcher: when more than one Google account is wired on Mac, the iPhone shows the linked list with active-account marker."),
                        String(
                            localized: "Two new Settings toggles — Hide quota-warning markers (only the tick-marks; notifications still fire) and Show provider changelog links (companion section in Settings → About)."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.26.1 (fork build 63.2 or later). iPhone 1.7.0 is also forward-compatible with Mac 0.25.2 — new cards just stay hidden until Mac is on the new build."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.6.0",
            status: "",
            summary: String(
                localized: "11 new provider cards plus a Claude peak-hours indicator and pre-depletion warning markers on every usage bar."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "11 new providers from Mac CodexBar v0.24/v0.25 — Windsurf, Codebuff, DeepSeek, Manus, Xiaomi MiMo, Doubao, Command Code, StepFun, Crof, Venice, OpenAI API. Each renders in its own brand color across Usage / Cost / Subscription tabs and on the provider detail page."),
                        String(
                            localized: "Push notifications expanded to cover the 11 new providers — your iPhone now pings on their quota events the same way it does for the existing 27."),
                        String(
                            localized: "Claude peak-hours indicator on the Claude detail page — quick glance at whether you're inside Anthropic's published 8am-2pm ET peak window or how long until the next one starts."),
                        String(
                            localized: "Quota warning markers on every usage bar — tick marks at the thresholds you set on Mac (default 50% / 20% remaining) and a warning icon when you cross the most critical one. Per-provider customization on Mac flows through transparently."),
                        String(
                            localized: "Push notification when you cross a warning threshold (not just at full depletion) — your iPhone now buzzes the moment you hit 50%, 20%, or whatever you've configured."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to 0.25.2 or later for the warning push. New providers work from 0.25.1."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.3",
            status: "",
            summary: String(
                localized: "Multi-account display fix on Cost and Subscription Utilization, plus a new cross-version account-link prompt with the related crash fix."),
            sections: [
                .init(
                    title: String(localized: "Recent updates"),
                    items: [
                        String(
                            localized: "Abacus AI and Mistral support — monthly usage and renewal countdown sync to your iPhone, with quota push notifications."),
                        String(
                            localized: "Claude Designs / Daily Routines / Web Sonnet usage bars on the Claude detail page; Cursor Extra budget gauge on the Cursor page."),
                        String(
                            localized: "Synthetic 5h / weekly tokens / search hourly labels render correctly instead of generic fallbacks."),
                        String(
                            localized: "Codex Pro $100 plan badge; estimated cost for newly-released models marked with *."),
                        String(
                            localized: "Two Macs on different CodexBar versions during a rolling upgrade now show a single card per account."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(localized: "Requires CodexBar for Mac 0.23.4 or later for the new providers."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.2",
            status: "",
            summary: String(
                localized: "Primarily resolves multiple Codex accounts failing to display fully on iPhone. After configuring multiple Codex accounts on Mac, iPhone now shows each account as a separate card; Cost, Usage, and Provider Share all attribute correctly per account."),
            sections: [
                .init(
                    title: String(localized: "Stability"),
                    items: [
                        String(
                            localized: "Added a real-data regression test suite covering all 27 providers to ensure sync stability across multi-account and multi-device scenarios."),
                    ]),
                .init(
                    title: String(localized: "Other fixes"),
                    items: [
                        String(
                            localized: "Some accounts (Claude / Ollama / Copilot etc.) being incorrectly hidden in specific scenarios."),
                        String(
                            localized: "Stale sync records left behind by previous Mac sessions persisting on iPhone."),
                        String(localized: "Cards being merged or lost in multi-account scenarios."),
                    ]),
                .init(
                    title: String(localized: "Required Mac version"),
                    items: [
                        String(localized: "Update Mac CodexBar to 0.23.6 for these changes to take effect."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.1",
            status: "",
            summary: String(
                localized: "Upstream v0.21–0.23 provider alignment — Abacus AI + Mistral as new providers, Claude Designs / Daily Routines / Web Sonnet bars, Cursor Extra usage, Synthetic 5h-weekly-search lanes. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Our GitHub repo was renamed from `o1xhack/CodexBar` to `o1xhack/CodexBar-Mobile` to differentiate from the upstream Mac repo. Existing download links keep working via redirect; nothing in your iCloud sync setup needs to change."),
                        String(
                            localized: "Update Mac CodexBar to **0.23.4 (Build 58.4.1.3.1) or later** for the new providers and accurate Cost numbers — earlier 0.23.x has a Codex parser bug. Download: [github.com/o1xhack/CodexBar-Mobile/releases](https://github.com/o1xhack/CodexBar-Mobile/releases)."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Abacus AI support — when you enable Abacus on Mac 0.23+, your iPhone shows the monthly compute-credit usage with billing-cycle countdown. Quota depleted / restored push notifications work like the other 25 providers."),
                        String(
                            localized: "Mistral support — monthly spend and renewal date sync to your iPhone. Push notifications fire on quota events."),
                        String(
                            localized: "Claude extras — Designs, Daily Routines, and Web Sonnet usage bars now appear on the Claude detail page when your account exposes those quotas via OAuth or the Web app."),
                        String(
                            localized: "Cursor Extra usage — on-demand budget gauge from Cursor's menu bar metric is now visible on the Cursor detail page when the budget is enabled."),
                        String(
                            localized: "Synthetic 3-lane labels — five-hour quota, weekly tokens, and search hourly are labeled correctly on the detail page instead of generic Session / Weekly fallback labels."),
                        String(
                            localized: "Codex Pro $100 plan badge — the new Pro $100 / prolite plan names from upstream v0.21 sync through and display in the account-info capsule on each Codex card."),
                        String(
                            localized: "Color palette extended — Abacus uses a warm brown tone, Mistral a vibrant red. Both stay distinct from existing provider colors across cards, charts, and the share image."),
                        String(
                            localized: "Estimated cost for newly-released models — when Mac sees a model name that isn't in its pricing table yet, it uses the closest known model's rate as a temporary estimate and marks the value with * on the Provider Detail cost card. Stops Daily Spend from quietly dropping to $0 the day a fresh model name appears."),
                        String(
                            localized: "Two Macs, one card — when your two Macs are on different CodexBar versions during a rolling upgrade, your iPhone now correctly shows a single card per account rather than duplicates. Works for accounts whose email contains non-ASCII characters (café@…) too."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(
                            localized: "Mac-side ghost-records cleanup — when you disable a provider on Mac or your Codex account identity changes after a Mac upgrade, the old CloudKit record is now actively deleted at the source. Combines with the iOS 1.3.1 display-time filter for double protection against stale cards."),
                        String(
                            localized: "27 providers / 54 push-subscription zones — the push-notification subscription set automatically expands on first launch to cover Abacus AI and Mistral alongside the existing 25 providers."),
                        String(
                            localized: "Wire-format unchanged — iOS 1.3.x users on the same iCloud account see the new providers as fallback cards (color-tinted) without crashing or missing data; existing 25 providers stay fully functional. iOS 1.5.0 adds the structured rendering for the new ones."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.5.0",
            status: "",
            summary: String(
                localized: "Upstream v0.21–0.23 provider alignment — Abacus AI + Mistral as new providers, Claude Designs / Daily Routines / Web Sonnet bars, Cursor Extra usage, Synthetic 5h-weekly-search lanes. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Update Mac CodexBar to **0.23.4 (Build 58.4.1.3.1) or later** for the new providers and accurate Cost numbers — earlier 0.23.x has a Codex parser bug. Download: [github.com/o1xhack/CodexBar-Mobile/releases](https://github.com/o1xhack/CodexBar-Mobile/releases)."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Abacus AI support — when you enable Abacus on Mac 0.23+, your iPhone shows the monthly compute-credit usage with billing-cycle countdown. Quota depleted / restored push notifications work like the other 25 providers."),
                        String(
                            localized: "Mistral support — monthly spend and renewal date sync to your iPhone. Push notifications fire on quota events."),
                        String(
                            localized: "Claude extras — Designs, Daily Routines, and Web Sonnet usage bars now appear on the Claude detail page when your account exposes those quotas via OAuth or the Web app."),
                        String(
                            localized: "Cursor Extra usage — on-demand budget gauge from Cursor's menu bar metric is now visible on the Cursor detail page when the budget is enabled."),
                        String(
                            localized: "Synthetic 3-lane labels — five-hour quota, weekly tokens, and search hourly are labeled correctly on the detail page instead of generic Session / Weekly fallback labels."),
                        String(
                            localized: "Codex Pro $100 plan badge — the new Pro $100 / prolite plan names from upstream v0.21 sync through and display in the account-info capsule on each Codex card."),
                        String(
                            localized: "Color palette extended — Abacus uses a warm brown tone, Mistral a vibrant red. Both stay distinct from existing provider colors across cards, charts, and the share image."),
                        String(
                            localized: "Estimated cost for newly-released models — when Mac sees a model name that isn't in its pricing table yet, it uses the closest known model's rate as a temporary estimate and marks the value with * on the Provider Detail cost card. Stops Daily Spend from quietly dropping to $0 the day a fresh model name appears."),
                        String(
                            localized: "Two Macs, one card — when your two Macs are on different CodexBar versions during a rolling upgrade, your iPhone now correctly shows a single card per account rather than duplicates. Works for accounts whose email contains non-ASCII characters (café@…) too."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(
                            localized: "Mac-side ghost-records cleanup — when you disable a provider on Mac or your Codex account identity changes after a Mac upgrade, the old CloudKit record is now actively deleted at the source. Combines with the iOS 1.3.1 display-time filter for double protection against stale cards."),
                        String(
                            localized: "27 providers / 54 push-subscription zones — the push-notification subscription set automatically expands on first launch to cover Abacus AI and Mistral alongside the existing 25 providers."),
                        String(
                            localized: "Wire-format unchanged — iOS 1.3.x users on the same iCloud account see the new providers as fallback cards (color-tinted) without crashing or missing data; existing 25 providers stay fully functional. iOS 1.5.0 adds the structured rendering for the new ones."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.3.0",
            status: "",
            summary: String(
                localized: "Upstream v0.20 provider alignment — Perplexity + OpenCode Go, Codex multi-account cards, SwiftData-backed local cache. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Update CodexBar on Mac to 0.20.3 (Build 55.3.1.3.0) or later to see Perplexity's structured credit breakdown (recurring / promo / purchased pools + Pro/Max plan + renewal countdown). Older Mac versions fall back to the legacy 3-bar rendering on the Perplexity detail page. Download from github.com/o1xhack/CodexBar-Mobile/releases."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Perplexity credit breakdown — when Mac 0.20.3+ is installed, the Perplexity detail page shows a stacked 3-segment bar for monthly / bonus / purchased credits, a Pro/Max plan badge, and a renewal-date countdown."),
                        String(
                            localized: "OpenCode Go support — separate provider from OpenCode Zen with its own tint (mint) and push subscriptions; cards are visually distinguishable at a glance even with both products enabled."),
                        String(
                            localized: "Codex multi-account cards — if you have 2+ Codex accounts (e.g. a personal Pro and a work Business account), each now renders as its own card with the email as the subtitle. Accounts without an email get a localized ordinal fallback (\"Codex 2\", etc.)."),
                        String(
                            localized: "Full push-notification coverage — quota depleted / restored pushes now work for Perplexity and OpenCode Go in addition to the 23 existing providers."),
                        String(
                            localized: "Provider color palette consolidated — every tab and card uses the same color for a given provider, so the Subscription Utilization chart, the provider list, the share card, and the detail page all agree."),
                    ]),
                .init(
                    title: String(localized: "Under the hood"),
                    items: [
                        String(
                            localized: "SwiftData-backed local cache — cold start time for Usage / Cost tabs reduced from 2-5 seconds to under 200 ms. Data persists across app relaunches instead of re-fetching from CloudKit every time."),
                        String(
                            localized: "Per-provider CloudKit records with zlib compression — removes the 1 MB-per-record hard cap that long-term users were approaching as their utilization history grew."),
                        String(
                            localized: "Push-driven incremental sync — Mac changes now land on iPhone within ~500 ms via CloudKit silent pushes instead of waiting for the next manual refresh."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.2.0",
            status: "",
            summary: String(localized: "Subscription Utilization, multi-Mac sync, and push notifications from Mac."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "You must update CodexBar on Mac to 0.19.0 (Build 54.1.2.0) or later to use this release. Subscription Utilization data collection and Mac→iOS push notifications both depend on Mac-side changes in that version. Download from github.com/o1xhack/CodexBar-Mobile/releases."),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Subscription Utilization visualization — see how much of each session / weekly / opus quota you're using, per provider and across all providers. 30-day daily bar chart in the Cost tab with Today / This Week / 14 Days / 30 Days summary cards, plus a utilization history chart on every provider detail page."),
                        String(
                            localized: "Multi-Mac data merge — if you run CodexBar on more than one Mac, data from all of them is deduped by hour and combined on iPhone, so your iPhone charts stay consistent regardless of which Mac was last active."),
                        String(
                            localized: "Push notifications from Mac — when a session quota hits 0% or becomes available again on any of your Macs, your iPhone receives a localized notification that includes the provider name (e.g. \"Codex session quota depleted\" / \"Codex 的会话额度已耗尽\"). Background App Refresh does not need to be enabled."),
                    ]),
                .init(
                    title: String(localized: "Improvements"),
                    items: [
                        String(
                            localized: "Settings and Developer Tools streamlined — Setup Guide promoted to the top of Settings; Push Diagnostic tool added under Developer Tools to inspect the Mac→iOS push chain; redundant How It Works sections removed."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.1.0",
            status: "",
            summary: String(localized: "Multi-device CloudKit sync. Requires updated Mac app."),
            sections: [
                .init(
                    title: String(localized: "Important"),
                    items: [
                        String(
                            localized: "Version 1.1.0 requires the latest CodexBar Mac app (0.18.0-mobile-1.1.0 or later) to unlock CloudKit sync. Download it from GitHub: github.com/o1xhack/CodexBar-Mobile/releases"),
                    ]),
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "CloudKit multi-device sync — data from multiple Macs is now merged on iPhone instead of last-write-wins."),
                        String(
                            localized: "New Sync Detail page in Settings — view sync status, connected devices, and detailed error info."),
                        String(
                            localized: "Raw Sync Data inspector — per-device unmerged data with daily cost breakdowns for debugging."),
                        String(
                            localized: "Specific CloudKit error messages — network, auth, quota issues now show exact cause instead of generic errors."),
                    ]),
                .init(
                    title: String(localized: "Improvements"),
                    items: [
                        String(localized: "Tab bar no longer hides when scrolling."),
                        String(localized: "Simplified sync status bar at the bottom of Usage and Cost tabs."),
                        String(localized: "Legacy KVS sync maintained as fallback for older Mac app versions."),
                    ]),
            ]),
        ReleaseNotesVersion(
            version: "1.0.0 (21)",
            status: "",
            summary: String(localized: "The first App Store release. Works with CodexBar on Mac."),
            sections: [
                .init(
                    title: String(localized: "What's New"),
                    items: [
                        String(
                            localized: "Share your AI spending as a beautiful image card — choose Classic or Vibe style, supports Today, 7 Days, and 30 Days, and adapts to dark mode."),
                        String(localized: "Usage percentages now stay crisp without blur on provider cards."),
                        String(localized: "Cost summaries and breakdown amounts remain sharp in tighter layouts."),
                        String(localized: "View AI coding tool usage on iPhone, synced from Mac via iCloud."),
                        String(
                            localized: "Provider cards with real-time rate limits, budget progress, and daily cost breakdowns."),
                        String(
                            localized: "Cost dashboard with provider share, model and service mix, and 30-day spend analysis."),
                        String(
                            localized: "Interactive charts with Bar and Line styles, press-and-hold inspection, and horizontal scrolling for history."),
                        String(localized: "Supports English, Simplified Chinese, Traditional Chinese, and Japanese."),
                        String(localized: "Liquid Glass design, demo mode, onboarding guide, and pull-to-refresh."),
                    ]),
                .init(
                    title: String(localized: "Improvements & Fixes"),
                    items: [
                        String(localized: "Percentage and cost labels are now sharper and easier to read."),
                        String(localized: "Toggle between used and remaining quota display in Settings."),
                        String(localized: "Smarter chart axis scaling with clean integer tick marks."),
                        String(localized: "Improved iCloud sync reliability and error reporting."),
                    ]),
            ]),
    ]
}

private struct ReleaseNotesView: View {
    private let versions = MobileReleaseNotesCatalog.versions

    private var latestVersion: ReleaseNotesVersion? {
        self.versions.first
    }

    private var historicalVersions: ArraySlice<ReleaseNotesVersion> {
        self.versions.dropFirst()
    }

    var body: some View {
        List {
            if let latestVersion = self.latestVersion {
                Section("Latest") {
                    ReleaseNotesCard(version: latestVersion)
                }
            }

            Section("History") {
                if self.historicalVersions.isEmpty {
                    Text("Older iOS release notes will appear here as new versions ship.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(self.historicalVersions)) { version in
                        DisclosureGroup {
                            ReleaseNotesContent(version: version)
                                .padding(.top, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("\(String(localized: "Version")) \(version.version)")
                                        .fontWeight(.semibold)
                                    ReleaseNotesBadge(title: version.status)
                                }

                                Text(version.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Release Notes")
    }
}

private struct ReleaseNotesCard: View {
    let version: ReleaseNotesVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(localized: "Version")) \(self.version.version)")
                        .font(.headline)
                    Text(self.version.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ReleaseNotesBadge(title: self.version.status)
            }

            ReleaseNotesContent(version: self.version)
        }
        .padding(.vertical, 8)
    }
}

private struct ReleaseNotesContent: View {
    let version: ReleaseNotesVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(self.version.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 7)

                                // Use LocalizedStringKey init so markdown
                                // (specifically `[label](url)` links) renders
                                // as tappable, with bold / italic also
                                // honored. Existing items without markdown
                                // syntax continue to render as plain text.
                                Text(.init(item))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .tint(.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ReleaseNotesBadge: View {
    let title: String

    var body: some View {
        Text(self.title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.12), in: Capsule())
    }
}

private struct UsageSettingsView: View {
    @AppStorage(MobileSettingsKeys.usageCostChartStyle) private var usageCostChartStyleRawValue = CostChartStyle.bars
        .rawValue
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode
            .remaining.rawValue
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false
    @AppStorage(MobileSettingsKeys.hideQuotaWarningMarkers) private var hideQuotaWarningMarkers = false
    @AppStorage(MobileSettingsKeys.showProviderChangelogLinks) private var showProviderChangelogLinks = false

    var body: some View {
        List {
            Section {
                Toggle("Show remaining usage", isOn: self.$showRemainingUsage)
                    .toggleStyle(.switch)
                    .font(.body)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("show-remaining-usage-toggle")
            } header: {
                Text("Usage")
            } footer: {
                Text("Display the quota you have left instead of the quota you have used on usage cards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Chart Style", selection: self.usageChartStyle) {
                    ForEach(CostChartStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Charts")
            } footer: {
                Text("Press and hold on the chart to inspect the exact value for a given day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: self.$hideQuotaWarningMarkers) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("setting_hide_quota_markers_title")
                        Text("setting_hide_quota_markers_subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("hide-quota-warning-markers-toggle")
                Toggle(isOn: self.$showProviderChangelogLinks) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("setting_show_changelog_links_title")
                        Text("setting_show_changelog_links_subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("show-provider-changelog-links-toggle")
            } header: {
                Text("setting_section_warnings_links")
            }

            Section {
                Toggle(isOn: self.$hidePersonalInfo) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide personal information")
                        Text("Obscure email addresses in the Usage page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Usage Setting")
        .listStyle(.insetGrouped)
    }

    private var usageChartStyle: Binding<CostChartStyle> {
        Binding(
            get: { CostChartStyle(rawValue: self.usageCostChartStyleRawValue) ?? .bars },
            set: { self.usageCostChartStyleRawValue = $0.rawValue })
    }
}

private struct CostSettingsView: View {
    @AppStorage(MobileSettingsKeys.dashboardCostChartStyle) private var dashboardCostChartStyleRawValue =
        CostChartStyle.line.rawValue
    @AppStorage(MobileSettingsKeys.openCostByDefault) private var openCostByDefault = false

    // Round 6 / P4b — Cost Window Ledger controls.
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MobileSettingsKeys.cwlEnabled) private var cwlEnabled = MobileSettingsDefaults.cwlEnabled
    @AppStorage(MobileSettingsKeys.cwlWindowDays) private var cwlWindowDays = MobileSettingsDefaults.cwlWindowDays
    @State private var showClearLedgerConfirm = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: self.$cwlEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local cost history")
                        Text("Off uses the latest synced Mac snapshots and the Mac history window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            "On keeps synced daily cost points on this iPhone for the selected window. It still requires Mac sync and never reads Mac logs directly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if self.cwlEnabled {
                    Picker("History window", selection: self.$cwlWindowDays) {
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                        Text("365 Days").tag(365)
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Cost History")
            }

            if self.cwlEnabled {
                if let diagnostics = self.ledgerDiagnostics, diagnostics.rowCount > 0 {
                    Section("Local Ledger") {
                        LabeledContent("Days collected", value: "\(diagnostics.dayCount)")
                        LabeledContent("Providers", value: "\(diagnostics.providerCount)")
                        if diagnostics.deviceCount > 1 {
                            LabeledContent("Devices", value: "\(diagnostics.deviceCount)")
                        }
                        if let earliest = diagnostics.earliestDayKey {
                            LabeledContent("Since", value: earliest)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        self.showClearLedgerConfirm = true
                    } label: {
                        Text("Clear local cost history")
                    }
                    .confirmationDialog(
                        Text("Clear local cost history?"),
                        isPresented: self.$showClearLedgerConfirm,
                        titleVisibility: .visible)
                    {
                        Button("Clear", role: .destructive) {
                            try? CostLedgerService.clearAll(in: self.modelContext)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "Deletes the on-device cost ledger only. Synced data is unaffected; history rebuilds as the Mac keeps syncing.")
                    }
                }
            }

            Section("Charts") {
                Picker("Chart Style", selection: self.dashboardChartStyle) {
                    ForEach(CostChartStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle(isOn: self.$openCostByDefault) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Cost by default")
                        Text("Launch the app on the Cost tab next time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Press and hold on the chart to inspect the exact value for a given day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cost Setting")
        .onChange(of: self.cwlEnabled) { _, isOn in
            // First enable: import the existing blob history into the ledger so
            // the dashboard has data immediately instead of waiting for the next
            // Mac sync. If the user previously cleared local history, keep that
            // clear boundary so re-enabling does not restore older blob data. On
            // failure, revert the toggle (CWL stays off, blob path keeps working).
            // Idempotent — re-enabling is a cheap no-op.
            guard isOn else { return }
            do {
                try CostLedgerService.seedFromExistingBlobsRespectingClearTombstone(
                    in: self.modelContext)
            } catch {
                self.cwlEnabled = false
            }
        }
    }

    /// Read-on-render ledger diagnostics for the Settings panel. O(rows);
    /// fine for a settings screen. `try?` → nil on any read error (panel hides).
    private var ledgerDiagnostics: CostLedgerDiagnostics? {
        try? CostLedgerService.diagnostics(in: self.modelContext)
    }

    private var dashboardChartStyle: Binding<CostChartStyle> {
        Binding(
            get: { CostChartStyle(rawValue: self.dashboardCostChartStyleRawValue) ?? .line },
            set: { self.dashboardCostChartStyleRawValue = $0.rawValue })
    }
}

private struct WidgetSettingsView: View {
    let usageData: SyncedUsageData

    @State private var selectedFamily = CodexBarWidgetPreviewFamily.medium
    @State private var selectedColorStyle = CodexBarWidgetColorStyle.mono

    private let modes: [CodexBarWidgetMode] = [
        .overview,
        .todayCost,
        .providerFocus,
        .syncHealth,
    ]

    var body: some View {
        List {
            Section {
                Picker(String(localized: "Widget Size"), selection: self.$selectedFamily) {
                    ForEach(self.availableFamilies) { family in
                        Text(family.title).tag(family)
                    }
                }
                .pickerStyle(.segmented)

                Picker(String(localized: "Color Style"), selection: self.$selectedColorStyle) {
                    ForEach(CodexBarWidgetColorStyle.allCases, id: \.rawValue) { colorStyle in
                        Text(colorStyle.previewTitle).tag(colorStyle)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: self.selectedFamily.gallerySpacing) {
                    ForEach(self.modes, id: \.rawValue) { mode in
                        WidgetPreviewFrame(
                            family: self.selectedFamily,
                            mode: mode,
                            colorStyle: self.selectedColorStyle,
                            snapshot: self.previewSnapshot)
                    }
                }
                .animation(.snappy(duration: 0.22), value: self.selectedFamily)
                .animation(.snappy(duration: 0.22), value: self.selectedColorStyle)
                .accessibilityIdentifier(
                    "widget-preview-gallery-\(self.selectedFamily.rawValue)-\(self.selectedColorStyle.rawValue)")
            } header: {
                Text("Preview")
            }
        }
        .navigationTitle("Widget Setting")
        .listStyle(.insetGrouped)
    }

    private var availableFamilies: [CodexBarWidgetPreviewFamily] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [.small, .medium, .large, .extraLarge]
        }
        return [.small, .medium, .large]
    }

    private var previewSnapshot: CodexBarWidgetSnapshot {
        guard let snapshot = self.usageData.snapshot else {
            return .placeholder()
        }
        let widgetSnapshot = CodexBarWidgetSnapshotBuilder.makeSnapshot(
            from: [snapshot],
            now: .now)
        return widgetSnapshot.state == .loaded ? widgetSnapshot : .placeholder()
    }
}

private struct WidgetPreviewFrame: View {
    let family: CodexBarWidgetPreviewFamily
    let mode: CodexBarWidgetMode
    let colorStyle: CodexBarWidgetColorStyle
    let snapshot: CodexBarWidgetSnapshot

    var body: some View {
        GeometryReader { proxy in
            let size = self.family.previewSize(maxWidth: proxy.size.width)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    Text(self.mode.previewTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    CodexBarWidgetView(
                        entry: CodexBarWidgetEntry(
                            date: .now,
                            configuration: CodexBarWidgetConfigurationIntent(
                                mode: self.mode,
                                colorStyle: self.colorStyle),
                            snapshot: self.snapshot),
                        previewFamily: self.family.widgetFamily)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: self.family.cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: self.family.cornerRadius, style: .continuous)
                                .stroke(.separator.opacity(0.42), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                        .accessibilityIdentifier(
                            "widget-preview-\(self.family.rawValue)-\(self.mode.rawValue)-\(self.colorStyle.rawValue)")
                }
                .frame(width: size.width, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: self.family.frameHeight)
    }
}

private enum CodexBarWidgetPreviewFamily: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String {
        self.rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "iPad XL"
        }
    }

    var widgetFamily: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        case .extraLarge: .systemExtraLarge
        }
    }

    var gallerySpacing: CGFloat {
        switch self {
        case .small: 16
        case .medium: 18
        case .large: 20
        case .extraLarge: 18
        }
    }

    var frameHeight: CGFloat {
        switch self {
        case .small: 196
        case .medium: 190
        case .large: 382
        case .extraLarge: 306
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: 24
        case .medium: 26
        case .large: 28
        case .extraLarge: 30
        }
    }

    func previewSize(maxWidth: CGFloat) -> CGSize {
        let available = max(140, maxWidth - 8)
        switch self {
        case .small:
            let side = min(162, available)
            return CGSize(width: side, height: side)
        case .medium:
            let width = min(338, available)
            return CGSize(width: width, height: width / 2.08)
        case .large:
            let width = min(338, available)
            return CGSize(width: width, height: width * 1.04)
        case .extraLarge:
            let width = min(560, available)
            return CGSize(width: width, height: width / 2.05)
        }
    }
}

extension CodexBarWidgetMode {
    fileprivate var previewTitle: LocalizedStringResource {
        switch self {
        case .overview: "Overview"
        case .providerFocus: "Provider Focus"
        case .todayCost: "Today Cost"
        case .syncHealth: "Sync Health"
        }
    }
}

extension CodexBarWidgetColorStyle {
    fileprivate var previewTitle: LocalizedStringResource {
        switch self {
        case .mono: "Mono"
        case .colorful: "Colorful"
        }
    }
}

// MARK: - Previews

#Preview("With Data") {
    ContentView(usageData: PreviewData.makeSyncedUsageData())
}

#Preview("Empty State") {
    ContentView(usageData: PreviewData.makeEmptyUsageData())
}
