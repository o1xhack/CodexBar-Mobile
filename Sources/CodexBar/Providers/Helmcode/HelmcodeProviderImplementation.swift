import CodexBarCore
import Foundation

struct HelmcodeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .helmcode

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        let cookies: CookieProviderSettings = context.settings.resolvedCookieSettings(
            provider: self.id, tokenOverride: context.tokenOverride)
        return .init(HelmcodeProviderSettings(
            cookieSource: cookies.cookieSource,
            manualCookieHeader: cookies.manualCookieHeader,
            manualTenant: context.settings.helmcodeManualTenant), for: HelmcodeProviderSettingsKey.self)
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        PluginCookieProviderImplementation(spec: HelmcodeProviderDescriptor.spec).settingsPickers(context: context) + [
            ProviderSettingsPickerDescriptor(
                id: "helmcode-manual-tenant",
                title: "Manual cookie tenant",
                subtitle: "The pasted header is sent only to this tenant.",
                binding: context.binding(\.helmcodeManualTenant),
                options: [
                    .init(id: "helmcode", title: "Helmcode Cloud"),
                    .init(id: "nanBuilders", title: "NaN Builders"),
                ],
                isVisible: { context.settings.helmcodeCookieSource == .manual },
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        PluginCookieProviderImplementation(spec: HelmcodeProviderDescriptor.spec).settingsFields(context: context)
    }
}

extension SettingsStore {
    var helmcodeCookieHeader: String {
        get { self[providerConfig: .helmcode, field: .cookieHeader] }
        set { self[providerConfig: .helmcode, field: .cookieHeader] = newValue }
    }

    var helmcodeCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .helmcode, fallback: .auto) }
        set { self.setCookieSource(newValue, provider: .helmcode) }
    }

    var helmcodeManualTenant: String {
        get { self.configSnapshot.providerConfig(for: .helmcode)?.region == "nanBuilders" ? "nanBuilders" : "helmcode" }
        set { self.updateProviderConfig(provider: .helmcode) { $0.region = newValue } }
    }
}
