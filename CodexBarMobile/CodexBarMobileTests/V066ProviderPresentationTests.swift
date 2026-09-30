import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Bundled plugin presentation")
struct V066ProviderPresentationTests {
    @Test
    func `every Aixy budget label fragment localizes in all four languages`() {
        for language in ["en", "zh-Hans", "zh-Hant", "ja"] {
            let locale = Locale(identifier: language)
            for scope in ["Organization", "Project", "Team", "User", "Key"] {
                for period in ["Daily", "Weekly", "Monthly", "Lifetime"] {
                    for sharing in ["Shared", "Personal"] {
                        for enforcement in ["Hard", "Monitor"] {
                            let fragments = [scope, period, sharing, enforcement]
                            let label = fragments.joined(separator: " · ")
                            let expected = fragments.map {
                                MobileLocalizedString.value($0, defaultValue: $0, locale: locale)
                            }.joined(separator: " · ")
                            #expect(ProviderDetailLocalization.localized(
                                label, providerID: "aixy", locale: locale) == expected)
                        }
                    }
                }
            }
        }
    }

    @Test
    func `Aixy fixed detail labels localize while dynamic plugin content stays verbatim`() {
        let expectations: [(locale: String, title: String, key: String, project: String, observed: String)] = [
            ("en", "Aixy key", "Key", "Project", "Observed"),
            ("zh-Hans", "Aixy 密钥", "密钥", "项目", "观测时间"),
            ("zh-Hant", "Aixy 金鑰", "金鑰", "專案", "觀測時間"),
            ("ja", "Aixy キー", "キー", "プロジェクト", "観測日時"),
        ]
        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            #expect(ProviderDetailLocalization.localized(
                "Aixy key", providerID: "aixy", locale: locale) == expectation.title)
            #expect(ProviderDetailLocalization.localized(
                "Key", providerID: "aixy", locale: locale) == expectation.key)
            #expect(ProviderDetailLocalization.localized(
                "Project", providerID: "aixy", locale: locale) == expectation.project)
            #expect(ProviderDetailLocalization.localized(
                "Observed", providerID: "aixy", locale: locale) == expectation.observed)
            #expect(ProviderDetailLocalization.localized(
                "customer project", providerID: "aixy", locale: locale) == "customer project")
            #expect(ProviderDetailLocalization.localized(
                "Key", providerID: "custom-plugin", locale: locale) == "Key")
        }
    }

    @Test
    func `new provider detail labels localize without changing custom labels`() {
        let expectations: [(locale: String, credits: String, characters: String, subscription: String)] = [
            ("en", "Credits", "Characters", "Subscription"),
            ("zh-Hans", "额度", "字符数", "订阅"),
            ("zh-Hant", "額度", "字元數", "訂閱"),
            ("ja", "クレジット", "文字数", "サブスクリプション"),
        ]
        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            #expect(ProviderDetailLocalization.localized(
                "Credits", providerID: "perplexity", locale: locale) == expectation.credits)
            #expect(ProviderDetailLocalization.localized(
                "Characters", providerID: "elevenlabs", locale: locale) == expectation.characters)
            #expect(ProviderDetailLocalization.localized(
                "Subscription", providerID: "nous", locale: locale) == expectation.subscription)
            #expect(ProviderDetailLocalization.localized(
                "Credits", providerID: "custom-plugin", locale: locale) == "Credits")
            #expect(ProviderDetailLocalization.localized(
                "Balance",
                providerID: "llmproxy",
                context: .rowLabel(sectionTitle: "Providers"),
                locale: locale) == "Balance")
            #expect(ProviderDetailLocalization.localized(
                "Other models",
                providerID: "bifrost",
                context: .rowLabel(sectionTitle: "Models"),
                locale: locale) == "Other models")
        }
    }

    @Test
    func `reviewed provider sections localize in all four languages`() {
        let expectations: [(locale: String, billing: String, hypercredits: String, loaded: String)] = [
            ("en", "Billing", "Hypercredits", "Loaded"),
            ("zh-Hans", "账单", "Hyper 额度", "已加载"),
            ("zh-Hant", "帳單", "Hyper 額度", "已載入"),
            ("ja", "請求", "Hyper クレジット", "読み込み済み"),
        ]
        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            for providerID in ["coderabbit", "replicate", "typesafe"] {
                #expect(ProviderDetailLocalization.localized(
                    "Billing", providerID: providerID, locale: locale) == expectation.billing)
            }
            #expect(ProviderDetailLocalization.localized(
                "Hypercredits", providerID: "hyper", locale: locale) == expectation.hypercredits)
            #expect(ProviderDetailLocalization.localized(
                "Loaded", providerID: "llmman", locale: locale) == expectation.loaded)
        }
    }

    @Test
    func `new provider dynamic labels remain verbatim`() {
        let locale = Locale(identifier: "zh-Hans")
        #expect(ProviderDetailLocalization.localized(
            "Spent (2026-09 billing)",
            providerID: "typesafe",
            context: .rowLabel(sectionTitle: "Billing"),
            locale: locale) == "支出（2026-09 billing）")
        #expect(ProviderDetailLocalization.localized(
            "Loaded",
            providerID: "llmman",
            context: .rowLabel(sectionTitle: "Loaded models"),
            locale: locale) == "Loaded")
        #expect(ProviderDetailLocalization.localized(
            "Loaded", providerID: "custom-plugin", locale: locale) == "Loaded")
        #expect(ProviderDetailLocalization.localizedValue(
            "Balance: $12.50", providerID: "typesafe", locale: locale) == "余额：$12.50")
        #expect(ProviderDetailLocalization.localizedValue(
            "Balance: $12.50", providerID: "typesafe", rowLabel: "Plan", locale: locale)
            == "Balance: $12.50")
    }

    @Test
    func `TypeSafe credit expiry keeps amounts and date in four languages`() {
        let expectations: [(locale: String, value: String)] = [
            ("en", "5 of 10, expires Sep 2"),
            ("zh-Hans", "5 / 10，Sep 2 到期"),
            ("zh-Hant", "5 / 10，Sep 2 到期"),
            ("ja", "5 / 10、有効期限 Sep 2"),
        ]
        for expectation in expectations {
            let locale = Locale(identifier: expectation.locale)
            #expect(ProviderDetailLocalization.localizedValue(
                "5 of 10, expires Sep 2",
                providerID: "typesafe",
                rowLabel: "Credit",
                locale: locale) == expectation.value)
            #expect(ProviderDetailLocalization.localizedValue(
                "5 of 10, expires Sep 2",
                providerID: "typesafe",
                rowLabel: "Plan",
                locale: locale) == "5 of 10, expires Sep 2")
        }
    }

    @Test
    func `new plugin values preserve counts and localize fixed words`() {
        let locale = Locale(identifier: "zh-Hans")
        #expect(ProviderDetailLocalization.localizedValue(
            "13/50 credits", providerID: "perplexity", locale: locale) == "13/50 额度")
        #expect(ProviderDetailLocalization.localizedValue(
            "4 / 10 credits used · Unlimited",
            providerID: "gitkraken",
            locale: locale) == "4 / 10 已用额度 · 无限")
        #expect(ProviderDetailLocalization.localizedValue(
            "Not included in this login response",
            providerID: "muse",
            rowLabel: "Quota",
            locale: locale) == "此登录响应未提供")
        #expect(ProviderDetailLocalization.localizedValue(
            "Not included in this login response",
            providerID: "muse",
            rowLabel: "Plan",
            locale: locale) == "Not included in this login response")
        #expect(ProviderDetailLocalization.localizedValue(
            "No allowance", providerID: "custom-plugin", locale: locale) == "No allowance")
        #expect(ProviderDetailLocalization.localizedValue(
            "5 credits", providerID: "llmproxy", locale: locale) == "5 credits")
        #expect(ProviderDetailLocalization.localizedValue(
            "Unlimited", providerID: "llmproxy", locale: locale) == "Unlimited")
        #expect(ProviderDetailLocalization.localized(
            "Weekly", providerID: "muse", locale: locale) == "每周")
        #expect(ProviderDetailLocalization.localizedValue(
            "Muse login", providerID: "muse", locale: locale) == "Muse 登录")
        #expect(ProviderDetailLocalization.localizedValue(
            "Muse login", providerID: "muse", rowLabel: "Plan", locale: locale) == "Muse login")
        #expect(ProviderDetailLocalization.localizedValue(
            "limit 1,200", providerID: "v0", rowLabel: "Rate-limit remaining", locale: locale) == "上限 1,200")
        #expect(ProviderDetailLocalization.localizedValue(
            "of 1,200", providerID: "v0", rowLabel: "Billing remaining", locale: locale) == "/ 1,200")
        #expect(ProviderDetailLocalization.localizedValue(
            "Unavailable", providerID: "v0", rowLabel: "Rate-limit remaining", locale: locale) == "不可用")
        #expect(ProviderDetailLocalization.localizedValue(
            "of demo", providerID: "v0", rowLabel: "Scope", locale: locale) == "of demo")
        #expect(ProviderDetailLocalization.localizedValue(
            "Unavailable", providerID: "v0", rowLabel: "Scope", locale: locale) == "Unavailable")
        #expect(ProviderDetailLocalization.localizedValue(
            "Quarterly", providerID: "bifrost", locale: locale) == "每季度")
    }

    @Test
    func `Bifrost summary localizes while a real model name stays verbatim`() {
        let rows = [
            SyncProviderDetailSection.Row(label: "Other models", value: "model quota"),
            SyncProviderDetailSection.Row(label: "Model 2", value: "quota"),
            SyncProviderDetailSection.Row(label: "Model 3", value: "quota"),
            SyncProviderDetailSection.Row(label: "Model 4", value: "quota"),
            SyncProviderDetailSection.Row(label: "Model 5", value: "quota"),
            SyncProviderDetailSection.Row(label: "Other models", value: "3"),
        ]
        let section = SyncProviderDetailSection(title: "Models", rows: rows)
        let locale = Locale(identifier: "zh-Hans")
        let realModel = ProviderDetailLocalization.rowContext(
            providerID: "bifrost", section: section, row: rows[0], index: 0)
        let summary = ProviderDetailLocalization.rowContext(
            providerID: "bifrost", section: section, row: rows[5], index: 5)
        #expect(ProviderDetailLocalization.localized(
            rows[0].label, providerID: "bifrost", context: realModel, locale: locale) == "Other models")
        #expect(ProviderDetailLocalization.localized(
            rows[5].label, providerID: "bifrost", context: summary, locale: locale) == "其他模型")
    }

    @Test
    func `account tab fallback localizes when account identity is absent`() {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 0))
        let group = ProviderAccountGroup(
            providerID: "codex", providerName: "Codex", accounts: [provider, provider])
        #expect(group.tabLabel(forIndex: 1, locale: Locale(identifier: "en")) == "Account 2")
        #expect(group.tabLabel(forIndex: 1, locale: Locale(identifier: "zh-Hans")) == "账户 2")
        #expect(group.tabLabel(forIndex: 1, locale: Locale(identifier: "ja")) == "アカウント 2")
        for (providerID, login, expected) in [
            ("v0", "API key", "API 密钥"),
            ("nous", "Subscription", "订阅"),
            ("helmcode", "Dashboard session", "控制台会话"),
            ("hyper", "Browser session", "浏览器会话"),
            ("llmman", "Local daemon", "本地后台服务"),
        ] {
            let account = ProviderUsageSnapshot(
                providerID: providerID,
                providerName: providerID,
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: login,
                statusMessage: nil,
                isError: false,
                lastUpdated: Date(timeIntervalSince1970: 0))
            let group = ProviderAccountGroup(
                providerID: providerID, providerName: providerID, accounts: [account, account])
            #expect(group.tabLabel(forIndex: 0, locale: Locale(identifier: "zh-Hans")) == expected)
        }
    }
}
