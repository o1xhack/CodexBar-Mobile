import CodexBarCore
import Foundation

struct QoderProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .qoder
    private var plugin: PluginCookieProviderImplementation {
        PluginCookieProviderImplementation(
            spec: QoderProviderDescriptor.spec,
            fieldActions: { context in
                [.openURL(
                    id: "qoder-open-usage",
                    title: "Open Qoder Usage",
                    url: Self.usageDashboardURL(settings: context.settings))]
            },
            trailingText: {
                let entries = [nil, "qoder.com", "qoder.com.cn"].compactMap { domain in
                    CookieHeaderCache.loadForDisplay(provider: .qoder, scope: domain.map {
                        .providerVariant($0)
                    })
                }
                return entries.max(by: { $0.storedAt < $1.storedAt }).map {
                    ProviderCookieSourceUI.cachedTrailingText(entry: $0)
                }
            })
    }

    @MainActor
    static func usageDashboardURL(settings: SettingsStore) -> URL {
        QoderProviderDescriptor.dashboardURL(
            settings: settings.resolvedCookieSettings(provider: .qoder, tokenOverride: nil),
            sourceLabel: nil)
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        self.plugin.tokenAccountsVisibility(context: context, support: support)
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        self.plugin.applyTokenAccountCookieSource(settings: settings)
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        self.plugin.settingsPickers(context: context)
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        self.plugin.settingsFields(context: context)
    }
}
