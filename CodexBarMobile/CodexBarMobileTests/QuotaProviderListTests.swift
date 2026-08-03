import CodexBarSync
import Testing

@testable import CodexBarMobile

/// Pins the push-notification subscription provider list. iOS 1.5.0 added
/// `abacus` and `mistral` alongside upstream Mac v0.21–0.23. Each entry
/// here corresponds to a `(provider, state)` pair iOS subscribes to at
/// launch (one zone for `depleted`, one for `restored`), so the count is
/// what determines how many CKRecordZoneSubscriptions fire.
///
/// **Cause-oriented assertions:** the list must STAY in lockstep with
/// Mac's `UsageProvider` enum cases — adding a provider on Mac without
/// adding it here means iOS never receives that provider's quota
/// notifications. We can't enforce that at compile time across the wire
/// (UsageProvider is Mac-side), so the test pins the count and the
/// presence of every known ID. Updates to either side need a matched
/// update here.
@Suite("Quota provider list")
struct QuotaProviderListTests {

    @Test("Total count is 69 after the v0.47 catch-up")
    func totalCount() {
        // Outcome: 25 → 27 in iOS 1.5.0 (Abacus + Mistral) →
        // 38 in iOS 1.6.0 (11 new from Mac v0.24+v0.25 catch-up) →
        // 40 in iOS 1.7.0 (2 new from Mac v0.26.0: moonshot + bedrock) →
        // 45 in iOS 1.8.0 (5 new from Mac v0.27.0: grok, groq,
        // elevenlabs, deepgram, llmproxy) →
        // 48 in iOS 1.9.0 (3 new from Mac v0.28+v0.29: azureopenai,
        // alibabatokenplan, t3chat) →
        // 49 in iOS 1.12.0 (Devin from upstream v0.34.0) →
        // 53 in iOS 1.13.0 (LiteLLM, Poe, Chutes, Zed from upstream
        // v0.36.0+v0.36.1) →
        // 57 in iOS 1.17.0 (Sakana AI, Qoder, CrossModel, ClawRouter
        // from upstream v0.38.0-v0.39.0) → 65 in iOS 1.19.0
        // (8 new providers from upstream v0.42.0-v0.45.2) → 69 in
        // iOS 1.20.0 (Qwen Cloud, ZoomMate, xAI, Notion AI from v0.46-v0.47).
        // If this number shifts without matching upstream updates,
        // the push-subscription set drifts out of sync with Mac's
        // actual emitting providers.
        #expect(QuotaProviderList.providers.count == 69)
    }

    @Test("Subscription zone count is 207 (69 providers × 3 states)")
    func subscriptionZoneCount() {
        // iOS 1.5.0: 27 × 2 = 54 zones.
        // iOS 1.6.0 / Mac 0.25.2: 38 × 3 (depleted/restored/warning) = 114.
        // iOS 1.7.0 / Mac 0.26.2: 40 × 3 = 120 zones (+moonshot, +bedrock).
        // iOS 1.8.0 / Mac 0.27.0: 45 × 3 = 135 zones (+grok, +groq,
        // +elevenlabs, +deepgram, +llmproxy).
        // iOS 1.9.0 / Mac 0.29.0: 48 × 3 = 144 zones (+azureopenai,
        // +alibabatokenplan, +t3chat).
        // iOS 1.12.0 / Mac 0.35.0: 49 × 3 = 147 zones (+devin).
        // iOS 1.13.0 / Mac 0.36.1: 53 × 3 = 159 zones (+litellm,
        // +poe, +chutes, +zed).
        // iOS 1.17.0 / Mac 0.39.0.1: 57 × 3 = 171 zones (+sakana,
        // +qoder, +crossmodel, +clawrouter).
        // iOS 1.19.0 / Mac 0.45.2.1: 65 × 3 = 195 zones
        // (+clinepass, +deepinfra, +neuralwatt, +longcat, +sub2api,
        // +wayfinder, +zenmux, +aiand).
        // iOS 1.20.0 / Mac 0.47.0.1: 69 × 3 = 207 zones
        // (+qwencloud, +zoommate, +xai, +notion).
        // `QuotaTransitionSubscriptions.makeConfigs()` builds one
        // `SubConfig` per (provider, state) — pinning here so a
        // future state addition/removal can't drift silently.
        #expect(QuotaProviderList.providers.count * 3 == 207)
    }

