import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("iOS 1.23 v0.56 synced provider semantics")
struct V056SyncSemanticsTests {
    private struct LocalizationExpectation {
        let locale: String
        let plan: String
        let credits: String
        let overage: String
        let tools: String
        let enabled: String
        let creditValue: String
        let capValue: String
        let bonusValue: String
        let overageWindow: String
        let offlineOne: String
        let offlineMany: String
    }

    private static let encoder = CloudSyncConstants.makeJSONEncoder()
    private static let decoder = CloudSyncConstants.makeJSONDecoder()
    private static let timestamp = Date(timeIntervalSince1970: 1_788_000_000)

    @Test
    func `pre-v056 payload keeps additive compatibility defaults`() throws {
        let payload = Data(
            """
            {
              "providerID":"legacy-provider",
              "providerName":"Legacy Provider",
              "primary":null,
              "secondary":null,
              "accountEmail":null,
              "loginMethod":null,
              "statusMessage":null,
              "isError":false,
              "lastUpdated":"2026-08-01T00:00:00Z"
            }
            """.utf8)

        let provider = try Self.decoder.decode(ProviderUsageSnapshot.self, from: payload)
        #expect(provider.rateWindows.isEmpty)
        #expect(provider.details.isEmpty)
        #expect(provider.costSummary == nil)
        #expect(provider.providerAmount == nil)
    }

    @Test
    func `v056 provider signals round trip through the unchanged payload envelope`() throws {
        let providers = [
            Self.cursorFixture,
            Self.kiroFixture,
            Self.fireworksFixture,
            Self.antigravityFixture,
        ]
        let snapshot = SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: Self.timestamp,
            deviceName: "v056-mac",
            deviceID: "v056-mac-a",
            appVersion: "0.56.0.1",
            mobileVersion: "1.23.0",
            notificationPushEnabled: true)

        let payload = try Self.encoder.encode(snapshot)
        let decoded = try Self.decoder.decode(SyncedUsageSnapshot.self, from: payload)

