import CodexBarSync
import Foundation
import Testing

/// Regression guard for the provider list that seeds iOS CKRecordZoneSubscriptions.
///
/// iOS 1.5.0 (Mac v0.23) adds Abacus AI and Mistral on top of the
/// 1.3.0 (Mac v0.20) baseline that already included Perplexity and
/// OpenCode Go. The provider set is the single source of truth for both:
///   - Mac side picks the CloudKit zone to write a QuotaTransition record to
///   - iOS side creates one CKRecordZoneSubscription per (provider, state)
/// If the two sides drift, iOS stops receiving pushes for the orphaned provider.
/// Tests below pin the expected set so upstream provider churn is a compile-time
/// conversation, not a silent production miss.
@Suite("QuotaProviderList contract")
struct QuotaProviderListTests {
    @Test("Provider list has expected count (57 after v0.39 catch-up)")
    func providerCount() {
        // 25 base → 27 in iOS 1.5.0 (Abacus + Mistral) → 38 in iOS 1.6.0
        // (11 new from Mac v0.24+v0.25) → 40 in iOS 1.7.0 (Moonshot +
        // AWS Bedrock from upstream v0.26.0) → 45 in iOS 1.8.0 (Grok,
        // GroqCloud, ElevenLabs, Deepgram, LLM Proxy from upstream
        // v0.27.0) → 48 in iOS 1.9.0 (Azure OpenAI, Alibaba Token Plan,
        // T3 Chat from upstream v0.28.0+v0.29.0) → 49 in iOS 1.12.0
        // (Devin from upstream v0.34.0) → 53 in iOS 1.13.0 (LiteLLM,
        // Poe, Chutes, Zed from upstream v0.36.0+v0.36.1) → 57 in
        // iOS 1.17.0 (Sakana AI, Qoder, CrossModel, ClawRouter from
        // upstream v0.38.0-v0.39.0). Must stay synced with
        // iOS-side test in CodexBarMobileTests/QuotaProviderListTests.swift.
        #expect(QuotaProviderList.providers.count == 57)
    }

    @Test("Perplexity is registered with the Mac-side displayName")
    func perplexityRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "perplexity" })
        #expect(entry.displayName == "Perplexity")
    }

    @Test("OpenCode Go is registered and distinct from OpenCode Zen")
    func opencodeGoRegistered() throws {
        let zen = try #require(QuotaProviderList.providers.first { $0.id == "opencode" })
        let go = try #require(QuotaProviderList.providers.first { $0.id == "opencodego" })
        #expect(zen.displayName == "OpenCode")
        #expect(go.displayName == "OpenCode Go")
        #expect(zen.id != go.id)
    }

    @Test("Abacus AI is registered with the Mac-side displayName")
    func abacusRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "abacus" })
        #expect(entry.displayName == "Abacus AI")
    }

    @Test("Mistral is registered with the Mac-side displayName")
    func mistralRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "mistral" })
        #expect(entry.displayName == "Mistral")
    }

    @Test("No duplicate provider IDs")
    func noDuplicateIDs() {
        let ids = QuotaProviderList.providers.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("No blank IDs or displayNames")
    func noBlankEntries() {
        for provider in QuotaProviderList.providers {
            #expect(!provider.id.isEmpty)
            #expect(!provider.displayName.isEmpty)
        }
    }

    @Test("quotaZoneName composes (providerID, state) consistently for Mac + iOS")
    func zoneNameContract() {
        // Mac writes QuotaTransition records to this exact zone name; iOS
        // subscribes to this exact zone name. If the formula drifts the two
        // sides lose each other.
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "perplexity", state: "depleted")
                == "Quota-perplexity-depletedZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "opencodego", state: "restored")
                == "Quota-opencodego-restoredZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "abacus", state: "depleted")
                == "Quota-abacus-depletedZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "mistral", state: "restored")
                == "Quota-mistral-restoredZone")
    }

    @Test("iOS subscription count is 57 × 3 = 171 (depleted + restored + warning)")
    func subscriptionCountDerivation() {
        // 54 → 76 in iOS 1.5.x → 114 in iOS 1.6.0 (38 × 3 after adding
        // the "warning" state for pre-depletion threshold pushes) →
        // 120 in iOS 1.7.0 (40 × 3 after the v0.26 catch-up) →
        // 135 in iOS 1.8.0 (45 × 3 after the v0.27 catch-up: +grok,
        // +groq, +elevenlabs, +deepgram, +llmproxy) →
        // 144 in iOS 1.9.0 (48 × 3 after the v0.28+v0.29 catch-up:
        // +azureopenai, +alibabatokenplan, +t3chat) →
        // 147 in iOS 1.12.0 (49 × 3 after the v0.34 catch-up: +devin) →
        // 159 in iOS 1.13.0 (53 × 3 after the v0.36 catch-up:
        // +litellm, +poe, +chutes, +zed) →
        // 171 in iOS 1.17.0 (57 × 3 after the v0.38/v0.39 catch-up:
        // +sakana, +qoder, +crossmodel, +clawrouter).
        // If this fails,
        // someone either dropped a provider or changed the state
        // matrix without updating the iOS subscription setup in
        // `QuotaTransitionSubscriptions.makeConfigs()`.
        let states = ["depleted", "restored", "warning"]
        let subscriptionCount = QuotaProviderList.providers.count * states.count
        #expect(subscriptionCount == 171)
    }

    // MARK: - iOS 1.7.0 / Mac 0.26.2 — v0.26.0 catch-up

    @Test("Moonshot / Kimi API is registered with the Mac-side displayName")
    func moonshotRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "moonshot" })
        #expect(entry.displayName == "Moonshot / Kimi API")
    }

    @Test("AWS Bedrock is registered with the Mac-side displayName")
    func bedrockRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "bedrock" })
        #expect(entry.displayName == "AWS Bedrock")
    }

    @Test("Devin is registered with the Mac-side displayName")
    func devinRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "devin" })
        #expect(entry.displayName == "Devin")
    }

    @Test("LiteLLM is registered with the Mac-side displayName")
    func litellmRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "litellm" })
        #expect(entry.displayName == "LiteLLM")
    }

    @Test("Poe is registered with the Mac-side displayName")
    func poeRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "poe" })
        #expect(entry.displayName == "Poe")
    }

    @Test("Chutes is registered with the Mac-side displayName")
    func chutesRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "chutes" })
        #expect(entry.displayName == "Chutes")
    }

    @Test("Zed is registered with the Mac-side displayName")
    func zedRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "zed" })
        #expect(entry.displayName == "Zed")
    }

    @Test("Sakana AI is registered with the Mac-side displayName")
    func sakanaRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "sakana" })
        #expect(entry.displayName == "Sakana AI")
    }

    @Test("Qoder is registered with the Mac-side displayName")
    func qoderRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "qoder" })
        #expect(entry.displayName == "Qoder")
    }

    @Test("CrossModel is registered with the Mac-side displayName")
    func crossModelRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "crossmodel" })
        #expect(entry.displayName == "CrossModel")
    }

    @Test("ClawRouter is registered with the Mac-side displayName")
    func clawRouterRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "clawrouter" })
        #expect(entry.displayName == "ClawRouter")
    }
}
