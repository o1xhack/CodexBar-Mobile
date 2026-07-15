import Foundation
import Testing
@testable import CodexBarSync

/// Unit tests for the `EmailRedaction.redact` helper introduced in
/// Mac build 65.4 / iOS 1.8.0 build 136. Pins the edge-case behaviour
/// so a future refactor doesn't silently regress and start leaking
/// full emails into OSLog / NSE diagnostic logs.
///
/// Build 137 / 65.5 — added per Opus 4.7 second-pass CR follow-up.
@Suite("EmailRedaction")
struct EmailRedactionTests {
    @Test
    func `nil → '<nil>'`() {
        #expect(EmailRedaction.redact(nil) == "<nil>")
    }

    @Test
    func `empty string → '<empty>'`() {
        #expect(EmailRedaction.redact("") == "<empty>")
        // Whitespace-only is normalised to empty after trim.
        #expect(EmailRedaction.redact("   ") == "<empty>")
    }

    @Test
    func `no @ → returned verbatim (non-email identity strings)`() {
        // Mac's writeQuotaTransition only writes emails to this field,
        // but other call sites may pass identity strings that aren't
        // emails (loginMethod, accountID). Pass them through so logs
        // stay debuggable; only emails get the redaction treatment.
        #expect(EmailRedaction.redact("plain-username") == "plain-username")
        #expect(EmailRedaction.redact("opaque-account-id-123") == "opaque-account-id-123")
    }

    @Test
    func `standard email → '<first-char>***@<domain>'`() {
        #expect(EmailRedaction.redact("admin@example.com") == "a***@example.com")
        #expect(EmailRedaction.redact("yuxiao@apple.com") == "y***@apple.com")
        // Whitespace around the email is trimmed before redaction.
        #expect(EmailRedaction.redact("  admin@example.com  ") == "a***@example.com")
    }

    @Test
    func `empty local part '@domain' → '***@domain'`() {
        // Unusual but RFC 5321 allows it via `<>`. Mac shouldn't
        // ever produce this, but the helper should fail safe.
        #expect(EmailRedaction.redact("@example.com") == "***@example.com")
    }

    @Test
    func `multiple @ → split on FIRST @ (RFC-correct local-then-domain)`() {
        // RFC 5321 doesn't allow `@` in the domain, but the local
        // part can contain quoted `@`. We split on the first `@` so
        // `a@b@c.com` redacts to `a***@b@c.com`, which preserves the
        // signal that there's something off with the input without
        // exposing more of the local part than `a`.
        #expect(EmailRedaction.redact("a@b@c.com") == "a***@b@c.com")
    }

    @Test
    func `Unicode local part`() {
        // Internationalised email addresses can have non-ASCII local
        // parts. We take the first character (a Swift `Character`,
        // which is a grapheme cluster, not a byte) so emoji + CJK
        // are handled correctly.
        #expect(EmailRedaction.redact("用户@例子.com") == "用***@例子.com")
        #expect(EmailRedaction.redact("👤user@example.com") == "👤***@example.com")
    }

    @Test
    func `very long input`() {
        let longLocal = String(repeating: "x", count: 200)
        let result = EmailRedaction.redact("\(longLocal)@example.com")
        #expect(result == "x***@example.com")
    }
}
