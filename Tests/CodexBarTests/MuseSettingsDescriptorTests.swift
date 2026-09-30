import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

extension ProviderSettingsDescriptorTests {
    @Test
    func `Muse browser team quota is opt in and the chosen team reaches the snapshot`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-muse")
        let implementation = MuseProviderImplementation()
        let context = fixture.settingsContext(provider: .muse)
        let picker = try #require(implementation.settingsPickers(context: context).first)
        let team = try #require(implementation.settingsPickers(context: context).first { $0.id == "muse-web-team-id" })
        let snapshotContext = ProviderSettingsSnapshotContext(settings: fixture.settings, tokenOverride: nil)
        #expect(picker.binding.wrappedValue == "off")
        #expect(team.isVisible?() == false)
        let defaults = try ProviderSettingsSnapshot(
            contributions: [#require(implementation.settingsSnapshot(context: snapshotContext))])
        #expect(defaults[MuseProviderSettingsKey.self]?.cookieSource == .off)
        #expect(defaults[MuseProviderSettingsKey.self]?.webTeamID == nil)
        picker.binding.wrappedValue = "auto"
        team.binding.wrappedValue = " 424242424242 "
        #expect(team.isVisible?() == true)
        #expect(fixture.settings.providerConfig(for: .muse)?.workspaceID == "424242424242")
        let chosen = try ProviderSettingsSnapshot(
            contributions: [#require(implementation.settingsSnapshot(context: snapshotContext))])
        #expect(chosen[MuseProviderSettingsKey.self]?.cookieSource == .auto)
        #expect(chosen[MuseProviderSettingsKey.self]?.webTeamID == "424242424242")
    }

    @Test
    func `Muse team picker never chooses the first visible team`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-muse-teams")
        fixture.settings.museCookieSource = .auto
        fixture.store.snapshots[.muse] = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [.init(title: "Browser teams", rows: [
                .init(label: "Status", value: "Choose a browser team"),
                .init(label: "Alpha", value: "11"),
                .init(label: "Beta", value: "22"),
            ])],
            updatedAt: Date())
        let implementation = MuseProviderImplementation()
        let context = fixture.settingsContext(provider: .muse)
        let picker = try #require(implementation.settingsPickers(context: context)
            .first { $0.id == "muse-web-team-id" })
        #expect(picker.options.map(\.id) == ["", "11", "22"])
        #expect(picker.options.last?.title == "Beta (22)")
        #expect(picker.binding.wrappedValue.isEmpty)
        picker.binding.wrappedValue = "22"
        #expect(fixture.settings.museWebTeamID == "22")
        fixture.store.snapshots[.muse] = nil
        let unavailable = try #require(implementation.settingsPickers(context: context)
            .first { $0.id == "muse-web-team-id" })
        #expect(unavailable.binding.wrappedValue == "22")
        #expect(unavailable.options.map(\.id) == ["", "22"])
        #expect(unavailable.options.last?.title.contains("unavailable") == true)
    }
}
