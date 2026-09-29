import CodexBarCore
import Foundation

extension SettingsStore {
    var museCookieHeader: String {
        get { self[providerConfig: .muse, field: .cookieHeader] }
        set { self[providerConfig: .muse, field: .cookieHeader] = newValue }
    }

    var museWebTeamID: String {
        get { self[providerConfig: .muse, field: .workspace] }
        set { self[providerConfig: .muse, field: .workspace] = newValue }
    }

    var museCookieSource: ProviderCookieSource {
        // Browser sessions are opt-in; a pasted header without an explicit source means Manual, as in the CLI.
        get {
            let header = self.providerConfig(for: .muse)?.sanitizedCookieHeader
            return self.resolvedCookieSource(provider: .muse, fallback: header == nil ? .off : .manual)
        }
        set { self.setCookieSource(newValue, provider: .muse) }
    }
}
