import SwiftUI
import WidgetKit

struct WidgetActivityView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: WidgetActivityEntry
    var previewFamily: WidgetFamily?

    private var family: WidgetFamily {
        self.previewFamily ?? self.environmentFamily
    }

    private var isComparison: Bool {
        self.family == .systemLarge || self.family == .systemExtraLarge
    }

    private var activityStatus: String? {
        if self.entry.projection.state == .error { return String(localized: "Sync Error") }
        if self.entry.projection.state == .syncing { return String(localized: "Syncing") }
        if self.entry.projection.isStale { return String(localized: "Stale") }
        return nil
    }

    var body: some View {
        Group {
            switch self.entry.projection.state {
            case .loaded:
                self.loadedView
            case .syncing:
                if self.entry.projection.sources.isEmpty {
                    self.stateView(String(localized: "Open CodexBar to refresh token history."))
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

    private var loadedView: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 11
            let width = max(0, geometry.size.width - inset * 2)
            let weeks = WidgetActivityLayout.weeks(for: self.family)
            Group {
                if self.isComparison {
                    VStack(alignment: .leading, spacing: self.family == .systemLarge ? 8 : 6) {
                        self.panel(for: self.entry.sourceIDs.first ?? "all", weeks: weeks, width: width)
                        self.secondPanel(weeks: weeks, width: width)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    self.panel(
                        for: self.entry.sourceIDs.first ?? "all",
                        weeks: weeks,
                        width: width,
                        compact: self.family == .systemSmall)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, inset)
            .padding(.vertical, self.family == .systemExtraLarge ? 9 : 11)
        }
    }

    @ViewBuilder
    private func secondPanel(weeks: Int, width: CGFloat) -> some View {
        let first = self.entry.sourceIDs.first ?? "all"
        let second = self.entry.sourceIDs.dropFirst().first ?? "all"
        if first == second {
            self.panelMessage(String(localized: "Choose a different source"))
        } else {
            self.panel(for: second, weeks: weeks, width: width)
        }
    }

    @ViewBuilder
    private func panel(for id: String, weeks: Int, width: CGFloat, compact: Bool = false) -> some View {
        if let source = self.entry.projection.source(id: id) {
            let cellSize = WidgetActivityLayout.cellSize(width: width, weeks: weeks, compact: compact)
            let color = ProviderColorPalette.color(for: id, tintHex: source.tintHex)
            VStack(alignment: .leading, spacing: compact ? 7 : 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(id == WidgetActivityProjection.allSourceID ? String(localized: "All") : source.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if let activityStatus = self.activityStatus {
                        Text(activityStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                WidgetActivityGrid(
                    source: source,
                    weeks: weeks,
                    referenceDate: self.entry.date,
                    cellSize: cellSize,
                    color: color,
                    compact: compact)
                    .frame(width: width, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
        } else {
            self.panelMessage(String(localized: "Source unavailable"))
        }
    }

    private func panelMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
    let color: Color
    var compact = false

    private var cells: [(key: String, day: WidgetActivityDay?, isFuture: Bool)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: self.referenceDate)
        guard let firstWeek = WidgetActivityWindow.startDate(
            weeks: self.weeks, referenceDate: self.referenceDate, calendar: calendar)
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
            columns: Array(
                repeating: GridItem(.fixed(self.cellSize), spacing: WidgetActivityLayout.cellSpacing),
                count: self.compact ? 7 : self.weeks),
            alignment: .leading,
            spacing: WidgetActivityLayout.cellSpacing)
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
        let fill: Color = if tokens == nil {
            .secondary.opacity(0.06)
        } else if tokens == 0 {
            .secondary.opacity(0.14)
        } else if self.renderingMode == .accented {
            .primary.opacity(day?.intensity ?? 0.25)
        } else {
            self.color.opacity(day?.intensity ?? 0.25)
        }
        return RoundedRectangle(cornerRadius: 2)
            .fill(fill)
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

enum WidgetActivityLayout {
    static let cellSpacing: CGFloat = 2

    static func weeks(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 5
        case .systemMedium: 27
        case .systemLarge: 18
        case .systemExtraLarge: 38
        default: 27
        }
    }

    static func cellSize(width: CGFloat, weeks: Int, compact: Bool) -> CGFloat {
        let columns = compact ? 7 : weeks
        return max(4, (width - CGFloat(columns - 1) * self.cellSpacing) / CGFloat(columns))
    }
}

enum WidgetActivityWindow {
    static func startDate(weeks: Int, referenceDate: Date, calendar baseCalendar: Calendar) -> Date? {
        guard weeks > 0 else { return nil }
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: referenceDate)
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return nil }
        return calendar.date(byAdding: .weekOfYear, value: 1 - weeks, to: currentWeek)
    }

    static func activeDayCount(
        source: WidgetActivitySource,
        weeks: Int,
        referenceDate: Date,
        calendar: Calendar = .current) -> Int
    {
        guard let firstDay = self.startDate(weeks: weeks, referenceDate: referenceDate, calendar: calendar)
        else { return 0 }
        let firstKey = self.dayKey(firstDay, calendar: calendar)
        let lastKey = self.dayKey(referenceDate, calendar: calendar)
        return source.days.count { day in
            day.key >= firstKey && day.key <= lastKey && (day.tokens ?? 0) > 0
        }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
