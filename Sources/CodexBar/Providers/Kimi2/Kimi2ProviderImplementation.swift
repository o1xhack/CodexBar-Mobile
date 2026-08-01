import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct Kimi2ProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .kimi2

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.sourceLabel(for: context.provider)
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.kimi2UsageDataSource
        _ = settings.kimi2APIKey
        _ = settings.kimi2CookieSource
        _ = settings.kimi2ManualCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .kimi2(context.settings.kimi2SettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.kimi2UsageDataSource.rawValue
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        switch context.settings.kimi2UsageDataSource {
        case .api: .api
        case .web: .web
        case .auto, .cli, .oauth: .auto
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.kimi2UsageDataSource.rawValue },
            set: { raw in
                context.settings.kimi2UsageDataSource = ProviderSourceMode(rawValue: raw) ?? .auto
            })
        let usageOptions = [
            ProviderSettingsPickerOption(id: ProviderSourceMode.auto.rawValue, title: "Auto"),
            ProviderSettingsPickerOption(id: ProviderSourceMode.api.rawValue, title: "API key"),
            ProviderSettingsPickerOption(id: ProviderSourceMode.web.rawValue, title: "Browser cookies"),
        ]

        let cookieBinding = Binding(
            get: { context.settings.kimi2CookieSource.rawValue },
            set: { raw in
                context.settings.kimi2CookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let options = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.kimi2CookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies.",
                manual: "Paste a cookie header or the kimi-auth token value.",
                off: "Kimi2 cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "kimi2-usage-source",
                title: "Usage source",
                subtitle: "Auto tries your configured API key, then a signed-in Kimi2 Code CLI credential, " +
                    "then browser cookies.",
                binding: usageBinding,
                options: usageOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard context.settings.kimi2UsageDataSource == .auto else { return nil }
                    let label = context.store.sourceLabel(for: .kimi2)
                    return label == "auto" ? nil : label
                }),
            ProviderSettingsPickerDescriptor(
                id: "kimi2-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies.",
                dynamicSubtitle: subtitle,
                binding: cookieBinding,
                options: options,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "kimi2-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. You can also provide KIMI2_CODE_API_KEY.",
                kind: .secure,
                placeholder: "Paste Kimi2 Code API key...",
                binding: context.stringBinding(\.kimi2APIKey),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "kimi2-open-api-docs",
                        title: "Open API docs",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://www.kimi.com/code/docs/en/") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "kimi2-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: \u{2026}\n\nor paste the kimi-auth token value",
                binding: context.stringBinding(\.kimi2ManualCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "kimi2-open-console",
                        title: "Open Console",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://www.kimi.com/code/console") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.kimi2CookieSource == .manual },
                onActivate: { context.settings.ensureKimi2AuthTokenLoaded() }),
        ]
    }
}
