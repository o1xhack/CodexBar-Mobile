import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("v0.45 provider presentation")
struct V045ProviderPresentationTests {
    @Test
    func `canonical generic window labels map to localized semantic keys`() {
        #expect(ProviderWindowLabel.localizationKey(for: "Daily") == "v045_window_daily")
        #expect(ProviderWindowLabel.localizationKey(for: "Weekly") == "v045_window_weekly")
        #expect(ProviderWindowLabel.localizationKey(for: "5-hour") == "5-hour")
        #expect(ProviderWindowLabel.localizationKey(for: "Credits") == "Credits")
        #expect(ProviderWindowLabel.localizationKey(for: "Monthly") == "v045_window_monthly")
        #expect(ProviderWindowLabel.localizationKey(for: "Additional") == "v045_window_additional")
        #expect(ProviderWindowLabel.localizationKey(for: "5 hour limit") == "v045_window_5_hour_limit")
        #expect(ProviderWindowLabel.localizationKey(for: "Daily Routines") == "v045_window_daily_routines")
        #expect(ProviderWindowLabel.localizationKey(for: "Web Sonnet") == "v045_window_web_sonnet")
        #expect(ProviderWindowLabel.localizationKey(for: "Total") == "v052_window_total")
        #expect(ProviderWindowLabel.localizationKey(for: "Third Party") == "v052_window_third_party")
        #expect(ProviderWindowLabel.localizationKey(for: "On-demand") == "v052_window_on_demand")
        #expect(ProviderWindowLabel.localizationKey(for: "Provider custom lane") == nil)
        #expect(ProviderWindowLabel.localized("Provider custom lane", fallback: "Limit") == "Provider custom lane")
        #expect(ProviderWindowLabel.localized("Fable only", fallback: "Limit").contains("Fable"))
    }

    @Test
    func `v052 provider labels localize in all four languages`() {
        let expectations: [(locale: String, total: String, thirdParty: String, onDemand: String)] = [
            ("en", "Total", "Third Party", "On-demand"),
            ("ja", "合計", "サードパーティ", "オンデマンド"),
            ("zh-Hans", "总计", "第三方", "按需"),
            ("zh-Hant", "總計", "第三方", "隨選"),
        ]

        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            #expect(ProviderWindowLabel.localized("Total", fallback: "Limit", locale: locale) == expectation.total)
            #expect(ProviderWindowLabel.localized(
                "Third Party",
                fallback: "Limit",
                locale: locale) == expectation.thirdParty)
            #expect(ProviderWindowLabel.localized(
                "On-demand",
                fallback: "Limit",
                locale: locale) == expectation.onDemand)
        }
    }

    @Test
    func `sub2api mode and amount formatters preserve wallet semantics`() {
        #expect(Sub2APIUsageCard.modeLabel(kind: "wallet") == String(localized: "v045_mode_wallet"))
        #expect(Sub2APIUsageCard.modeLabel(kind: "subscription") == String(localized: "v045_mode_subscription"))
        #expect(ProviderAmountCard.title(kind: "balance") == String(localized: "v045_amount_balance_title"))
        #expect(ProviderAmountCard.title(kind: "spend") == String(localized: "v045_amount_spend_title"))
        #expect(!ProviderAmountCard.formattedAmount(12.5, currencyCode: "USD").isEmpty)
        #expect(ProviderAmountCard.localizedPeriod("Last 30 days") == String(localized: "v045_period_last_30_days"))
        #expect(ProviderAmountCard.localizedPeriod("Provider custom period") == "Provider custom period")
    }

    @Test(arguments: [
        (offline: true, dryRun: false, missingKeys: 0, status: "healthy", key: "v045_status_offline"),
        (offline: false, dryRun: true, missingKeys: 0, status: "healthy", key: "v045_status_dry_run"),
        (offline: false, dryRun: false, missingKeys: 1, status: "healthy", key: "v045_status_attention"),
        (offline: false, dryRun: false, missingKeys: 0, status: "healthy", key: "v045_status_active"),
    ])
    func `wayfinder status priority is stable`(
        input: (offline: Bool, dryRun: Bool, missingKeys: Int, status: String, key: String))
    {
        let usage = SyncWayfinderUsage(
            gatewayStatus: input.status,
            offline: input.offline,
            dryRun: input.dryRun,
            missingKeyCount: input.missingKeys,
            modelCount: 1,
            requests: 2,
            tokens: 3,
            realized: 1,
            baseline: 2,
            saved: 1,
            savedPercent: 50,
            priced: true,
            routes: [],
            averageDecisionMilliseconds: nil,
            updatedAt: .now)
        #expect(WayfinderUsageCard.statusLabel(for: usage) == String(localized: String.LocalizationValue(input.key)))
    }
}

