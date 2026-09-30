import CodexBarSync
import Foundation

struct TokenActivitySeries: Identifiable, Sendable {
    let provider: ProviderUsageSnapshot
    let days: [SyncDailyPoint]
    var hasLedgerCounts = false
    var id: String {
        self.provider.cardIdentityKey
    }
}

struct TokenActivityTotal: Equatable, Sendable {
    let value: Int?
    let isLowerBound: Bool

    var text: String {
        guard let value else { return String(localized: "Unavailable") }
        return (self.isLowerBound ? "≥" : "") + value.formatted()
    }
}

enum TokenActivity {
    static func dayRevision(
        providers: [ProviderUsageSnapshot],
        snapshots: [SyncedUsageSnapshot],
        referenceDate: Date,
        readerCalendar: Calendar = Calendar(identifier: .gregorian)) -> String
    {
        let producerDays = Set((providers + snapshots.flatMap(\.providers)).compactMap { provider -> String? in
            guard let summary = provider.costSummary else { return nil }
            return "\(summary.bucketTimeZoneIdentifier ?? "legacy"):\(summary.costDayKey(for: referenceDate))"
        })
        return ([Self.dayKey(referenceDate, calendar: readerCalendar)] + producerDays.sorted()).joined(separator: "|")
    }

    static func total(_ series: [TokenActivitySeries], dayKey: String? = nil) -> TokenActivityTotal {
        var values: [Int] = []
        var incomplete = false
        for item in series {
            let points: [SyncDailyPoint?] = if let dayKey {
                [item.days.first { $0.dayKey == dayKey }]
            } else {
                item.days.map(Optional.some)
            }
            for point in points {
                if let value = Self.recordedTokens(point, series: item) { values.append(value) }
                if point == nil || Self.knownTokens(point) == nil { incomplete = true }
            }
        }
        return TokenActivityTotal(
            value: values.isEmpty ? nil : SyncCounterMath.saturatingSum(values),
            isLowerBound: !values.isEmpty && incomplete)
    }

