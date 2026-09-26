#if os(macOS)
import Foundation
import SweetCookieKit
import Testing
@testable import CodexBarCore

struct KimiLocalStorageTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let token = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE4MDAwMDM2MDB9.signature"

    @Test(arguments: ChromiumLocalStorageDiscovery.defaultBrowsers)
    func `imports regional sessions across the Chromium catalog`(browser: Browser) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("kimi-storage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = try #require(ChromiumProfileLocator.roots(for: [browser], homeDirectories: [home]).first)
        for profile in ["Default", "Profile 2", "user-work", "Guest Profile"] {
            let storage = root.url.appendingPathComponent("\(profile)/Local Storage/leveldb")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            try Self.writeLog(origin: "https://www.kimi.ai", value: Self.token, to: storage)
        }
        try Data(#"{"profile":{"info_cache":{"Default":{"name":"Personal"}}}}"#.utf8)
            .write(to: root.url.appendingPathComponent("Local State"))
        let detection = BrowserDetection(homeDirectory: home.path)
        let api = BrowserLocalStorageAPI { origin, browsers, _, logger in
            #expect(browsers == ChromiumLocalStorageDiscovery.defaultBrowsers)
            return BrowserLocalStorageAPI.loadProfiles(
                origin: origin,
                root: root.url,
                browserID: browser.rawValue,
                labelPrefix: root.labelPrefix,
                logger: logger)
        }
        let profiles = api.profiles(
            for: "https://www.kimi.ai",
            browsers: ChromiumLocalStorageDiscovery.defaultBrowsers,
            using: detection,
            logger: { _ in })
        #expect(Set(profiles.map(\.id)) ==
            Set(["Default", "Profile 2", "user-work"].map { "\(browser.rawValue):\($0)" }))
        #expect(profiles.contains { $0.label == "\(root.labelPrefix) — Personal" })
        #expect(KimiCookieImporter.localStorageTokens(
            region: .international, browserDetection: detection, localStorage: api, now: Self.now) == [Self.token])
        #expect(KimiCookieImporter.localStorageTokens(
            region: .china, browserDetection: detection, localStorage: api, now: Self.now).isEmpty)
    }

    @Test
    func `only current access tokens are imported without refresh tokens or duplicates`() {
        let expired = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.signature"
        let api = BrowserLocalStorageAPI { origin, _, _, _ in
            #expect(origin == "https://www.kimi.ai")
            return [.init(id: "fixture", label: "Fixture", entries: [
                .init(key: "refresh_token", value: Self.token),
                .init(key: "access_token", value: expired),
                .init(key: "access_token", value: "not-a-token"),
                .init(key: "access_token", value: "a.b.c"),
                .init(key: "access_token", value: Self.token + "; kimi-auth=x"),
                .init(key: "access_token", value: " \(Self.token)\n"),
                .init(key: "access_token", value: "\"\(Self.token)\""),
            ])]
        }
        #expect(KimiCookieImporter.localStorageTokens(
            region: .international, localStorage: api, now: Self.now) == [Self.token])
        #expect(KimiCookieImporter.localStorageTokens(
            region: .international, localStorage: api, now: Self.now.addingTimeInterval(3600)).isEmpty)
    }

    private static func writeLog(origin: String, value: String, to directory: URL) throws {
        let key = Data("_\(origin)\0access_token".utf8)
        let value = Data([1]) + Data(value.utf8)
        var batch = Data(repeating: 0, count: 8)
        batch.append(contentsOf: [1, 0, 0, 0])
        batch.append(1)
        batch.append(UInt8(key.count))
        batch.append(key)
        batch.append(UInt8(value.count))
        batch.append(value)
        var record = Data(repeating: 0, count: 4)
        let length = UInt16(batch.count).littleEndian
        withUnsafeBytes(of: length) { record.append(contentsOf: $0) }
        record.append(1)
        record.append(batch)
        try record.write(to: directory.appendingPathComponent("000003.log"))
    }
}
#endif
