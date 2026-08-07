import Foundation

// MARK: - OpenAI API Admin Dashboard (upstream v0.26.1)

/// A single day's cost / token / request bucket inside the OpenAI Admin
/// API usage breakdown. Populated only for `providerID == "openai"`.
public struct SyncOpenAIDailyBucket: Codable, Sendable, Equatable {
    public let dayKey: String
    public let costUSD: Double
    public let requests: Int
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    public init(
        dayKey: String,
        costUSD: Double,
        requests: Int,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        totalTokens: Int)
    {
        self.dayKey = dayKey
        self.costUSD = costUSD
        self.requests = requests
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.dayKey = try c.decode(String.self, forKey: .dayKey)
        self.costUSD = try c.decode(Double.self, forKey: .costUSD)
        self.requests = try c.decode(Int.self, forKey: .requests)
        self.inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        self.cachedInputTokens = try c.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        self.outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        self.totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
    }
}

/// An aggregate window summary (Today / 7d / 30d) computed by Mac and
/// pushed to iOS in the OpenAI dashboard payload.
public struct SyncOpenAISummary: Codable, Sendable, Equatable {
    public let totalCostUSD: Double
    public let totalRequests: Int
    public let totalTokens: Int

    public init(totalCostUSD: Double, totalRequests: Int, totalTokens: Int) {
        self.totalCostUSD = totalCostUSD
        self.totalRequests = totalRequests
        self.totalTokens = totalTokens
    }
}

/// A model-level breakdown row inside the OpenAI dashboard (e.g. gpt-5
/// vs. gpt-5.5 contributions). `costUSD` may be 0 when only request /
/// token counts are surfaced by the Admin endpoint.
public struct SyncOpenAIModelBreakdown: Codable, Sendable, Equatable {
    public let modelName: String
    public let requests: Int
    public let totalTokens: Int
    public let costUSD: Double

    public init(modelName: String, requests: Int, totalTokens: Int, costUSD: Double) {
        self.modelName = modelName
        self.requests = requests
        self.totalTokens = totalTokens
        self.costUSD = costUSD
    }
}

/// A non-model line-item breakdown row (e.g. embeddings, moderation,
/// fine-tuning, audio). Populated when the Admin response separates
/// service categories.
public struct SyncOpenAILineItem: Codable, Sendable, Equatable {
    public let name: String
    public let costUSD: Double

    public init(name: String, costUSD: Double) {
        self.name = name
        self.costUSD = costUSD
    }
}

/// Full OpenAI Admin API dashboard payload. Populated only on the
/// `openai` provider snapshot. iOS surfaces this as the "OpenAI API
/// Dashboard" section on the provider detail page (Today / 7d / 30d
/// cards + 30-day cost chart + top models / line items lists).
///
/// **Wire compatibility:** optional + `decodeIfPresent` everywhere so
/// old iOS clients ignore the field, and the field is dropped cleanly
/// when Mac doesn't have Admin API access.
public struct SyncOpenAIAPIDashboard: Codable, Sendable, Equatable {
    public let last30Days: SyncOpenAISummary
    public let last7Days: SyncOpenAISummary
    public let latestDay: SyncOpenAISummary?
    public let dailyBuckets: [SyncOpenAIDailyBucket]
    public let topModels: [SyncOpenAIModelBreakdown]
    public let topLineItems: [SyncOpenAILineItem]
    /// Window size in days that `dailyBuckets` covers. Mac clamps to
    /// 1..365 and iOS picker filters down from this. Default 30 so
    /// payloads written by pre-1.8.0 Macs decode cleanly into a
    /// 30-day window — matches the historical behaviour.
    public let historyDays: Int

    public init(
        last30Days: SyncOpenAISummary,
        last7Days: SyncOpenAISummary,
        latestDay: SyncOpenAISummary?,
        dailyBuckets: [SyncOpenAIDailyBucket] = [],
        topModels: [SyncOpenAIModelBreakdown] = [],
        topLineItems: [SyncOpenAILineItem] = [],
        historyDays: Int = 30)
    {
        self.last30Days = last30Days
        self.last7Days = last7Days
        self.latestDay = latestDay
        self.dailyBuckets = dailyBuckets
        self.topModels = topModels
        self.topLineItems = topLineItems
        self.historyDays = max(1, min(365, historyDays))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.last30Days = try c.decode(SyncOpenAISummary.self, forKey: .last30Days)
        self.last7Days = try c.decode(SyncOpenAISummary.self, forKey: .last7Days)
        self.latestDay = try c.decodeIfPresent(SyncOpenAISummary.self, forKey: .latestDay)
        self.dailyBuckets =
            try c.decodeIfPresent([SyncOpenAIDailyBucket].self, forKey: .dailyBuckets) ?? []
        self.topModels =
            try c.decodeIfPresent([SyncOpenAIModelBreakdown].self, forKey: .topModels) ?? []
        self.topLineItems =
            try c.decodeIfPresent([SyncOpenAILineItem].self, forKey: .topLineItems) ?? []
        let rawHistoryDays = try c.decodeIfPresent(Int.self, forKey: .historyDays) ?? 30
        self.historyDays = max(1, min(365, rawHistoryDays))
    }
}

