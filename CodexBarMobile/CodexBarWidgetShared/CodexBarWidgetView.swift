import SwiftUI
import WidgetKit

struct CodexBarWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var environmentFamily

    let entry: CodexBarWidgetEntry
    let previewFamily: WidgetFamily?

    init(entry: CodexBarWidgetEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .systemExtraLarge:
            extraLargeLoadedView
        default:
            mediumLoadedView
        }
    }

    private var smallLoadedView: some View {
        VStack(alignment: .leading, spacing: spacing.header) {
            smallModeContent
                .frame(maxHeight: .infinity, alignment: .center)
            loadedFooterLine
        }
        .padding(spacing.padding)
    }

    @ViewBuilder
    private var smallModeContent: some View {
        switch entry.configuration.mode {
        case .overview:
            heroMetric(
                value: percentText(entry.snapshot.maxUsagePercent),
                label: String(localized: "Usage"),
                systemImage: "gauge.with.dots.needle.67percent",
                progress: entry.snapshot.maxUsagePercent)
        case .providerFocus:
            providerHero(focusedProvider)
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
    }

    private var mediumLoadedView: some View {
        VStack(alignment: .leading, spacing: spacing.section) {
            mediumModeContent
            loadedFooterLine
        }
        .padding(spacing.padding)
    }

    @ViewBuilder
    private var mediumModeContent: some View {
        switch entry.configuration.mode {
        case .overview:
            metricStrip
            providerRows(providers: displayProviders, limit: 1, metric: .usage)
        case .providerFocus:
            providerHero(focusedProvider)
        case .todayCost:
            todayCostHero
            providerRows(
                providers: todayCostProviders,
                limit: 2,
                metric: .todayCost,
                emptyMessage: String(localized: "No spend today"))
        case .syncHealth:
            heroMetric(
                value: syncValue,
                label: relativeSyncText,
                systemImage: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.icloud",
                progress: nil)
            syncHealthRows(limit: 2, includeLastSync: false)
        }
    }

    private var largeLoadedView: some View {
        VStack(alignment: .leading, spacing: spacing.section) {
            largeModeContent
            Spacer(minLength: 0)
            loadedFooterLine
        }
        .padding(spacing.padding)
    }

    @ViewBuilder
    private var largeModeContent: some View {
        switch entry.configuration.mode {
        case .overview:
            metricStrip
            divider
            providerRows(
                providers: displayProviders,
                limit: 3,
                metric: .usage,
                rowMinHeight: spacing.largeProviderRowMinHeight)
            divider
            syncSummaryStrip
        case .providerFocus:
            providerHero(focusedProvider)
            divider
            providerRows(
                providers: secondaryFocusProviders,
                limit: 3,
                metric: .usage,
                rowMinHeight: spacing.largeProviderRowMinHeight)
            divider
            syncSummaryStrip
        case .todayCost:
            todayCostHero
            divider
            providerRows(
                providers: todayCostProviders,
                limit: 3,
                metric: .todayCost,
                rowMinHeight: spacing.largeProviderRowMinHeight,
                emptyMessage: String(localized: "No spend today"))
            divider
            labeledValue(String(localized: "Tokens"), tokensText(entry.snapshot.todayTokens))
        case .syncHealth:
            heroMetric(
                value: syncValue,
                label: relativeSyncText,
                systemImage: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.icloud",
                progress: nil)
            divider
            syncHealthRows(limit: entry.snapshot.errorCount > 0 ? 3 : 2, includeLastSync: false)
        }
    }

    private var extraLargeLoadedView: some View {
        VStack(alignment: .leading, spacing: spacing.section) {
            switch entry.configuration.mode {
            case .overview:
                HStack(alignment: .top, spacing: spacing.extraLargeColumn) {
                    VStack(alignment: .leading, spacing: spacing.section) {
                        metricStrip
                        divider
                        syncHealthRows(limit: 4)
                    }
                    verticalDivider(height: 170)
                    providerRows(providers: displayProviders, limit: 4, metric: .usage)
                }
            case .providerFocus:
                HStack(alignment: .top, spacing: spacing.extraLargeColumn) {
                    VStack(alignment: .leading, spacing: spacing.section) {
                        providerHero(focusedProvider)
                        divider
                        syncSummaryStrip
                    }
                    verticalDivider(height: 170)
                    providerRows(providers: secondaryFocusProviders, limit: 4, metric: .usage)
                }
            case .todayCost:
                HStack(alignment: .top, spacing: spacing.extraLargeColumn) {
                    VStack(alignment: .leading, spacing: spacing.section) {
                        todayCostHero
                        divider
                        labeledValue(String(localized: "Tokens"), tokensText(entry.snapshot.todayTokens))
                    }
                    verticalDivider(height: 170)
                    providerRows(
                        providers: todayCostProviders,
                        limit: 4,
                        metric: .todayCost,
                        emptyMessage: String(localized: "No spend today"))
                }
            case .syncHealth:
                HStack(alignment: .top, spacing: spacing.extraLargeColumn) {
                    VStack(alignment: .leading, spacing: spacing.section) {
                        heroMetric(
                            value: syncValue,
                            label: relativeSyncText,
                            systemImage: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.icloud",
                            progress: nil)
                        divider
                        syncHealthRows(limit: 3, includeLastSync: false)
                    }
                    verticalDivider(height: 170)
                    providerRows(providers: displayProviders, limit: 4, metric: .usage)
                }
            }
            loadedFooterLine
        }
        .padding(spacing.padding)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeLabel(title: String(localized: "Syncing"), systemImage: "icloud.and.arrow.down", compact: false)
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
            modeLabel(title: String(localized: "No Data"), systemImage: "macbook.and.iphone", compact: false)
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
            modeLabel(title: String(localized: "Sync Error"), systemImage: "exclamationmark.icloud", compact: false)
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

    private func modeLabel(title: String, systemImage: String, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            Text(title)
                .font(compact ? .caption.weight(.medium) : .caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Spacer(minLength: 0)
            if entry.snapshot.errorCount > 0 {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.secondary)
            }
        }
        .foregroundStyle(palette.secondary)
    }

    private var metricStrip: some View {
        HStack(alignment: .top, spacing: spacing.metricColumn) {
            compactMetric(
                label: String(localized: "Today"),
                value: costText(entry.snapshot.todayCostUSD),
                systemImage: "dollarsign.circle")
            verticalDivider(height: spacing.metricDividerHeight)
            compactMetric(
                label: String(localized: "30 Days"),
                value: costText(entry.snapshot.thirtyDayCostUSD),
                systemImage: "calendar")
            verticalDivider(height: spacing.metricDividerHeight)
            compactMetric(
                label: String(localized: "Usage"),
                value: percentValueText(entry.snapshot.maxUsagePercent),
                systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    private func compactMetric(label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: spacing.compactMetric) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(palette.secondary)

            Text(value)
                .font(compactMetricValueFont)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .privacySensitive()
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerHero(_ provider: CodexBarWidgetProviderSummary?) -> some View {
        VStack(alignment: .leading, spacing: spacing.hero) {
            if let provider {
                HStack(spacing: 7) {
                    providerMark(provider)
                    Text(provider.providerName)
                        .font(rowTitleFont)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(percentText(provider.usagePercent))
                    .font(.system(size: heroFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .privacySensitive()
                    .widgetAccentable()
                progressLine(provider.usagePercent, height: progressHeight)
                Text(providerSubtitle(provider))
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
        VStack(alignment: .leading, spacing: spacing.hero) {
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
                .font(.system(size: heroFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .privacySensitive()
                .widgetAccentable()

            if let progress {
                progressLine(progress, height: progressHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerRows(
        providers: [CodexBarWidgetProviderSummary],
        limit: Int,
        metric: ProviderRowMetric,
        rowMinHeight: CGFloat? = nil,
        emptyMessage: String = String(localized: "No provider data")
    ) -> some View {
        VStack(spacing: spacing.row) {
            ForEach(Array(providers.prefix(limit).enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    divider
                }
                providerRow(provider, metric: metric)
                    .frame(minHeight: rowMinHeight ?? 0, alignment: .center)
            }
            if providers.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var todayCostHero: some View {
        VStack(alignment: .leading, spacing: spacing.hero) {
            Text(costText(entry.snapshot.todayCostUSD))
                .font(.system(size: heroFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .privacySensitive()
                .widgetAccentable()

            Text(tokensText(entry.snapshot.todayTokens))
                .font(.caption2)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerRow(
        _ provider: CodexBarWidgetProviderSummary,
        metric: ProviderRowMetric
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                providerMark(provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.providerName)
                        .font(rowTitleFont)
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    Text(providerSubtitle(provider))
                        .font(rowSubtitleFont)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(rowMetricText(provider, metric: metric))
                    .font(rowValueFont)
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .privacySensitive()
                    .widgetAccentable()
            }
            if metric == .usage {
                progressLine(provider.usagePercent, height: rowProgressHeight)
            }
        }
    }

    private func syncHealthRows(limit: Int, includeLastSync: Bool = true) -> some View {
        let rows = syncHealthItems(includeLastSync: includeLastSync)
        return VStack(spacing: spacing.row) {
            ForEach(Array(rows.prefix(limit).enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    divider
                }
                labeledValue(item.label, item.value)
            }
        }
    }

    private func syncHealthItems(includeLastSync: Bool) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if includeLastSync {
            rows.append((String(localized: "Last Sync"), relativeSyncText))
        }
        rows.append((String(localized: "Providers"), String(format: String(localized: "%d providers"), entry.snapshot.providerCount)))
        rows.append((String(localized: "Devices"), String(format: String(localized: "%d devices"), entry.snapshot.deviceCount)))
        if entry.snapshot.errorCount > 0 {
            rows.append((String(localized: "Errors"), String(format: String(localized: "%d errors"), entry.snapshot.errorCount)))
        }
        return rows
    }

    private var syncSummaryStrip: some View {
        HStack(alignment: .top, spacing: spacing.metricColumn) {
            compactMetric(
                label: String(localized: "Last Sync"),
                value: relativeSyncText,
                systemImage: entry.snapshot.isStale ? "clock.badge.exclamationmark" : "checkmark.icloud")
            verticalDivider(height: spacing.metricDividerHeight)
            compactMetric(
                label: String(localized: "Providers"),
                value: String(format: String(localized: "%d providers"), entry.snapshot.providerCount),
                systemImage: "person.2")
            verticalDivider(height: spacing.metricDividerHeight)
            compactMetric(
                label: String(localized: "Devices"),
                value: String(format: String(localized: "%d devices"), entry.snapshot.deviceCount),
                systemImage: "macbook.and.iphone")
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
                .font(rowValueFont)
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
        .frame(width: providerMarkSize, height: providerMarkSize)
        .accessibilityHidden(true)
    }

    private func progressLine(_ percent: Double?, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let fraction = min(1, max(0, (percent ?? 0) / 100))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.progressTrack)
                if percent != nil, fraction > 0 {
                    Capsule()
                        .fill(palette.primary)
                        .frame(width: proxy.size.width * fraction)
                        .widgetAccentable()
                }
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
            .font(footerFont)
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var loadedFooterLine: some View {
        if shouldShowLoadedFooterLine {
            footerLine
        }
    }

    private var shouldShowLoadedFooterLine: Bool {
        switch (entry.configuration.mode, family) {
        case (.syncHealth, _),
             (.overview, .systemLarge),
             (.overview, .systemExtraLarge),
             (.providerFocus, .systemLarge),
             (.providerFocus, .systemExtraLarge):
            false
        default:
            true
        }
    }

    private var spacing: CodexBarWidgetSpacing {
        CodexBarWidgetSpacing(family: family)
    }

    private var family: WidgetFamily {
        previewFamily ?? environmentFamily
    }

    private var heroFontSize: CGFloat {
        switch family {
        case .systemSmall: 34
        case .systemMedium: 28
        case .systemLarge: 31
        case .systemExtraLarge: 34
        default: 28
        }
    }

    private var progressHeight: CGFloat {
        switch family {
        case .systemSmall: 5
        case .systemExtraLarge: 5
        default: 4
        }
    }

    private var rowProgressHeight: CGFloat {
        family == .systemExtraLarge ? 4 : 3
    }

    private var providerMarkSize: CGFloat {
        family == .systemExtraLarge ? 10 : 9
    }

    private var compactMetricValueFont: Font {
        switch family {
        case .systemExtraLarge:
            .callout.weight(.semibold).monospacedDigit()
        default:
            .caption.weight(.semibold).monospacedDigit()
        }
    }

    private var rowTitleFont: Font {
        switch family {
        case .systemExtraLarge:
            .callout.weight(.semibold)
        default:
            .caption.weight(.semibold)
        }
    }

    private var rowSubtitleFont: Font {
        switch family {
        case .systemExtraLarge:
            .caption
        default:
            .caption2
        }
    }

    private var rowValueFont: Font {
        switch family {
        case .systemExtraLarge:
            .callout.weight(.semibold).monospacedDigit()
        default:
            .caption.weight(.semibold).monospacedDigit()
        }
    }

    private var footerFont: Font {
        switch family {
        case .systemExtraLarge:
            .caption
        default:
            .caption2
        }
    }

    private var syncValue: String {
        entry.snapshot.isStale ? String(localized: "Stale") : String(localized: "Healthy")
    }

    private var displayProviders: [CodexBarWidgetProviderSummary] {
        let providers = entry.snapshot.topProviders
        return providers.filter { !$0.isError } + providers.filter(\.isError)
    }

    private var focusedProvider: CodexBarWidgetProviderSummary? {
        displayProviders.first
    }

    private var secondaryFocusProviders: [CodexBarWidgetProviderSummary] {
        Array(displayProviders.dropFirst())
    }

    private var todayCostProviders: [CodexBarWidgetProviderSummary] {
        displayProviders
            .filter { ($0.todayCostUSD ?? 0) > 0 }
            .sorted { lhs, rhs in
            let lhsCost = lhs.todayCostUSD ?? 0
            let rhsCost = rhs.todayCostUSD ?? 0
            if lhsCost == rhsCost {
                return (lhs.usagePercent ?? 0) > (rhs.usagePercent ?? 0)
            }
            return lhsCost > rhsCost
        }
    }

    private func providerSubtitle(_ provider: CodexBarWidgetProviderSummary) -> String {
        if provider.isError {
            return String(localized: "Sync Error")
        }
        return provider.displaySubtitle ?? relativeText(since: provider.lastUpdated)
    }

    private func rowMetricText(
        _ provider: CodexBarWidgetProviderSummary,
        metric: ProviderRowMetric
    ) -> String {
        switch metric {
        case .usage:
            return percentValueText(provider.usagePercent)
        case .todayCost:
            return costText(provider.todayCostUSD)
        case .thirtyDayCost:
            return costText(provider.thirtyDayCostUSD)
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

    private func percentValueText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", min(100, max(0, value)))
    }

    private func compact(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private enum ProviderRowMetric: Equatable {
    case usage
    case todayCost
    case thirtyDayCost
}

private struct CodexBarWidgetSpacing {
    let padding: CGFloat
    let header: CGFloat
    let section: CGFloat
    let row: CGFloat
    let hero: CGFloat
    let compactMetric: CGFloat
    let metricColumn: CGFloat
    let metricDividerHeight: CGFloat
    let extraLargeColumn: CGFloat
    let largeProviderRowMinHeight: CGFloat?

    init(family: WidgetFamily) {
        switch family {
        case .systemSmall:
            padding = 10
            header = 6
            section = 8
            row = 6
            hero = 6
            compactMetric = 4
            metricColumn = 8
            metricDividerHeight = 34
            extraLargeColumn = 10
            largeProviderRowMinHeight = nil
        case .systemLarge:
            padding = 17
            header = 8
            section = 12
            row = 7
            hero = 7
            compactMetric = 5
            metricColumn = 12
            metricDividerHeight = 39
            extraLargeColumn = 16
            largeProviderRowMinHeight = 52
        case .systemExtraLarge:
            padding = 22
            header = 10
            section = 14
            row = 10
            hero = 9
            compactMetric = 6
            metricColumn = 16
            metricDividerHeight = 46
            extraLargeColumn = 22
            largeProviderRowMinHeight = nil
        default:
            padding = 14
            header = 7
            section = 10
            row = 7
            hero = 7
            compactMetric = 5
            metricColumn = 10
            metricDividerHeight = 36
            extraLargeColumn = 12
            largeProviderRowMinHeight = nil
        }
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
            CodexBarWidgetView(entry: .preview(mode: .overview))
                .previewDisplayName("Extra Large Light")
                .previewContext(WidgetPreviewContext(family: .systemExtraLarge))
                .environment(\.colorScheme, .light)
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
