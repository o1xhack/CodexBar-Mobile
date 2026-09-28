import Foundation
import SwiftData

/// Builds and caches the app-wide `ModelContainer`.
///
/// P2a behavior:
/// - The store stays in the app sandbox even if an App Group entitlement is
///   added. Switching URLs would hide pre-2.2 local history on upgrade.
///   Widget extensions consume a separate read-only projection in App Group.
/// - Persistent history is not a disposable CloudKit cache: it can outlive
///   the producer's current sync window. Opening failures preserve every file
///   and use explicitly reported temporary storage until the next launch.
enum ModelContainerFactory {
    /// Shared projection group; the SwiftData store does not move here.
    static let appGroupID = "group.com.o1xhack.codexbar"

    /// Default SQLite filename inside whichever container we land on.
    static let storeFilename = "CodexBarStore.sqlite"

    // `NSLock` is reference-type and inherently thread-safe; access to
    // `sharedContainer` is serialised by the lock below, so marking the
    // stored state `nonisolated(unsafe)` is correct under Swift 6 strict
    // concurrency.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sharedContainer: ModelContainer?
    nonisolated(unsafe) private static var temporaryStorage = false

    struct OpenResult {
        let container: ModelContainer
        let isPersistent: Bool
    }

    static var isUsingTemporaryStore: Bool {
        lock.lock()
        defer { lock.unlock() }
        return temporaryStorage
    }

    /// Returns a lazily-constructed app-wide container. Thread-safe.
    static func shared() -> ModelContainer {
        lock.lock()
        defer { lock.unlock() }
        if let existing = sharedContainer { return existing }
        let result = Self.openContainer(at: Self.defaultStoreURL())
        sharedContainer = result.container
        temporaryStorage = !result.isPersistent
        return result.container
    }

    /// Main-actor convenience for view code that wants a `ModelContext` directly.
    @MainActor
    static func sharedMainContext() -> ModelContext {
        Self.shared().mainContext
    }

    /// Exposed for tests: build a container at an explicit URL (typically a
    /// temporary directory) without touching the shared singleton.
    static func makeContainer(at storeURL: URL) -> ModelContainer {
        Self.openContainer(at: storeURL).container
    }

    /// The injectable opener verifies failure handling without corrupting a
    /// real user's database. Neither failure path deletes or renames the store.
    static func openContainer(
        at storeURL: URL,
        opener: (Schema, ModelConfiguration) throws -> ModelContainer = { schema, configuration in
            try ModelContainer(for: schema, configurations: configuration)
        }) -> OpenResult
    {
        let schema = Schema(CodexBarSwiftDataSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none)
        do {
            return try OpenResult(container: opener(schema, configuration), isPersistent: true)
        } catch {
            print("[CodexBar SwiftData] Persistent store unavailable; preserving files " +
                "and using temporary storage. Error: \(error)")
            let memoryConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none)
            // If even the in-memory schema cannot open, the application cannot
            // operate. This failure must still never destroy the original files.
            let container = try! ModelContainer(for: schema, configurations: memoryConfiguration)
            return OpenResult(container: container, isPersistent: false)
        }
    }

    /// Default on-disk location. Keep the pre-2.2 app-sandbox URL on upgrades.
    static func defaultStoreURL() -> URL {
        let fm = FileManager.default
        let base: URL
        do {
            base = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
        } catch {
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let dir = base.appendingPathComponent("CodexBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.storeFilename, isDirectory: false)
    }

    /// Remove the SQLite file + its WAL/SHM sidecars. Safe if files are absent.
    static func deleteStoreFiles(at storeURL: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    /// Test hook to clear the cached singleton between test cases.
    static func _resetSharedForTests() {
        lock.lock()
        sharedContainer = nil
        temporaryStorage = false
        lock.unlock()
    }
}
