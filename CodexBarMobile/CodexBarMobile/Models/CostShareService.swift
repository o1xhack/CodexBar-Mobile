import CodexBarSync
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Share Period

// MARK: - Share Style

enum ShareCardStyleOption: String, CaseIterable, Identifiable {
    case classic
    case cyber
    case heatmap

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .cyber: String(localized: "Vibe")
        case .heatmap: String(localized: "Heatmap")
        }
    }

    var symbol: String {
        switch self {
        case .classic: "doc.text.image"
        case .cyber: "sparkles"
        case .heatmap: "square.grid.3x3.square"
        }
    }
}

enum SharePeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .today: String(localized: "Today")
        case .week: String(localized: "7 Days")
        case .month: String(localized: "30 Days")
        }
    }

    var vibeHeadline: String {
        switch self {
        case .today: String(localized: "Did you vibe today?")
        case .week: String(localized: "Did you vibe this week?")
        case .month: String(localized: "Did you vibe this month?")
        }
    }
}

// MARK: - Data model for share card

struct ShareCardData {
    let totalCost: Double // total for the selected period
    let todayCost: Double
    let totalTokens: Int
    let activeDays: Int
    let avgDailyCost: Double
    let providers: [ProviderRow]
    let topModels: [BreakdownRow]
    let dailyBars: [DailyBar] // bars for chart (7 or 30 entries)
    var totalCostIsKnown = true
    var totalCostIsLowerBound = false
    var todayCostIsKnown = true
    var todayCostIsLowerBound = false
    var costCoverageIsIncomplete = false
    var avgDailyCostIsKnown = true

    struct ProviderRow {
        let name: String
        let cost: Double
        let share: Double // 0–1
        let color: Color
        var shareIsKnown = true
        var costIsLowerBound = false

        var costDisplayValue: String {
            let prefix = self.costIsLowerBound ? "≥" : ""
            return "\(prefix)\(CostFormatting.usd(self.cost))"
        }
    }

    struct BreakdownRow {
        let label: String
        let cost: Double
        let share: Double
    }

    struct DailyBar {
        let label: String // "Mon", "03/15", etc.
        let cost: Double
        var costIsKnown = true
    }

    /// Top 5 providers + "Others" if 6 or more exist (iOS 1.9.0+: bumped from
    /// top 3 → top 5 for consistency with the Cost dashboard's top-5+Others
    /// cap. Threshold is `count >= 6` — a list of exactly 5 just shows 5, no
    /// Others bucket).
    var displayProviders: [ProviderRow] {
        guard self.providers.count > 5 else { return self.providers }
        let top5 = Array(providers.prefix(5))
        let othersShare = self.providers.dropFirst(5).reduce(0.0) { $0 + $1.share }
        let othersCost = self.providers.dropFirst(5).reduce(0.0) { $0 + $1.cost }
        let others = ProviderRow(
            name: OthersRowPreview.title(names: self.providers.dropFirst(5).map(\.name)),
            cost: othersCost,
            share: othersShare,
            color: .gray,
            shareIsKnown: self.providers.dropFirst(5).allSatisfy(\.shareIsKnown),
            costIsLowerBound: self.providers.dropFirst(5).contains(where: \.costIsLowerBound))
        return top5 + [others]
    }

    var chartMaximumCost: Double {
        let maximum = self.dailyBars
            .filter(\.costIsKnown)
            .map(\.cost)
            .max() ?? 0
        return maximum > 0 ? maximum : 1
    }

    var todayCostDisplayValue: String {
        guard self.todayCostIsKnown else { return "—" }
        let prefix = self.todayCostIsLowerBound ? "≥" : ""
        return "\(prefix)\(CostFormatting.usd(self.todayCost))"
    }

    var totalCostDisplayValue: String {
        guard self.totalCostIsKnown else { return "—" }
        let prefix = self.totalCostIsLowerBound ? "≥" : ""
        return "\(prefix)\(CostFormatting.usd(self.totalCost))"
    }

    func chartBarHeight(for day: DailyBar, chartHeight: CGFloat) -> CGFloat {
        guard day.costIsKnown, day.cost > 0 else { return 0 }
        return max(2, CGFloat(day.cost / self.chartMaximumCost) * chartHeight)
    }
}

// MARK: - QR Code Generator

enum QRCodeGenerator {
    static func generate(from string: String, size: CGFloat = 120) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else {
            return UIImage(systemName: "qrcode")!
        }

        let scale = size / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return UIImage(systemName: "qrcode")!
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Share Service

@MainActor
enum CostShareService {
    static func renderImage(
        period: SharePeriod,
        data: ShareCardData,
        theme: ShareCardTheme = .light,
        style: ShareCardStyleOption = .classic,
        heatmapData: HeatmapShareData? = nil) -> UIImage?
    {
        let view = CostShareCardView(
            period: period,
            data: data,
            theme: theme,
            style: style,
            heatmapData: heatmapData)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        return renderer.uiImage
    }

