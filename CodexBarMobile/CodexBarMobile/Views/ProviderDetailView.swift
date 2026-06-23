import Charts
import CodexBarSync
import SwiftUI

struct ProviderDetailView: View {
    /// All accounts for the provider whose row the user tapped. When
    /// `group.hasMultipleAccounts`, a segmented control at the top of
    /// the body switches between accounts and the rest of the view
    /// re-renders against the selected snapshot — mirroring Mac's
    /// "click into provider menu → tabs" UX.
    let group: ProviderAccountGroup

    @State private var selectedAccountIndex: Int = 0

    @AppStorage(MobileSettingsKeys.usageCostChartStyle) private var chartStyleRawValue = CostChartStyle.bars.rawValue
    @State private var selectedDate: String?

    /// Single-account convenience init — used by call sites that
    /// haven't been refactored to pass a group yet (e.g., `RawProviderDetailView`
    /// in `ContentView`, SwiftUI previews). Wraps the snapshot in a
    /// 1-element group so the body code path is uniform.
    init(provider: ProviderUsageSnapshot) {
        self.group = ProviderAccountGroup(
            providerID: provider.providerID,
            providerName: provider.providerName,
            accounts: [provider])
    }

    /// Multi-account init — preferred path from the post-merge,
    /// post-grouping Usage list.
    init(group: ProviderAccountGroup) {
        self.group = group
    }

    /// Computed accessor for the currently-selected snapshot. **All
    /// downstream rendering code references `self.provider`** — this
    /// computed property is the only thing that changes when the user
    /// taps a different tab. Keeps the body code identical to the
    /// pre-refactor single-account version.
    private var provider: ProviderUsageSnapshot {
        guard self.group.accounts.indices.contains(self.selectedAccountIndex) else {
            return self.group.accounts[0]
        }
        return self.group.accounts[self.selectedAccountIndex]
    }

    private var chartStyle: CostChartStyle {
        CostChartStyle(rawValue: self.chartStyleRawValue) ?? .bars
    }