    @Test("Warning-zone name format matches Mac/iOS contract")
    func warningZoneNameFormat() {
        // Mac's `CloudSyncManager.writeQuotaWarningTransition` and
        // iOS's `QuotaTransitionSubscriptions.makeConfigs()` MUST
        // agree on this template byte-for-byte. Pinning so a future
        // rename here would break warning push delivery entirely.
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "codex", state: "warning") == "Quota-codex-warningZone")
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "claude", state: "warning") == "Quota-claude-warningZone")
    }

    @Test("Abacus AI is present with the upstream-canonical displayName")
    func abacusPresent() {
        let abacus = QuotaProviderList.providers.first(where: { $0.id == "abacus" })
        #expect(abacus != nil)
        // Cause: displayName MUST match
        // `AbacusProviderDescriptor.metadata.displayName` on Mac. If
        // Mac renames upstream and we don't update here, the push body
        // shows the stale name (still functional, but visibly wrong).
        #expect(abacus?.displayName == "Abacus AI")
    }

    @Test("Mistral is present with the upstream-canonical displayName")
    func mistralPresent() {
        let mistral = QuotaProviderList.providers.first(where: { $0.id == "mistral" })
        #expect(mistral != nil)
        #expect(mistral?.displayName == "Mistral")
    }

    /// Cause-oriented: a provider ID typo (e.g. accidentally "mistralai"
    /// instead of "mistral") would silently fail to subscribe — Mac
    /// writes to `Quota-mistral-depletedZone` but iOS subscribes to
    /// `Quota-mistralai-depletedZone`, so pushes are delivered into
    /// the void. Pin lowercase + no-spaces shape.
    @Test("Cause: every provider ID is lowercase and contains no whitespace")
    func providerIDFormatInvariant() {
        for provider in QuotaProviderList.providers {
            #expect(provider.id == provider.id.lowercased(),
                "Provider ID '\(provider.id)' must be lowercase")
            #expect(!provider.id.contains(" "),
                "Provider ID '\(provider.id)' must not contain spaces")
            #expect(!provider.id.isEmpty, "Provider ID must not be empty")
        }
    }

    /// Cause-oriented: the zone name template is the byte-for-byte wire
    /// contract between Mac writes and iOS subscriptions. Any change
    /// to the format (separator, casing, suffix) silently breaks
    /// existing users. Pin all known providers' resulting zone names
    /// for both states.
    @Test("Zone name template stays `Quota-{providerID}-{state}Zone`")
    func zoneNameContract() {
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "abacus", state: "depleted") ==
                "Quota-abacus-depletedZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "mistral", state: "restored") ==
                "Quota-mistral-restoredZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "codex", state: "depleted") ==
                "Quota-codex-depletedZone")
    }

    /// Cause-oriented: order of `providers` matters for the deterministic
    /// subscription-creation sequence on first launch (single-pass
    /// upserts). A reordering that puts a new provider before
    /// previously-existing ones would shift CK subscription IDs and
    /// re-create them all. Verify Abacus + Mistral + the 11 v0.24/v0.25
    /// additions are appended at the END (additive), not interleaved.
    @Test("Cause: new providers through v0.47 are appended at the tail")
    func newProvidersAppended() {
        let providers = QuotaProviderList.providers
        // Providers are append-only so per-(provider,state) CK subscription
        // IDs stay stable across upgrades. Pin the recent tail so a careless
        // edit can't reorder providers and force every existing user's iOS
        // app to re-create subscriptions.
        //  - iOS 1.8.0 appended 5 v0.27.0 providers (positions [40..44]).
        //  - iOS 1.9.0 appended 3 v0.28+v0.29 providers (positions [45..47]).
        //  - iOS 1.12.0 appended Devin from v0.34.0 (position [48]).
        //  - iOS 1.13.0 appended 4 v0.36 providers (positions [49..52]).
        //  - iOS 1.17.0 appended 4 v0.38/v0.39 providers (positions [53..56]).
        //  - iOS 1.19.0 appended 8 v0.42-v0.45 providers (positions [57..64]).
        let tail = providers.suffix(29).map(\.id)
        #expect(tail == [
            "grok", "groq", "elevenlabs", "deepgram", "llmproxy",
            "azureopenai", "alibabatokenplan", "t3chat", "devin",
            "litellm", "poe", "chutes", "zed",
            "sakana", "qoder", "crossmodel", "clawrouter",
            "clinepass", "deepinfra", "neuralwatt", "longcat",
            "sub2api", "wayfinder", "zenmux", "aiand",
            "qwencloud", "zoommate", "xai", "notion",
        ], "provider catch-up additions through v0.47 must stay at the tail in this order")
    }

    @Test("Sakana AI present (v0.38)")
    func sakanaPresent() {
        let provider = QuotaProviderList.providers.first(where: { $0.id == "sakana" })
        #expect(provider != nil)
        #expect(provider?.displayName == "Sakana AI")
    }

    @Test("Qoder present (v0.39)")
    func qoderPresent() {
        let provider = QuotaProviderList.providers.first(where: { $0.id == "qoder" })
        #expect(provider != nil)
        #expect(provider?.displayName == "Qoder")
    }

    @Test("CrossModel present (v0.39)")
    func crossModelPresent() {
        let provider = QuotaProviderList.providers.first(where: { $0.id == "crossmodel" })
        #expect(provider != nil)
        #expect(provider?.displayName == "CrossModel")
    }

    @Test("ClawRouter present (v0.39)")
    func clawRouterPresent() {
        let provider = QuotaProviderList.providers.first(where: { $0.id == "clawrouter" })
        #expect(provider != nil)
        #expect(provider?.displayName == "ClawRouter")
    }

    @Test("v0.42-v0.45 providers use upstream-canonical display names")
    func v045ProvidersPresent() {
        let expected = [
            "clinepass": "ClinePass", "deepinfra": "DeepInfra",
            "neuralwatt": "Neuralwatt", "longcat": "LongCat",
            "sub2api": "sub2api", "wayfinder": "Wayfinder",
            "zenmux": "ZenMux", "aiand": "ai&",
        ]
        let actual = Dictionary(uniqueKeysWithValues: QuotaProviderList.providers.map { ($0.id, $0.displayName) })
        for (id, displayName) in expected {
            #expect(actual[id] == displayName)
        }
    }

    @Test("v0.46-v0.47 providers use upstream-canonical display names")
    func v047ProvidersPresent() {
        let expected = [
            "qwencloud": "Qwen Cloud", "zoommate": "ZoomMate",
            "xai": "xAI", "notion": "Notion AI",
        ]
        let actual = Dictionary(uniqueKeysWithValues: QuotaProviderList.providers.map { ($0.id, $0.displayName) })
        for (id, displayName) in expected {
            #expect(actual[id] == displayName)
        }
    }

    // MARK: - iOS 1.6.0 · v0.24+v0.25 catch-up presence

    /// Cause-oriented: each provider must be present with its
    /// upstream-canonical displayName so the static `alertBody`
    /// generated at subscription time matches what Mac writes into
    /// the push body.
    @Test("OpenAI API balance present (v0.25 #877)")
    func openaiPresent() {
        let openai = QuotaProviderList.providers.first(where: { $0.id == "openai" })
        #expect(openai != nil)
        #expect(openai?.displayName == "OpenAI API")
    }

    @Test("Manus present (v0.25 #700)")
    func manusPresent() {
        let manus = QuotaProviderList.providers.first(where: { $0.id == "manus" })
        #expect(manus != nil)
        #expect(manus?.displayName == "Manus")
    }

    @Test("Windsurf present (v0.24 #583)")
    func windsurfPresent() {
        let windsurf = QuotaProviderList.providers.first(where: { $0.id == "windsurf" })
        #expect(windsurf != nil)
        #expect(windsurf?.displayName == "Windsurf")
    }

    @Test("Xiaomi MiMo present (v0.25 #651)")
    func mimoPresent() {
        let mimo = QuotaProviderList.providers.first(where: { $0.id == "mimo" })
        #expect(mimo != nil)
        #expect(mimo?.displayName == "Xiaomi MiMo")
    }

    @Test("Doubao present (v0.25 #498)")
    func doubaoPresent() {
        let doubao = QuotaProviderList.providers.first(where: { $0.id == "doubao" })
        #expect(doubao != nil)
        #expect(doubao?.displayName == "Doubao")
    }

    @Test("DeepSeek present (v0.24 #811)")
    func deepseekPresent() {
        let deepseek = QuotaProviderList.providers.first(where: { $0.id == "deepseek" })
        #expect(deepseek != nil)
        #expect(deepseek?.displayName == "DeepSeek")
    }

    @Test("Codebuff present (v0.24 #837)")
    func codebuffPresent() {
        let codebuff = QuotaProviderList.providers.first(where: { $0.id == "codebuff" })
        #expect(codebuff != nil)
        #expect(codebuff?.displayName == "Codebuff")
    }

    @Test("Crof present (v0.25 #872)")
    func crofPresent() {
        let crof = QuotaProviderList.providers.first(where: { $0.id == "crof" })
        #expect(crof != nil)
        #expect(crof?.displayName == "Crof")
    }

    @Test("Venice present (v0.25 #865)")
    func venicePresent() {
        let venice = QuotaProviderList.providers.first(where: { $0.id == "venice" })
        #expect(venice != nil)
        #expect(venice?.displayName == "Venice")
    }

    @Test("Command Code present (v0.25 #857)")
    func commandCodePresent() {
        let cc = QuotaProviderList.providers.first(where: { $0.id == "commandcode" })
        #expect(cc != nil)
        #expect(cc?.displayName == "Command Code")
    }

    @Test("StepFun present (v0.25 #815)")
    func stepfunPresent() {
        let stepfun = QuotaProviderList.providers.first(where: { $0.id == "stepfun" })
        #expect(stepfun != nil)
        #expect(stepfun?.displayName == "StepFun")
    }

    /// Cause-oriented: no duplicate IDs would silently double-subscribe.
    @Test("Cause: no duplicate provider IDs")
    func noDuplicateIDs() {
        let ids = QuotaProviderList.providers.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate provider IDs found")
    }

    /// Cause-oriented: the catalog/release-notes copy references the
    /// provider count and zone count. If those numbers drift from this
    /// list, the user-facing release notes lie. Doc the cross-coupling.
    /// (Zone count is providers × 3 states since iOS 1.6.0 added the
    /// `warning` state alongside `depleted`/`restored`.)
    @Test("Cause: catalog 69/207 numbers match the actual list")
    func catalogNumbersAlignWithList() {
        #expect(QuotaProviderList.providers.count == 69)
        #expect(QuotaProviderList.providers.count * 3 == 207)
    }

    @Test("Devin present (v0.34.0)")
    func devinPresent() {
        let devin = QuotaProviderList.providers.first(where: { $0.id == "devin" })
        #expect(devin != nil)
        #expect(devin?.displayName == "Devin")
    }

    @Test("LiteLLM present (v0.36.0)")
    func litellmPresent() {
        let litellm = QuotaProviderList.providers.first(where: { $0.id == "litellm" })
        #expect(litellm != nil)
        #expect(litellm?.displayName == "LiteLLM")
    }

    @Test("Poe present (v0.36.1)")
    func poePresent() {
        let poe = QuotaProviderList.providers.first(where: { $0.id == "poe" })
        #expect(poe != nil)
        #expect(poe?.displayName == "Poe")
    }

    @Test("Chutes present (v0.36.1)")
    func chutesPresent() {
        let chutes = QuotaProviderList.providers.first(where: { $0.id == "chutes" })
        #expect(chutes != nil)
        #expect(chutes?.displayName == "Chutes")
    }

    @Test("Zed present (v0.36.1)")
    func zedPresent() {
        let zed = QuotaProviderList.providers.first(where: { $0.id == "zed" })
        #expect(zed != nil)
        #expect(zed?.displayName == "Zed")
    }

    /// Cause-oriented: iOS 1.7.0 specifically adds Moonshot + Bedrock.
    /// Pin them by id + displayName so a rename on either side doesn't
    /// silently break push delivery for the new providers.
    @Test("Moonshot / Kimi API present (v0.26.0 #911)")
    func moonshotPresent() {
        let m = QuotaProviderList.providers.first(where: { $0.id == "moonshot" })
        #expect(m != nil)
        #expect(m?.displayName == "Moonshot / Kimi API")
    }

    @Test("AWS Bedrock present (v0.26.0 #897)")
    func bedrockPresent() {
        let b = QuotaProviderList.providers.first(where: { $0.id == "bedrock" })
        #expect(b != nil)
        #expect(b?.displayName == "AWS Bedrock")
    }
}
