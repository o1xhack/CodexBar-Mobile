import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MenuBarLayoutPaletteTests {
    @Test(arguments: [320.0, 440.0, 600.0])
    func `palette preserves the natural width of a token that fits the pane`(_ width: Double) throws {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        defer { store.stopSharedSpendDashboardPublication() }
        let editor = MenuBarLayoutEditor(settings: settings, store: store)
        let token = MenuBarLayoutToken.windowResetAbsolute(window: .session)
        let label = MenuBarLayoutChipLabel(
            title: token.editorLabel(provider: nil), systemImage: token.editorSystemImage, isSelected: false)
        let natural = try Self.render(label)
        let palette = try Self.render(editor.palette(MenuBarLayoutPaletteGroup(
            id: "time", title: "", tokens: [token], includesLineBreak: false))
            .frame(width: width, alignment: .leading))

        if width == 440, let path = ProcessInfo.processInfo.environment["CODEXBAR_LAYOUT_PALETTE_PROOF"] {
            let proof = try Self.render(editor.palette(MenuBarLayoutPaletteGroup(
                id: "time", title: "Time", tokens: MenuBarLayoutPaletteTokens.time, includesLineBreak: false))
                .frame(width: width, alignment: .leading).padding(20).background(.white))
            let png = try #require(proof.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
        }

        // Compare painted chip extents, not font-specific pixels or a stored screenshot golden.
        #expect(natural.pixelsWide < Int(width))
        #expect(Self.paintedWidth(palette) >= Self.paintedWidth(natural) - 1)
    }

    private static func render(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.light))
        renderer.scale = 1
        return try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
    }

    private static func paintedWidth(_ image: NSBitmapImageRep) -> Int {
        (0..<image.pixelsWide).last { x in
            (0..<image.pixelsHigh).contains { (image.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.05 }
        }.map { $0 + 1 } ?? 0
    }
}
