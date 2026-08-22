import SwiftUI

private let qrURL = "https://codexbarios.o1xhack.com"
/// Matches `CostShareCardView` dimensions (3:4 aspect, 390×520pt). Two
/// theme variants share the same canvas so users can toggle between them
/// without the resulting image dimensions changing — important for social
/// previews that cache by aspect ratio. See `CostShareCardView` for the
/// full rationale on why this size is frozen.
private let cardWidth: CGFloat = 390
private let cardHeight: CGFloat = 520

// MARK: - Cyber theme (dark / light)

struct CyberTheme {
    let bg: Color
    let headline: Color
    let headlineGlow: Color
    let heroText: Color
    let heroGlow: Color
    let accent: Color
    let accentGlow: Color
    let dim: Color
    let line: Color
    let qrInvert: Bool

    static let dark = CyberTheme(
        bg: Color(red: 0.03, green: 0.03, blue: 0.07),
        headline: Color(red: 0.0, green: 0.90, blue: 0.95),
        headlineGlow: Color(red: 0.0, green: 0.90, blue: 0.95).opacity(0.5),
        heroText: .white,
        heroGlow: Color(red: 0.95, green: 0.20, blue: 0.60).opacity(0.5),
        accent: Color(red: 0.95, green: 0.20, blue: 0.60),
        accentGlow: Color(red: 0.95, green: 0.20, blue: 0.60).opacity(0.3),
        dim: Color.white.opacity(0.35),
        line: Color.white.opacity(0.06),
        qrInvert: true
    )

    static let light = CyberTheme(
        bg: Color(red: 0.96, green: 0.96, blue: 0.98),
        headline: Color(red: 0.0, green: 0.55, blue: 0.60),
        headlineGlow: Color.clear,
        heroText: Color(red: 0.10, green: 0.10, blue: 0.12),
        heroGlow: Color.clear,
        accent: Color(red: 0.75, green: 0.15, blue: 0.45),
        accentGlow: Color.clear,
        dim: Color(red: 0.50, green: 0.50, blue: 0.55),
        line: Color.black.opacity(0.08),
        qrInvert: false
    )

    static func from(_ colorScheme: ColorScheme) -> CyberTheme {
        colorScheme == .dark ? .dark : .light
    }
}

// MARK: - Main Entry

struct CyberShareCardView: View {
    let period: SharePeriod
    let data: ShareCardData
    var theme: CyberTheme = .dark

    var body: some View {
        CyberCard(data: data, period: period, theme: theme)
    }
}

// MARK: - Helpers

private func formatUSD(_ value: Double) -> String { CostFormatting.usd(value) }

private func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
    if count >= 1_000 { return String(format: "%.0fK", Double(count) / 1_000) }
    return "\(count)"
}

private func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}

// MARK: - Cyber QR Footer (centered)

private struct CyberFooter: View {
    let theme: CyberTheme

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.headline.opacity(0.05))
                    .frame(width: 54, height: 54)

                Image(uiImage: QRCodeGenerator.generate(from: qrURL, size: 48))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .if(theme.qrInvert) { $0.colorInvert() }

                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(theme.headline.opacity(0.4), lineWidth: 1)
                    .frame(width: 54, height: 54)
                    .shadow(color: theme.headlineGlow.opacity(0.3), radius: 4)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(theme.headline)
                    .frame(width: 4, height: 4)
                    .shadow(color: theme.headlineGlow, radius: 3)
                Text("CODEXBAR")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(theme.headline)
                    .tracking(3)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Arc Gauge

private struct ArcGauge: View {
    let value: Double
    let label: String
    let color: Color
    let size: CGFloat
    let theme: CyberTheme

