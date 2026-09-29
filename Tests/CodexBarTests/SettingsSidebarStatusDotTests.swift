import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

struct SettingsSidebarStatusDotTests {
    @Test
    func `Critical status describes provider service health`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: .critical)
                == "Provider service status: Critical issue")
        }
    }

    @Test
    func `Major status describes provider service health`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: .major)
                == "Provider service status: Major outage")
        }
    }

    @Test(arguments: [ProviderStatusIndicator.critical, .major, .minor, .maintenance, .unknown, .none])
    func `Provider row announces visible service status`(indicator: ProviderStatusIndicator) {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: indicator) == "Codex — Provider service status: \(indicator.label)")
        }
    }

    @Test
    func `Disabled provider keeps its existing accessibility label`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: false,
                statusChecksEnabled: true,
                indicator: .critical) == "Codex — Disabled")
        }
    }

    @Test
    func `Provider row omits service status when status checks are off`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: false,
                indicator: .major) == "Codex")
        }
    }

    @Test
    func `missing service status uses the unknown color`() {
        #expect(SettingsSidebarProviderRow.statusColor(for: nil) == .gray)
        #expect(SettingsSidebarProviderRow.statusColor(for: nil)
            == SettingsSidebarProviderRow.statusColor(for: .unknown))
    }

    @Test(arguments: [
        (ProviderStatusIndicator.none, Color.green),
        (.minor, .yellow),
        (.major, .orange),
        (.critical, .red),
        (.maintenance, .gray),
        (.unknown, .gray),
    ])
    func `fetched service indicators retain their colors`(indicator: ProviderStatusIndicator, color: Color) {
        #expect(SettingsSidebarProviderRow.statusColor(for: indicator) == color)
    }

    @Test
    func `Missing status is unknown rather than operational`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: nil)
                == "Provider service status: Status unknown")
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: nil) == "Codex — Provider service status: Status unknown")
        }
    }

    @Test
    func `Fetched healthy status remains operational`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(SettingsSidebarProviderRow.statusDescription(for: ProviderStatusIndicator.none)
                == "Provider service status: Operational")
            #expect(SettingsSidebarProviderRow.accessibilityLabel(
                name: "Codex",
                isEnabled: true,
                statusChecksEnabled: true,
                indicator: ProviderStatusIndicator.none) == "Codex — Provider service status: Operational")
        }
    }

    @MainActor
    @Test
    func `render synthetic sidebar proof when requested`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_SIDEBAR_SCREENSHOT_PATH"] else { return }
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = true
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let renderer = ImageRenderer(content: SettingsSidebarProviderRow(
            provider: .codex,
            store: store,
            isEnabled: .constant(true))
            .frame(width: 240)
            .padding(16)
            .environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        let tiff = try #require(renderer.nsImage?.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
    }
}
