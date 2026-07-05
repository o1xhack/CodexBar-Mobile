import SwiftUI

/// Single source of truth for provider-card tint colors.
///
/// Before iOS 1.3.0 / Build 70 this logic was duplicated (with subtle
/// drift) across 5 call sites: `ProviderUsageView.providerColor`,
/// `ProviderDetailView.providerColor`, `UtilizationAggregateView.providerColor(for:)`,
/// `ContentView.providerTint(for:)`, and `CostShareService.providerColor(for:)`.
/// Any new provider (e.g. Perplexity / OpenCode Go from upstream 0.20) had to
/// be added in 5 places or face color collisions across tabs.
///
/// Pass the `providerID` (the lowercase canonical ID like `"perplexity"` or
/// `"opencodego"`) — not the display name. The function lowercases + strips
/// spaces defensively so passing a display name still works, but prefer ID.
enum ProviderColorPalette {
    /// Returns the brand-aligned tint color for a provider.
    ///
    /// New provider additions MUST check the specificity ordering — narrower
    /// matches (`opencodego`) go **before** broader substrings (`opencode`)
    /// so we don't accidentally collapse two distinct providers back into the
    /// same color.
    static func color(for providerIdentifier: String) -> Color {
        let normalized = providerIdentifier
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        // Specific new providers from upstream v0.20 — these come first
        // because `opencodego.contains("opencode")` would otherwise grab the
        // more general rule below and collapse Go into Zen's blue.
        if normalized.contains("perplexity") {
            // Perplexity brand teal (#21808D) — distinct from Claude orange
            // and Codex purple.
            return Color(red: 0.13, green: 0.50, blue: 0.55)
        }
        if normalized.contains("opencodego") {
            // Mint — visually distinct from OpenCode Zen's blue so a user
            // with both products enabled can tell the cards apart at a glance.
            return .mint
        }

        // Specific new providers from upstream v0.21 / v0.23 (iOS 1.5.0).
        if normalized.contains("abacus") {
            // Abacus AI — brown/amber (#8B5E3C). Distinct from Claude's
            // orange-tan (warmer hue) and from any of the existing colors.
            // Picked to evoke the wooden-bead-counter abacus association
            // while staying readable in dark mode against neutral cards.
            return Color(red: 0.55, green: 0.37, blue: 0.24)
        }
        if normalized.contains("mistral") {
            // Mistral — vibrant red (#E63946). Mistral's official brand
            // color is fire-orange (#FF7A00) but that collides with
            // Claude's orange-tan; shifting to red preserves the warm-tone
            // brand intent while staying visually distinct in the card
            // grid and the 30-day utilization stacked bar chart.
            return Color(red: 0.90, green: 0.22, blue: 0.27)
        }

        // Specific new providers from upstream v0.24 / v0.25 (iOS 1.6.0).
        // 10 picks; the 11th catch-up provider (`openai`, OpenAI API balance
        // from v0.25) inherits the existing ChatGPT-green rule below since
        // both share the `openai` providerID.
        //
        // Color choices avoid the existing palette zones (claude orange-tan,
        // codex/cursor purple, openai/chatgpt green, gemini cyan, openrouter
        // indigo, perplexity teal, opencodego mint, opencode blue,
        // abacus brown, mistral red).
        if normalized.contains("windsurf") {
            // Windsurf (Codeium) — navy (#1A3372). Distinct from the
            // opencode `.blue` fallback (deeper, more saturated).
            return Color(red: 0.10, green: 0.20, blue: 0.45)
        }
        if normalized.contains("codebuff") {
            // Codebuff — olive (#808833). Distinguishes from gemini cyan
            // and the .green ChatGPT/OpenAI rule below. Substring "code" is
            // shared with `commandcode` (both have their own `if`); neither
            // matches the broader `code` substring (there is no such rule).
            return Color(red: 0.50, green: 0.55, blue: 0.20)
        }
        if normalized.contains("deepseek") {
            // DeepSeek — royal blue (#4D6BFE). DeepSeek's official brand
            // color. Distinct from the .blue opencode fallback (more
            // saturated, brighter).
            return Color(red: 0.30, green: 0.42, blue: 1.0)
        }
        if normalized.contains("manus") {
            // Manus — violet (#8B40BF). Sits between codex purple (which
            // is .purple, ~ #800080) and a redder magenta; keeps the
            // "agent-tool" cluster visually grouped while remaining distinct.
            return Color(red: 0.55, green: 0.25, blue: 0.75)
        }
        if normalized.contains("mimo") {
            // Xiaomi MiMo — bright orange (#FF8C00). Xiaomi's brand orange
            // is close to Claude orange-tan; shifted brighter / more saturated
            // so the two are distinguishable in dark mode and stacked charts.
            return Color(red: 1.0, green: 0.55, blue: 0.0)
        }
        if normalized.contains("doubao") {
            // Doubao (ByteDance/Volcengine) — hot pink (#FF6699). Avoids
            // the red zone Mistral owns and the warm-orange Claude/MiMo
            // zone, while staying in the "warm-toned brand" family.
            return Color(red: 1.0, green: 0.40, blue: 0.60)
        }
        if normalized.contains("commandcode") {
            // Command Code — slate gray (#66728A). Neutral / professional
            // tone since Command Code is a CLI billing tool; distinct from
            // every brand-colored provider. Also a hedge: substring "code"
            // is shared with codebuff (above) and `codex` (below), but the
            // specificity of `commandcode.contains("commandcode")` matches
            // here first; `commandcode.contains("codex") == false`.
            return Color(red: 0.40, green: 0.45, blue: 0.54)
        }
        if normalized.contains("stepfun") {
            // StepFun — bright violet (#A659F2). The brighter cousin of
            // Manus violet; placed AFTER manus so the brighter shade lights
            // up for stepfun specifically.
            return Color(red: 0.65, green: 0.35, blue: 0.95)
        }
        if normalized.contains("crof") {
            // Crof — amber (#D9A61A). Sits between Abacus brown (cooler)
            // and the yellow zone; deliberately bright so it doesn't read
            // as "mustard" against neutral cards.
            return Color(red: 0.85, green: 0.65, blue: 0.10)
        }
        if normalized.contains("venice") {
            // Venice — plum (#8C5990). A pinker / warmer purple than
            // Codex (.purple) or Manus violet; keeps the multi-provider
            // purple cluster legible at a glance.
            return Color(red: 0.55, green: 0.35, blue: 0.55)
        }

        // iOS 1.8.0 — upstream v0.27.0 new providers (5 picks).
        // Color choices avoid the existing palette zones; new entries
        // sit beside their conceptual cluster (Grok/Groq both "warm"
        // brand-aligned shades distinct from Mistral red, ElevenLabs
        // pure-voice teal, Deepgram brand purple, LLM Proxy neutral
        // slate since it's a meta-provider).
        if normalized.contains("grok") {
            // xAI Grok — charcoal black (#1A1A1A). Matches Grok brand
            // identity (xAI "X" minimalist black on white). Distinct
            // from any colored brand in the palette; reads as neutral
            // strong card frame in dark + light mode.
            return Color(red: 0.10, green: 0.10, blue: 0.12)
        }
        if normalized.contains("groq") {
            // GroqCloud — orange-red (#F55036). GroqCloud official
            // brand uses orange and red gradients. Distinct from
            // Mistral red (#E63946 — pure red) and MiMo orange
            // (#FF8C00 — pure orange) by sitting between them. Note
            // specificity: `grok` matched above, so reaching this
            // line requires `groq` (with q).
            return Color(red: 0.96, green: 0.31, blue: 0.21)
        }
        if normalized.contains("elevenlabs") {
            // ElevenLabs — pure black-and-white brand → use a
            // soft sage-green (#7AAE82). Distinct from gemini cyan,
            // codebuff olive, and the OpenAI greens. Evokes "voice
            // / audio waveform" without colliding with existing
            // palette zones.
            return Color(red: 0.48, green: 0.68, blue: 0.51)
        }
        if normalized.contains("deepgram") {
            // Deepgram — brand purple (#7C3AED). Distinct from
            // codex/cursor `.purple` (~#800080) by being more
            // saturated and bluer; sits between codex and openrouter
            // in the purple cluster without collapsing into either.
            return Color(red: 0.49, green: 0.23, blue: 0.93)
        }
        if normalized.contains("llmproxy") || normalized.contains("llm-proxy") {
            // LLM Proxy — neutral slate-blue (#5C7A99). LLM Proxy is
            // a meta-provider that aggregates upstream models, so
            // intentionally neutral / "infrastructure" tone. Distinct
            // from commandcode slate-gray (#66728A — warmer / more
            // gray) by being slightly cooler / bluer.
            return Color(red: 0.36, green: 0.48, blue: 0.60)
        }

        // iOS 1.9.0 — upstream v0.28.0+v0.29.0 new providers (3 picks).
        // Checked BEFORE the generic `openai`/`opencode` rules below:
        // `"azureopenai".contains("openai")` is true, so Azure OpenAI must
        // match here first or it would collapse into the ChatGPT-green rule.
        if normalized.contains("azureopenai") {
            // Azure OpenAI — Microsoft Azure blue (#0078D4). Distinct from
            // the opencode `.blue` fallback and deepseek royal blue by being
            // a cleaner mid cyan-blue tied to the Azure brand.
            return Color(red: 0.0, green: 0.47, blue: 0.83)
        }
        if normalized.contains("alibabatokenplan") {
            // Alibaba Token Plan (Bailian) — Alibaba orange (#F26A0D).
            // Sits in the warm-orange family (MiMo/Bedrock) but redder so the
            // Bailian quota card reads distinctly. The base `alibaba` (Qwen)
            // provider keeps the .blue fallback — it is a different product.
            return Color(red: 0.95, green: 0.42, blue: 0.05)
        }
        if normalized.contains("t3chat") {
            // T3 Chat — rose-pink (#E84A99). T3's brand accent is a pink /
            // magenta; placed apart from doubao hot-pink and antigravity
            // magenta by being a brighter rose.
            return Color(red: 0.91, green: 0.29, blue: 0.60)
        }
        if normalized.contains("devin") {
            // Devin — blue-green (#2FAE92). Distinct from Azure/OpenCode
            // blues and Perplexity teal while staying in the calm
            // productivity-tool family for the provider grid.
            return Color(red: 0.18, green: 0.68, blue: 0.57)
        }
        // iOS 1.13.0 — upstream v0.36.0+v0.36.1 new providers.
        if normalized.contains("litellm") || normalized.contains("lite-llm") {
            // LiteLLM — proxy/infrastructure blue (#1A61B8). Cooler and
            // brighter than LLM Proxy's slate-blue so both proxy providers
            // stay distinguishable in provider grids and cost charts.
            return Color(red: 0.10, green: 0.38, blue: 0.72)
        }
        if normalized.contains("poe") {
            // Poe — saturated violet (#6D47DB). Distinct from Perplexity's
            // teal and from the generic Codex/Cursor purple.
            return Color(red: 0.43, green: 0.28, blue: 0.86)
        }
        if normalized.contains("chutes") {
            // Chutes — green-teal (#059E73). Distinct from Devin's
            // blue-green and OpenAI's generic green rule.
            return Color(red: 0.02, green: 0.62, blue: 0.45)
        }
        if normalized.contains("zed") {
            // Zed — graphite (#333A47). Neutral editor tone, checked
            // after z.ai so the short `zed` ID does not interfere with
            // the existing z.ai palette entry.
            return Color(red: 0.20, green: 0.23, blue: 0.28)
        }
        // iOS 1.17.0 — upstream v0.38.0+v0.39.0 new providers.
        if normalized.contains("sakana") {
            // Sakana AI — ocean blue from upstream provider branding.
            return Color(red: 0.16, green: 0.46, blue: 0.86)
        }
        if normalized.contains("qoder") {
            // Qoder — emerald green from upstream provider branding.
            return Color(red: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0)
        }
        if normalized.contains("crossmodel") {
            // CrossModel — violet from upstream provider branding.
            return Color(red: 124.0 / 255.0, green: 58.0 / 255.0, blue: 237.0 / 255.0)
        }
        if normalized.contains("clawrouter") || normalized.contains("claw-router") {
            // ClawRouter — periwinkle from upstream provider branding.
            return Color(red: 89.0 / 255.0, green: 110.0 / 255.0, blue: 246.0 / 255.0)
        }

        // iOS 1.7.0 — upstream v0.26.0 new providers.
        if normalized.contains("moonshot") || normalized.contains("kimi-api") {
            // Moonshot / Kimi API — deep indigo (#3C4FE0). Distinct
            // from Kimi (existing) cooler blue and Antigravity.
            return Color(red: 0.24, green: 0.31, blue: 0.88)
        }
        if normalized.contains("bedrock") {
            // AWS Bedrock — AWS-orange (#FF9900). The most recognizable
            // AWS brand tint; reads cleanly against the cost-budget
            // gradient on the dedicated card.
            return Color(red: 1.00, green: 0.60, blue: 0.00)
        }
        // Earlier upstream providers without explicit entries (falls
        // back to .blue otherwise). Adding distinct tints so the
        // multi-card grid stays legible.
        if normalized.contains("kiro") {
            // Kiro — emerald (#3F9D7C). Stands apart from gemini cyan
            // and the openrouter purple cluster.
            return Color(red: 0.25, green: 0.62, blue: 0.49)
        }
        if normalized.contains("zai") || normalized.contains("z.ai") {
            // z.ai — slate teal (#2E7080). Cooler than perplexity teal,
            // warmer than gemini cyan.
            return Color(red: 0.18, green: 0.44, blue: 0.50)
        }
        if normalized.contains("antigravity") {
            // Antigravity — saturated magenta (#C8358A). Distinct from
            // the purple cluster (Codex/Cursor) and from venice plum.
            return Color(red: 0.78, green: 0.21, blue: 0.54)
        }

        // Existing provider mappings — preserved from pre-1.3.0 behavior.
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return Color(red: 0.82, green: 0.55, blue: 0.28)
        }
        if normalized.contains("codex") || normalized.contains("cursor") {
            return .purple
        }
        if normalized.contains("openai") || normalized.contains("chatgpt") {
            return .green
        }
        if normalized.contains("gemini") {
            return .cyan
        }
        if normalized.contains("openrouter") {
            return Color(red: 0.42, green: 0.35, blue: 0.83)
        }
        if normalized.contains("opencode") {
            // OpenCode Zen (the original `opencode` ID). Kept at blue which
            // is also the implicit fallback, but making it explicit keeps
            // the matrix readable when a future provider claims the fallback.
            return .blue
        }
        return .blue
    }
}
