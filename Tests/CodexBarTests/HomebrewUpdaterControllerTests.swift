import Foundation
import Observation
import os
import Testing
@testable import CodexBar

@MainActor
struct HomebrewUpdaterControllerTests {
    private static let caskSource = """
    cask "codexbar" do
      version "0.66.0"
      sha256 "a12bbb5e6a6a8d539aa9bd67df6dcae6433f005c639a1d4b9595d8fc218f5616"

      url "https://github.com/steipete/CodexBar/releases/download/v#{version}/CodexBar-macos-universal-#{version}.zip"
      auto_updates true
    end
    """

    @MainActor
    private final class Fixture {
        var installedVersion = "0.65.0"
        var caskSource = HomebrewUpdaterControllerTests.caskSource
        var fetchError: Error?
        var upgradeError: Error?
        var versionAfterUpgrade: String?
        var upgradeCount = 0
        var upgradeWait: CheckedContinuation<Void, Never>?
        var suspendUpgrade = false
        var relaunchCount = 0

        func makeController() -> HomebrewUpdaterController {
            HomebrewUpdaterController(
                savedAutoCheck: false,
                dependencies: HomebrewUpdaterController.Dependencies(
                    installedVersion: { self.installedVersion },
                    fetchCaskSource: { @MainActor in
                        if let error = self.fetchError { throw error }
                        return self.caskSource
                    },
                    runUpgrade: { @MainActor in
                        self.upgradeCount += 1
                        if self.suspendUpgrade, self.upgradeCount == 1 {
                            await withCheckedContinuation { self.upgradeWait = $0 }
                        }
                        if let error = self.upgradeError { throw error }
                        if let version = self.versionAfterUpgrade { self.installedVersion = version }
                    },
                    relaunch: { self.relaunchCount += 1 }),
                startScheduledChecks: false)
        }
    }

    @Test
    func `parses the version declared by the cask`() {
        #expect(HomebrewCaskVersion.parse(caskSource: Self.caskSource) == "0.66.0")
        #expect(HomebrewCaskVersion.parse(caskSource: "cask \"codexbar\" do\nend") == nil)
        #expect(HomebrewCaskVersion.parse(caskSource: "  version \"\"") == nil)
    }

    @Test
    func `compares versions numerically`() {
        #expect(HomebrewCaskVersion.isNewer("0.66.0", than: "0.65.0"))
        #expect(HomebrewCaskVersion.isNewer("0.100.0", than: "0.99.1"))
        #expect(!HomebrewCaskVersion.isNewer("0.65.0", than: "0.65.0"))
        #expect(!HomebrewCaskVersion.isNewer("0.64.9", than: "0.65.0"))
    }

    @Test
    func `stable release supersedes its prerelease`() {
        #expect(HomebrewCaskVersion.isNewer("0.66.0", than: "0.66.0-beta.1"))
        #expect(!HomebrewCaskVersion.isNewer("0.66.0-beta.1", than: "0.66.0"))
    }

    @Test
    func `stale local tap cannot report an incomplete upgrade as success`() async {
        let fixture = Fixture()
        fixture.caskSource = "version \"0.67.0\""
        fixture.versionAfterUpgrade = "0.66.0"
        let controller = fixture.makeController()
        await controller.performCheck()
        await controller.performInstall()
        #expect(fixture.relaunchCount == 0)
        #expect(controller.phase == .failed(HomebrewUpdateError.versionUnchanged("0.66.0").localizedDescription))
    }

    @Test
    func `newer cask version is offered for install`() async {
        let fixture = Fixture()
        let controller = fixture.makeController()

        await controller.performCheck()

        #expect(controller.phase == .available("0.66.0"))
        #expect(controller.updateStatus.availableVersion == "0.66.0")
    }

    @Test
    func `older remote tap is not offered as a downgrade`() async {
        let fixture = Fixture()
        fixture.installedVersion = "0.67.0"
        let controller = fixture.makeController()
        await controller.performCheck()
        await controller.performInstall()
        #expect(controller.phase == .upToDate)
        #expect(controller.updateStatus.availableVersion == nil)
        #expect(fixture.upgradeCount == 0)
    }

    @Test
    func `matching cask version reports up to date`() async {
        let fixture = Fixture()
        fixture.installedVersion = "0.66.0"
        let controller = fixture.makeController()

        await controller.performCheck()

        #expect(controller.phase == .upToDate)
        #expect(controller.updateStatus.availableVersion == nil)
    }

