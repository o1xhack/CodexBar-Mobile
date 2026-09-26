import Foundation

public struct QoderProviderSettings: ProviderCookieSettings {
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?
    public let manualCookieOrigin: String?

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?) {
        self.init(cookieSource: cookieSource, manualCookieHeader: manualCookieHeader, manualCookieOrigin: nil)
    }

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?, manualCookieOrigin: String?) {
        self.cookieSource = cookieSource
        let site = QoderCookieRouting.site(forManualCookieHeader: manualCookieHeader)
        // Invalid captures never become origin-less credentials in the generic broker.
        self.manualCookieHeader = site == nil ? nil : manualCookieHeader
        self.manualCookieOrigin = manualCookieOrigin ?? site?.webOrigin
    }
}

public enum QoderProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.qoder
    public typealias Section = QoderProviderSettings
}

extension ProviderSettingsSnapshot {
    public typealias QoderProviderSettings = CodexBarCore.QoderProviderSettings
    public var qoder: QoderProviderSettings? {
        self[QoderProviderSettingsKey.self]
    }

    public static func make(qoder: QoderProviderSettings?) -> Self {
        self.make(qoder, for: QoderProviderSettingsKey.self)
    }
}

extension ProviderSettingsSnapshotContribution {
    public static func qoder(_ section: QoderProviderSettings) -> Self {
        Self(section, for: QoderProviderSettingsKey.self)
    }
}