    /// True when the displayed provider holds synthetic mock data.
    /// Drives the MOCK badge in the nav header.
    private var isMockProvider: Bool {
        MockProviderDetector.isMock(self.provider)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if self.group.hasMultipleAccounts {
                    self.accountTabBar
                }
                if self.isMockProvider {
                    self.mockBanner
                }

                // Rate limit cards (or Perplexity credit breakdown when available)
                self.primaryUsageSection

                // v0.26 dedicated cards — dispatched by providerID +
                // typed envelope field. iOS 1.7.0 fold-in. Each card
                // is only rendered when both the providerID matches
                // AND the snapshot carries its typed payload; missing
                // data falls through silently to the generic sections
                // below.
                if self.provider.providerID == "kiro",
                   let kiroCredits = self.provider.kiroCredits
                {
                    KiroCreditsCard(credits: kiroCredits, tintColor: self.providerColor)
                }
                if self.provider.providerID == "bedrock",
                   let bedrockCost = self.provider.bedrockCost
                {
                    BedrockCostCard(cost: bedrockCost, tintColor: self.providerColor)
                }
                if self.provider.providerID == "moonshot",
                   let moonshotBalance = self.provider.moonshotBalance
                {
                    MoonshotBalanceCard(balance: moonshotBalance, tintColor: self.providerColor)
                }
                if self.provider.providerID == "zai",
                   let zaiHourly = self.provider.zaiHourlyUsage
                {
                    ZaiHourlyChart(usage: zaiHourly, tintColor: self.providerColor)
                }
                if self.provider.providerID == "openai",
                   let openAIDashboard = self.provider.openAIAPIDashboard
                {
                    OpenAIDashboardSection(dashboard: openAIDashboard, tintColor: self.providerColor)
                }
                if self.provider.providerID == "antigravity",
                   let antigravityAccounts = self.provider.antigravityAccounts,
                   antigravityAccounts.accounts.count > 1
                {
                    AntigravityAccountSwitcher(accounts: antigravityAccounts, tintColor: self.providerColor)
                }

                // iOS 1.8.0 — v0.27 dedicated cards. Same dispatch
                // pattern as v0.26: provider ID match + envelope field
                // present. Falls through silently to the generic card
                // list when Mac is on a pre-0.27.0 build (envelope
                // fields stay nil).
                if self.provider.providerID == "grok",
                   let grokBilling = self.provider.grokBilling
                {
                    GrokBillingCard(billing: grokBilling, tintColor: self.providerColor)
                }
                if self.provider.providerID == "elevenlabs",
                   let elevenLabsCredits = self.provider.elevenLabsCredits
                {
                    ElevenLabsCreditsCard(credits: elevenLabsCredits, tintColor: self.providerColor)
                }
                if self.provider.providerID == "deepgram",
                   let deepgramUsage = self.provider.deepgramUsage
                {
                    DeepgramUsageCard(usage: deepgramUsage, tintColor: self.providerColor)
                }
                if self.provider.providerID == "groq",
                   let groqMetrics = self.provider.groqMetrics
                {
                    GroqMetricsCard(metrics: groqMetrics, tintColor: self.providerColor)
                }
                if self.provider.providerID == "llmproxy",
                   let llmProxyStats = self.provider.llmProxyStats
                {
                    LLMProxyStatsCard(stats: llmProxyStats, tintColor: self.providerColor)
                }
                // iOS 1.9.0 — parity gap D: OpenRouter balance / credits / usage.
                if self.provider.providerID == "openrouter",
                   let openRouterStats = self.provider.openRouterStats
                {
                    OpenRouterStatsCard(stats: openRouterStats, tintColor: self.providerColor)
                }
                // iOS 1.9.0 — parity gap E: Azure OpenAI deployment info.
                if self.provider.providerID == "azureopenai",
                   let azureInfo = self.provider.azureOpenAIInfo
                {
                    AzureOpenAIInfoCard(info: azureInfo, tintColor: self.providerColor)
                }
                // iOS 1.9.0 — parity gap G: Alibaba Token Plan (Bailian) credits.
                if self.provider.providerID == "alibabatokenplan",
                   let alibabaPlan = self.provider.alibabaTokenPlan
                {
                    AlibabaTokenPlanCard(plan: alibabaPlan, tintColor: self.providerColor)
                }
                // iOS 1.10.0 — DeepSeek web-session usage + cost (v0.30.0 #1166).
                if self.provider.providerID == "deepseek",
                   let deepSeekUsage = self.provider.deepSeekUsage
                {
                    DeepSeekUsageCard(usage: deepSeekUsage, tintColor: self.providerColor)
                }

                // iOS 1.8.0 build 134 — v0.27 existing-provider
                // extensions. Same dispatch pattern: provider ID
                // match + envelope field present.
                if self.provider.providerID == "claude",
                   let claudeAdmin = self.provider.claudeAdminUsage
                {
                    ClaudeAdminUsageCard(usage: claudeAdmin, tintColor: self.providerColor)
                }
                if self.provider.providerID == "claude",
                   let claudeExtra = self.provider.claudeExtraUsage
                {
                    ClaudeExtraUsageCard(extraUsage: claudeExtra, tintColor: self.providerColor)
                }
                if self.provider.providerID == "opencodego",
                   let zenBalance = self.provider.openCodeGoZenBalance
                {
                    OpenCodeGoZenBalanceCard(balance: zenBalance, tintColor: self.providerColor)
                }
                if self.provider.providerID == "minimax",
                   let minimaxBilling = self.provider.minimaxBilling
                {
                    MiniMaxBillingCard(billing: minimaxBilling, tintColor: self.providerColor)
                }
                if self.provider.providerID == "codex",
                   let codexWorkspace = self.provider.codexWorkspace,
                   (codexWorkspace.workspaceName?.isEmpty == false || codexWorkspace.weeklyPaceLabel?.isEmpty == false)
                {
                    CodexWorkspaceBadge(context: codexWorkspace, tintColor: self.providerColor)
                }
                if self.provider.providerID == "codex",
                   let resetCredits = self.provider.codexResetCredits,
                   resetCredits.availableCount > 0
                {
                    CodexResetCreditsCard(resetCredits: resetCredits, tintColor: self.providerColor)
                }
                if self.provider.providerID == "codex",
                   let confidence = self.provider.usageDataConfidence,
                   UsageDataConfidenceNotice.shouldRender(confidence)
                {
                    UsageDataConfidenceNotice(rawValue: confidence, tintColor: self.providerColor)
                }

                // Claude peak-hours indicator (Anthropic peak window
                // 8am-2pm America/New_York, weekdays). Pure time-of-day
                // logic in `ClaudePeakHours` — no wire field involved.
                if self.provider.providerID == "claude" {
                    self.claudePeakHoursSection
                }

                // Cost summary grid
                if let cost = self.provider.costSummary,
                   cost.sessionCostUSD != nil || cost.last30DaysCostUSD != nil
                {
                    self.costSummarySection(cost)
                }

                // Budget progress
                if let budget = self.provider.budget {
                    BudgetProgressView(budget: budget, tintColor: self.providerColor)
                }

                // Utilization history chart
                if let history = self.provider.utilizationHistory, !history.isEmpty {
                    UtilizationHistoryView(series: history, tintColor: self.providerColor)
                }

                // Daily chart
                if let cost = self.provider.costSummary, !cost.daily.isEmpty {
                    self.dailyChartSection(cost.daily, currencyCode: cost.currencyCode)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(self.provider.providerName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if self.isMockProvider {
                ToolbarItem(placement: .topBarTrailing) {
                    MockBadgeView()
                }
            }
        }
    }

    // MARK: - Mock Detail Banner

    /// Inline banner at the top of the detail page reminding the user
    /// Segmented control at the top of the detail view — one tab per
    /// account in `group`. Mirrors Mac's per-provider account tabs
    /// (e.g., OpenAI menu card showing `admin-msxiao113 / admin-outlook`).
    /// Resets `selectedDate` (daily-chart hover state) on tab switch so
    /// the chart hover from one account doesn't bleed into another.
    private var accountTabBar: some View {
        Picker(
            selection: Binding(
                get: { self.selectedAccountIndex },
                set: { newIndex in
                    self.selectedAccountIndex = newIndex
                    self.selectedDate = nil
                }),
            label: Text(""))
        {
            ForEach(self.group.accounts.indices, id: \.self) { index in
                Text(self.group.tabLabel(forIndex: index))
                    .tag(index)
                    .accessibilityIdentifier(
                        self.group.tabAccessibilityIdentifier(forIndex: index))
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("provider-account-tab-bar-\(self.group.providerID)")
    }

    /// this provider's data is synthetic. Mirrors the global
    /// `MockProviderBanner` in spirit (so users hitting the detail page
    /// directly without seeing the global banner still understand) but
    /// scoped to this single provider.
    @ViewBuilder
    private var mockBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "testtube.2")
                .font(.subheadline.bold())
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("This is mock data")
                    .font(.caption.bold())
                Text("Synthetic provider injected by Mac for testing. Real numbers are restored ~30s after Mac toggles mock off.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.purple.opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.30), lineWidth: 1))
    }

    // MARK: - Claude Peak Hours

    /// Displays Anthropic's Claude peak window status for the current
    /// moment. Pure client-side computation in `ClaudePeakHours`
    /// (mirrors the Mac-side logic byte-for-byte; both sides use the
    /// same hardcoded window: 8am–2pm America/New_York, weekdays).
    /// Visible on the Claude provider detail page only; other providers
    /// don't render this section.
    @ViewBuilder
    private var claudePeakHoursSection: some View {
        let status = ClaudePeakHours.status(at: Date())
        HStack(spacing: 10) {
            Image(systemName: status.isPeak ? "sun.max.fill" : "moon.fill")
                .font(.subheadline)
                .foregroundStyle(status.isPeak ? .orange : .secondary)
            Text(status.label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Primary usage section

    /// Chooses between a specialized provider card and the generic
    /// rate-window list. When a typed envelope card claims the primary
    /// real estate (Perplexity, Kiro, Bedrock, Moonshot), we skip the
    /// generic list to avoid double-rendering the same data.
    @ViewBuilder
    private var primaryUsageSection: some View {
        if self.provider.providerID == "perplexity",
           let credits = self.provider.perplexityCredits
        {
            PerplexityCreditsCard(credits: credits, tintColor: self.providerColor)
        } else if self.providerHasDedicatedPrimaryCard {
            // The dedicated card is rendered below in the body; skip
            // the generic rate-window list so the page isn't redundant.
            EmptyView()
        } else {
            self.rateLimitSection
        }
    }

    private var providerHasDedicatedPrimaryCard: Bool {
        switch self.provider.providerID {
        case "kiro" where self.provider.kiroCredits != nil:
            true
        case "bedrock" where self.provider.bedrockCost != nil:
            true
        case "moonshot" where self.provider.moonshotBalance != nil:
            true
        default:
            false
        }
    }

    // MARK: - Rate Limits

    @ViewBuilder
    private var rateLimitSection: some View {
        let windows = self.provider.allRateWindows
        if !windows.isEmpty {
            VStack(spacing: 12) {
                ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                    let warning = self.provider.quotaWarning(forWindowIndex: index)
                    UsageCardView(
                        label: window.label ?? self.defaultLabel(at: index),
                        window: window,
                        tintColor: self.providerColor,
                        percentageAccessibilityIdentifier: "provider-detail-percent-\(self.provider.providerID)-\(index)",
                        quotaWarningThresholds: warning.thresholds,
                        quotaWarningsEnabled: warning.enabled)
                }
            }
        }
    }

    // MARK: - Cost Summary

    private func costSummarySection(_ cost: SyncCostSummary) -> some View {
        // Prefer daily[today] over sessionCostUSD so the "Today" card here
        // matches what the Cost-tab summary card shows for this provider.
        // See `SyncCostSummary+Today.swift` for reasoning. Cost + tokens
        // are resolved through one `todayTotals()` call so they can't
        // straddle midnight with mismatched day keys.
        let today = cost.todayTotals()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cost & Usage")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let todayCost = today.costUSD {
                    CostMetricCard(
                        title: "Today",
                        value: CostFormatting.cost(todayCost, currencyCode: cost.currencyCode),
                        subtitle: today.tokens.map { Self.formatTokens($0) },
                        tintColor: self.providerColor,
                        isEstimated: today.isEstimated == true)
                }
                if let monthCost = cost.last30DaysCostUSD {
                    CostMetricCard(
                        // Reflect the Mac's configurable 1–365 day window (gap F)
                        // instead of a hardcoded "30 Days"; nil/30 → "30 Days".
                        title: cost.historyDays.flatMap {
                            $0 == 30 ? nil : LocalizedStringResource("\($0) Days")
                        } ?? "30 Days",
                        value: CostFormatting.cost(monthCost, currencyCode: cost.currencyCode),
                        subtitle: Self.costSubtitle(
                            tokens: cost.last30DaysTokens,
                            requests: cost.last30DaysRequests),
                        tintColor: self.providerColor,
                        isEstimated: cost.isEstimated == true)
                }
            }

            if today.isEstimated == true || cost.isEstimated == true {
                Text("* Estimated cost · auto-corrects after Mac upgrades to the latest pricing table")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Daily Chart

    private func dailyChartSection(_ daily: [SyncDailyPoint], currencyCode: String?) -> some View {
        let sortedDaily = Self.sortedDailyPoints(daily)
        let xAxisDayKeys = Self.dailyAxisDayKeys(for: sortedDaily)
        // Precompute axis values once per section build. `daily` is stable across
        // `selectedDate` hover changes, so pulling this out of the `.chartYAxis`
        // closure eliminates redundant axis recomputation on every chart re-render.
        let yAxisValues = MobileChartAxisFormatter.axisValues(for: sortedDaily.map(\.costUSD))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Daily Spend")
                    .font(.headline)
                Text("(\(currencyCode ?? "USD"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("provider-daily-spend-title")

            Chart(sortedDaily, id: \.dayKey) { point in
                switch self.chartStyle {
                case .bars:
                    BarMark(
                        x: .value(String(localized: "Date"), point.dayKey),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor.gradient)
                        .cornerRadius(3)
                case .line:
                    AreaMark(
                        x: .value(String(localized: "Date"), point.dayKey),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor.opacity(0.16))
                        .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value(String(localized: "Date"), point.dayKey),
                        y: .value(String(localized: "Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor)
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }

                if self.selectedDate == point.dayKey {
                    RuleMark(x: .value(String(localized: "Selected Date"), point.dayKey))
                        .foregroundStyle(self.providerColor.opacity(0.3))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value(String(localized: "Selected Date"), point.dayKey),
                        y: .value(String(localized: "Selected Cost"), point.costUSD))
                        .foregroundStyle(self.providerColor)
                        .symbolSize(80)
                }
            }
            .chartXSelection(value: self.$selectedDate)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: min(sortedDaily.count, Self.chartVisibleDays))
            .chartScrollPosition(initialX: Self.chartScrollInitialDayKey(daily: sortedDaily))
            .chartXAxis {
                AxisMarks(values: xAxisDayKeys) { value in
                    AxisGridLine()
                    AxisValueLabel(anchor: .top) {
                        if let dayKey = value.as(String.self) {
                            Text(Self.dailyAxisLabel(for: dayKey))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: yAxisValues) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(MobileChartAxisFormatter.axisLabel(for: v))
                                .font(.caption2)
                        }
                    }
                }
            }
            // 200pt chart height — tuned so the Daily Spend chart fits below
            // the primary-usage / cost-summary / budget sections without
            // pushing the provider's utilization history off-screen on a
            // compact iPhone (iPhone SE 3rd gen, 667pt total height). A
            // taller chart improves readability for outliers but requires
            // the user to scroll more; 200pt is the empirically-tuned
            // balance. If increasing this, verify the page still works on
            // the smallest supported device.
            .frame(height: 200)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let selectedDate, let point = sortedDaily.first(where: { $0.dayKey == selectedDate }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(point.dayKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CostFormatting.cost(point.costUSD, currencyCode: currencyCode))
                            .font(.caption.monospacedDigit())
                            .fontWeight(.medium)
                        Text("· \(Self.formatTokens(point.totalTokens))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Codex standard/fast spend split for the selected day — the
                    // iOS mirror of the Mac cost-history "Std / Fast" hover detail
                    // (upstream #1070). Nil for non-Codex / pre-0.29 days.
                    if let split = CodexCostSplit.subtitle(summing: point.modelBreakdowns) {
                        Text(split)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Chart Constants

    static let chartVisibleDays = 30

    static func sortedDailyPoints(_ daily: [SyncDailyPoint]) -> [SyncDailyPoint] {
        daily.sorted { $0.dayKey < $1.dayKey }
    }

    static func dailyAxisDayKeys(for daily: [SyncDailyPoint]) -> [String] {
        Self.sortedDailyPoints(daily).enumerated().compactMap { index, point in
            index.isMultiple(of: 7) ? point.dayKey : nil
        }
    }

    static func dailyAxisLabel(for dayKey: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar(identifier: .gregorian)
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dayKey) else {
            return dayKey
        }

        let outputFormatter = DateFormatter()
        outputFormatter.calendar = Calendar(identifier: .gregorian)
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")
        outputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        outputFormatter.dateFormat = "M/d"
        return outputFormatter.string(from: date)
    }

    static func chartScrollInitialDayKey(daily: [SyncDailyPoint]) -> String {
        let startIndex = max(0, daily.count - chartVisibleDays)
        return daily[startIndex].dayKey
    }

    // MARK: - Helpers

    private var providerColor: Color {
        ProviderColorPalette.color(for: self.provider.providerID)
    }

    private func defaultLabel(at index: Int) -> String {
        switch index {
        case 0: String(localized: "Session")
        case 1: String(localized: "Weekly")
        default: "\(String(localized: "Limit")) \(index + 1)"
        }
    }

    static func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }
    static func formatTokens(_ count: Int) -> String { CostFormatting.tokens(count) }

    /// Cost-card subtitle combining the token count with an optional request
    /// count (upstream #1163; nil for providers/Mac builds without it).
    static func costSubtitle(tokens: Int?, requests: Int?) -> String? {
        var parts: [String] = []
        if let tokens { parts.append(Self.formatTokens(tokens)) }
        if let requests, requests > 0 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            let n = f.string(from: NSNumber(value: requests)) ?? "\(requests)"
            parts.append(String(format: String(localized: "cost_requests_inline", defaultValue: "%@ req"), n))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Previews

#Preview("With Cost Data") {
    NavigationStack {
        ProviderDetailView(provider: PreviewData.claudeProvider)
    }
}

#Preview("No Cost Data") {
    NavigationStack {
        ProviderDetailView(provider: PreviewData.cursorProvider)
    }
}
