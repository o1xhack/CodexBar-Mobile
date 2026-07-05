import Foundation

/// A single rate-limit window snapshot for iCloud sync.
public struct SyncRateWindow: Codable, Sendable, Equatable {
    public let label: String?
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }

    public init(
        label: String? = nil,
        usedPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        resetDescription: String?)
    {
        self.label = label
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        self.windowMinutes = try container.decodeIfPresent(Int.self, forKey: .windowMinutes)
        self.resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        self.resetDescription = try container.decodeIfPresent(String.self, forKey: .resetDescription)
    }
}

/// A single day's cost/token data point for iCloud sync.
public struct SyncCostBreakdown: Codable, Sendable, Equatable {
    public let label: String
    public let costUSD: Double
    /// `true` when the cost was computed from a fallback pricing row
    /// (model name not in the local pricing table). `nil` for payloads
    /// from Mac builds before 0.23 — iOS treats nil as `false` (not
    /// estimated) so old data renders cleanly. See
    /// `Research/018-model-fallback-pricing.md` §6.
    public let isEstimated: Bool?
    /// Codex standard (non-priority) spend within this model/day, split out
    /// from `costUSD` (upstream v0.29.0 #1070). Optional — `nil` for
    /// non-Codex providers and for Mac builds before 0.29.0 that didn't
    /// split standard vs fast. Synthesized `Codable` decodes a missing key
    /// as `nil`, so old payloads stay wire-compatible. iOS renders the
    /// "Std / Fast" sub-line only when at least one split field is present.
    public let standardCostUSD: Double?
    /// Codex fast / priority-tier spend within this model/day.
    public let priorityCostUSD: Double?
    /// Codex standard-tier tokens for this model/day.
    public let standardTokens: Int?
    /// Codex fast / priority-tier tokens for this model/day.
    public let priorityTokens: Int?

    public init(
        label: String,
        costUSD: Double,
        isEstimated: Bool? = nil,
        standardCostUSD: Double? = nil,
        priorityCostUSD: Double? = nil,
        standardTokens: Int? = nil,
        priorityTokens: Int? = nil)
    {
        self.label = label
        self.costUSD = costUSD
        self.isEstimated = isEstimated
        self.standardCostUSD = standardCostUSD
        self.priorityCostUSD = priorityCostUSD
        self.standardTokens = standardTokens
        self.priorityTokens = priorityTokens
    }
}

/// A single day's cost/token data point for iCloud sync.
public struct SyncDailyPoint: Codable, Sendable, Equatable {
    public let dayKey: String
    public let costUSD: Double
    public let totalTokens: Int
    public let modelBreakdowns: [SyncCostBreakdown]
    public let serviceBreakdowns: [SyncCostBreakdown]
    /// Day-level OR aggregate of `modelBreakdowns[*].isEstimated`. `nil`
    /// for payloads from Mac builds before 0.23 — iOS treats nil as
    /// `false` (not estimated). See `Research/018-model-fallback-pricing.md` §6.
    public let isEstimated: Bool?

    public init(
        dayKey: String,
        costUSD: Double,
        totalTokens: Int,
        modelBreakdowns: [SyncCostBreakdown] = [],
        serviceBreakdowns: [SyncCostBreakdown] = [],
        isEstimated: Bool? = nil)
    {
        self.dayKey = dayKey
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.modelBreakdowns = modelBreakdowns
        self.serviceBreakdowns = serviceBreakdowns
        self.isEstimated = isEstimated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dayKey = try container.decode(String.self, forKey: .dayKey)
        self.costUSD = try container.decode(Double.self, forKey: .costUSD)
        self.totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        // `?? []` backward-compat fallback: Mac builds prior to 0.18 didn't
        // write `modelBreakdowns` / `serviceBreakdowns`. Those old payloads
        // must still decode — an iPhone reading them treats the day as "no
        // breakdown data" (empty arrays) rather than throwing. Removing the
        // fallback would crash the entire `SyncCostSummary.daily` decode and
        // lose every pre-0.18 user's history from the iPhone view.
        self.modelBreakdowns =
            try container.decodeIfPresent([SyncCostBreakdown].self, forKey: .modelBreakdowns) ?? []
        self.serviceBreakdowns =
            try container.decodeIfPresent([SyncCostBreakdown].self, forKey: .serviceBreakdowns) ?? []
        self.isEstimated = try container.decodeIfPresent(Bool.self, forKey: .isEstimated)
    }
}

