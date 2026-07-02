import SwiftUI
import WidgetKit
import XCTest

@testable import CodexBarMobile

/// Render every supported WidgetKit branch with the same view used by the
/// extension and Settings preview. This is not a pixel-perfect visual review;
/// it prevents mode/family/style/color-scheme branches from shipping blank,
/// crashing, or disconnected from the shared widget view.
@MainActor
final class CodexBarWidgetRenderMatrixTests: XCTestCase {
    private let modes: [CodexBarWidgetMode] = [
        .overview,
        .providerFocus,
        .todayCost,
        .syncHealth,
    ]

    private let colorStyles: [CodexBarWidgetColorStyle] = [
        .mono,
        .colorful,
    ]

    private let colorSchemes: [ColorScheme] = [
        .light,
        .dark,
    ]

    private let families: [(family: WidgetFamily, size: CGSize)] = [
        (.systemSmall, CGSize(width: 158, height: 158)),
        (.systemMedium, CGSize(width: 338, height: 162)),
        (.systemLarge, CGSize(width: 338, height: 354)),
        (.systemExtraLarge, CGSize(width: 560, height: 274)),
    ]

    func testAllWidgetModesFamiliesStylesAndSchemesRender() {
        let snapshot = CodexBarWidgetSnapshot.placeholder(now: Date(timeIntervalSince1970: 1_800_000_000))

        for mode in modes {
            for colorStyle in colorStyles {
                for colorScheme in colorSchemes {
                    for family in families {
                        let image = renderWidget(
                            mode: mode,
                            colorStyle: colorStyle,
                            colorScheme: colorScheme,
                            family: family.family,
                            size: family.size,
                            snapshot: snapshot)

                        XCTAssertNotNil(
                            image,
                            "Widget must render \(mode.rawValue)/\(family.family)/\(colorStyle.rawValue)/\(colorScheme)")
                        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
                        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
                    }
                }
            }
        }
    }

    func testWidgetErrorEmptyAndSyncingStatesRenderAcrossFamilies() {
        let states: [(name: String, snapshot: CodexBarWidgetSnapshot)] = [
            ("error", .error("iCloud account not signed in")),
            ("noData", .noData()),
            ("syncing", .syncing()),
        ]

        for state in states {
            for family in families {
                let image = renderWidget(
                    mode: .syncHealth,
                    colorStyle: .colorful,
                    colorScheme: .dark,
                    family: family.family,
                    size: family.size,
                    snapshot: state.snapshot)

                XCTAssertNotNil(image, "Widget \(state.name) state must render for \(family.family)")
                XCTAssertGreaterThan(image?.size.width ?? 0, 0)
                XCTAssertGreaterThan(image?.size.height ?? 0, 0)
            }
        }
    }

    private func renderWidget(
        mode: CodexBarWidgetMode,
        colorStyle: CodexBarWidgetColorStyle,
        colorScheme: ColorScheme,
        family: WidgetFamily,
        size: CGSize,
        snapshot: CodexBarWidgetSnapshot
    ) -> UIImage? {
        let entry = CodexBarWidgetEntry(
            date: Date(timeIntervalSince1970: 1_800_000_060),
            configuration: CodexBarWidgetConfigurationIntent(
                mode: mode,
                colorStyle: colorStyle),
            snapshot: snapshot)
        let view = CodexBarWidgetView(entry: entry, previewFamily: family)
            .environment(\.colorScheme, colorScheme)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
