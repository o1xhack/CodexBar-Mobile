import CodexBarSync
import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Share Period

// MARK: - Share Style

enum ShareCardStyleOption: String, CaseIterable, Identifiable {
    case classic
    case cyber

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .cyber: String(localized: "Vibe")
        }
    }
}

enum SharePeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

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
    let totalCost: Double          // total for the selected period
    let todayCost: Double
    let totalTokens: Int
    let activeDays: Int
    let avgDailyCost: Double
    let providers: [ProviderRow]
    let topModels: [BreakdownRow]
    let dailyBars: [DailyBar]      // bars for chart (7 or 30 entries)

    struct ProviderRow {
        let name: String
        let cost: Double
        let share: Double // 0–1
        let color: Color
    }

    struct BreakdownRow {
        let label: String
        let cost: Double
        let share: Double
    }

    struct DailyBar {
        let label: String // "Mon", "03/15", etc.
        let cost: Double
    }

    /// Top 5 providers + "Others" if 6 or more exist (iOS 1.9.0+: bumped from
    /// top 3 → top 5 for consistency with the Cost dashboard's top-5+Others
    /// cap. Threshold is `count >= 6` — a list of exactly 5 just shows 5, no
    /// Others bucket).
    var displayProviders: [ProviderRow] {
        guard providers.count > 5 else { return providers }
        let top5 = Array(providers.prefix(5))
        let othersShare = providers.dropFirst(5).reduce(0.0) { $0 + $1.share }
        let othersCost = providers.dropFirst(5).reduce(0.0) { $0 + $1.cost }
        let others = ProviderRow(
            name: String(localized: "Others"),
            cost: othersCost,
            share: othersShare,
            color: .gray
        )
        return top5 + [others]
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
    static func renderImage(period: SharePeriod, data: ShareCardData, theme: ShareCardTheme = .light, style: ShareCardStyleOption = .classic) -> UIImage? {
        let view = CostShareCardView(period: period, data: data, theme: theme, style: style)
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
    /// Create ShareCardData for a given period from live insights
    init(insights: CostDashboardInsights, period: SharePeriod) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let monthStart = calendar.date(byAdding: .day, value: -29, to: today)!

        // Filter daily points by period
        let filteredDays: [CostDashboardInsights.DailyPoint]
        switch period {
        case .today:
            filteredDays = []
        case .week:
            filteredDays = insights.dailyPoints.filter { $0.date >= weekStart }
        case .month:
            filteredDays = insights.dailyPoints.filter { $0.date >= monthStart }
        }

        func monthlyDailyPoints(for row: CostDashboardInsights.ProviderRow) -> [CostDashboardInsights.DailyPoint] {
            row.dailyPoints.filter { $0.date >= monthStart }
        }

        func authoritativeThirtyDaySummary(for row: CostDashboardInsights.ProviderRow) -> (costUSD: Double?, tokens: Int?) {
            guard let summary = row.provider.costSummary else {
                return (nil, nil)
            }
            let summaryWindowDays = max(1, min(summary.historyDays ?? 30, 365))
            guard summaryWindowDays <= 30 else {
                return (nil, nil)
            }
            return (summary.last30DaysCostUSD, summary.last30DaysTokens)
        }

        func monthlyCost(for row: CostDashboardInsights.ProviderRow) -> Double {
            let dailyCost = monthlyDailyPoints(for: row).reduce(0) { $0 + $1.costUSD }
            guard let summaryCost = authoritativeThirtyDaySummary(for: row).costUSD else {
                return dailyCost
            }
            return max(dailyCost, summaryCost)
        }

        func monthlyTokens(for row: CostDashboardInsights.ProviderRow) -> Int {
            let dailyTokens = monthlyDailyPoints(for: row).reduce(0) { $0 + $1.totalTokens }
            guard let summaryTokens = authoritativeThirtyDaySummary(for: row).tokens else {
                return dailyTokens
            }
            return max(dailyTokens, summaryTokens)
        }

        let dayKeyFormatter = SyncCostSummary.iso8601DayKeyFormatter()

        func costSummaryPoints(
            for row: CostDashboardInsights.ProviderRow,
            period: SharePeriod
        ) -> [SyncDailyPoint] {
            guard let summary = row.provider.costSummary else { return [] }
            return summary.daily.filter { point in
                guard let date = dayKeyFormatter.date(from: point.dayKey) else { return false }
                switch period {
                case .today:
                    return calendar.isDate(date, inSameDayAs: today)
                case .week:
                    return date >= weekStart
                case .month:
                    return date >= monthStart
                }
            }
        }

        func monthlySummaryDailyPoints() -> [CostDashboardInsights.DailyPoint] {
            var totals: [String: (date: Date, costUSD: Double, totalTokens: Int)] = [:]
            for row in insights.providerRows {
                for point in costSummaryPoints(for: row, period: .month) {
                    guard let date = dayKeyFormatter.date(from: point.dayKey) else { continue }
                    totals[point.dayKey, default: (date, 0, 0)].costUSD += point.costUSD
                    totals[point.dayKey, default: (date, 0, 0)].totalTokens += point.totalTokens
                }
            }
            return totals
                .map { dayKey, total in
                    CostDashboardInsights.DailyPoint(
                        dayKey: dayKey,
                        date: total.date,
                        costUSD: total.costUSD,
                        totalTokens: total.totalTokens)
                }
                .sorted { $0.date < $1.date }
        }

        func modelRows(for period: SharePeriod) -> [BreakdownRow] {
            var totals: [String: Double] = [:]
            for row in insights.providerRows {
                for point in costSummaryPoints(for: row, period: period) {
                    for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                        totals[breakdown.label, default: 0] += breakdown.costUSD
                    }
                }
            }
            let hasLedgerOnlyProvider = insights.providerRows.contains { row in
                row.provider.costSummary == nil && (row.thirtyDayCost > 0 || !row.dailyPoints.isEmpty)
            }
            if period != .today && (totals.isEmpty || hasLedgerOnlyProvider) {
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
                .map { $0 }
        }

        // Compute totals
        let periodCost: Double
        let periodTokens: Int
        let monthlySummaryDays = monthlySummaryDailyPoints()
        let monthlyUsesProviderSummary: Bool
        switch period {
        case .today:
            periodCost = insights.totalTodayCost
            periodTokens = insights.providerRows.reduce(0) { total, row in
                total + row.todayTokens
            }
            monthlyUsesProviderSummary = false
        case .week:
            periodCost = filteredDays.reduce(0) { $0 + $1.costUSD }
            periodTokens = filteredDays.reduce(0) { $0 + $1.totalTokens }
            monthlyUsesProviderSummary = false
        case .month:
            let providerCost = insights.providerRows.reduce(0) { $0 + monthlyCost(for: $1) }
            let dailyCost = filteredDays.reduce(0) { $0 + $1.costUSD }
            periodCost = providerCost > 0 ? providerCost : dailyCost
            let providerTokens = insights.providerRows.reduce(0) { $0 + monthlyTokens(for: $1) }
            let dailyTokens = filteredDays.reduce(0) { $0 + $1.totalTokens }
            periodTokens = providerTokens > 0 ? providerTokens : dailyTokens
            monthlyUsesProviderSummary = providerCost > dailyCost || providerTokens > dailyTokens
        }

        // Provider rows are computed from provider-level daily points. This
        // keeps 7-day share cards exact instead of scaling 30-day shares.
        let adjustedProviders: [ProviderRow] = insights.providerRows.map { row in
            let cost: Double
            switch period {
            case .today:
                cost = row.todayCost
            case .week:
                cost = row.dailyPoints
                    .filter { $0.date >= weekStart }
                    .reduce(0) { $0 + $1.costUSD }
            case .month:
                cost = monthlyCost(for: row)
            }
            return ProviderRow(
                name: row.provider.providerName,
                cost: cost,
                share: periodCost > 0 ? cost / periodCost : 0,
                color: Self.providerColor(for: row.provider.providerID)
            )
        }

        let activeDays: Int
        let displayDays: [CostDashboardInsights.DailyPoint]
        switch period {
        case .today:
            displayDays = []
            activeDays = 1
        case .week:
            displayDays = filteredDays
            activeDays = displayDays.count(where: { $0.costUSD > 0 })
        case .month:
            displayDays = monthlyUsesProviderSummary && !monthlySummaryDays.isEmpty
                ? monthlySummaryDays
                : filteredDays
            activeDays = displayDays.count(where: { $0.costUSD > 0 })
        }

        self.totalCost = periodCost
        self.todayCost = insights.totalTodayCost
        self.totalTokens = periodTokens
        self.activeDays = activeDays
        self.avgDailyCost = activeDays > 0 ? periodCost / Double(activeDays) : 0
        self.providers = adjustedProviders.filter { $0.cost > 0 }

        // Top models (top 5 — bumped from 3 in iOS 1.9.0 for cap consistency).
        self.topModels = modelRows(for: period)

        // Daily bars
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"

        switch period {
        case .today:
            self.dailyBars = []
        case .week:
            self.dailyBars = displayDays.map { point in
                DailyBar(label: weekdayFormatter.string(from: point.date), cost: point.costUSD)
            }
        case .month:
            self.dailyBars = displayDays.enumerated().map { index, point in
                let dayNum = index + 1
                // Label every 7th day (= one label per week) plus day 1 and
                // the final day for visual anchors. On a 30-day window this
                // yields labels at days 1, 7, 14, 21, 28, 30 — same cadence
                // as the Cost-tab daily-spend chart's `.stride(by: .day,
                // count: 7)` gridlines, so the share card and dashboard
                // chart read as a matching pair. Changing the 7 here will
                // un-sync the two charts — also update ContentView's stride.
                let showLabel = dayNum == 1 || dayNum % 7 == 0 || dayNum == displayDays.count
                return DailyBar(label: showLabel ? "\(dayNum)" : "", cost: point.costUSD)
            }
        }
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
        }()
    )

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
        dailyBars: []
    )

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
        ]
    )
}
