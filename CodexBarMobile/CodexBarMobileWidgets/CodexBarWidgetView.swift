import SwiftUI
import WidgetKit

struct CodexBarWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
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
            palette.background
        }
    }

    private var palette: CodexBarWidgetPalette {
        CodexBarWidgetPalette(colorScheme: colorScheme)
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
        VStack(alignment: .leading, spacing: 9) {
            header(title: titleForMode, compact: true)
            Spacer(minLength: 0)
            switch entry.configuration.mode {
            case .overview:
                heroMetric(
                    value: percentText(entry.snapshot.maxUsagePercent),
                    label: String(localized: "Max Usage"),
                    systemImage: "gauge.with.dots.needle.67percent",
                    progress: entry.snapshot.maxUsagePercent)
            case .providerFocus:
                providerHero(entry.snapshot.topProviders.first)
            case .todayCost:
                heroMetric(
                    value: costText(entry.snapshot.todayCostUSD),
                    label: String(localized: "Today"),
                    systemImage: "dollarsign.circle",
                    progress: nil)
            case .syncHealth:
                heroMetric(
                    value: syncValue,
                    label: relativeSyncText,
                    systemImage: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.icloud",
                    progress: nil)
            }
            Spacer(minLength: 0)
            footerLine
        }
        .padding(14)
    }

    private var mediumLoadedView: some View {
        VStack(alignment: .leading, spacing: 11) {
            header(title: titleForMode, compact: false)
            switch entry.configuration.mode {
            case .overview:
                heroPair
                providerRows(limit: 2)
            case .providerFocus:
                providerHero(entry.snapshot.topProviders.first)
                providerRows(limit: 2)
            case .todayCost:
                heroMetric(
                    value: costText(entry.snapshot.todayCostUSD),
                    label: String(localized: "Today"),
                    systemImage: "dollarsign.circle",
                    progress: nil)
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
        VStack(alignment: .leading, spacing: 13) {
            header(title: String(localized: "Dashboard"), compact: false)
            metricStrip
            divider
            providerRows(limit: 4)
            divider
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
                .foregroundStyle(palette.primary)
            Text(String(localized: "Reading iCloud sync data"))
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(palette.primary)
            Text(String(localized: "Open CodexBar on your iPhone after your Mac syncs usage."))
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
    }

    private var errorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: String(localized: "Sync Error"), compact: false)
            Spacer()
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.primary)
            Text(localizedErrorMessage)
                .font(.caption)
                .foregroundStyle(palette.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
    }

    private func header(title: String, compact: Bool) -> some View {
        HStack(spacing: 7) {
            Text("CodexBar")
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Rectangle()
                .fill(palette.separator)
                .frame(width: 1, height: compact ? 10 : 12)
            Text(title)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            if entry.snapshot.errorCount > 0 {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var heroPair: some View {
        HStack(alignment: .top, spacing: 12) {
            heroMetric(
                value: costText(entry.snapshot.todayCostUSD),
                label: String(localized: "Today"),
                systemImage: "dollarsign.circle",
                progress: nil)
            verticalDivider(height: 48)
            compactMetric(
                label: String(localized: "Max Usage"),
                value: percentText(entry.snapshot.maxUsagePercent),
                systemImage: "gauge.with.dots.needle.67percent")
            verticalDivider(height: 48)
            compactMetric(
                label: String(localized: "Sync"),
                value: syncValue,
                systemImage: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.icloud")
        }
    }

    private var metricStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            compactMetric(
                label: String(localized: "Today"),
                value: costText(entry.snapshot.todayCostUSD),
                systemImage: "dollarsign.circle")
            verticalDivider(height: 42)
            compactMetric(
                label: String(localized: "30 Days"),
                value: costText(entry.snapshot.thirtyDayCostUSD),
                systemImage: "calendar")
            verticalDivider(height: 42)
            compactMetric(
                label: String(localized: "Max Usage"),
                value: percentText(entry.snapshot.maxUsagePercent),
                systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    private func compactMetric(label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(palette.secondary)

            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .privacySensitive()
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerHero(_ provider: CodexBarWidgetProviderSummary?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let provider {
                HStack(spacing: 7) {
                    providerMark(provider)
                    Text(provider.providerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(percentText(provider.usagePercent))
                    .font(.system(size: family == .systemSmall ? 30 : 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .privacySensitive()
                    .widgetAccentable()
                progressLine(provider.usagePercent, height: family == .systemSmall ? 4 : 3)
                Text(provider.displaySubtitle ?? String(localized: "Usage"))
                    .font(.caption2)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            } else {
                heroMetric(
                    value: String(localized: "No provider data"),
                    label: String(localized: "Usage"),
                    systemImage: "gauge.open.with.lines.needle.33percent",
                    progress: nil)
            }
        }
    }

    private func heroMetric(
        value: String,
        label: String,
        systemImage: String,
        progress: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .foregroundStyle(palette.secondary)

            Text(value)
                .font(.system(size: family == .systemSmall ? 29 : 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .privacySensitive()
                .widgetAccentable()

            if let progress {
                progressLine(progress, height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerRows(limit: Int) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(entry.snapshot.topProviders.prefix(limit).enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    divider
                }
                providerRow(provider)
            }
            if entry.snapshot.topProviders.isEmpty {
                Text(String(localized: "No provider data"))
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func providerRow(_ provider: CodexBarWidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                providerMark(provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.providerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    Text(provider.displaySubtitle ?? relativeText(since: provider.lastUpdated))
                        .font(.caption2)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(percentText(provider.usagePercent))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .privacySensitive()
                    .widgetAccentable()
            }
            progressLine(provider.usagePercent, height: 3)
        }
    }

    private var costBreakdownRows: some View {
        VStack(spacing: 8) {
            labeledValue(String(localized: "Today"), costText(entry.snapshot.todayCostUSD))
            divider
            labeledValue(String(localized: "30 Days"), costText(entry.snapshot.thirtyDayCostUSD))
            divider
            labeledValue(String(localized: "Tokens"), tokensText(entry.snapshot.todayTokens))
        }
    }

    private var syncHealthRows: some View {
        VStack(spacing: 8) {
            labeledValue(String(localized: "Last Sync"), relativeSyncText)
            divider
            labeledValue(String(localized: "Providers"), String(format: String(localized: "%d providers"), entry.snapshot.providerCount))
            divider
            labeledValue(String(localized: "Devices"), String(format: String(localized: "%d devices"), entry.snapshot.deviceCount))
            if entry.snapshot.errorCount > 0 {
                divider
                labeledValue(String(localized: "Errors"), String(format: String(localized: "%d errors"), entry.snapshot.errorCount))
            }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .privacySensitive()
                .widgetAccentable()
        }
    }

    private func providerMark(_ provider: CodexBarWidgetProviderSummary) -> some View {
        ZStack {
            Circle()
                .strokeBorder(provider.isError ? palette.primary : palette.secondary, lineWidth: 1.4)
            if provider.isError {
                Circle()
                    .fill(palette.primary.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .padding(2)
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
    }

    private func progressLine(_ percent: Double?, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let fraction = min(1, max(0, (percent ?? 0) / 100))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.progressTrack)
                Capsule()
                    .fill(palette.primary)
                    .frame(width: max(height, proxy.size.width * fraction))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func verticalDivider(height: CGFloat) -> some View {
        Rectangle()
            .fill(palette.separator)
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var footerLine: some View {
        Text(relativeSyncText)
            .font(.caption2)
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
    }

    private var syncValue: String {
        entry.snapshot.isStale ? String(localized: "Stale") : String(localized: "Healthy")
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
}

private struct CodexBarWidgetPalette {
    let colorScheme: ColorScheme

    var background: Color {
        colorScheme == .dark
            ? Color(red: 0.02, green: 0.02, blue: 0.02)
            : Color(red: 0.97, green: 0.97, blue: 0.96)
    }

    var primary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.88)
    }

    var secondary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.58)
            : Color.black.opacity(0.52)
    }

    var separator: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.10)
    }

    var progressTrack: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.12)
    }
}

struct CodexBarWidgetViewPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            CodexBarWidgetView(entry: .preview(mode: .overview))
                .previewDisplayName("Small Light")
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .light)
            CodexBarWidgetView(entry: .preview(mode: .syncHealth))
                .previewDisplayName("Small Dark")
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .environment(\.colorScheme, .dark)
            CodexBarWidgetView(entry: .preview(mode: .providerFocus))
                .previewDisplayName("Medium Light")
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .environment(\.colorScheme, .light)
            CodexBarWidgetView(entry: .preview(mode: .todayCost))
                .previewDisplayName("Medium Dark")
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .environment(\.colorScheme, .dark)
            CodexBarWidgetView(entry: .preview(mode: .overview))
                .previewDisplayName("Large Light")
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .environment(\.colorScheme, .light)
            CodexBarWidgetView(entry: .preview(mode: .syncHealth, snapshot: .error("iCloud account not signed in")))
                .previewDisplayName("Large Dark")
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .environment(\.colorScheme, .dark)
        }
    }
}

private extension CodexBarWidgetEntry {
    static func preview(
        mode: CodexBarWidgetMode,
        snapshot: CodexBarWidgetSnapshot = .placeholder()
    ) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(
            date: .now,
            configuration: CodexBarWidgetConfigurationIntent(mode: mode),
            snapshot: snapshot)
    }
}
