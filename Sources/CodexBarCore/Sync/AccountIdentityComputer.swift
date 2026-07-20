import Foundation

/// Computes a stable identifier set for a provider snapshot, used by iOS
/// `CloudSyncReader.mergeSnapshots` to group snapshots from multiple Macs
/// into a single logical account card. See
/// `Research/019-account-identity-multi-version-merge.md` for the full
/// architecture.
///
/// **Discipline (load-bearing):**
/// - Identifiers are **additive**. Once an identifier scheme is published
///   for a provider in a release, it MUST keep being written for ≥3 minor
///   releases before removal. See `Research/019-account-identity-multi-version-merge.md`
///   §6.
/// - Identifiers are **opaque to iOS**. Format is `{providerID}:{scheme}:{value}`
///   but iOS does string-equality only — never parses. New schemes can be
///   added at any time.
/// - **Time-bounded values** (JWT exp, session tokens, refresh tokens)
///   MUST NEVER appear here. Only stable identifiers.
/// - **Group / shared aliases** (`team@company.com`, etc.) MUST NOT be
///   written. Only authenticated primary identifiers.
public enum AccountIdentityComputer {
    /// Maximum length of any single identifier string. Truncating beyond
    /// this is silent — the truncated value still groups across Macs that
    /// hit the same truncation, but warn in logs so we can fix the source.
    ///
    /// **Must equal** `AccountIdentityNormalize.maxAccountIdentifierLength`
    /// in `Shared/iCloud/AccountIdentityNormalize.swift` so iOS legacy-email
    /// synthesis truncates at the same point. A unit test
    /// (`AccountIdentityComputerTests.normalize_matches_iOSSharedNormalize`)
    /// pins this contract.
    public static let maxIdentifierLength = 256

    /// Compute the identifier set for a provider snapshot.
    ///
    /// Returns nil for providers that don't have a stable account model
    /// (most quota-only providers): iOS will fall back to the legacy
    /// per-device bucket for those — current behavior, no regression.
    ///
    /// Returns `[]` only when this provider DOES participate (Tier-A) but
    /// no identifier could be derived (e.g. user signed out, fetch failed).
    /// iOS treats `[]` like nil for grouping purposes.
    public static func compute(
        provider: UsageProvider,
        identity: ProviderIdentitySnapshot?) -> [String]?
    {
        switch provider {
        case .codex:
            self.codex(identity: identity)
        case .claude:
            self.claude(identity: identity)
        case .vertexai:
            self.vertexAI(identity: identity)
        case .zai, .gemini, .antigravity, .cursor, .opencode, .opencodego, .alibaba, .factory, .copilot, .devin,
             .minimax, .kilo, .kiro, .kimi, .augment, .jetbrains, .amp, .ollama, .synthetic,
             .openrouter, .warp, .perplexity, .abacus, .mistral,
             // Upstream 0.24–0.25.1 providers. Kept non-Tier-A for now —
             // iOS falls back to per-device legacy bucket. Promote to a
             // dedicated case (with stable identifier extraction) only
             // after we ship corresponding iOS render support and have a
             // real cross-Mac merge use case for that provider.
             .openai, .manus, .windsurf, .mimo, .doubao, .deepseek,
             .codebuff, .crof, .venice, .commandcode, .stepfun,
             // Upstream v0.26.0 new providers. Same rationale as above —
             // iOS 1.7 surfaces these via single-account cards; promote
             // to Tier-A only when cross-Mac merging is needed.
             .moonshot, .bedrock,
             // Upstream v0.27.0 new providers. iOS 1.8 surfaces these
             // via single-account cards. Promote to Tier-A only if a
             // user files a cross-Mac merging request for them.
             .grok, .groq, .elevenlabs, .deepgram, .llmproxy,
             // Upstream v0.28.0–v0.29.0 new providers. iOS 1.9 surfaces
             // these via single-account cards. Promote to Tier-A only if a
             // user files a cross-Mac merging request for them.
             .azureopenai, .alibabatokenplan, .t3chat,
             // Upstream v0.36.0–v0.36.1 new providers. iOS 1.13 surfaces
             // these via generic single-account cards and push subscriptions;
             // promote only when cross-Mac merging has a stable account ID.
             .zed, .litellm, .poe, .chutes,
             // Upstream v0.38.0–v0.39.0 new providers. iOS 1.17 surfaces
             // these via generic single-account cards and push subscriptions;
             // promote only when cross-Mac merging has a stable account ID.
             .sakana, .qoder, .clawrouter,
             // Upstream v0.42.0-v0.45.2 providers. Their generic identity,
             // quota, balance and cost data can sync without promoting a
             // provider to Tier-A. Keep per-device fallback until a stable
             // cross-Mac account identifier is available.
             .clinepass, .deepinfra, .neuralwatt, .longcat, .sub2api,
             .wayfinder, .zenmux, .aiand:
            // Non-Tier-A providers: no stable account model required by
            // iOS today. Return nil → iOS falls back to per-device legacy
            // bucket. If a future provider needs cross-Mac merging, add
            // a case here with its identifier sources.
            nil
        }
    }

