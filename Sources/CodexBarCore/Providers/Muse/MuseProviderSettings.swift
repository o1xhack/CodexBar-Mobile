import Foundation

public struct MuseProviderSettings: ProviderCookieSettings {
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?
    /// The dev.meta.ai team whose quota fills omitted login quotas. Nil means no team was chosen.
    public let webTeamID: String?

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?) {
        self.init(cookieSource: cookieSource, manualCookieHeader: manualCookieHeader, webTeamID: nil)
    }

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?, webTeamID: String?) {
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
        self.webTeamID = webTeamID
    }
}

public enum MuseProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.muse
    public typealias Section = MuseProviderSettings
}

extension ProviderSettingsSnapshot {
    public static func make(muse: MuseProviderSettings?) -> Self {
        self.make(muse, for: MuseProviderSettingsKey.self)
    }
}
