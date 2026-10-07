import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenCodeUsageError: LocalizedError {
    case invalidCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "OpenCode session cookie is invalid or expired."
        case let .networkError(message):
            "OpenCode network error: \(message)"
        case let .apiError(message):
            "OpenCode API error: \(message)"
        case let .parseFailed(message):
            "OpenCode parse error: \(message)"
        }
    }
}

public struct OpenCodeUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.provider(.opencode, scope: "usage"))
    private static let baseURL = URL(string: "https://opencode.ai")!
    private static let serverURL = URL(string: "https://opencode.ai/_server")!
    private static let workspacesServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private static let subscriptionServerID = "7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4"
    /// Customer/billing server function, the same one `OpenCodeGoUsageFetcher` reads the Zen
    /// balance from. It carries the monthly spend fields pay-as-you-go workspaces bill against.
    private static let billingServerID = "c83b78a614689c38ebee981f9b39a8b377716db85c1fd7dbab604adc02d3313d"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    private struct ServerRequest {
        let serverID: String
        let args: [Any]?
        let method: String
        let referer: URL
    }

    public static func fetchUsage(
        cookieHeader: String,
        timeout: TimeInterval,
        now: Date = Date(),
        workspaceIDOverride: String? = nil,
        session transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) async throws -> OpenCodeUsageSnapshot
    {
        guard let requestCookieHeader = OpenCodeWebCookieSupport.requestCookieHeader(from: cookieHeader) else {
            throw OpenCodeUsageError.invalidCredentials
        }
        let normalizedOverride = OpenCodeGoUsageFetcher.normalizeWorkspaceID(workspaceIDOverride)
        if let rawOverride = workspaceIDOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawOverride.isEmpty, normalizedOverride == nil
        {
            throw OpenCodeUsageError.apiError("Invalid workspace override.")
        }
        let workspaceID: String = if let override = normalizedOverride {
            override
        } else {
            try await OpenCodeLegacyFallback.fetch(cookieHeader: requestCookieHeader, requiresConsoleCookie: true) {
                try await OpenCodeConsoleUsageFetcher.fetchWorkspaceID(
                    cookieHeader: requestCookieHeader, timeout: timeout, transport: transport)
            } legacy: {
                try await self.fetchWorkspaceID(
                    cookieHeader: requestCookieHeader, timeout: timeout, transport: transport)
            }
        }
        return try await OpenCodeLegacyFallback.fetch(cookieHeader: requestCookieHeader, requiresConsoleCookie: true) {
            try await OpenCodeConsoleUsageFetcher.fetchUsage(
                workspaceID: workspaceID,
                cookieHeader: requestCookieHeader,
                timeout: timeout,
                now: now,
                transport: transport)
        } legacy: {
            try await self.fetchLegacyUsage(
                workspaceID: workspaceID,
                cookieHeader: requestCookieHeader,
                timeout: timeout,
                now: now,
                transport: transport)
        }
    }

    private static func fetchLegacyUsage(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        now: Date,
        transport: any ProviderHTTPTransport) async throws -> OpenCodeUsageSnapshot
    {
        do {
            let subscriptionText = try await self.fetchSubscriptionInfo(
                workspaceID: workspaceID,
                cookieHeader: cookieHeader,
                timeout: timeout,
                transport: transport)
            return try self.parseSubscription(text: subscriptionText, now: now)
        } catch let error as OpenCodeUsageError {
            // Pay-as-you-go workspaces have no subscription object, so the subscription server
            // function answers with null or fails outright. Their spend lives in the billing
            // payload instead, which is still reachable with the same session cookie.
            guard self.canFallBackToBilling(from: error) else { throw error }
            do {
                if let snapshot = try await self.fetchPayAsYouGoUsage(
                    workspaceID: workspaceID,
                    cookieHeader: cookieHeader,
                    timeout: timeout,
                    now: now,
                    transport: transport)
                {
                    return snapshot
                }
            } catch OpenCodeUsageError.invalidCredentials {
                throw OpenCodeUsageError.invalidCredentials
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                Self.log.error("OpenCode billing fallback failed: \(error.localizedDescription)")
            }
            throw error
        }
    }
}

