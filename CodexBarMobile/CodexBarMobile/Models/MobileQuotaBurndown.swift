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

    struct NativeLane: Equatable, Sendable {
        let index: Int
        let nativeIndex: Int
        let label: String
        let seriesName: String
        let window: SyncRateWindow
    }

    private static func nativeIndex(for window: SyncRateWindow, index: Int) -> Int? {
        guard let id = window.id?.lowercased() else { return (0...2).contains(index) ? index : nil }
        switch id {
        case "primary": return 0
        case "secondary": return 1
        case "tertiary": return 2
        default: return nil
        }
    }

    static func nativeLanes(for provider: ProviderUsageSnapshot) -> [NativeLane] {
        let windows: [(index: Int, window: SyncRateWindow)] = if provider.rateWindows.isEmpty {
            [provider.primary, provider.secondary].enumerated().compactMap { index, window in
                window.map { (index: index, window: $0) }
            }
        } else {
            provider.rateWindows.enumerated().map { (index: $0.offset, window: $0.element) }
        }
        var winners: [String: NativeLane] = [:]
        for (index, window) in windows {
            guard let slot = self.nativeIndex(for: window, index: index),
                  let name = self.historySeriesName(for: window, index: index, providerID: provider.providerID)
            else { continue }
            let label: String = if provider.providerID == "codex" {
                switch name {
                case "weekly": "Weekly"
                case "monthly": "Monthly"
                default: "Session"
                }
            } else {
                window.label ?? (slot == 0 ? "Session" : slot == 1 ? "Weekly" : "Opus")
            }
            // Codex's producer resolves same-role native slots in favor of secondary.
            if let winner = winners[name], winner.nativeIndex > slot { continue }
            winners[name] = NativeLane(
                index: slot, nativeIndex: slot, label: label, seriesName: name, window: window)
        }
        return ["session", "weekly", "opus", "monthly"].compactMap { winners[$0] }
    }

    static func historySeriesName(
        for window: SyncRateWindow, index: Int, providerID: String) -> String?
    {
        // Extra-window labels and periods do not establish a shared history.
        guard let nativeIndex = self.nativeIndex(for: window, index: index) else { return nil }
        if providerID == "codex" {
            guard (0...1).contains(nativeIndex) else { return nil }
            // Mirrors CodexConsumerProjection's native-slot classification.
            switch window.windowMinutes {
            case 300: return "session"
            case 10080: return "weekly"
            case 43200: return "monthly"
            default: return nativeIndex == 0 ? "session" : "weekly"
            }
        }
        guard providerID == "claude" else { return nil }
        switch nativeIndex {
        case 0: return "session"
        case 1: return "weekly"
        case 2: return "opus"
        default: return nil
        }
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
