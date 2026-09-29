import SwiftUI

/// The exported Vibe poster keeps the same frozen 3:4 canvas as Classic so
/// switching templates never changes the social-share aspect ratio.
struct CyberShareCardView: View {
    let period: SharePeriod
    let data: ShareCardData
    var theme: CyberTheme = .dark

    var body: some View {
        VibeShareCard(period: self.period, data: self.data, theme: self.theme)
    }
}

struct CyberTheme {
    let background: [Color]
    let foreground: Color
    let secondary: Color
    let surface: Color
    let accent: Color
    let qrBackground: Color

    static let dark = CyberTheme(
        background: [
            Color(red: 0.05, green: 0.06, blue: 0.13),
            Color(red: 0.12, green: 0.08, blue: 0.24),
            Color(red: 0.04, green: 0.16, blue: 0.24),
        ],
        foreground: .white,
        secondary: .white.opacity(0.62),
        surface: .white.opacity(0.10),
        accent: Color(red: 0.43, green: 0.84, blue: 1),
        qrBackground: .white)

    static let light = CyberTheme(
        background: [
            Color(red: 0.93, green: 0.96, blue: 1),
            Color(red: 0.92, green: 0.89, blue: 1),
            Color(red: 0.87, green: 0.97, blue: 0.98),
        ],
        foreground: Color(red: 0.08, green: 0.09, blue: 0.15),
        secondary: Color(red: 0.28, green: 0.29, blue: 0.38),
        surface: .white.opacity(0.55),
        accent: Color(red: 0.08, green: 0.48, blue: 0.78),
        qrBackground: .white)
}

private struct VibeShareCard: View {
    let period: SharePeriod
    let data: ShareCardData
    let theme: CyberTheme

    private var heroCost: String {
        self.period == .today ? self.data.todayCostDisplayValue : self.data.totalCostDisplayValue
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: self.theme.background,
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 35)
                .offset(x: 150, y: -220)
            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 40)
                .offset(x: -170, y: 230)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("CodexBar")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text(self.period.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(self.theme.surface, in: Capsule())
                }

                Text(String(localized: "AI activity, beautifully summarized."))
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .padding(.top, 24)
                    .frame(maxWidth: 330, alignment: .leading)

                if self.data.totalTokens > 0 {
                    Text(Self.compactTokens(self.data.totalTokens))
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)
                        .padding(.top, 14)
                    Text(String(localized: "tokens recorded"))
                        .font(.subheadline)
                        .foregroundStyle(self.theme.secondary)
                }

                HStack(spacing: 10) {
                    VibeMetric(title: String(localized: "Spend"), value: self.heroCost, theme: self.theme)
                    VibeMetric(
                        title: String(localized: "Active Days"),
                        value: "\(self.data.activeDays)",
                        theme: self.theme)
                }
                .padding(.top, 20)

                if self.data.costCoverageIsIncomplete {
                    Text(String(localized: "Historical cost coverage is incomplete."))
                        .font(.caption2)
                        .foregroundStyle(self.theme.secondary)
                        .padding(.top, 8)
                }

                VStack(spacing: 10) {
                    ForEach(Array(self.data.displayProviders.prefix(4).enumerated()), id: \.offset) { _, provider in
                        HStack(spacing: 10) {
                            Circle().fill(provider.color).frame(width: 8, height: 8)
                            Text(provider.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(provider.cost, format: .currency(code: "USD"))
                                .font(.subheadline.monospacedDigit())
                            if provider.shareIsKnown {
                                Text(provider.share, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(self.theme.secondary)
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(14)
                .background(self.theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 16)

                Spacer(minLength: 12)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Your AI activity, at a glance"))
                            .font(.caption.weight(.medium))
                        Text("codexbarios.o1xhack.com")
                            .font(.caption2)
                            .foregroundStyle(self.theme.secondary)
                    }
                    Spacer()
                    Image(uiImage: QRCodeGenerator.generate(from: "https://codexbarios.o1xhack.com", size: 46))
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 46, height: 46)
                        .padding(4)
                        .background(self.theme.qrBackground, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .foregroundStyle(self.theme.foreground)
            .padding(22)
        }
        .frame(width: 390, height: 520)
    }

    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1000 { return String(format: "%.0fK", Double(value) / 1000) }
        return "\(value)"
    }
}

private struct VibeMetric: View {
    let title: String
    let value: String
    let theme: CyberTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.title)
                .font(.caption)
                .foregroundStyle(self.theme.secondary)
            Text(self.value)
                .font(.title3.bold().monospacedDigit())
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(self.theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Vibe Dark") {
    CyberShareCardView(period: .month, data: .preview, theme: .dark)
}

#Preview("Vibe Light") {
    CyberShareCardView(period: .month, data: .preview, theme: .light)
}
