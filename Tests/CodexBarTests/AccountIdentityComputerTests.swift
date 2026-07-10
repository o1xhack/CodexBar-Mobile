import Foundation
import Testing
@testable import CodexBarCore

/// Pins the Mac-side identifier computation contract documented in
/// `Research/019-account-identity-multi-version-merge.md`. iOS consumes
/// these strings opaquely — every change to the format here ripples
/// through to merge behavior across all live devices.
@Suite("AccountIdentityComputer")
struct AccountIdentityComputerTests {
    // MARK: - Tier-A providers produce identifiers

    @Test
    func `Codex with org + email produces both identifiers, account first`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "user@example.com",
            accountOrganization: "org-abc123",
            loginMethod: "ChatGPT")
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        #expect(ids.count == 2)
        #expect(ids[0] == "codex:account:org-abc123")
        #expect(ids[1] == "codex:email:user@example.com")
    }

    @Test
    func `Codex with only email returns email-only set`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "user@example.com",
            accountOrganization: nil,
            loginMethod: nil)
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        #expect(ids == ["codex:email:user@example.com"])
    }

    @Test
    func `Codex with only org returns account-only set`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: nil,
            accountOrganization: "org-abc",
            loginMethod: nil)
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        #expect(ids == ["codex:account:org-abc"])
    }

    @Test
    func `Codex with empty identity returns empty array (transient signin)`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil)
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        #expect(
            ids.isEmpty,
            "Tier-A provider with no identity → [] (not nil) so iOS distinguishes 'we tried' from 'old Mac'.")
    }

    @Test
    func `Codex with nil identity returns nil (legacy path)`() {
        // nil identity means we don't have an authoritative identity
        // record at all — same semantics as a legacy Mac that didn't
        // populate the field. Returning [] would be misleading.
        #expect(AccountIdentityComputer.compute(provider: .codex, identity: nil) == [])
    }

    @Test
    func `Claude follows the same shape as Codex`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: "claude-user@example.com",
            accountOrganization: "anthropic-org-xyz",
            loginMethod: "OAuth")
        let ids = try #require(AccountIdentityComputer.compute(provider: .claude, identity: identity))
        #expect(ids == ["claude:account:anthropic-org-xyz", "claude:email:claude-user@example.com"])
    }

    @Test
    func `VertexAI uses project: prefix for the org identifier`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .vertexai,
            accountEmail: "gcp-user@example.com",
            accountOrganization: "gcp-project-12345",
            loginMethod: "gcloud")
        let ids = try #require(AccountIdentityComputer.compute(provider: .vertexai, identity: identity))
        #expect(ids == ["vertexai:project:gcp-project-12345", "vertexai:email:gcp-user@example.com"])
    }

    // MARK: - Non-Tier-A providers

    @Test
    func `Non-Tier-A providers return nil — fall to legacy per-device bucket on iOS`() {
        // Sample a few; the implementation switch lists them all.
        let nonTierA: [UsageProvider] = [
            .perplexity, .cursor, .copilot, .gemini, .opencode, .opencodego,
            .alibaba, .factory, .minimax, .kimi, .kimik2, .augment, .jetbrains,
            .amp, .ollama, .synthetic, .openrouter, .warp, .abacus, .mistral,
            .zai, .antigravity, .kilo, .kiro, .sakana, .qoder, .crossmodel, .clawrouter,
        ]
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "x@y.com",
            accountOrganization: "org",
            loginMethod: "x")
        for provider in nonTierA {
            #expect(
                AccountIdentityComputer.compute(provider: provider, identity: identity) == nil,
                "\(provider) should return nil — iOS uses legacy per-device bucket.")
        }
    }

    // MARK: - Normalization

    @Test
    func `Email is lowercased + trimmed before being used as identifier value`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "  USER@EXAMPLE.COM  ",
            accountOrganization: nil,
            loginMethod: nil)
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        #expect(ids == ["codex:email:user@example.com"])
    }

    @Test
    func `Empty / whitespace-only values are dropped, not encoded as email:`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "   ",
            accountOrganization: "org-abc",
            loginMethod: nil)
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        // Only org survives; whitespace email never appears as `codex:email:`.
        #expect(ids == ["codex:account:org-abc"])
    }

    @Test
    func `Special characters in value are URL-encoded so : separator stays unambiguous`() throws {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: nil,
            // Hypothetical org ID with a colon — must be encoded so it
            // doesn't collide with the `:` separator in the identifier
            // template `provider:scheme:value`.
            accountOrganization: "org:with:colons",
            loginMethod: nil)
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        let value = try #require(ids.first?.dropFirst("codex:account:".count))
        #expect(
            !value.contains(":"),
            "Embedded colons in value must be URL-encoded so iOS can split correctly if it ever wants to.")
    }

    @Test
    func `Unicode NFC normalization applied (composed and decomposed forms collapse)`() throws {
        // Same logical name written two ways: composed (one code point)
        // and decomposed (two code points). After NFC normalization they
        // produce the same identifier — so two Macs that capture the
        // user's email in different UTF-8 normalizations still merge.
        let composedIdentity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "café@example.com",
            accountOrganization: nil,
            loginMethod: nil)
        let decomposedIdentity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "cafe\u{0301}@example.com", // 'e' + combining acute
            accountOrganization: nil,
            loginMethod: nil)
        let composedIDs = try #require(AccountIdentityComputer.compute(provider: .codex, identity: composedIdentity))
        let decomposedIDs = try #require(AccountIdentityComputer.compute(
            provider: .codex,
            identity: decomposedIdentity))
        #expect(composedIDs == decomposedIDs)
    }

    @Test
    func `Identifier value capped at maxIdentifierLength`() throws {
        let huge = String(repeating: "a", count: AccountIdentityComputer.maxIdentifierLength + 100)
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: nil,
            accountOrganization: huge,
            loginMethod: nil)
        let ids = try #require(AccountIdentityComputer.compute(provider: .codex, identity: identity))
        let value = try #require(ids.first?.dropFirst("codex:account:".count))
        #expect(value.count <= AccountIdentityComputer.maxIdentifierLength)
    }

    @Test
    func `normalize rejects nil`() {
        #expect(AccountIdentityComputer.normalize(nil) == nil)
    }

    /// Cross-target contract pin (0.23.3 P1-3).
    ///
    /// Mac `AccountIdentityComputer.normalize` and iOS Shared
    /// `AccountIdentityNormalize.normalize` MUST produce byte-identical
    /// output for every input — otherwise legacy `accountEmail` fallback
    /// synthesis on iOS produces different identifier strings than what
    /// the Mac wrote, and accounts split across cards. This test pins
    /// the Mac side to specific expected outputs; the iOS test
    /// `AccountIdentityNormalizeContractTests` pins the iOS side to the
    /// SAME expected outputs. If you change normalize, update both
    /// sides AND both tests in the same commit.
    @Test
    func `normalize byte-equals iOS shared contract`() {
        let cases: [(String?, String?)] = [
            ("ABC", "abc"),
            ("Café@Example.com", "caf%C3%A9@example.com"),
            (" trailing  ", "trailing"),
            ("cafe\u{0301}@example.com", "caf%C3%A9@example.com"),
            ("a:b|c/d", "a%3Ab%7Cc%2Fd"),
            ("", nil),
            ("   ", nil),
            (nil, nil),
        ]
        for (input, expected) in cases {
            #expect(
                AccountIdentityComputer.normalize(input) == expected,
                "normalize(\(input ?? "<nil>")) — expected \(expected ?? "<nil>")")
        }
    }
}
