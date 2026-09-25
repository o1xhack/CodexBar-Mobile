import Foundation
#if os(macOS)
import SweetCookieKit
#endif

/// Shared browser policies and traversal; providers retain session validation, caching, and logging.
enum BrowserCookieImportSupport {
    /// Keep deliberate Chrome-only policies explicit without duplicating platform guards in descriptors.
    static func chromeOnly(reason _: StaticString) -> BrowserCookieImportOrder? {
        #if os(macOS)
        Browser.defaultImportOrder.filter { $0 == .chrome }
        #else
        nil
        #endif
    }

    #if os(macOS)
    static func collectSessions<Session>(
        from browsers: [Browser],
        missingError: any Error,
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
        guard !sessions.isEmpty else { throw missingError }
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
