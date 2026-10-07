import Foundation
import Testing
@testable import CodexBarCore

struct AntigravityOAuthCredentialsStoreTests {
    @Test
    func `oauth discovery declines unrelated binary identities without a matching record`() {
        var data = Data([0xFF])
        data.append(Data("\(self.googleClientID("one"))\u{0}\(self.googleClientID("two"))".utf8))
        data.append(Data(self.googleClientSecret(repeating: "a").utf8))
        data.append(Data(self.googleClientSecret(repeating: "b").utf8))

        #expect(AntigravityOAuthConfig.parseClient(fromInstalledArtifactData: data) == nil)
    }

    @Test(arguments: [false, true])
    func `oauth discovery pairs the fields initialized together in Antigravity 2_19_1`(intel: Bool) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = AntigravityOAuthClient(
            clientID: self.googleClientID("desktop"),
            clientSecret: self.googleClientSecret(repeating: "a"))
        let alternate = AntigravityOAuthClient(
            clientID: self.googleClientID("alternate"),
            clientSecret: self.googleClientSecret(repeating: "b"))
        try self.writeAntigravityApp(
            named: "Antigravity.app",
            under: root,
            artifactRelativePath: "Contents/Resources/bin/language_server",
            artifactData: self.binaryFixture(clients: [client, alternate], intel: intel))

