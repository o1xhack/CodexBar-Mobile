import Foundation

protocol UsageQuotaHistoryInspecting {
    static func observation(at date: Date, samples: [UsageQuotaPoint]) -> UsageQuotaPoint?
}

/// Inspection never interpolates a value or carries a reading through missing history.
enum UsageQuotaDetailPresentation: UsageQuotaHistoryInspecting {
    static func observation(at date: Date, samples: [UsageQuotaPoint]) -> UsageQuotaPoint? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        let valid = samples.filter {
            $0.date.timeIntervalSince1970.isFinite && $0.remainingPercent.isFinite
                && (0...100).contains($0.remainingPercent)
        }
        if let exact = valid.last(where: { $0.date == date }) { return exact }
        for segment in Dictionary(grouping: valid, by: \.segment).values {
            let ordered = segment.sorted { $0.date < $1.date }
            guard let first = ordered.first, let last = ordered.last,
                  first.date < date, date < last.date else { continue }
            return ordered.min {
                let lhs = abs($0.date.timeIntervalSince(date))
                let rhs = abs($1.date.timeIntervalSince(date))
                return lhs == rhs ? $0.date < $1.date : lhs < rhs
            }
        }
        return nil
    }

    /// Nil selection is idle: each series retains its own latest real timestamp.
    /// Explicit inspection never falls back to that reading across a gap.
    static func reading(
        selectedDate: Date?, samples: [UsageQuotaPoint], domain: ClosedRange<Date>) -> UsageQuotaPoint?
    {
        let visible = samples.filter {
            domain.contains($0.date) && $0.date.timeIntervalSince1970.isFinite
                && $0.remainingPercent.isFinite && (0...100).contains($0.remainingPercent)
        }
        if let selectedDate { return self.observation(at: selectedDate, samples: visible) }
        return visible.max { $0.date < $1.date }
    }

    static func currentRemaining(_ line: UsageQuotaResolvedLine, now: Date) -> Double? {
        guard line.state == .available, !line.isStale, let reset = line.resetDate, reset > now,
              let value = line.currentRemainingPercent, value.isFinite, (0...100).contains(value)
        else { return nil }
        return value
    }

    static func currentLines(_ lines: [UsageQuotaResolvedLine], now: Date) -> [UsageQuotaResolvedLine] {
        lines.enumerated().sorted { lhs, rhs in
            func upcoming(_ line: UsageQuotaResolvedLine) -> Date {
                guard let reset = line.resetDate, reset.timeIntervalSince1970.isFinite, reset > now
                else { return .distantFuture }
                return reset
            }
            let left = upcoming(lhs.element), right = upcoming(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }
}
