import Foundation

public enum Kimi2ProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .kimi2,
            metadata: ProviderMetadata(
                id: .kimi2,
                displayName: "Kimi 2",
                sessionLabel: "Weekly",
                weeklyLabel: "Rate Limit",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Kimi2 usage",
                cliName: "kimi2",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://www.kimi.com/code/console",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .kimi,
                iconResourceName: "ProviderIcon-kimi",
                color: ProviderColor(red: 254 / 255, green: 96 / 255, blue: 60 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x000000),
                    ProviderColor(hex: 0x4E6EF2),
                    ProviderColor(hex: 0xFFFFFF),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Kimi2 cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "kimi2",
                aliases: ["kimi2-ai"],
                versionDetector: nil))
    }

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        switch context.sourceMode {
        case .api:
            [Kimi2APIFetchStrategy()]
        case .web:
            [Kimi2WebFetchStrategy()]
        case .auto:
            [Kimi2APIFetchStrategy(), Kimi2CLICredentialFetchStrategy(), Kimi2WebFetchStrategy()]
        case .cli, .oauth:
            []
        }
    }
}

struct Kimi2APIFetchStrategy: ProviderFetchStrategy {
    let id: String = "kimi2.api"
    let kind: ProviderFetchKind = .apiToken
    private let transport: any ProviderHTTPTransport

    init(transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) {
        self.transport = transport
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.sourceMode == .api || Kimi2SettingsReader.apiKey(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Kimi2SettingsReader.apiKey(environment: context.env) else {
            throw Kimi2APIError.missingAPIKey
        }
        let baseURL = try Kimi2SettingsReader.codeAPIBaseURL(environment: context.env)
        let snapshot = try await Kimi2UsageFetcher.fetchCodeAPIUsage(
            apiKey: apiKey,
            baseURL: baseURL,
            transport: self.transport)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "Kimi2 Code API key")
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        Kimi2CodeAPIFallbackPolicy.shouldFallback(on: error, context: context)
    }
}

struct Kimi2CLICredentialFetchStrategy: ProviderFetchStrategy {
    let id: String = "kimi2.cli"
    let kind: ProviderFetchKind = .oauth
    private let transport: any ProviderHTTPTransport

    init(transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) {
        self.transport = transport
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.sourceMode == .auto &&
            Kimi2SettingsReader.hasKimi2CodeCredential(environment: context.env)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let token = Kimi2SettingsReader.kimiCodeAccessToken(environment: context.env) else {
            throw Kimi2APIError.expiredCodeCredential
        }
        let baseURL = try Kimi2SettingsReader.codeAPIBaseURL(environment: context.env)
        let identityHeaders = Kimi2SettingsReader.kimiCodeIdentityHeaders(environment: context.env)
        let snapshot: Kimi2UsageSnapshot
        do {
            snapshot = try await Kimi2UsageFetcher.fetchCodeAPIUsage(
                apiKey: token,
                baseURL: baseURL,
                identityHeaders: identityHeaders,
                transport: self.transport)
        } catch {
            throw Self.normalizedCodeAPIError(error)
        }
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "Kimi2 Code CLI")
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        Kimi2CodeAPIFallbackPolicy.shouldFallback(on: error, context: context)
    }

    static func normalizedCodeAPIError(_ error: Error) -> Error {
        guard case Kimi2APIError.invalidAPIKey = error else { return error }
        return Kimi2APIError.invalidCodeCredential
    }
}

private enum Kimi2CodeAPIFallbackPolicy {
    static func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        guard context.sourceMode == .auto else { return false }
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        if case Kimi2APIError.missingAPIKey = error {
            return true
        }
        if case Kimi2APIError.expiredCodeCredential = error {
            return true
        }
        if case Kimi2APIError.invalidCodeCredential = error {
            return true
        }
        if case Kimi2APIError.invalidAPIKey = error {
            return true
        }
        if case Kimi2APIError.apiError = error {
            return true
        }
        return error is DecodingError
    }
}

struct Kimi2WebFetchStrategy: ProviderFetchStrategy {
    let id: String = "kimi2.web"
    let kind: ProviderFetchKind = .web
    private static let log = CodexBarLog.logger(LogCategories.kimiWeb)

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        if Kimi2CookieHeader.resolveCookieOverride(context: context) != nil {
            return true
        }

        if Self.resolveToken(environment: context.env) != nil {
            return true
        }

        #if os(macOS)
        if context.settings?.kimi2?.cookieSource != .off {
            return Kimi2CookieImporter.hasSession()
        }
        #endif

        return false
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let token = self.resolveToken(context: context) else {
            throw Kimi2APIError.missingToken
        }

        let snapshot = try await Kimi2UsageFetcher.fetchUsage(authToken: token)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "Kimi2 web cookie")
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        if case Kimi2APIError.missingToken = error {
            return false
        }
        if case Kimi2APIError.invalidToken = error {
            return false
        }
        return true
    }

    private func resolveToken(context: ProviderFetchContext) -> String? {
        // Check manual cookie first (highest priority when set)
        if let override = Kimi2CookieHeader.resolveCookieOverride(context: context) {
            return override.token
        }

        // Try browser cookie import when auto mode is enabled
        #if os(macOS)
        if context.settings?.kimi2?.cookieSource != .off {
            do {
                let session = try Kimi2CookieImporter.importSession()
                if let token = session.authToken {
                    return token
                }
            } catch {
                // No browser cookies found
            }
        }
        #endif

        // Fall back to environment
        if let override = Self.resolveToken(environment: context.env) {
            return override
        }
        return nil
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.kimiAuthToken(environment: environment)
    }
}
