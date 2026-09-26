import Foundation
import Testing
@testable import CodexBarCore

@MainActor
struct OpenAIDashboardImportModelsTests {
    @Test
    func `cookie import errors keep platform independent descriptions`() {
        typealias ImportError = OpenAIDashboardBrowserCookieImporter.ImportError
        let cases: [(ImportError, String)] = [
            (.noCookiesFound, "No browser cookies found."),
            (.browserAccessDenied(details: "fixture"), "Browser cookie access denied. fixture"),
            (.browserCookieLoadTimedOut(details: "fixture"), "Browser cookie loading timed out. fixture"),
            (.dashboardStillRequiresLogin, "Browser cookies imported, but dashboard still requires login."),
            (.manualCookieHeaderInvalid, "Manual cookie header is missing a valid OpenAI session cookie."),
            (.noMatchingAccount(found: []), "No matching OpenAI web session found in browsers."),
            (
                .noMatchingAccount(found: [
                    .init(sourceLabel: "B", email: "b@example.invalid"),
                    .init(sourceLabel: "A", email: "z@example.invalid"),
                    .init(sourceLabel: "A", email: "a@example.invalid"),
                ]),
                "OpenAI web session does not match Codex account. " +
                    "Found: A=a@example.invalid, A=z@example.invalid, B=b@example.invalid."),
        ]
        for (error, description) in cases {
            #expect(error.localizedDescription == description)
        }
    }

    @Test
    func `cookie import models retain identity and result fields`() {
        typealias FoundAccount = OpenAIDashboardBrowserCookieImporter.FoundAccount
        let account = FoundAccount(sourceLabel: "Fixture", email: "test@example.invalid")
        #expect(Set([account, account]).count == 1)
        #expect(account != FoundAccount(sourceLabel: "Other", email: account.email))
        let result = OpenAIDashboardBrowserCookieImporter.ImportResult(
            sourceLabel: account.sourceLabel, cookieCount: 2, signedInEmail: account.email, matchesCodexEmail: false)
        #expect(result.sourceLabel == "Fixture")
        #expect(result.cookieCount == 2)
        #expect(result.signedInEmail == "test@example.invalid")
        #expect(!result.matchesCodexEmail)
    }

    #if !os(macOS)
    @Test
    func `unsupported platforms keep cookie import unavailable`() async {
        let importer = OpenAIDashboardBrowserCookieImporter()
        do {
            _ = try await importer.importBestCookies(intoAccountEmail: nil)
            Issue.record("Expected unsupported platform error")
        } catch {
            #expect(error.localizedDescription ==
                "Browser cookie access denied. OpenAI web cookie import is only supported on macOS.")
        }
        do {
            _ = try await importer.importManualCookies(cookieHeader: "fixture=value", intoAccountEmail: nil)
            Issue.record("Expected unsupported platform error")
        } catch {
            #expect(error.localizedDescription ==
                "Browser cookie access denied. OpenAI web cookie import is only supported on macOS.")
        }
    }
    #endif
}
