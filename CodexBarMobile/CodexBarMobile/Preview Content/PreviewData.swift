import CodexBarSync
import Foundation

enum PreviewData {
    // MARK: - Sample daily cost data (50 days)

    private static func makeDaily(
        baseCost: Double,
        tokenBase: Int,
        serviceMix: [(String, Double)] = [],
        modelMix: [(String, Double)] = []) -> [SyncDailyPoint]
    {
        let calendar = Calendar.current
        let today = Date()
        return (0..<50).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayKey = Self.dayKeyFormatter.string(from: date)

            // Simulate realistic spend curve: gradual ramp-up with weekly dips on weekends
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7
            let recencyBoost = pow(Double(50 - daysAgo) / 50.0, 1.5) // ramps up toward today
            let weekdayFactor = isWeekend ? 0.3 : 1.0
            let noise = 1.0 + sin(Double(daysAgo) * 1.7) * 0.25
            let cost = max(0.02, baseCost * recencyBoost * weekdayFactor * noise)
            let tokens = max(500, Int(Double(tokenBase) * recencyBoost * weekdayFactor * noise))

            return SyncDailyPoint(
                dayKey: dayKey,
                costUSD: cost,
                totalTokens: tokens,
                modelBreakdowns: modelMix.map { label, share in
                    SyncCostBreakdown(label: label, costUSD: cost * share)
                },
                serviceBreakdowns: serviceMix.map { label, share in
                    SyncCostBreakdown(label: label, costUSD: cost * share)
                })
        }
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Providers