    /// Both Cost and provider grids consume the same daily totals, including missing/lower-bound states.
    static func dailyTotals(_ series: [TokenActivitySeries]) -> [String: TokenActivityTotal] {
        let keys = Set(series.flatMap { $0.days.map(\.dayKey) })
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, Self.total(series, dayKey: $0)) })
    }

    static func window(referenceDate: Date, calendar: Calendar) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: referenceDate)
        let firstDay = calendar.date(byAdding: .day, value: -364, to: today)!
        return firstDay...today
    }

    static func sourceRevision(_ snapshots: [SyncedUsageSnapshot]) -> String {
        snapshots.flatMap { snapshot in
            snapshot.providers.map { provider in
                let publication = snapshot.publicationTimestamp(for: provider).timeIntervalSince1970
                return "\(snapshot.deviceID ?? "_"):\(provider.cardIdentityKey)@\(publication)"
            }
        }.sorted().joined(separator: ";")
    }

    static func knownTokens(_ day: SyncDailyPoint?) -> Int? {
        guard let day, day.tokenCountIsKnown != false, day.totalTokens >= 0 else { return nil }
        return day.totalTokens
    }

    /// Fixed logarithmic bands keep a provider's colors stable while browsing history.
    static func intensity(_ tokens: Int) -> Double {
        switch tokens {
        case ...0: 0
        case ..<100_000: 0.25
        case ..<1_000_000: 0.5
        case ..<10_000_000: 0.75
        default: 1
        }
    }

    static func series(
        providers: [ProviderUsageSnapshot],
        rollups: [CostLedgerProviderRollup]?,
        referenceDate: Date = Date()) -> [TokenActivitySeries]
    {
        providers.compactMap { provider in
            let matching = rollups?.filter { rollup in
                guard provider.providerID == rollup.providerID else { return false }
                if rollup.accountIdentityKey != nil {
                    return !Set(CostLedgerService.accountIdentityKeys(for: provider))
                        .isDisjoint(with: rollup.accountIdentityKeys)
                }
                return provider.accountEmail == rollup.accountEmail
            }
            let days: [SyncDailyPoint] = if let matching {
                // Rollups already apply device/account merge semantics. Do not merge the
                // current blob again: it is the same data and would double count it.
                Self.combine(matching.flatMap(\.dailyPoints), alreadyAggregated: true)
            } else {
                Self.snapshotDays(provider.costSummary, referenceDate: referenceDate)
            }
            let series = TokenActivitySeries(provider: provider, days: days, hasLedgerCounts: rollups != nil)
            guard days.contains(where: { Self.recordedTokens($0, series: series) != nil }) else { return nil }
            return series
        }
    }

    /// Use the same logical age mapping as the ledger when persistence is disabled.
    static func snapshotDays(
        _ summary: SyncCostSummary?,
        referenceDate: Date,
        readerTimeZone: TimeZone = .current) -> [SyncDailyPoint]
    {
        guard let summary, !summary.hasInvalidBucketTimeZoneIdentifier else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        var readerCalendar = Calendar(identifier: .gregorian)
        readerCalendar.timeZone = readerTimeZone
        guard let producerToday = formatter.date(from: summary.costDayKey(for: referenceDate)),
              let readerToday = formatter.date(from: dayKey(referenceDate, calendar: readerCalendar))
        else { return [] }
        var mapping: [String: String] = [:]
        for age in 0..<365 {
            let producer = formatter.calendar.date(byAdding: .day, value: -age, to: producerToday)!
            let reader = formatter.calendar.date(byAdding: .day, value: -age, to: readerToday)!
            mapping[formatter.string(from: producer)] = formatter.string(from: reader)
        }
        return summary.reportingPeriodDaily.compactMap { point in
            guard let key = mapping[point.dayKey] else { return nil }
            return SyncDailyPoint(
                dayKey: key,
                costUSD: 0,
                totalTokens: point.totalTokens,
                costIsKnown: false,
                tokenCountIsKnown: point.tokenCountIsKnown)
        }
    }

    static func combine(_ days: [SyncDailyPoint], alreadyAggregated: Bool = false) -> [SyncDailyPoint] {
        Dictionary(grouping: days, by: \.dayKey).map { key, values in
            SyncDailyPoint(
                dayKey: key,
                costUSD: 0,
                totalTokens: SyncCounterMath.saturatingSum(values.map {
                    alreadyAggregated ? max(0, $0.totalTokens) : self.knownTokens($0) ?? 0
                }),
                costIsKnown: false,
                tokenCountIsKnown: values.allSatisfy { self.knownTokens($0) != nil })
        }.sorted { $0.dayKey < $1.dayKey }
    }

    static func recordedTokens(_ day: SyncDailyPoint?, series: TokenActivitySeries) -> Int? {
        if let known = knownTokens(day) { return known }
        // The ledger sums only known contributions, so a positive incomplete
        // aggregate is a lower bound. Raw unavailable values are never trusted.
        guard series.hasLedgerCounts, let day, day.totalTokens > 0 else { return nil }
        return day.totalTokens
    }

    static func tokenText(_ day: SyncDailyPoint?, series: TokenActivitySeries) -> String {
        guard let value = recordedTokens(day, series: series) else { return String(localized: "Unavailable") }
        return (day?.tokenCountIsKnown == false ? "≥" : "") + value.formatted()
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Quartiles of positive days avoid a single outlier flattening a whole year's colors.
/// Tied counts always share a color; zero and unavailable remain separate states.
struct TokenActivityColorScale {
    let thresholds: [Int]

    init(values: [Int]) {
        let positive = values.filter { $0 > 0 }.sorted()
        self.thresholds = positive.isEmpty ? [] : [1, 2, 3].map {
            positive[min(positive.count - 1, (positive.count * $0) / 4)]
        }
    }

    func intensity(_ tokens: Int) -> Double {
        guard tokens > 0 else { return 0 }
        guard !self.thresholds.isEmpty else { return 0.25 }
        return 0.25 + Double(self.thresholds.count { tokens > $0 }) * 0.25
    }
}
