import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("v0.74 provider presentation")
struct V074ProviderPresentationTests {
    private static func utc(_ year: Int, _ month: Int, _ day: Int, hour: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    @Test func `new provider detail labels localize in four languages`() {
        let expected: [(String, String, [String: String])] = [
            ("aerostack", "Monthly AI tokens", ["zh-Hans": "每月 AI Token", "zh-Hant": "每月 AI Token", "ja": "月間 AI トークン"]),
            ("aerostack", "Above allowance", ["zh-Hans": "超出额度", "zh-Hant": "超出額度", "ja": "割当量の超過分"]),
            ("cosmic", "Input tokens", ["zh-Hans": "输入 Token", "zh-Hant": "輸入 Token", "ja": "入力トークン"]),
            ("tavily", "Account plan", ["zh-Hans": "账户套餐", "zh-Hant": "帳戶方案", "ja": "アカウントプラン"]),
            ("exa", "API key this month (UTC)", ["zh-Hans": "本月 API 密钥 (UTC)", "zh-Hant": "本月 API 金鑰 (UTC)", "ja": "今月の API キー (UTC)"]),
            ("sailresearch", "Last 30 days spend", ["zh-Hans": "过去 30 天支出", "zh-Hant": "過去 30 天支出", "ja": "過去30日間の支出"]),
            ("sofya", "Available credits", ["zh-Hans": "可用额度", "zh-Hant": "可用額度", "ja": "利用可能なクレジット"]),
            ("xapi", "Free credits", ["zh-Hans": "免费额度", "zh-Hant": "免費額度", "ja": "無料クレジット"]),
            ("qwencloud", "Seats", ["zh-Hans": "席位", "zh-Hant": "席位", "ja": "シート"]),
            ("ollama", "Next refill", ["zh-Hans": "下次补充", "zh-Hant": "下次補充", "ja": "次回の補充"]),
            ("notion", "Personal credits", ["zh-Hans": "个人额度", "zh-Hant": "個人額度", "ja": "個人クレジット"]),
            ("xai", "Live remaining (est.)", ["zh-Hans": "实时剩余（估算）", "zh-Hant": "即時剩餘（估算）", "ja": "リアルタイム残高（推定）"]),
        ]
        for (provider, label, translations) in expected {
            #expect(ProviderDetailLocalization.localized(label, providerID: provider, locale: Locale(identifier: "en")) == label)
            for (language, value) in translations {
                #expect(
                    ProviderDetailLocalization.localized(label, providerID: provider, locale: Locale(identifier: language))
                        == value,
                    "\(provider) \(label) \(language)")
            }
        }
        // A custom plugin's identical label stays verbatim.
        #expect(ProviderDetailLocalization.localized(
            "Seats", providerID: "my-plugin", locale: Locale(identifier: "zh-Hans")) == "Seats")
    }

    @Test func `new provider values localize fixed states and credit amounts`() {
        let zh = Locale(identifier: "zh-Hans")
        #expect(ProviderDetailLocalization.localizedValue("Unlimited", providerID: "tavily", locale: zh) == "无限")
        #expect(ProviderDetailLocalization.localizedValue("Not reported", providerID: "cosmic", locale: zh) == "未提供")
        // Sail Research reports an unavailable organization balance with this fixed value.
        #expect(ProviderDetailLocalization.localizedValue("Unavailable", providerID: "sailresearch", locale: zh) == "不可用")
        #expect(ProviderDetailLocalization.localizedValue(
            "Unavailable", providerID: "sailresearch", locale: Locale(identifier: "ja"))
            == MobileLocalizedString.value("Unavailable", defaultValue: "Unavailable", locale: Locale(identifier: "ja")))
        #expect(ProviderDetailLocalization.localizedValue("$64.10", providerID: "sailresearch", locale: zh) == "$64.10")
        #expect(ProviderDetailLocalization.localizedValue("1,250 credits", providerID: "tinyapi", locale: zh) == "1,250 额度")
        #expect(ProviderDetailLocalization.localizedValue("120 / 500 credits used", providerID: "qwencloud", locale: zh)
            == "已用 120 / 500 额度")
        #expect(ProviderDetailLocalization.localizedValue(
            "120 / 500 credits used", providerID: "qwencloud", locale: Locale(identifier: "ja")) == "120 / 500 クレジット使用済み")
        #expect(ProviderDetailLocalization.localizedValue("Team", providerID: "qwencloud", locale: zh) == "团队")
        #expect(ProviderDetailLocalization.localizedValue("$7.25", providerID: "linkup", locale: zh) == "$7.25")
        #expect(ProviderDetailLocalization.localizedValue("Something new", providerID: "sofya", locale: zh) == "Something new")
    }

    @Test func `Notion allowance rows render credit and usage values in four languages`() {
        let row = SyncProviderDetailSection.Row(
            label: "Standard remaining", value: "1,365.33 credits", secondaryValue: "134.67 / 1,500 used")
        for (language, primary, secondary) in [
            ("en", "1,365.33 credits", "134.67 / 1,500 used"),
            ("zh-Hans", "1,365.33 额度", "已用 134.67 / 1,500"),
            ("zh-Hant", "1,365.33 額度", "已用 134.67 / 1,500"),
            ("ja", "1,365.33 クレジット", "134.67 / 1,500 使用済み"),
        ] {
            let presentation = ProviderDetailRowPresentation(
                providerID: "notion", row: row, sectionTitle: "Personal credits", locale: Locale(identifier: language))
            #expect(presentation.value == primary)
            #expect(presentation.secondaryValue == secondary)
        }

        let zh = Locale(identifier: "zh-Hans")
        #expect(ProviderDetailLocalization.localizedValue(
            "0 credits", providerID: "notion", sectionTitle: "Personal credits", locale: zh) == "0 额度")
        #expect(ProviderDetailLocalization.localizedValue(
            "workspace credits", providerID: "notion", sectionTitle: "Personal credits", locale: zh)
            == "workspace credits")
        #expect(ProviderDetailLocalization.localizedValue(
            "420 credits", providerID: "my-plugin", sectionTitle: "Personal credits", locale: zh) == "420 credits")
    }

    @Test func `new quota window labels localize`() {
        let ja = Locale(identifier: "ja")
        #expect(ProviderWindowLabel.localized("Team", fallback: "Session", providerID: "qwencloud", locale: ja)
            == MobileLocalizedString.value("Team", defaultValue: "Team", locale: ja))
        #expect(ProviderWindowLabel.localized("Output tokens", fallback: "Weekly", providerID: "cosmic", locale: ja)
            == "出力トークン")
        #expect(ProviderWindowLabel.localized("Plan credits", fallback: "Session", providerID: "tavily",
                                              locale: Locale(identifier: "zh-Hant")) == "方案額度")
    }

    @Test func `Google Developer cloud credit details and quota descriptions localize in four languages`() {
        let balance = "$7.50 of $10.00 left"
        let status = SyncProviderDetailSection.Row(
            label: "Status", value: "Not applied", secondaryValue: "me.developers.google.com/benefits")
        let granted = SyncProviderDetailSection.Row(label: "Granted", value: "2026-12-01")
        for (language, expectedStatus, expectedBalance, day, expiry) in [
            ("en", "Not applied", balance, "Dec 1, 2026", "Expires Dec 1, 2026"),
            ("zh-Hans", "未领取", "剩余 $7.50（共 $10.00）", "2026年12月1日", "2026年12月1日 到期"),
            ("zh-Hant", "未領取", "剩餘 $7.50（共 $10.00）", "2026年12月1日", "2026年12月1日 到期"),
            ("ja", "未適用", "残り $7.50 / $10.00", "2026年12月1日", "有効期限：2026年12月1日"),
        ] {
            let locale = Locale(identifier: language)
            let statusPresentation = ProviderDetailRowPresentation(
                providerID: "googledeveloper", row: status, sectionTitle: "Cloud credits", locale: locale)
            let grantPresentation = ProviderDetailRowPresentation(
                providerID: "googledeveloper", row: granted, sectionTitle: "Billing", locale: locale)
            #expect(statusPresentation.value == expectedStatus)
            #expect(statusPresentation.secondaryValue == "me.developers.google.com/benefits")
            #expect(grantPresentation.value == day)
            #expect(ProviderDetailLocalization.localizedValue(balance, providerID: "googledeveloper", locale: locale)
                == expectedBalance)
            #expect(ProviderDetailLocalization.localizedValue(
                balance + " · Expires 2026-12-01", providerID: "googledeveloper", locale: locale)
                == "\(expectedBalance) · \(expiry)")
        }

        let zh = Locale(identifier: "zh-Hans")
        #expect(ProviderDetailLocalization.localizedValue(
            "CHF 0.00 of CHF 10.00 left", providerID: "googledeveloper", locale: zh)
            == "剩余 CHF 0.00（共 CHF 10.00）")
        #expect(ProviderDetailLocalization.localizedValue(
            "Not applied", providerID: "googledeveloper", rowLabel: "Billing account", sectionTitle: "Billing", locale: zh)
            == "Not applied")
        #expect(ProviderDetailLocalization.localizedValue(
            "2026-02-30", providerID: "googledeveloper", rowLabel: "Granted", sectionTitle: "Billing", locale: zh)
            == "2026-02-30")
        #expect(ProviderDetailLocalization.localizedValue(
            balance, providerID: "my-plugin", locale: zh) == balance)
    }

    @Test func `the Mac's Claude credentials-changed error becomes phone guidance`() {
        let mac = "Claude Code credentials changed (Updated 5m ago). Click Refresh to re-grant CodexBar access."
        #expect(ProviderDetailLocalization.localizedStatusMessage(mac, isError: true, locale: Locale(identifier: "zh-Hans"))
            == "Mac 上的 Claude Code 凭证已变更。请在那台 Mac 上打开 CodexBar，点击“刷新”重新授权。")
        #expect(ProviderDetailLocalization.localizedStatusMessage(mac, isError: true, locale: Locale(identifier: "en"))
            == "Claude Code credentials changed on your Mac. Open CodexBar on that Mac and click Refresh to re-grant access.")
        // Only the error form is rewritten, and unrelated errors stay verbatim.
        #expect(ProviderDetailLocalization.localizedStatusMessage(mac, isError: false, locale: Locale(identifier: "zh-Hans"))
            == mac)
        #expect(ProviderDetailLocalization.localizedStatusMessage(
            "Claude OAuth credentials not found. Run `claude` to authenticate.",
            isError: true,
            locale: Locale(identifier: "zh-Hans")) == "Claude OAuth credentials not found. Run `claude` to authenticate.")
    }

    @Test func `calendar-day subscription dates show the same day in every time zone`() throws {
        let posix = Locale(identifier: "en_US_POSIX")
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let noon = try #require(ProviderUsageSnapshot.calendarDayDate("2026-11-03"))
        #expect(SubscriptionDateTimeZone.calendarDayString("2026-11-03", locale: posix) == formatter.string(from: noon))
        // The day string never shifts with the reader's zone; UTC calendar day 3 at noon is day 3 everywhere it is shown.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(utc.component(.day, from: noon) == 3)
        for bad in ["2026-02-30", "2026-11-3", "11/03/2026", "", "2026-13-01"] {
            #expect(ProviderUsageSnapshot.validCalendarDay(bad) == nil, "\(bad)")
            #expect(SubscriptionDateTimeZone.calendarDayString(bad) == nil, "\(bad)")
        }
        #expect(SubscriptionDateTimeZone.timeZone(providerID: "minimax", date: noon).identifier == "Asia/Shanghai")
        #expect(SubscriptionDateTimeZone.timeZone(providerID: "claude", date: noon) == .current)
    }

    @Test func `calendar-day subscription fields decode, validate, and survive the merge`() throws {
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let base: [String: Any] = [
            "providerID": "claude", "providerName": "Claude", "isError": false, "lastUpdated": "2026-10-14T00:00:00Z",
        ]
        func decode(_ extra: [String: Any]) throws -> ProviderUsageSnapshot {
            try decoder.decode(
                ProviderUsageSnapshot.self,
                from: JSONSerialization.data(withJSONObject: base.merging(extra) { $1 }))
        }
        #expect(try decode(["subscriptionRenewsOn": "2026-11-03"]).subscriptionRenewsOn == "2026-11-03")
        #expect(try decode(["subscriptionRenewsOn": "not-a-day"]).subscriptionRenewsOn == nil)
        #expect(try decode(["subscriptionRenewsOn": 42]).subscriptionRenewsOn == nil)
        // Payloads from older Macs have no key.
        #expect(try decode([:]).subscriptionRenewsOn == nil)

        let provider = try decode(["subscriptionRenewsOn": "2026-11-03"])
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([
            SyncedUsageSnapshot(
                providers: [provider], syncTimestamp: Date(timeIntervalSince1970: 1_791_500_000),
                deviceName: "Synthetic Mac A", deviceID: "mac-a"),
            SyncedUsageSnapshot(
                providers: [try decode([:])], syncTimestamp: Date(timeIntervalSince1970: 1_791_499_000),
                deviceName: "Synthetic Mac B", deviceID: "mac-b"),
        ]))
        #expect(merged.providers.first(where: { $0.providerID == "claude" })?.subscriptionRenewsOn == "2026-11-03")
    }
}
