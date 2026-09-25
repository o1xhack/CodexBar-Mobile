import Testing
@testable import CodexBarCore

struct SharedSettingsReaderTests {
    @Test
    func `cleaned environment aliases preserve ordered fallback`() {
        #expect(DeepInfraSettingsReader.apiKey(environment: [
            "DEEPINFRA_API_KEY": " ' ' ", "DEEPINFRA_TOKEN": " 'fallback' ",
        ]) == "fallback")
        #expect(FireworksSettingsReader.apiKey(environment: [
            "CODEXBAR_FIREWORKS_API_KEY": "\" \"", "FIREWORKS_API_KEY": " first ", "FIREWORKS_KEY": "last",
        ]) == "first")
        #expect(FireworksSettingsReader.accountSlug(environment: [
            "CODEXBAR_FIREWORKS_ACCOUNT_SLUG": "''", "FIREWORKS_ACCOUNT_SLUG": " 'account' ",
        ]) == "account")
        #expect(AlibabaCodingPlanSettingsReader.apiToken(environment: [
            "ALIBABA_CODING_PLAN_API_KEY": "''", "ALIBABA_QWEN_API_KEY": " qwen ", "DASHSCOPE_API_KEY": "last",
        ]) == "qwen")
        #expect(MiniMaxAPISettingsReader.apiToken(environment: [
            "MINIMAX_CODING_API_KEY": "''", "MINIMAX_API_KEY": " standard ",
        ]) == "standard")
    }

    @Test(arguments: ["1", " TRUE ", "'yes'", "\"On\""])
    func `strict endpoint policy accepts existing truthy spellings`(value: String) {
        #expect(AlibabaCodingPlanSettingsReader.rejectedEndpointOverrideKey(environment: [
            AlibabaCodingPlanSettingsReader.requireProviderEndpointOverridesKey: value,
            AlibabaCodingPlanSettingsReader.hostKey: "custom.example",
        ]) == AlibabaCodingPlanSettingsReader.hostKey)
        #expect(MiniMaxSettingsReader.rejectedEndpointOverrideKey(environment: [
            MiniMaxSettingsReader.requireProviderEndpointOverridesKey: value,
            MiniMaxSettingsReader.remainsURLKey: "https://custom.example/remains",
        ]) == MiniMaxSettingsReader.remainsURLKey)
    }

    @Test(arguments: ["", "false", "0", "unknown"])
    func `other endpoint policy values preserve custom https overrides`(value: String) {
        #expect(AlibabaCodingPlanSettingsReader.rejectedEndpointOverrideKey(environment: [
            AlibabaCodingPlanSettingsReader.requireProviderEndpointOverridesKey: value,
            AlibabaCodingPlanSettingsReader.hostKey: "custom.example",
        ]) == nil)
        #expect(MiniMaxSettingsReader.rejectedEndpointOverrideKey(environment: [
            MiniMaxSettingsReader.requireProviderEndpointOverridesKey: value,
            MiniMaxSettingsReader.remainsURLKey: "https://custom.example/remains",
        ]) == nil)
    }

    @Test
    func `invalid overrides remain visible in declared key order`() {
        let alibaba = [
            AlibabaCodingPlanSettingsReader.hostKey: "http://custom.example",
            AlibabaCodingPlanSettingsReader.quotaURLKey: "http://custom.example/quota",
        ]
        #expect(AlibabaCodingPlanSettingsReader.hostOverride(environment: alibaba) == nil)
        #expect(AlibabaCodingPlanSettingsReader.rejectedEndpointOverrideKey(environment: alibaba)
            == AlibabaCodingPlanSettingsReader.hostKey)
        let minimax = [
            MiniMaxSettingsReader.hostKey: "''",
            MiniMaxSettingsReader.codingPlanURLKey: "https://custom.example/plan",
            MiniMaxSettingsReader.remainsURLKey: "http://custom.example/remains",
            MiniMaxSettingsReader.billingHistoryURLKey: "http://custom.example/billing",
        ]
        #expect(MiniMaxSettingsReader.remainsURL(environment: minimax) == nil)
        #expect(MiniMaxSettingsReader.rejectedEndpointOverrideKey(environment: minimax)
            == MiniMaxSettingsReader.remainsURLKey)
        let proxy = [LLMProxySettingsReader.baseURLEnvironmentKey: "http://public.example"]
        #expect(LLMProxySettingsReader.hasBaseURLOverride(environment: proxy))
        #expect(LLMProxySettingsReader.baseURL(environment: proxy) == nil)
    }
}
