import Foundation

public enum QoderProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(tokenAccountSupport: TokenAccountSupport(
        title: "Session tokens",
        subtitle: "Store multiple Qoder Cookie headers.",
        placeholder: "Cookie: …",
        injection: .cookieHeader,
        requiresManualCookieSource: true,
        cookieName: nil))

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .qoder,
            settingsSection: .init(QoderProviderSettingsKey.self, cookieSettings: QoderProviderSettings.self),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .qoder,
                displayName: "Qoder",
                sessionLabel: "Credits",
                weeklyLabel: "Balance",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "Big model credits from the Qoder usage dashboard.",
                toggleTitle: "Show Qoder usage",
                cliName: "qoder",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                debugLogUnavailableMessage: "Qoder debug log not yet implemented",
                usesDetailBackedWindow: true,
                browserCookieOrder: BrowserCookieImportSupport.chromeOnly(
                    reason: "Preserve documented Chrome import without unrelated Keychain prompts"),
                dashboardURL: QoderWebSite.international.dashboardURL.absoluteString,
                statusPageURL: nil,
                statusLinkURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .qoder),
                iconResourceName: "ProviderIcon-qoder",
                color: ProviderColor(red: 16 / 255, green: 185 / 255, blue: 129 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x2ADB5C),
                    ProviderColor(hex: 0x111113),
                    ProviderColor(hex: 0xFFFFFF),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Qoder cost summary is not supported." }),
            presentation: ProviderUsagePresentation(
                menuCard: ProviderMenuCardPresentation(
                    showsPrimaryBalanceDescription: true,
                    hidesPrimaryResetWithoutDate: true),
                menu: ProviderMenuDescriptorPresentation(primaryDescriptionIsDetail: { _ in true })),
            fetchPlan: self.fetchPlan(),
            cli: ProviderCLIConfig(
                name: "qoder",
                aliases: [],
                versionDetector: nil,
                browserSupportExemption: { _, _, settings in
                    settings?.qoder?.cookieSource == .manual
                }))
    }

    private static func fetchPlan() -> ProviderFetchPlan {
        ProviderFetchPlan(
            sourceModes: [.auto, .web],
            pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [QoderPluginFetchStrategy()] }))
    }

    public static func dashboardURL(
        settings: ProviderSettingsSnapshot.QoderProviderSettings?,
        sourceLabel: String?) -> URL
    {
        guard settings?.cookieSource == .manual else {
            return self.dashboardURL(forSourceLabel: sourceLabel)
        }
        return QoderWebSite.allCases.first { $0.webOrigin == settings?.manualCookieOrigin }?.dashboardURL
            ?? QoderWebSite.international.dashboardURL
    }

    public static func dashboardURL(forSourceLabel sourceLabel: String?) -> URL {
        guard let sourceLabel, !sourceLabel.isEmpty else {
            return QoderWebSite.international.dashboardURL
        }
        return QoderCookieRouting.site(for: sourceLabel).dashboardURL
    }
}

struct QoderPluginFetchStrategy: ProviderFetchStrategy {
    let id = "qoder.js"
    let kind: ProviderFetchKind = .web
    private let script: ScriptFetchStrategy

    init(transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) {
        self.script = ScriptFetchStrategy(
            id: "qoder.js",
            provider: .qoder,
            bundledPlugin: "qoder",
            kind: .web,
            transport: transport,
            resolveValues: { context in
                guard context.settings?.qoder?.cookieSource != .off else { return nil }
                return .init(settings: ["REQUEST_TIMEOUT": String(min(30, max(1, context.webTimeout)))])
            }, isEnabled: { _ in true })
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool { await self.script.isAvailable(context) }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let result = try await self.script.fetch(context)
        let source = result.usage.identity?.loginMethod ?? "web"
        let usage = result.usage.withIdentity(ProviderIdentitySnapshot(
            providerID: .qoder,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil))
        return self.makeResult(usage: usage, sourceLabel: source)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool { false }
}
