import Foundation
#if os(macOS)
import SweetCookieKit
#endif

/// Shared browser policies and traversal; providers retain session validation, caching, and logging.
public enum BrowserCookieImportSupport {
    public static func browserNames(for provider: UsageProvider?) -> String {
        #if os(macOS)
        self.importOrder(for: provider).map(\.displayName).joined(separator: ", ")
        #else
        "none on this platform"
        #endif
    }

    /// Keep deliberate Chrome-only policies explicit without duplicating platform guards in descriptors.
    static func chromeOnly(reason _: StaticString) -> BrowserCookieImportOrder? {
        #if os(macOS)
        Browser.defaultImportOrder.filter { $0 == .chrome }
        #else
        nil
        #endif
    }

    #if os(macOS)
    static func importOrder(for provider: UsageProvider?) -> [Browser] {
        provider.map { ProviderDefaults.metadata[$0]?.browserCookieOrder ?? Browser.defaultImportOrder } ?? [.chrome]
    }

    static func collectSessions<Session>(
        from browsers: [Browser],
        missingError: (any Error)?,
        logger: (String) -> Void,
        load: (Browser) throws -> [Session]) throws -> [Session]
    {
        var sessions: [Session] = []
        for browser in browsers {
            do {
                try sessions.append(contentsOf: load(browser))
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                logger("\(browser.displayName) cookie import failed: \(error.localizedDescription)")
            }
        }
        if sessions.isEmpty, let missingError { throw missingError }
        return sessions
    }

    static func loadProfiles(
        from browser: Browser,
        domains: [String],
        client: BrowserCookieClient,
        logger: @escaping (String) -> Void) throws -> [(label: String, cookies: [HTTPCookie])]
    {
        let query = BrowserCookieQuery(domains: domains)
        let sources = try client.codexBarRecords(matching: query, in: browser, logger: logger)
        return self.httpCookieProfiles(from: sources, origin: query.origin)
    }

    static func httpCookieProfiles(
        from sources: [BrowserCookieStoreRecords],
        origin: BrowserCookieOriginStrategy) -> [(label: String, cookies: [HTTPCookie])]
    {
        BrowserCookieProfiles.merge(sources).compactMap { profile in
            let cookies = BrowserCookieClient.makeHTTPCookies(profile.records, origin: origin)
            return cookies.isEmpty ? nil : (profile.label, cookies)
        }
    }
    #endif
}
