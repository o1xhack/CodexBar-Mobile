import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct SpendActivityAppearanceTests {
    @Test(arguments: [ColorSchemeContrast.standard, .increased])
    func `dark activity becomes brighter as usage rises while zero stays quiet`(contrast: ColorSchemeContrast) throws {
        let palette = SpendActivityPalette(colorScheme: .dark, contrast: contrast)
        let luminances = try (0...4).map { try Self.luminance(palette.color(forLevel: $0)) }
        for level in 1...4 {
            #expect(luminances[level] > luminances[level - 1])
            #expect(Self.contrast(luminances[level], against: Self.darkBackground) >= 3)
        }
        #expect(Self.contrast(luminances[0], against: Self.darkBackground) < 2)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func `missing history is distinct from confirmed zero in both appearances`(scheme: ColorScheme) throws {
        let palette = SpendActivityPalette(colorScheme: scheme)
        let empty = try Self.luminance(palette.color(forLevel: 0))
        let missing = try Self.luminance(palette.unavailableFill)
        let stroke = try Self.luminance(palette.unavailableStroke)
        #expect(empty != missing)
        #expect(Self.contrast(stroke, against: missing) >= 3)
    }

    @Test
    func `month labels clamp to the grid without cutting off the last month`() {
        #expect(SpendActivityMonthLabelsLayout.originX(offset: 515, labelWidth: 30, gridWidth: 520) == 490)
        #expect(SpendActivityMonthLabelsLayout.originX(offset: 10, labelWidth: 30, gridWidth: 520) == 10)
        #expect(SpendActivityMonthLabelsLayout.originX(offset: 0, labelWidth: 30, gridWidth: 20) == 0)
    }

    private static let darkBackground = 0.016807375752887384 // sRGB #232323.

    private static func contrast(_ luminance: Double, against background: Double) -> Double {
        (max(luminance, background) + 0.05) / (min(luminance, background) + 0.05)
    }

    private static func luminance(_ color: Color) throws -> Double {
        let color = try #require(NSColor(color).usingColorSpace(.sRGB))
        let components = [color.redComponent, color.greenComponent, color.blueComponent].map { value in
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return zip(components, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
