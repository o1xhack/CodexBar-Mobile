import Charts
import CodexBarSync
import SwiftUI

/// Displays subscription utilization history as a capsule bar chart (V4 style).
///
/// Layout rules (matching Cost daily chart behavior):
/// - Fixed visible window of 30 bar positions
/// - Data right-aligned: sparse data shows on the right, left is empty
/// - When data > 30: horizontal scrolling enabled, default to rightmost
/// - Each bar = one reset window (session=5h, weekly=7d)
struct UtilizationHistoryView: View {
    let series: [SyncUtilizationSeries]
    let tintColor: Color

    @State private var selectedSeriesIndex = 0
    @State private var selectedIndex: Int?

    /// Cache (rawPoints, displayPoints, hasData) keyed on `identityKey`. Invalidated via
    /// synchronous check in body + `.onChange(initial: true)` — see body for rationale.
    @State private var cachedKey: String = ""
    @State private var cachedRawPoints: [DisplayPoint] = []
    @State private var cachedDisplayPoints: [DisplayPoint] = []
    @State private var cachedHasData = false

    private var activeSeries: SyncUtilizationSeries? {
        let index = min(self.selectedSeriesIndex, self.series.count - 1)
        guard index >= 0, index < self.series.count else { return nil }
        return self.series[index]
    }

    private let trackColor = Color.primary.opacity(0.06)
    /// Bar width in points. Chosen with `windowSize` so the chart's visible
    /// area fits ~30 bars + inter-bar padding on a 390pt iPhone screen.
    /// Changing this without `windowSize` re-tuning can make labels overlap
    /// or leave excessive empty padding.
    private let barWidth: CGFloat = 10
    /// Fixed visible window size — matches Cost chart's ~30 bars per screen.
    /// Also constrains `dateFormat` below to `"M/d"` compact format so labels
    /// fit beneath narrow bars.
    private let windowSize = 30

    /// Identity key for the active series. Cheap O(1) — fixed number of string
    /// interpolations regardless of entry count. This property is the `.task(id:)` key
    /// and gets recomputed on every render, including during chart hover/drag where
    /// `selectedIndex` state changes every frame. O(entry-count) serialization in this
    /// hot path would negate the caching win.
    ///
    /// Correctness relies on the same data-flow guarantee as
    /// `UtilizationAggregateView.identityKey` — see that method's comment. Summary:
    /// upstream always bumps the owning provider's `lastUpdated` when utilization
    /// changes, and the latest-captured timestamp on the active series also bumps
    /// when new entries arrive. Together they give sufficient invalidation without
    /// touching every entry.
    static func identityKey(series: [SyncUtilizationSeries], selectedSeriesIndex: Int) -> String {
        let idx = max(0, min(selectedSeriesIndex, series.count - 1))
        guard idx >= 0, idx < series.count else {
            return "empty"
        }
        let active = series[idx]
        let latestCaptured = active.entries.last?.capturedAt.timeIntervalSince1970 ?? 0
        let latestReset = active.entries.last?.resetsAt?.timeIntervalSince1970 ?? -1
        return "\(idx)|\(active.name)|\(active.windowMinutes)|c=\(active.entries.count)|lc=\(latestCaptured)|lr=\(latestReset)"
    }

