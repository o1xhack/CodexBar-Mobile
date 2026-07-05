#if os(macOS)
import Foundation

extension OpenAIDashboardBrowserCookieImporter {
    private struct PendingCookieStoreMutation {
        let token: UUID
        let task: Task<Void, Never>
    }

    @MainActor private static var pendingCookieStoreMutations: [ObjectIdentifier: PendingCookieStoreMutation] = [:]
    private nonisolated static let cookieCacheQueue = DispatchQueue(
        label: "com.steipete.codexbar.openai-cookie-cache")

    private final class CookieLoadCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var didFinish = false

        func finish(_ action: () -> Void) {
            let shouldFinish = self.lock.withLock {
                guard !self.didFinish else { return false }
                self.didFinish = true
                return true
            }
            if shouldFinish { action() }
        }
    }

    nonisolated static func remainingTimeout(
        until deadline: Date?,
        cappedAt localLimit: TimeInterval? = nil,
        now: Date = Date()) throws -> TimeInterval
    {
        guard let deadline else {
            return localLimit.map(OpenAIDashboardFetcher.sanitizedTimeout) ?? .greatestFiniteMagnitude
        }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { throw URLError(.timedOut) }
        guard let localLimit else { return remaining }
        return min(OpenAIDashboardFetcher.sanitizedTimeout(localLimit), remaining)
    }

    nonisolated static func runBoundedCookieLoad<T: Sendable>(
        deadline: Date?,
        timeoutObserver: (@Sendable () -> Void)? = nil,
        operation: @escaping @Sendable () throws -> T) async throws -> T
    {
        guard let deadline else {
            return try await Task.detached(priority: .userInitiated, operation: operation).value
        }
        let timeout = try self.remainingTimeout(until: deadline)
        let completion = CookieLoadCompletion()
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTimer = WallClockTimeout(
                timeInterval: timeout,
                threadName: "CodexBar cookie load timeout",
                handler: {
                    completion.finish {
                        timeoutObserver?()
                        continuation.resume(throwing: URLError(.timedOut))
                    }
                })
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result(catching: operation)
                completion.finish {
                    timeoutTimer.cancel()
                    continuation.resume(with: result)
                }
            }
            timeoutTimer.start()
        }
    }

    nonisolated static func runBoundedCookieCacheOperation<T: Sendable>(
        deadline: Date?,
        operation: @escaping @Sendable () throws -> T) async throws -> T
    {
        guard let deadline else {
            return try await withCheckedThrowingContinuation { continuation in
                self.cookieCacheQueue.async {
                    continuation.resume(with: Result(catching: operation))
                }
            }
        }

        let timeout = try self.remainingTimeout(until: deadline)
        let completion = CookieLoadCompletion()
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTimer = WallClockTimeout(
                timeInterval: timeout,
                threadName: "CodexBar cookie cache timeout",
                handler: {
                    completion.finish {
                        continuation.resume(throwing: URLError(.timedOut))
                    }
                })
            self.cookieCacheQueue.async {
                let result = Result(catching: operation)
                completion.finish {
                    timeoutTimer.cancel()
                    continuation.resume(with: result)
                }
            }
            timeoutTimer.start()
        }
    }

    static func runBoundedCallback(
        deadline: Date?,
        timeoutObserver: (@Sendable () -> Void)? = nil,
        start: (@escaping @Sendable () -> Void) -> Void) async throws
    {
        let completion = CookieLoadCompletion()
        guard let deadline else {
            await withCheckedContinuation { continuation in
                start {
                    completion.finish { continuation.resume() }
                }
            }
            return
        }

        let timeout = try self.remainingTimeout(until: deadline)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timeoutTimer = WallClockTimeout(
                timeInterval: timeout,
                threadName: "CodexBar callback timeout",
                handler: {
                    completion.finish {
                        timeoutObserver?()
                        continuation.resume(throwing: URLError(.timedOut))
                    }
                })
            start {
                completion.finish {
                    timeoutTimer.cancel()
                    continuation.resume()
                }
            }
            timeoutTimer.start()
        }
    }

    static func runBoundedValueCallback<T: Sendable>(
        deadline: Date?,
        timeoutObserver: (@Sendable () -> Void)? = nil,
        start: (@escaping @Sendable (T) -> Void) -> Void) async throws -> T
    {
        let completion = CookieLoadCompletion()
        guard let deadline else {
            return await withCheckedContinuation { continuation in
                start { value in
                    completion.finish { continuation.resume(returning: value) }
                }
            }
        }

        let timeout = try self.remainingTimeout(until: deadline)
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTimer = WallClockTimeout(
                timeInterval: timeout,
                threadName: "CodexBar value callback timeout",
                handler: {
                    completion.finish {
                        timeoutObserver?()
                        continuation.resume(throwing: URLError(.timedOut))
                    }
                })
            start { value in
                completion.finish {
                    timeoutTimer.cancel()
                    continuation.resume(returning: value)
                }
            }
            timeoutTimer.start()
        }
    }

    static func runSerializedCallback(
        key: ObjectIdentifier,
        deadline: Date?,
        start: @escaping (@escaping @Sendable () -> Void) -> Void) async throws
    {
        while let pending = self.pendingCookieStoreMutations[key] {
            try await self.waitForMutation(pending.task, deadline: deadline)
            if self.pendingCookieStoreMutations[key]?.token == pending.token {
                self.pendingCookieStoreMutations[key] = nil
            }
        }

        let token = UUID()
        let task = Task { @MainActor in
            await withCheckedContinuation { continuation in
                start { continuation.resume() }
            }
        }
        self.pendingCookieStoreMutations[key] = PendingCookieStoreMutation(token: token, task: task)
        Task { @MainActor in
            await task.value
            if self.pendingCookieStoreMutations[key]?.token == token {
                self.pendingCookieStoreMutations[key] = nil
            }
        }
        try await self.waitForMutation(task, deadline: deadline)
    }

    private static func waitForMutation(_ task: Task<Void, Never>, deadline: Date?) async throws {
        try await self.runBoundedCallback(deadline: deadline) { completion in
            Task { @MainActor in
                await task.value
                completion()
            }
        }
    }
}
#endif
