import AppKit
import CodexBarCore

@MainActor
enum ProviderBrandIcon {
    enum Style: Hashable {
        case monochrome
        case brand
    }

    private static let size = NSSize(width: 18, height: 18)
    private static var cache: [Style: [UsageProvider: NSImage]] = [:]

    /// Lazy-loaded resource bundle for provider icons.
    private static let resourceBundle: Bundle = {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return Bundle.module
        }
        // SwiftPM creates a CodexBar_CodexBar.bundle for resources in the CodexBar target.
        if let bundleURL = Bundle.main.url(forResource: "CodexBar_CodexBar", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL)
        {
            return bundle
        }
        // Fallback to main bundle for development/testing.
        return Bundle.main
    }()

    static func image(for provider: UsageProvider, style: Style = .monochrome) -> NSImage? {
        if let cached = self.cache[style]?[provider] {
            return cached
        }

        let baseName = ProviderDescriptorRegistry.descriptor(for: provider).branding.iconResourceName
        let bundle = self.resourceBundle
        // Only explicitly curated brand assets have reliable original colors. Existing provider
        // SVGs are often white silhouettes, so they must remain templates in both appearances.
        // Providers can share a monochrome resource while representing different products.
        let brandResourceName = "Brand-ProviderIcon-" + provider.rawValue
        let brandImage: NSImage? = style == .brand ? ["svg", "png"].lazy.compactMap { fileExtension in
            bundle.url(forResource: brandResourceName, withExtension: fileExtension)
                .flatMap { NSImage(contentsOf: $0) }
        }.first : nil
        guard let image = brandImage ?? bundle.url(forResource: baseName, withExtension: "svg")
            .flatMap({ NSImage(contentsOf: $0) }) else { return nil }

        image.size = self.size
        image.isTemplate = brandImage == nil
        self.cache[style, default: [:]][provider] = image
        return image
    }

    static func resetCacheForTesting() {
        self.cache.removeAll()
    }
}
