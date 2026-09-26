import Foundation

public protocol ProviderCookieSettings: Sendable {
    var cookieSource: ProviderCookieSource { get }
    var manualCookieHeader: String? { get }
    var manualCookieOrigin: String? { get }

    init(cookieSource: ProviderCookieSource, manualCookieHeader: String?)
    init(cookieSource: ProviderCookieSource, manualCookieHeader: String?, manualCookieOrigin: String?)
}

extension ProviderCookieSettings {
    public var manualCookieOrigin: String? {
        nil
    }

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?, manualCookieOrigin _: String?) {
        self.init(cookieSource: cookieSource, manualCookieHeader: manualCookieHeader)
    }
}

public struct CookieProviderSettings: ProviderCookieSettings {
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?
    public let manualCookieOrigin: String?

    public init(cookieSource: ProviderCookieSource = .auto, manualCookieHeader: String? = nil) {
        self.init(cookieSource: cookieSource, manualCookieHeader: manualCookieHeader, manualCookieOrigin: nil)
    }

    public init(cookieSource: ProviderCookieSource, manualCookieHeader: String?, manualCookieOrigin: String?) {
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
        self.manualCookieOrigin = manualCookieOrigin
    }
}

extension ProviderSettingsSnapshot {
    public typealias CookieProviderSettings = CodexBarCore.CookieProviderSettings
}
