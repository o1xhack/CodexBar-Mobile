import CodexBarSync
import SwiftUI
import Testing
@testable import CodexBarMobile

/// Pins the consolidated provider-tint palette introduced in iOS 1.3.0 (70).
///
/// Before Build 70 this logic was duplicated (with subtle drift) across 5
/// files. Any new provider (e.g. Perplexity / OpenCode Go) required touching
/// all 5, and the aggregate utilization view even had a different semantic
/// (exact-match + `.gray` default) than the rest. These tests pin:
///   - new upstream-0.20 providers get distinct brand-aligned tints
///   - pre-existing providers keep their established colors (no silent regression)
///   - specificity ordering: `opencodego` never collapses into the broader
///     `opencode` match
///   - normalization lets callers pass either `providerID` (`"opencodego"`)
///     or `providerName` (`"OpenCode Go"`) and get the same color
@Suite("Provider color palette")
struct ProviderColorPaletteTests {
    @Test("Perplexity resolves to its brand teal (#21808D)")
    func perplexityIsTeal() {
        let color = ProviderColorPalette.color(for: "perplexity")
        // Reconstruct the brand teal and compare. Use UIColor for RGBA
        // extraction because SwiftUI `Color` doesn't expose components
        // directly across platforms.
        let expected = UIColor(red: 0.13, green: 0.50, blue: 0.55, alpha: 1)
        #expect(UIColor(color).isApproximately(expected))
    }

    @Test("OpenCode Go resolves to mint (distinct from OpenCode Zen's blue)")
    func opencodeGoIsMint() {
        let go = ProviderColorPalette.color(for: "opencodego")
        let zen = ProviderColorPalette.color(for: "opencode")
        #expect(UIColor(go).isApproximately(UIColor(.mint)))
        #expect(UIColor(zen).isApproximately(UIColor(.blue)))
        // Sanity: the two colors are actually different.
        #expect(!UIColor(go).isApproximately(UIColor(zen)))
    }

    @Test("Specificity: `opencodego` is NOT collapsed into `opencode` rule")
    func opencodeGoDoesNotCollideWithOpencode() {
        // `"opencodego".contains("opencode") == true`, so the specificity
        // ordering in the palette matters. A naive reordering would regress
        // this test.
        let go = ProviderColorPalette.color(for: "opencodego")
        #expect(UIColor(go).isApproximately(UIColor(.mint)))
        #expect(!UIColor(go).isApproximately(UIColor(.blue)))
    }