@Suite("v0.49 generic detail presentation")
struct V049ProviderDetailPresentationTests {
    @Test
    func `generic details supersede only the matching legacy provider card`() {
        let migratedCards: [(String, LegacyProviderDetailCard)] = [
            ("kiro", .kiroCredits),
            ("zai", .zaiHourlyUsage),
            ("zoommate", .zoomMateCredits),
            ("openai", .openAIAPIDashboard),
            ("deepgram", .deepgramUsage),
            ("groq", .groqMetrics),
            ("openrouter", .openRouterStats),
            ("deepseek", .deepSeekUsage),
            ("sub2api", .sub2APIUsage),
            ("wayfinder", .wayfinderUsage),
            ("claude", .claudeAdminUsage),
            ("minimax", .miniMaxBilling),
        ]

        for (providerID, card) in migratedCards {
            #expect(ProviderDetailPresentationPolicy.shouldRenderLegacyCard(
                card,
                providerID: providerID,
                hasGenericDetails: false))
            #expect(!ProviderDetailPresentationPolicy.shouldRenderLegacyCard(
                card,
                providerID: providerID,
                hasGenericDetails: true))
        }

        // A provider-level details envelope must not hide another typed lane,
        // nor may a custom provider accidentally claim a bundled card lane.
        #expect(ProviderDetailPresentationPolicy.shouldRenderLegacyCard(
            .kiroCredits,
            providerID: "claude",
            hasGenericDetails: true))
        #expect(ProviderDetailPresentationPolicy.shouldRenderLegacyCard(
            .openRouterStats,
            providerID: "plugin:team-dashboard",
            hasGenericDetails: true))
    }

    @Test
    func `first party detail semantics and IBM Bob window localize in all four languages`() {
        let expectations: [(locale: String, bobcoin: String, summary: String, monthly: String)] = [
            ("en", "Bobcoin usage", "Usage summary", "Monthly Bobcoins"),
            ("ja", "Bobcoin 使用量", "使用量の概要", "月間 Bobcoin"),
            ("zh-Hans", "Bobcoin 用量", "用量概览", "每月 Bobcoin"),
            ("zh-Hant", "Bobcoin 用量", "用量概覽", "每月 Bobcoin"),
        ]

        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            #expect(ProviderDetailLocalization.localized(
                "Bobcoin usage",
                providerID: "ibmbob",
                locale: locale) == expectation.bobcoin)
            #expect(ProviderDetailLocalization.localized(
                "Usage summary",
                providerID: "openai",
                locale: locale) == expectation.summary)
            #expect(ProviderWindowLabel.localized(
                "Monthly Bobcoins",
                fallback: "Limit",
                locale: locale) == expectation.monthly)
        }
        #expect(ProviderWindowLabel.localizationKey(for: "Monthly Bobcoins") == "v049_window_monthly_bobcoins")
    }

    @Test
    func `custom plugin and dynamic first party labels remain verbatim`() {
        for identifier in ["en", "ja", "zh-Hans", "zh-Hant"] {
            let locale = Locale(identifier: identifier)
            #expect(ProviderDetailLocalization.localized(
                "Usage summary",
                providerID: "plugin:team-dashboard",
                locale: locale) == "Usage summary")
            #expect(ProviderDetailLocalization.localized(
                "Enterprise Team A",
                providerID: "ibmbob",
                locale: locale) == "Enterprise Team A")
            #expect(ProviderDetailLocalization.localized(
                "Usage summary",
                providerID: "ibmbob",
                context: .rowLabel(sectionTitle: "Bobcoin usage"),
                locale: locale) == "Usage summary")
            #expect(ProviderDetailLocalization.localized(
                "Models",
                providerID: "groq",
                context: .rowLabel(sectionTitle: "Models"),
                locale: locale) == "Models")
            #expect(ProviderDetailLocalization.localized(
                "Usage summary",
                providerID: "groq",
                context: .rowLabel(sectionTitle: "Usage summary"),
                locale: locale) == self.expectationsByLocale[identifier])
        }
    }

    private var expectationsByLocale: [String: String] {
        [
            "en": "Usage summary",
            "ja": "使用量の概要",
            "zh-Hans": "用量概览",
            "zh-Hant": "用量概覽",
        ]
    }
}
