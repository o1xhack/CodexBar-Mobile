import CodexBarSync
import SwiftUI

/// A shared token-only surface. Cost and Usage use the same history worker and reducer.
struct TokenActivitySection: View {
    let providers: [ProviderUsageSnapshot]
    var sourceSnapshots: [SyncedUsageSnapshot] = []
    var isOverview = false
    var isDemoMode = false
    var referenceDate = Date()
    @AppStorage(MobileSettingsKeys.cwlEnabled) private var useLedger = MobileSettingsDefaults.cwlEnabled
    @AppStorage(MobileSettingsKeys.cwlBlobSeedClearedAt) private var clearedAt: Double = 0
    @State private var series: [TokenActivitySeries] = []
    @State private var overviewDay: String?
    @State private var failed = false
    @State private var loadedScope: String?
    private var scope: String {
        self.providers
            .map {
                $0.cardIdentityKey + CostLedgerService.accountIdentityKeys(for: $0).sorted().joined(separator: ",")
                    + "+" + ($0.sourceReport?.absorbedAccountIdentities ?? []).joined(separator: ",")
            }
            .joined(separator: "|")
            + "|\(self.useLedger)|\(self.isDemoMode)|\(self.clearedAt)|\(TimeZone.current.identifier)"
            + self.sourceSnapshots.compactMap(\.deviceID).sorted().joined(separator: "|")
    }

