import Foundation

package final class WallClockTimeout: @unchecked Sendable {
    private static let maximumInterval: TimeInterval = 60 * 60 * 24 * 365 * 100

    private let condition = NSCondition()
    private let deadline: Date
    private let handler: @Sendable () -> Void
    private let threadName: String?
    private var didStart = false
    private var isCancelled = false

    package convenience init(
        duration: Duration,
        threadName: String? = nil,
        handler: @escaping @Sendable () -> Void)
    {
        self.init(
            timeInterval: Self.timeInterval(for: duration),
            threadName: threadName,
            handler: handler)
    }

    package init(
        timeInterval: TimeInterval,
        threadName: String? = nil,
        handler: @escaping @Sendable () -> Void)
    {
        self.deadline = Self.deadline(after: timeInterval)
        self.threadName = threadName
        self.handler = handler
    }

    package func start() {
        self.condition.lock()
        guard !self.didStart else {
            self.condition.unlock()
            return
        }
        self.didStart = true
        self.condition.unlock()

        let thread = Thread { self.run() }
        thread.name = self.threadName
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    package func cancel() {
        self.condition.lock()
        self.isCancelled = true
        self.condition.signal()
        self.condition.unlock()
    }

    private func run() {
        let shouldFire: Bool
        self.condition.lock()
        while !self.isCancelled {
            let now = Date()
            guard now < self.deadline else { break }
            self.condition.wait(until: self.deadline)
        }
        shouldFire = !self.isCancelled
        self.condition.unlock()

        if shouldFire {
            self.handler()
        }
    }

    private static func deadline(after interval: TimeInterval) -> Date {
        guard interval.isFinite else { return .distantFuture }
        let clamped = max(0, min(interval, Self.maximumInterval))
        return Date().addingTimeInterval(clamped)
    }

    private static func timeInterval(for duration: Duration) -> TimeInterval {
        guard duration > .zero else { return 0 }
        let components = duration.components
        let seconds = max(0, Double(components.seconds))
        let attoseconds = max(0, Double(components.attoseconds))
        return min(seconds + attoseconds / 1_000_000_000_000_000_000, Self.maximumInterval)
    }
}
