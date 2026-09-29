import AppKit
import CodexBarCore
import Foundation
import Sparkle

enum HomebrewCaskVersion {
    static let caskSourceURL = URL(
        string: "https://raw.githubusercontent.com/steipete/homebrew-tap/main/Casks/codexbar.rb")!

    static func parse(caskSource: String) -> String? {
        for line in caskSource.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("version ") else { continue }
            let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let version = parts[1].trimmingCharacters(in: .whitespaces)
            return version.isEmpty ? nil : version
        }
        return nil
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        SUStandardVersionComparator.default.compareVersion(
            self.comparableVersion(candidate), toVersion: self.comparableVersion(installed)) == .orderedDescending
    }

    private static func comparableVersion(_ version: String) -> String {
        // Sparkle ignores everything after a hyphen; CodexBar also ships semver-style prerelease tags.
        version.replacingOccurrences(of: "-(?=alpha|beta|rc|pre|dev)", with: "", options: .regularExpression)
    }
}

enum HomebrewUpdateError: LocalizedError, Equatable {
    case invalidCaskResponse
    case brewNotFound
    case versionUnchanged(String)

    var errorDescription: String? {
        switch self {
        case .invalidCaskResponse:
            "Could not read the latest version from the Homebrew tap."
        case .brewNotFound:
            "Could not find a unique Homebrew installation managing this app."
        case let .versionUnchanged(version):
            "Homebrew finished, but CodexBar is still version \(version). The requested update was not installed."
        }
    }
}

/// Keeps Homebrew as the owner of cask installs: it only reads the tap's cask version and runs
/// `brew upgrade` on request, leaving both the receipt and bundle installation to Homebrew.
@MainActor
@Observable
final class HomebrewUpdaterController: UpdaterProviding {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case installing
        case failed(String)
    }

    struct Dependencies {
        var installedVersion: () -> String
        var fetchCaskSource: @Sendable () async throws -> String
        var runUpgrade: @Sendable () async throws -> Void
        var relaunch: @MainActor () -> Void
    }

    private static let checkInterval: Duration = .seconds(24 * 60 * 60)
    private static let log = CodexBarLog.logger(LogCategories.app)

    let isAvailable = false
    let manualUpdateCommand: ManualUpdateCommand? = .homebrew
    let updateStatus = UpdateStatus()
    var automaticallyDownloadsUpdates = false
    private(set) var phase: Phase = .idle

    var unavailableReason: String? {
        L("Managed by Homebrew")
    }

    var automaticallyChecksForUpdates: Bool {
        didSet {
            guard oldValue != self.automaticallyChecksForUpdates else { return }
            self.rescheduleChecks()
        }
    }

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var scheduledChecks: Task<Void, Never>?
    @ObservationIgnored private var activeCheck: Task<Void, Never>?

    init(savedAutoCheck: Bool, dependencies: Dependencies = .live, startScheduledChecks: Bool = true) {
        self.automaticallyChecksForUpdates = savedAutoCheck
        self.dependencies = dependencies
        if startScheduledChecks {
            self.rescheduleChecks()
        }
    }

    deinit {
        self.scheduledChecks?.cancel()
        self.activeCheck?.cancel()
    }

    func checkForUpdates(_ sender: Any?) {
        guard self.activeCheck == nil, self.phase != .installing else { return }
        self.activeCheck = Task { [weak self] in
            await self?.performCheck()
            self?.activeCheck = nil
        }
    }

    func installUpdate() {
        guard self.phase != .installing else { return }
        Task { [weak self] in
            await self?.performInstall()
        }
    }

    func performCheck() async {
        guard self.phase != .installing, self.phase != .checking else { return }
        self.phase = .checking
        do {
            let source = try await self.dependencies.fetchCaskSource()
            guard let latest = HomebrewCaskVersion.parse(caskSource: source) else {
                throw HomebrewUpdateError.invalidCaskResponse
            }
            if HomebrewCaskVersion.isNewer(latest, than: self.dependencies.installedVersion()) {
                self.updateStatus.availableVersion = latest
                self.phase = .available(latest)
            } else {
                self.updateStatus.availableVersion = nil
                self.phase = .upToDate
            }
        } catch {
            Self.log.warning("Homebrew update check failed", metadata: ["error": error.localizedDescription])
            self.phase = .failed(error.localizedDescription)
        }
    }

    func performInstall() async {
        guard self.phase != .installing, self.phase != .checking,
              let targetVersion = self.updateStatus.availableVersion else { return }
        let startingVersion = self.dependencies.installedVersion()
        self.phase = .installing
        self.updateStatus.isInstalling = true
        defer { self.updateStatus.isInstalling = false }
        do {
            try await self.dependencies.runUpgrade()
            let installedVersion = self.dependencies.installedVersion()
            guard HomebrewCaskVersion.isNewer(installedVersion, than: startingVersion),
                  !HomebrewCaskVersion.isNewer(targetVersion, than: installedVersion)
            else {
                throw HomebrewUpdateError.versionUnchanged(installedVersion)
            }
            self.updateStatus.availableVersion = nil
            self.phase = .upToDate
            self.dependencies.relaunch()
        } catch {
            Self.log.error("Homebrew upgrade failed", metadata: ["error": error.localizedDescription])
            self.phase = .failed(error.localizedDescription)
        }
    }

    private func rescheduleChecks() {
        self.scheduledChecks?.cancel()
        self.scheduledChecks = nil
        guard self.automaticallyChecksForUpdates else { return }
        self.scheduledChecks = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkForUpdates(nil)
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }
}

