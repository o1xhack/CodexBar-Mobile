import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct InlineUsageDashboardLayoutTests {
    @Test(arguments: AppLanguage.allCases.filter { $0 != .system })
    func `localized statistic headings reserve their full wrapped height`(language: AppLanguage) {
        CodexBarLocalizationOverride.$appLanguage.withValue(language.rawValue) {
            let title = L("Estimated: %@", L("%@ tokens", L("Current window")))
            let columnWidth: CGFloat = 130
            let proposal = CGSize(width: columnWidth, height: .greatestFiniteMagnitude)
            let fullTitleHeight = NSHostingController(rootView: Text(title).font(.caption2)
                .fixedSize(horizontal: false, vertical: true)).sizeThatFits(in: proposal).height
            let shortTitleHeight = NSHostingController(rootView: Text("X").font(.caption2))
                .sizeThatFits(in: proposal).height
            let dashboardProposal = CGSize(width: columnWidth * 2 + 8, height: .greatestFiniteMagnitude)
            let shortHeight = NSHostingController(rootView: InlineUsageDashboardContent(model: Self.model(title: "X")))
                .sizeThatFits(in: dashboardProposal).height
            let fullHeight = NSHostingController(rootView: InlineUsageDashboardContent(model: Self.model(title: title)))
                .sizeThatFits(in: dashboardProposal).height

            #expect(
                fullHeight - shortHeight >= fullTitleHeight - shortTitleHeight - 1,
                "\(language.rawValue): the heading must fit without truncation")
            if language == .english {
                #expect(fullTitleHeight > shortTitleHeight)
            }
        }
    }

    @Test
    func `render synthetic statistics proof when requested`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_MENU_CARD_PROOF_DIR"] else { return }
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let title = L("Estimated: %@", L("%@ tokens", L("Current window")))
            let content = VStack(alignment: .leading, spacing: 12) {
                Text("Codex statistics · synthetic").font(.headline)
                InlineUsageDashboardContent(model: Self.model(title: title))
            }
            .padding(14)
            .frame(width: 296)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("statistics.png"))
        }
    }

    private static func model(title: String) -> InlineUsageDashboardModel {
        InlineUsageDashboardModel(
            accessibilityLabel: "Synthetic statistics",
            valueStyle: .tokens,
            kpis: [
                .init(title: L("Latest tokens"), value: "1K", emphasis: false),
                .init(title: title, value: "2K", emphasis: false),
            ],
            points: [],
            detailLines: [])
    }
}
