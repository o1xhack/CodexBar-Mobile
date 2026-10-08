import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct SpendBrandRenderingTests {
    @Test
    func `provider artwork keeps its brand color under an unrelated tint`() throws {
        let renderer = ImageRenderer(content: SpendProviderIcon(provider: .claude, size: 64).tint(.purple))
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        var warmPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                if color.redComponent > color.blueComponent + 0.1 { warmPixels += 1 }
            }
        }
        #expect(warmPixels > 100)
    }
}
