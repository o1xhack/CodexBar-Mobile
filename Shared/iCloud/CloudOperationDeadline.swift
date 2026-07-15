import Foundation

/// A hard wall-clock deadline for callback-based CloudKit operations.
///
/// CloudKit's async convenience APIs do not expose the underlying operation,
/// so callers cannot reliably cancel a request that never calls back. The Mac
/// write path uses this gate with explicit `CKOperation` instances: timeout or
/// task cancellation first claims the exactly-once completion, then invokes
/// the supplied cancellation closure. Late CloudKit callbacks are ignored.
public enum CloudOperationDeadlineError: Error, Sendable, Equatable, LocalizedError {
    case timedOut(stage: String)

    public var errorDescription: String? {
        switch self {
        case let .timedOut(stage):
            "iCloud sync timed out during \(stage)"
        }
    }
}

enum CloudOperationDeadline {
    private static let timeoutQueue = DispatchQueue(
        label: "com.o1xhack.codexbar.cloudkit-deadlines",
        qos: .utility)

    static func run<Value: Sendable>(
        stage: String,
        timeout: TimeInterval,
        cancel: @escaping @Sendable () -> Void,
        start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void) async throws -> Value
    {
        let gate = CloudOperationCompletionGate<Value>(cancel: cancel)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                start { result in
                    gate.complete(with: result, cancelOperation: false)
                }

                let timeoutWork = DispatchWorkItem {
                    gate.complete(
                        with: .failure(CloudOperationDeadlineError.timedOut(stage: stage)),
                        cancelOperation: true)
                }
                gate.install(timeoutWork: timeoutWork)
                Self.timeoutQueue.asyncAfter(
                    deadline: .now() + max(timeout, 0),
                    execute: timeoutWork)
            }
        } onCancel: {
            gate.complete(with: .failure(CancellationError()), cancelOperation: true)
        }
    }
}

private final class CloudOperationCompletionGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelOperation: (@Sendable () -> Void)?
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var timeoutWork: DispatchWorkItem?

    init(cancel: @escaping @Sendable () -> Void) {
        self.cancelOperation = cancel
    }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let completedResult = self.lock.withLock { () -> Result<Value, Error>? in
            if let result = self.result {
                return result
            }
            self.continuation = continuation
            return nil
        }
        if let completedResult {
            continuation.resume(with: completedResult)
        }
    }

    func install(timeoutWork: DispatchWorkItem) {
        let shouldCancel = self.lock.withLock {
            guard self.result == nil else { return true }
            self.timeoutWork = timeoutWork
            return false
        }
        if shouldCancel {
            timeoutWork.cancel()
        }
    }

    func complete(with result: Result<Value, Error>, cancelOperation: Bool) {
        let completion = self.lock.withLock {
            () -> (CheckedContinuation<Value, Error>?, DispatchWorkItem?, (@Sendable () -> Void)?)? in
            guard self.result == nil else { return nil }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            let timeoutWork = self.timeoutWork
            self.timeoutWork = nil
            let cancellation = self.cancelOperation
            self.cancelOperation = nil
            return (continuation, timeoutWork, cancellation)
        }
        guard let completion else { return }

        completion.1?.cancel()
        if cancelOperation {
            completion.2?()
        }
        completion.0?.resume(with: result)
    }
}

struct CloudOperationBudget: Sendable {
    private let deadline: Date

    init(seconds: TimeInterval) {
        self.deadline = Date().addingTimeInterval(max(seconds, 0))
    }

    func remaining(for stage: String) throws -> TimeInterval {
        let remaining = self.deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            throw CloudOperationDeadlineError.timedOut(stage: stage)
        }
        return remaining
    }
}

final class LockedResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Value, Error>?

    func set(_ value: Result<Value, Error>) {
        self.lock.withLock {
            self.value = value
        }
    }

    func get() -> Result<Value, Error>? {
        self.lock.withLock { self.value }
    }
}

final class LockedArrayBox<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element] = []

    func append(_ value: Element) {
        self.lock.withLock {
            self.values.append(value)
        }
    }

    func snapshot() -> [Element] {
        self.lock.withLock { self.values }
    }
}
