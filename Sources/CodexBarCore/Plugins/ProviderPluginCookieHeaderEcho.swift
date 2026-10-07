import Foundation

/// Bundled authority to echo one URL-matched cookie without exposing its value to JavaScript.
public struct ProviderPluginCookieHeaderEcho: Sendable {
    let origin: String
    let cookie: String
    let header: String

    init(
        _ value: any ProviderPluginValue,
        domains: Set<String>,
        endpoints: Set<ProviderPluginEndpoint>,
        requiredCookies: Set<String>) throws
    {
        guard value.isObject, !value.isArray,
              try Set(value.propertyNames()) == ["origin", "cookie", "header"],
              let origin = value.property("origin"), origin.isString,
              let cookie = value.property("cookie"), cookie.isString,
              let header = value.property("header"), header.isString,
              domains.contains(String(origin.stringValue().dropFirst("https://".count))),
              origin.stringValue().hasPrefix("https://"), endpoints.contains(.fixed(origin.stringValue())),
              requiredCookies.contains(cookie.stringValue()),
              header.stringValue().range(of: #"^[Xx]-[A-Za-z0-9-]{1,62}$"#, options: .regularExpression) != nil
        else { throw ProviderPluginError.invalidManifest("invalid bundled cookie headerEcho") }
        self.origin = origin.stringValue()
        self.cookie = cookie.stringValue()
        self.header = header.stringValue()
    }

    func value(from cookieHeader: String) throws -> String {
        let matches = CookieHeaderNormalizer.pairs(from: cookieHeader).filter { $0.name == self.cookie }
        guard !cookieHeader.utf8.contains(where: { $0 < 32 || $0 == 127 }), matches.count == 1,
              let value = matches.first?.value, !value.isEmpty,
              value.utf8.allSatisfy({ (33...126).contains($0) })
        else {
            throw ProviderFetchClassifiedError(
                kind: .missingCredential,
                message: "The session requires one valid CSRF cookie matching the request URL.")
        }
        return value
    }
}