    static let claudeProvider = ProviderUsageSnapshot(
        providerID: "claude",
        providerName: "Claude",
        primary: SyncRateWindow(
            label: "Session",
            usedPercent: 13,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3600 * 2.5),
            resetDescription: nil),
        secondary: SyncRateWindow(
            label: "Weekly",
            usedPercent: 16,
            windowMinutes: 10080,
            resetsAt: Date().addingTimeInterval(3600 * 24 * 4),
            resetDescription: nil),
        accountEmail: "user@example.com",
        loginMethod: "Max",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-120),
        costSummary: SyncCostSummary(
            sessionCostUSD: 57.14,
            sessionTokens: 565_900,
            last30DaysCostUSD: 401.30,
            last30DaysTokens: 12_450_000,
            daily: makeDaily(
                baseCost: 8.5,
                tokenBase: 350_000,
                modelMix: [("claude-opus-4-6", 0.77), ("claude-sonnet-4", 0.23)])),
        budget: SyncBudgetSnapshot(
            usedAmount: 42.50,
            limitAmount: 100.0,
            currencyCode: "USD",
            period: "Monthly",
            resetsAt: Date().addingTimeInterval(3600 * 24 * 12)),
        rateWindows: [
            SyncRateWindow(
                label: "Session",
                usedPercent: 13,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(3600 * 2.5),
                resetDescription: nil),
            SyncRateWindow(
                label: "Weekly",
                usedPercent: 16,
                windowMinutes: 10080,
                resetsAt: Date().addingTimeInterval(3600 * 24 * 4),
                resetDescription: nil),
            SyncRateWindow(
                label: "Sonnet",
                usedPercent: 1,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(3600 * 4.5),
                resetDescription: nil),
        ])

    static let cursorProvider = ProviderUsageSnapshot(
        providerID: "codex",
        providerName: "Codex",
        primary: SyncRateWindow(
            usedPercent: 78,
            windowMinutes: 180,
            resetsAt: Date().addingTimeInterval(3600),
            resetDescription: nil),
        secondary: SyncRateWindow(
            usedPercent: 55,
            windowMinutes: 10080,
            resetsAt: Date().addingTimeInterval(3600 * 24 * 2),
            resetDescription: nil),
        accountEmail: "dev@cursor.sh",
        loginMethod: "Business",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-300),
        costSummary: SyncCostSummary(
            sessionCostUSD: 20.49,
            sessionTokens: 207_900,
            last30DaysCostUSD: 109.33,
            last30DaysTokens: 2_980_000,
            daily: makeDaily(
                baseCost: 5.2,
                tokenBase: 180_000,
                serviceMix: [("Codex Run", 0.74), ("GitHub Code Review", 0.18), ("Responses API", 0.08)],
                modelMix: [("gpt-5.4", 0.52), ("gpt-5.3-codex", 0.33), ("gpt-5.1-codex-mini", 0.15)])),
        budget: SyncBudgetSnapshot(
            usedAmount: 74.60,
            limitAmount: 120.0,
            currencyCode: "USD",
            period: "Monthly",
            resetsAt: Date().addingTimeInterval(3600 * 24 * 9)))

    static let openRouterProvider = ProviderUsageSnapshot(
        providerID: "openrouter",
        providerName: "OpenRouter",
        primary: SyncRateWindow(
            usedPercent: 92,
            windowMinutes: 60,
            resetsAt: Date().addingTimeInterval(600),
            resetDescription: nil),
        secondary: nil,
        accountEmail: "user@openrouter.ai",
        loginMethod: "Credits",
        statusMessage: "Rate limit approaching",
        isError: true,
        lastUpdated: Date().addingTimeInterval(-60),
        costSummary: SyncCostSummary(
            sessionCostUSD: 0.48,
            sessionTokens: 5400,
            last30DaysCostUSD: 11.80,
            last30DaysTokens: 422_000,
            daily: makeDaily(
                baseCost: 0.39,
                tokenBase: 13500,
                modelMix: [("openrouter/sonoma", 0.44), ("deepseek-chat", 0.31), ("qwen-max", 0.25)])))

    static let chatGPTProvider = ProviderUsageSnapshot(
        providerID: "chatgpt",
        providerName: "ChatGPT",
        primary: SyncRateWindow(
            usedPercent: 5,
            windowMinutes: 180,
            resetsAt: Date().addingTimeInterval(3600 * 2),
            resetDescription: nil),
        secondary: SyncRateWindow(
            usedPercent: 12,
            windowMinutes: 10080,
            resetsAt: Date().addingTimeInterval(3600 * 24 * 5),
            resetDescription: "Resets every Monday"),
        accountEmail: "user@openai.com",
        loginMethod: "Plus",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-600),
        costSummary: SyncCostSummary(
            sessionCostUSD: 0.92,
            sessionTokens: 9800,
            last30DaysCostUSD: 19.40,
            last30DaysTokens: 730_000,
            daily: makeDaily(
                baseCost: 0.65,
                tokenBase: 24500,
                modelMix: [("gpt-4.1", 0.58), ("gpt-4o", 0.42)])))

    // MARK: - iOS 1.7.0 / v0.26 preview providers

    static let kiroProvider = ProviderUsageSnapshot(
        providerID: "kiro",
        providerName: "Kiro",
        primary: nil,
        secondary: nil,
        accountEmail: "user-mock@kiro.test",
        loginMethod: "CLI",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-90),
        costSummary: SyncCostSummary(
            sessionCostUSD: 0.04,
            sessionTokens: 1_200,
            last30DaysCostUSD: 1.40,
            last30DaysTokens: 320_000,
            daily: makeDaily(baseCost: 0.05, tokenBase: 9_000, modelMix: [("kiro-sonnet", 1.0)])),
        rateWindows: [
            SyncRateWindow(
                id: "overage",
                label: "Overage",
                usedPercent: 24,
                windowMinutes: 43_200,
                resetsAt: Date().addingTimeInterval(86_400 * 11),
                resetDescription: nil),
        ],
        kiroCredits: SyncKiroCredits(
            planName: "Pro",
            creditsUsed: 320,
            creditsTotal: 1_000,
            creditsPercent: 32,
            bonusUsed: 45,
            bonusTotal: 200,
            bonusExpiryDays: 19,
            resetsAt: Date().addingTimeInterval(86_400 * 11)),
        details: [
            SyncProviderDetailSection(
                title: "Usage",
                rows: [
                    .init(label: "Plan", value: "Pro"),
                    .init(label: "Credits left", value: "680"),
                    .init(label: "Bonus credits left", value: "155"),
                    .init(label: "Overage cost", value: "$4.20"),
                    .init(label: "Context used", value: "42%"),
                    .init(label: "Tools", value: "18"),
                    .init(label: "Kiro responses", value: "126"),
                ]),
        ])

    static let bedrockProvider = ProviderUsageSnapshot(
        providerID: "bedrock",
        providerName: "AWS Bedrock",
        primary: nil,
        secondary: nil,
        accountEmail: "ops-mock@bedrock.test",
        loginMethod: "us-east-1",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-120),
        costSummary: SyncCostSummary(
            sessionCostUSD: 0.55,
            sessionTokens: 12_000,
            last30DaysCostUSD: 19.10,
            last30DaysTokens: 5_300_000,
            daily: makeDaily(baseCost: 0.80, tokenBase: 180_000, modelMix: [("anthropic.claude-3-5-sonnet", 0.75), ("amazon.titan", 0.25)])),
        bedrockCost: SyncBedrockCost(
            monthlySpendUSD: 19.10,
            monthlyBudgetUSD: 50.0,
            inputTokens: 4_200_000,
            outputTokens: 1_100_000,
            region: "us-east-1",
            budgetUsedPercent: 38.2,
            updatedAt: Date()))

    static let moonshotProvider = ProviderUsageSnapshot(
        providerID: "moonshot",
        providerName: "Moonshot / Kimi API",
        primary: SyncRateWindow(
            label: "Balance",
            usedPercent: 42,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: "Top-up · ¥58.40 left"),
        secondary: nil,
        accountEmail: "balance-mock@moonshot.test",
        loginMethod: "cn-default",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-60),
        costSummary: SyncCostSummary(
            sessionCostUSD: 0.06,
            sessionTokens: 2_400,
            last30DaysCostUSD: 1.20,
            last30DaysTokens: 200_000,
            daily: makeDaily(baseCost: 0.08, tokenBase: 6_800, modelMix: [("kimi-k2-instruct", 1.0)])),
        moonshotBalance: SyncMoonshotBalance(
            balanceAmount: 58.40,
            balanceCurrency: "CNY",
            region: "cn-default",
            updatedAt: Date()))

    static let zaiProvider: ProviderUsageSnapshot = {
        let cal = Calendar.current
        let now = Date()
        let xTime: [Date] = (0..<24).compactMap { offset in
            cal.date(byAdding: .hour, value: -23 + offset, to: now)
        }
        return ProviderUsageSnapshot(
            providerID: "zai",
            providerName: "z.ai",
            primary: SyncRateWindow(
                label: "Session",
                usedPercent: 28,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(3_600 * 3),
                resetDescription: "in 3h"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 42,
                windowMinutes: 10_080,
                resetsAt: Date().addingTimeInterval(86_400 * 4),
                resetDescription: "in 4 days"),
            accountEmail: "dev-mock@zai.test",
            loginMethod: "API",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date().addingTimeInterval(-30),
            zaiHourlyUsage: SyncZaiHourlyUsage(
                xTime: xTime,
                modelSeries: [
                    SyncZaiModelSeries(
                        modelName: "glm-4.6",
                        tokens: (0..<24).map { ($0 % 4 == 0) ? Int.random(in: 1_500...6_000) : nil }),
                    SyncZaiModelSeries(
                        modelName: "glm-4.6-plus",
                        tokens: (0..<24).map { ($0 % 3 == 1) ? Int.random(in: 800...3_000) : nil }),
                ]))
    }()

    static let openAIDashboardProvider = ProviderUsageSnapshot(
        providerID: "openai",
        providerName: "OpenAI API",
        primary: nil,
        secondary: nil,
        accountEmail: "team-mock@openai.test",
        loginMethod: "Admin API",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-180),
        costSummary: nil,
        openAIAPIDashboard: SyncOpenAIAPIDashboard(
            last30Days: SyncOpenAISummary(totalCostUSD: 142.33, totalRequests: 4_201, totalTokens: 1_234_567),
            last7Days: SyncOpenAISummary(totalCostUSD: 38.50, totalRequests: 1_103, totalTokens: 312_000),
            latestDay: SyncOpenAISummary(totalCostUSD: 5.21, totalRequests: 142, totalTokens: 45_321),
            dailyBuckets: (1...30).map { day in
                SyncOpenAIDailyBucket(
                    dayKey: String(format: "2026-04-%02d", day),
                    costUSD: Double.random(in: 0.5...8.0),
                    requests: Int.random(in: 50...300),
                    inputTokens: Int.random(in: 1_000...50_000),
                    cachedInputTokens: Int.random(in: 0...10_000),
                    outputTokens: Int.random(in: 200...10_000),
                    totalTokens: Int.random(in: 1_200...60_000))
            },
            topModels: [
                SyncOpenAIModelBreakdown(modelName: "gpt-5", requests: 2_100, totalTokens: 800_000, costUSD: 0),
                SyncOpenAIModelBreakdown(modelName: "gpt-5.5", requests: 1_400, totalTokens: 380_000, costUSD: 0),
                SyncOpenAIModelBreakdown(modelName: "gpt-4o-mini", requests: 540, totalTokens: 110_000, costUSD: 0),
            ],
            topLineItems: [
                SyncOpenAILineItem(name: "Completions", costUSD: 100.40),
                SyncOpenAILineItem(name: "Embeddings", costUSD: 22.10),
                SyncOpenAILineItem(name: "Audio", costUSD: 12.83),
            ]))

    static let antigravityMultiAccountProvider = ProviderUsageSnapshot(
        providerID: "antigravity",
        providerName: "Antigravity",
        primary: SyncRateWindow(
            label: "Weekly",
            usedPercent: 35,
            windowMinutes: 10_080,
            resetsAt: Date().addingTimeInterval(86_400 * 4),
            resetDescription: "in 4 days"),
        secondary: nil,
        accountEmail: "primary-mock@antigravity.test",
        loginMethod: "OAuth",
        statusMessage: nil,
        isError: false,
        lastUpdated: Date().addingTimeInterval(-45),
        antigravityAccounts: SyncMultiAccountList(
            accounts: [
                SyncMultiAccountEntry(email: "primary-mock@antigravity.test", isActive: true, expiresAt: Date().addingTimeInterval(3_600 * 12)),
                SyncMultiAccountEntry(email: "alt-mock@antigravity.test", isActive: false, expiresAt: Date().addingTimeInterval(3_600 * 36)),
            ],
            activeIndex: 0))

    static let sampleSnapshot = SyncedUsageSnapshot(
        providers: [
            claudeProvider, cursorProvider, openRouterProvider, chatGPTProvider,
            kiroProvider, bedrockProvider, moonshotProvider, zaiProvider,
            openAIDashboardProvider, antigravityMultiAccountProvider,
        ],
        syncTimestamp: Date().addingTimeInterval(-45),
        deviceName: "MacBook Pro",
        appVersion: "0.26.2",
        mobileVersion: "1.7.0")

    @MainActor
    static func makeSyncedUsageData() -> SyncedUsageData {
        let data = SyncedUsageData()
        data.snapshot = self.sampleSnapshot
        return data
    }

    @MainActor
    static func makeEmptyUsageData() -> SyncedUsageData {
        SyncedUsageData()
    }
}
