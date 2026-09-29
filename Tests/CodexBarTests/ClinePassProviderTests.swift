import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct ClinePassProviderTests {
    @Test
    func `session availability does not copy the token into config`() throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: #function)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("providers.json")
        try #"{"providers":{"cline":{"settings":{"auth":{"accessToken":"fixture-session"}}}}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        let implementation = try #require(ProviderCatalog.implementation(for: .clinepass))
        #expect(implementation.isAvailable(context: .init(
            provider: .clinepass,
            settings: fixture.settings,
            environment: ["HOME": directory.path, "CLINE_PROVIDER_SETTINGS_PATH": file.path])))
        #expect(fixture.settings.providerConfig(for: .clinepass)?.sanitizedAPIKey == nil)
    }

    @Test
    func `render synthetic session guidance when requested`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_CLINEPASS_PROOF_DIR"] else { return }
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: #function)
        let implementation = try #require(ProviderCatalog.implementation(for: .clinepass))
        let field = try #require(implementation.settingsFields(
            context: fixture.settingsContext(provider: .clinepass)).first)
        for stage in ["before", "after"] {
            let displayed = ProviderSettingsFieldDescriptor(
                id: field.id,
                title: field.title,
                subtitle: stage == "before" ? "Stored in ~/.codexbar/config.json. Paste a ClinePass API key."
                    : field.subtitle,
                kind: field.kind,
                placeholder: field.placeholder,
                binding: .constant(""),
                actions: [],
                isVisible: nil)
            let hosting = NSHostingView(rootView: VStack(alignment: .leading, spacing: 18) {
                Text("ClinePass").font(.title2.bold())
                Text("Synthetic settings").font(.caption).foregroundStyle(.secondary)
                ProviderSettingsFieldRowView(field: displayed)
            }.padding(24).frame(width: 600).background(Color(nsColor: .windowBackgroundColor)))
            hosting.appearance = NSAppearance(named: .aqua)
            let png = try #require(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("clinepass-\(stage).png"))
        }
    }

    @Test
    func `provider appears in settings with API key field and official icon`() throws {
        let suite = "ClinePassProviderTests-settings"
        let defaults = InMemoryUserDefaults()
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let implementation = try #require(ProviderCatalog.implementation(for: .clinepass))
        let context = ProviderSettingsContext(
            provider: .clinepass,
            settings: settings,
            store: store,
            statusText: { _ in nil },
            setStatusText: { _, _ in },
            lastAppActiveRunAt: { _ in nil },
            setLastAppActiveRunAt: { _, _ in },
            requestConfirmation: { _ in },
            runLoginFlow: {})

        #expect(settings.orderedProviders().contains(.clinepass))
        #expect(ProviderCatalog.implementation(for: .clinepass)?.id == .clinepass)
        #expect(ProviderDescriptorRegistry.descriptor(for: .clinepass).branding.iconResourceName ==
            "ProviderIcon-clinepass")
        #expect(!implementation.isAvailable(context: ProviderAvailabilityContext(
            provider: .clinepass,
            settings: settings,
            environment: [:])))

        let field = try #require(implementation.settingsFields(context: context).first)
        #expect(field.id == "clinepass-api-key")
        #expect(field.kind == .secure)

        field.binding.wrappedValue = "clinepass-test-key"

        #expect(settings[providerConfig: .clinepass, field: .apiKey] == "clinepass-test-key")
        #expect(settings.providerConfig(for: .clinepass)?.sanitizedAPIKey == "clinepass-test-key")
        #expect(implementation.isAvailable(context: ProviderAvailabilityContext(
            provider: .clinepass,
            settings: settings,
            environment: [:])))
    }
}

struct ClinePassUsageFetcherTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `parser ignores unknown limit types without dropping known windows`(
        engine: ProviderPluginEngineKind) async throws
    {
        let payload = Data(#"""
        {
          "success": true,
          "data": {
            "limits": [
              {
                "type": "five_hour",
                "percentUsed": 12.5,
                "resetsAt": "2026-07-16T15:00:00Z"
              },
              {
                "type": "experimental_pool",
                "percentUsed": 77,
                "resetsAt": "2026-07-16T15:00:00Z"
              },
              {
                "type": "weekly",
                "percentUsed": 25,
                "resetsAt": "2026-07-20T00:00:00Z"
              },
              {
                "type": "monthly",
                "percentUsed": 40,
                "resetsAt": null
              }
            ]
          }
        }
        """#.utf8)
        let runtime = try BundledPluginTestSupport.runtime(
            "clinepass",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                let response = try #require(HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]))
                return (payload, response)
            })

        let snapshot = try await runtime.fetchUsage(secrets: ["CLINE_API_KEY": "test-key"])

        #expect(snapshot.primary?.usedPercent == 12.5)
        #expect(snapshot.primary?.windowMinutes == 5 * 60)
        #expect(snapshot.secondary?.usedPercent == 25)
        #expect(snapshot.secondary?.windowMinutes == 7 * 24 * 60)
        #expect(snapshot.tertiary?.usedPercent == 40)
        #expect(snapshot.tertiary?.windowMinutes == 30 * 24 * 60)
    }
}
