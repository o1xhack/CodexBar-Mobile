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
        let view = CodexBarWidgetView(entry: entry, previewFamily: family)
            .environment(\.colorScheme, colorScheme)
            .environment(\.widgetRenderingMode, renderingMode)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
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
