import CodexBarCore
import Foundation

extension SettingsStore {
    var kimi2UsageDataSource: ProviderSourceMode {
        get { self.configSnapshot.providerConfig(for: .kimi2)?.source ?? .auto }
        set {
            let source: ProviderSourceMode? = switch newValue {
            case .auto: .auto
            case .api: .api
            case .web: .web
            case .cli, .oauth: .auto
            }
            self.updateProviderConfig(provider: .kimi2) { entry in
                entry.source = source
            }
            self.logProviderModeChange(provider: .kimi2, field: "usageSource", value: newValue.rawValue)
        }
    }

    var kimi2APIKey: String {
        get { self.configSnapshot.providerConfig(for: .kimi2)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .kimi2) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .kimi2, field: "apiKey", value: newValue)
        }
    }

    var kimi2ManualCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .kimi2)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .kimi2) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .kimi2, field: "cookieHeader", value: newValue)
        }
    }

    var kimi2CookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .kimi2, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .kimi2) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .kimi2, field: "cookieSource", value: newValue.rawValue)
        }
    }

    func ensureKimi2AuthTokenLoaded() {}
}

extension SettingsStore {
    func kimi2SettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot.Kimi2ProviderSettings {
        self.ensureKimi2AuthTokenLoaded()
        return self.resolvedCookieSettings(
            provider: .kimi2,
            configuredSource: self.kimi2CookieSource,
            configuredHeader: self.kimi2ManualCookieHeader,
            tokenOverride: tokenOverride)
    }
}
