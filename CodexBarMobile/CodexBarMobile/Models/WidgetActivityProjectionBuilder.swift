import CodexBarSync
import Foundation

/// Runs in the app after its normal history aggregation, never in the widget.
enum WidgetActivityProjectionBuilder {
    static func make(
        series: [TokenActivitySeries],
        latestSyncAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current) -> WidgetActivityProjection
    {
        guard !series.isEmpty else {
            return WidgetActivityProjection(
                version: WidgetActivityProjection.schemaVersion,
                state: .noData,
                generatedAt: now,
                latestSyncAt: latestSyncAt,
                sources: [])
        }

        let providerIDs = Set(series.map { $0.provider.providerID }).sorted()
        let all = Self.source(
            id: WidgetActivityProjection.allSourceID,
            name: "All",
            series: series,
            now: now,
            calendar: calendar)
        let providers = providerIDs.compactMap { providerID -> WidgetActivitySource? in
            let matching = series.filter { $0.provider.providerID == providerID }
            guard let provider = matching.first else { return nil }
            return Self.source(
                id: providerID,
                name: providerID == "claude" ? "Claude Code" : provider.provider.providerName,
                series: matching,
                now: now,
                calendar: calendar)
        }
        return WidgetActivityProjection(
            version: WidgetActivityProjection.schemaVersion,
            state: .loaded,
            generatedAt: now,
            latestSyncAt: latestSyncAt,
            sources: [all] + providers)
    }

    private static func source(
        id: String,
        name: String,
        series: [TokenActivitySeries],
        now: Date,
        calendar: Calendar) -> WidgetActivitySource
    {
        let totals = TokenActivity.dailyTotals(series)
        let scale = TokenActivityColorScale(values: totals.values.compactMap(\.value))
        let start = TokenActivity.window(referenceDate: now, calendar: calendar).lowerBound
        let days = (0..<365).compactMap { offset -> WidgetActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = TokenActivity.dayKey(date, calendar: calendar)
            let total = totals[key]
            return WidgetActivityDay(
                key: key,
                tokens: total?.value,
                isLowerBound: total?.isLowerBound ?? false,
                intensity: total?.value.map(scale.intensity) ?? 0)
        }
        return WidgetActivitySource(id: id, name: name, days: days)
    }
}