    @Test("Claude keeps brand orange across ID and name inputs")
    func claudeIsBrandOrange() {
        let expected = UIColor(red: 0.82, green: 0.55, blue: 0.28, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "claude")).isApproximately(expected))
        #expect(UIColor(ProviderColorPalette.color(for: "Claude")).isApproximately(expected))
        #expect(UIColor(ProviderColorPalette.color(for: "anthropic")).isApproximately(expected))
    }

    @Test("Codex stays purple")
    func codexIsPurple() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "codex"))
                .isApproximately(UIColor(.purple)))
    }

    @Test("Normalization: display name with spaces matches providerID")
    func displayNameMatchesID() {
        // `"opencodego".lowercased().replacingOccurrences(of: " ", with: "")` vs
        // `"OpenCode Go".lowercased().replacingOccurrences(of: " ", with: "")`
        // should resolve to the same color, so callers passing displayName
        // (e.g. CostShareService pre-refactor) don't silently fall to the
        // generic blue fallback.
        let byID = ProviderColorPalette.color(for: "opencodego")
        let byName = ProviderColorPalette.color(for: "OpenCode Go")
        #expect(UIColor(byID).isApproximately(UIColor(byName)))
    }

    @Test("Empty input falls to blue (not a crash)")
    func emptyFallsToBlue() {
        #expect(
            UIColor(ProviderColorPalette.color(for: ""))
                .isApproximately(UIColor(.blue)))
    }

    @Test("Unknown provider falls to blue")
    func unknownFallsToBlue() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "brand-new-ai-tool"))
                .isApproximately(UIColor(.blue)))
    }

    @Test("Gemini stays cyan (was only in UtilizationAggregateView pre-consolidation)")
    func geminiIsCyan() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "gemini"))
                .isApproximately(UIColor(.cyan)))
    }

    @Test("OpenRouter keeps its custom indigo")
    func openrouterIsIndigo() {
        let expected = UIColor(red: 0.42, green: 0.35, blue: 0.83, alpha: 1)
        #expect(
            UIColor(ProviderColorPalette.color(for: "openrouter"))
                .isApproximately(expected))
    }

    // MARK: - iOS 1.5.0 · Abacus + Mistral additions

    @Test("Abacus AI follows the v0.70 purple brand color")
    func abacusIsBrown() {
        let expected = UIColor(red: 129.0 / 255, green: 78.0 / 255, blue: 232.0 / 255, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "abacus")).isApproximately(expected))
    }

    @Test("Mistral follows the v0.70 orange brand color")
    func mistralIsRed() {
        let expected = UIColor(red: 0.82577103, green: 0.26554206, blue: 0.13277103, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "mistral")).isApproximately(expected))
    }

    /// Cause-oriented: Abacus's brown is in the same warm-tone family as
    /// Claude's brand orange-tan. A naive future palette change that
    /// shifts Abacus closer to Claude would silently regress the visual
    /// distinguishability that's the whole point of T2. Pin the delta.
    @Test("Cause: Abacus brown is visually distinct from Claude orange")
    func abacusDistinctFromClaude() {
        let abacus = UIColor(ProviderColorPalette.color(for: "abacus"))
        let claude = UIColor(ProviderColorPalette.color(for: "claude"))
        // Components in [0,1]; require > 0.10 cumulative L1 delta across RGB
        // (perceptual distinguishability rule of thumb on neutral cards).
        var aR: CGFloat = 0; var aG: CGFloat = 0; var aB: CGFloat = 0; var aA: CGFloat = 0
        var cR: CGFloat = 0; var cG: CGFloat = 0; var cB: CGFloat = 0; var cA: CGFloat = 0
        _ = abacus.getRed(&aR, green: &aG, blue: &aB, alpha: &aA)
        _ = claude.getRed(&cR, green: &cG, blue: &cB, alpha: &cA)
        let delta = abs(aR - cR) + abs(aG - cG) + abs(aB - cB)
        #expect(delta > 0.10, "Abacus and Claude must stay perceptually distinct (Δ=\(delta))")
    }

    /// Cause-oriented: Mistral's brand color is fire-orange (#FF7A00) —
    /// we deliberately shifted to red to avoid clashing with Claude's
    /// orange-tan. If anyone "restores" the brand orange, this test
    /// catches the collision before it ships.
    @Test("Cause: Mistral red is visually distinct from Claude orange")
    func mistralDistinctFromClaude() {
        let mistral = UIColor(ProviderColorPalette.color(for: "mistral"))
        let claude = UIColor(ProviderColorPalette.color(for: "claude"))
        var mR: CGFloat = 0; var mG: CGFloat = 0; var mB: CGFloat = 0; var mA: CGFloat = 0
        var cR: CGFloat = 0; var cG: CGFloat = 0; var cB: CGFloat = 0; var cA: CGFloat = 0
        _ = mistral.getRed(&mR, green: &mG, blue: &mB, alpha: &mA)
        _ = claude.getRed(&cR, green: &cG, blue: &cB, alpha: &cA)
        let delta = abs(mR - cR) + abs(mG - cG) + abs(mB - cB)
        #expect(delta > 0.10, "Mistral and Claude must stay perceptually distinct (Δ=\(delta))")
    }

    /// Cause-oriented: Abacus and Mistral are both "new" so they could
    /// have been picked too close to each other. Pin the delta so a
    /// future palette tuning of one doesn't accidentally walk into the
    /// other.
    @Test("Cause: Abacus and Mistral are distinct from each other")
    func abacusDistinctFromMistral() {
        let abacus = UIColor(ProviderColorPalette.color(for: "abacus"))
        let mistral = UIColor(ProviderColorPalette.color(for: "mistral"))
        var aR: CGFloat = 0; var aG: CGFloat = 0; var aB: CGFloat = 0; var aA: CGFloat = 0
        var mR: CGFloat = 0; var mG: CGFloat = 0; var mB: CGFloat = 0; var mA: CGFloat = 0
        _ = abacus.getRed(&aR, green: &aG, blue: &aB, alpha: &aA)
        _ = mistral.getRed(&mR, green: &mG, blue: &mB, alpha: &mA)
        let delta = abs(aR - mR) + abs(aG - mG) + abs(aB - mB)
        #expect(delta > 0.10, "Abacus and Mistral must stay perceptually distinct (Δ=\(delta))")
    }

    /// Cause-oriented: the palette uses substring `contains` matching.
    /// Mac's provider IDs are kebab-case ASCII (`abacus`, `mistral`),
    /// but a display name like `"Abacus AI"` (with space) is normalized
    /// to `"abacusai"` and must still resolve to brown. Without this
    /// test, a future provider with substring `aba` could silently
    /// inherit Abacus's color.
    @Test("Abacus matches both providerID and displayName (normalization)")
    func abacusNormalization() {
        let byID = UIColor(ProviderColorPalette.color(for: "abacus"))
        let byName = UIColor(ProviderColorPalette.color(for: "Abacus AI"))
        #expect(byID.isApproximately(byName))
    }

    @Test("Mistral matches both providerID and displayName (normalization)")
    func mistralNormalization() {
        let byID = UIColor(ProviderColorPalette.color(for: "mistral"))
        let byName = UIColor(ProviderColorPalette.color(for: "Mistral"))
        #expect(byID.isApproximately(byName))
    }

    /// Cause-oriented: the existing fallback for unknown providers is
    /// `.blue`. Adding new specific entries (Abacus, Mistral) must NOT
    /// shift the unknown fallback. Pin it.
    @Test("Cause: unknown provider unchanged at .blue after Abacus/Mistral additions")
    func unknownStillBlueAfter150() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "future-llm-provider"))
                .isApproximately(UIColor(.blue)))
    }

    // MARK: - iOS 1.6.0 · v0.24+v0.25 catch-up additions

    @Test("Windsurf resolves to navy")
    func windsurfIsNavy() {
        let expected = UIColor(red: 0.10, green: 0.20, blue: 0.45, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "windsurf")).isApproximately(expected))
    }

    @Test("Codebuff follows the v0.70 green brand color")
    func codebuffIsOlive() {
        let expected = UIColor(red: 0.00000000, green: 0.53089906, blue: 0.31021161, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "codebuff")).isApproximately(expected))
    }

    @Test("DeepSeek resolves to royal blue")
    func deepseekIsRoyalBlue() {
        let expected = UIColor(red: 0.29275945, green: 0.40682158, blue: 0.96572599, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "deepseek")).isApproximately(expected))
    }

    @Test("Manus resolves to violet")
    func manusIsViolet() {
        let expected = UIColor(red: 0.55, green: 0.25, blue: 0.75, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "manus")).isApproximately(expected))
    }

    @Test("MiMo (Xiaomi) resolves to bright orange")
    func mimoIsBrightOrange() {
        let expected = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "mimo")).isApproximately(expected))
    }

    @Test("Doubao resolves to hot pink")
    func doubaoIsHotPink() {
        let expected = UIColor(red: 1.0, green: 0.40, blue: 0.60, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "doubao")).isApproximately(expected))
    }

    @Test("Command Code follows the v0.70 purple brand color")
    func commandcodeIsSlate() {
        let expected = UIColor(red: 0.54901961, green: 0.30588235, blue: 0.86666667, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "commandcode")).isApproximately(expected))
    }

    @Test("StepFun resolves to bright violet")
    func stepfunIsBrightViolet() {
        let expected = UIColor(red: 0.65, green: 0.35, blue: 0.95, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "stepfun")).isApproximately(expected))
    }

    @Test("Crof resolves to amber")
    func crofIsAmber() {
        let expected = UIColor(red: 0.85, green: 0.65, blue: 0.10, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "crof")).isApproximately(expected))
    }

    @Test("Venice follows the v0.70 blue brand color")
    func veniceIsPlum() {
        // WCAG luminance ceiling 0.18 preserves the blue hue on white cards.
        let expected = UIColor(red: 0.19929830, green: 0.47499428, blue: 0.73408207, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "venice")).isApproximately(expected))
    }

    /// `openai` is the providerID for both ChatGPT browser cookie scraping
    /// (existing) AND the new v0.25 "OpenAI API balance" provider. The new
    /// catch-up release reuses the existing .green rule rather than splitting
    /// into a separate color — both surfaces represent the same upstream
    /// brand, and SyncCoordinator emits records under the same providerID.
    @Test("OpenAI API balance inherits existing ChatGPT green (no new color for `openai`)")
    func openaiApiBalanceInheritsChatGPTGreen() {
        let openai = UIColor(ProviderColorPalette.color(for: "openai"))
        let chatgpt = UIColor(ProviderColorPalette.color(for: "chatgpt"))
        #expect(openai.isApproximately(chatgpt))
        #expect(openai.isApproximately(UIColor(.green)))
    }

    /// Cause-oriented: substring specificity. `commandcode` and `codebuff`
    /// both contain "code" but there's NO broad `contains("code")` rule;
    /// each has its own `if`. A future refactor that introduces a generic
    /// "code" rule above these would silently collapse them — pin the
    /// invariant.
    @Test("Specificity: commandcode and codebuff do not collide")
    func codeFamilyDoesNotCollide() {
        let cc = UIColor(ProviderColorPalette.color(for: "commandcode"))
        let cb = UIColor(ProviderColorPalette.color(for: "codebuff"))
        #expect(!cc.isApproximately(cb), "commandcode and codebuff must be distinct")
    }

    /// Cause-oriented: stepfun violet and manus violet are intentionally
    /// similar (the brighter sibling). A future tuning that drifts them
    /// closer than `delta=0.10` would lose the "bright vs medium" hierarchy.
    @Test("Cause: stepfun (bright violet) distinct from manus (medium violet)")
    func stepfunDistinctFromManus() {
        let sf = UIColor(ProviderColorPalette.color(for: "stepfun"))
        let manus = UIColor(ProviderColorPalette.color(for: "manus"))
        var sR: CGFloat = 0; var sG: CGFloat = 0; var sB: CGFloat = 0; var sA: CGFloat = 0
        var mR: CGFloat = 0; var mG: CGFloat = 0; var mB: CGFloat = 0; var mA: CGFloat = 0
        _ = sf.getRed(&sR, green: &sG, blue: &sB, alpha: &sA)
        _ = manus.getRed(&mR, green: &mG, blue: &mB, alpha: &mA)
        let delta = abs(sR - mR) + abs(sG - mG) + abs(sB - mB)
        #expect(delta > 0.10, "stepfun and manus must stay distinguishable (Δ=\(delta))")
    }

    /// Cause-oriented: Crof amber sits between Abacus brown and a yellow
    /// zone. A future tuning that brightens Abacus closer to Crof would
    /// regress visual distinguishability of the warm-tone family.
    @Test("Cause: Crof amber distinct from Abacus brown")
    func crofDistinctFromAbacus() {
        let crof = UIColor(ProviderColorPalette.color(for: "crof"))
        let abacus = UIColor(ProviderColorPalette.color(for: "abacus"))
        var crR: CGFloat = 0; var crG: CGFloat = 0; var crB: CGFloat = 0; var crA: CGFloat = 0
        var abR: CGFloat = 0; var abG: CGFloat = 0; var abB: CGFloat = 0; var abA: CGFloat = 0
        _ = crof.getRed(&crR, green: &crG, blue: &crB, alpha: &crA)
        _ = abacus.getRed(&abR, green: &abG, blue: &abB, alpha: &abA)
        let delta = abs(crR - abR) + abs(crG - abG) + abs(crB - abB)
        #expect(delta > 0.10, "Crof and Abacus must stay distinguishable (Δ=\(delta))")
    }

    /// Cause-oriented: MiMo orange is intentionally brighter than Claude
    /// orange-tan to avoid mid-tone collision. Pin the delta so a future
    /// "softer orange" tuning of MiMo doesn't walk it into Claude's color.
    @Test("Cause: MiMo bright orange distinct from Claude orange-tan")
    func mimoDistinctFromClaude() {
        let mimo = UIColor(ProviderColorPalette.color(for: "mimo"))
        let claude = UIColor(ProviderColorPalette.color(for: "claude"))
        var mR: CGFloat = 0; var mG: CGFloat = 0; var mB: CGFloat = 0; var mA: CGFloat = 0
        var cR: CGFloat = 0; var cG: CGFloat = 0; var cB: CGFloat = 0; var cA: CGFloat = 0
        _ = mimo.getRed(&mR, green: &mG, blue: &mB, alpha: &mA)
        _ = claude.getRed(&cR, green: &cG, blue: &cB, alpha: &cA)
        let delta = abs(mR - cR) + abs(mG - cG) + abs(mB - cB)
        #expect(delta > 0.10, "MiMo and Claude must stay distinguishable (Δ=\(delta))")
    }

    /// Cause-oriented: Doubao hot pink sits between Mistral red and a
    /// pinker zone. Tuning either too close would collapse two distinct
    /// "warm" providers into visually-identical cards.
    @Test("Cause: Doubao hot pink distinct from Mistral red")
    func doubaoDistinctFromMistral() {
        let doubao = UIColor(ProviderColorPalette.color(for: "doubao"))
        let mistral = UIColor(ProviderColorPalette.color(for: "mistral"))
        var dR: CGFloat = 0; var dG: CGFloat = 0; var dB: CGFloat = 0; var dA: CGFloat = 0
        var mR: CGFloat = 0; var mG: CGFloat = 0; var mB: CGFloat = 0; var mA: CGFloat = 0
        _ = doubao.getRed(&dR, green: &dG, blue: &dB, alpha: &dA)
        _ = mistral.getRed(&mR, green: &mG, blue: &mB, alpha: &mA)
        let delta = abs(dR - mR) + abs(dG - mG) + abs(dB - mB)
        #expect(delta > 0.10, "Doubao and Mistral must stay distinguishable (Δ=\(delta))")
    }

    /// New 1.6.0 providers must still leave the unknown fallback intact
    /// at `.blue`. Defends against an accidental edit that moves the
    /// fallback into a specific new color.
    @Test("Cause: unknown provider unchanged at .blue after 1.6.0 additions")
    func unknownStillBlueAfter160() {
        #expect(
            UIColor(ProviderColorPalette.color(for: "future-llm-provider-2026"))
                .isApproximately(UIColor(.blue)))
    }

    /// Normalization sanity for spaces. `"Command Code"` and `"commandcode"`
    /// must resolve to the same color so calling sites that pass display
    /// name don't drift.
    @Test("Command Code normalization: ID and displayName resolve identically")
    func commandcodeNormalization() {
        let byID = UIColor(ProviderColorPalette.color(for: "commandcode"))
        let byName = UIColor(ProviderColorPalette.color(for: "Command Code"))
        #expect(byID.isApproximately(byName))
    }

    // MARK: - iOS 1.12.0 · Devin catch-up

    @Test("Devin follows the v0.70 blue brand color")
    func devinIsBlueGreen() {
        let expected = UIColor(red: 0.17418413, green: 0.44079250, blue: 0.90646846, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "devin")).isApproximately(expected))
    }

    @Test("Devin normalization: ID and displayName resolve identically")
    func devinNormalization() {
        let byID = UIColor(ProviderColorPalette.color(for: "devin"))
        let byName = UIColor(ProviderColorPalette.color(for: "Devin"))
        #expect(byID.isApproximately(byName))
    }

    // MARK: - iOS 1.13.0 · v0.36 provider catch-up

    @Test("LiteLLM resolves to proxy blue")
    func litellmIsProxyBlue() {
        let expected = UIColor(red: 0.10, green: 0.38, blue: 0.72, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "litellm")).isApproximately(expected))
    }

    @Test("Poe resolves to saturated violet")
    func poeIsViolet() {
        let expected = UIColor(red: 0.43, green: 0.28, blue: 0.86, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "poe")).isApproximately(expected))
    }

    @Test("Chutes resolves to green-teal")
    func chutesIsGreenTeal() {
        let expected = UIColor(red: 0.02, green: 0.62, blue: 0.45, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "chutes")).isApproximately(expected))
    }

    @Test("Zed resolves to graphite")
    func zedIsGraphite() {
        let expected = UIColor(red: 0.20, green: 0.23, blue: 0.28, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "zed")).isApproximately(expected))
    }

    @Test("LiteLLM normalization and LLM Proxy do not collide")
    func litellmDoesNotCollideWithLLMProxy() {
        let byID = UIColor(ProviderColorPalette.color(for: "litellm"))
        let byName = UIColor(ProviderColorPalette.color(for: "LiteLLM"))
        let proxy = UIColor(ProviderColorPalette.color(for: "llmproxy"))
        #expect(byID.isApproximately(byName))
        #expect(!byID.isApproximately(proxy), "LiteLLM and LLM Proxy must stay visually distinct")
    }

    @Test("Zed and z.ai do not collide")
    func zedDoesNotCollideWithZai() {
        let zed = UIColor(ProviderColorPalette.color(for: "zed"))
        let zai = UIColor(ProviderColorPalette.color(for: "zai"))
        #expect(!zed.isApproximately(zai), "Zed and z.ai must stay visually distinct")
    }

    // MARK: - iOS 1.17.0 · v0.38/v0.39 provider catch-up

    @Test("Sakana AI resolves to ocean blue")
    func sakanaIsOceanBlue() {
        let expected = UIColor(red: 0.16, green: 0.46, blue: 0.86, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "sakana")).isApproximately(expected))
    }

    @Test("Qoder resolves to emerald")
    func qoderIsEmerald() {
        let expected = UIColor(red: 16.0 / 255.0, green: 185.0 / 255.0, blue: 129.0 / 255.0, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "qoder")).isApproximately(expected))
    }

    @Test("CrossModel resolves to violet")
    func crossModelIsViolet() {
        let expected = UIColor(red: 124.0 / 255.0, green: 58.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "crossmodel")).isApproximately(expected))
    }

    @Test("ClawRouter resolves to periwinkle")
    func clawRouterIsPeriwinkle() {
        let expected = UIColor(red: 89.0 / 255.0, green: 110.0 / 255.0, blue: 246.0 / 255.0, alpha: 1)
        #expect(UIColor(ProviderColorPalette.color(for: "clawrouter")).isApproximately(expected))
    }

    @Test("CrossModel normalization and Codex do not collide")
    func crossModelDoesNotCollideWithCodex() {
        let byID = UIColor(ProviderColorPalette.color(for: "crossmodel"))
        let byName = UIColor(ProviderColorPalette.color(for: "CrossModel"))
        let codex = UIColor(ProviderColorPalette.color(for: "codex"))
        #expect(byID.isApproximately(byName))
        #expect(!byID.isApproximately(codex), "CrossModel and Codex must stay visually distinct")
    }

    @Test("ClawRouter normalization accepts hyphenated input")
    func clawRouterNormalization() {
        let byID = UIColor(ProviderColorPalette.color(for: "clawrouter"))
        let byHyphen = UIColor(ProviderColorPalette.color(for: "claw-router"))
        #expect(byID.isApproximately(byHyphen))
    }

    // MARK: - iOS 1.19.0 · v0.42-v0.45 provider catch-up

    @Test("v0.42-v0.45 provider colors are distinct from the generic blue fallback")
    func v045ProviderColorsAreExplicit() {
        let fallback = UIColor(ProviderColorPalette.color(for: "unknown-provider"))
        let ids = [
            "clinepass", "deepinfra", "neuralwatt", "longcat",
            "sub2api", "wayfinder", "zenmux", "aiand",
        ]
        for id in ids {
            let color = UIColor(ProviderColorPalette.color(for: id))
            #expect(!color.isApproximately(fallback), "\(id) must not use the generic fallback color")
        }
    }

    @Test("v0.42-v0.45 provider color normalization accepts display-name variants")
    func v045ProviderColorNormalization() {
        let pairs = [
            ("clinepass", "Cline-Pass"),
            ("deepinfra", "Deep-Infra"),
            ("neuralwatt", "Neural-Watt"),
            ("longcat", "Long-Cat"),
            ("sub2api", "Sub-2-API"),
            ("wayfinder", "Way-Finder"),
            ("zenmux", "Zen-Mux"),
            ("aiand", "ai&"),
        ]
        for (id, name) in pairs {
            #expect(
                UIColor(ProviderColorPalette.color(for: id))
                    .isApproximately(UIColor(ProviderColorPalette.color(for: name))))
        }
    }

    // MARK: - iOS 1.20.0 · v0.46-v0.47 provider catch-up

    @Test("v0.46-v0.47 provider colors are distinct from the generic blue fallback")
    func v047ProviderColorsAreExplicit() {
        let fallback = UIColor(ProviderColorPalette.color(for: "unknown-provider"))
        for id in ["qwencloud", "zoommate", "xai", "notion"] {
            #expect(
                !UIColor(ProviderColorPalette.color(for: id)).isApproximately(fallback),
                "\(id) must not use the generic fallback color")
        }
    }

    @Test("v0.46-v0.47 provider color normalization accepts display-name variants")
    func v047ProviderColorNormalization() {
        let pairs = [
            ("qwencloud", "Qwen-Cloud"),
            ("zoommate", "Zoom-Mate"),
            ("xai", "x-ai"),
            ("notion", "Notion AI"),
        ]
        for (id, name) in pairs {
            #expect(
                UIColor(ProviderColorPalette.color(for: id))
                    .isApproximately(UIColor(ProviderColorPalette.color(for: name))))
        }
    }

    @Test("v0.67 provider colors have explicit non-fallback tints")
    func v067ProviderColorsAreExplicit() {
        let fallback = UIColor(ProviderColorPalette.color(for: "unknown-provider"))
        for id in ["xkiro", "raycast", "aixy"] {
            #expect(
                !UIColor(ProviderColorPalette.color(for: id)).isApproximately(fallback),
                "\(id) must not use the generic fallback color")
        }
    }

    @Test("v0.67 provider colors normalize display-name variants")
    func v067ProviderColorNormalization() {
        let pairs = [("xkiro", "xKiro"), ("raycast", "Raycast"), ("aixy", "Aixy")]
        for (id, name) in pairs {
            #expect(
                UIColor(ProviderColorPalette.color(for: id))
                    .isApproximately(UIColor(ProviderColorPalette.color(for: name))))
        }
    }

    @Test("v0.72 provider colors use upstream brand tints")
    func v072ProviderColorsMatchUpstreamBrands() {
        let expected = [
            ("museai", UIColor(red: 6 / 255, green: 104 / 255, blue: 225 / 255, alpha: 1)),
            ("lithosai", UIColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1)),
            ("workbuddy", UIColor(red: 13 / 255, green: 200 / 255, blue: 166 / 255, alpha: 1)),
        ]
        for (id, color) in expected {
            #expect(UIColor(ProviderColorPalette.color(for: id)).isApproximately(color), "\(id)")
        }
    }

    @Test("muse.ai never borrows the Muse Code tint")
    func v072MuseAIIsDistinctFromMuseCode() {
        let museCode = UIColor(ProviderColorPalette.color(for: "muse"))
        for name in ["museai", "Muse (muse.ai)"] {
            #expect(!UIColor(ProviderColorPalette.color(for: name)).isApproximately(museCode), "\(name)")
        }
        let pairs = [("museai", "Muse (muse.ai)"), ("lithosai", "LithosAI"), ("workbuddy", "WorkBuddy")]
        for (id, name) in pairs {
            #expect(
                UIColor(ProviderColorPalette.color(for: id))
                    .isApproximately(UIColor(ProviderColorPalette.color(for: name))))
        }
    }
}

