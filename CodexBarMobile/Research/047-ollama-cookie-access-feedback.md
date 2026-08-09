# Ollama Browser Cookie Access Feedback

Status: done

Date: 2026-08-09

## Evidence

- The supplied screenshot shows Chrome signed in at ollama.com/settings while CodexBar reports "No Ollama session cookie found".
- The active Chrome profile has one Ollama session row in Default/Cookies: host ollama.com, name __Secure-session, persistent, unexpired, with encrypted value prefix v10. Cookie values were not read or retained.
- BrowserCookieClient discovers the same Chrome Default store, but the live importer probe reports that Chrome Safe Storage needs Keychain interaction. A background probe skips the read to avoid showing a macOS prompt; an explicit retry reaches the interaction-required path and would show a prompt.
- The installed binary is 0.45.2.2 (CodexGitCommit=c1fc1e29, built 2026-07-27), before the repository's later background-cookie authorization change (a3883384).

## Root cause

When a background refresh sees an installed Chrome cookie store but the no-UI Safe Storage preflight returns .interactionRequired, BrowserCookieAccessGate correctly skips the read. OllamaCookieImporter does not preserve that reason, so fallback import ends as the generic noSessionCookie error. The UI therefore tells a signed-in user to sign in again and gives no indication that a manual refresh is required to authorize Chrome Safe Storage.

## Design

Expose the existing localized Keychain-retry error when the no-UI preflight reports that interaction is required. The cookie gate exposes that diagnostic state; the importer uses it only when a browser source was suppressed. Background refreshes remain prompt-free. Reusing the existing error and UI mapper keeps the recovery copy localized and tells the user to open the provider card and click Refresh, which runs the existing explicit-retry path.

This change does not read cookie values, disable Keychain protections, or alter the separate Ollama Cloud/iPhone sync durability fix.

## Acceptance

- A background interaction-required Chrome import produces the recovery error, not noSessionCookie.
- A real no-cookie condition still produces noSessionCookie.
- Explicit retry behavior is unchanged.
- Focused Ollama and browser-gate tests pass; no test performs a real Keychain read.