        #expect(decoded.providers == providers)
        #expect(decoded.providers.first { $0.providerID == "cursor" }?.rateWindows.last?.label == "Grok Bot")
        #expect(decoded.providers.first { $0.providerID == "kiro" }?.details.first?.rows.count == 6)
        #expect(decoded.providers.first { $0.providerID == "fireworks" }?.providerAmount?.kind == "spend")
    }

    @Test
    func `partial and token-only cost never becomes authoritative zero`() throws {
        let cursor = try Self.roundTripped(Self.cursorFixture)
        let antigravity = try Self.roundTripped(Self.antigravityFixture)
        let cursorCost = try #require(cursor.costSummary)
        let antigravityCost = try #require(antigravity.costSummary)

        #expect(cursorCost.last30DaysCostUSD == 8.40)
        #expect(cursorCost.hasIncompleteHistoricalCostCoverage(at: Self.timestamp))
        #expect(cursorCost.completeHistoryCostUSD(at: Self.timestamp) == nil)
        #expect(antigravityCost.sessionCostUSD == nil)
        #expect(antigravityCost.last30DaysCostUSD == nil)
        #expect(antigravityCost.daily.first?.costIsKnown == false)
        #expect(antigravityCost.daily.first?.totalTokens == 12345)
        #expect(antigravityCost.completeHistoryCostUSD(at: Self.timestamp) == nil)
    }

    @Test
    func `Kiro stable labels localize while Cursor dynamic lane stays verbatim`() {
        let expectations: [LocalizationExpectation] = [
            .init(
                locale: "en", plan: "Plan", credits: "Credits left", overage: "Overage cost", tools: "Tools",
                enabled: "Enabled", creditValue: "3603.49 credits", capValue: "of 10000",
                bonusValue: "of 200 · expires in 19 days", overageWindow: "Overage",
                offlineOne: "Offline · 1 conversation", offlineMany: "Offline · 12 conversations"),
            .init(
                locale: "ja", plan: "プラン", credits: "残りクレジット", overage: "超過コスト", tools: "ツール",
                enabled: "有効", creditValue: "3603.49 クレジット", capValue: "/ 10000",
                bonusValue: "/ 200 · あと19日で期限切れ", overageWindow: "超過分",
                offlineOne: "オフライン · 1 件の会話", offlineMany: "オフライン · 12 件の会話"),
            .init(
                locale: "zh-Hans", plan: "套餐", credits: "剩余额度", overage: "超额费用", tools: "工具",
                enabled: "已启用", creditValue: "3603.49 额度", capValue: "/ 10000",
                bonusValue: "/ 200 · 19 天后过期", overageWindow: "超额用量",
                offlineOne: "离线 · 1 个对话", offlineMany: "离线 · 12 个对话"),
            .init(
                locale: "zh-Hant", plan: "方案", credits: "剩餘額度", overage: "超額費用", tools: "工具",
                enabled: "已啟用", creditValue: "3603.49 額度", capValue: "/ 10000",
                bonusValue: "/ 200 · 19 天後過期", overageWindow: "超額用量",
                offlineOne: "離線 · 1 個對話", offlineMany: "離線 · 12 個對話"),
        ]

        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            #expect(ProviderDetailLocalization.localized(
                "Plan",
                providerID: "kiro",
                locale: locale) == expectation.plan)
            #expect(ProviderDetailLocalization.localized(
                "Credits left",
                providerID: "kiro",
                locale: locale) == expectation.credits)
            #expect(ProviderDetailLocalization.localized(
                "Overage cost",
                providerID: "kiro",
                locale: locale) == expectation.overage)
            #expect(ProviderDetailLocalization.localized(
                "Tools",
                providerID: "kiro",
                locale: locale) == expectation.tools)
            #expect(ProviderDetailLocalization.localizedValue(
                "Enabled",
                providerID: "kiro",
                locale: locale) == expectation.enabled)
            #expect(ProviderDetailLocalization.localizedValue(
                "3603.49 credits",
                providerID: "kiro",
                locale: locale) == expectation.creditValue)
            #expect(ProviderDetailLocalization.localizedValue(
                "of 10000",
                providerID: "kiro",
                locale: locale) == expectation.capValue)
            #expect(ProviderDetailLocalization.localizedValue(
                "of 200 · expires in 19d",
                providerID: "kiro",
                locale: locale) == expectation.bonusValue)
            #expect(ProviderDetailLocalization.localizedValue(
                "of 10000",
                providerID: "custom-plugin",
                locale: locale) == "of 10000")
            #expect(ProviderWindowLabel.localized(
                "Grok Bot",
                fallback: "Limit",
                providerID: "cursor",
                locale: locale) == "Grok Bot")
            #expect(ProviderWindowLabel.localized(
                "Overage",
                fallback: "Limit",
                providerID: "kiro",
                locale: locale) == expectation.overageWindow)
            #expect(ProviderWindowLabel.localized(
                "Offline · 1 conversation",
                fallback: "Limit",
                providerID: "antigravity",
                locale: locale) == expectation.offlineOne)
            #expect(ProviderWindowLabel.localized(
                "Offline · 12 conversations",
                fallback: "Limit",
                providerID: "antigravity",
                locale: locale) == expectation.offlineMany)
            #expect(ProviderWindowLabel.localized(
                "Offline · 12 conversations",
                fallback: "Limit",
                providerID: "custom-plugin",
                locale: locale) == "Offline · 12 conversations")
            #expect(ProviderWindowLabel.localized(
                "Overage",
                fallback: "Limit",
                providerID: "custom-plugin",
                locale: locale) == "Overage")
        }

        #expect(ProviderDetailLocalization.localizedValue(
            "expires in 1d",
            providerID: "kiro",
            locale: Locale(identifier: "zh-Hans")) == "1 天后过期")
        #expect(ProviderDetailLocalization.localizedValue(
            "expires in 0d",
            providerID: "kiro",
            locale: Locale(identifier: "ja")) == "期限切れ")
    }

    @Test
    func `OpenRouter and z ai stable detail fragments localize in all four languages`() {
        let expectations: [(
            locale: String,
            keyLimit: String,
            spendHistory: String,
            spendingCap: String,
            noLimit: String,
            unavailable: String,
            timeout: String,
            invalid: String,
            failed: String,
            responseUnavailable: String,
            managementRequired: String,
            managementNotConfigured: String,
            httpFailure: String,
            rate: String,
            balance: String,
            balanceBreakdown: String)] = [
                (
                    "en", "API key limit", "Spend history", "Spending cap, not balance", "No limit configured",
                    "Unavailable right now", "Request timed out", "Response was invalid", "Request failed",
                    "Response was unavailable", "Management API key required", "Management API key not configured",
                    "Request returned HTTP 403", "100 requests / 10s", "Account balance",
                    "recharged ¥20.00 · granted ¥5.00 · spent ¥7.00"),
                (
                    "ja", "API キー上限", "支出履歴", "残高ではなく利用上限", "上限未設定",
                    "現在利用できません", "リクエストがタイムアウトしました", "応答が無効でした",
                    "リクエストに失敗しました", "応答を取得できませんでした", "管理 API キーが必要です",
                    "管理 API キーが設定されていません", "リクエストが HTTP 403 を返しました",
                    "100 件のリクエスト / 10s", "アカウント残高", "入金 ¥20.00 · 付与 ¥5.00 · 利用済み ¥7.00"),
                (
                    "zh-Hans", "API 密钥限额", "支出历史", "消费上限，并非余额", "未设置限额",
                    "当前不可用", "请求超时", "响应无效", "请求失败", "无法获取响应", "需要管理 API 密钥",
                    "未配置管理 API 密钥", "请求返回 HTTP 403", "100 个请求 / 10s", "账户余额",
                    "充值 ¥20.00 · 赠送 ¥5.00 · 已消费 ¥7.00"),
                (
                    "zh-Hant", "API 金鑰限額", "支出歷史", "消費上限，並非餘額", "未設定限額",
                    "目前無法使用", "請求逾時", "回應無效", "請求失敗", "無法取得回應", "需要管理 API 金鑰",
                    "未設定管理 API 金鑰", "請求傳回 HTTP 403", "100 個請求 / 10s", "帳戶餘額",
                    "儲值 ¥20.00 · 贈送 ¥5.00 · 已消費 ¥7.00"),
            ]

        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            #expect(ProviderDetailLocalization.localized(
                "API key limit",
                providerID: "openrouter",
                locale: locale) == expectation.keyLimit)
            #expect(ProviderDetailLocalization.localized(
                "Spend history",
                providerID: "openrouter",
                locale: locale) == expectation.spendHistory)
            #expect(ProviderDetailLocalization.localizedValue(
                "Spending cap, not balance",
                providerID: "openrouter",
                locale: locale) == expectation.spendingCap)
            #expect(ProviderDetailLocalization.localizedValue(
                "No limit configured",
                providerID: "openrouter",
                locale: locale) == expectation.noLimit)
            #expect(ProviderDetailLocalization.localizedValue(
                "Unavailable right now",
                providerID: "openrouter",
                locale: locale) == expectation.unavailable)
            #expect(ProviderDetailLocalization.localizedValue(
                "Request timed out",
                providerID: "openrouter",
                locale: locale) == expectation.timeout)
            #expect(ProviderDetailLocalization.localizedValue(
                "Response was invalid",
                providerID: "openrouter",
                locale: locale) == expectation.invalid)
            #expect(ProviderDetailLocalization.localizedValue(
                "Request failed",
                providerID: "openrouter",
                locale: locale) == expectation.failed)
            #expect(ProviderDetailLocalization.localizedValue(
                "Response was unavailable",
                providerID: "openrouter",
                locale: locale) == expectation.responseUnavailable)
            #expect(ProviderDetailLocalization.localizedValue(
                "Management API key required",
                providerID: "openrouter",
                locale: locale) == expectation.managementRequired)
            #expect(ProviderDetailLocalization.localizedValue(
                "Management API key not configured",
                providerID: "openrouter",
                locale: locale) == expectation.managementNotConfigured)
            #expect(ProviderDetailLocalization.localizedValue(
                "Request returned HTTP 403",
                providerID: "openrouter",
                locale: locale) == expectation.httpFailure)
            #expect(ProviderDetailLocalization.localizedValue(
                "100 requests / 10s",
                providerID: "openrouter",
                locale: locale) == expectation.rate)
            #expect(ProviderDetailLocalization.localized(
                "Account balance",
                providerID: "zai",
                locale: locale) == expectation.balance)
            #expect(ProviderDetailLocalization.localizedValue(
                "recharged ¥20.00 · granted ¥5.00 · spent ¥7.00",
                providerID: "zai",
                locale: locale) == expectation.balanceBreakdown)
        }

        #expect(ProviderDetailLocalization.localized(
            "API key limit",
            providerID: "custom-plugin") == "API key limit")
        #expect(ProviderDetailLocalization.localizedValue(
            "Unavailable right now",
            providerID: "custom-plugin") == "Unavailable right now")
        #expect(ProviderDetailLocalization.localizedValue(
            "recharged custom value · provider-defined detail",
            providerID: "zai",
            locale: Locale(identifier: "zh-Hans")) == "recharged custom value · provider-defined detail")
    }

    private static func roundTripped(_ provider: ProviderUsageSnapshot) throws -> ProviderUsageSnapshot {
        try self.decoder.decode(ProviderUsageSnapshot.self, from: self.encoder.encode(provider))
    }

    private static var cursorFixture: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "cursor",
            providerName: "Cursor",
            primary: nil,
            secondary: nil,
            accountEmail: "cursor@example.test",
            loginMethod: "Browser",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.timestamp,
            costSummary: SyncCostSummary(
                sessionCostUSD: 1.20,
                sessionTokens: 5000,
                last30DaysCostUSD: 8.40,
                last30DaysTokens: 90000,
                daily: [SyncDailyPoint(
                    dayKey: "2026-08-28",
                    costUSD: 1.20,
                    totalTokens: 5000,
                    costIsKnown: true)],
                costProvenance: .mixed,
                coverage: SyncCostCoverage(priced: 8, unpriced: 1, unmetered: 0, estimated: 2),
                historyCoverageIsEstablished: true,
                historyWindowIsComparable: true),
            rateWindows: [
                SyncRateWindow(
                    id: "total",
                    label: "Total",
                    usedPercent: 31,
                    windowMinutes: 43200,
                    resetsAt: nil,
                    resetDescription: nil),
                SyncRateWindow(
                    id: "grok-bot",
                    label: "Grok Bot",
                    usedPercent: 12,
                    windowMinutes: 43200,
                    resetsAt: nil,
                    resetDescription: nil),
            ])
    }

    private static var kiroFixture: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "kiro",
            providerName: "Kiro",
            primary: nil,
            secondary: nil,
            accountEmail: "kiro@example.test",
            loginMethod: "CLI",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.timestamp,
            rateWindows: [SyncRateWindow(
                id: "overage",
                label: "Overage",
                usedPercent: 24,
                windowMinutes: 43200,
                resetsAt: nil,
                resetDescription: nil)],
            details: [SyncProviderDetailSection(
                title: "Usage",
                rows: [
                    .init(label: "Plan", value: "Pro"),
                    .init(label: "Credits left", value: "680"),
                    .init(label: "Bonus credits left", value: "155"),
                    .init(label: "Overage cost", value: "$4.20"),
                    .init(label: "Context used", value: "42%"),
                    .init(label: "Tools", value: "18"),
                ])])
    }

    private static var fireworksFixture: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "fireworks",
            providerName: "Fireworks AI",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "API key",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.timestamp,
            providerAmount: SyncProviderAmount(
                kind: "spend",
                amount: 42.50,
                currencyCode: "USD",
                period: "Last 30 days",
                isEstimated: false))
    }

    private static var antigravityFixture: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "antigravity",
            providerName: "Antigravity",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Local logs",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.timestamp,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: 12345,
                last30DaysCostUSD: nil,
                last30DaysTokens: 12345,
                daily: [SyncDailyPoint(
                    dayKey: "2026-08-28",
                    costUSD: 0,
                    totalTokens: 12345,
                    costIsKnown: false)],
                costProvenance: .unknown,
                coverage: SyncCostCoverage(priced: 0, unpriced: 0, unmetered: 1, estimated: 0),
                historyCoverageIsEstablished: true,
                historyWindowIsComparable: true))
    }
}