    @Test
    func `failed check keeps the update and exposes recovery`() async {
        let fixture = Fixture()
        let controller = fixture.makeController()
        await controller.performCheck()

        fixture.fetchError = HomebrewUpdateError.invalidCaskResponse
        await controller.performCheck()

        #expect(controller.phase == .failed(HomebrewUpdateError.invalidCaskResponse.localizedDescription))
        #expect(controller.updateStatus.availableVersion == "0.66.0")
    }

    @Test
    func `successful upgrade relaunches the app`() async {
        let fixture = Fixture()
        fixture.versionAfterUpgrade = "0.66.0"
        let controller = fixture.makeController()
        await controller.performCheck()

        await controller.performInstall()

        #expect(fixture.upgradeCount == 1)
        #expect(fixture.relaunchCount == 1)
        #expect(controller.updateStatus.availableVersion == nil)
        #expect(controller.updateStatus.isInstalling == false)
    }

    @Test
    func `upgrade that leaves the version unchanged fails without relaunching`() async {
        let fixture = Fixture()
        let controller = fixture.makeController()
        await controller.performCheck()

        await controller.performInstall()

        #expect(fixture.relaunchCount == 0)
        #expect(controller.phase == .failed(HomebrewUpdateError.versionUnchanged("0.65.0").localizedDescription))
        #expect(controller.updateStatus.availableVersion == "0.66.0")
        #expect(controller.updateStatus.isInstalling == false)
    }

    @Test
    func `missing brew surfaces a failure`() async {
        let fixture = Fixture()
        fixture.upgradeError = HomebrewUpdateError.brewNotFound
        let controller = fixture.makeController()
        await controller.performCheck()

        await controller.performInstall()

        #expect(fixture.relaunchCount == 0)
        #expect(controller.phase == .failed(HomebrewUpdateError.brewNotFound.localizedDescription))
    }

    @Test
    func `concurrent install and check cannot overlap an upgrade`() async {
        let fixture = Fixture()
        fixture.suspendUpgrade = true
        fixture.versionAfterUpgrade = "0.66.0"
        let controller = fixture.makeController()
        await controller.performCheck()
        let first = Task { await controller.performInstall() }
        while fixture.upgradeWait == nil {
            await Task.yield()
        }

        await controller.performCheck()
        #expect(controller.phase == .installing)
        await controller.performInstall()
        #expect(fixture.upgradeCount == 1)
        #expect(controller.updateStatus.isInstalling)
        fixture.upgradeWait?.resume()
        await first.value
        #expect(fixture.relaunchCount == 1)
    }

    @Test
    func `failed initial check exposes the error for manual recovery`() async {
        let fixture = Fixture()
        fixture.fetchError = HomebrewUpdateError.invalidCaskResponse
        let controller = fixture.makeController()
        await controller.performCheck()
        #expect(controller.phase == .failed(HomebrewUpdateError.invalidCaskResponse.localizedDescription))
    }

    @Test
    func `brew environment puts the brew prefix first on PATH`() {
        let environment = HomebrewUpdaterController.Dependencies.brewEnvironment(
            brewPath: "/opt/homebrew/bin/brew",
            base: ["HOME": "/Users/example", "PATH": "/custom"])

        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environment["HOME"] == "/Users/example")
        #expect(environment["HOMEBREW_NO_ENV_HINTS"] == "1")
        #expect(environment["HOMEBREW_NO_SUDO"] == "1")
        #expect(environment["NONINTERACTIVE"] == "1")
    }

    @Test
    func `update status changes notify menu observers`() {
        let status = UpdateStatus()
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = status.availableVersion
            _ = status.isInstalling
        } onChange: {
            changed.withLock { $0 = true }
        }
        status.availableVersion = "0.66.0"
        #expect(changed.withLock { $0 })
        changed.withLock { $0 = false }
        withObservationTracking {
            _ = status.isInstalling
        } onChange: {
            changed.withLock { $0 = true }
        }
        status.isInstalling = true
        #expect(changed.withLock { $0 })
    }

    @Test
    func `menu offers available update and shows install progress`() {
        let available = MenuDescriptor.metaSection(updateReady: false, availableUpdateVersion: "0.66.0")
        #expect(available.entries.contains { entry in
            if case let .action(title, .installUpdate) = entry { return title == "Update to 0.66.0" }
            return false
        })

        let installing = MenuDescriptor.metaSection(
            updateReady: false,
            availableUpdateVersion: "0.66.0",
            isInstallingUpdate: true)
        #expect(installing.entries.contains { entry in
            if case let .text(title, _) = entry { return title == "Updating with Homebrew…" }
            return false
        })
        #expect(!installing.entries.contains { entry in
            if case .action(_, .installUpdate) = entry { return true }
            return false
        })
    }
}
