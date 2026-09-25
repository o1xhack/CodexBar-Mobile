import AppKit
import SwiftUI
import XCTest
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@MainActor
final class MoonshotCurrencyNativeProofTests: XCTestCase {
    func test_regionalCurrencyInProductionMenuCard() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CODEXBAR_MOONSHOT_NATIVE_PROOF"] == "1" else {
            throw XCTSkip("Set CODEXBAR_MOONSHOT_NATIVE_PROOF=1 for signed synthetic UI proof")
        }
        guard environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] == "1",
              environment[CodexCredentialFileAccess.isolationEnvironmentKey] == "1",
              environment["CODEXBAR_TEST_SESSION_FILE_ISOLATION"] == "1",
              environment["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1"
        else { return XCTFail("Native proof requires credential and session isolation") }
        let directory = try URL(fileURLWithPath: XCTUnwrap(environment["CODEXBAR_MOONSHOT_PROOF_DIRECTORY"]))
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "moonshot",
            transport: ProviderHTTPTransportHandler { request in
                let body = """
                {"code":0,"data":{"available_balance":50,"voucher_balance":50,"cash_balance":-0.42},
                "scode":"0x0","status":true}
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), response)
            })
        let after = try await runtime.fetchUsage(
            settings: ["BASE_URL": MoonshotRegion.china.apiBaseURLString],
            secrets: ["MOONSHOT_API_KEY": "synthetic-proof-token"])
        // Reproduce the previous USD labels using the same amounts and unchanged international formatter.
        let before = try await runtime.fetchUsage(
            settings: ["BASE_URL": MoonshotRegion.international.apiBaseURLString],
            secrets: ["MOONSHOT_API_KEY": "synthetic-proof-token"])
        XCTAssertEqual(before.loginMethod(for: .moonshot), "Balance: $50.00 · $0.42 in deficit")
        XCTAssertEqual(after.loginMethod(for: .moonshot), "Balance: CN¥50.00 · CN¥0.42 in deficit")
        let cli = CLIRenderer.renderText(
            provider: .moonshot,
            snapshot: after,
            credits: nil,
            context: RenderContext(header: "Moonshot", status: nil, useColor: false, resetStyle: .absolute))
        XCTAssertTrue(cli.contains("CN¥50.00"))
        XCTAssertTrue(cli.contains("CN¥0.42"))
        try cli.write(to: directory.appendingPathComponent("moonshot-cli-after.txt"), atomically: true, encoding: .utf8)

        let application = NSApplication.shared
        guard application.delegate == nil else { return XCTFail("Requires a standalone test application") }
        let previousPolicy = application.activationPolicy()
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.title = "CodexBar Moonshot currency — synthetic fixture"
        defer {
            window.close()
            _ = application.setActivationPolicy(previousPolicy)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                previousApplication?.activate()
            }
        }
        _ = application.setActivationPolicy(.regular)
        application.finishLaunching()
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        try self.capture(before, name: "before", title: "Before: USD labels", window: window, directory: directory)
        try self.capture(after, name: "after", title: "After: CNY labels", window: window, directory: directory)
    }

    private func capture(
        _ snapshot: UsageSnapshot, name: String, title: String, window: NSWindow, directory: URL) throws
    {
        let model = try UsageMenuCardView.Model.make(.init(
            provider: .moonshot,
            metadata: XCTUnwrap(ProviderDefaults.metadata[.moonshot]),
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: snapshot.loginMethod(for: .moonshot)),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: true,
            now: snapshot.updatedAt))
        window.contentView = NSHostingView(rootView:
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.headline)
                Text("Synthetic China API response · no account access").font(.caption)
                UsageMenuCardView(model: model, width: 390)
                Spacer()
            }.padding(24))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = [
            "-x", "-o", "-l", String(window.windowNumber),
            directory.appendingPathComponent("moonshot-\(name).png").path,
        ]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
    }
}
