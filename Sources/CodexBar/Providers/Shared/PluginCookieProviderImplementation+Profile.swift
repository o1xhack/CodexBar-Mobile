import CodexBarCore
import Foundation
import SweetCookieKit
import SwiftUI

extension PluginCookieProviderImplementation {
    @MainActor
    func browserProfilePicker(
        browser: String,
        context: ProviderSettingsContext,
        profiles: [BrowserProfile]? = nil) -> ProviderSettingsPickerDescriptor
    {
        let browser = Browser(rawValue: browser)
        let profiles = profiles ?? browser.flatMap { try? BrowserCookieClient().codexBarStores(for: $0) }?
            .map(\.profile) ?? []
        var seen = Set<String>()
        var options = [ProviderSettingsPickerOption(id: "", title: L("Select profile…"))]
        options += profiles.filter { seen.insert($0.id).inserted }.map {
            ProviderSettingsPickerOption(id: $0.id, title: $0.name)
        }
        if let saved = context.settings.providerConfig(for: self.id)?.browserProfileID,
           !saved.isEmpty, !seen.contains(saved)
        {
            options.append(.init(
                id: saved,
                title: L("Unavailable profile: %@", URL(fileURLWithPath: saved).lastPathComponent)))
        }
        return ProviderSettingsPickerDescriptor(
            id: "browser-profile",
            title: L("Browser profile"),
            subtitle: L(
                "Read only the selected %@ profile. Accounts are never selected automatically.",
                browser?.displayName ?? "browser"),
            binding: Binding(
                get: { context.settings.providerConfig(for: self.id)?.browserProfileID ?? "" },
                set: { value in
                    context.store.clearProviderState(self.id)
                    context.settings.updateProviderConfig(provider: self.id) {
                        $0.browserProfileID = value.isEmpty ? nil : value
                    }
                }),
            options: options,
            isVisible: nil,
            onChange: nil,
            trailingActions: [ProviderCookieRefreshAction.descriptor(
                provider: self.id, cookieSource: { .auto }, context: context)])
    }
}
