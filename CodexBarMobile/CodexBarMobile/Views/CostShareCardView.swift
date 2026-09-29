import SwiftUI

private let qrURL = "https://codexbarios.o1xhack.com"
/// Fixed share-card dimensions (3:4 aspect, iPhone 15-ish width). This is the
/// canvas size the card renders INTO — `UIImage` export + social-network
/// previews depend on the exact pixel dimensions after 2×/3× scale. Changing
/// either value would re-crop every existing share-template layout in the
/// card body, reflow the QR-footer spacing, and (if shipped to users) make
/// previous screenshots in user chats look inconsistent next to new ones.
/// If you absolutely need a new size, clone the view and keep this one.
private let cardWidth: CGFloat = 390
private let cardHeight: CGFloat = 520

// MARK: - Theme colors (light / dark)

struct ShareCardTheme {
    let background: Color
    let foreground: Color
    let secondary: Color
    let tertiary: Color
    let cardBackground: Color
    let divider: Color
    let isDark: Bool

    static let light = ShareCardTheme(
        background: .white,
        foreground: .black,
        secondary: Color(red: 0.56, green: 0.56, blue: 0.58),
        tertiary: Color(red: 0.78, green: 0.78, blue: 0.80),
        cardBackground: Color(red: 0.95, green: 0.95, blue: 0.97),
        divider: Color(red: 0.78, green: 0.78, blue: 0.78),
        isDark: false)

    static let dark = ShareCardTheme(
        background: Color(red: 0.08, green: 0.08, blue: 0.10),
        foreground: .white,
        secondary: Color(red: 0.56, green: 0.56, blue: 0.58),
        tertiary: Color(red: 0.44, green: 0.44, blue: 0.46),
        cardBackground: Color.white.opacity(0.08),
        divider: Color.white.opacity(0.12),
        isDark: true)

    static func from(_ colorScheme: ColorScheme) -> ShareCardTheme {
        colorScheme == .dark ? .dark : .light
    }
}

// MARK: - Main Entry Point

struct CostShareCardView: View {
    let period: SharePeriod
    let data: ShareCardData
    var theme: ShareCardTheme = .light
    var style: ShareCardStyleOption = .classic
    var heatmapData: HeatmapShareData?

    init(
        period: SharePeriod,
        data: ShareCardData,
        theme: ShareCardTheme = .light,
        style: ShareCardStyleOption = .classic,
        heatmapData: HeatmapShareData? = nil)
    {
        self.period = period
        self.data = data
        self.theme = theme
        self.style = style
        self.heatmapData = heatmapData
    }

    var body: some View {
        switch self.style {
        case .classic:
            switch self.period {
            case .today: TodayCard(data: self.data, theme: self.theme)
            case .week: ChartCard(
                    data: self.data,
                    periodLabel: String(localized: "7 Days"),
                    is30Day: false,
                    theme: self.theme)
            case .month: ChartCard(
                    data: self.data,
                    periodLabel: String(localized: "30 Days"),
                    is30Day: true,
                    theme: self.theme)
            }
        case .cyber:
            CyberShareCardView(period: self.period, data: self.data, theme: self.theme.isDark ? .dark : .light)
        case .heatmap:
            HeatmapShareCardView(data: self.heatmapData ?? .preview, theme: self.theme)
        }
    }
}

// MARK: - Shared Components

private func formatUSD(_ value: Double) -> String {
    CostFormatting.usd(value)
}

// Share cards use a visually-compact token glyph (no "tokens" suffix — the
// suffix is implied by the card layout). Kept separate from
// `CostFormatting.tokens(_:)` which includes the localized unit label.
private func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1000 {
        return String(format: "%.0fK", Double(count) / 1000)
    }
    return "\(count)"
}

private func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}

