import Foundation

/// The providers CodexBar can emit quota transition notifications for. The ID
/// strings must match `UsageProvider` raw values in
/// `Sources/CodexBarCore/Providers/Providers.swift` — when a new provider is
/// added upstream, this list and the iOS app must ship an update together to
/// start receiving pushes for it.
///
/// Used on iOS to create one `CKRecordZoneSubscription` per
/// `(provider, state)` pair at app launch. Each subscription's static
/// `alertBody` is pre-filled with the `displayName` via `String(format:)` so
/// the push body shows e.g. "Codex 会话额度已耗尽" on a Chinese iPhone without
/// needing CloudKit to substitute anything per record (see
/// `Research/007-push-per-provider-subscriptions.md`).
///
/// Used on Mac to pick the destination zone from a transition's provider ID
/// (e.g. `codex` depleted → `Quota-codex-depletedZone`).
public enum QuotaProviderList {

    public struct Provider: Sendable, Equatable {
        public let id: String
        public let displayName: String

        public init(id: String, displayName: String) {
            self.id = id
            self.displayName = displayName
        }
    }

    /// Display names track `ProviderDescriptor.metadata.displayName` on Mac as
    /// of 2026-04-22. If a Mac-side rename lands later, iOS subscriptions
    /// still fire — the body just shows the stale name until the iOS app ships
    /// an update.
    public static let providers: [Provider] = [
        // Each displayName must match the string in the corresponding
        // `ProviderDescriptor.metadata.displayName` on Mac (grep for
        // `displayName:` in Sources/CodexBarCore/Providers/*/*ProviderDescriptor.swift).
        Provider(id: "codex", displayName: "Codex"),
        Provider(id: "claude", displayName: "Claude"),
        Provider(id: "cursor", displayName: "Cursor"),
        Provider(id: "opencode", displayName: "OpenCode"),
        Provider(id: "opencodego", displayName: "OpenCode Go"),
        Provider(id: "alibaba", displayName: "Alibaba"),
        Provider(id: "factory", displayName: "Droid"),
        Provider(id: "gemini", displayName: "Gemini"),
        Provider(id: "antigravity", displayName: "Antigravity"),
        Provider(id: "copilot", displayName: "Copilot"),
        Provider(id: "zai", displayName: "z.ai"),
        Provider(id: "perplexity", displayName: "Perplexity"),
        Provider(id: "minimax", displayName: "MiniMax"),
        Provider(id: "kimi", displayName: "Kimi"),
        Provider(id: "kilo", displayName: "Kilo"),
        Provider(id: "kiro", displayName: "Kiro"),
        Provider(id: "vertexai", displayName: "Vertex AI"),
        Provider(id: "augment", displayName: "Augment"),
        Provider(id: "jetbrains", displayName: "JetBrains AI"),
        Provider(id: "kimik2", displayName: "Kimi K2"),
        Provider(id: "amp", displayName: "Amp"),
        Provider(id: "ollama", displayName: "Ollama"),
        Provider(id: "synthetic", displayName: "Synthetic"),
        Provider(id: "warp", displayName: "Warp"),
        Provider(id: "openrouter", displayName: "OpenRouter"),
        // Added in iOS 1.5.0 alongside Mac v0.23. Display names match
        // `AbacusProviderDescriptor.metadata.displayName` ("Abacus AI") and
        // `MistralProviderDescriptor.metadata.displayName` ("Mistral").
        // Subscription count: 25 → 27 providers × 2 states = 54 zones.
        Provider(id: "abacus", displayName: "Abacus AI"),
        Provider(id: "mistral", displayName: "Mistral"),
        // Added in iOS 1.6.0 alongside Mac v0.24+v0.25 (commit 1c95d6e7).
        // 11 new providers verified against upstream descriptors
        // (`grep "displayName:" Sources/CodexBarCore/Providers/*/[A-Z]*ProviderDescriptor.swift`).
        // Subscription count: 27 → 38 (iOS 1.6.0) → 40 (iOS 1.7.0)
        // providers × 3 states (depleted+restored+warning) = 120 zones.
        // APPENDED at the tail so existing 27-entry CK subscription IDs
        // stay stable across the 1.5.x → 1.6.0 upgrade (no re-subscribe
        // churn for installed users).
        Provider(id: "openai", displayName: "OpenAI API"),
        Provider(id: "manus", displayName: "Manus"),
        Provider(id: "windsurf", displayName: "Windsurf"),
        Provider(id: "mimo", displayName: "Xiaomi MiMo"),
        Provider(id: "doubao", displayName: "Doubao"),
        Provider(id: "deepseek", displayName: "DeepSeek"),
        Provider(id: "codebuff", displayName: "Codebuff"),
        Provider(id: "crof", displayName: "Crof"),
        Provider(id: "venice", displayName: "Venice"),
        Provider(id: "commandcode", displayName: "Command Code"),
        Provider(id: "stepfun", displayName: "StepFun"),
        // iOS 1.7.0 catch-up — upstream v0.26.0 new providers.
        // Mirrors MockProviderInjector.realProviderIDsBorrowedByMocks.
        Provider(id: "moonshot", displayName: "Moonshot / Kimi API"),
        Provider(id: "bedrock", displayName: "AWS Bedrock"),
        // iOS 1.8.0 catch-up — upstream v0.27.0 new providers.
        // Push subscriptions for these get registered on first iOS
        // launch after the upgrade so quota-depleted / -restored
        // notifications work end-to-end.
        Provider(id: "grok", displayName: "Grok"),
        Provider(id: "groq", displayName: "GroqCloud"),
        Provider(id: "elevenlabs", displayName: "ElevenLabs"),
        Provider(id: "deepgram", displayName: "Deepgram"),
        Provider(id: "llmproxy", displayName: "LLM Proxy"),
        // iOS 1.9.0 catch-up — upstream v0.28.0+v0.29.0 new providers.
        // IDs match UsageProvider raw values; display names match each
        // ProviderDescriptor.metadata.displayName. APPENDED at the tail so
        // existing per-provider CK subscription IDs stay stable across the
        // 1.8.0 → 1.9.0 upgrade. 45 → 48 providers × 3 states = 144 zones.
        Provider(id: "azureopenai", displayName: "Azure OpenAI"),
        Provider(id: "alibabatokenplan", displayName: "Alibaba Token Plan"),
        Provider(id: "t3chat", displayName: "T3 Chat"),
        // iOS 1.12.0 catch-up — upstream v0.34.0 new provider.
        // APPENDED at the tail so existing per-provider CK subscription IDs
        // stay stable across upgrades. 48 → 49 providers × 3 states = 147 zones.
        Provider(id: "devin", displayName: "Devin"),
        // iOS 1.13.0 catch-up — upstream v0.36.0 + v0.36.1 new providers.
        // APPENDED at the tail so existing per-provider CK subscription IDs
        // stay stable across upgrades. 49 → 53 providers × 3 states = 159 zones.
        Provider(id: "litellm", displayName: "LiteLLM"),
        Provider(id: "poe", displayName: "Poe"),
        Provider(id: "chutes", displayName: "Chutes"),
        Provider(id: "zed", displayName: "Zed"),
        // iOS 1.17.0 catch-up — upstream v0.38.0-v0.39.0 new providers.
        // APPENDED at the tail so existing per-provider CK subscription IDs
        // stay stable across upgrades. 53 → 57 providers × 3 states = 171 zones.
        Provider(id: "sakana", displayName: "Sakana AI"),
        Provider(id: "qoder", displayName: "Qoder"),
        Provider(id: "crossmodel", displayName: "CrossModel"),
        Provider(id: "clawrouter", displayName: "ClawRouter"),
        // iOS 1.19.0 catch-up — upstream v0.42.0-v0.45.2 new providers.
        // APPENDED at the tail so every existing per-provider CloudKit zone
        // and subscription identifier stays stable. Kimi K2 and CrossModel
        // remain above for mixed-version Macs even though upstream removed
        // them from the v0.42+ Mac registry. 57 → 66 providers × 3 states
        // = 198 subscriptions.
        Provider(id: "clinepass", displayName: "ClinePass"),
        Provider(id: "deepinfra", displayName: "DeepInfra"),
        Provider(id: "neuralwatt", displayName: "Neuralwatt"),
        Provider(id: "longcat", displayName: "LongCat"),
        Provider(id: "sub2api", displayName: "sub2api"),
        Provider(id: "wayfinder", displayName: "Wayfinder"),
        Provider(id: "zenmux", displayName: "ZenMux"),
        Provider(id: "aiand", displayName: "ai&"),
        // Kimi 2 (this PR): Mac-side QuotaTransitionWriter writes
        // Quota-kimi2-{state}Zone records; iOS must subscribe to receive
        // depleted/restored/warning pushes. Appended at the tail so all
        // existing per-provider subscription identifiers stay stable.
        Provider(id: "kimi2", displayName: "Kimi 2"),
    ]

    /// Returns the CloudKit zone name for a given `(providerID, state)`. The
    /// zone name is the join point between Mac-side record writes and iOS-side
    /// per-provider subscriptions — both must compute the same string.
    ///
    /// `state` is expected to be `"depleted"` or `"restored"`. Other values
    /// produce a zone name that will never match any iOS subscription.
    ///
    /// **WIRE CONTRACT.** Format `"Quota-{providerID}-{state}Zone"` is
    /// literally the CKRecordZone name on the iCloud server. Every user's
    /// per-provider push subscriptions were registered with these exact
    /// strings. Any change to the template (separator, casing, suffix)
    /// silently breaks push delivery for every existing user — there is no
    /// migration path for zone renames on Apple's side short of having every
    /// user manually reinstall / re-subscribe. Mac-side writes and iOS-side
    /// subscriptions must compute the same string byte-for-byte.
    public static func quotaZoneName(providerID: String, state: String) -> String {
        return "Quota-\(providerID)-\(state)Zone"
    }
}