extension OpenCodeUsageFetcher {
    /// Only subscription-shaped failures are worth retrying against billing. Credential and
    /// transport failures would fail the same way on the billing call.
    private static func canFallBackToBilling(from error: OpenCodeUsageError) -> Bool {
        switch error {
        case .apiError, .parseFailed:
            true
        case .invalidCredentials, .networkError:
            false
        }
    }

    private static func fetchPayAsYouGoUsage(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        now: Date,
        transport: any ProviderHTTPTransport) async throws -> OpenCodeUsageSnapshot?
    {
        let referer = URL(string: "https://opencode.ai/workspace/\(workspaceID)") ?? self.baseURL
        let text = try await self.fetchServerText(
            request: ServerRequest(
                serverID: self.billingServerID,
                args: [workspaceID],
                method: "GET",
                referer: referer),
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        if OpenCodeWebParsing.looksSignedOut(text: text) {
            throw OpenCodeUsageError.invalidCredentials
        }
        guard let billing = OpenCodeZenBillingParser.parse(text: text) else {
            Self.log.error("OpenCode billing payload did not contain monthly usage fields.")
            return nil
        }
        guard !billing.hasSubscription else {
            Self.log.warning("OpenCode billing fallback still reports a subscription; preserving subscription error.")
            return nil
        }
        Self.log.info(
            "OpenCode billing usage resolved (subscription \(billing.hasSubscription ? "present" : "null"), " +
                "limit \(billing.monthlyLimitUSD == nil ? "unset" : "set")).")
        return .payAsYouGo(
            OpenCodeUsageSnapshot.PayAsYouGoUsage(
                monthlyUsageUSD: billing.monthlyUsageUSD,
                monthlyLimitUSD: billing.monthlyLimitUSD,
                balanceUSD: billing.balanceUSD),
            updatedAt: now)
    }

    private static func fetchWorkspaceID(
        cookieHeader: String,
        timeout: TimeInterval,
        transport: any ProviderHTTPTransport) async throws -> String
    {
        let text = try await self.fetchServerText(
            request: ServerRequest(
                serverID: self.workspacesServerID,
                args: nil,
                method: "GET",
                referer: self.baseURL),
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        if OpenCodeWebParsing.looksSignedOut(text: text) {
            throw OpenCodeUsageError.invalidCredentials
        }
        var ids = OpenCodeWebParsing.parseWorkspaceIDs(text: text)
        if ids.isEmpty {
            ids = OpenCodeWebParsing.parseWorkspaceIDsFromJSON(text: text)
        }
        if ids.isEmpty {
            Self.log.error("OpenCode workspace ids missing after GET; retrying with POST.")
            let fallback = try await self.fetchServerText(
                request: ServerRequest(
                    serverID: self.workspacesServerID,
                    args: [],
                    method: "POST",
                    referer: self.baseURL),
                cookieHeader: cookieHeader,
                timeout: timeout,
                transport: transport)
            if OpenCodeWebParsing.looksSignedOut(text: fallback) {
                throw OpenCodeUsageError.invalidCredentials
            }
            ids = OpenCodeWebParsing.parseWorkspaceIDs(text: fallback)
            if ids.isEmpty {
                ids = OpenCodeWebParsing.parseWorkspaceIDsFromJSON(text: fallback)
            }
            if ids.isEmpty {
                self.logParseSummary(text: fallback)
                throw OpenCodeUsageError.parseFailed("Missing workspace id.")
            }
            return ids[0]
        }
        return ids[0]
    }

    private static func fetchSubscriptionInfo(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        transport: any ProviderHTTPTransport) async throws -> String
    {
        let referer = URL(string: "https://opencode.ai/workspace/\(workspaceID)/billing") ?? self.baseURL
        let text = try await self.fetchServerText(
            request: ServerRequest(
                serverID: self.subscriptionServerID,
                args: [workspaceID],
                method: "GET",
                referer: referer),
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        if OpenCodeWebParsing.looksSignedOut(text: text) {
            throw OpenCodeUsageError.invalidCredentials
        }
        if self.isExplicitNullPayload(text: text) {
            Self.log.warning("OpenCode subscription GET returned null; skipping POST fallback.")
            throw self.missingSubscriptionDataError(workspaceID: workspaceID)
        }
        if self.parseSubscriptionJSON(text: text, now: Date()) == nil,
           OpenCodeWebParsing.extractDouble(
               pattern: #"rollingUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
               text: text) == nil
        {
            Self.log.error("OpenCode subscription payload missing after GET; retrying with POST.")
            let fallback = try await self.fetchServerText(
                request: ServerRequest(
                    serverID: self.subscriptionServerID,
                    args: [workspaceID],
                    method: "POST",
                    referer: referer),
                cookieHeader: cookieHeader,
                timeout: timeout,
                transport: transport)
            if OpenCodeWebParsing.looksSignedOut(text: fallback) {
                throw OpenCodeUsageError.invalidCredentials
            }
            if self.isExplicitNullPayload(text: fallback) {
                Self.log.warning("OpenCode subscription POST returned null.")
                throw self.missingSubscriptionDataError(workspaceID: workspaceID)
            }
            return fallback
        }
        return text
    }

    private static func isExplicitNullPayload(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("null") == .orderedSame {
            return true
        }
        // A server function that resolves to null answers with the seeded payload
        // `…["server-fn:<uuid>"]=[],null)`. Treating it as a null payload avoids a POST retry that
        // opencode.ai answers with HTTP 500 for workspaces without a subscription.
        if trimmed.range(
            of: #"\]\s*=\s*\[\s*\]\s*,\s*null\s*\)\s*$"#,
            options: .regularExpression) != nil
        {
            return true
        }
        return false
    }

    private static func missingSubscriptionDataError(workspaceID: String) -> OpenCodeUsageError {
        OpenCodeUsageError.apiError(
            "No subscription usage data was returned for workspace \(workspaceID). " +
                "This usually means this workspace does not have OpenCode subscription quota data available.")
    }

    private static func fetchServerText(
        request serverRequest: ServerRequest,
        cookieHeader: String,
        timeout: TimeInterval,
        transport: any ProviderHTTPTransport) async throws -> String
    {
        let url = self.serverRequestURL(
            serverID: serverRequest.serverID,
            args: serverRequest.args,
            method: serverRequest.method)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = serverRequest.method
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        urlRequest.setValue(serverRequest.serverID, forHTTPHeaderField: "X-Server-Id")
        urlRequest.setValue("server-fn:\(UUID().uuidString)", forHTTPHeaderField: "X-Server-Instance")
        urlRequest.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue(self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        urlRequest.setValue(serverRequest.referer.absoluteString, forHTTPHeaderField: "Referer")
        urlRequest.setValue("text/javascript, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if serverRequest.method.uppercased() != "GET",
           let args = serverRequest.args
        {
            let body = try JSONSerialization.data(withJSONObject: args, options: [])
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: urlRequest)
        } catch let error as URLError where error.code == .badServerResponse {
            throw OpenCodeUsageError.networkError("Invalid response")
        } catch {
            throw error
        }

        guard response.statusCode == 200 else {
            let bodyText = String(data: response.data, encoding: .utf8) ?? ""
            let contentType = response.response.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            Self.log
                .error("OpenCode returned \(response.statusCode) (type=\(contentType) length=\(response.data.count))")
            if OpenCodeWebParsing.looksSignedOut(text: bodyText) {
                throw OpenCodeUsageError.invalidCredentials
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                throw OpenCodeUsageError.invalidCredentials
            }
            if let message = OpenCodeWebParsing.extractServerErrorMessage(from: bodyText) {
                throw OpenCodeUsageError.apiError("HTTP \(response.statusCode): \(message)")
            }
            throw OpenCodeUsageError.apiError("HTTP \(response.statusCode)")
        }

        guard let text = String(data: response.data, encoding: .utf8) else {
            throw OpenCodeUsageError.parseFailed("Response was not UTF-8.")
        }
        return text
    }
}

extension OpenCodeUsageFetcher {
    static func parseSubscription(text: String, now: Date) throws -> OpenCodeUsageSnapshot {
        if let snapshot = self.parseSubscriptionJSON(text: text, now: now) {
            return snapshot
        }

        guard let rollingPercent = OpenCodeWebParsing.extractDouble(
            pattern: #"rollingUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            text: text),
            let rollingReset = OpenCodeWebParsing.extractInt(
                pattern: #"rollingUsage[^}]*?resetInSec\s*:\s*([0-9]+)"#,
                text: text),
            let weeklyPercent = OpenCodeWebParsing.extractDouble(
                pattern: #"weeklyUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
                text: text),
            let weeklyReset = OpenCodeWebParsing.extractInt(
                pattern: #"weeklyUsage[^}]*?resetInSec\s*:\s*([0-9]+)"#,
                text: text)
        else {
            self.logParseSummary(text: text)
            throw OpenCodeUsageError.parseFailed("Missing usage fields.")
        }

        return OpenCodeUsageSnapshot(
            rollingUsagePercent: rollingPercent,
            weeklyUsagePercent: weeklyPercent,
            rollingResetInSec: rollingReset,
            weeklyResetInSec: weeklyReset,
            updatedAt: now)
    }

    private static func parseSubscriptionJSON(text: String, now: Date) -> OpenCodeUsageSnapshot? {
        guard let quota = OpenCodeSubscriptionParser(requiresWeeklyUsage: true)
            .parseSubscriptionJSON(text: text, now: now)
        else { return nil }
        return OpenCodeUsageSnapshot(quota: quota)
    }

    private static func serverRequestURL(serverID: String, args: [Any]?, method: String) -> URL {
        guard method.uppercased() == "GET" else {
            return self.serverURL
        }

        var components = URLComponents(url: self.serverURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "id", value: serverID)]
        if let args, !args.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: args, options: []),
           let encodedArgs = String(data: data, encoding: .utf8)
        {
            queryItems.append(URLQueryItem(name: "args", value: encodedArgs))
        }
        components?.queryItems = queryItems
        return components?.url ?? self.serverURL
    }

    private static func logParseSummary(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            let hint = if trimmed.hasPrefix("<") {
                "html"
            } else if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                "json"
            } else if trimmed.isEmpty {
                "empty"
            } else {
                "text"
            }
            Self.log.error("OpenCode response non-JSON: hint=\(hint) length=\(text.count)")
            return
        }
        let summary = self.summarizeJSON(object: object, depth: 0)
        guard !summary.isEmpty else { return }
        Self.log.error("OpenCode response summary: \(summary)")
    }

    private static func summarizeJSON(object: Any, depth: Int) -> String {
        if let dict = object as? [String: Any] {
            guard depth <= 3 else { return "" }
            let parts = dict.sorted { $0.key < $1.key }.map { key, value in
                "\(key):\(self.summarizeJSON(object: value, depth: depth + 1))"
            }
            return "{\(parts.joined(separator: ", "))}"
        }
        if let array = object as? [Any] {
            guard depth <= 3 else { return "" }
            guard let first = array.first else { return "[]" }
            return "[\(self.summarizeJSON(object: first, depth: depth + 1))]"
        }
        switch object {
        case is String: return "string"
        case is Bool: return "bool"
        case is Int, is Double, is NSNumber: return "number"
        default: return "value"
        }
    }
}