extension HomebrewUpdaterController.Dependencies {
    static var live: Self {
        let bundleURL = Bundle.main.bundleURL
        return Self(
            installedVersion: { Self.bundleShortVersion(at: bundleURL) ?? AppVersion.shortVersion },
            fetchCaskSource: {
                var request = URLRequest(url: HomebrewCaskVersion.caskSourceURL, timeoutInterval: 20)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let source = String(data: data, encoding: .utf8)
                else {
                    throw HomebrewUpdateError.invalidCaskResponse
                }
                return source
            },
            runUpgrade: {
                _ = try await Self.upgrade(appBundleURL: bundleURL)
            },
            relaunch: { Self.relaunch(bundleURL: bundleURL) })
    }

    static func upgrade(
        appBundleURL: URL,
        caskroomURLs: [URL] = InstallOrigin.caskroomURLs) async throws -> SubprocessResult
    {
        guard let prefix = InstallOrigin.homebrewPrefix(appBundleURL: appBundleURL, caskroomURLs: caskroomURLs) else {
            throw HomebrewUpdateError.brewNotFound
        }
        let brew = prefix.appendingPathComponent("bin/brew").path
        guard FileManager.default.isExecutableFile(atPath: brew) else { throw HomebrewUpdateError.brewNotFound }
        let environment = Self.brewEnvironment(brewPath: brew)
        _ = try await SubprocessRunner.runToCompletion(
            binary: brew, arguments: ["update"], environment: environment, label: "homebrew-update")
        return try await SubprocessRunner.runToCompletion(
            binary: brew,
            arguments: ["upgrade", "--cask", "steipete/tap/codexbar"],
            environment: environment,
            label: "homebrew-upgrade")
    }

    static func bundleShortVersion(at bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plistURL) else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    static func brewEnvironment(
        brewPath: String,
        base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String]
    {
        var environment = base
        let brewDirectory = URL(fileURLWithPath: brewPath).deletingLastPathComponent().path
        environment["PATH"] = "\(brewDirectory):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["NONINTERACTIVE"] = "1"
        environment["HOMEBREW_NO_SUDO"] = "1"
        environment["HOMEBREW_NO_UPGRADE_QUIT_CASKS"] = "1"
        return environment
    }

    @MainActor
    private static func relaunch(bundleURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "/bin/sleep 1; /usr/bin/open -n \"$0\"", bundleURL.path]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            CodexBarLog.logger(LogCategories.app).error(
                "Relaunch after Homebrew upgrade failed",
                metadata: ["error": error.localizedDescription])
        }
    }
}
