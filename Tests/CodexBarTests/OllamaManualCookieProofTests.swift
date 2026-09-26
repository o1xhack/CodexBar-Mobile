import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct OllamaManualCookieProofTests {
    @Test
    func `render synthetic manual cookie recovery when requested`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_OLLAMA_MANUAL_PROOF_DIR"] else { return }
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        settings.ollamaCookieSource = .manual
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let context = ProviderSettingsContext(
            provider: .ollama,
            settings: settings,
            store: store,
            statusText: { _ in nil },
            setStatusText: { _, _ in },
            lastAppActiveRunAt: { _ in nil },
            setLastAppActiveRunAt: { _, _ in },
            requestConfirmation: { _ in })
        let picker = try #require(OllamaProviderImplementation().settingsPickers(context: context)
            .first { $0.id == "ollama-cookie-source" })
        // Reconstruct the previous descriptor with its empty Manual trailing content.
        let before = ProviderSettingsPickerDescriptor(
            id: picker.id,
            title: picker.title,
            subtitle: picker.subtitle,
            dynamicSubtitle: picker.dynamicSubtitle,
            binding: picker.binding,
            options: picker.options,
            isVisible: nil,
            onChange: nil)
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for width in [540, 620] {
            try self.capture(
                before,
                error: .noSessionCookie,
                width: width,
                destination: output.appendingPathComponent("before-\(width).png"))
            try self.capture(
                picker,
                error: .manualCookieHeaderEmpty,
                width: width,
                destination: output.appendingPathComponent("after-\(width).png"))
        }
    }

    private func capture(
        _ picker: ProviderSettingsPickerDescriptor,
        error: OllamaUsageError,
        width: Int,
        destination: URL) throws
    {
        let view = NSHostingView(rootView: VStack(alignment: .leading, spacing: 8) {
            Text("Ollama · synthetic empty Manual configuration").font(.headline).padding(.horizontal, 20)
            Form {
                Section("Connection") {
                    ProviderSettingsPickerRowView(picker: picker)
                }
            }.formStyle(.grouped).frame(height: 150)
            Text(error.localizedDescription).font(.caption).padding(.horizontal, 20)
        }.frame(width: CGFloat(width), height: 280).background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(x: 0, y: 0, width: width, height: 280)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        defer { window.contentView = nil }
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
    }
}