@Suite("Provider color dark-mode contrast")
struct ProviderColorContrastTests {
    private func snapshot(_ tint: String?) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "grok",
            providerName: "Grok",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 0),
            providerIconTintHex: tint)
    }

    private func resolved(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return ProviderColorPalette.relativeLuminance(red: r, green: g, blue: b)
    }

    private func contrast(_ foreground: UIColor, against background: UIColor) -> CGFloat {
        let values = [self.luminance(foreground), self.luminance(background)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }

    @Test
    func `Near-black provider tints are lifted to a readable shade in dark mode`() {
        for id in ["grok", "xai", "zed", "windsurf"] {
            let color = ProviderColorPalette.color(for: id)
            #expect(self.contrast(
                self.resolved(color, .dark),
                against: UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)) >= 4.5)
            #expect(self.luminance(self.resolved(color, .light)) < 0.05)
        }
    }

    @Test
    func `Synced black icon tint is lifted in dark mode through the snapshot path`() {
        let color = ProviderColorPalette.color(for: self.snapshot("#000000"))
        #expect(self.luminance(self.resolved(color, .dark)) >= 0.239)
        #expect(self.luminance(self.resolved(color, .light)) < 0.001)
    }

    @Test(arguments: ["#FFFFFF", "#FFFF00"])
    func `Synced pale icon tint darkens on light cards without dimming in dark mode`(hex: String) {
        let color = ProviderColorPalette.color(for: self.snapshot(hex))
        #expect(self.contrast(self.resolved(color, .light), against: .white) >= 4.5)
        #expect(self.luminance(self.resolved(color, .dark)) > 0.9)
    }

    @Test
    func `Invalid synced tint falls back to the provider palette in both appearances`() {
        let fallback = ProviderColorPalette.color(for: "grok")
        let invalid = ProviderColorPalette.color(for: self.snapshot("not-a-hex-color"))
        #expect(self.resolved(invalid, .light).isApproximately(self.resolved(fallback, .light)))
        #expect(self.resolved(invalid, .dark).isApproximately(self.resolved(fallback, .dark)))
    }

    @Test
    func `Older Mac snapshot without a tint uses the same readable palette`() {
        let fallback = ProviderColorPalette.color(for: "grok")
        let oldSnapshot = ProviderColorPalette.color(for: self.snapshot(nil))
        #expect(self.resolved(oldSnapshot, .light).isApproximately(self.resolved(fallback, .light)))
        #expect(self.resolved(oldSnapshot, .dark).isApproximately(self.resolved(fallback, .dark)))
    }

    @Test
    func `Bright tints are unchanged in dark mode`() {
        let claude = ProviderColorPalette.color(for: "claude")
        let dark = self.resolved(claude, .dark)
        let light = self.resolved(claude, .light)
        #expect(dark.isApproximately(light))
    }
}

