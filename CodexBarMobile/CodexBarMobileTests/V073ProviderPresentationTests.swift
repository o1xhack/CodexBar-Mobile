import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("v0.73 provider presentation")
struct V073ProviderPresentationTests {
    @Test func `Langdock included-limits row localizes in four languages`() {
        let expected: [(String, String, String)] = [
            ("en", "Included limits", "No included usage limits available"),
            ("zh-Hans", "套餐内额度", "没有可用的套餐内用量额度"),
            ("zh-Hant", "方案內額度", "沒有可用的方案內用量額度"),
            ("ja", "プラン内の上限", "利用可能なプラン内の使用上限はありません"),
        ]
        for (language, label, value) in expected {
            let locale = Locale(identifier: language)
            #expect(ProviderDetailLocalization.localized("Included limits", providerID: "langdock", locale: locale) == label)
            #expect(ProviderDetailLocalization.localizedValue(
                "No included usage limits available",
                providerID: "langdock",
                rowLabel: "Included limits",
                locale: locale) == value)
        }
        #expect(ProviderDetailLocalization.localizedValue(
            "Something new", providerID: "langdock", locale: Locale(identifier: "zh-Hans")) == "Something new")
    }

    @Test func `the Mac's limits note is localized and other status text stays verbatim`() {
        let note = SyncStatusNote.limitsUnavailable
        #expect(ProviderDetailLocalization.localizedStatusMessage(
            note, isError: false, locale: Locale(identifier: "zh-Hans")) == "这台 Mac 上无法获取此账号的用量额度。")
        #expect(ProviderDetailLocalization.localizedStatusMessage(
            note, isError: false, locale: Locale(identifier: "ja")) == "この Mac では、このアカウントの使用上限を取得できません。")
        #expect(ProviderDetailLocalization.localizedStatusMessage(
            note, isError: true, locale: Locale(identifier: "zh-Hans")) == note)
        #expect(ProviderDetailLocalization.localizedStatusMessage(
            "Cookie expired", isError: false, locale: Locale(identifier: "zh-Hans")) == "Cookie expired")
    }
}