// MARK: - z.ai hourly chart (upstream v0.26.0)

/// One model's token-per-hour series. `tokens` is parallel to
/// `SyncZaiHourlyUsage.xTime`; `nil` slots mean "no data for that hour".
public struct SyncZaiModelSeries: Codable, Sendable, Equatable {
    public let modelName: String
    public let tokens: [Int?]

    public init(modelName: String, tokens: [Int?]) {
        self.modelName = modelName
        self.tokens = tokens
    }
}

/// Per-model hourly and daily token usage. iOS renders this as a stacked
/// bar chart on the z.ai provider detail page. The daily fields were added
/// in iOS 1.20.0 and decode to empty arrays for older Mac payloads.
public struct SyncZaiHourlyUsage: Codable, Sendable, Equatable {
    /// X-axis timestamps for the hourly bars (one per hour bucket).
    public let xTime: [Date]
    /// Per-model parallel series; tokens count matches `xTime.count`.
    public let modelSeries: [SyncZaiModelSeries]
    /// X-axis timestamps for the daily 7/30-day ranges.
    public let dailyXTime: [Date]
    /// Per-model parallel daily series; tokens count matches `dailyXTime.count`.
    public let dailyModelSeries: [SyncZaiModelSeries]

    public init(
        xTime: [Date],
        modelSeries: [SyncZaiModelSeries],
        dailyXTime: [Date] = [],
        dailyModelSeries: [SyncZaiModelSeries] = [])
    {
        self.xTime = xTime
        self.modelSeries = modelSeries
        self.dailyXTime = dailyXTime
        self.dailyModelSeries = dailyModelSeries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.xTime = try container.decodeIfPresent([Date].self, forKey: .xTime) ?? []
        self.modelSeries = try container.decodeIfPresent(
            [SyncZaiModelSeries].self,
            forKey: .modelSeries) ?? []
        self.dailyXTime = try container.decodeIfPresent([Date].self, forKey: .dailyXTime) ?? []
        self.dailyModelSeries = try container.decodeIfPresent(
            [SyncZaiModelSeries].self,
            forKey: .dailyModelSeries) ?? []
    }
}

// MARK: - Kiro credits + bonus (upstream v0.26.0; v0.27.0 adds overage)

/// Kiro plan + monthly credit allowance + optional bonus pool.
/// Populated only on the `kiro` provider snapshot.
///
/// v0.27.0 (upstream) added two overage fields — `overageCreditsUsed`
/// and `estimatedOverageCostUSD` — that Mac surfaces when a plan has
/// been exhausted. Both are optional + decoded with `decodeIfPresent`
/// so pre-v0.27.0 payloads (no overage data) still decode cleanly.
public struct SyncKiroCredits: Codable, Sendable, Equatable {
    public let planName: String?
    public let creditsUsed: Double
    public let creditsTotal: Double?
    public let creditsPercent: Double?
    public let bonusUsed: Double?
    public let bonusTotal: Double?
    public let bonusExpiryDays: Int?
    public let resetsAt: Date?
    /// Credits used **above the plan cap** (i.e. overage usage). Only
    /// populated when the Kiro CLI reports `overage_credits_used` —
    /// always nil before v0.27.0.
    public let overageCreditsUsed: Double?
    /// Mac-computed `(overageCreditsUsed * priceUSD)` estimate. Always
    /// USD; nil when no overage data is present or when Kiro has not
    /// surfaced a price. iOS displays this as a "overage cost" badge.
    public let estimatedOverageCostUSD: Double?

