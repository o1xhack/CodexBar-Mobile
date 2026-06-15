import Foundation

extension UsageStore {
    private final class ProbeTimeoutRace: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, Never>?
        private var result: String?
        private var tasks: [Task<Void, Never>] = []

        func install(_ continuation: CheckedContinuation<String, Never>) {
            let result: String? = self.lock.withLock {
                if let result = self.result {
                    return result
                }
                self.continuation = continuation
                return nil
            }
            if let result {
                continuation.resume(returning: result)
            }
        }

        func install(_ task: Task<Void, Never>) {
            let shouldCancel = self.lock.withLock {
                guard self.result == nil else { return true }
                self.tasks.append(task)
                return false
            }
            if shouldCancel {
                task.cancel()
            }
        }

        func complete(with result: String) {
            let completion = self.lock.withLock {
                guard self.result == nil else {
                    return (nil as CheckedContinuation<String, Never>?, [] as [Task<Void, Never>])
                }
                self.result = result
                let continuation = self.continuation
                self.continuation = nil
                let tasks = self.tasks
                self.tasks.removeAll()
                return (continuation, tasks)
            }
            completion.1.forEach { $0.cancel() }
            completion.0?.resume(returning: result)
        }
    }

    nonisolated static func runWithTimeout(
        seconds: Double,
        operation: @escaping @Sendable () async -> String) async -> String
    {
        let timeoutMessage = "Probe timed out after \(Int(seconds))s"
        let race = ProbeTimeoutRace()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.install(continuation)

                race.install(Task {
                    let result = await operation()
                    race.complete(with: result)
                })
                race.install(Task {
                    try? await Task.sleep(for: .seconds(max(seconds, 0)))
                    guard !Task.isCancelled else { return }
                    race.complete(with: timeoutMessage)
                })
            }
        } onCancel: {
            race.complete(with: timeoutMessage)
        }
    }
}