private struct QRFooter: View {
    let theme: ShareCardTheme

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: QRCodeGenerator.generate(from: qrURL, size: 64))
                .interpolation(.none)
                .resizable()
                .frame(width: 64, height: 64)
                .if(self.theme.isDark) { $0.colorInvert() }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text("CodexBar")
                    .font(.subheadline.bold())
                    .foregroundStyle(self.theme.foreground)
                Text(String(localized: "Track your AI coding costs"))
                    .font(.caption)
                    .foregroundStyle(self.theme.secondary)
                Text("codexbarios.o1xhack.com")
                    .font(.caption2)
                    .foregroundStyle(self.theme.tertiary)
            }
            Spacer()
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let theme: ShareCardTheme

    var body: some View {
        VStack(spacing: 2) {
            Text(self.title)
                .font(.caption2)
                .foregroundStyle(self.theme.secondary)
            Text(self.value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(self.theme.foreground)
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Stacked Bar (provider-colored segments)

private struct StackedBar: View {
    let providers: [ShareCardData.ProviderRow]
    let totalHeight: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        if self.providers.allSatisfy(\.shareIsKnown) {
            // Largest at bottom (stable baseline), smallest at top
            VStack(spacing: 0) {
                ForEach(Array(self.providers.reversed().enumerated()), id: \.offset) { _, p in
                    Rectangle()
                        .fill(p.color)
                        .frame(height: max(0, self.totalHeight * p.share))
                }
            }
            .frame(height: self.totalHeight)
            .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius))
        }
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Today Card (Provider-focused, Style 7 based)

// ────────────────────────────────────────────────────────────────

private struct TodayCard: View {
    let data: ShareCardData
    let theme: ShareCardTheme

    var body: some View {
        // Compute once per render; `displayProviders` is O(providers.count) but is invoked
        // in multiple ForEach blocks below — cache locally to avoid repeated recomputation.
        let providers = self.data.displayProviders
        return VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "AI Coding Spend"))
                        .font(.caption)
                        .foregroundStyle(self.theme.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    Text(String(localized: "Today"))
                        .font(.title3.bold())
                        .foregroundStyle(self.theme.foreground)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .padding(.bottom, 16)

            // Hero number
            Text(self.data.todayCostDisplayValue)
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(self.theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

            if self.data.costCoverageIsIncomplete {
                Text("Historical cost coverage is incomplete.")
                    .font(.caption2)
                    .foregroundStyle(self.theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if self.data.totalTokens > 0 {
                Text("\(formatTokens(self.data.totalTokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(self.theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer().frame(height: 18)

            // Provider breakdown (top 3 + Others)
            VStack(spacing: 8) {
                ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(provider.color)
                            .frame(width: 8, height: 8)
                        Text(provider.name)
                            .font(.subheadline)
                            .foregroundStyle(self.theme.foreground)
                        Spacer()
                        Text(formatUSD(provider.cost))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(self.theme.secondary)
                        if provider.shareIsKnown {
                            Text(formatPercent(provider.share))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(self.theme.foreground)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.bottom, 14)

            // Share bar
            if providers.allSatisfy(\.shareIsKnown) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(providers.enumerated()), id: \.offset) { _, p in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(p.color)
                                .frame(width: max(4, geo.size.width * p.share))
                        }
                    }
                }
                .frame(height: 8)
                .padding(.bottom, 14)
            }

            // Top models (compact)
            if !self.data.topModels.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "Top Models"))
                        .font(.caption.bold())
                        .foregroundStyle(self.theme.secondary)
                    // iOS 1.9.0+: top 5 (was 3) to match the rest of the cap rule.
                    ForEach(Array(self.data.topModels.prefix(5).enumerated()), id: \.offset) { _, model in
                        HStack {
                            Text(model.label)
                                .font(.caption)
                                .foregroundStyle(self.theme.foreground)
                                .lineLimit(1)
                            Spacer()
                            Text(formatPercent(model.share))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(self.theme.secondary)
                        }
                    }
                }
                .padding(10)
                .background(self.theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            self.theme.divider.frame(height: 0.5).padding(.vertical, 10)
            QRFooter(theme: self.theme)
        }
        .padding(24)
        .frame(width: cardWidth, height: cardHeight)
        .background(ClassicCardBackground(theme: self.theme))
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Chart Card (7-day / 30-day, Style 6 based)

// ────────────────────────────────────────────────────────────────

private struct ChartCard: View {
    let data: ShareCardData
    let periodLabel: String
    let is30Day: Bool
    let theme: ShareCardTheme

    private var barHeight: CGFloat {
        self.is30Day ? 140 : 150
    }

    var body: some View {
        // Compute once per render; referenced in 30+ StackedBar instantiations plus legend row.
        let providers = self.data.displayProviders
        return VStack(spacing: 0) {
            // Header — matches Today card style
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "AI Coding Spend"))
                        .font(.caption)
                        .foregroundStyle(self.theme.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    Text(self.periodLabel)
                        .font(.title3.bold())
                        .foregroundStyle(self.theme.foreground)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .padding(.bottom, 14)

            // Hero number
            Text(self.data.totalCostIsKnown ? formatUSD(self.data.totalCost) : "—")
                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(self.theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            if self.data.costCoverageIsIncomplete {
                Text("Historical cost coverage is incomplete.")
                    .font(.caption2)
                    .foregroundStyle(self.theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -8)
                    .padding(.bottom, 4)
            }

            // Chart area — stacked bars by provider color
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: self.is30Day ? 2 : 6) {
                    ForEach(Array(self.data.dailyBars.enumerated()), id: \.offset) { _, day in
                        let totalH = self.data.chartBarHeight(for: day, chartHeight: self.barHeight)
                        StackedBar(
                            providers: providers,
                            totalHeight: totalH,
                            cornerRadius: self.is30Day ? 2 : 4)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: self.barHeight)
                .padding(.horizontal, self.is30Day ? 6 : 10)
                .padding(.top, 10)

                // X-axis labels — separate row below bars
                if self.is30Day {
                    HStack {
                        Text("1")
                        Spacer()
                        Text("10")
                        Spacer()
                        Text("20")
                        Spacer()
                        Text("30")
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(self.theme.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(self.data.dailyBars.enumerated()), id: \.offset) { _, day in
                            Text(day.label)
                                .font(.system(size: 9))
                                .foregroundStyle(self.theme.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
            .background(self.theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 12)

            // Bottom metrics
            HStack(spacing: 0) {
                MetricPill(
                    title: String(localized: "Tokens"),
                    value: formatTokens(self.data.totalTokens),
                    theme: self.theme)
                    .frame(maxWidth: .infinity)
                self.theme.divider.frame(width: 0.5, height: 28)
                if self.is30Day {
                    MetricPill(
                        title: String(localized: "Active Days"),
                        value: "\(self.data.activeDays)",
                        theme: self.theme)
                        .frame(maxWidth: .infinity)
                    self.theme.divider.frame(width: 0.5, height: 28)
                }
                MetricPill(
                    title: String(localized: "Avg/Day"),
                    value: self.data.avgDailyCostIsKnown ? formatUSD(self.data.avgDailyCost) : "—",
                    theme: self.theme)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 8)

            // Provider legend. Two columns keep six sources readable on the
            // fixed export canvas instead of compressing every name into an
            // ambiguous one-line strip.
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                alignment: .leading,
                spacing: 5)
            {
                ForEach(Array(providers.enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 5) {
                        Circle().fill(p.color).frame(width: 6, height: 6)
                        Text(p.name)
                            .font(.system(size: 10))
                            .foregroundStyle(self.theme.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 3)
                        if p.shareIsKnown {
                            Text(formatPercent(p.share))
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(self.theme.secondary)
                        }
                    }
                }
            }

            Spacer()

            self.theme.divider.frame(height: 0.5).padding(.vertical, 8)
            QRFooter(theme: self.theme)
        }
        .padding(24)
        .frame(width: cardWidth, height: cardHeight)
        .background(ClassicCardBackground(theme: self.theme))
    }
}

private struct ClassicCardBackground: View {
    let theme: ShareCardTheme

    var body: some View {
        LinearGradient(
            colors: [self.theme.background, Color.orange.opacity(self.theme.isDark ? 0.08 : 0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}

// MARK: - Previews

#Preview("Today - Light") {
    CostShareCardView(period: .today, data: .previewToday, theme: .light)
}

#Preview("Today - Dark") {
    CostShareCardView(period: .today, data: .previewToday, theme: .dark)
        .padding().background(Color.gray)
}

#Preview("7 Days - Light") {
    CostShareCardView(period: .week, data: .preview7d, theme: .light)
}

#Preview("7 Days - Dark") {
    CostShareCardView(period: .week, data: .preview7d, theme: .dark)
        .padding().background(Color.gray)
}

#Preview("30 Days - Dark") {
    CostShareCardView(period: .month, data: .preview, theme: .dark)
        .padding().background(Color.gray)
}
