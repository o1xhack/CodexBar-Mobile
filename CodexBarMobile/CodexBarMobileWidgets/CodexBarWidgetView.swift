import SwiftUI
import WidgetKit

struct CodexBarWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: CodexBarWidgetEntry

    var body: some View {
        Group {
            switch entry.snapshot.state {
            case .placeholder:
                loadedView
            case .syncing:
                loadingView
            case .noData:
                emptyView
            case .error:
                errorView
            case .loaded:
                loadedView
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.15, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var loadedView: some View {
        switch family {
        case .systemSmall:
            smallLoadedView
        case .systemMedium:
            mediumLoadedView
        case .systemLarge:
            largeLoadedView
        default:
            mediumLoadedView
        }
    }

    private var smallLoadedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: titleForMode, compact: true)
            Spacer(minLength: 0)
            switch entry.configuration.mode {
            case .overview:
                heroMetric(
                    value: percentText(entry.snapshot.maxUsagePercent),
                    label: String(localized: "Max Usage"),
                    systemImage: "gauge.with.dots.needle.67percent",
                    color: usageColor(entry.snapshot.maxUsagePercent))
            case .providerFocus:
                providerHero(entry.snapshot.topProviders.first)
            case .todayCost:
                heroMetric(
                    value: costText(entry.snapshot.todayCostUSD),
                    label: String(localized: "Today"),
                    systemImage: "dollarsign.circle.fill",
                    color: .green)
            case .syncHealth:
                heroMetric(
                    value: entry.snapshot.isStale ? String(localized: "Stale") : String(localized: "Healthy"),
                    label: relativeSyncText,
                    systemImage: entry.snapshot.isStale ? "exclamationmark.triangle.fill" : "checkmark.icloud.fill",
                    color: entry.snapshot.isStale ? .orange : .cyan)
            }
            Spacer(minLength: 0)
            footerLine
        }
        .padding(14)
    }

    private var mediumLoadedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: titleForMode, compact: false)
            switch entry.configuration.mode {
            case .overview:
                metricStrip
                providerRows(limit: 2)
            case .providerFocus:
                providerRows(limit: 3)
            case .todayCost:
                metricStrip
                costBreakdownRows
            case .syncHealth:
                syncHealthRows
            }
            Spacer(minLength: 0)
            footerLine
        }
        .padding(14)
    }

    private var largeLoadedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(title: String(localized: "Dashboard"), compact: false)
            metricStrip
            providerRows(limit: 4)
            syncHealthRows
            Spacer(minLength: 0)
            footerLine
        }
        .padding(16)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: String(localized: "Syncing"), compact: false)
            Spacer()
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(String(localized: "Reading iCloud sync data"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: String(localized: "No Data"), compact: false)
            Spacer()
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(String(localized: "Open CodexBar on your iPhone after your Mac syncs usage."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
    }

    private var errorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: String(localized: "Sync Error"), compact: false)
            Spacer()
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.orange)
            Text(localizedErrorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
    }

    private func header(title: String, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(title)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if entry.snapshot.errorCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.primary)
    }

    private var metricStrip: some View {
        HStack(spacing: 8) {
            metricTile(
                title: String(localized: "Today"),
                value: costText(entry.snapshot.todayCostUSD),
                systemImage: "dollarsign.circle.fill",
                color: .green)
            metricTile(
                title: String(localized: "Max Usage"),
                value: percentText(entry.snapshot.maxUsagePercent),
                systemImage: "gauge.with.dots.needle.67percent",
                color: usageColor(entry.snapshot.maxUsagePercent))
            metricTile(
                title: String(localized: "Sync"),
                value: entry.snapshot.isStale ? String(localized: "Stale") : String(localized: "Healthy"),
                systemImage: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.icloud.fill",
                color: entry.snapshot.isStale ? .orange : .cyan)
        }
    }

    private func metricTile(
        title: String,
        value: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .privacySensitive()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func providerHero(_ provider: CodexBarWidgetProviderSummary?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let provider {
                HStack(spacing: 8) {
                    providerDot(provider)
                    Text(provider.providerName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(percentText(provider.usagePercent))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(usageColor(provider.usagePercent))
                    .lineLimit(1)
                    .privacySensitive()
                Text(provider.displaySubtitle ?? String(localized: "Usage"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                heroMetric(
                    value: String(localized: "No provider data"),
                    label: String(localized: "Usage"),
                    systemImage: "gauge.open.with.lines.needle.33percent",
                    color: .cyan)
            }
        }
    }

    private func heroMetric(
        value: String,
        label: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .privacySensitive()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func providerRows(limit: Int) -> some View {
        VStack(spacing: 8) {
            ForEach(entry.snapshot.topProviders.prefix(limit)) { provider in
                HStack(spacing: 8) {
                    providerDot(provider)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.providerName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(provider.displaySubtitle ?? relativeText(since: provider.lastUpdated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(percentText(provider.usagePercent))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(usageColor(provider.usagePercent))
                        .lineLimit(1)
                        .privacySensitive()
                }
            }
            if entry.snapshot.topProviders.isEmpty {
                Text(String(localized: "No provider data"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var costBreakdownRows: some View {
        VStack(spacing: 8) {
            labeledValue(String(localized: "Today"), costText(entry.snapshot.todayCostUSD), color: .green)
            labeledValue(String(localized: "30 Days"), costText(entry.snapshot.thirtyDayCostUSD), color: .mint)
            labeledValue(String(localized: "Tokens"), tokensText(entry.snapshot.todayTokens), color: .cyan)
        }
    }

    private var syncHealthRows: some View {
        VStack(spacing: 8) {
            labeledValue(String(localized: "Last Sync"), relativeSyncText, color: entry.snapshot.isStale ? .orange : .cyan)
            labeledValue(String(localized: "Providers"), String(format: String(localized: "%d providers"), entry.snapshot.providerCount), color: .indigo)
            labeledValue(String(localized: "Devices"), String(format: String(localized: "%d devices"), entry.snapshot.deviceCount), color: .purple)
            if entry.snapshot.errorCount > 0 {
                labeledValue(String(localized: "Errors"), String(format: String(localized: "%d errors"), entry.snapshot.errorCount), color: .orange)
            }
        }
    }

    private func labeledValue(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .privacySensitive()
        }
    }

    private var footerLine: some View {
        Text(relativeSyncText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var titleForMode: String {
        switch entry.configuration.mode {
        case .overview: String(localized: "Overview")
        case .providerFocus: String(localized: "Provider Focus")
        case .todayCost: String(localized: "Today Cost")
        case .syncHealth: String(localized: "Sync Health")
        }
    }

    private var relativeSyncText: String {
        guard let latestSyncAt = entry.snapshot.latestSyncAt else {
            return String(localized: "No recent sync")
        }
        let relative = relativeText(since: latestSyncAt)
        return String(format: String(localized: "Updated %@ ago"), relative)
    }

    private func relativeText(since date: Date) -> String {
        let interval = max(0, entry.date.timeIntervalSince(date))
        if interval < 60 {
            return String(localized: "just now")
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        if interval < 60 * 60 {
            formatter.allowedUnits = [.minute]
        } else if interval < 60 * 60 * 24 {
            formatter.allowedUnits = [.hour]
        } else {
            formatter.allowedUnits = [.day]
        }
        return formatter.string(from: interval) ?? String(localized: "just now")
    }

    private var localizedErrorMessage: String {
        guard let message = entry.snapshot.message else {
            return String(localized: "Try again after iCloud is available.")
        }
        switch message {
        case "Network unavailable":
            return String(localized: "Network unavailable")
        case "iCloud account not signed in":
            return String(localized: "iCloud account not signed in")
        case "iCloud storage quota exceeded":
            return String(localized: "iCloud storage quota exceeded")
        default:
            return message
        }
    }

    private func costText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func tokensText(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000 {
            return "\(compact(Double(value) / 1_000_000)) \(String(localized: "M tokens"))"
        }
        if value >= 1_000 {
            return "\(compact(Double(value) / 1_000)) \(String(localized: "K tokens"))"
        }
        return "\(value.formatted()) \(String(localized: "tokens"))"
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return String(localized: "No usage") }
        return String(format: String(localized: "%.0f%% used"), min(100, max(0, value)))
    }

    private func compact(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func providerDot(_ provider: CodexBarWidgetProviderSummary) -> some View {
        Circle()
            .fill(provider.isError ? .orange : usageColor(provider.usagePercent))
            .frame(width: 9, height: 9)
    }

    private func usageColor(_ value: Double?) -> Color {
        guard let value else { return .cyan }
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        if value >= 45 { return .yellow }
        return .cyan
    }
}

#Preview(as: .systemSmall) {
    CodexBarStatusWidget()
} timeline: {
    CodexBarWidgetEntry(
        date: .now,
        configuration: CodexBarWidgetConfigurationIntent(mode: .overview),
        snapshot: .placeholder())
    CodexBarWidgetEntry(
        date: .now,
        configuration: CodexBarWidgetConfigurationIntent(mode: .todayCost),
        snapshot: .placeholder())
}

#Preview(as: .systemMedium) {
    CodexBarStatusWidget()
} timeline: {
    CodexBarWidgetEntry(
        date: .now,
        configuration: CodexBarWidgetConfigurationIntent(mode: .providerFocus),
        snapshot: .placeholder())
}

#Preview(as: .systemLarge) {
    CodexBarStatusWidget()
} timeline: {
    CodexBarWidgetEntry(
        date: .now,
        configuration: CodexBarWidgetConfigurationIntent(mode: .overview),
        snapshot: .placeholder())
    CodexBarWidgetEntry(
        date: .now,
        configuration: CodexBarWidgetConfigurationIntent(mode: .syncHealth),
        snapshot: .error("iCloud account not signed in"))
}
