import Foundation

package enum BoundedTaskJoinOutcome<Value: Sendable> {
    case value(Value)
    case failure(any Error)
    case timedOut
}

package final class BoundedTaskJoin<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let sourceTask: Task<Value, Error>
    private var outcome: BoundedTaskJoinOutcome<Value>?
    private var continuation: CheckedContinuation<BoundedTaskJoinOutcome<Value>, Never>?
    private var observerTask: Task<Void, Never>?
    private var timeoutTimer: TimeoutTimer?

    package init(sourceTask: Task<Value, Error>) {
        self.sourceTask = sourceTask
    }

    package func value(joinGrace: Duration) async -> BoundedTaskJoinOutcome<Value> {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.lock.lock()
                if let outcome = self.outcome {
                    self.lock.unlock()
                    continuation.resume(returning: outcome)
                    return
                }

                self.continuation = continuation
                let sourceTask = self.sourceTask
                self.observerTask = Task { [weak self] in
                    do {
                        let value = try await sourceTask.value
                        self?.resolve(.value(value), cancelSource: false)
                    } catch {
                        self?.resolve(.failure(error), cancelSource: false)
                    }
                }
                let timeoutTimer = TimeoutTimer(joinGrace: joinGrace) { [weak self] in
                    self?.resolve(.timedOut, cancelSource: true)
                }
                self.timeoutTimer = timeoutTimer
                timeoutTimer.resume()
                self.lock.unlock()
            }
        } onCancel: {
            self.resolve(.failure(CancellationError()), cancelSource: true)
        }
    }

    private final class TimeoutTimer: @unchecked Sendable {
        private let timer: WallClockTimeout

        init(joinGrace: Duration, handler: @escaping @Sendable () -> Void) {
            self.timer = WallClockTimeout(
                duration: joinGrace,
                threadName: "CodexBar bounded task timeout",
                handler: handler)
        }

        func resume() {
            self.timer.start()
        }

        func cancel() {
            self.timer.cancel()
        }
    }

    private func resolve(_ outcome: BoundedTaskJoinOutcome<Value>, cancelSource: Bool) {
        self.lock.lock()
        guard self.outcome == nil else {
            self.lock.unlock()
            return
        }

        self.outcome = outcome
        let continuation = self.continuation
        self.continuation = nil
        let observerTask = self.observerTask
        let timeoutTimer = self.timeoutTimer
        self.observerTask = nil
        self.timeoutTimer = nil
        self.lock.unlock()

        if cancelSource {
            self.sourceTask.cancel()
        }
        observerTask?.cancel()
        timeoutTimer?.cancel()
        continuation?.resume(returning: outcome)
    }
}