// MARK: - Test helpers

extension UIColor {
    /// Tolerance-based RGBA comparison. Two SwiftUI `Color`s round-trip through
    /// `UIColor` and pick up tiny float drift; a hard `==` would fail.
    fileprivate func isApproximately(_ other: UIColor, tolerance: CGFloat = 0.02) -> Bool {
        var lhsR: CGFloat = 0; var lhsG: CGFloat = 0
        var lhsB: CGFloat = 0; var lhsA: CGFloat = 0
        var rhsR: CGFloat = 0; var rhsG: CGFloat = 0
        var rhsB: CGFloat = 0; var rhsA: CGFloat = 0
        // Brand pins are light-mode values; dark mode may lift them
        // (ProviderColorPalette.readable), so resolve independent of the
        // simulator's appearance.
        let light = UITraitCollection(userInterfaceStyle: .light)
        guard
            resolvedColor(with: light).getRed(&lhsR, green: &lhsG, blue: &lhsB, alpha: &lhsA),
            other.resolvedColor(with: light).getRed(&rhsR, green: &rhsG, blue: &rhsB, alpha: &rhsA)
        else {
            return false
        }
        return abs(lhsR - rhsR) < tolerance
            && abs(lhsG - rhsG) < tolerance
            && abs(lhsB - rhsB) < tolerance
            && abs(lhsA - rhsA) < tolerance
    }
}
