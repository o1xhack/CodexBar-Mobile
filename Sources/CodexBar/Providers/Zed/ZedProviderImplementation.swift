import CodexBarCore

struct ZedProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .zed

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .init(CookieProviderSettings(
            cookieSource: context.settings.zedCookieSource,
            manualCookieHeader: context.settings.zedCookieHeader), for: ZedProviderSettingsKey.self)
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        [ProviderCookieSourceUI.picker(
            id: "zed-cookie-source",
            context: context,
            source: \.zedCookieSource,
            allowsOff: true,
            subtitles: {
                .init(
                    auto: "Imports a Chrome session for Zed token spend and edit predictions.",
                    manual: "Uses the pasted browser session for Zed token spend and edit predictions.",
                    off: "Uses the Zed editor login. Token spend requires browser cookies.")
            })]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "zed-cookie",
            title: "Zed cookie",
            subtitle: "Paste the Cookie request header from zed.dev.",
            kind: .secure,
            placeholder: "Cookie: …",
            binding: context.binding(\.zedCookieHeader),
            actions: [],
            isVisible: { context.settings.zedCookieSource == .manual })]
    }
}

extension SettingsStore {
    var zedCookieHeader: String {
        get { self[providerConfig: .zed, field: .cookieHeader] }
        set { self[providerConfig: .zed, field: .cookieHeader] = newValue }
    }

    var zedCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .zed, fallback: .off) }
        set { self.setCookieSource(newValue, provider: .zed) }
    }
}
