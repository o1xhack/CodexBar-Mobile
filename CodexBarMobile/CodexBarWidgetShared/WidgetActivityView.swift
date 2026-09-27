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
            let inset: CGFloat = 16
            let width = max(0, geometry.size.width - inset * 2)
            let height = max(0, geometry.size.height - inset * 2)
            let panelGap: CGFloat = self.family == .systemExtraLarge ? 6 : 8
            let panelHeight = self.isComparison ? max(0, (height - panelGap) / 2) : height
            let weeks = WidgetActivityLayout.weeks(for: self.family)
            Group {
                if self.isComparison {
                    VStack(alignment: .leading, spacing: panelGap) {
                        self.panel(for: self.entry.sourceIDs.first ?? "all", weeks: weeks, width: width, height: panelHeight)
                        self.secondPanel(weeks: weeks, width: width, height: panelHeight)
                    }
                } else {
                    self.panel(
                        for: self.entry.sourceIDs.first ?? "all",
                        weeks: weeks,
                        width: width,
                        height: panelHeight,
                        compact: self.family == .systemSmall)
                }
            }
            .frame(width: width, height: height, alignment: .center)
            .padding(.horizontal, inset)
            .padding(.vertical, inset)
        }
    }

    @ViewBuilder
    private func secondPanel(weeks: Int, width: CGFloat, height: CGFloat) -> some View {
        let first = self.entry.sourceIDs.first ?? "all"
        let second = self.entry.sourceIDs.dropFirst().first ?? "all"
        if first == second {
            self.panelMessage(String(localized: "Choose a different source"))
        } else {
            self.panel(for: second, weeks: weeks, width: width, height: height)
        }
    }

    @ViewBuilder
    private func panel(for id: String, weeks: Int, width: CGFloat, height: CGFloat, compact: Bool = false) -> some View {
        if let source = self.entry.projection.source(id: id) {
            let columnSpacing = WidgetActivityLayout.columnSpacing(for: self.family)
            let cellSize = WidgetActivityLayout.cellSize(
                width: width, weeks: weeks, compact: compact, spacing: columnSpacing)
            let columns = compact ? 7 : weeks
            let gridWidth = CGFloat(columns) * cellSize + CGFloat(columns - 1) * columnSpacing
            let titleGap: CGFloat = self.family == .systemExtraLarge ? 4 : 6
            let rowSpacing = WidgetActivityLayout.rowSpacing(
                family: self.family, cellSize: cellSize, panelHeight: height, titleGap: titleGap)
            let color = ProviderColorPalette.color(for: id, tintHex: source.tintHex)
            VStack(alignment: .leading, spacing: titleGap) {
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
                    columnSpacing: columnSpacing,
                    rowSpacing: rowSpacing,
                    color: color,
                    compact: compact)
                    .frame(width: gridWidth, alignment: .leading)
            }
            .frame(width: gridWidth, height: height, alignment: .center)
            .frame(width: width, height: height, alignment: .center)
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
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
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
        let dates: [Date] = if self.compact {
            WidgetActivityWindow.compactDates(weeks: self.weeks, referenceDate: self.referenceDate, calendar: calendar)
        } else {
            (0..<7).flatMap { weekday in
                (0..<self.weeks).compactMap { week in
                    calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstWeek)
                }
            }
        }
        return dates.map { date -> (key: String, day: WidgetActivityDay?, isFuture: Bool) in
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
            return (key, byKey[key], date > today)
        }
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(self.cellSize), spacing: self.columnSpacing),
                count: self.compact ? 7 : self.weeks),
            alignment: .leading,
            spacing: self.rowSpacing)
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
    static func columnSpacing(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? 5 : 4.5
    }

    static func weeks(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 5
        case .systemMedium: 24
        case .systemLarge: 18
        case .systemExtraLarge: 38
        default: 27
        }
    }

    static func cellSize(width: CGFloat, weeks: Int, compact: Bool, spacing: CGFloat) -> CGFloat {
        let columns = compact ? 7 : weeks
        let available = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        return max(4, compact ? min(14, available) : available)
    }

    static func rowSpacing(family: WidgetFamily, cellSize: CGFloat, panelHeight: CGFloat, titleGap: CGFloat) -> CGFloat {
        if family == .systemSmall { return 5 }
        let titleHeight: CGFloat = 20
        let needed = (panelHeight - titleHeight - titleGap - 7 * cellSize) / 6
        return min(7.5, max(4.5, needed))
    }
}

enum WidgetActivityWindow {
    static func compactDates(weeks: Int, referenceDate: Date, calendar: Calendar) -> [Date] {
        guard weeks > 0 else { return [] }
        let today = calendar.startOfDay(for: referenceDate)
        let count = weeks * 7
        guard let first = calendar.date(byAdding: .day, value: 1 - count, to: today) else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

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
