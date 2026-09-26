# Provider tint contrast in iOS

Status: in-progress

## Context

PR #140 fixes near-black provider colors on dark Usage cards. The iOS color
palette feeds Usage, provider details, Cost sharing, and token activity. Mac
snapshots may also supply a custom `providerIconTintHex`; this is not limited to
the built-in palette.

## Findings

- In Dark Mode, near-black built-in or synced tints make Usage percentages,
  progress bars, detail labels, and chart accents hard to see. The original PR
  raises low-luminance colors but targets 0.2 relative luminance, which is only
  about 4:1 against the cited `#1C1C1E` card color.
- A near-white tint supplied by Mac is the symmetric failure in Light Mode.
  The original PR deliberately leaves all Light Mode tints unchanged, so this
  case remains invisible on a pale card.
- The Usage card uses an ultra-thin material, so a fixed hex card color is an
  approximation. The contrast target should leave margin for light material
  variation and preserve built-in brand colors in Light Mode.
- The sync payload, CloudKit schema, and merge logic are unchanged. Only iOS
  rendering changes, including rendering on mixed app versions; the canonical
  sync compatibility gate therefore applies.

## Design

1. Keep the PR's dynamic UIKit color resolution so Dark Mode changes apply
   across all palette consumers, including provider details and charts.
2. Raise the dark-mode floor to at least 0.24 relative luminance (above 4.5:1
   against `#1C1C1E`).
3. Apply a light-mode ceiling of 0.18 only to Mac-supplied hex tints. Blend
   brighter tints toward black just enough to clear 4.5:1 against white.
   Built-in Light Mode brand colors remain pinned.
4. Cover both palette entry points, appearance changes, near-black and
   near-white synced colors, and invalid tint fallback in focused tests.
5. Use iOS 2.1.0 build 213 for the fix. Update technical and four-language
   in-app release notes in the existing 2.1.0 block.

## Validation

- Focused palette tests and the iOS build/test gate on a signed simulator,
  with all build artifacts on StudioSSD. The unsigned simulator launch failed
  at the CloudKit entitlement gate before executing tests.
- Inspect a current render of the production Usage card in both appearances
  if a simulator or preview is available.
- Record the 16 combinations from `docs/ios-sync-compatibility-testing.md` in
  `03-testing.md`, distinguishing real-device checks from substituted evidence.
- Review the final diff, push to PR #140 if allowed, request Codex review on
  the exact head, fix findings, and request a fresh review after every push.
