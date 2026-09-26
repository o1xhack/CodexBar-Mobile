import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

@Suite("ModelContainerFactory Tests")
struct ModelContainerFactoryTests {

    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    @Test("Container creates successfully at a temp URL")
    func testContainerCreatesSuccessfully() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let container = ModelContainerFactory.makeContainer(at: url)

        // Smoke: fetch an empty table and ensure we get back an empty array
        // rather than throwing.
        let context = ModelContext(container)
        let results = try context.fetch(FetchDescriptor<DeviceRecord>())
        #expect(results.isEmpty)
    }

    @Test("Data persists across container relaunches at the same URL")
    @MainActor
    func testPersistenceAcrossRelaunches() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let deviceID = "persistence-test-\(UUID().uuidString)"

        // Launch 1: insert a DeviceRecord and save.
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            let device = DeviceRecord(deviceID: deviceID, deviceName: "MacBook Pro")
            context.insert(device)
            try context.save()
        }

        // Launch 2: re-open the same URL and confirm the row survives.
        do {
            let container = ModelContainerFactory.makeContainer(at: url)
            let context = ModelContext(container)
            let captured = deviceID
            let descriptor = FetchDescriptor<DeviceRecord>(
                predicate: #Predicate { $0.deviceID == captured })
            let results = try context.fetch(descriptor)
            #expect(results.count == 1)
            #expect(results.first?.deviceName == "MacBook Pro")
        }
    }

    @Test("Default store URL is a valid writable location")
    func testDefaultStoreURLIsWritable() throws {
        let url = ModelContainerFactory.defaultStoreURL()
        let parent = url.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: parent.path))
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false)
        #expect(url == appSupport.appendingPathComponent("CodexBar/CodexBarStore.sqlite"))
    }
    @Test("Open failure preserves the database and both SQLite sidecars")
    func failedOpenPreservesFiles() throws {
        struct UnavailableStore: Error {}
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let files = ["", "-wal", "-shm"].map { URL(fileURLWithPath: url.path + $0) }
        for (index, file) in files.enumerated() {
            try Data("unique saved history \(index)".utf8).write(to: file)
        }
        let original = try files.map { try Data(contentsOf: $0) }
        let result = ModelContainerFactory.openContainer(at: url) { _, _ in
            throw UnavailableStore()
        }
        #expect(!result.isPersistent)
        #expect(try files.map { try Data(contentsOf: $0) } == original)
    }

    @Test("A later successful open recovers history after temporary storage")
    @MainActor
    func successfulReopenRecoversHistory() throws {
        struct UnavailableStore: Error {}
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        do {
            let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
            context.insert(DailyCostPoint(
                deviceID: "history-mac", providerID: "codex", accountEmail: nil,
                dayKey: "2026-01-01", costUSD: 12000, totalTokens: 900,
                lastUpdated: Date(timeIntervalSince1970: 1767225600)))
            try context.save()
        }
        let temporary = ModelContainerFactory.openContainer(at: url) { _, _ in
            throw UnavailableStore()
        }
        #expect(!temporary.isPersistent)
        #expect(try ModelContext(temporary.container).fetch(FetchDescriptor<DailyCostPoint>()).isEmpty)
        let reopened = ModelContainerFactory.openContainer(at: url)
        #expect(reopened.isPersistent)
        let history = try ModelContext(reopened.container).fetch(FetchDescriptor<DailyCostPoint>())
        #expect(history.count == 1)
        #expect(history.first?.costUSD == 12000)
        #expect(history.first?.dayKey == "2026-01-01")
    }

    @Test("Temporary mode cannot clear preserved history or advance its tombstone")
    @MainActor
    func temporaryModeRejectsClear() throws {
        struct UnavailableStore: Error {}
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let suite = "history-clear-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let result = ModelContainerFactory.openContainer(at: url) { _, _ in throw UnavailableStore() }
        let context = ModelContext(result.container)
        context.insert(DailyCostPoint(
            deviceID: "mac", providerID: "codex", accountEmail: nil,
            dayKey: "2026-01-01", costUSD: 12000, totalTokens: 900, lastUpdated: Date()))
        try context.save()
        #expect(throws: CostLedgerService.ClearError.self) {
            try CostLedgerService.clearAll(
                in: context, userDefaults: defaults, persistentStorageAvailable: result.isPersistent)
        }
        #expect(!CostLedgerService.hasBlobSeedClearTombstone(userDefaults: defaults))
        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).first?.costUSD == 12000)
    }

}
