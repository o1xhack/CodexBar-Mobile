import CodexBarSync
import SwiftUI

struct CodexServiceMixView: View {
    let summary: SyncCostSummary
    private var rows: [(String, Double)] {
        var values: [String: Double] = [:]
        for day in self.summary.reportingPeriodDaily where day.costIsKnown != false {
            for entry in day.serviceBreakdowns where entry.costUSD.isFinite && entry.costUSD > 0 {
                values[entry.label, default: 0] += entry.costUSD
            }
        }
        return values.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }

    var body: some View {
        if !self.rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Codex Service Mix")).font(.headline)
                Text(String(localized: "Service costs in the current Mac sync window."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(self.rows, id: \.0) { row in
                    HStack {
                        Text(row.0)
                        Spacer()
                        Text(row.1, format: .currency(code: self.summary.currencyCode ?? "USD"))
                    }.font(.subheadline)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