    // MARK: - Per-provider identifier extraction

    private static func codex(identity: ProviderIdentitySnapshot?) -> [String]? {
        guard let identity else { return [] }
        var ids: [String] = []
        // Primary: organization ID. Stable across email changes, IdP swaps.
        if let normalized = Self.normalize(identity.accountOrganization) {
            ids.append("codex:account:\(normalized)")
        }
        // Secondary: email. Less stable but useful for transitional
        // grouping (Mac without org-id can still merge via email).
        if identity.accountEmailIsFallbackLabel != true,
           let normalized = Self.normalize(identity.accountEmail)
        {
            ids.append("codex:email:\(normalized)")
        }
        return ids
    }

    private static func claude(identity: ProviderIdentitySnapshot?) -> [String]? {
        guard let identity else { return [] }
        var ids: [String] = []
        // Primary: organization ID (Anthropic Team / Enterprise org).
        // For consumer plans this is often nil — falls back to email.
        if let normalized = Self.normalize(identity.accountOrganization) {
            ids.append("claude:account:\(normalized)")
        }
        // Secondary: email. For consumer Claude OAuth this is the only
        // stable handle we have today. Future work may add the OAuth
        // `sub` claim as a third identifier (Research/019 §4.2).
        if identity.accountEmailIsFallbackLabel != true,
           let normalized = Self.normalize(identity.accountEmail)
        {
            ids.append("claude:email:\(normalized)")
        }
        return ids
    }

    private static func vertexAI(identity: ProviderIdentitySnapshot?) -> [String]? {
        guard let identity else { return [] }
        var ids: [String] = []
        // Primary: GCP project / org identifier.
        if let normalized = Self.normalize(identity.accountOrganization) {
            ids.append("vertexai:project:\(normalized)")
        }
        // Secondary: GCP user account email.
        if identity.accountEmailIsFallbackLabel != true,
           let normalized = Self.normalize(identity.accountEmail)
        {
            ids.append("vertexai:email:\(normalized)")
        }
        return ids
    }

    // MARK: - Normalization

    /// Apply the normalization rules from Research/019 §4.4:
    /// - lowercase
    /// - Unicode NFC
    /// - trim whitespace
    /// - URL-percent-encode the value (safe across `:` / `|` / `/` etc.)
    /// - skip empty / whitespace-only
    /// - cap at `maxIdentifierLength` bytes
    ///
    /// **Mirrors `AccountIdentityNormalize.normalize`** in Shared/ —
    /// iOS uses that copy to synthesize the legacy-email fallback so
    /// it lands on the SAME bytes Mac writes for `codex:email:...` etc.
    /// If you change this, change Shared/ too. A unit test pins them.
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        let nfc = lowered.precomposedStringWithCanonicalMapping
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ":|/"))
        guard let encoded = nfc.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        if encoded.count > Self.maxIdentifierLength {
            return String(encoded.prefix(Self.maxIdentifierLength))
        }
        return encoded
    }
}
