import SwiftUI
import WidgetKit

struct WidgetActivityView: View {
    @Environment(\.widgetFamily) private var environmentFamily

    let entry: WidgetActivityEntry
    var previewFamily: WidgetFamily?

    private var family: WidgetFamily { self.previewFamily ?? self.environmentFamily }
    private var isComparison: Bool {
        self.family == .systemLarge || self.family == .systemExtraLarge
    }

    var body: some View {
        Group {
            switch self.entry.projection.state {
            case .loaded:
                self.loadedView
            case .syncing:
                if self.entry.projection.sources.isEmpty {
                    self.stateView(String(localized: "Preparing token history…"))
                } else {
                    self.loadedView
                }
            case .noData:
                self.stateView(String(localized: "Token history is unavailable."))
            case .error:
                if self.entry.projection.sources.isEmpty {
                    self.stateView(String(localized: "Could not load token history. Please try again."))
                } else {
                    self.loadedView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        .widgetURL(URL(string: "codexbar://token-activity"))
    }

    @ViewBuilder
    private var loadedView: some View {
        if self.isComparison {
            if self.family == .systemExtraLarge {
                GeometryReader { geometry in
                    let panelWidth = (geometry.size.width - 61) / 2
                    let cellSize = min(14, max(7, floor((panelWidth - 57) / 20)))
                    HStack(alignment: .center, spacing: 20) {
                        self.panel(for: self.entry.sourceIDs.first ?? "all", weeks: 20, cellSize: cellSize)
                        Rectangle().fill(.primary.opacity(0.10)).frame(width: 1, height: 150)
                        self.secondPanel(weeks: 20, cellSize: cellSize)
                    }
                    .padding(20)
                    .frame(maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    self.panel(for: self.entry.sourceIDs.first ?? "all", weeks: 12)
                    Rectangle().fill(.primary.opacity(0.10)).frame(height: 1)
                    self.secondPanel(weeks: 12)
                }
                .padding(17)
            }
        } else {
            let weeks = self.family == .systemSmall ? 5 : 12
            if self.family == .systemSmall {
                self.panel(for: self.entry.sourceIDs.first ?? "all", weeks: weeks)
                    .padding(13)
            } else {
                self.mediumPanel(for: self.entry.sourceIDs.first ?? "all", weeks: weeks)
                    .padding(17)
            }
        }
    }

    @ViewBuilder
    private func mediumPanel(for id: String, weeks: Int) -> some View {
        if let source = self.entry.projection.source(id: id) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(id == WidgetActivityProjection.allSourceID ? String(localized: "All") : source.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(self.summary(for: source, weeks: weeks))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(self.dateRange(for: weeks))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if self.entry.projection.isStale {
                        Text(String(localized: "Stale"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if self.entry.projection.state == .error {
                        Text(String(localized: "Sync Error"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if self.entry.projection.state == .syncing {
                        Text(String(localized: "Syncing"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 88, alignment: .leading)
                WidgetActivityGrid(source: source, weeks: weeks, referenceDate: self.entry.date, cellSize: 13)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            self.stateView(String(localized: "Source unavailable"))
        }
    }

    @ViewBuilder
    private func secondPanel(weeks: Int, cellSize: CGFloat? = nil) -> some View {
        let first = self.entry.sourceIDs.first ?? "all"
        let second = self.entry.sourceIDs.dropFirst().first ?? "all"
        if first == second {
            self.stateView(String(localized: "Choose a different source"))
        } else {
            self.panel(for: second, weeks: weeks, cellSize: cellSize)
        }
    }

    @ViewBuilder
    private func panel(for id: String, weeks: Int, cellSize: CGFloat? = nil) -> some View {
        if let source = self.entry.projection.source(id: id) {
            VStack(alignment: .leading, spacing: self.family == .systemSmall ? 8 : 10) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(id == WidgetActivityProjection.allSourceID ? String(localized: "All") : source.name)
                        .font(self.family == .systemSmall ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if self.entry.projection.isStale {
                        Text(String(localized: "Stale"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if self.entry.projection.state == .error {
                        Text(String(localized: "Sync Error"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if self.entry.projection.state == .syncing {
                        Text(String(localized: "Syncing"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                WidgetActivityGrid(
                    source: source,
                    weeks: weeks,
                    referenceDate: self.entry.date,
                    cellSize: cellSize ?? (self.family == .systemSmall ? 14 : 11),
                    compact: self.family == .systemSmall)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 4) {
                    Text(self.summary(for: source, weeks: weeks))
                        .lineLimit(1)
                    if self.family != .systemSmall {
                        Spacer(minLength: 0)
                        Text(self.dateRange(for: weeks))
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            self.stateView(String(localized: "Source unavailable"))
        }
    }

    private func summary(for source: WidgetActivitySource, weeks: Int) -> String {
        let recent = source.days.suffix(weeks * 7)
        let active = recent.count { ($0.tokens ?? 0) > 0 }
        return "\(active) " + String(localized: "Active Days")
    }

    private func dateRange(for weeks: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: self.entry.date)
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let firstWeek = calendar.date(byAdding: .weekOfYear, value: 1 - weeks, to: currentWeek)
        else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        let firstMonth = formatter.string(from: firstWeek)
        let lastMonth = formatter.string(from: today)
        return firstMonth == lastMonth ? firstMonth : firstMonth + "–" + lastMonth
    }

    private func stateView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(String(localized: "Token Activity"))
                .font(.headline)
            Spacer(minLength: 0)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}

private struct WidgetActivityGrid: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let source: WidgetActivitySource
    let weeks: Int
    let referenceDate: Date
    let cellSize: CGFloat
    var compact = false

    private var cells: [(key: String, day: WidgetActivityDay?, isFuture: Bool)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: self.referenceDate)
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let firstWeek = calendar.date(byAdding: .weekOfYear, value: 1 - self.weeks, to: currentWeek)
        else { return [] }
        let byKey = Dictionary(uniqueKeysWithValues: self.source.days.map { ($0.key, $0) })
        let positions: [(Int, Int)] = if self.compact {
            (0..<self.weeks).flatMap { week in (0..<7).map { (week, $0) } }
        } else {
            (0..<7).flatMap { weekday in (0..<self.weeks).map { ($0, weekday) } }
        }
        return positions.compactMap { week, weekday -> (key: String, day: WidgetActivityDay?, isFuture: Bool)? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstWeek) else {
                    return nil
                }
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                let key = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
                return (key, byKey[key], date > today)
        }
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(self.cellSize), spacing: 3), count: self.compact ? 7 : self.weeks),
            spacing: 3)
        {
            ForEach(Array(self.cells.enumerated()), id: \.offset) { _, cell in
                self.cell(cell.day, isFuture: cell.isFuture)
                    .accessibilityLabel(self.accessibilityLabel(for: cell.key, day: cell.day))
                    .accessibilityHidden(cell.isFuture)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func cell(_ day: WidgetActivityDay?, isFuture: Bool) -> some View {
        let tokens = day?.tokens
        let unknown = tokens == nil || day?.isLowerBound == true
        let fill: Color = if tokens == nil {
            .clear
        } else if tokens == 0 {
            .secondary.opacity(0.11)
        } else if self.renderingMode == .accented {
            .primary.opacity(0.24 + (day?.intensity ?? 0) * 0.72)
        } else {
            .accentColor.opacity(0.24 + (day?.intensity ?? 0) * 0.72)
        }
        return RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        Color.secondary.opacity(unknown ? 0.45 : 0),
                        style: StrokeStyle(lineWidth: 1, dash: unknown ? [2] : []))
            }
            .frame(width: self.cellSize, height: self.cellSize)
            .opacity(isFuture ? 0 : 1)
            .widgetAccentable(tokens != nil && tokens != 0)
    }

    private func accessibilityLabel(for key: String, day: WidgetActivityDay?) -> String {
        guard let tokens = day?.tokens else {
            return key + ", " + String(localized: "Unavailable")
        }
        let prefix = day?.isLowerBound == true ? "≥" : ""
        return key + ", " + prefix + tokens.formatted() + " " + String(localized: "Tokens")
    }
}
