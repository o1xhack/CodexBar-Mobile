import CloudKit
import Foundation
import Testing
@testable import CodexBarSync

private final class DeadlineTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        self.lock.withLock { self.value = true }
    }

    func get() -> Bool {
        self.lock.withLock { self.value }
    }
}

private final class DeadlineCompletionBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<Value, Error>) -> Void)?

    func set(_ completion: @escaping @Sendable (Result<Value, Error>) -> Void) {
        self.lock.withLock { self.completion = completion }
    }

    func succeed(_ value: Value) {
        self.lock.withLock { self.completion }?(.success(value))
    }
}

private enum DeadlineTestError: Error, Equatable {
    case failed
}

private final class RetainingDeadlineOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<Int, Error>) -> Void)?

    func start(_ completion: @escaping @Sendable (Result<Int, Error>) -> Void) {
        self.lock.withLock { self.completion = completion }
        completion(.success(7))
    }

    func cancel() {}
}

struct CloudOperationDeadlineTests {
    @Test
    func `CloudKit operation receives an explicit deadline configuration`() throws {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [])

        CloudSyncManager.configureOperation(operation, deadline: 17)

        let configuration = try #require(operation.configuration)
        #expect(configuration.timeoutIntervalForRequest == 17)
        #expect(configuration.timeoutIntervalForResource == 17)
        #expect(operation.qualityOfService == .utility)
    }

    @Test
    func `synchronous success returns without cancelling the operation`() async throws {
        let cancelled = DeadlineTestFlag()

        let value = try await CloudOperationDeadline.run(
            stage: "account status",
            timeout: 1,
            cancel: { cancelled.set() },
            start: { finish in finish(.success(42)) })

        #expect(value == 42)
        #expect(!cancelled.get())
    }

    @Test
    func `operation error is forwarded without reporting a timeout`() async {
        let cancelled = DeadlineTestFlag()

        await #expect(throws: DeadlineTestError.failed) {
            let _: Int = try await CloudOperationDeadline.run(
                stage: "zone fetch",
                timeout: 1,
                cancel: { cancelled.set() },
                start: { finish in finish(.failure(DeadlineTestError.failed)) })
        }

        #expect(!cancelled.get())
    }

    @Test
    func `timeout cancels the operation and returns a stage-specific error`() async {
        let cancelled = DeadlineTestFlag()

        await #expect(throws: CloudOperationDeadlineError.timedOut(stage: "record save")) {
            let _: Void = try await CloudOperationDeadline.run(
                stage: "record save",
                timeout: 0.02,
                cancel: { cancelled.set() },
                start: { _ in })
        }
        #expect(cancelled.get())
    }

    @Test
    func `late callback after timeout is ignored`() async {
        let cancelled = DeadlineTestFlag()
        let completion = DeadlineCompletionBox<Int>()

        await #expect(throws: CloudOperationDeadlineError.timedOut(stage: "zone fetch")) {
            _ = try await CloudOperationDeadline.run(
                stage: "zone fetch",
                timeout: 0.02,
                cancel: { cancelled.set() },
                start: { finish in
                    completion.set(finish)
                })
        }

        completion.succeed(42)
        #expect(cancelled.get())
    }

    @Test
    func `task cancellation cancels the operation and returns cancellation`() async {
        let cancelled = DeadlineTestFlag()
        let task = Task {
            let _: Int = try await CloudOperationDeadline.run(
                stage: "record save",
                timeout: 60,
                cancel: { cancelled.set() },
                start: { _ in })
        }

        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(cancelled.get())
    }

    @Test
    func `completed operation does not remain retained by its completion gate`() async throws {
        weak var weakOperation: RetainingDeadlineOperation?

        do {
            let operation = RetainingDeadlineOperation()
            weakOperation = operation
            let value = try await CloudOperationDeadline.run(
                stage: "record fetch",
                timeout: 1,
                cancel: { operation.cancel() },
                start: { operation.start($0) })
            #expect(value == 7)
        }

        await Task.yield()
        #expect(weakOperation == nil)
    }
}