/// Aggregated cost/token summary for iCloud sync.
public struct SyncCostSummary: Codable, Sendable, Equatable {
    public let sessionCostUSD: Double?
    public let sessionTokens: Int?
    public let last30DaysCostUSD: Double?
    public let last30DaysTokens: Int?
    public let daily: [SyncDailyPoint]
    /// Summary-level OR aggregate of `daily[*].isEstimated`. `nil` for
    /// payloads from Mac builds before 0.23 — iOS treats nil as `false`
    /// (not estimated). See `Research/018-model-fallback-pricing.md` §6.
    public let isEstimated: Bool?
    /// Number of days the Mac's cost-history window covers (user-configurable
    /// 1–365, default 30). Drives the iOS cost-summary label so it reads
    /// "Last N days" instead of a hardcoded "30 Days" when the value may be a
    /// 7- or 365-day total (gap F). Optional — nil for pre-0.29 payloads; iOS
    /// treats nil as 30 (the historical default).
    public let historyDays: Int?
    /// iOS 1.10.0 / Mac 0.31.0 (025) — upstream #1163: request counts +
    /// currency for the shared cost cards. Optional; nil for pre-0.31
    /// payloads. iOS shows "N requests" + the right currency symbol.
    public let sessionRequests: Int?
    public let last30DaysRequests: Int?
    public let currencyCode: String?

    public init(
        sessionCostUSD: Double?,
        sessionTokens: Int?,
        last30DaysCostUSD: Double?,
        last30DaysTokens: Int?,
        daily: [SyncDailyPoint],
        isEstimated: Bool? = nil,
        historyDays: Int? = nil,
        sessionRequests: Int? = nil,
        last30DaysRequests: Int? = nil,
        currencyCode: String? = nil)
    {
        self.sessionCostUSD = sessionCostUSD
        self.sessionTokens = sessionTokens
        self.last30DaysCostUSD = last30DaysCostUSD
        self.last30DaysTokens = last30DaysTokens
        self.daily = daily
        self.isEstimated = isEstimated
        self.historyDays = historyDays
        self.sessionRequests = sessionRequests
        self.last30DaysRequests = last30DaysRequests
        self.currencyCode = currencyCode
    }
}

/// Provider budget/spend snapshot for iCloud sync.
public struct SyncBudgetSnapshot: Codable, Sendable, Equatable {
    public let usedAmount: Double
    public let limitAmount: Double
    public let currencyCode: String
    public let period: String?
    public let resetsAt: Date?

    public init(
        usedAmount: Double,
        limitAmount: Double,
        currencyCode: String,
        period: String?,
        resetsAt: Date?)
    {
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.currencyCode = currencyCode
        self.period = period
        self.resetsAt = resetsAt
    }
}

