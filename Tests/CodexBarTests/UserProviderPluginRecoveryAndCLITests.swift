#if canImport(JavaScriptCore)
import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

extension UserProviderPluginTests {
    @Test(arguments: [false, true])
    func `recovered plugin settings retain secrets without duplicating the opaque record`(opaqueNumber: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let id = try #require(ProviderInstanceID(rawValue: "recovered-fixture"))
        let raw = #"""
        {"version":1,"providers":[{"id":"recovered-fixture","enabled":true,
         "pluginSettings":{"REGION":"west"},"pluginSecrets":{"TOKEN":"fixture-secret"}}]}
        """#
        let input = opaqueNumber ? raw.replacingOccurrences(
            of: "\"enabled\":true", with: "\"enabled\":true,\"future\":1.0000000000000000000000000001") : raw
        // Use a distinct ID for each argument so registry state cannot pre-load the next fixture.
        let fixtureID = opaqueNumber ? "recovered-numeric-fixture" : id.rawValue
        var config = try CodexBarConfig.decode(from: Data(input.replacingOccurrences(
            of: id.rawValue, with: fixtureID).utf8))
        #expect(config.unavailableProviders.count == 1)
        _ = try fixture.write(name: "recover.js", source: Self.javaScriptPlugin(id: fixtureID))
        UserProviderPluginRegistry.refresh(loader: fixture.loader(transport: RecordingTransport(responseJSON: "{}")))
        let recoveredID = try #require(ProviderInstanceID(rawValue: fixtureID))
        var provider = try #require(config.providerConfig(for: recoveredID))
        provider.enabled = false
        config.setProviderConfig(provider)
        let saved = try config.encodedData()
        if opaqueNumber {
            let text = try #require(String(data: saved, encoding: .utf8))
            #expect(text.contains("1.0000000000000000000000000001"))
        }
        let reloaded = try CodexBarConfig.decode(from: saved)
        #expect(reloaded.providers.count == (opaqueNumber ? 0 : 1))
        #expect(reloaded.providerConfig(for: recoveredID)?.enabled == opaqueNumber)
        #expect(reloaded.providerConfig(for: recoveredID)?.pluginSecrets == ["TOKEN": "fixture-secret"])
        #expect(reloaded.providerConfig(for: recoveredID)?.pluginSettings == ["REGION": "west"])
    }
}

extension UserProviderPluginTests {
    @Test
    func `plugin CLI renders all standard window titles and JSON retains them`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plugin = try fixture.loader(transport: RecordingTransport(responseJSON: "{}"))
            .load(fileURL: fixture.write(name: "titles.js", source: """
            defineProvider({
              id: "window-titles", name: "Window Titles", endpoints: ["https://example.test"], settings: [],
              fetchUsage() { return {
                primary: {title:"Requests",usedPercent:25},
                secondary: {usedPercent:40},
                tertiary: {title:"Credits",usedPercent:60}
              }; }
            });
            """))
        try fixture.approvals.record(plugin.approvalBinding(settings: [:]))
        let snapshot = try await plugin.fetchUsage(
            settings: [:], secrets: [:], environment: [:], approvalStore: fixture.approvals)
        #expect(CodexBarCLI.pluginSnapshotLines(plugin: plugin, snapshot: snapshot) == [
            "Window Titles", "Requests: 25% used", "Secondary: 40% used", "Credits: 60% used",
        ])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        #expect((json["primary"] as? [String: Any])?["title"] as? String == "Requests")
        #expect((json["secondary"] as? [String: Any])?["title"] == nil)
        #expect((json["tertiary"] as? [String: Any])?["title"] as? String == "Credits")
    }
}
#endif