    var body: some View {
        // Arc gauge geometry:
        // - `trim(from: 0.15, to: 0.85)` spans 70% of the circle = 252° of arc.
        //   The remaining 30° gap at the top is where the center-label text
        //   sits — the gauge reads visually as ~5 o'clock through ~7 o'clock
        //   "opening" with the value rotating clockwise to fill it.
        // - The second circle's `to: 0.15 + 0.7 * value` overlays a partial
        //   fill proportional to `value ∈ [0, 1]` on that same 252° arc.
        //   When `value == 1`, it matches the track's endpoint at 0.85.
        // Changing the 0.15/0.85 offsets shifts the gauge's "opening" side
        // and re-aligns the center label — do NOT adjust without also
        // retuning the text alignment inside this view.
        ZStack {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(theme.line, style: StrokeStyle(lineWidth: 5, lineCap: .round))

            Circle()
                .trim(from: 0.15, to: 0.15 + 0.7 * value)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .shadow(color: color.opacity(0.5), radius: 4)

            VStack(spacing: 0) {
                Text(formatPercent(value))
                    .font(.system(size: size * 0.22, weight: .black, design: .monospaced))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: size * 0.1, design: .monospaced))
                    .foregroundStyle(theme.dim)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}

// ────────────────────────────────────────────────────────────────
// MARK: - Unified Cyber Card (all 3 periods)
// ────────────────────────────────────────────────────────────────

private struct CyberCard: View {
    let data: ShareCardData
    let period: SharePeriod
    let theme: CyberTheme

    private var heroCost: Double {
        period == .today ? data.todayCost : data.totalCost
    }

    private var heroCostIsKnown: Bool {
        period == .today ? data.todayCostIsKnown : data.totalCostIsKnown
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)

            // 1. Headline — big, centered, always single line
            Text(period.vibeHeadline)
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .foregroundStyle(theme.headline)
                .shadow(color: theme.headlineGlow, radius: 12)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)

            // 2. Token count — large, centered, subscript label
            if data.totalTokens > 0 {
                VStack(spacing: 0) {
                    Text(formatTokens(data.totalTokens))
                        .font(.system(size: 48, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(theme.heroText)
                        .shadow(color: theme.heroGlow, radius: 12)
                    Text("TOKENS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.dim)
                        .tracking(3)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            }

            // 3. Cost — medium, accent color
            Text(self.heroCostIsKnown ? formatUSD(self.heroCost) : "—")
                .font(.system(size: 20, weight: .bold, design: .monospaced).monospacedDigit())
                .foregroundStyle(theme.accent)
                .shadow(color: theme.accentGlow, radius: 6)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 22)

            if data.costCoverageIsIncomplete {
                Text("Historical cost coverage is incomplete.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.dim)
                    .padding(.top, -16)
                    .padding(.bottom, 12)
            }

            // 4. Gauge row
            HStack(spacing: 24) {
                ForEach(Array(data.displayProviders.prefix(3).enumerated()), id: \.offset) { _, p in
                    ArcGauge(value: p.share, label: p.name, color: p.color, size: 88, theme: theme)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            // 5. Provider cost row
            HStack(spacing: 0) {
                ForEach(Array(data.displayProviders.prefix(3).enumerated()), id: \.offset) { i, p in
                    if i > 0 {
                        theme.line.frame(width: 0.5, height: 24)
                    }
                    VStack(spacing: 2) {
                        Text(formatUSD(p.cost))
                            .font(.system(size: 12, weight: .bold, design: .monospaced).monospacedDigit())
                            .foregroundStyle(p.color)
                        Text(p.name)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(theme.dim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: 10)

            theme.line.frame(height: 0.5).padding(.bottom, 10)
            CyberFooter(theme: theme)
        }
        .padding(20)
        .frame(width: cardWidth, height: cardHeight)
        .background(theme.bg)
    }
}

// MARK: - Previews

#Preview("Cyber Today Dark") {
    CyberShareCardView(period: .today, data: .previewToday, theme: .dark)
}

#Preview("Cyber Today Light") {
    CyberShareCardView(period: .today, data: .previewToday, theme: .light)
}

#Preview("Cyber 7d Dark") {
    CyberShareCardView(period: .week, data: .preview7d, theme: .dark)
}

#Preview("Cyber 7d Light") {
    CyberShareCardView(period: .week, data: .preview7d, theme: .light)
}

#Preview("Cyber 30d Dark") {
    CyberShareCardView(period: .month, data: .preview, theme: .dark)
}

#Preview("Cyber 30d Light") {
    CyberShareCardView(period: .month, data: .preview, theme: .light)
}