    private var refreshKey: String {
        self.scope + self.providers.map { "\($0.lastUpdated.timeIntervalSince1970)" }.joined(separator: "|")
            + self.sourceSnapshots.map { "\($0.deviceID ?? ""):\($0.syncTimestamp.timeIntervalSince1970)" }.joined()
            + TokenActivity.sourceRevision(self.sourceSnapshots)
            + TokenActivity.dayRevision(
                providers: self.providers, snapshots: self.sourceSnapshots, referenceDate: self.referenceDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if self.loadedScope == self.scope, !self.series.isEmpty {
                if self.isOverview {
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink {
                            ScrollView {
                                TokenActivityCharts(
                                    series: self.series,
                                    isOverview: true,
                                    referenceDate: self.referenceDate,
                                    failed: self.failed)
                                    .padding()
                            }
                            .navigationTitle(String(localized: "Token Activity"))
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Daily Tokens Overview")).font(.headline)
                                    Text(TokenActivity.total(self.series).text)
                                        .font(.title2.bold().monospacedDigit())
                                        .accessibilityIdentifier("token-overview-total")
                                    Text(String(localized: "Past year · All providers"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary).accessibilityHidden(true)
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("token-overview-link")
                        ScrollView(.horizontal) {
                            TokenActivityGrid(
                                series: self.series,
                                color: .blue,
                                label: String(localized: "Daily Tokens Overview"),
                                referenceDate: self.referenceDate,
                                selectedDay: self.$overviewDay)
                        }
                        .defaultScrollAnchor(.trailing)
                        .accessibilityIdentifier("token-overview-heatmap")
                        if let overviewDay {
                            Text(overviewDay + " · " + TokenActivity.total(self.series, dayKey: overviewDay).text)
                                .font(.subheadline.monospacedDigit())
                        }
                        Text(String(localized: "Colors show relative daily activity over the past year."))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    TokenActivityCharts(
                        series: self.series,
                        isOverview: false,
                        referenceDate: self.referenceDate,
                        failed: self.failed)
                }
            } else if self.failed {
                Text(String(localized: "Could not load token history. Please try again."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: self.refreshKey) {
            let requestedScope = self.scope
            do {
                let result: [TokenActivitySeries] = if self.useLedger, !self.isDemoMode {
                    try await CostHistoryWorker.shared.tokenActivity(
                        providers: self.providers,
                        sourceSnapshots: self.sourceSnapshots,
                        referenceDate: self.referenceDate)
                } else {
                    try await CostHistoryWorker.shared.snapshotTokenActivity(
                        providers: self.providers, referenceDate: self.referenceDate)
                }
                guard !Task.isCancelled else { return }
                self.series = result
                self.loadedScope = requestedScope
                self.failed = false
            } catch {
                guard !Task.isCancelled else { return }
                self.failed = true
            }
        }
    }
}

private struct TokenActivityCharts: View {
    @Environment(\.mobileAdaptiveLayout) private var layout
    let series: [TokenActivitySeries]
    let isOverview: Bool
    let referenceDate: Date
    let failed: Bool
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var hasSelection = false
    private var selectedDay: String? {
        self.hasSelection ? TokenActivity.dayKey(self.selectedDate, calendar: Calendar(identifier: .gregorian)) : nil
    }

    private var daySelection: Binding<String?> {
        Binding(get: { self.selectedDay }, set: { key in
            guard let key else { return }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: key) else { return }
            self.selectedDate = date
            self.hasSelection = true
        })
    }

    private func title(for item: TokenActivitySeries) -> String {
        if self.series.count(where: { $0.provider.providerID == item.provider.providerID }) > 1,
           let email = item.provider.accountEmail
        {
            return item.provider.providerName + " · " + email
        }
        return item.provider.providerName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(self
                .isOverview ? String(localized: "Daily Tokens Overview") : String(localized: "Token Activity"))
                .font(.headline)
            Text(String(localized: "Past year · Swipe to explore. Missing history is not zero."))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "Recorded tokens") + ": " + TokenActivity.total(self.series).text)
                .font(.subheadline.monospacedDigit())
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 20),
                    count: self.isOverview && self.layout.usesTwoColumns ? 2 : 1),
                alignment: .leading,
                spacing: 20)
            {
                ForEach(self.series) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        if self.isOverview {
                            Text(self.title(for: item))
                                .font(.title3.bold())
                                .foregroundStyle(ProviderColorPalette.color(for: item.provider))
                        }
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                TokenActivityGrid(
                                    series: [item],
                                    color: ProviderColorPalette.color(for: item.provider),
                                    label: self.title(for: item),
                                    referenceDate: self.referenceDate,
                                    selectedDay: self.daySelection)
                                    .id(item.id)
                            }
                            .defaultScrollAnchor(.trailing)
                            Button(String(localized: "Back to today")) {
                                proxy.scrollTo(item.id, anchor: .trailing)
                            }.font(.caption)
                        }
                    }
                }
            }
            Text(String(localized: "Colors show relative daily activity over the past year."))
                .font(.caption2).foregroundStyle(.secondary)
            DatePicker(
                String(localized: "Date"),
                selection: self.$selectedDate,
                in: Calendar.current.date(byAdding: .day, value: -364, to: self.referenceDate)!...self
                    .referenceDate,
                displayedComponents: .date)
                .accessibilityIdentifier("token-date-picker")
                .onChange(of: self.selectedDate) { self.hasSelection = true }
            if let selectedDay {
                Text(selectedDay).font(.subheadline.bold()).accessibilityIdentifier("selected-token-day")
                if self.isOverview {
                    Text(String(localized: "Recorded tokens") + ": " + TokenActivity.total(
                        self.series, dayKey: selectedDay).text)
                        .font(.subheadline.monospacedDigit())
                }
                ForEach(self.series) { item in
                    HStack {
                        Text(self.title(for: item))
                        Spacer()
                        Text(TokenActivity.tokenText(
                            item.days.first { $0.dayKey == selectedDay },
                            series: item))
                            .monospacedDigit()
                    }.font(.caption)
                    if let names = item.days.first(where: { $0.dayKey == selectedDay })?.modelsUsed,
                       !names.isEmpty
                    {
                        Text(String(localized: "Observed models") + ": " + names.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("token-observed-models")
                    }
                }
            }
            if self.failed {
                Text(String(localized: "Could not refresh token history. Showing the last loaded data."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TokenActivityGrid: View {
    let series: [TokenActivitySeries]
    let color: Color
    let label: String
    let referenceDate: Date
    @Binding var selectedDay: String?
    @ScaledMetric(relativeTo: .caption2) private var calendarLabelHeight: CGFloat = 16
    private var gridHeight: CGFloat {
        120 + 2 * self.calendarLabelHeight
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }

    private var dates: [Date] {
        let start = TokenActivity.window(referenceDate: self.referenceDate, calendar: self.calendar).lowerBound
        let weekStart = self.calendar.dateInterval(of: .weekOfYear, for: start)!.start
        return (0..<371).compactMap { self.calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        let gridDates = self.dates
        let points = TokenActivity.dailyTotals(self.series)
        let scale = TokenActivityColorScale(values: points.values.compactMap(\.value))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(stride(from: 0, to: gridDates.count, by: 7)), id: \.self) { index in
                    let date = gridDates[index]
                    Text(self.calendar.component(.day, from: date) <= 7 ? date
                        .formatted(.dateTime.month(.abbreviated)) : "")
                        .font(.caption2).fixedSize().frame(
                            width: 12, alignment: index >= gridDates.count - 21 ? .trailing : .leading)
                }
            }
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7), spacing: 4) {
                ForEach(gridDates, id: \.self) { date in
                    let key = TokenActivity.dayKey(date, calendar: self.calendar)
                    self.cell(key: key, date: date, total: points[key], scale: scale)
                }
            }
            HStack {
                Text(
                    TokenActivity.window(referenceDate: self.referenceDate, calendar: self.calendar).lowerBound,
                    format: .dateTime.year().month().day())
                Spacer()
                Text(self.referenceDate, format: .dateTime.year().month().day())
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .frame(height: self.gridHeight, alignment: .top)
    }

    private func cell(
        key: String,
        date: Date,
        total: TokenActivityTotal?,
        scale: TokenActivityColorScale) -> some View
    {
        let count = total?.value
        let padding = !TokenActivity.window(referenceDate: self.referenceDate, calendar: self.calendar).contains(date)
        let fill: Color = count.map {
            $0 == 0 ? Color.secondary.opacity(0.1) :
                self.color.opacity(scale.intensity($0))
        } ?? .clear
        let unknown = total?.isLowerBound == true || count == nil
        let shape = RoundedRectangle(cornerRadius: 3).fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(
                Color.secondary.opacity(unknown ? 0.25 : 0),
                style: StrokeStyle(lineWidth: 1, dash: [2])))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(
                self.selectedDay == key ? Color.primary : .clear, lineWidth: 2))
            .frame(width: 12, height: 12)
        return shape.opacity(padding ? 0 : 1)
            .allowsHitTesting(!padding)
            .contentShape(Rectangle())
            .onTapGesture { if !padding { self.selectedDay = key } }
            .onLongPressGesture { if !padding { self.selectedDay = key } }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !padding { self.selectedDay = key } }
            .accessibilityHidden(padding)
            .accessibilityIdentifier("token-day-" + key)
            .accessibilityLabel(key + ", " + self.label + ", " + (total?.text ?? String(localized: "Unavailable")))
    }
}
