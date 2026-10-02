import CodexBarSync
import Foundation

/// An observation-based projection, never a prediction of usage or access.
struct MobileQuotaBurndown: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let date: Date
        let remainingPercent: Double
    }

    let start: Date
    let reset: Date
    let capturedAt: Date
    let samples: [Sample]
    let ideal: [Sample]

    static func historySeriesName(for window: SyncRateWindow, index: Int) -> String? {
        let id = window.id?.lowercased() ?? ""
        let label = window.label?.lowercased() ?? ""
        if id.contains("opus") || label.contains("opus") { return "opus" }
        if window.period == .weekly || id.contains("weekly") || label.contains("week") { return "weekly" }
        if id == "tertiary" { return "opus" }
        if id == "secondary" || label.contains("sonnet") { return "weekly" }
        if id == "primary" || window.period == .session || id.contains("session") || label.contains("session") {
            return "session"
        }
        if window.id == nil {
            switch index {
            case 0: return "session"
            case 1: return "weekly"
            case 2: return "opus"
            default: break
            }
        }
        return nil
    }

    init?(
        series: SyncUtilizationSeries?,
        window: SyncRateWindow,
        capturedAt: Date,
        referenceDate: Date)
    {
        guard window.usageKnown, !window.isSyntheticPlaceholder, window.blockingQuota == nil,
              window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
              let minutes = window.windowMinutes, minutes > 0,
              let reset = window.resetsAt,
              reset.timeIntervalSince1970.isFinite,
              capturedAt.timeIntervalSince1970.isFinite,
              referenceDate.timeIntervalSince1970.isFinite,
              capturedAt <= referenceDate, referenceDate < reset,
              series == nil || series?.windowMinutes == minutes
        else { return nil }
        let start = reset.addingTimeInterval(-Double(minutes) * 60)
        guard start.timeIntervalSince1970.isFinite, start <= capturedAt, capturedAt < reset else { return nil }

        let history = (series?.entries ?? []).enumerated().filter { _, entry in
            entry.capturedAt.timeIntervalSince1970.isFinite
                && entry.capturedAt >= start && entry.capturedAt <= capturedAt
                && entry.usedPercent.isFinite && (0...100).contains(entry.usedPercent)
                && (entry.resetsAt.map {
                    $0.timeIntervalSince1970.isFinite && abs($0.timeIntervalSince(reset)) <= 120
                } ?? true)
        }.sorted { lhs, rhs in
            lhs.element.capturedAt == rhs.element.capturedAt
                ? lhs.offset < rhs.offset : lhs.element.capturedAt < rhs.element.capturedAt
        }.map(\.element)
        var segment: [SyncUtilizationEntry] = []
        let current = SyncUtilizationEntry(capturedAt: capturedAt, usedPercent: window.usedPercent, resetsAt: reset)
        for entry in history + [current] {
            if let last = segment.last, entry.capturedAt == last.capturedAt {
                segment.removeLast()
            }
            if let last = segment.last, entry.usedPercent < last.usedPercent {
                segment.removeAll(keepingCapacity: true)
            }
            segment.append(entry)
        }
        self.start = start
        self.reset = reset
        self.capturedAt = capturedAt
        self.samples = segment.map { Sample(date: $0.capturedAt, remainingPercent: 100 - $0.usedPercent) }
        self.ideal = [Sample(date: start, remainingPercent: 100), Sample(date: reset, remainingPercent: 0)]
    }
}
