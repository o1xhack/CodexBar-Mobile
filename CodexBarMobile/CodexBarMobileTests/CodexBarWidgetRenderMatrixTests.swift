import SwiftUI
import UIKit
import WidgetKit
import XCTest

@testable import CodexBarMobile

/// Render every supported WidgetKit branch with the same view used by the
/// extension and Settings preview. This is not a pixel-perfect visual review;
/// it prevents mode/family/style/color-scheme branches from shipping blank,
/// flat, or disconnected from the shared widget view.
@MainActor
final class CodexBarWidgetRenderMatrixTests: XCTestCase {
    private let modes: [CodexBarWidgetMode] = [
        .overview,
        .providerFocus,
        .todayCost,
        .syncHealth,
        .quotaPace,
    ]

    private let colorStyles: [CodexBarWidgetColorStyle] = [
        .mono,
        .colorful,
    ]

    private let colorSchemes: [ColorScheme] = [
        .light,
        .dark,
    ]

    private let renderingModes: [WidgetRenderingMode] = [
        .fullColor,
        .accented,
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
                    for renderingMode in renderingModes {
                        for family in families {
                            let image = renderWidget(
                                mode: mode,
                                colorStyle: colorStyle,
                                colorScheme: colorScheme,
                                renderingMode: renderingMode,
                                family: family.family,
                                size: family.size,
                                snapshot: snapshot)

                            XCTAssertNotNil(
                                image,
                                "Widget must render \(mode.rawValue)/\(family.family)/\(colorStyle.rawValue)/\(colorScheme)/\(renderingMode)")
                            XCTAssertGreaterThan(image?.size.width ?? 0, 0)
                            XCTAssertGreaterThan(image?.size.height ?? 0, 0)

                            let context = "\(mode.rawValue)/\(family.family)/\(colorStyle.rawValue)/\(colorScheme)/\(renderingMode)"
                            guard let stats = self.assertVisibleImage(image, context: context) else {
                                continue
                            }
                            if colorStyle == .colorful, renderingMode == .fullColor {
                                XCTAssertGreaterThan(
                                    stats.maxSaturation,
                                    0.14,
                                    "Colorful widget must render visible accent color for \(context)")
                            }
                        }
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
                    renderingMode: .accented,
                    family: family.family,
                    size: family.size,
                    snapshot: state.snapshot)

                XCTAssertNotNil(image, "Widget \(state.name) state must render for \(family.family)")
                XCTAssertGreaterThan(image?.size.width ?? 0, 0)
                XCTAssertGreaterThan(image?.size.height ?? 0, 0)
                self.assertVisibleImage(image, context: "\(state.name)/\(family.family)")
            }
        }
    }

    func testTokenActivityFamiliesAndStatesRenderInHomeScreenAppearances() {
        let projection = WidgetActivityProjection.preview(now: Date(timeIntervalSince1970: 1_800_000_000))
        let states: [WidgetActivityProjection] = [
            projection,
            .state(.syncing),
            .state(.noData),
            .state(.error),
        ]
        for state in states {
            for family in families {
                for scheme in colorSchemes {
                    for mode in renderingModes {
                        let entry = WidgetActivityEntry(
                            date: projection.generatedAt,
                            sourceIDs: family.family == .systemSmall || family.family == .systemMedium
                                ? ["claude"] : ["all", "codex"],
                            projection: state)
                        let view = ZStack {
                            scheme == .dark ? Color.black : Color.white
                            WidgetActivityView(entry: entry, previewFamily: family.family)
                                .environment(\.colorScheme, scheme)
                                .environment(\.widgetRenderingMode, mode)
                        }
                        .frame(width: family.size.width, height: family.size.height)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        self.assertVisibleImage(
                            renderer.uiImage,
                            context: "activity/\(state.state)/\(family.family)/\(scheme)/\(mode)")
                    }
                }
            }
        }
    }

    func testTokenActivityLoadedLayoutsAreAvailableForVisualReview() {
        let projection = WidgetActivityProjection.preview(now: Date(timeIntervalSince1970: 1_800_000_000))
        let appearances: [(name: String, scheme: ColorScheme, mode: WidgetRenderingMode)] = [
            ("light", .light, .fullColor),
            ("dark", .dark, .fullColor),
            ("tinted", .dark, .accented),
        ]
        for family in self.families {
            for appearance in appearances {
                let entry = WidgetActivityEntry(
                    date: projection.generatedAt,
                    sourceIDs: family.family == .systemSmall || family.family == .systemMedium
                        ? ["claude"] : ["all", "codex"],
                    projection: projection)
                let view = ZStack {
                    appearance.scheme == .dark ? Color.black : Color.white
                    WidgetActivityView(entry: entry, previewFamily: family.family)
                        .environment(\.colorScheme, appearance.scheme)
                        .environment(\.widgetRenderingMode, appearance.mode)
                }
                .frame(width: family.size.width, height: family.size.height)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.uiImage else {
                    XCTFail("Could not render \(family.family)/\(appearance.name)")
                    continue
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Token Activity \(family.family) \(appearance.name)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
            }
        }
    }

    /// Research/065: every Quota Pace layout, attached for visual review.
    func testQuotaPaceLayoutsAreAvailableForVisualReview() {
        let snapshot = CodexBarWidgetSnapshot.placeholder(now: Date(timeIntervalSince1970: 1_800_000_000))
        let appearances: [(name: String, scheme: ColorScheme, mode: WidgetRenderingMode)] = [
            ("light", .light, .fullColor),
            ("dark", .dark, .fullColor),
            ("tinted", .dark, .accented),
        ]
        for family in self.families {
            for appearance in appearances {
                for colorStyle in self.colorStyles {
                    let image = self.renderWidget(
                        mode: .quotaPace,
                        colorStyle: colorStyle,
                        colorScheme: appearance.scheme,
                        renderingMode: appearance.mode,
                        family: family.family,
                        size: family.size,
                        snapshot: snapshot)
                    let context = "quotaPace/\(family.family)/\(appearance.name)/\(colorStyle.rawValue)"
                    _ = self.assertVisibleImage(image, context: context)
                    guard let image else { continue }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Quota Pace \(family.family) \(appearance.name) \(colorStyle.rawValue)"
                    attachment.lifetime = .keepAlways
                    self.add(attachment)
                }
            }
        }
    }

    func testQuotaPaceExtraLargeKeepsAnUnavailableConfiguredProvider() {
        let snapshot = CodexBarWidgetSnapshot.placeholder(now: Date(timeIntervalSince1970: 1_800_000_000))
        let selection = [
            WidgetProviderEntity(id: "codex", name: "Codex"),
            WidgetProviderEntity(id: "gemini", name: "Gemini"),
        ]
        let picked = WidgetProviderSelection.pace(from: snapshot.topProviders, selected: selection, limit: 2)
        XCTAssertEqual(picked.map(\.providerID), ["codex", "gemini"])
        XCTAssertNil(picked.last?.quotaPace)
        let entry = CodexBarWidgetEntry(
            date: Date(timeIntervalSince1970: 1_800_000_060),
            configuration: CodexBarWidgetConfigurationIntent(
                mode: .quotaPace, colorStyle: .mono, providers: selection),
            snapshot: snapshot)
        let view = ZStack {
            Color.white
            CodexBarWidgetView(entry: entry, previewFamily: .systemExtraLarge)
        }
        .frame(width: 560, height: 274)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        _ = self.assertVisibleImage(renderer.uiImage, context: "quotaPace-xl-mixed")
    }

    func testQuotaPaceWithoutPaceDataRendersTheEmptyMessage() {
        let placeholder = CodexBarWidgetSnapshot.placeholder(now: Date(timeIntervalSince1970: 1_800_000_000))
        let snapshot = CodexBarWidgetSnapshot(
            state: .loaded,
            generatedAt: placeholder.generatedAt,
            latestSyncAt: placeholder.latestSyncAt,
            deviceCount: 1,
            providerCount: 1,
            errorCount: 0,
            todayCostUSD: nil,
            thirtyDayCostUSD: nil,
            todayTokens: nil,
            maxUsagePercent: 30,
            topProviders: placeholder.topProviders.filter { $0.quotaPace == nil },
            message: nil,
            isStale: false)
        // The view takes its empty branch: nothing qualifies for the pace mode.
        XCTAssertTrue(WidgetProviderSelection.pace(from: snapshot.topProviders, selected: nil, limit: 2).isEmpty)
        for family in self.families {
            let image = self.renderWidget(
                mode: .quotaPace,
                colorStyle: .mono,
                colorScheme: .light,
                family: family.family,
                size: family.size,
                snapshot: snapshot)
            _ = self.assertVisibleImage(image, context: "quotaPace-empty/\(family.family)")
        }
    }

    func testTokenActivityUnavailableAndDuplicateSourcesRenderClearly() {
        let projection = WidgetActivityProjection.preview(now: Date(timeIntervalSince1970: 1_800_000_000))
        let cases: [(name: String, family: WidgetFamily, ids: [String])] = [
            ("removed single", .systemSmall, ["removed-provider"]),
            ("removed comparison", .systemLarge, ["all", "removed-provider"]),
            ("duplicate comparison", .systemLarge, ["codex", "codex"]),
            ("removed extra large", .systemExtraLarge, ["all", "removed-provider"]),
        ]
        for item in cases {
            guard let size = self.families.first(where: { $0.family == item.family })?.size else {
                XCTFail("Missing render size for \(item.name)")
                continue
            }
            let entry = WidgetActivityEntry(date: projection.generatedAt, sourceIDs: item.ids, projection: projection)
            let view = ZStack {
                Color.white
                WidgetActivityView(entry: entry, previewFamily: item.family)
            }
            .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            self.assertVisibleImage(renderer.uiImage, context: item.name)
        }
    }

    func testLoadedFooterLineIsAlwaysCentered() throws {
        let sourceURL = Self.sourceFileURL(
            forRelative: "CodexBarMobile/CodexBarWidgetShared/CodexBarWidgetView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private var footerAlignment: Alignment {\n        .center\n    }"),
            "The loaded `Updated ...` footer must stay centered for every widget mode and family.")
        XCTAssertFalse(
            source.contains("return .leading"),
            "Do not reintroduce mode/family-specific leading alignment for the loaded footer.")
    }

    private func renderWidget(
        mode: CodexBarWidgetMode,
        colorStyle: CodexBarWidgetColorStyle,
        colorScheme: ColorScheme,
        renderingMode: WidgetRenderingMode = .fullColor,
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
        let view = ZStack {
            // `containerBackground(for: .widget)` is supplied by WidgetKit at
            // runtime. In an off-screen ImageRenderer test it can be
            // transparent, so provide a host-like opaque fallback background
            // and let the widget content render on top.
            (colorScheme == .dark ? Color.black : Color.white)
            CodexBarWidgetView(entry: entry, previewFamily: family)
                .environment(\.colorScheme, colorScheme)
                .environment(\.widgetRenderingMode, renderingMode)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }

    private static func sourceFileURL(forRelative relativePath: String) -> URL {
        var url = URL(fileURLWithPath: #filePath)
        let parts = url.pathComponents
        guard let idx = parts.lastIndex(of: "CodexBarMobile") else {
            return URL(fileURLWithPath: relativePath)
        }
        let root = URL(fileURLWithPath: parts[..<idx].joined(separator: "/"), isDirectory: true)
        return root.appendingPathComponent(relativePath)
    }

    @discardableResult
    private func assertVisibleImage(
        _ image: UIImage?,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> RenderedImageStats? {
        guard let image else {
            XCTFail("Widget image is nil for \(context)", file: file, line: line)
            return nil
        }
        guard let stats = RenderedImageStats(image: image) else {
            XCTFail("Could not inspect widget pixels for \(context)", file: file, line: line)
            return nil
        }

        XCTAssertGreaterThan(
            stats.averageAlpha,
            0.95,
            "Widget image should be opaque for \(context)",
            file: file,
            line: line)
        XCTAssertGreaterThan(
            stats.luminanceRange,
            0.08,
            "Widget image should have visible foreground/background contrast for \(context)",
            file: file,
            line: line)
        return stats
    }
}

private struct RenderedImageStats {
    let averageAlpha: CGFloat
    let luminanceRange: CGFloat
    let maxSaturation: CGFloat

    init?(image: UIImage) {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            return nil
        }

        var minLuminance = CGFloat.greatestFiniteMagnitude
        var maxLuminance = CGFloat.leastNormalMagnitude
        var maxSaturation: CGFloat = 0
        var alphaTotal: CGFloat = 0
        var sampleCount: CGFloat = 0
        let xStride = max(1, width / 96)
        let yStride = max(1, height / 96)

        for y in stride(from: 0, to: height, by: yStride) {
            for x in stride(from: 0, to: width, by: xStride) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = CGFloat(pixels[offset]) / 255
                let green = CGFloat(pixels[offset + 1]) / 255
                let blue = CGFloat(pixels[offset + 2]) / 255
                let alpha = CGFloat(pixels[offset + 3]) / 255
                guard alpha > 0.01 else {
                    continue
                }

                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                let maxChannel = max(red, green, blue)
                let minChannel = min(red, green, blue)
                let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0

                minLuminance = min(minLuminance, luminance)
                maxLuminance = max(maxLuminance, luminance)
                maxSaturation = max(maxSaturation, saturation)
                alphaTotal += alpha
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return nil
        }

        self.averageAlpha = alphaTotal / sampleCount
        self.luminanceRange = maxLuminance - minLuminance
        self.maxSaturation = maxSaturation
    }
}
