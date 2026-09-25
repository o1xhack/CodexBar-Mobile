import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCLI

@MainActor
struct HyperPresentationTests {
    @Test
    func `plugin balance renders in CLI and card without a fictional quota`() async throws {
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "hyper",
            transport: ProviderHTTPTransportHandler { request in
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (Data(#"{"balance":42.5}"#.utf8), response)
            })
        let snapshot = try await runtime.fetchUsage(
            secrets: ["HYPER_API_KEY": "fixture-key"], sourceMode: .api)
        let output = CLIRenderer.renderText(
            provider: .hyper,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(header: "hyper", status: nil, useColor: false, resetStyle: .absolute))
        #expect(output.contains("42.5 HC"))
        #expect(!output.contains("Cost:"))
        #expect(!output.contains("/ 0"))
        let metadata = try #require(ProviderDefaults.metadata[.hyper])
        let model = UsageMenuCardView.Model.make(.init(
            provider: .hyper,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: true,
            now: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(model.providerCost == nil)
        let hasBalance = model.providerDetails.flatMap(\.rows)
            .contains { $0.label == "Balance" && $0.value == "42.5 HC" }
        #expect(hasBalance)
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_HYPER_SCREENSHOT"] else { return }
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let hosting = NSHostingView(rootView: AnyView(UsageMenuCardView(model: model, width: 360)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.colorScheme, .light)
                    .environment(\.displayScale, 2)
                    .background(Color(nsColor: .windowBackgroundColor))))
            hosting.appearance = NSAppearance(named: .aqua)
            try #require(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
                .write(to: URL(fileURLWithPath: path))
        }
    }
}