/// A single data point in the subscription utilization history.
public struct SyncUtilizationEntry: Codable, Sendable, Equatable {
    public let capturedAt: Date
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(capturedAt: Date, usedPercent: Double, resetsAt: Date?) {
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// A named series of utilization history entries (e.g. "session", "weekly", "opus").
public struct SyncUtilizationSeries: Codable, Sendable, Equatable {
    public let name: String
    public let windowMinutes: Int
    public let entries: [SyncUtilizationEntry]

    public init(name: String, windowMinutes: Int, entries: [SyncUtilizationEntry]) {
        self.name = name
        self.windowMinutes = windowMinutes
        self.entries = entries
    }
}

/// Perplexity-specific credit breakdown for iOS detail rendering.
///
/// Perplexity's backend exposes three distinct credit pools that the generic
/// `SyncRateWindow` list can't faithfully represent:
///   - `recurring` — monthly Pro/Max plan entitlement
///   - `promo`     — bonus / time-limited credits (may expire)
///   - `purchased` — on-demand top-ups (no expiration)
///
/// All fields Optional so a free-tier account (no recurring), an old Mac
/// payload (pre-0.20.3, key absent entirely), and future pool additions all
/// degrade silently. Amounts are in **cents** — the raw unit upstream
/// `PerplexityUsageSnapshot` uses — iOS formats for display.
public struct SyncPerplexityCreditSummary: Codable, Sendable, Equatable {
    public let recurringTotalCents: Double?
    public let recurringUsedCents: Double?
    public let promoTotalCents: Double?
    public let promoUsedCents: Double?
    public let promoExpiresAt: Date?
    public let purchasedTotalCents: Double?
    public let purchasedUsedCents: Double?
    /// Next recurring renewal (nil on free tier or when Mac hasn't parsed it).
    public let renewalAt: Date?
    /// `"Pro"` / `"Max"` / `nil` — inferred upstream from recurring quota.
    public let planName: String?
    /// Passthrough of `response.balance_cents`; rarely displayed, kept for parity.
    public let balanceCents: Double?

    public init(
        recurringTotalCents: Double? = nil,
        recurringUsedCents: Double? = nil,
        promoTotalCents: Double? = nil,
        promoUsedCents: Double? = nil,
        promoExpiresAt: Date? = nil,
        purchasedTotalCents: Double? = nil,
        purchasedUsedCents: Double? = nil,
        renewalAt: Date? = nil,
        planName: String? = nil,
        balanceCents: Double? = nil)
    {
        self.recurringTotalCents = recurringTotalCents
        self.recurringUsedCents = recurringUsedCents
        self.promoTotalCents = promoTotalCents
        self.promoUsedCents = promoUsedCents
        self.promoExpiresAt = promoExpiresAt
        self.purchasedTotalCents = purchasedTotalCents
        self.purchasedUsedCents = purchasedUsedCents
        self.renewalAt = renewalAt
        self.planName = planName
        self.balanceCents = balanceCents
    }
}

/// A single provider's usage snapshot for iCloud sync.
public struct ProviderUsageSnapshot: Codable, Sendable, Equatable {
    public let providerID: String
    public let providerName: String
    public let primary: SyncRateWindow?
    public let secondary: SyncRateWindow?
    /// Dynamic list of all rate windows (replaces primary/secondary when present).
    public let rateWindows: [SyncRateWindow]
    public let accountEmail: String?
    public let loginMethod: String?
    public let statusMessage: String?
    public let isError: Bool
    public let lastUpdated: Date
    public let costSummary: SyncCostSummary?
    public let budget: SyncBudgetSnapshot?
    /// Optional subscription lifecycle metadata surfaced by providers such as
    /// MiniMax. Additive only: old Mac payloads decode as nil, old iOS clients
    /// ignore the keys, and cross-version merges use latestNonNil semantics.
    public let subscriptionExpiresAt: Date?
    public let subscriptionRenewsAt: Date?
    /// Subscription utilization history (session/weekly/opus) for chart display.
    public let utilizationHistory: [SyncUtilizationSeries]?
    /// Perplexity-specific structured credit breakdown. Populated only when
    /// `providerID == "perplexity"` and Mac ≥ 0.20.3. Nil for all other
    /// providers and for older Mac clients — iOS falls back to the generic
    /// `rateWindows` rendering in that case.
    public let perplexityCredits: SyncPerplexityCreditSummary?

    /// Mac-side stable identifiers for the logical account this snapshot
    /// represents. iOS uses these as grouping evidence: any two snapshots
    /// that share at least one identifier in this list merge into one card.
    ///
    /// Format: `{providerID}:{scheme}:{value}` — e.g.
    /// `"codex:account:org-abc123"`, `"codex:email:user@example.com"`,
    /// `"claude:oauth-sub:xyz789"`. The `providerID` prefix prevents
    /// cross-provider false merges. The `scheme` is informational —
    /// iOS doesn't parse it, only compares strings.
    ///
    /// **Mac rule (additive only):** new schemes are appended to the
    /// list while legacy schemes stay in place for ≥3 minor releases.
    /// Removing an identifier scheme requires a documented deprecation
    /// cycle. See `Research/019-account-identity-multi-version-merge.md`
    /// §6.
    ///
    /// **`nil`** (decode default for old Mac payloads, e.g. ≤ 0.20.3) →
    /// iOS buckets the snapshot under a per-device legacy key, never
    /// auto-merging it with other Macs. The user sees a "data not
    /// aligned" hint on the affected card.
    ///
    /// **`[]`** (empty array) → treated identically to nil. Mac wrote
    /// the field but couldn't compute any identifier (transient signin
    /// state). Avoids grouping all anonymous snapshots together.
    public let accountIdentities: [String]?

    /// iOS 1.6.0 / Mac 0.25.2 — per-provider quota warning configuration
    /// resolved by Mac's settings layer (`SettingsStore.quotaWarningEnabled`
    /// + `resolvedQuotaWarningThresholds`). iOS reads this to render
    /// warning marker ticks on the usage bar (UsageCardView).
    ///
    /// `nil` when the snapshot came from a Mac pre-0.25.2 (field didn't
    /// exist) or when the providerID didn't resolve to a known
    /// `UsageProvider` case on Mac side (mock fallbacks, future
    /// providers). iOS falls back to `SyncQuotaWarningConfig.macDefaults`
    /// `[50, 20]` for visual rendering. See Research/020 §R7.4.
    ///
    /// Wire-compatible: optional + `decodeIfPresent`. Pre-1.6.0 iOS
    /// ignores the new field; old Mac doesn't emit it.
    public let quotaWarnings: SyncQuotaWarningConfig?

    // MARK: - iOS 1.7.0 / Mac 0.26.2 — v0.26 envelope extensions
    //
    // All six fields are optional + `decodeIfPresent` so pre-1.7.0 iOS
    // clients (and the inverse — Mac builds that don't have the upstream
    // data yet) keep decoding payloads without errors. The wire schema
    // version is intentionally NOT bumped (`providerPayloadVersion`
    // stays at 1) because additive optional fields don't require a
    // forced rewrite cycle. See `Research/020-multi-account-comprehensive.md`
    // §wire-extension protocol and `Shared/iCloud/CloudConstants.swift`.

    /// OpenAI Admin API usage dashboard (Today / 7d / 30d summaries +
    /// 30-day daily breakdown + top models / line items). Populated
    /// only on the `openai` provider snapshot when Mac has Admin API
    /// access. iOS surfaces this as the "OpenAI API Dashboard" section.
    public let openAIAPIDashboard: SyncOpenAIAPIDashboard?

    /// z.ai per-model hourly token usage. Populated only on the `zai`
    /// provider snapshot when Mac has at least one model_usage data
    /// point in the active window. iOS renders this as a stacked
    /// hourly bar chart.
    public let zaiHourlyUsage: SyncZaiHourlyUsage?

    /// Kiro plan + credit + bonus balance. Populated only on the
    /// `kiro` provider snapshot. iOS renders this as a Perplexity-style
    /// dedicated credits card with plan tag + bonus countdown.
    public let kiroCredits: SyncKiroCredits?

    /// AWS Bedrock monthly spend + budget. Populated only on the
    /// `bedrock` provider snapshot (NEW provider in v0.26.0). iOS
    /// renders this as a cost-forward card with budget progress + region.
    public let bedrockCost: SyncBedrockCost?

    /// Moonshot / Kimi API account balance. Populated only on the
    /// `moonshot` provider snapshot (NEW provider in v0.26.0). iOS
    /// renders this as a simple balance + region card.
    public let moonshotBalance: SyncMoonshotBalance?

    /// OAuth multi-account list + active index. Populated today only
    /// on the `antigravity` provider snapshot when more than one Google
    /// account is wired. iOS renders this as an account switcher
    /// affordance below the usage card.
    public let antigravityAccounts: SyncMultiAccountList?

    // MARK: - iOS 1.8.0 / Mac 0.27.0 — v0.27 envelope extensions
    //
    // All five fields are optional + `decodeIfPresent` so pre-1.8.0
    // iOS clients keep decoding payloads without errors. Wire schema
    // version is intentionally NOT bumped — additive optional fields
    // do not require a forced rewrite cycle.

    /// Grok (xAI) monthly billing summary. Populated only on the
    /// `grok` provider snapshot when Mac has Grok CLI billing or
    /// grok.com web-billing access. iOS renders this as a dedicated
    /// monthly cost card with planTier badge.
    public let grokBilling: SyncGrokBilling?

    /// ElevenLabs character credits + voice slot state. Populated
    /// only on the `elevenlabs` provider snapshot. iOS renders this
    /// as a character-credits primary row plus optional voice-slot
    /// secondary rows when slot data is present.
    public let elevenLabsCredits: SyncElevenLabsCredits?

    /// Deepgram speech / agent / TTS usage breakdown for the active
    /// project. Populated only on the `deepgram` provider snapshot.
    /// iOS renders the speech+agent split, request count, and
    /// optional TTS character count.
    public let deepgramUsage: SyncDeepgramUsage?

    /// GroqCloud Enterprise Prometheus rate metrics (requests / min,
    /// tokens / min, cache hit %). Populated only on the `groq`
    /// provider snapshot when Mac has an Enterprise key. iOS
    /// renders these as live-rate badges; for non-Enterprise keys
    /// the field stays nil and iOS falls back to the generic card.
    public let groqMetrics: SyncGroqMetrics?

    /// LLM Proxy meta-provider aggregate: provider / credential
    /// counts, lowest remaining quota %, and top-3 upstream
    /// breakdown. Populated only on the `llmproxy` provider
    /// snapshot. iOS renders the per-upstream breakdown as a
    /// stacked list under the primary "X% used" badge.
    public let llmProxyStats: SyncLLMProxyStats?

    // MARK: - iOS 1.8.0 build 134 / Mac 0.27.0 — existing-provider extensions
    //
    // Added after the initial 1.8.0 ship to bring v0.27.0 parity for
    // Anthropic Admin API, Enterprise spend-limit, MiniMax 30-day
    // billing, OpenCode Zen balance, and Codex workspace + weekly
    // pace. Wire schema not bumped — additive optionals only.

    /// Anthropic Admin API per-org usage. Populated only on the
    /// `claude` provider snapshot when Mac has an Admin API key.
    /// iOS surfaces this as the "Admin API" section on the Claude
    /// detail page (mirrors the OpenAI Admin API Dashboard layout).
    public let claudeAdminUsage: SyncClaudeAdminUsage?

    /// Anthropic OAuth `extra_usage` spend-limit metric (Enterprise
    /// and Team-with-extra-usage plans). Populated only on the
    /// `claude` provider snapshot. iOS renders this as a dedicated
    /// "Extra usage" row beneath the session / weekly bars.
    public let claudeExtraUsage: SyncClaudeExtraUsage?

    /// OpenCode Go Zen workspace pay-as-you-go balance. Populated
    /// only on the `opencodego` provider snapshot when the user has a
    /// Zen-enabled workspace and Mac scraped a balance. iOS shows
    /// this as a fourth balance row beneath rolling / weekly /
    /// monthly bars.
    public let openCodeGoZenBalance: SyncOpenCodeGoZenBalance?

    /// MiniMax 30-day billing history. Populated only on the
    /// `minimax` provider snapshot when Mac has an API key. iOS
    /// shows a 30-day token chart plus top-3 method/model breakdowns.
    public let minimaxBilling: SyncMiniMaxBillingHistory?

    /// Codex workspace context + weekly pace. Populated only on the
    /// `codex` provider snapshot when the OpenAI dashboard exposed
    /// workspace data. iOS shows the workspace name as a caption
    /// and the pace as a directional badge.
    public let codexWorkspace: SyncCodexWorkspaceContext?

    // MARK: - iOS 1.9.0 / Mac 0.29.0 — parity-gap envelope extensions
    // Additive optionals (decodeIfPresent); no wire-schema bump.

    /// OpenRouter balance + credits + per-key usage windows (gap D).
    /// Populated only on the `openrouter` provider snapshot.
    public let openRouterStats: SyncOpenRouterStats?

    /// Azure OpenAI deployment identity (gap E). Populated only on the
    /// `azureopenai` provider snapshot.
    public let azureOpenAIInfo: SyncAzureOpenAIInfo?

    /// Alibaba Token Plan (Bailian) structured credit quota (gap G).
    /// Populated only on the `alibabatokenplan` provider snapshot.
    public let alibabaTokenPlan: SyncAlibabaTokenPlan?

    // MARK: - iOS 1.10.0 / Mac 0.31.0 — v0.30/v0.31 sync (025)
    // Additive optional (decodeIfPresent); no wire-schema bump.

    /// DeepSeek web-session usage + cost summary + balance (upstream v0.30.0
    /// #1166). Populated only on the `deepseek` provider snapshot. iOS renders
    /// the dedicated DeepSeekUsageCard; nil → falls back to generic rendering.
    public let deepSeekUsage: SyncDeepSeekUsage?

    // MARK: - iOS 1.15.0 / Mac 0.37.2.1 — v0.37 sync (033)
    // Additive optionals (decodeIfPresent); no wire-schema bump.

    /// Codex manual rate-limit reset credits (upstream v0.37.0). Populated only
    /// on the `codex` provider snapshot when Mac has fetched reset-credit state.
    public let codexResetCredits: SyncCodexResetCredits?

    /// Raw upstream `UsageDataConfidence` value (e.g. "exact", "estimated",
    /// "percentOnly"). `nil` means legacy/unknown; future values are preserved as
    /// strings so iOS does not reject newer Mac payloads.
    public let usageDataConfidence: String?

    // MARK: - iOS 1.17.0 / Mac 0.39.0.1 — v0.39 sync
    // Additive optional (decodeIfPresent); no wire-schema bump.

    /// CrossModel wallet balance plus day/week/month usage windows. Populated
    /// only on the `crossmodel` provider snapshot. CrossModel has no generic
    /// rate window, so iOS needs this typed payload to render anything useful.
    public let crossModelUsage: SyncCrossModelUsage?

    /// All available rate windows. Prefers `rateWindows` if non-empty, otherwise falls back to primary/secondary.
    public var allRateWindows: [SyncRateWindow] {
        if !self.rateWindows.isEmpty { return self.rateWindows }
        return [self.primary, self.secondary].compactMap(\.self)
    }

    public init(
        providerID: String,
        providerName: String,
        primary: SyncRateWindow?,
        secondary: SyncRateWindow?,
        accountEmail: String?,
        loginMethod: String?,
        statusMessage: String?,
        isError: Bool,
        lastUpdated: Date,
        costSummary: SyncCostSummary? = nil,
        budget: SyncBudgetSnapshot? = nil,
        subscriptionExpiresAt: Date? = nil,
        subscriptionRenewsAt: Date? = nil,
        rateWindows: [SyncRateWindow] = [],
        utilizationHistory: [SyncUtilizationSeries]? = nil,
        perplexityCredits: SyncPerplexityCreditSummary? = nil,
        accountIdentities: [String]? = nil,
        quotaWarnings: SyncQuotaWarningConfig? = nil,
        openAIAPIDashboard: SyncOpenAIAPIDashboard? = nil,
        zaiHourlyUsage: SyncZaiHourlyUsage? = nil,
        kiroCredits: SyncKiroCredits? = nil,
        bedrockCost: SyncBedrockCost? = nil,
        moonshotBalance: SyncMoonshotBalance? = nil,
        antigravityAccounts: SyncMultiAccountList? = nil,
        grokBilling: SyncGrokBilling? = nil,
        elevenLabsCredits: SyncElevenLabsCredits? = nil,
        deepgramUsage: SyncDeepgramUsage? = nil,
        groqMetrics: SyncGroqMetrics? = nil,
        llmProxyStats: SyncLLMProxyStats? = nil,
        claudeAdminUsage: SyncClaudeAdminUsage? = nil,
        claudeExtraUsage: SyncClaudeExtraUsage? = nil,
        openCodeGoZenBalance: SyncOpenCodeGoZenBalance? = nil,
        minimaxBilling: SyncMiniMaxBillingHistory? = nil,
        codexWorkspace: SyncCodexWorkspaceContext? = nil,
        openRouterStats: SyncOpenRouterStats? = nil,
        azureOpenAIInfo: SyncAzureOpenAIInfo? = nil,
        alibabaTokenPlan: SyncAlibabaTokenPlan? = nil,
        deepSeekUsage: SyncDeepSeekUsage? = nil,
        codexResetCredits: SyncCodexResetCredits? = nil,
        usageDataConfidence: String? = nil,
        crossModelUsage: SyncCrossModelUsage? = nil)
    {
        self.providerID = providerID
        self.providerName = providerName
        self.primary = primary
        self.secondary = secondary
        self.rateWindows = rateWindows
        self.accountEmail = accountEmail
        self.loginMethod = loginMethod
        self.statusMessage = statusMessage
        self.isError = isError
        self.lastUpdated = lastUpdated
        self.costSummary = costSummary
        self.budget = budget
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.subscriptionRenewsAt = subscriptionRenewsAt
        self.utilizationHistory = utilizationHistory
        self.perplexityCredits = perplexityCredits
        self.accountIdentities = accountIdentities
        self.quotaWarnings = quotaWarnings
        self.openAIAPIDashboard = openAIAPIDashboard
        self.zaiHourlyUsage = zaiHourlyUsage
        self.kiroCredits = kiroCredits
        self.bedrockCost = bedrockCost
        self.moonshotBalance = moonshotBalance
        self.antigravityAccounts = antigravityAccounts
        self.grokBilling = grokBilling
        self.elevenLabsCredits = elevenLabsCredits
        self.deepgramUsage = deepgramUsage
        self.groqMetrics = groqMetrics
        self.llmProxyStats = llmProxyStats
        self.claudeAdminUsage = claudeAdminUsage
        self.claudeExtraUsage = claudeExtraUsage
        self.openCodeGoZenBalance = openCodeGoZenBalance
        self.minimaxBilling = minimaxBilling
        self.codexWorkspace = codexWorkspace
        self.openRouterStats = openRouterStats
        self.azureOpenAIInfo = azureOpenAIInfo
        self.alibabaTokenPlan = alibabaTokenPlan
        self.deepSeekUsage = deepSeekUsage
        self.codexResetCredits = codexResetCredits
        self.usageDataConfidence = usageDataConfidence
        self.crossModelUsage = crossModelUsage
    }

    /// Returns a copy with `quotaWarnings` swapped out. Used by Mac
    /// SyncCoordinator post-hoc to inject per-provider config (resolved
    /// from `SettingsStore`) before encoding the wire envelope, without
    /// requiring each provider fetcher to know about the settings layer.
    public func with(quotaWarnings: SyncQuotaWarningConfig?) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: self.providerID,
            providerName: self.providerName,
            primary: self.primary,
            secondary: self.secondary,
            accountEmail: self.accountEmail,
            loginMethod: self.loginMethod,
            statusMessage: self.statusMessage,
            isError: self.isError,
            lastUpdated: self.lastUpdated,
            costSummary: self.costSummary,
            budget: self.budget,
            subscriptionExpiresAt: self.subscriptionExpiresAt,
            subscriptionRenewsAt: self.subscriptionRenewsAt,
            rateWindows: self.rateWindows,
            utilizationHistory: self.utilizationHistory,
            perplexityCredits: self.perplexityCredits,
            accountIdentities: self.accountIdentities,
            quotaWarnings: quotaWarnings,
            openAIAPIDashboard: self.openAIAPIDashboard,
            zaiHourlyUsage: self.zaiHourlyUsage,
            kiroCredits: self.kiroCredits,
            bedrockCost: self.bedrockCost,
            moonshotBalance: self.moonshotBalance,
            antigravityAccounts: self.antigravityAccounts,
            grokBilling: self.grokBilling,
            elevenLabsCredits: self.elevenLabsCredits,
            deepgramUsage: self.deepgramUsage,
            groqMetrics: self.groqMetrics,
            llmProxyStats: self.llmProxyStats,
            claudeAdminUsage: self.claudeAdminUsage,
            claudeExtraUsage: self.claudeExtraUsage,
            openCodeGoZenBalance: self.openCodeGoZenBalance,
            minimaxBilling: self.minimaxBilling,
            codexWorkspace: self.codexWorkspace,
            openRouterStats: self.openRouterStats,
            azureOpenAIInfo: self.azureOpenAIInfo,
            alibabaTokenPlan: self.alibabaTokenPlan,
            deepSeekUsage: self.deepSeekUsage,
            codexResetCredits: self.codexResetCredits,
            usageDataConfidence: self.usageDataConfidence,
            crossModelUsage: self.crossModelUsage)
    }

