---
summary: "Official artwork used by spend chart legends and amount inspectors."
read_when:
  - Updating spend chart provider icons
---

# Spend chart provider artwork

Chart legends and amount inspectors request `ProviderBrandIcon.Style.brand`. Brand images retain
their original colors; a separate account color swatch matches the chart. Provider headings and
subscription summaries also use brand artwork, while account/source and model child rows retain
adaptive monochrome artwork. Menu bar and other settings callers keep the default monochrome style.
OpenCodex sources retain their branch symbol.

All production Usage & Spend provider icons share a 20-point square slot, including chart legends,
amount inspectors, provider headings, account/source rows, model rows and subscription summaries.
Rendering tests can enlarge the slot for pixel inspection. Codex, Antigravity and Cursor
use display scales of 1.17, 1.38 and 1.25 to compensate for transparent padding. The monochrome Codex and Antigravity SVGs use scales of 1.24 and 1.14.
Bedrock, Muse and Vertex AI retain the optical corrections documented in
[provider-brand-icons.md](provider-brand-icons.md).
Source image bytes and aspect ratios remain unchanged. Both chart
locations use the same 8-point account swatch.

Brand and monochrome images have independent cache entries. Curated assets are keyed by product
identity, so OpenAI API and Azure OpenAI do not inherit Codex artwork from their shared legacy
monochrome resource. Providers without curated artwork fall back to the existing adaptive template,
including Cursor's cube mark. Cursor's official
[brand guidelines](https://cursor.com/brand) provide light and dark variants of its monochrome mark;
the orange chart swatch must not recolor the logo.

Verified 2026-10-07. Artwork identifies third-party products and remains owned by its creators.
Assets load from the application bundle without any network requests.

| Resource | Primary source and verification | Transformation |
| --- | --- | --- |
| `Brand-ProviderIcon-codex.png` | Official Codex app, bundle `com.openai.codex`, version `26.928.31416`, signing team `2DC432GLL2`; [Codex product page](https://openai.com/codex/). Provenance verified in [provider-brand-icons.md](provider-brand-icons.md). | Unmodified transparent PNG from `Contents/Resources/app.asar`, `webview/assets/codex-app-ga-logo-3e5209898ca3.png`. Preserves the blue/purple gradient and white terminal mark; no cropping or recoloring. |
| `Brand-ProviderIcon-antigravity.png` | [Official homepage image](https://antigravity.google/assets/image/antigravity-logo.png), downloaded and hashed directly | Unmodified transparent PNG. Retains the official multicolor gradient, which native SVG decoding can flatten. |

| Bundled resource | SHA-256 |
| --- | --- |
| `Brand-ProviderIcon-codex.png` | `8e82b26c98a10e45798ce48124515720657f7735fb8d0853b3f087eaa8a6b74e` |
| `Brand-ProviderIcon-antigravity.png` | `193ba1805de11c23cd0c7a1df92aa0a886708e57350f6f7766100afe5befed73` |

Resource tests check separate caches in both load orders, original color pixels, transparent padding,
and adaptive fallback. Offline production view renders cover light/dark appearances and narrow widths.