        #expect(AntigravityOAuthConfig.discoverClientFromInstalledApp(applicationRoots: [root]) == client)
    }

    @Test
    func `oauth discovery keeps a lone UTF8 pair beyond the text window`() {
        let id = self.googleClientID("legacy")
        let secret = self.googleClientSecret(repeating: "a")
        let data = Data((String(repeating: " ", count: 5000) + id + "\u{0}" + secret).utf8)
        #expect(AntigravityOAuthConfig.parseClient(fromInstalledArtifactData: data) ==
            AntigravityOAuthClient(clientID: id, clientSecret: secret))
    }

    @Test
    func `oauth discovery declines ambiguous text records`() {
        let content = """
        vs/platform/cloudCode/common/oauthClient.js
        clientId="\(self.googleClientID("one"))"; clientSecret="\(self.googleClientSecret(repeating: "a"))";
        clientId="\(self.googleClientID("two"))"; clientSecret="\(self.googleClientSecret(repeating: "b"))";
        """
        #expect(AntigravityOAuthConfig.parseClient(fromInstalledArtifactData: Data(content.utf8)) == nil)
    }

    @Test(arguments: [false, true], [20, 36, 96, 152])
    func `oauth discovery rejects malformed MachO metadata`(intel: Bool, offset: Int) {
        let clients = ["one", "two"].map {
            AntigravityOAuthClient(
                clientID: self.googleClientID($0),
                clientSecret: self.googleClientSecret(repeating: "a"))
        }
        var data = self.binaryFixture(clients: clients, intel: intel)
        data.replaceSubrange(offset..<(offset + 4), with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(AntigravityOAuthConfig.parseClient(fromInstalledArtifactData: data) == nil)
    }

    @Test(arguments: [false, true])
    func `oauth discovery does not cross pair broken records`(intel: Bool) {
        let clients = ["one", "two"].map {
            AntigravityOAuthClient(
                clientID: self.googleClientID($0),
                clientSecret: self.googleClientSecret(repeating: "a"))
        }
        var data = self.binaryFixture(clients: clients, intel: intel)
        // Remove the first record's secret store and the second record's ID store.
        data[intel ? 548 : 543] = 0
        data[intel ? 593 : 591] = 0
        #expect(AntigravityOAuthConfig.parseClient(fromInstalledArtifactData: data) == nil)
    }

    @Test
    func `oauth discovery accepts a binary Data slice`() {
        let client = AntigravityOAuthClient(
            clientID: self.googleClientID("desktop"), clientSecret: self.googleClientSecret(repeating: "a"))
        let alternate = AntigravityOAuthClient(
            clientID: self.googleClientID("alternate"), clientSecret: self.googleClientSecret(repeating: "b"))
        var data = Data([0])
        data.append(self.binaryFixture(clients: [client, alternate], intel: false))
        #expect(AntigravityOAuthConfig.parseClient(fromInstalledArtifactData: data.dropFirst()) == client)
    }

    /// Synthetic Mach-O with the two adjacent Go string fields observed in Google's signed 2.19.1 binaries.
    /// Constants are pooled separately from the instructions; string order does not establish ownership.
    private func binaryFixture(
        clients: [AntigravityOAuthClient],
        intel: Bool,
        reverseSecrets: Bool = false) -> Data
    {
        var data = Data(repeating: 0, count: 16384)
        func word(_ offset: Int, _ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
        }
        func bytes(_ offset: Int, _ values: [UInt8]) {
            data.replaceSubrange(offset..<(offset + values.count), with: values)
        }
        word(0, 0xFEED_FACF)
        word(4, intel ? 0x0100_0007 : 0x0100_000C)
        word(16, 1)
        word(20, 152)
        word(32, 0x19)
        word(36, 152)
        bytes(40, Array("__TEXT".utf8))
        word(60, 1) // vmaddr = 0x100000000
        word(64, UInt32(data.count))
        word(80, UInt32(data.count))
        word(96, 1)
        bytes(104, Array("__text".utf8))
        word(136, 512)
        word(140, 1)
        word(144, UInt32(clients.count * 64))
        word(152, 512)
        for (index, client) in clients.enumerated() {
            let instruction = 512 + index * 64
            let secret = 8192 + (reverseSecrets ? clients.count - index - 1 : index) * 128
            let id = 12288 + index * 128
            bytes(secret, Array(client.clientSecret.utf8))
            bytes(id, Array(client.clientID.utf8))
            if intel {
                bytes(instruction, [0x48, 0xC7, 0x40, 0x08])
                word(instruction + 4, UInt32(client.clientID.utf8.count))
                bytes(instruction + 8, [0x48, 0x8D, 0x0D])
                word(instruction + 11, UInt32(id - instruction - 15))
                bytes(instruction + 15, [0x48, 0x89, 0x08, 0x48, 0xC7, 0x40, 0x18])
                word(instruction + 22, 35)
                bytes(instruction + 26, [0x48, 0x8D, 0x0D])
                word(instruction + 29, UInt32(secret - instruction - 33))
                bytes(instruction + 33, [0x48, 0x89, 0x48, 0x10])
            } else {
                for (field, address, length) in [(0, id, client.clientID.utf8.count), (1, secret, 35)] {
                    let offset = instruction + field * 16
                    let pages = UInt32((address >> 12) - (offset >> 12))
                    word(offset, 0x9000_0001 | (pages & 3) << 29 | (pages >> 2) << 5)
                    word(offset + 4, 0x9100_0021 | UInt32(address & 4095) << 10)
                    word(offset + 8, 0xD280_0002 | UInt32(length) << 5)
                    word(offset + 12, field == 0 ? 0xA900_0801 : 0xA901_0801)
                }
            }
        }
        return data
    }

    @Test
    func `oauth client discovery reads renamed legacy bundle`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyClient = AntigravityOAuthClient(
            clientID: self.googleClientID("legacy"),
            clientSecret: self.googleClientSecret(repeating: "a"))
        try self.writeAntigravityApp(
            named: "Antigravity 2.app",
            under: root,
            bundleIdentifier: "com.google.antigravity-ide",
            artifactRelativePath: "Contents/Resources/app/out/main.js",
            artifactData: Data("""
            out-build/vs/platform/cloudCode/common/oauthClient.js
            clientId="\(legacyClient.clientID)";
            clientSecret="\(legacyClient.clientSecret)";
            """.utf8))

        #expect(
            AntigravityOAuthConfig.discoverClientFromInstalledApp(
                applicationRoots: [root]) == legacyClient)
    }

    @Test
    func `oauth client discovery reads renamed gemini bundle identifier`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let geminiClient = AntigravityOAuthClient(
            clientID: self.googleClientID("gemini"),
            clientSecret: self.googleClientSecret(repeating: "f"))
        try self.writeAntigravityApp(
            named: "Google Gemini.app",
            under: root,
            bundleIdentifier: "com.google.GeminiMacOS",
            artifactRelativePath: "Contents/Resources/app/out/main.js",
            artifactData: Data("""
            out-build/vs/platform/cloudCode/common/oauthClient.js
            clientId="\(geminiClient.clientID)";
            clientSecret="\(geminiClient.clientSecret)";
            """.utf8))

        #expect(
            AntigravityOAuthConfig.discoverClientFromInstalledApp(
                applicationRoots: [root]) == geminiClient)
    }

    @Test
    func `oauth client discovery reads gemini native binary artifact`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let geminiClient = AntigravityOAuthClient(
            clientID: self.googleClientID("gemini-native"),
            clientSecret: self.googleClientSecret(repeating: "g"))
        var artifactData = Data([0xFF])
        artifactData.append(Data(
            """
            \u{0}\(geminiClient.clientSecret)\u{0}oauth_data\u{0}\(geminiClient.clientID)\u{0}
            """.utf8))
        try self.writeAntigravityApp(
            named: "Gemini.app",
            under: root,
            bundleIdentifier: "com.google.GeminiMacOS",
            artifactRelativePath: "Contents/MacOS/Gemini",
            artifactData: artifactData)

        #expect(
            AntigravityOAuthConfig.discoverClientFromInstalledApp(
                applicationRoots: [root]) == geminiClient)
    }

    @Test
    func `oauth client discovery skips gemini app with foreign bundle identifier`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let foreignClient = AntigravityOAuthClient(
            clientID: self.googleClientID("foreign"),
            clientSecret: self.googleClientSecret(repeating: "h"))
        var artifactData = Data([0xFF])
        artifactData.append(Data(
            """
            \u{0}\(foreignClient.clientSecret)\u{0}oauth_data\u{0}\(foreignClient.clientID)\u{0}
            """.utf8))
        try self.writeAntigravityApp(
            named: "Gemini.app",
            under: root,
            bundleIdentifier: "com.example.other-gemini",
            artifactRelativePath: "Contents/MacOS/Gemini",
            artifactData: artifactData)

        #expect(
            AntigravityOAuthConfig.discoverClientFromInstalledApp(
                applicationRoots: [root]) == nil)
    }

    @Test
    func `oauth client discovery reads standalone antigravity 2 bundle`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let standaloneClient = AntigravityOAuthClient(
            clientID: self.googleClientID("standalone"),
            clientSecret: self.googleClientSecret(repeating: "b"))
        let alternateClient = AntigravityOAuthClient(
            clientID: self.googleClientID("alternate"),
            clientSecret: self.googleClientSecret(repeating: "c"))
        let artifactData = self.binaryFixture(
            clients: [standaloneClient, alternateClient], intel: false, reverseSecrets: true)
        try self.writeAntigravityApp(
            named: "Antigravity.app",
            under: root,
            artifactRelativePath: "Contents/Resources/bin/language_server",
            artifactData: artifactData)

        #expect(
            AntigravityOAuthConfig.discoverClientFromInstalledApp(
                applicationRoots: [root]) == standaloneClient)
    }

    @Test
    func `oauth client discovery reads antigravity extension language server`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let extensionClient = AntigravityOAuthClient(
            clientID: self.googleClientID("extension"),
            clientSecret: self.googleClientSecret(repeating: "d"))
        let staleClient = AntigravityOAuthClient(
            clientID: self.googleClientID("stale"),
            clientSecret: self.googleClientSecret(repeating: "e"))
        try self.writeAntigravityApp(
            named: "Antigravity IDE.app",
            under: root,
            bundleIdentifier: "com.google.antigravity-ide",
            artifactRelativePath: "Contents/Resources/app/out/main.js",
            artifactData: Data("""
            out-build/vs/platform/cloudCode/common/oauthClient.js
            clientId="\(staleClient.clientID)";
            clientSecret="\(staleClient.clientSecret)";
            """.utf8))
        var artifactData = Data([0xFF])
        artifactData.append(Data(
            """
            \u{0}\(extensionClient.clientSecret)\u{0}oauth_data\u{0}\(extensionClient.clientID)\u{0}
            """.utf8))
        try self.writeAntigravityApp(
            named: "Antigravity IDE.app",
            under: root,
            bundleIdentifier: "com.google.antigravity-ide",
            artifactRelativePath: "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
            artifactData: artifactData)

        #expect(
            AntigravityOAuthConfig.discoverClientFromInstalledApp(
                applicationRoots: [root]) == extensionClient)
    }

    @Test
    func `oauth client discovery pairs lone binary secret with trailing client id`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let standaloneClient = AntigravityOAuthClient(
            clientID: self.googleClientID("standalone"),
            clientSecret: self.googleClientSecret(repeating: "b"))
        let alternateClientID = self.googleClientID("alternate")
        var artifactData = self.binaryFixture(clients: [standaloneClient], intel: false)
        let decoy = Data(alternateClientID.utf8)
        artifactData.replaceSubrange(12000..<(12000 + decoy.count), with: decoy)
        try self.writeAntigravityApp(
            named: "Antigravity.app",
            under: root,
            artifactRelativePath: "Contents/Resources/bin/language_server",
            artifactData: artifactData)

        #expect(
            AntigravityOAuthConfig.discoverClientFromInstalledApp(
                applicationRoots: [root]) == standaloneClient)
    }

    private func writeAntigravityApp(
        named name: String,
        under root: URL,
        bundleIdentifier: String = "com.google.antigravity",
        artifactRelativePath: String,
        artifactData: Data) throws
    {
        let appURL = root.appendingPathComponent(name, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleIdentifier],
            format: .xml,
            options: 0)
        try infoData.write(to: infoURL)

        let artifactURL = appURL.appendingPathComponent(artifactRelativePath)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try artifactData.write(to: artifactURL)
    }

    private func googleClientID(_ name: String) -> String {
        "123456789012-" + name + ".apps" + ".googleusercontent.com"
    }

    private func googleClientSecret(repeating character: Character) -> String {
        "GOC" + "SPX-" + String(repeating: character, count: 28)
    }
}