    /// Render card to a temp PNG file for use with ShareLink(item: URL)
    static func renderToFile(period: SharePeriod, data: ShareCardData, theme: ShareCardTheme = .light) -> URL? {
        guard let image = renderImage(period: period, data: data, theme: theme),
              let pngData = image.pngData() else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-Share-\(period.rawValue).png")
        do {
            try pngData.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Build from CostDashboardInsights

extension ShareCardData {
    /// Create share data using the same captured instant that produced the
    /// source insights. This is the normal UI path and prevents a sheet left
    /// open across producer midnight from mixing two logical days.
    init(
        insights: CostDashboardInsights,
        period: SharePeriod,
        calendar: Calendar = .current)
    {
        self.init(
            insights: insights,
            period: period,
            now: insights.referenceDate,
            calendar: calendar)
    }

    /// Explicit reference-date form for deterministic tests and callers that
    /// intentionally rebuild the share projection for another instant.
    init(
        insights: CostDashboardInsights,
        period: SharePeriod,
        now: Date,
        calendar: Calendar = .current)
    {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let monthStart = calendar.date(byAdding: .day, value: -29, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let displayDayKeyFormatter = DateFormatter()
        displayDayKeyFormatter.calendar = calendar
        displayDayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        displayDayKeyFormatter.timeZone = calendar.timeZone
        displayDayKeyFormatter.dateFormat = "yyyy-MM-dd"

        func periodIncludes(
            dayKey: String,
            date: Date,
            summary: SyncCostSummary?,
            usesReaderCalendar: Bool = false,
            period selectionPeriod: SharePeriod) -> Bool
        {
            if !usesReaderCalendar,
               let summary,
               let offset = summary.costDayOffset(for: dayKey, from: now)
            {
                let oldestOffset = switch selectionPeriod {
                case .today: 0
                case .week: -6
                case .month: -29
                }
                return offset >= oldestOffset && offset <= 0
            }
            switch selectionPeriod {
            case .today:
                return calendar.isDate(date, inSameDayAs: today)
            case .week:
                return date >= weekStart && date < tomorrow
            case .month:
                return date >= monthStart && date < tomorrow
            }
        }

        /// Map a producer-local logical day onto the reader's relative day
        /// axis. A UTC producer's day 0 therefore renders on the phone's day 0
        /// even when their wall-clock date strings differ around midnight.
        func displayIdentity(
            dayKey: String,
            date: Date,
            summary: SyncCostSummary?,
            usesReaderCalendar: Bool = false) -> (dayKey: String, date: Date)
        {
            guard !usesReaderCalendar,
                  let summary,
                  let offset = summary.costDayOffset(for: dayKey, from: now),
                  let displayDate = calendar.date(byAdding: .day, value: offset, to: today)
            else {
                return (dayKey, date)
            }
            return (displayDayKeyFormatter.string(from: displayDate), displayDate)
        }

        /// Rebuild daily display values from provider rows instead of reusing
        /// the dashboard-wide daily accumulator. The latter deliberately marks
        /// a whole day unavailable when any provider is unavailable; share-card
        /// totals, however, retain the known provider contributions as a
        /// qualified lower bound. Using the same reducer here keeps totals,
        /// active-day counts, bars, and model rows internally consistent.
        func providerDailyPoints(
            where includes: (CostDashboardInsights.ProviderRow, CostDashboardInsights.DailyPoint) -> Bool) -> [
            CostDashboardInsights.DailyPoint
        ] {
            typealias Accumulator = (
                date: Date,
                costUSD: Double,
                totalTokens: Int,
                sawAvailableCost: Bool,
                sawUnavailableCost: Bool,
                hasCostActivity: Bool,
                modelCosts: [String: Double],
                serviceCosts: [String: Double])
            var totals: [String: Accumulator] = [:]

            for row in insights.providerRows {
                for point in row.dailyPoints where includes(row, point) {
                    let identity = displayIdentity(
                        dayKey: point.dayKey,
                        date: point.date,
                        summary: row.provider.costSummary,
                        usesReaderCalendar: row.dailyPointsUseReaderCalendar)
                    var total = totals[identity.dayKey] ?? (
                        identity.date, 0, 0, false, false, false, [:], [:])
                    total.totalTokens += point.totalTokens
                    total.hasCostActivity = total.hasCostActivity || point.hasCostActivity
                    if point.costIsKnown == false {
                        total.sawUnavailableCost = true
                    } else {
                        total.sawAvailableCost = true
                        total.costUSD += point.costUSD
                        for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                            total.modelCosts[breakdown.label, default: 0] += breakdown.costUSD
                        }
                        for breakdown in point.serviceBreakdowns where breakdown.costUSD > 0 {
                            total.serviceCosts[breakdown.label, default: 0] += breakdown.costUSD
                        }
                    }
                    totals[identity.dayKey] = total
                }
            }

            return totals.map { dayKey, total in
                CostDashboardInsights.DailyPoint(
                    dayKey: dayKey,
                    date: total.date,
                    costUSD: total.costUSD,
                    costIsKnown: total.sawAvailableCost
                        ? true
                        : total.sawUnavailableCost ? false : nil,
                    hasCostActivity: total.hasCostActivity,
                    totalTokens: total.totalTokens,
                    modelBreakdowns: total.modelCosts.map {
                        SyncCostBreakdown(label: $0.key, costUSD: $0.value)
                    },
                    serviceBreakdowns: total.serviceCosts.map {
                        SyncCostBreakdown(label: $0.key, costUSD: $0.value)
                    })
            }
            .sorted { $0.date < $1.date }
        }

        // Filter provider-aware daily points by period. Keep a separate check
        // over the provider rows because the cross-provider reducer retains a
        // known lower-bound contribution when another provider is unavailable.
        // That merged day is useful for totals, but it must not authorize a
        // fallback to dashboard-wide model costs that may contain the
        // unavailable provider's breakdowns.
        let filteredDays = providerDailyPoints { row, point in
            periodIncludes(
                dayKey: point.dayKey,
                date: point.date,
                summary: row.provider.costSummary,
                usesReaderCalendar: row.dailyPointsUseReaderCalendar,
                period: period)
        }
        let selectedPeriodHasUnavailableProviderCost = insights.providerRows.contains { row in
            row.dailyPoints.contains { point in
                periodIncludes(
                    dayKey: point.dayKey,
                    date: point.date,
                    summary: row.provider.costSummary,
                    usesReaderCalendar: row.dailyPointsUseReaderCalendar,
                    period: period) && point.costIsKnown == false
            }
        }
        let selectedPeriodHasMixedReportingPeriods: Bool = {
            guard period != .today else { return false }
            let summaries = insights.providerRows.compactMap(\.provider.costSummary)
            guard !summaries.isEmpty else { return false }
            let periods = Set(summaries.map { summary in
                summary.reportingPeriod ?? "rolling:\(max(1, min(summary.reportingPeriodHistoryDays ?? 30, 365)))"
            })
            return periods.count > 1
        }()
        let selectedPeriodHasIncomparableHistoryWindow: Bool = switch period {
        case .today:
            false
        case .week, .month:
            insights.providerRows.contains {
                $0.provider.costSummary?.reportingPeriodHistoryWindowIsComparable == false
            }
        }
        let selectedPeriodHasUnresolvedModernProviderCost = insights.providerRows.contains { row in
            guard let summary = row.provider.costSummary else { return false }

            // Aggregate coverage counters are not date-scoped, so a reported
            // pricing gap cannot be proven outside the selected period.
            if summary.reportingPeriodCoverage.map({ $0.unpriced > 0 || $0.unmetered > 0 }) == true {
                return true
            }

            // Every selectable period extends through Today. If the producer's
            // last cost source belongs to another day, dates after that source
            // are not certified zero even when the older scan completed.
            let sourceDayKey = summary.sourceDayKey
                ?? summary.sourceUpdatedAt.map(summary.costDayKey)
            if let sourceDayKey,
               sourceDayKey != summary.costDayKey(for: now)
            {
                return true
            }

            if summary.hasInvalidBucketTimeZoneIdentifier {
                return true
            }

            switch period {
            case .today:
                // The aggregate catch-up bit is not date-scoped. Even a
                // priced Today row remains a lower bound until the producer
                // finishes discovering every file in its scan window.
                return summary.reportingPeriodHistoryCoverageIsEstablished == false
            case .week:
                // The producer's aggregate catch-up bit is not date-scoped.
                // Old cached rows therefore cannot prove that a pending file
                // is outside this week. A multi-Mac window mismatch also
                // cannot prove every source covered all seven days because
                // the merged legacy-compatible payload retains only the
                // widest label, so keep both cases qualified.
                return summary.reportingPeriodHistoryCoverageIsEstablished == false ||
                    summary.reportingPeriodHistoryWindowIsComparable == false
            case .month:
                return summary.reportingPeriodHistoryCoverageIsEstablished == false ||
                    summary.reportingPeriodHistoryWindowIsComparable == false
            }
        }
        let selectedPeriodHasUnknownLegacyProviderCost = insights.providerRows.contains { row in
            guard let summary = row.provider.costSummary,
                  summary.reportingPeriodHistoryCoverageIsEstablished == nil,
                  summary.reportingPeriodCoverage == nil,
                  summary.reportingPeriodDaily.isEmpty
            else {
                return false
            }

            switch period {
            case .today:
                return (summary.sessionTokens ?? 0) > 0 && summary.sessionCostUSD == nil
            case .week:
                // A legacy aggregate with no dated rows cannot identify how
                // much of a non-zero 30-day total belongs to this week.
                let tokens = summary.reportingPeriodTokens ?? summary.sessionTokens ?? 0
                return (summary.reportingPeriodCostUSD ?? 0) > 0 || tokens > 0
            case .month:
                let tokens = summary.reportingPeriodTokens ?? summary.sessionTokens ?? 0
                return tokens > 0 && summary.reportingPeriodCostUSD == nil
            }
        }

        func monthlyDailyPoints(for row: CostDashboardInsights.ProviderRow) -> [CostDashboardInsights.DailyPoint] {
            row.dailyPoints.filter { point in
                periodIncludes(
                    dayKey: point.dayKey,
                    date: point.date,
                    summary: row.provider.costSummary,
                    usesReaderCalendar: row.dailyPointsUseReaderCalendar,
                    period: .month)
            }
        }

        let dayKeyFormatter = SyncCostSummary.iso8601DayKeyFormatter()

        func providerDailyCoverageIsComplete(
            for row: CostDashboardInsights.ProviderRow,
            dayCount: Int) -> Bool
        {
            let summary = row.provider.costSummary
            if let summary {
                let sourceDayKey = summary.sourceDayKey ?? summary.sourceUpdatedAt.map(summary.costDayKey)
                guard summary.reportingPeriodHistoryCoverageIsEstablished != false,
                      summary.reportingPeriodHistoryWindowIsComparable != false,
                      !summary.hasIncompleteHistoricalCostCoverage(at: now),
                      !summary.hasInvalidBucketTimeZoneIdentifier,
                      summary.reportingPeriodCoverage.map({ $0.unpriced == 0 && $0.unmetered == 0 }) ?? true,
                      sourceDayKey == nil || sourceDayKey == summary.costDayKey(for: now)
                else {
                    return false
                }
            }
            let requiredOffsets = Set((0..<dayCount).map { -$0 })
            var knownOffsets = Set<Int>()

            func addKnownOffset(
                dayKey: String,
                date: Date,
                costIsKnown: Bool?,
                usesReaderCalendar: Bool)
            {
                guard costIsKnown != false else { return }
                if !usesReaderCalendar,
                   let summary,
                   let offset = summary.costDayOffset(for: dayKey, from: now)
                {
                    knownOffsets.insert(offset)
                } else if summary == nil || usesReaderCalendar {
                    let offset = calendar.dateComponents(
                        [.day],
                        from: today,
                        to: calendar.startOfDay(for: date)).day
                    if let offset { knownOffsets.insert(offset) }
                }
            }

            for point in row.dailyPoints {
                addKnownOffset(
                    dayKey: point.dayKey,
                    date: point.date,
                    costIsKnown: point.costIsKnown,
                    usesReaderCalendar: row.dailyPointsUseReaderCalendar)
            }
            if let summary {
                for point in summary.reportingPeriodDaily {
                    guard let date = dayKeyFormatter.date(from: point.dayKey) else { continue }
                    addKnownOffset(
                        dayKey: point.dayKey,
                        date: date,
                        costIsKnown: point.costIsKnown,
                        usesReaderCalendar: false)
                }
            }
            if requiredOffsets.isSubset(of: knownOffsets) {
                return true
            }

            // Sparse daily ledgers can certify omitted dates as zero only when
            // the producer explicitly completed a window that covers every
            // selected logical date.
            guard let summary,
                  summary.reportingPeriodHistoryCoverageIsEstablished != false,
                  summary.reportingPeriodHistoryWindowIsComparable != false,
                  (!summary.reportingPeriodDaily.isEmpty || summary.reportingPeriod != nil ||
                    (summary.reportingPeriodHistoryCoverageIsEstablished == true &&
                        summary.reportingPeriodCostUSD == 0 && summary.reportingPeriodTokens == 0)),
                  summary.reportingPeriodDaily.allSatisfy({ $0.costIsKnown != false }),
                  !summary.hasIncompleteHistoricalCostCoverage(at: now)
            else {
                return false
            }
            let availableStartOffset: Int
            if let reportingPeriod = summary.reportingPeriod,
               reportingPeriod.hasPrefix("rolling:"),
               let reportedDays = Int(reportingPeriod.dropFirst("rolling:".count)),
               reportedDays > 0
            {
                availableStartOffset = -(min(reportedDays, 365) - 1)
            } else if summary.reportingPeriod == "month-to-date" {
                availableStartOffset = -(calendar.component(.day, from: today) - 1)
            } else if summary.reportingPeriod == "all",
                      let historyDays = summary.reportingPeriodHistoryDays,
                      historyDays > 0
            {
                availableStartOffset = -(min(historyDays, 365) - 1)
            } else if summary.reportingPeriod == nil,
                      summary.reportingPeriodHistoryDays.map({ $0 >= dayCount }) ?? true
            {
                // Before reportingPeriod was added, completed sparse summaries
                // represented the legacy rolling window. A typed MTD summary
                // never takes this path.
                availableStartOffset = -(dayCount - 1)
            } else {
                // An older summary without typed period semantics cannot
                // prove whether its coverage starts at month-start or at a
                // rolling boundary. Dated rows above can still prove it.
                return false
            }
            if let historyDays = summary.reportingPeriodHistoryDays, historyDays < dayCount {
                return false
            }
            let requiredStartOffset = -(dayCount - 1)
            return availableStartOffset <= requiredStartOffset
        }

        func weeklyCost(for row: CostDashboardInsights.ProviderRow) -> (value: Double, isKnown: Bool) {
            let availableDaily = row.dailyPoints
                .filter { point in
                    periodIncludes(
                        dayKey: point.dayKey,
                        date: point.date,
                        summary: row.provider.costSummary,
                        usesReaderCalendar: row.dailyPointsUseReaderCalendar,
                        period: .week)
                }
                .filter { $0.costIsKnown != false }
            return (
                availableDaily.reduce(0) { $0 + $1.costUSD },
                providerDailyCoverageIsComplete(for: row, dayCount: 7))
        }

        func hasCompatibleLegacyThirtyDayAggregate(for row: CostDashboardInsights.ProviderRow) -> Bool {
            guard let summary = row.provider.costSummary,
                  summary.last30DaysCostUSD != nil,
                  summary.reportingPeriod == nil,
                  summary.reportingPeriodHistoryWindowIsComparable != false,
                  summary.reportingPeriodHistoryDays == nil || summary.reportingPeriodHistoryDays == 30
            else {
                return false
            }
            return true
        }

        func authoritativeThirtyDaySummary(for row: CostDashboardInsights
            .ProviderRow) -> (costUSD: Double?, tokens: Int?)
        {
            guard let summary = row.provider.costSummary else {
                return (nil, nil)
            }
            guard summary.reportingPeriodHistoryWindowIsComparable != false else {
                return (nil, nil)
            }
            guard !selectedPeriodHasMixedReportingPeriods else {
                return (nil, nil)
            }
            let hasCompatibleModernAggregate = summary.reportingPeriod == "rolling:30"
            guard hasCompatibleModernAggregate || hasCompatibleLegacyThirtyDayAggregate(for: row) else {
                return (nil, nil)
            }
            return (
                summary.last30DaysCostUSD,
                summary.last30DaysTokens)
        }

        func monthlyCost(for row: CostDashboardInsights.ProviderRow) -> (value: Double, isKnown: Bool) {
            let availableDaily = monthlyDailyPoints(for: row).filter { $0.costIsKnown != false }
            let dailyCost = availableDaily.reduce(0) { $0 + $1.costUSD }
            let dailyCoverageIsComplete = providerDailyCoverageIsComplete(for: row, dayCount: 30)
            let summaryCost = authoritativeThirtyDaySummary(for: row).costUSD
            guard let summaryCost else {
                return (dailyCost, dailyCoverageIsComplete)
            }
            return (
                max(dailyCost, summaryCost),
                true)
        }

        func monthlyTokens(for row: CostDashboardInsights.ProviderRow) -> Int {
            let dailyTokens = monthlyDailyPoints(for: row).reduce(0) { $0 + $1.totalTokens }
            guard let summaryTokens = authoritativeThirtyDaySummary(for: row).tokens else {
                return dailyTokens
            }
            return max(dailyTokens, summaryTokens)
        }

        func costSummaryPoints(
            for row: CostDashboardInsights.ProviderRow,
            period: SharePeriod) -> [SyncDailyPoint]
        {
            guard let summary = row.provider.costSummary else { return [] }
            return summary.reportingPeriodDaily.filter { point in
                guard let date = dayKeyFormatter.date(from: point.dayKey) else { return false }
                return periodIncludes(
                    dayKey: point.dayKey,
                    date: date,
                    summary: summary,
                    period: period)
            }
        }

        func monthlySummaryDisplayData() -> (
            dailyPoints: [CostDashboardInsights.DailyPoint],
            modelBreakdowns: [SyncCostBreakdown])
        {
            var totals: [String: (
                date: Date,
                costUSD: Double,
                totalTokens: Int,
                sawAvailableCost: Bool,
                sawUnavailableCost: Bool,
                hasCostActivity: Bool)] = [:]
            var modelTotals: [String: Double] = [:]
            func addDay(
                dayKey: String,
                date: Date,
                costUSD: Double,
                costIsKnown: Bool?,
                totalTokens: Int,
                modelBreakdowns: [SyncCostBreakdown])
            {
                totals[dayKey, default: (date, 0, 0, false, false, false)].totalTokens += totalTokens
                if costUSD > 0 {
                    totals[dayKey]?.hasCostActivity = true
                }
                if costIsKnown == false {
                    totals[dayKey]?.sawUnavailableCost = true
                } else {
                    // Keep the visible lower-bound contribution even when a
                    // different provider on the same day is unavailable.
                    totals[dayKey]?.sawAvailableCost = true
                    totals[dayKey]?.costUSD += costUSD
                }
                // Keep Top Models on the same truth boundary as the day total.
                // A producer may retain non-zero breakdowns while explicitly
                // marking the row unavailable; those values must not reappear
                // as dollar shares after the subtotal itself is suppressed.
                for breakdown in modelBreakdowns
                    where costIsKnown != false && breakdown.costUSD > 0
                {
                    modelTotals[breakdown.label, default: 0] += breakdown.costUSD
                }
            }
            for row in insights.providerRows {
                if row.provider.costSummary == nil {
                    for point in monthlyDailyPoints(for: row) {
                        addDay(
                            dayKey: point.dayKey,
                            date: point.date,
                            costUSD: point.costUSD,
                            costIsKnown: point.costIsKnown,
                            totalTokens: point.totalTokens,
                            modelBreakdowns: point.modelBreakdowns)
                    }
                } else {
                    for point in costSummaryPoints(for: row, period: .month) {
                        guard let date = dayKeyFormatter.date(from: point.dayKey) else { continue }
                        let identity = displayIdentity(
                            dayKey: point.dayKey,
                            date: date,
                            summary: row.provider.costSummary)
                        addDay(
                            dayKey: identity.dayKey,
                            date: identity.date,
                            costUSD: point.costUSD,
                            costIsKnown: point.costIsKnown,
                            totalTokens: point.totalTokens,
                            modelBreakdowns: point.modelBreakdowns)
                    }
                }
            }
            let dailyPoints = totals
                .map { dayKey, total in
                    CostDashboardInsights.DailyPoint(
                        dayKey: dayKey,
                        date: total.date,
                        costUSD: total.costUSD,
                        costIsKnown: total.sawAvailableCost
                            ? true
                            : total.sawUnavailableCost ? false : nil,
                        hasCostActivity: total.hasCostActivity,
                        totalTokens: total.totalTokens)
                }
                .sorted { $0.date < $1.date }
            let modelBreakdowns = modelTotals
                .map { SyncCostBreakdown(label: $0.key, costUSD: $0.value) }
                .sorted {
                    if $0.costUSD == $1.costUSD {
                        return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                    }
                    return $0.costUSD > $1.costUSD
                }
            return (dailyPoints, modelBreakdowns)
        }

        func modelRows(
            for period: SharePeriod,
            monthlyUsesProviderSummary: Bool,
            monthlySummaryModelBreakdowns: [SyncCostBreakdown]) -> [BreakdownRow]
        {
            var totals: [String: Double] = [:]
            if period == .month, monthlyUsesProviderSummary {
                for breakdown in monthlySummaryModelBreakdowns where breakdown.costUSD > 0 {
                    totals[breakdown.label, default: 0] += breakdown.costUSD
                }
            } else {
                for point in filteredDays where point.costIsKnown != false {
                    for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                        totals[breakdown.label, default: 0] += breakdown.costUSD
                    }
                }
            }
            let periodDays = switch period {
            case .today: 1
            case .week: 7
            case .month: 30
            }
            let usesDashboardWindow = period != .month || !monthlyUsesProviderSummary
            if totals.isEmpty,
               usesDashboardWindow,
               !selectedPeriodHasUnavailableProviderCost,
               (insights.historyDays ?? 30) <= periodDays
            {
                let fallbackRows = insights.modelRows
                    .filter { $0.amountUSD > 0 }
                    .sorted {
                        if $0.amountUSD == $1.amountUSD {
                            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                        } else {
                            $0.amountUSD > $1.amountUSD
                        }
                    }
                    .prefix(5)
                let fallbackTotal = fallbackRows.reduce(0) { $0 + $1.amountUSD }
                guard fallbackTotal > 0 else { return [] }
                return fallbackRows
                    .map { row in
                        BreakdownRow(
                            label: row.label,
                            cost: row.amountUSD,
                            share: row.amountUSD / fallbackTotal)
                    }
            }
            let totalModel = totals.values.reduce(0, +)
            guard totalModel > 0 else { return [] }
            return totals
                .map { label, cost in
                    BreakdownRow(
                        label: label,
                        cost: cost,
                        share: cost / totalModel)
                }
                .sorted {
                    if $0.cost == $1.cost {
                        $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                    } else {
                        $0.cost > $1.cost
                    }
                }
                .prefix(5)
                .map(\.self)
        }

        // Compute totals
        var periodCost: Double
        var periodCostIsKnown: Bool
        var periodTokens: Int
        let monthlySummaryData = monthlySummaryDisplayData()
        let monthlySummaryDays = monthlySummaryData.dailyPoints
        let missingDailyCostIsKnown = !insights.providerRows.isEmpty &&
            insights.providerRows.allSatisfy {
                providerDailyCoverageIsComplete(for: $0, dayCount: 30)
            }
        var monthlyUsesProviderSummary: Bool
        switch period {
        case .today:
            periodCost = insights.totalTodayCost
            periodCostIsKnown = insights.totalTodayCostIsKnown
            periodTokens = insights.providerRows.reduce(0) { total, row in
                total + row.todayTokens
            }
            monthlyUsesProviderSummary = false
        case .week:
            let weeklyProviderCosts = insights.providerRows.map(weeklyCost(for:))
            periodCost = weeklyProviderCosts.reduce(0) { $0 + $1.value }
            let allProvidersAreExplicitlyClassified = zip(insights.providerRows, weeklyProviderCosts)
                .allSatisfy { row, cost in
                    if cost.isKnown { return true }
                    guard let summary = row.provider.costSummary else { return false }
                    return summary.reportingPeriodDaily.contains { point in
                        guard point.costIsKnown == false,
                              let date = SyncCostSummary.iso8601DayKeyFormatter().date(from: point.dayKey)
                        else {
                            return false
                        }
                        return periodIncludes(
                            dayKey: point.dayKey,
                            date: date,
                            summary: summary,
                            period: .week)
                    }
                }
            periodCostIsKnown = !weeklyProviderCosts.isEmpty &&
                (weeklyProviderCosts.allSatisfy(\.isKnown) ||
                    (weeklyProviderCosts.contains(where: { $0.value > 0 }) &&
                        !weeklyProviderCosts.allSatisfy(\.isKnown) && allProvidersAreExplicitlyClassified))
            periodTokens = filteredDays.reduce(0) { $0 + $1.totalTokens }
            monthlyUsesProviderSummary = false
        case .month:
            let monthlyProviderCosts = insights.providerRows.map(monthlyCost(for:))
            let providerCost = monthlyProviderCosts.reduce(0) { $0 + $1.value }
            let availableDays = filteredDays.filter { $0.costIsKnown != false }
            let dailyCost = availableDays.reduce(0) { $0 + $1.costUSD }
            periodCost = providerCost > 0 ? providerCost : dailyCost
            periodCostIsKnown = !monthlyProviderCosts.isEmpty && monthlyProviderCosts.allSatisfy(\.isKnown)
            let providerTokens = insights.providerRows.reduce(0) { $0 + monthlyTokens(for: $1) }
            let dailyTokens = filteredDays.reduce(0) { $0 + $1.totalTokens }
            periodTokens = providerTokens > 0 ? providerTokens : dailyTokens
            let summaryExtendsShortDashboardWindow = (insights.historyDays ?? 30) < 30
                && insights.providerRows.contains { row in
                    let summary = authoritativeThirtyDaySummary(for: row)
                    return summary.costUSD != nil || summary.tokens != nil
                }
            monthlyUsesProviderSummary = summaryExtendsShortDashboardWindow
                || providerCost > dailyCost
                || providerTokens > dailyTokens
                || !monthlySummaryData.modelBreakdowns.isEmpty
        }

        if selectedPeriodHasIncomparableHistoryWindow {
            periodCost = 0
            periodCostIsKnown = false
            periodTokens = 0
            monthlyUsesProviderSummary = false
        }
        if selectedPeriodHasMixedReportingPeriods {
            // Keep any dated subtotal available to the card as a lower bound,
            // but never present it as a comparable period total or token mix.
            periodCostIsKnown = false
            periodTokens = 0
        }

        let providerSharesAreKnown = periodCostIsKnown &&
            !selectedPeriodHasMixedReportingPeriods &&
            !selectedPeriodHasUnavailableProviderCost &&
            !selectedPeriodHasUnresolvedModernProviderCost &&
            !selectedPeriodHasUnknownLegacyProviderCost &&
            !insights.providerRows.isEmpty &&
            insights.providerRows.allSatisfy { row in
                switch period {
                case .today:
                    return row.todayCostIsKnown && !row.todayCostIsLowerBound
                case .week:
                    return providerDailyCoverageIsComplete(for: row, dayCount: 7)
                case .month:
                    return providerDailyCoverageIsComplete(for: row, dayCount: 30)
                }
            }

        // Provider rows are computed from provider-level daily points. This
        // keeps 7-day share cards exact instead of scaling 30-day shares.
        let adjustedProviders: [ProviderRow] = selectedPeriodHasIncomparableHistoryWindow
            ? []
            : insights.providerRows.map { row in
            let cost: Double
            let costIsLowerBound: Bool
            switch period {
            case .today:
                cost = row.todayCost
                costIsLowerBound = row.todayCostIsLowerBound
            case .week:
                let weekly = weeklyCost(for: row)
                cost = weekly.value
                costIsLowerBound = !weekly.isKnown
            case .month:
                let monthly = monthlyCost(for: row)
                cost = monthly.value
                costIsLowerBound = !monthly.isKnown ||
                    row.provider.costSummary?.hasIncompleteHistoricalCostCoverage(at: now) == true
            }
            return ProviderRow(
                name: row.provider.providerName,
                cost: cost,
                share: periodCost > 0 ? cost / periodCost : 0,
                color: Self.providerColor(for: row.provider.providerID),
                shareIsKnown: providerSharesAreKnown,
                costIsLowerBound: costIsLowerBound)
        }

        let activeDays: Int
        let displayDays: [CostDashboardInsights.DailyPoint]
        if selectedPeriodHasIncomparableHistoryWindow {
            displayDays = []
            activeDays = 0
        } else {
            switch period {
            case .today:
                displayDays = filteredDays
                activeDays = displayDays.contains(where: \.hasCostActivity) ? 1 : 0
            case .week:
                displayDays = filteredDays
                activeDays = displayDays.count(where: \.hasCostActivity)
            case .month:
                displayDays = monthlyUsesProviderSummary && !monthlySummaryDays.isEmpty
                    ? monthlySummaryDays
                    : filteredDays
                activeDays = displayDays.count(where: \.hasCostActivity)
            }
        }

        self.totalCost = periodCost
        self.todayCost = insights.totalTodayCost
        self.totalTokens = periodTokens
        self.activeDays = activeDays
        self.avgDailyCost = activeDays > 0 ? periodCost / Double(activeDays) : 0
        self.providers = adjustedProviders.filter { $0.cost > 0 }

        // Top models (top 5 — bumped from 3 in iOS 1.9.0 for cap consistency).
        self.topModels = selectedPeriodHasIncomparableHistoryWindow || selectedPeriodHasMixedReportingPeriods
            ? []
            : modelRows(
            for: period,
            monthlyUsesProviderSummary: monthlyUsesProviderSummary,
            monthlySummaryModelBreakdowns: monthlySummaryData.modelBreakdowns)

        // Daily bars
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"

        if selectedPeriodHasIncomparableHistoryWindow {
            self.dailyBars = []
        } else {
            switch period {
            case .today:
                self.dailyBars = []
            case .week:
                self.dailyBars = displayDays.filter { $0.costIsKnown != false }.map { point in
                    DailyBar(label: weekdayFormatter.string(from: point.date), cost: point.costUSD)
                }
            case .month:
                let pointsByDay = Dictionary(uniqueKeysWithValues: displayDays.map {
                    (calendar.startOfDay(for: $0.date), $0)
                })
                self.dailyBars = (0..<30).compactMap { index in
                    guard let date = calendar.date(byAdding: .day, value: index, to: monthStart) else {
                        return nil
                    }
                    let point = pointsByDay[date]
                    let dayNum = index + 1
                    // Label every 7th day (= one label per week) plus day 1 and
                    // the final day for visual anchors. On a 30-day window this
                    // yields labels at days 1, 7, 14, 21, 28, 30 — same cadence
                    // as the Cost-tab daily-spend chart's `.stride(by: .day,
                    // count: 7)` gridlines, so the share card and dashboard
                    // chart read as a matching pair. Changing the 7 here will
                    // un-sync the two charts — also update ContentView's stride.
                    let showLabel = dayNum == 1 || dayNum % 7 == 0 || dayNum == 30
                    let costIsKnown = point?.costIsKnown != false
                        && (point != nil || missingDailyCostIsKnown)
                    return DailyBar(
                        label: showLabel ? "\(dayNum)" : "",
                        cost: costIsKnown ? point?.costUSD ?? 0 : 0,
                        costIsKnown: costIsKnown)
                }
            }
        }
        self.totalCostIsKnown = periodCostIsKnown
        self.totalCostIsLowerBound = period == .today
            ? insights.totalTodayCostIsLowerBound
            : adjustedProviders.contains(where: \.costIsLowerBound)
        self.todayCostIsKnown = insights.totalTodayCostIsKnown
        self.todayCostIsLowerBound = insights.totalTodayCostIsLowerBound
        let selectedPeriodUsesIncompleteSummary = period == .month &&
            monthlyUsesProviderSummary &&
            insights.providerRows.contains {
                $0.provider.costSummary?.hasIncompleteHistoricalCostCoverage(at: now) == true
            }
        self.costCoverageIsIncomplete = selectedPeriodHasUnavailableProviderCost ||
            selectedPeriodHasUnresolvedModernProviderCost ||
            selectedPeriodHasUnknownLegacyProviderCost ||
            selectedPeriodUsesIncompleteSummary ||
            (period != .today && !insights.providerRows.isEmpty && !periodCostIsKnown) ||
            self.dailyBars.contains(where: { !$0.costIsKnown })
        // A retained lower-bound subtotal is useful, but dividing it by only
        // the fully priced days overstates Avg/Day. Keep the subtotal visible
        // with its incomplete-coverage warning and suppress the derived
        // average until the whole contributing window is comparable.
        self.avgDailyCostIsKnown = periodCostIsKnown
            && activeDays > 0
            && !self.costCoverageIsIncomplete
    }
}

// MARK: - Provider color mapping

extension ShareCardData {
    static func providerColor(for providerIdentifier: String) -> Color {
        ProviderColorPalette.color(for: providerIdentifier)
    }
}

// MARK: - Preview data

extension ShareCardData {
    static let preview = ShareCardData(
        totalCost: 541.83,
        todayCost: 78.56,
        totalTokens: 18_450_000,
        activeDays: 24,
        avgDailyCost: 22.58,
        providers: [
            .init(name: "Claude", cost: 401.30, share: 0.74, color: Color(red: 0.82, green: 0.55, blue: 0.28)),
            .init(name: "Codex", cost: 109.33, share: 0.20, color: .purple),
            .init(name: "ChatGPT", cost: 19.40, share: 0.04, color: .green),
            .init(name: "OpenRouter", cost: 11.80, share: 0.02, color: Color(red: 0.42, green: 0.35, blue: 0.83)),
        ],
        topModels: [
            .init(label: "claude-opus-4-6", cost: 308.20, share: 0.57),
            .init(label: "claude-sonnet-4", cost: 93.10, share: 0.17),
            .init(label: "gpt-5.4", cost: 56.84, share: 0.10),
        ],
        dailyBars: {
            // 30 days of sample data, only label every 7th day
            let base = 18.0
            return (0..<30).map { i in
                let weekday = (i + 3) % 7
                let isWeekend = weekday == 5 || weekday == 6
                let growth = pow(Double(i + 1) / 30.0, 1.3)
                let noise = sin(Double(i) * 0.8) * 4
                let cost = max(0.5, (isWeekend ? base * 0.3 : base) * growth + noise)
                let showLabel = i == 0 || (i + 1) % 7 == 0 || i == 29
                return DailyBar(label: showLabel ? "\(i + 1)" : "", cost: cost)
            }
        }())

    static let previewToday = ShareCardData(
        totalCost: 78.56,
        todayCost: 78.56,
        totalTokens: 565_000,
        activeDays: 1,
        avgDailyCost: 78.56,
        providers: [
            .init(name: "Claude", cost: 57.14, share: 0.73, color: Color(red: 0.82, green: 0.55, blue: 0.28)),
            .init(name: "Codex", cost: 20.49, share: 0.26, color: .purple),
            .init(name: "ChatGPT", cost: 0.92, share: 0.01, color: .green),
        ],
        topModels: [
            .init(label: "claude-opus-4-6", cost: 44.10, share: 0.56),
            .init(label: "claude-sonnet-4", cost: 13.04, share: 0.17),
            .init(label: "gpt-5.4", cost: 12.30, share: 0.16),
        ],
        dailyBars: [])

    static let preview7d = ShareCardData(
        totalCost: 184.26,
        todayCost: 78.56,
        totalTokens: 4_820_000,
        activeDays: 6,
        avgDailyCost: 30.71,
        providers: [
            .init(name: "Claude", cost: 138.20, share: 0.75, color: Color(red: 0.82, green: 0.55, blue: 0.28)),
            .init(name: "Codex", cost: 35.86, share: 0.19, color: .purple),
            .init(name: "ChatGPT", cost: 10.20, share: 0.06, color: .green),
        ],
        topModels: [
            .init(label: "claude-opus-4-6", cost: 106.40, share: 0.58),
            .init(label: "claude-sonnet-4", cost: 31.80, share: 0.17),
            .init(label: "gpt-5.4", cost: 21.56, share: 0.12),
        ],
        dailyBars: [
            .init(label: "Thu", cost: 15.20),
            .init(label: "Fri", cost: 22.40),
            .init(label: "Sat", cost: 4.80),
            .init(label: "Sun", cost: 3.20),
            .init(label: "Mon", cost: 28.60),
            .init(label: "Tue", cost: 31.50),
            .init(label: "Wed", cost: 78.56),
        ])
}
