import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AlibabaTokenPlanUsageError: LocalizedError, Sendable, Equatable {
    case loginRequired
    case invalidCredentials
    case apiError(String)
    case networkError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loginRequired:
            "Alibaba Token Plan login required."
        case .invalidCredentials:
            "Alibaba Token Plan credentials are invalid."
        case let .apiError(message):
            "Alibaba Token Plan API error: \(message)"
        case let .networkError(message):
            "Alibaba Token Plan network error: \(message)"
        case let .parseFailed(message):
            "Could not parse Alibaba Token Plan usage: \(message)"
        }
    }
}

// swiftlint:disable:next type_body_length
public struct AlibabaTokenPlanUsageFetcher: Sendable {
    private struct SubscriptionSummaryContext: Sendable {
        let url: URL
        let cookieHeader: String
        let secToken: String?
        let region: AlibabaTokenPlanAPIRegion
        let environment: [String: String]
        let now: Date
    }

    private struct RateLimitContext: Sendable {
        let cookieHeader: String
        let secToken: String
        let region: AlibabaTokenPlanAPIRegion
        let environment: [String: String]
        let now: Date
    }

    private static let log = CodexBarLog.logger("alibaba-token-plan")
    private static let bssServiceCode = "BssOpenAPI-V3"
    private static let subscriptionSummaryAction = "GetSubscriptionSummary"
    private static let rateLimitMergeGrace: Duration = .seconds(2)
    private static let rateLimitFallbackGrace: Duration = .seconds(5)
    private static let browserLikeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
    private static let safariLikeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3 Safari/605.1.15"

    public static var dashboardURL: URL {
        Self.dashboardURL(region: .international, environment: ProcessInfo.processInfo.environment)
    }

    public static func dashboardURL(
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        if let host = AlibabaTokenPlanSettingsReader.hostOverride(environment: environment),
           let base = ProviderEndpointOverrideValidator.normalizedHTTPSURL(from: host),
           var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
           let dashboardComponents = URLComponents(url: region.dashboardURL, resolvingAgainstBaseURL: false)
        {
            components.path = dashboardComponents.path
            components.percentEncodedQuery = dashboardComponents.percentEncodedQuery
            components.fragment = dashboardComponents.fragment
            return components.url ?? region.dashboardURL
        }
        return region.dashboardURL
    }