    /// Backward-compatible decoder: old payloads without `rateWindows`/`costSummary`/`budget`/`perplexityCredits`/`accountIdentities`/`quotaWarnings` still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providerID = try container.decode(String.self, forKey: .providerID)
        self.providerName = try container.decode(String.self, forKey: .providerName)
        self.primary = try container.decodeIfPresent(SyncRateWindow.self, forKey: .primary)
        self.secondary = try container.decodeIfPresent(SyncRateWindow.self, forKey: .secondary)
        self.rateWindows = try container.decodeIfPresent([SyncRateWindow].self, forKey: .rateWindows) ?? []
        self.accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail)
        self.loginMethod = try container.decodeIfPresent(String.self, forKey: .loginMethod)
        self.statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        self.isError = try container.decode(Bool.self, forKey: .isError)
        self.lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        self.costSummary = try container.decodeIfPresent(SyncCostSummary.self, forKey: .costSummary)
        self.budget = try container.decodeIfPresent(SyncBudgetSnapshot.self, forKey: .budget)
        self.subscriptionExpiresAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionExpiresAt)
        self.subscriptionRenewsAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionRenewsAt)
        self.utilizationHistory = try container.decodeIfPresent([SyncUtilizationSeries].self, forKey: .utilizationHistory)
        self.perplexityCredits = try container.decodeIfPresent(SyncPerplexityCreditSummary.self, forKey: .perplexityCredits)
        self.accountIdentities = try container.decodeIfPresent([String].self, forKey: .accountIdentities)
        self.quotaWarnings = try container.decodeIfPresent(SyncQuotaWarningConfig.self, forKey: .quotaWarnings)
        // iOS 1.7.0 / Mac 0.26.2 — v0.26 envelope extensions. All
        // `decodeIfPresent` so old Mac payloads (without these keys)
        // decode cleanly into `nil`.
        self.openAIAPIDashboard = try container.decodeIfPresent(SyncOpenAIAPIDashboard.self, forKey: .openAIAPIDashboard)
        self.zaiHourlyUsage = try container.decodeIfPresent(SyncZaiHourlyUsage.self, forKey: .zaiHourlyUsage)
        self.kiroCredits = try container.decodeIfPresent(SyncKiroCredits.self, forKey: .kiroCredits)
        self.bedrockCost = try container.decodeIfPresent(SyncBedrockCost.self, forKey: .bedrockCost)
        self.moonshotBalance = try container.decodeIfPresent(SyncMoonshotBalance.self, forKey: .moonshotBalance)
        self.antigravityAccounts = try container.decodeIfPresent(SyncMultiAccountList.self, forKey: .antigravityAccounts)
        // iOS 1.8.0 / Mac 0.27.0 — v0.27 envelope extensions.
        self.grokBilling = try container.decodeIfPresent(SyncGrokBilling.self, forKey: .grokBilling)
        self.elevenLabsCredits = try container.decodeIfPresent(SyncElevenLabsCredits.self, forKey: .elevenLabsCredits)
        self.deepgramUsage = try container.decodeIfPresent(SyncDeepgramUsage.self, forKey: .deepgramUsage)
        self.groqMetrics = try container.decodeIfPresent(SyncGroqMetrics.self, forKey: .groqMetrics)
        self.llmProxyStats = try container.decodeIfPresent(SyncLLMProxyStats.self, forKey: .llmProxyStats)
        // iOS 1.8.0 build 134 — existing-provider extensions.
        self.claudeAdminUsage = try container.decodeIfPresent(SyncClaudeAdminUsage.self, forKey: .claudeAdminUsage)
        self.claudeExtraUsage = try container.decodeIfPresent(SyncClaudeExtraUsage.self, forKey: .claudeExtraUsage)
        self.openCodeGoZenBalance = try container.decodeIfPresent(SyncOpenCodeGoZenBalance.self, forKey: .openCodeGoZenBalance)
        self.minimaxBilling = try container.decodeIfPresent(SyncMiniMaxBillingHistory.self, forKey: .minimaxBilling)
        self.codexWorkspace = try container.decodeIfPresent(SyncCodexWorkspaceContext.self, forKey: .codexWorkspace)
        // iOS 1.9.0 / Mac 0.29.0 — parity-gap extensions.
        self.openRouterStats = try container.decodeIfPresent(SyncOpenRouterStats.self, forKey: .openRouterStats)
        self.azureOpenAIInfo = try container.decodeIfPresent(SyncAzureOpenAIInfo.self, forKey: .azureOpenAIInfo)
        self.alibabaTokenPlan = try container.decodeIfPresent(SyncAlibabaTokenPlan.self, forKey: .alibabaTokenPlan)
        self.deepSeekUsage = try container.decodeIfPresent(SyncDeepSeekUsage.self, forKey: .deepSeekUsage)
        // iOS 1.15.0 / Mac 0.37.2.1 — v0.37 envelope extensions.
        self.codexResetCredits = try container.decodeIfPresent(SyncCodexResetCredits.self, forKey: .codexResetCredits)
        self.usageDataConfidence = try container.decodeIfPresent(String.self, forKey: .usageDataConfidence)
        // iOS 1.17.0 / Mac 0.39.0.1 — v0.39 CrossModel wallet/usage payload.
        self.crossModelUsage = try container.decodeIfPresent(SyncCrossModelUsage.self, forKey: .crossModelUsage)
    }
}