    public init(
        planName: String?,
        creditsUsed: Double,
        creditsTotal: Double?,
        creditsPercent: Double?,
        bonusUsed: Double?,
        bonusTotal: Double?,
        bonusExpiryDays: Int?,
        resetsAt: Date?,
        overageCreditsUsed: Double? = nil,
        estimatedOverageCostUSD: Double? = nil)
    {
        self.planName = planName
        self.creditsUsed = creditsUsed
        self.creditsTotal = creditsTotal
        self.creditsPercent = creditsPercent
        self.bonusUsed = bonusUsed
        self.bonusTotal = bonusTotal
        self.bonusExpiryDays = bonusExpiryDays
        self.resetsAt = resetsAt
        self.overageCreditsUsed = overageCreditsUsed
        self.estimatedOverageCostUSD = estimatedOverageCostUSD
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.planName = try c.decodeIfPresent(String.self, forKey: .planName)
        self.creditsUsed = try c.decode(Double.self, forKey: .creditsUsed)
        self.creditsTotal = try c.decodeIfPresent(Double.self, forKey: .creditsTotal)
        self.creditsPercent = try c.decodeIfPresent(Double.self, forKey: .creditsPercent)
        self.bonusUsed = try c.decodeIfPresent(Double.self, forKey: .bonusUsed)
        self.bonusTotal = try c.decodeIfPresent(Double.self, forKey: .bonusTotal)
        self.bonusExpiryDays = try c.decodeIfPresent(Int.self, forKey: .bonusExpiryDays)
        self.resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
        // v0.27.0 additions — decodeIfPresent so v0.26 payloads decode.
        self.overageCreditsUsed = try c.decodeIfPresent(Double.self, forKey: .overageCreditsUsed)
        self.estimatedOverageCostUSD = try c.decodeIfPresent(Double.self, forKey: .estimatedOverageCostUSD)
    }
}

// MARK: - AWS Bedrock cost (upstream v0.26.0, NEW provider)

/// AWS Bedrock monthly cost + budget tracking. Populated only on the
/// `bedrock` provider snapshot.
public struct SyncBedrockCost: Codable, Sendable, Equatable {
    public let monthlySpendUSD: Double
    public let monthlyBudgetUSD: Double?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let region: String?
    /// Optional pre-computed `(monthlySpend / monthlyBudget) * 100`,
    /// clamped to 0..<100. iOS can compute this locally too but Mac
    /// already does it for the menu bar, so we ship the result.
    public let budgetUsedPercent: Double?
    public let updatedAt: Date

    public init(
        monthlySpendUSD: Double,
        monthlyBudgetUSD: Double?,
        inputTokens: Int?,
        outputTokens: Int?,
        region: String?,
        budgetUsedPercent: Double?,
        updatedAt: Date)
    {
        self.monthlySpendUSD = monthlySpendUSD
        self.monthlyBudgetUSD = monthlyBudgetUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.region = region
        self.budgetUsedPercent = budgetUsedPercent
        self.updatedAt = updatedAt
    }
}

// MARK: - Moonshot / Kimi API balance (upstream v0.26.0, NEW provider)

/// Moonshot / Kimi API account balance. Populated only on the
/// `moonshot` provider snapshot.
public struct SyncMoonshotBalance: Codable, Sendable, Equatable {
    public let balanceAmount: Double
    /// ISO 4217 currency code (e.g. "CNY", "USD"). Optional because
    /// older Moonshot fetchers may not surface it.
    public let balanceCurrency: String?
    public let region: String?
    public let updatedAt: Date

    public init(
        balanceAmount: Double,
        balanceCurrency: String?,
        region: String?,
        updatedAt: Date)
    {
        self.balanceAmount = balanceAmount
        self.balanceCurrency = balanceCurrency
        self.region = region
        self.updatedAt = updatedAt
    }
}

// MARK: - Antigravity multi-account (upstream v0.26.0)

/// One OAuth account row inside `SyncMultiAccountList`.
public struct SyncMultiAccountEntry: Codable, Sendable, Equatable {
    public let email: String
    public let isActive: Bool
    public let expiresAt: Date?

    public init(email: String, isActive: Bool, expiresAt: Date?) {
        self.email = email
        self.isActive = isActive
        self.expiresAt = expiresAt
    }
}

/// Multi-account OAuth account list (Antigravity today; future
/// providers may reuse this shape). `activeIndex` matches the
/// element with `isActive == true`; sent redundantly so iOS can
/// detect a desync.
public struct SyncMultiAccountList: Codable, Sendable, Equatable {
    public let accounts: [SyncMultiAccountEntry]
    public let activeIndex: Int?

    public init(accounts: [SyncMultiAccountEntry], activeIndex: Int?) {
        self.accounts = accounts
        self.activeIndex = activeIndex
    }
}
