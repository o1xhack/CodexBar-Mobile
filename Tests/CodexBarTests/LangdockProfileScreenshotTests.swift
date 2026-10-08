import AppKit
import SweetCookieKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct LangdockProfileScreenshotTests {
    @Test
    func `render selected profile settings with synthetic data when requested`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_LANGDOCK_PROOF_DIR"] else { return }
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: #function)
        fixture.settings.updateProviderConfig(provider: .langdock) { $0.browserProfileID = "/synthetic/Edge/Profile 2" }
        let picker = PluginCookieProviderImplementation(spec: LangdockProviderDescriptor.spec).browserProfilePicker(
            browser: "edge",
            context: fixture.settingsContext(provider: .langdock),
            profiles: [.init(id: "/synthetic/Edge/Profile 2", name: "Personal (synthetic)")])
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for before in [true, false] {
            let view = NSHostingView(rootView: VStack(alignment: .leading, spacing: 12) {
                Text("Langdock · synthetic settings").font(.headline).padding(.horizontal, 20)
                Form {
                    Section("Connection") {
                        if before {
                            ProviderSettingsFieldRowView(field: .init(
                                id: "langdock-edge-profile-id",
                                title: "Edge profile ID",
                                subtitle: "Enter the Edge profile directory path for your Langdock account. " +
                                    "CodexBar reads only that profile and never switches accounts automatically.",
                                kind: .plain,
                                placeholder: "/synthetic/Edge/Profile 2",
                                binding: .constant("/synthetic/Edge/Profile 2"),
                                actions: [],
                                isVisible: nil))
                        } else {
                            ProviderSettingsPickerRowView(picker: picker)
                        }
                    }
                }.formStyle(.grouped)
            }.padding(.vertical, 16).frame(width: 620, height: 240).background(Color(nsColor: .windowBackgroundColor)))
            view.frame = NSRect(x: 0, y: 0, width: 620, height: 240)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = view
            defer { window.contentView = nil }
            window.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("langdock-settings-\(before ? "before" : "after").png"))
        }
    }
}