    private var identityKey: String {
        Self.identityKey(series: self.series, selectedSeriesIndex: self.selectedSeriesIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscription Utilization")
                .font(.headline)

            if self.series.count > 1 {
                Picker("Series", selection: self.$selectedSeriesIndex) {
                    ForEach(Array(self.series.enumerated()), id: \.offset) { index, s in
                        Text(Self.seriesDisplayName(s)).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: self.selectedSeriesIndex) { _, _ in
                    self.selectedIndex = nil
                }
            }

            self.resolvedContent()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: self.identityKey, initial: true) { _, newKey in
            guard self.cachedKey != newKey else { return }
            self.cachedKey = newKey
            guard let active = self.activeSeries else {
                self.cachedRawPoints = []
                self.cachedDisplayPoints = []
                self.cachedHasData = false
                return
            }
            let raw = Self.buildPeriodPoints(from: active)
            if raw.isEmpty {
                self.cachedRawPoints = []
                self.cachedDisplayPoints = []
                self.cachedHasData = false
            } else {
                self.cachedRawPoints = raw
                self.cachedDisplayPoints = Self.rightAlignPoints(raw, windowSize: self.windowSize)
                self.cachedHasData = true
            }
        }
    }

    /// Resolves cached points synchronously on cache miss. Keeps the chart populated on
    /// the very first frame — fixes the right-edge clip regression that appeared when
    /// `.task(id:)` left cached arrays empty during first render and `ScrollableIfNeeded`
    /// locked in the wrong `dataCount`.
    private func resolvedPoints() -> (raw: [DisplayPoint], display: [DisplayPoint], hasData: Bool) {
        if self.cachedKey == self.identityKey {
            return (self.cachedRawPoints, self.cachedDisplayPoints, self.cachedHasData)
        }
        guard let active = self.activeSeries else { return ([], [], false) }
        let computed = Self.buildPeriodPoints(from: active)
        if computed.isEmpty { return ([], [], false) }
        let display = Self.rightAlignPoints(computed, windowSize: self.windowSize)
        return (computed, display, true)
    }

    @ViewBuilder
    private func resolvedContent() -> some View {
        let resolved = self.resolvedPoints()
        if resolved.hasData {
            self.capsuleChart(resolved.display, dataCount: resolved.raw.count)
                .frame(height: 140)
            self.detailLine(resolved.display)
                .frame(height: 16)
        } else {
            self.emptyState
        }
    }

    private var emptyState: some View {
        Text("No utilization data yet. Keep CodexBar running on your Mac to start recording.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }

    // MARK: - Data Processing

    struct DisplayPoint: Identifiable {
        let id: Int
        let date: Date?
        let usedPercent: Double
        let isObserved: Bool
        /// True for padding slots (no data, just spacing)
        let isPadding: Bool
    }

    /// Groups raw entries into period-aligned points.
    static func buildPeriodPoints(from series: SyncUtilizationSeries) -> [DisplayPoint] {
        guard !series.entries.isEmpty, series.windowMinutes > 0 else { return [] }

        let windowSeconds = Double(series.windowMinutes) * 60
        let validEntries = series.entries.filter {
            $0.capturedAt.timeIntervalSince1970.isFinite
                && $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                && ($0.resetsAt?.timeIntervalSince1970.isFinite ?? true)
        }
        let latestReset = validEntries.compactMap(\.resetsAt).max()

        var bestByPeriod: [Int: (date: Date, usedPercent: Double)] = [:]

        for entry in validEntries {
            let boundary: Date
            if let reset = entry.resetsAt ?? latestReset {
                let diff = reset.timeIntervalSince(entry.capturedAt)
                guard let periodIndex = Int(exactly: floor(diff / windowSeconds)) else { continue }
                boundary = reset.addingTimeInterval(-Double(periodIndex) * windowSeconds)
            } else {
                let epoch = entry.capturedAt.timeIntervalSince1970
                let slot = floor(epoch / windowSeconds) * windowSeconds
                boundary = Date(timeIntervalSince1970: slot)
            }

            guard let periodKey = Int(exactly: (boundary.timeIntervalSince1970 / windowSeconds).rounded(.towardZero))
            else { continue }

            if let existing = bestByPeriod[periodKey] {
                if entry.usedPercent > existing.usedPercent {
                    bestByPeriod[periodKey] = (date: boundary, usedPercent: entry.usedPercent)
                }
            } else {
                bestByPeriod[periodKey] = (date: boundary, usedPercent: entry.usedPercent)
            }
        }

        guard !bestByPeriod.isEmpty else { return [] }

        let sortedKeys = bestByPeriod.keys.sorted()
        let minKey = sortedKeys.first!
        let maxKey = sortedKeys.last!

        var points: [DisplayPoint] = []
        var idx = 0

        // Bound gap expansion before allocating. A corrupt timestamp must not
        // create billions of padding points only to discard them afterwards.
        let (lastWindowStart, overflow) = maxKey.subtractingReportingOverflow(89)
        let firstVisibleKey = overflow ? minKey : max(minKey, lastWindowStart)
        for key in firstVisibleKey...maxKey {
            if let observed = bestByPeriod[key] {
                points.append(DisplayPoint(
                    id: idx, date: observed.date,
                    usedPercent: min(100, max(0, observed.usedPercent)),
                    isObserved: true, isPadding: false))
            } else {
                let gapDate = Date(timeIntervalSince1970: Double(key) * windowSeconds)
                points.append(DisplayPoint(
                    id: idx, date: gapDate,
                    usedPercent: 0, isObserved: false, isPadding: false))
            }
            idx += 1
        }

        // Keep last 90 points max for scrolling
        if points.count > 90 {
            points = Array(points.suffix(90))
            for i in points.indices {
                points[i] = DisplayPoint(
                    id: i, date: points[i].date,
                    usedPercent: points[i].usedPercent,
                    isObserved: points[i].isObserved, isPadding: false)
            }
        }

        return points
    }

    /// Right-aligns data: if fewer than windowSize points, pad left with empty slots.
    /// Result always has at least windowSize items (or more for scrollable).
    private static func rightAlignPoints(_ data: [DisplayPoint], windowSize: Int) -> [DisplayPoint] {
        if data.count >= windowSize {
            return data // Enough data, scrolling handles the rest
        }

        // Pad left with empty slots
        let paddingCount = windowSize - data.count
        var result: [DisplayPoint] = []

        for i in 0..<paddingCount {
            result.append(DisplayPoint(
                id: i, date: nil,
                usedPercent: 0, isObserved: false, isPadding: true))
        }

        for (offset, point) in data.enumerated() {
            result.append(DisplayPoint(
                id: paddingCount + offset, date: point.date,
                usedPercent: point.usedPercent,
                isObserved: point.isObserved, isPadding: false))
        }

        return result
    }

    // MARK: - Chart

    private func capsuleChart(_ points: [DisplayPoint], dataCount: Int) -> some View {
        Chart {
            ForEach(points) { point in
                if !point.isPadding {
                    // Track
                    BarMark(
                        x: .value("I", point.id),
                        yStart: .value("S", 0),
                        yEnd: .value("E", 100),
                        width: .fixed(self.barWidth))
                        .foregroundStyle(self.trackColor)
                        .cornerRadius(5)

                    // Fill
                    BarMark(
                        x: .value("I", point.id),
                        yStart: .value("S", 0),
                        yEnd: .value("E", point.usedPercent),
                        width: .fixed(self.barWidth))
                        .foregroundStyle(point.isObserved ? self.tintColor : self.tintColor.opacity(0.2))
                        .cornerRadius(5)
                }
            }

            if let si = self.selectedIndex, si >= 0, si < points.count, !points[si].isPadding {
                RuleMark(x: .value("S", si))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        // Widen the trailing edge by 1 slot so the rightmost bar + label get
        // fully painted when the chart is scrolled to the right edge (fixed-width
        // BarMarks clip at the chartXVisibleDomain boundary otherwise).
        .chartXScale(domain: 0...max(points.count, self.windowSize))
        .chartXAxis {
            // `desiredCount: 4` → ~4 date labels across 30 bars. Lower
            // (2-3) feels sparse on a 10pt-bar chart; higher (5+) crowds
            // the `"M/d"` labels into each other at the narrow card width.
            // Paired with the compact-format axisLabel below.
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let idx = value.as(Int.self), idx >= 0, idx < points.count,
                       let date = points[idx].date
                    {
                        Text(Self.axisLabel(for: date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .modifier(ScrollableIfNeeded(
            dataCount: dataCount,
            windowSize: self.windowSize,
            totalPoints: points.count))
        .chartXSelection(value: self.$selectedIndex)
    }

    // MARK: - Detail Line

    @ViewBuilder
    private func detailLine(_ points: [DisplayPoint]) -> some View {
        if let si = self.selectedIndex, si >= 0, si < points.count, !points[si].isPadding {
            let point = points[si]
            HStack {
                if let date = point.date {
                    Text(Self.fullDateLabel(date))
                }
                if !point.isObserved {
                    Text("(no data)").foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(format: "%.0f%% used", point.usedPercent))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            let observed = points.filter(\.isObserved)
            let avg = observed.reduce(0.0) { $0 + $1.usedPercent } / Double(max(observed.count, 1))
            HStack {
                Text(String(format: String(localized: "%d data points"), observed.count))
                Spacer()
                Text(String(format: String(localized: "Avg") + " %.0f%%", avg))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private static func seriesDisplayName(_ series: SyncUtilizationSeries) -> String {
        switch series.name {
        case "session": String(localized: "Session")
        case "weekly": String(localized: "Weekly")
        case "opus": String(localized: "Opus")
        default: series.name.capitalized
        }
    }

    private static func axisLabel(for date: Date) -> String {
        // **Intentionally locale-free compact numeric format.**
        // Bars are 10pt wide; labels need to read as `"4/23"` in every
        // interface language. `setLocalizedDateFormatFromTemplate("Md")`
        // yields `"4月23日"` in Simplified Chinese — three CJK glyphs —
        // which overflows the narrow bar spacing. Do NOT "localize" this
        // without first solving the layout constraint. See Build 84
        // revert in CHANGELOG for full context.
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private static func fullDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Conditional Scroll Modifier

private struct ScrollableIfNeeded: ViewModifier {
    let dataCount: Int
    let windowSize: Int
    let totalPoints: Int

    func body(content: Content) -> some View {
        if self.dataCount > self.windowSize {
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: self.windowSize)
                .chartScrollPosition(initialX: self.totalPoints - self.windowSize)
        } else {
            content
        }
    }
}
