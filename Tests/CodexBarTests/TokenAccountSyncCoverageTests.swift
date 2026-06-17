import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Coverage pin — Fork's `SyncCoordinator.tokenBasedMultiAccountProviders`
/// MUST equal `TokenAccountSupportCatalog.allProviders` byte-for-byte.
///
/// Pre-Phase-G this list was hardcoded in `SyncCoordinator.swift` and
/// drifted behind catalog updates by 7 providers (openai, deepseek,
/// antigravity, manus, copilot, venice, stepfun) — every one of which
/// silently lost multi-account sync because Mac stopped pushing per-
/// account snapshots through the wire envelope. iOS displayed only the
/// active account; user discovered the gap by clicking into OpenAI on
/// iPhone and seeing only `admin-msxiao113` while Mac had both
/// `admin-msxiao113` and `admin-outlook` as switchable tabs.
///
/// This test catches the regression at build time: any upstream merge
/// that adds a new token-account provider (or any future fork change
/// that touches either side) fails the build unless both are in sync.
@MainActor
@Suite("Token-account sync coverage — catalog ⇔ SyncCoordinator")
struct TokenAccountSyncCoverageTests {
    @Test("SyncCoordinator.tokenBasedMultiAccountProviders mirrors TokenAccountSupportCatalog.allProviders")
    func syncListMirrorsCatalog() {
        let syncList = Set(SyncCoordinator.tokenBasedMultiAccountProvidersForTesting)
        let catalog = Set(TokenAccountSupportCatalog.allProviders)
        let missingFromSync = catalog.subtracting(syncList)
        let extraInSync = syncList.subtracting(catalog)
        // Providers in catalog but NOT in sync list silently lose
        // multi-account on iOS (Phase G regression class).
        #expect(missingFromSync.isEmpty, "Missing: \(missingFromSync.map(\.rawValue).sorted())")
        // Providers in sync list but NOT in catalog would crash on
        // fetch (no token-account support).
        #expect(extraInSync.isEmpty, "Extra: \(extraInSync.map(\.rawValue).sorted())")
    }

    @Test("Catalog contains the 22 providers known through v0.36.1 (regression sentinel)")
    func catalogContainsExpectedProviders() {
        // v0.36.1 baseline — 22 providers in TokenAccountSupportCatalog.
        //   Phase G (v0.26.x) added the first 18: openai/claude/deepseek/
        //     antigravity/zai/cursor/opencode/opencodego/factory/minimax/
        //     manus/augment/ollama/abacus/mistral/copilot/venice/stepfun.
        //   v0.27.0 added 3 more: elevenlabs, groq, llmproxy (all API-key
        //     style providers).
        //   v0.36.1 added LiteLLM API-key token accounts; Poe/Chutes/Zed do
        //     not expose token-account catalog support.
        // If this count changes (up or down), confirm the catalog change
        // was intentional. The set is deliberately listed verbatim — if
        // upstream renames or removes a provider, this test fails loudly
        // rather than silently shipping a regressed sync.
        let expected: Set<String> = [
            "openai", "claude", "deepseek", "antigravity", "zai",
            "cursor", "opencode", "opencodego", "factory", "minimax",
            "manus", "augment", "ollama", "abacus", "mistral",
            "copilot", "venice", "stepfun",
            // v0.27.0 additions
            "elevenlabs", "groq", "llmproxy",
            // v0.36.1 additions
            "litellm",
        ]
        let actual = Set(TokenAccountSupportCatalog.allProviders.map(\.rawValue))
        let added = actual.subtracting(expected)
        let removed = expected.subtracting(actual)
        #expect(
            added.isEmpty,
            "Catalog gained providers since Phase G baseline (verify intent + bump expected set): \(added.sorted())")
        #expect(
            removed.isEmpty,
            "Catalog lost providers since Phase G baseline (verify upstream rename / removal): \(removed.sorted())")
    }

    @Test("Catalog providers are ordered deterministically (stable sort by rawValue)")
    func catalogIsStablySorted() {
        let providers = TokenAccountSupportCatalog.allProviders
        let raws = providers.map(\.rawValue)
        let sorted = raws.sorted()
        #expect(raws == sorted, "allProviders must be sorted by rawValue for determinism across launches")
    }
}