    static func personalDashboardURL(
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String]) -> URL
    {
        guard let override = self.rateLimitOverrideBaseURL(environment: environment),
              var components = URLComponents(url: override, resolvingAgainstBaseURL: false),
              let personalComponents = URLComponents(
                  url: region.personalDashboardURL,
                  resolvingAgainstBaseURL: false)
        else {
            return region.personalDashboardURL
        }
        components.path = personalComponents.path
        components.percentEncodedQuery = personalComponents.percentEncodedQuery
        components.fragment = personalComponents.fragment
        return components.url ?? region.personalDashboardURL
    }

    public static func fetchUsage(
        cookieHeader: String,
        region: AlibabaTokenPlanAPIRegion = .international,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) async throws -> AlibabaTokenPlanUsageSnapshot
    {
        guard let headers = AlibabaTokenPlanCookieHeaders(singleHeader: cookieHeader) else {
            throw AlibabaTokenPlanSettingsError.invalidCookie
        }
        return try await self.fetchUsage(
            apiCookieHeader: headers.apiCookieHeader,
            dashboardCookieHeader: headers.dashboardCookieHeader,
            rateLimitCookieHeader: headers.rateLimitCookieHeader,
            region: region,
            environment: environment,
            now: now)
    }

    static func fetchUsage(
        apiCookieHeader: String,
        dashboardCookieHeader: String,
        rateLimitCookieHeader: String?,
        region: AlibabaTokenPlanAPIRegion = .international,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        session overrideSession: URLSession? = nil) async throws -> AlibabaTokenPlanUsageSnapshot
    {
        guard let normalizedAPIHeader = CookieHeaderNormalizer.normalize(apiCookieHeader),
              let normalizedDashboardHeader = CookieHeaderNormalizer.normalize(dashboardCookieHeader)
        else {
            throw AlibabaTokenPlanSettingsError.invalidCookie
        }
        let normalizedRateLimitHeader = CookieHeaderNormalizer.normalize(rateLimitCookieHeader)

        let url = self.resolveQuotaURL(region: region, environment: environment)
        let apiRedirectDiagnostics = RedirectDiagnostics(cookieHeader: normalizedAPIHeader)
        let rateLimitRedirectDiagnostics = RedirectDiagnostics(cookieHeader: normalizedRateLimitHeader ?? "")
        let dashboardRedirectDiagnostics: RedirectDiagnostics?
        let apiSession: URLSession
        let rateLimitSession: URLSession
        let dashboardSession: URLSession
        if let overrideSession {
            apiSession = overrideSession
            rateLimitSession = overrideSession
            dashboardSession = overrideSession
            dashboardRedirectDiagnostics = nil
        } else {
            let dashboardDiagnostics = RedirectDiagnostics(cookieHeader: normalizedDashboardHeader)
            apiSession = URLSession(
                configuration: .default,
                delegate: apiRedirectDiagnostics,
                delegateQueue: nil)
            rateLimitSession = URLSession(
                configuration: .default,
                delegate: rateLimitRedirectDiagnostics,
                delegateQueue: nil)
            dashboardSession = URLSession(
                configuration: .default,
                delegate: dashboardDiagnostics,
                delegateQueue: nil)
            dashboardRedirectDiagnostics = dashboardDiagnostics
        }
        defer {
            if overrideSession == nil {
                apiSession.invalidateAndCancel()
                rateLimitSession.invalidateAndCancel()
                dashboardSession.invalidateAndCancel()
            }
            if let dashboardRedirectDiagnostics, !dashboardRedirectDiagnostics.redirects.isEmpty {
                Self.log.info(
                    "Alibaba Token Plan dashboard redirects",
                    metadata: [
                        "count": "\(dashboardRedirectDiagnostics.redirects.count)",
                        "items": dashboardRedirectDiagnostics.redirects.joined(separator: " | "),
                    ])
            }
            if !apiRedirectDiagnostics.redirects.isEmpty {
                Self.log.info(
                    "Alibaba Token Plan subscription-summary redirects",
                    metadata: [
                        "count": "\(apiRedirectDiagnostics.redirects.count)",
                        "items": apiRedirectDiagnostics.redirects.joined(separator: " | "),
                    ])
            }
            if !rateLimitRedirectDiagnostics.redirects.isEmpty {
                Self.log.info(
                    "Alibaba Token Plan rate-limit redirects",
                    metadata: [
                        "count": "\(rateLimitRedirectDiagnostics.redirects.count)",
                        "items": rateLimitRedirectDiagnostics.redirects.joined(separator: " | "),
                    ])
            }
        }
        let secToken = await self.resolveSECToken(
            dashboardCookieHeader: normalizedDashboardHeader,
            apiCookieHeader: normalizedAPIHeader,
            region: region,
            environment: environment,
            session: dashboardSession)
        let rateLimitTask: Task<AlibabaTokenPlanUsageSnapshot, Error>? = if let secToken,
                                                                            let normalizedRateLimitHeader
        {
            Task {
                try await self.fetchRateLimitUsage(
                    context: RateLimitContext(
                        cookieHeader: normalizedRateLimitHeader,
                        secToken: secToken,
                        region: region,
                        environment: environment,
                        now: now),
                    session: rateLimitSession)
            }
        } else {
            nil
        }
        defer {
            rateLimitTask?.cancel()
        }
        Self.log.info(
            "Fetching Alibaba Token Plan usage",
            metadata: [
                "apiHost": url.host ?? "unknown",
                "region": region.rawValue,
                "apiCookieNames": self.cookieNamesDescription(from: normalizedAPIHeader),
                "rateLimitCookieNames": self.cookieNamesDescription(from: normalizedRateLimitHeader ?? ""),
                "dashboardCookieNames": self.cookieNamesDescription(from: normalizedDashboardHeader),
                "hasCSRF": self.hasCSRF(in: normalizedAPIHeader) ? "1" : "0",
                "secTokenSource": secToken == nil ? "missing" : "resolved",
            ])

        do {
            let subscriptionSnapshot = try await self.fetchSubscriptionSummary(
                context: SubscriptionSummaryContext(
                    url: url,
                    cookieHeader: normalizedAPIHeader,
                    secToken: secToken,
                    region: region,
                    environment: environment,
                    now: now),
                session: apiSession)
            return await self.mergeRateLimitTask(
                rateLimitTask,
                into: subscriptionSnapshot,
                joinGrace: self.rateLimitMergeGrace)
        } catch {
            guard let rateLimitTask else { throw error }
            switch await BoundedTaskJoin(sourceTask: rateLimitTask)
                .value(joinGrace: self.rateLimitFallbackGrace)
            {
            case let .value(rateLimitSnapshot):
                Self.log.info(
                    "Alibaba Token Plan subscription summary failed; using rate-limit usage",
                    metadata: ["error": error.localizedDescription])
                return rateLimitSnapshot
            case let .failure(rateLimitError):
                Self.log.info(
                    "Alibaba Token Plan rate-limit request also failed",
                    metadata: ["error": rateLimitError.localizedDescription])
            case .timedOut:
                Self.log.info("Alibaba Token Plan rate-limit fallback timed out")
            }
            throw error
        }
    }

    static func mergeRateLimitTask(
        _ rateLimitTask: Task<AlibabaTokenPlanUsageSnapshot, Error>?,
        into subscriptionSnapshot: AlibabaTokenPlanUsageSnapshot,
        joinGrace: Duration) async -> AlibabaTokenPlanUsageSnapshot
    {
        guard let rateLimitTask else { return subscriptionSnapshot }
        switch await BoundedTaskJoin(sourceTask: rateLimitTask).value(joinGrace: joinGrace) {
        case let .value(rateLimitSnapshot):
            return rateLimitSnapshot.mergingSubscriptionSummary(subscriptionSnapshot)
        case let .failure(error):
            Self.log.info(
                "Alibaba Token Plan rate-limit request failed; using subscription summary",
                metadata: ["error": error.localizedDescription])
        case .timedOut:
            Self.log.info("Alibaba Token Plan rate-limit request timed out; using subscription summary")
        }
        return subscriptionSnapshot
    }

    private static func fetchSubscriptionSummary(
        context: SubscriptionSummaryContext,
        session: URLSession) async throws -> AlibabaTokenPlanUsageSnapshot
    {
        var request = URLRequest(url: context.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = self.subscriptionSummaryRequestBody(
            region: context.region,
            secToken: context.secToken)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(context.cookieHeader, forHTTPHeaderField: "Cookie")
        if let csrf = self.extractCookieValue(name: "login_aliyunid_csrf", from: context.cookieHeader) ??
            self.extractCookieValue(name: "csrf", from: context.cookieHeader)
        {
            request.setValue(csrf, forHTTPHeaderField: "x-xsrf-token")
            request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.browserLikeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(context.region.dashboardOriginURLString, forHTTPHeaderField: "Origin")
        request.setValue(
            Self.dashboardURL(region: context.region, environment: context.environment).absoluteString,
            forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.log.error(
                "Alibaba Token Plan request failed",
                metadata: [
                    "apiHost": context.url.host ?? "unknown",
                    "error": error.localizedDescription,
                ])
            throw AlibabaTokenPlanUsageError.networkError(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.log.error("Alibaba Token Plan response was not HTTP")
            throw AlibabaTokenPlanUsageError.networkError("Invalid response")
        }
        Self.log.info(
            "Alibaba Token Plan HTTP response",
            metadata: [
                "status": "\(httpResponse.statusCode)",
                "bodyBytes": "\(data.count)",
                "contentType": httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none",
            ])
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AlibabaTokenPlanUsageError.loginRequired
            }
            Self.log.error("Alibaba Token Plan returned HTTP \(httpResponse.statusCode)")
            throw AlibabaTokenPlanUsageError.apiError("HTTP \(httpResponse.statusCode)")
        }

        return try self.parseUsageSnapshot(from: data, now: context.now)
    }

    private static func fetchRateLimitUsage(
        context: RateLimitContext,
        session: URLSession) async throws -> AlibabaTokenPlanUsageSnapshot
    {
        let url = self.resolveRateLimitURL(
            region: context.region,
            environment: context.environment)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = self.rateLimitRequestBody(
            cookieHeader: context.cookieHeader,
            secToken: context.secToken,
            region: context.region,
            environment: context.environment)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(context.cookieHeader, forHTTPHeaderField: "Cookie")
        if let csrf = self.extractCookieValue(name: "login_aliyunid_csrf", from: context.cookieHeader) ??
            self.extractCookieValue(name: "csrf", from: context.cookieHeader)
        {
            request.setValue(csrf, forHTTPHeaderField: "x-xsrf-token")
            request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.browserLikeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            self.rateLimitOriginURLString(
                region: context.region,
                environment: context.environment),
            forHTTPHeaderField: "Origin")
        request.setValue(
            self.personalDashboardURL(
                region: context.region,
                environment: context.environment).absoluteString,
            forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AlibabaTokenPlanUsageError.networkError(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AlibabaTokenPlanUsageError.networkError("Invalid rate-limit response")
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AlibabaTokenPlanUsageError.loginRequired
            }
            throw AlibabaTokenPlanUsageError.apiError("HTTP \(httpResponse.statusCode)")
        }
        return try self.parseRateLimitUsageSnapshot(from: data, now: context.now)
    }

    private static func rateLimitRequestBody(
        cookieHeader: String,
        secToken: String,
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String]) -> Data
    {
        let traceID = UUID().uuidString.lowercased()
        var cornerstoneParam: [String: Any] = [
            "feTraceId": traceID,
            "feURL": self.personalDashboardURL(region: region, environment: environment).absoluteString,
            "protocol": "V2",
            "console": "ONE_CONSOLE",
            "productCode": "p_efm",
            "switchAgent": 1_233_135,
            "switchUserType": 3,
            "domain": region.consoleDomain,
            "consoleSite": region.consoleSite,
            "userNickName": "",
            "userPrincipalName": "",
            "xsp_lang": "en-US",
        ]
        if let anonymousID = self.extractCookieValue(name: "cna", from: cookieHeader),
           !anonymousID.isEmpty
        {
            cornerstoneParam["X-Anonymous-Id"] = anonymousID
        }
        let paramsObject: [String: Any] = [
            "Api": region.rateLimitAPIName,
            "V": "1.0",
            "Data": [
                "cornerstoneParam": cornerstoneParam,
            ],
        ]
        guard let paramsData = try? JSONSerialization.data(withJSONObject: paramsObject, options: []),
              let paramsString = String(data: paramsData, encoding: .utf8)
        else {
            return Data()
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "params", value: paramsString),
            URLQueryItem(name: "region", value: region.currentRegionID),
            URLQueryItem(name: "sec_token", value: secToken),
        ]
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    static func resolveRateLimitURL(
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String]) -> URL
    {
        guard let override = self.rateLimitOverrideBaseURL(environment: environment),
              var components = URLComponents(url: override, resolvingAgainstBaseURL: false),
              let rateLimitComponents = URLComponents(
                  url: region.rateLimitURL,
                  resolvingAgainstBaseURL: false)
        else {
            return region.rateLimitURL
        }
        components.path = rateLimitComponents.path
        components.percentEncodedQuery = rateLimitComponents.percentEncodedQuery
        components.fragment = rateLimitComponents.fragment
        return components.url ?? region.rateLimitURL
    }

    static func rateLimitOriginURLString(
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String]) -> String
    {
        guard self.rateLimitOverrideBaseURL(environment: environment) != nil else {
            return region.dashboardOriginURLString
        }
        return self.originURLString(for: self.resolveRateLimitURL(
            region: region,
            environment: environment)) ?? region.dashboardOriginURLString
    }

    private static func rateLimitOverrideBaseURL(environment: [String: String]) -> URL? {
        if let quotaURL = AlibabaTokenPlanSettingsReader.quotaURL(environment: environment) {
            return quotaURL
        }
        guard let host = AlibabaTokenPlanSettingsReader.hostOverride(environment: environment) else {
            return nil
        }
        return ProviderEndpointOverrideValidator.normalizedHTTPSURL(from: host)
    }

    private static func originURLString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.string
    }

    static func resolveQuotaURL(
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String]) -> URL
    {
        if let override = AlibabaTokenPlanSettingsReader.quotaURL(environment: environment) {
            return override
        }
        if let host = AlibabaTokenPlanSettingsReader.hostOverride(environment: environment),
           let hostURL = self.quotaURL(from: host)
        {
            return hostURL
        }
        return self.defaultQuotaURL(region: region)
    }

    static var defaultQuotaURL: URL {
        self.defaultQuotaURL(region: .international)
    }

    static func defaultQuotaURL(region: AlibabaTokenPlanAPIRegion) -> URL {
        var components = URLComponents(string: region.gatewayBaseURLString)!
        components.path = "/data/api.json"
        components.queryItems = [
            URLQueryItem(name: "action", value: Self.subscriptionSummaryAction),
            URLQueryItem(name: "product", value: Self.bssServiceCode),
            URLQueryItem(name: "_tag", value: ""),
        ]
        return components.url!
    }

    static func parseUsageSnapshot(from data: Data, now: Date = Date()) throws -> AlibabaTokenPlanUsageSnapshot {
        guard !data.isEmpty else {
            throw AlibabaTokenPlanUsageError.parseFailed("Empty response body")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            if self.isLikelyLoginHTML(data) {
                throw AlibabaTokenPlanUsageError.loginRequired
            }
            throw AlibabaTokenPlanUsageError.parseFailed("Invalid JSON response")
        }
        let expanded = self.expandedJSON(object)
        guard let dictionary = expanded as? [String: Any] else {
            throw AlibabaTokenPlanUsageError.parseFailed("Unexpected payload")
        }

        try self.throwIfErrorPayload(dictionary)

        let summary = self.findSubscriptionSummary(in: dictionary) ?? dictionary
        let total = self.anyDouble(for: Self.totalQuotaKeys, in: summary)
        let remaining = self.anyDouble(for: Self.remainingQuotaKeys, in: summary)
        let used = self.anyDouble(for: Self.usedQuotaKeys, in: summary) ??
            total.flatMap { total in remaining.map { max(0, total - $0) } }
        let resetsAt = self.findResetDate(in: summary) ?? self.findResetDate(in: dictionary)
        let totalCount = self.anyDouble(for: Self.subscriptionCountKeys, in: summary)
        let planName = self.findPlanName(in: summary) ?? ((totalCount ?? 0) > 0 || total != nil ? "TOKEN PLAN" : nil)

        if planName == nil, total == nil, used == nil, remaining == nil, totalCount == nil {
            let diagnostics = self.payloadDiagnostics(payload: dictionary)
            Self.log.error("Alibaba Token Plan payload missing expected fields: \(diagnostics)")
            throw AlibabaTokenPlanUsageError.parseFailed("Missing token plan data (\(diagnostics))")
        }

        return AlibabaTokenPlanUsageSnapshot(
            planName: planName,
            usedQuota: used,
            totalQuota: total,
            remainingQuota: remaining,
            resetsAt: resetsAt,
            updatedAt: now)
    }

    static func parseRateLimitUsageSnapshot(
        from data: Data,
        now: Date = Date()) throws -> AlibabaTokenPlanUsageSnapshot
    {
        guard !data.isEmpty else {
            throw AlibabaTokenPlanUsageError.parseFailed("Empty response body")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            if self.isLikelyLoginHTML(data) {
                throw AlibabaTokenPlanUsageError.loginRequired
            }
            throw AlibabaTokenPlanUsageError.parseFailed("Invalid JSON response")
        }
        let expanded = self.expandedJSON(object)
        guard let dictionary = expanded as? [String: Any] else {
            throw AlibabaTokenPlanUsageError.parseFailed("Unexpected payload")
        }
        try self.throwIfErrorPayload(dictionary)

        let rateKeys = [
            "per5HourPercentage",
            "per1WeekPercentage",
            "per5HourResetTime",
            "per1WeekResetTime",
        ]
        guard let usage = self.findFirstDictionary(matchingAnyKey: rateKeys, in: dictionary) else {
            throw AlibabaTokenPlanUsageError.parseFailed("Missing rate-limit usage")
        }
        let fiveHour = self.normalizedUsedPercent(self.parseDouble(usage["per5HourPercentage"]))
        let sevenDay = self.normalizedUsedPercent(self.parseDouble(usage["per1WeekPercentage"]))
        guard fiveHour != nil || sevenDay != nil else {
            throw AlibabaTokenPlanUsageError.parseFailed("Missing rate-limit usage")
        }

        return AlibabaTokenPlanUsageSnapshot(
            planName: "TOKEN PLAN",
            usedQuota: nil,
            totalQuota: nil,
            remainingQuota: nil,
            resetsAt: nil,
            fiveHourUsedPercent: fiveHour,
            fiveHourResetsAt: self.parseDate(usage["per5HourResetTime"]),
            sevenDayUsedPercent: sevenDay,
            sevenDayResetsAt: self.parseDate(usage["per1WeekResetTime"]),
            updatedAt: now)
    }

    private static func normalizedUsedPercent(_ raw: Double?) -> Double? {
        guard let raw, raw >= 0 else { return nil }
        if raw <= 1 {
            return raw * 100
        }
        guard raw <= 100 else { return nil }
        return raw
    }

    private static func subscriptionSummaryRequestBody(region: AlibabaTokenPlanAPIRegion, secToken: String?) -> Data {
        let paramsObject = ["ProductCode": region.tokenPlanProductCode]
        guard let paramsData = try? JSONSerialization.data(withJSONObject: paramsObject, options: []),
              let paramsString = String(data: paramsData, encoding: .utf8)
        else {
            return Data()
        }

        var components = URLComponents()
        var queryItems = [
            URLQueryItem(name: "product", value: Self.bssServiceCode),
            URLQueryItem(name: "action", value: Self.subscriptionSummaryAction),
            URLQueryItem(name: "params", value: paramsString),
            URLQueryItem(name: "region", value: region.currentRegionID),
        ]
        if let secToken, !secToken.isEmpty {
            queryItems.append(URLQueryItem(name: "sec_token", value: secToken))
        }
        components.queryItems = queryItems
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func resolveSECToken(
        dashboardCookieHeader: String,
        apiCookieHeader: String,
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String],
        session: URLSession) async -> String?
    {
        let cookieSECToken = self.extractCookieValue(name: "sec_token", from: dashboardCookieHeader) ??
            self.extractCookieValue(name: "sec_token", from: apiCookieHeader)
        var request = URLRequest(url: self.dashboardURL(region: region, environment: environment))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(dashboardCookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(Self.safariLikeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept")

        if let (data, response) = try? await session.data(for: request),
           let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200,
           let html = String(data: data, encoding: .utf8),
           let token = self.extractSECToken(from: html)
        {
            Self.log.info(
                "Resolved Alibaba Token Plan sec_token from dashboard HTML",
                metadata: [
                    "dashboardHost": request.url?.host ?? "unknown",
                    "htmlBytes": "\(data.count)",
                ])
            return token
        }

        if let token = await self.fetchSECTokenFromUserInfo(
            cookieHeader: dashboardCookieHeader,
            region: region,
            environment: environment,
            session: session)
        {
            return token
        }

        if let cookieSECToken, !cookieSECToken.isEmpty {
            Self.log.info("Resolved Alibaba Token Plan sec_token from cookies")
            return cookieSECToken
        }

        Self.log.info(
            "Alibaba Token Plan sec_token missing; continuing with cookie-only request",
            metadata: [
                "dashboardCookieNames": self.cookieNamesDescription(from: dashboardCookieHeader),
                "apiCookieNames": self.cookieNamesDescription(from: apiCookieHeader),
            ])
        return nil
    }

    private static func fetchSECTokenFromUserInfo(
        cookieHeader: String,
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String],
        session: URLSession) async -> String?
    {
        let baseURL = self.consoleBaseURL(region: region, environment: environment)
        let userInfoURL = baseURL.appendingPathComponent("tool/user/info.json")
        var request = URLRequest(url: userInfoURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(Self.safariLikeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let referer = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : "\(baseURL.absoluteString)/"
        request.setValue(referer, forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }

        let expanded = self.expandedJSON(object)
        guard let token = self.findFirstString(forKeys: ["secToken", "sec_token"], in: expanded),
              !token.isEmpty
        else {
            return nil
        }

        Self.log.info(
            "Resolved Alibaba Token Plan sec_token from user info",
            metadata: [
                "userInfoHost": userInfoURL.host ?? "unknown",
                "bodyBytes": "\(data.count)",
            ])
        return token
    }

    private static func consoleBaseURL(
        region: AlibabaTokenPlanAPIRegion,
        environment: [String: String]) -> URL
    {
        let dashboard = self.dashboardURL(region: region, environment: environment)
        var components = URLComponents()
        components.scheme = dashboard.scheme
        components.host = dashboard.host
        components.port = dashboard.port
        return components.url ?? URL(string: region.dashboardOriginURLString)!
    }

    private static func quotaURL(from rawHost: String) -> URL? {
        let cleaned = AlibabaTokenPlanSettingsReader.cleaned(rawHost)
        guard let cleaned else { return nil }
        guard let base = ProviderEndpointOverrideValidator.normalizedHTTPSURL(from: cleaned) else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let defaultComponents = URLComponents(
            url: Self.defaultQuotaURL(region: .international),
            resolvingAgainstBaseURL: false)
        components?.path = "/data/api.json"
        components?.queryItems = defaultComponents?.queryItems
        return components?.url
    }

    private final class RedirectDiagnostics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let cookieHeader: String
        var redirects: [String] = []

        init(cookieHeader: String) {
            self.cookieHeader = cookieHeader
        }

        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void)
        {
            let from = AlibabaTokenPlanUsageFetcher.redactedURLDescription(response.url)
            let to = AlibabaTokenPlanUsageFetcher.redactedURLDescription(request.url)
            self.redirects.append("\(response.statusCode) \(from) -> \(to)")

            completionHandler(AlibabaTokenPlanUsageFetcher.redirectedRequest(
                response: response,
                request: request,
                cookieHeader: self.cookieHeader))
        }
    }

    private static func redactedURLDescription(_ url: URL?) -> String {
        guard let url else { return "unknown" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? "\(url.scheme ?? "unknown")://\(url.host ?? "unknown")"
    }

    static func redirectedRequest(
        response: HTTPURLResponse,
        request: URLRequest,
        cookieHeader: String) -> URLRequest?
    {
        guard request.url?.scheme?.lowercased() == "https" else {
            return nil
        }

        var updated = request
        if self.shouldForwardRedirectCookies(from: response.url, to: request.url) {
            updated.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        } else {
            updated.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        return updated
    }

    private static func shouldForwardRedirectCookies(from sourceURL: URL?, to targetURL: URL?) -> Bool {
        guard let sourceHost = sourceURL?.host?.lowercased(),
              let targetHost = targetURL?.host?.lowercased()
        else {
            return false
        }
        return sourceHost == targetHost
    }

    private static func throwIfErrorPayload(_ dictionary: [String: Any]) throws {
        if self.parseBool(dictionary["successResponse"]) == false {
            if let statusCode = self.findFirstInt(forKeys: ["statusCode", "status_code", "code"], in: dictionary),
               statusCode == 401 || statusCode == 403
            {
                throw AlibabaTokenPlanUsageError.invalidCredentials
            }
            let code = self.findFirstString(forKeys: ["code", "status", "statusCode"], in: dictionary)
            let message = self.findFirstString(forKeys: ["message", "msg", "statusMessage"], in: dictionary) ??
                code ??
                "request was not successful"
            if self.isLoginOrTokenError(code: code, message: message) {
                throw AlibabaTokenPlanUsageError.loginRequired
            }
            throw AlibabaTokenPlanUsageError.apiError(message)
        }

        if self.findBoolValues(forKeys: ["Success", "success"], in: dictionary).contains(false) {
            let code = self.findFirstString(forKeys: ["Code", "code"], in: dictionary)
            let message = self.findFirstString(forKeys: ["Message", "message", "msg", "Code", "code"], in: dictionary)
                ?? "request was not successful"
            if self.isLoginOrTokenError(code: code, message: message) {
                throw AlibabaTokenPlanUsageError.loginRequired
            }
            throw AlibabaTokenPlanUsageError.apiError(message)
        }

        if let statusCode = self.findFirstInt(forKeys: ["statusCode", "status_code", "code"], in: dictionary),
           statusCode != 0,
           statusCode != 200
        {
            let message = self.findFirstString(
                forKeys: ["statusMessage", "status_msg", "message", "msg"],
                in: dictionary)
                ?? "status code \(statusCode)"
            if statusCode == 401 || statusCode == 403 {
                throw AlibabaTokenPlanUsageError.invalidCredentials
            }
            throw AlibabaTokenPlanUsageError.apiError(message)
        }

        let codeText = self.findFirstString(forKeys: ["code", "status", "statusCode"], in: dictionary)?.lowercased()
        let messageText = self.findFirstString(forKeys: ["message", "msg", "statusMessage"], in: dictionary)?
            .lowercased()
        if self.isLoginOrTokenError(code: codeText, message: messageText) {
            throw AlibabaTokenPlanUsageError.loginRequired
        }
    }

    private static func isLoginOrTokenError(code: String?, message: String?) -> Bool {
        let combined = [code, message]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return combined.contains("needlogin") ||
            combined.contains("login") ||
            combined.contains("postonlyortokenerror") ||
            combined.contains("tokenerror") ||
            combined.contains("request has expired") ||
            combined.contains("refresh page") ||
            combined.contains("请求已经过期")
    }

    private static let planNameKeys = [
        "planName",
        "plan_name",
        "packageName",
        "package_name",
        "commodityName",
        "commodity_name",
        "instanceName",
        "instance_name",
        "displayName",
        "display_name",
        "ProductName",
        "productName",
        "name",
        "title",
        "planType",
        "plan_type",
    ]
    private static let usedQuotaKeys = [
        "usedQuota",
        "used_quota",
        "usedCredits",
        "usedCredit",
        "consumedCredits",
        "usage",
        "used",
        "usedAmount",
        "consumeAmount",
        "usedValue",
        "UsedValue",
        "consumedValue",
        "ConsumedValue",
    ]
    private static let totalQuotaKeys = [
        "totalQuota",
        "total_quota",
        "totalCredits",
        "totalCredit",
        "quota",
        "creditLimit",
        "creditsTotal",
        "monthlyTotalQuota",
        "amount",
        "totalValue",
        "TotalValue",
    ]
    private static let remainingQuotaKeys = [
        "remainingQuota",
        "remainQuota",
        "remainingCredits",
        "remainingCredit",
        "availableCredits",
        "balance",
        "remaining",
        "availableAmount",
        "remainAmount",
        "totalSurplusValue",
        "TotalSurplusValue",
        "surplusValue",
        "SurplusValue",
    ]
    private static let subscriptionCountKeys = [
        "totalCount",
        "TotalCount",
        "subscriptionTotalNumber",
        "SubscriptionTotalNumber",
    ]
    private static let resetDateKeys = [
        "nextRefreshTime",
        "resetTime",
        "periodEndTime",
        "billingCycleEnd",
        "billCycleEndTime",
        "expireTime",
        "expirationTime",
        "endTime",
        "validEndTime",
        "instanceEndTime",
        "nearestExpireDate",
        "NearestExpireDate",
    ]

    private static func findSubscriptionSummary(in payload: [String: Any]) -> [String: Any]? {
        if let data = self.findFirstDictionary(
            forKeys: ["Data", "data", "successResponse", "success_response"],
            in: payload),
            self.containsSubscriptionSummaryFields(data)
        {
            return data
        }
        return self.findFirstDictionary(
            matchingAnyKey: Self.usedQuotaKeys + Self.totalQuotaKeys + Self.remainingQuotaKeys +
                Self.subscriptionCountKeys,
            in: payload)
    }

    private static func containsSubscriptionSummaryFields(_ payload: [String: Any]) -> Bool {
        let keys = self.usedQuotaKeys + self.totalQuotaKeys + self.remainingQuotaKeys + self.subscriptionCountKeys
        return keys.contains { payload[$0] != nil }
    }

    private static func findPlanName(in payload: [String: Any]) -> String? {
        self.anyString(for: self.planNameKeys, in: payload) ??
            self.findFirstString(forKeys: self.planNameKeys, in: payload)
    }

    private static func findResetDate(in payload: [String: Any]) -> Date? {
        self.anyDate(for: self.resetDateKeys, in: payload) ??
            self.findFirstDate(forKeys: self.resetDateKeys, in: payload)
    }

    private static func payloadDiagnostics(payload: [String: Any]) -> String {
        let topKeys = payload.keys.sorted()
        let dataDict = self.findFirstDictionary(
            forKeys: ["Data", "data", "successResponse", "success_response"],
            in: payload)
        let dataKeys = dataDict?.keys.sorted() ?? []
        return "topKeys=\(topKeys.joined(separator: ",")) dataKeys=\(dataKeys.joined(separator: ","))"
    }

    private static func isLikelyLoginHTML(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return text.contains("<html") &&
            (text.contains("login") || text.contains("sign in") || text.contains("signin"))
    }

    private static func findFirstDictionary(forKeys keys: [String], in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let nested = dict[key] as? [String: Any] {
                    return nested
                }
            }
            for nestedValue in dict.values {
                if let nested = self.findFirstDictionary(forKeys: keys, in: nestedValue) {
                    return nested
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for item in array {
                if let nested = self.findFirstDictionary(forKeys: keys, in: item) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func findFirstDictionary(matchingAnyKey keys: [String], in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if keys.contains(where: { dict[$0] != nil }) {
                return dict
            }
            for nestedValue in dict.values {
                if let nested = self.findFirstDictionary(matchingAnyKey: keys, in: nestedValue) {
                    return nested
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for item in array {
                if let nested = self.findFirstDictionary(matchingAnyKey: keys, in: item) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func findFirstString(forKeys keys: [String], in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let parsed = self.parseString(dict[key]) {
                    return parsed
                }
            }
            for nestedValue in dict.values {
                if let parsed = self.findFirstString(forKeys: keys, in: nestedValue) {
                    return parsed
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for item in array {
                if let parsed = self.findFirstString(forKeys: keys, in: item) {
                    return parsed
                }
            }
        }
        return nil
    }

    private static func findBoolValues(forKeys keys: [String], in value: Any) -> [Bool] {
        if let dict = value as? [String: Any] {
            let directValues = keys.compactMap { self.parseBool(dict[$0]) }
            let nestedValues = dict.values.flatMap { self.findBoolValues(forKeys: keys, in: $0) }
            return directValues + nestedValues
        }
        if let array = value as? [Any] {
            return array.flatMap { self.findBoolValues(forKeys: keys, in: $0) }
        }
        return []
    }

    private static func findFirstInt(forKeys keys: [String], in value: Any) -> Int? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let parsed = self.parseInt(dict[key]) {
                    return parsed
                }
            }
            for nestedValue in dict.values {
                if let parsed = self.findFirstInt(forKeys: keys, in: nestedValue) {
                    return parsed
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for item in array {
                if let parsed = self.findFirstInt(forKeys: keys, in: item) {
                    return parsed
                }
            }
        }
        return nil
    }

    private static func findFirstDate(forKeys keys: [String], in value: Any) -> Date? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let parsed = self.parseDate(dict[key]) {
                    return parsed
                }
            }
            for nestedValue in dict.values {
                if let parsed = self.findFirstDate(forKeys: keys, in: nestedValue) {
                    return parsed
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for item in array {
                if let parsed = self.findFirstDate(forKeys: keys, in: item) {
                    return parsed
                }
            }
        }
        return nil
    }

    private static func expandedJSON(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var expanded: [String: Any] = [:]
            expanded.reserveCapacity(dict.count)
            for (key, nested) in dict {
                expanded[key] = self.expandedJSON(nested)
            }
            return expanded
        }
        if let array = value as? [Any] {
            return array.map { self.expandedJSON($0) }
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let nested = try? JSONSerialization.jsonObject(with: data, options: []),
           nested is [String: Any] || nested is [Any]
        {
            return self.expandedJSON(nested)
        }
        return value
    }

    private static func anyString(for keys: [String], in dict: [String: Any]) -> String? {
        for key in keys {
            if let value = self.parseString(dict[key]) {
                return value
            }
        }
        return nil
    }

    private static func anyDouble(for keys: [String], in dict: [String: Any]) -> Double? {
        for key in keys {
            if let value = self.parseDouble(dict[key]) {
                return value
            }
        }
        return nil
    }

    private static func anyDate(for keys: [String], in dict: [String: Any]) -> Date? {
        for key in keys {
            if let value = self.parseDate(dict[key]) {
                return value
            }
        }
        return nil
    }

    private static func anyBool(for keys: [String], in dict: [String: Any]) -> Bool? {
        for key in keys {
            if let value = self.parseBool(dict[key]) {
                return value
            }
        }
        return nil
    }

    private static func parseInt(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = self.parseString(raw) { return Int(value) }
        return nil
    }

    private static func parseDouble(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? Int64 { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = self.parseString(raw) {
            let cleaned = value.replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }
        return nil
    }

    private static func parseString(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        if let intValue = self.parseInt(raw) {
            if intValue > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(intValue) / 1000)
            }
            if intValue > 1_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(intValue))
            }
        }
        if let string = self.parseString(raw) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: string) {
                return date
            }
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"] {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: string) {
                    return date
                }
            }
        }
        return nil
    }

    private static func parseBool(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber { return number.boolValue }
        guard let string = self.parseString(raw)?.lowercased() else { return nil }
        switch string {
        case "true", "1", "yes", "active", "valid", "normal":
            return true
        case "false", "0", "no", "inactive", "invalid", "expired":
            return false
        default:
            return nil
        }
    }

    private static func extractCookieValue(name: String, from cookieHeader: String) -> String? {
        cookieHeader
            .split(separator: ";")
            .compactMap { part -> (String, String)? in
                let pieces = part.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pieces.count == 2 else { return nil }
                return (pieces[0], pieces[1])
            }
            .first { $0.0 == name }?
            .1
    }

    private static func hasCSRF(in cookieHeader: String) -> Bool {
        self.extractCookieValue(name: "login_aliyunid_csrf", from: cookieHeader) != nil ||
            self.extractCookieValue(name: "csrf", from: cookieHeader) != nil
    }

    static func cookieNames(from cookieHeader: String) -> [String] {
        CookieHeaderNormalizer.pairs(from: cookieHeader)
            .map(\.name)
            .filter { !$0.isEmpty }
            .uniquedSorted()
    }

    static func cookieNamesDescription(from cookieHeader: String) -> String {
        let names = self.cookieNames(from: cookieHeader)
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    private static func extractSECToken(from html: String) -> String? {
        let patterns = [
            #""secToken"\s*:\s*"([^"]+)""#,
            #""sec_token"\s*:\s*"([^"]+)""#,
            #"secToken['"]?\s*[:=]\s*['"]([^'"]+)['"]"#,
            #"sec_token['"]?\s*[:=]\s*['"]([^'"]+)['"]"#,
        ]
        for pattern in patterns {
            if let token = self.matchFirstGroup(pattern: pattern, in: html), !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private static func matchFirstGroup(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let value = text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }
}

extension [String] {
    fileprivate func uniquedSorted() -> [String] {
        Array(Set(self)).sorted()
    }
}
