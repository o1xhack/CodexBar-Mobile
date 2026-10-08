import Foundation
#if os(macOS)
import SweetCookieKit
#endif

public struct ProviderBrowserProfile: Sendable, Equatable {
    public let browserID: String
    public let profileID: String

    public init(browserID: String, profileID: String) {
        self.browserID = browserID
        self.profileID = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if os(macOS)
    static func selectedStore(_ selection: Self, from stores: [BrowserCookieStore]) throws -> BrowserCookieStore {
        let matching = stores.filter {
            $0.browser.rawValue == selection.browserID && $0.profile.id == selection.profileID
        }
        guard let store = matching.first(where: { $0.kind == .network })
            ?? matching.first(where: { $0.kind == .primary })
        else {
            throw ProviderFetchClassifiedError(
                kind: .missingCredential, message: "The selected browser profile has no discoverable cookie store.")
        }
        return store
    }
    #endif

    static func read(_ selection: Self, domains: Set<String>) throws -> [ProviderPluginCookieRecord] {
        #if os(macOS)
        guard let browser = Browser(rawValue: selection.browserID) else {
            throw ProviderPluginError.secretAccess("unsupported selected browser")
        }
        guard BrowserCookieAccessGate.shouldAttempt(browser) else {
            throw ProviderFetchClassifiedError(
                kind: .permissionDenied,
                message: "Browser cookie access is blocked. Check Keychain access and refresh manually.")
        }
        let client = BrowserCookieClient()
        let store: BrowserCookieStore
        do {
            store = try Self.selectedStore(selection, from: client.codexBarStores(for: browser))
        } catch {
            if BrowserDetection.selectedChromiumProfileAccessIssue(
                profileID: selection.profileID,
                browser: browser,
                homeDirectories: client.configuration.homeDirectories) == .accessDenied
            {
                throw ProviderFetchClassifiedError(
                    kind: .permissionDenied,
                    message: "Cannot read the selected browser profile. Check Files & Folders access.")
            }
            throw error
        }
        do {
            return try client.codexBarRecords(
                matching: BrowserCookieQuery(domains: domains.sorted(), domainMatch: .exact), in: store)
                .map(ProviderPluginCookieRecord.init)
        } catch let error as BrowserCookieError {
            guard case .accessDenied = error else { throw error }
            throw ProviderFetchClassifiedError(
                kind: .permissionDenied, message: "Cannot decrypt the selected profile. Check browser Keychain access.")
        }
        #else
        throw ProviderFetchClassifiedError(
            kind: .missingCredential,
            message: "Selected browser profiles require macOS.")
        #endif
    }
}

extension ProviderConfig {
    public var browserProfileID: String? {
        get { self.extensionValue(forKey: "browserProfileID") }
        set { self.setExtensionValue(newValue, forKey: "browserProfileID") }
    }
}

extension ProviderSettingsSectionRegistration {
    var selectedProfileCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        self.selectedProfileBrowser.flatMap(Browser.init(rawValue:)).map { [$0] }
        #else
        nil
        #endif
    }
}
