import CodexBarSync
import SwiftUI

/// The current producer window; older cost-ledger entries do not invent request counts.
struct SyncedDailyActivityView: View {
    let summary: SyncCostSummary
    @State private var showsAll = false

    private var sortedDays: [SyncDailyPoint] {
        self.summary.reportingPeriodDaily.sorted { $0.dayKey > $1.dayKey }
    }

    private var visibleDays: [SyncDailyPoint] {
        self.showsAll ? self.sortedDays : Array(self.sortedDays.prefix(7))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Daily activity")).font(.headline)
            Text(String(localized: "From the current Mac sync window. Missing counts are shown as unavailable."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(self.visibleDays, id: \.dayKey) { point in
                VStack(alignment: .leading, spacing: 6) {
                    Text(point.dayKey).font(.subheadline.bold().monospacedDigit())
                    ViewThatFits(in: .horizontal) {
                        HStack { self.metrics(point) }
                        VStack(alignment: .leading, spacing: 4) { self.metrics(point) }
                    }
                    .font(.caption.monospacedDigit())
                }
                if point.dayKey != self.visibleDays.last?.dayKey { Divider() }
            }
            if self.sortedDays.count > 7 {
                Button { self.showsAll.toggle() } label: {
                    Text(self.showsAll ? String(localized: "Show fewer days") : String(localized: "Show all days"))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("synced-daily-activity")
    }

    @ViewBuilder
    private func metrics(_ point: SyncDailyPoint) -> some View {
        Text(String(localized: "Requests") + ": " + Self.requestText(point))
        Text(String(localized: "Tokens") + ": " + Self.tokenText(point))
        Text(String(localized: "Cost") + ": " + Self.costText(point, currencyCode: self.summary.currencyCode ?? "USD"))
    }

    static func requestText(_ point: SyncDailyPoint) -> String {
        guard let count = point.requestCount, count >= 0 else { return String(localized: "Unavailable") }
        return count.formatted()
    }

    static func tokenText(_ point: SyncDailyPoint) -> String {
        guard point.tokenCountIsKnown != false, point.totalTokens >= 0 else { return String(localized: "Unavailable") }
        return point.totalTokens.formatted()
    }

    static func costText(_ point: SyncDailyPoint, currencyCode: String) -> String {
        guard point.costIsKnown != false, point.costUSD.isFinite else { return String(localized: "Unavailable") }
        return (point.isEstimated == true ? "≈ " : "") + point.costUSD.formatted(.currency(code: currencyCode))
    }
}
