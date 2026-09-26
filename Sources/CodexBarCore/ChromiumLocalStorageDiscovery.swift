#if os(macOS)
import Foundation
import SweetCookieKit

/// Locates raw Chromium stores; each caller supplies its own browser allowlist and origin decoder.
enum ChromiumLocalStorageDiscovery {
    static let defaultBrowsers = Browser.defaultImportOrder.filter(\.usesChromiumProfileStore)

    enum Storage {
        case localStorage
        case sessionStorage
        case indexedDB(originPrefixes: [String])

        var path: String {
            switch self {
            case .localStorage: "Local Storage/leveldb"
            case .sessionStorage: "Session Storage"
            case .indexedDB: "IndexedDB"
            }
        }

        var labelSuffix: String {
            switch self {
            case .localStorage: ""
            case .sessionStorage: " (Session Storage)"
            case .indexedDB: " (IndexedDB)"
            }
        }
    }

    struct Candidate {
        let label: String
        let url: URL
    }

    static func candidates(
        browserDetection: BrowserDetection,
        browsers: [Browser],
        storage: Storage = .localStorage,
        homeDirectories: [URL]? = nil) -> [Candidate]
    {
        let installedBrowsers = browsers.browsersWithProfileData(using: browserDetection)
        return self.candidates(browsers: installedBrowsers, storage: storage, homeDirectories: homeDirectories)
    }

    static func candidates(
        browsers: [Browser],
        storage: Storage = .localStorage,
        homeDirectories: [URL]? = nil) -> [Candidate]
    {
        let roots = ChromiumProfileLocator
            .roots(for: browsers, homeDirectories: homeDirectories ?? BrowserCookieClient.defaultHomeDirectories())
            .map { (url: $0.url, labelPrefix: $0.labelPrefix) }

        var candidates: [Candidate] = []
        for root in roots {
            candidates.append(contentsOf: self.profileCandidates(
                root: root.url,
                labelPrefix: root.labelPrefix,
                storage: storage))
        }
        return candidates
    }

    static func profileCandidates(
        root: URL,
        labelPrefix: String,
        storage: Storage = .localStorage) -> [Candidate]
    {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        let profileDirs = entries.filter { url in
            guard let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory), isDir else {
                return false
            }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return profileDirs.flatMap { dir -> [Candidate] in
            let storeURL = dir.appendingPathComponent(storage.path)
            let label = "\(labelPrefix) \(dir.lastPathComponent)\(storage.labelSuffix)"
            guard case let .indexedDB(originPrefixes) = storage else {
                guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
                return [Candidate(label: label, url: storeURL)]
            }
            let databases = (try? FileManager.default.contentsOfDirectory(
                at: storeURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            return databases.compactMap { database in
                let name = database.lastPathComponent
                guard name.hasSuffix(".indexeddb.leveldb"),
                      originPrefixes.contains(where: { name.hasPrefix($0) }),
                      (try? database.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { return nil }
                return Candidate(label: label, url: database)
            }
        }
    }
}
#endif