/// Full sync payload pushed from Mac to iOS via iCloud.
public struct SyncedUsageSnapshot: Codable, Sendable, Equatable {
    public let providers: [ProviderUsageSnapshot]
    public let syncTimestamp: Date
    public let deviceName: String
    /// Stable UUID identifying the source Mac. Used as CloudKit record name.
    public let deviceID: String?
    /// Mac app version (e.g. "0.18.0-beta.3")
    public let appVersion: String?
    /// Mobile version (e.g. "1.0.0")
    public let mobileVersion: String?
    /// When false, iOS should suppress push notifications for this snapshot.
    public let notificationPushEnabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case providers, syncTimestamp, deviceName, deviceID, appVersion
        case mobileVersion, notificationPushEnabled
        /// Legacy key for backward compatibility with older synced data.
        ///
        /// **DO NOT REMOVE.** Mac builds 0.17.x–0.19.x wrote this field name
        /// (`syncVersion`) instead of `mobileVersion`. If an iPhone reads an
        /// old-payload Mac snapshot with this key stripped from the decoder,
        /// the mobileVersion field decodes as nil, which downstream
        /// `latestNonNil` + highest-semver logic in `mergeSnapshots` turns
        /// into "no mobile version synced from any Mac" — a user-visible
        /// regression in Settings → About. Retained for at least until every
        /// live user has upgraded their Mac past 0.20.x.
        case syncVersion
    }

    public init(
        providers: [ProviderUsageSnapshot],
        syncTimestamp: Date,
        deviceName: String,
        deviceID: String? = nil,
        appVersion: String? = nil,
        mobileVersion: String? = nil,
        notificationPushEnabled: Bool? = nil)
    {
        self.providers = providers
        self.syncTimestamp = syncTimestamp
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.appVersion = appVersion
        self.mobileVersion = mobileVersion
        self.notificationPushEnabled = notificationPushEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providers = try container.decode([ProviderUsageSnapshot].self, forKey: .providers)
        self.syncTimestamp = try container.decode(Date.self, forKey: .syncTimestamp)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        // Read from "mobileVersion" first; fall back to legacy "syncVersion" key.
        // See `CodingKeys.syncVersion` docstring — retained for decoding
        // payloads written by Mac 0.17.x–0.19.x. Encoder writes only
        // `mobileVersion`, so newer payloads skip the fallback entirely.
        self.mobileVersion = try container.decodeIfPresent(String.self, forKey: .mobileVersion)
            ?? container.decodeIfPresent(String.self, forKey: .syncVersion)
        self.notificationPushEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationPushEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.providers, forKey: .providers)
        try container.encode(self.syncTimestamp, forKey: .syncTimestamp)
        try container.encode(self.deviceName, forKey: .deviceName)
        try container.encodeIfPresent(self.deviceID, forKey: .deviceID)
        try container.encodeIfPresent(self.appVersion, forKey: .appVersion)
        try container.encodeIfPresent(self.mobileVersion, forKey: .mobileVersion)
        try container.encodeIfPresent(self.notificationPushEnabled, forKey: .notificationPushEnabled)
    }
}
