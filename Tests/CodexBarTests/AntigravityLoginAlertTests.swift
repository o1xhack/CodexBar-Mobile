import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct AntigravityLoginAlertTests {
    @Test
    func `invalid OAuth client explains both overrides without displaying the raw response`() {
        let data = Data(#"{"error":"invalid_client","error_description":"synthetic rejected secret"}"#.utf8)
        let message = AntigravityLoginRunner.tokenExchangeFailureMessage(data: data, statusCode: 400)
        let result = AntigravityLoginRunner.Result(outcome: .failed(message))
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info?.message.contains("invalid_client") == true)
        #expect(info?.message.contains("Update Antigravity.app") == true)
        #expect(info?.message.contains("ANTIGRAVITY_OAUTH_CLIENT_ID") == true)
        #expect(info?.message.contains("ANTIGRAVITY_OAUTH_CLIENT_SECRET") == true)
        #expect(info?.message.contains("synthetic rejected secret") == false)
    }

    @Test
    func `other token exchange failures keep their existing diagnostic`() {
        let body = #"{"error":"invalid_grant"}"#
        #expect(AntigravityLoginRunner.tokenExchangeFailureMessage(data: Data(body.utf8), statusCode: 400) == body)
        #expect(AntigravityLoginRunner.tokenExchangeFailureMessage(data: Data([0xFF]), statusCode: 502) == "HTTP 502")
    }

    @Test
    func `authorization URL asks Google to select an account`() throws {
        let redirectURL = try #require(URL(string: "http://127.0.0.1:54321/callback"))
        let url = try AntigravityLoginRunner.makeAuthorizationURL(
            redirectURL: redirectURL,
            state: "state",
            oauthClient: AntigravityOAuthClient(
                clientID: "client.apps.googleusercontent.com",
                clientSecret: "secret"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let prompt = components.queryItems?.first(where: { $0.name == "prompt" })?.value

        #expect(prompt?.split(separator: " ").contains("select_account") == true)
        #expect(prompt?.split(separator: " ").contains("consent") == true)
    }

    @Test
    func `returns alert for timeout`() {
        let result = AntigravityLoginRunner.Result(outcome: .timedOut)
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info?.title == "Antigravity login timed out")
    }

    @Test
    func `returns alert for launch failure`() {
        let result = AntigravityLoginRunner.Result(outcome: .launchFailed("https://example.com/login"))
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info?.title == "Could not open browser for Antigravity")
        #expect(info?.message.contains("https://example.com/login") == true)
    }

    @Test
    func `returns alert for auth failure`() {
        let result = AntigravityLoginRunner.Result(outcome: .failed("permission denied"))
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info?.title == "Antigravity login failed")
        #expect(info?.message == "permission denied")
    }

    @Test
    func `returns nil on success`() {
        let result = AntigravityLoginRunner.Result(outcome: .success("user@example.com"))
        let info = StatusItemController.antigravityLoginAlertInfo(for: result)
        #expect(info == nil)
    }
}
