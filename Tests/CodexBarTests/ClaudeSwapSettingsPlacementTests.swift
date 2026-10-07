import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct ClaudeSwapSettingsPlacementTests {
    @Test
    func `claude swap path belongs to its toggle instead of the standalone fields`() throws {
        let fixture = try ProviderSettingsDescriptorTests()
            .makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-swap-path")
        let context = fixture.settingsContext(provider: .claude)
        let implementation = ClaudeProviderImplementation()
        let toggle = try #require(implementation.settingsToggles(context: context).first {
            $0.id == "claude-swap-accounts"
        })
        let fields = toggle.inlineFields
        #expect(fields.map(\.id) == ["claude-swap-executable-path"])
        let field = try #require(fields.first)
        #expect(!toggle.binding.wrappedValue)
        #expect(field.subtitle == "Path to the cswap executable (github.com/realiti4/claude-swap).")
        #expect(field.kind == .plain)
        toggle.binding.wrappedValue = true
        field.binding.wrappedValue = "/synthetic/bin/cswap"
        #expect(fixture.settings.claudeSwapExecutablePath == "/synthetic/bin/cswap")
        let otherFieldsAreEmpty = implementation.settingsToggles(context: context)
            .filter { $0.id != toggle.id }.allSatisfy(\.inlineFields.isEmpty)
        #expect(otherFieldsAreEmpty)
        #expect(!implementation.settingsFields(context: context).contains { $0.id == "claude-swap-executable-path" })
    }

    @Test
    func `render synthetic claude swap settings proof`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_CLAUDE_PRESENTATION_PROOF_DIR"] else {
            return
        }
        let fixture = try ProviderSettingsDescriptorTests()
            .makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-swap-proof")
        fixture.settings.claudeSwapEnabled = true
        let context = fixture.settingsContext(provider: .claude)
        let implementation = ClaudeProviderImplementation()
        let fields = implementation.settingsFields(context: context).filter { $0.id == "claude-swap-executable-path" }
        let toggles = implementation.settingsToggles(context: context).filter { $0.id == "claude-swap-accounts" }
        let hosting = NSHostingView(rootView: Form {
            ForEach(fields) { ProviderSettingsFieldRowView(field: $0) }
            Section("Options") {
                ForEach(toggles) { ProviderSettingsToggleRowView(toggle: $0) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 360)
        .environment(\.locale, Locale(identifier: "en"))
        .preferredColorScheme(.light))
        hosting.appearance = NSAppearance(named: .aqua)
        let png = try #require(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings.png"))
    }
}
