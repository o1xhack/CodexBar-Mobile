import Foundation
import Testing
@testable import CodexBar

struct InstallOriginTests {
    @Test
    func `detects legacy caskroom paths`() {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let app = URL(fileURLWithPath: "\(prefix)/Caskroom/codexbar/1.0.0/CodexBar.app")
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: []))
        }
    }

    @Test
    func `unrelated caskroom directory does not claim the app`() {
        #expect(!InstallOrigin.isHomebrewCask(
            appBundleURL: URL(fileURLWithPath: "/example/Caskroom/other/1.0/CodexBar.app"), caskroomURLs: []))
    }

    @Test(arguments: [false, true])
    func `matches the installed app through absolute or relative artifact links`(relative: Bool) throws {
        try self.withFixture { root, app, artifact in
            let destination = relative ? "../../../../Applications/CodexBar.app" : app.path
            try FileManager.default.createSymbolicLink(atPath: artifact.path, withDestinationPath: destination)
            let alias = root.appendingPathComponent("Alias.app")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: app)
            let other = root.appendingPathComponent("Other/CodexBar.app")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            let caskrooms = [root.appendingPathComponent("missing"), root.appendingPathComponent("brew/Caskroom")]

            #expect(InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: alias, caskroomURLs: caskrooms))
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: other, caskroomURLs: caskrooms))
        }
    }

    @Test
    func `requires an artifact link rather than just a caskroom or backup directory`() throws {
        try self.withFixture { root, app, artifact in
            #expect(!InstallOrigin.isHomebrewCask(
                appBundleURL: app, caskroomURLs: [root.appendingPathComponent("missing")]))
            let caskrooms = [root.appendingPathComponent("brew/Caskroom")]
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
            try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
        }
    }

    @Test
    func `ignores dangling links while checking the remaining versions`() throws {
        try self.withFixture { root, app, artifact in
            let missing = root.appendingPathComponent("Missing.app")
            try FileManager.default.createSymbolicLink(at: artifact, withDestinationURL: missing)
            let caskrooms = [root.appendingPathComponent("brew/Caskroom")]
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: missing, caskroomURLs: caskrooms))
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))

            let current = artifact.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("0.60.1/CodexBar.app")
            try FileManager.default.createDirectory(
                at: current.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: current, withDestinationURL: app)
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
        }
    }

    @Test
    func `legacy caskroom apps still check for competing prefix claims`() throws {
        try self.withFixture { root, _, artifact in
            let manager = FileManager.default
            try manager.createDirectory(at: artifact, withIntermediateDirectories: true)
            let owner = root.appendingPathComponent("brew")
            let samePrefix = owner.appendingPathComponent("Caskroom/codexbar/0.60.0/CodexBar.app")
            try manager.createDirectory(at: samePrefix.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.createSymbolicLink(at: samePrefix, withDestinationURL: artifact)
            let caskrooms = [owner.appendingPathComponent("Caskroom"), root.appendingPathComponent("other/Caskroom")]
            #expect(InstallOrigin.homebrewPrefix(appBundleURL: artifact, caskroomURLs: caskrooms)
                == owner.resolvingSymlinksInPath().standardizedFileURL)

            let competing = caskrooms[1].appendingPathComponent("codexbar/0.58.0/CodexBar.app")
            try manager.createDirectory(at: competing.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.createSymbolicLink(at: competing, withDestinationURL: artifact)
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: artifact, caskroomURLs: caskrooms))
            #expect(InstallOrigin.homebrewPrefix(appBundleURL: artifact, caskroomURLs: caskrooms) == nil)
        }
    }

    private func withFixture(_ body: (_ root: URL, _ app: URL, _ artifact: URL) throws -> Void) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let app = root.appendingPathComponent("Applications/CodexBar.app")
        let artifact = root.appendingPathComponent("brew/Caskroom/codexbar/0.59.0/CodexBar.app")
        try fileManager.createDirectory(at: app, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body(root, app, artifact)
    }
}
