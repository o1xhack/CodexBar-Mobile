import Foundation

public enum PerplexityProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()
    private static let credentials = ProviderCredentialAdapter(
        tokenResolver: { kind, environment, _ in
            guard kind == .primary, let token = Self.resolveSessionToken(environment: environment) else {
                return nil
            }
            return ProviderTokenResolution(token: token, source: .environment)
        },
        authDetector: { environment, _ in
            PerplexitySettingsReader.sessionToken(environment: environment) == nil ? [] : ["web"]
        },
        missingCredentialMessage: { _ in PerplexityAPIError.missingToken.errorDescription })

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .perplexity,
            menuBarMetrics: ProviderMenuBarMetricCapabilities(
                supported: [.automatic, .primary, .secondary, .tertiary]),
            settingsSection: .init(
                PerplexityProviderSettingsKey.self,
                cookieSettings: PerplexityProviderSettings.self),
            credentials: self.credentials,
            metadata: ProviderMetadata(
                id: .perplexity,
                displayName: "Perplexity",
                shortDisplayName: "Pplx",
                sessionLabel: "Credits",
                weeklyLabel: "Bonus credits",
                opusLabel: "Purchased",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Perplexity usage",
                cliName: "perplexity",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                sharePlanLabels: ["pro": "Pro", "max": "Max"],
                usesDetailBackedWindow: true,
                browserCookieOrder: nil,
                dashboardURL: "https://www.perplexity.ai/account/usage",
                statusPageURL: nil,
                statusLinkURL: "https://status.perplexity.com/"),
            branding: ProviderBranding(
                iconStyle: .init(provider: .perplexity),
                iconResourceName: "ProviderIcon-perplexity",
                color: ProviderColor(red: 32 / 255, green: 178 / 255, blue: 170 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x016A71),
                    ProviderColor(hex: 0x313131),
                    ProviderColor(hex: 0xFDFBFA),
                ]),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Perplexity cost tracking is not supported." }),
            presentation: ProviderUsagePresentation(
                iconWindowResolver: { context in
                    let windows = context.snapshot.orderedPerplexityDisplayWindows()
                    return ProviderUsageWindowPair(primary: windows.first, secondary: windows.dropFirst().first)
                },
                semanticWindowResolver: { snapshot in
                    ProviderSemanticWindows(session: snapshot.primary, weekly: snapshot.secondary)
                },
                menuBarLayoutSecondaryLabel: "Bonus credits",
                requestedMenuBarLaneOrders: [
                    .primary: [.primary, .secondary, .tertiary],
                    .secondary: [.secondary, .tertiary, .primary],
                    .tertiary: [.tertiary, .secondary, .primary],
                ],
                automaticSelectionPrioritizesExhaustedWindow: false,
                menuBarWindowResolver: { context in
                    guard context.metric == .automatic else { return .unhandled }
                    return .resolved(context.snapshot.automaticPerplexityWindow())
                },
                menu: ProviderMenuDescriptorPresentation(
                    secondaryDescriptionMode: .resetOverride,
                    tertiaryDescriptionOverridesReset: true)),
            fetchPlan: self.fetchPlan(),
            cli: ProviderCLIConfig(
                name: "perplexity",
                aliases: [],
                versionDetector: nil))
    }

    private static func resolveSessionToken(environment: [String: String]) -> String? {
        if let token = PerplexitySettingsReader.sessionToken(environment: environment) {
            return token
        }
        #if os(macOS)
        return try? PerplexityCookieImporter.importSession().sessionToken
        #else
        return nil
        #endif
    }

    private static func fetchPlan() -> ProviderFetchPlan {
        ProviderFetchPlan(
            sourceModes: [.auto, .web],
            pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                [ScriptFetchStrategy(
                    id: "perplexity.js",
                    provider: .perplexity,
                    bundledPlugin: "perplexity",
                    sourceLabel: "web",
                    kind: .web,
                    resolveValues: { context in
                        guard context.settings?.perplexity?.cookieSource != .off else { return nil }
                        let cookie = PerplexitySettingsReader.sessionCookieOverride(environment: context.env)
                        let value = cookie.map {
                            $0.requestCookieNames.count > 1 ? $0.token : "\($0.name)=\($0.token)"
                        }
                        return .init(secrets: value.map { ["SESSION_COOKIE": $0] } ?? [:])
                    }, isEnabled: { _ in true })]
            }))
    }
}
