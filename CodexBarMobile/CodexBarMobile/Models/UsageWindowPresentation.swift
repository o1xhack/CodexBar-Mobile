import CodexBarSync
import Foundation

/// Effective availability stays authoritative; raw use only explains why a
/// shorter lane is blocked. The phone clock cannot restore quota availability.
struct UsageWindowPresentation: Equatable {
    let window: SyncRateWindow

    var isBlocked: Bool {
        self.window.blockingQuota != nil
    }

    var rawUsedPercent: Double? {
        guard let value = self.window.blockingQuota?.rawUsedPercent,
              value.isFinite, (0...100).contains(value)
        else { return nil }
        return value
    }

    var resetDate: Date? {
        guard let date = self.window.resetsAt, date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }

    func hasExpiredObservation(at date: Date) -> Bool {
        self.resetDate.map { $0 <= date } ?? false
    }
}
