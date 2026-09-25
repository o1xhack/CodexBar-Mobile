import Foundation
import SweetCookieKit

public enum ZedProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    private static var browserCookieOrder: BrowserCookieImportOrder? {
        #if os(macOS)
        [.chrome]
        #else
        nil
        #endif
    }

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .zed,
            settingsSection: .init(
                ZedProviderSettingsKey.self,
                cookieSettings: { $0 },
                credentialSettings: { context in
                    CookieProviderSettings(
                        cookieSource: context.config?.cookieSource
                            ?? (context.config?.sanitizedCookieHeader == nil ? .off : .manual),
                        manualCookieHeader: context.config?.sanitizedCookieHeader)
                }),
            metadata: ProviderMetadata(
                id: .zed,
                displayName: "Zed",
                sessionLabel: "Edit predictions",
                weeklyLabel: "Billing cycle",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Zed usage",
                cliName: "zed",
                defaultEnabled: false,
                widgetSelectable: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                sharePlanLabels: [
                    "zed free": "Zed Free", "zed pro": "Zed Pro", "zed pro trial": "Zed Pro Trial",
                    "zed student": "Zed Student", "zed business": "Zed Business",
                ],
                browserCookieOrder: self.browserCookieOrder,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .init(provider: .zed),
                iconResourceName: "ProviderIcon-zed",
                color: ProviderColor(red: 8 / 255, green: 78 / 255, blue: 255 / 255),
                confettiPalette: [
                    ProviderColor(hex: 0x084CCF),
                    ProviderColor(hex: 0x000000),
                    ProviderColor(hex: 0xFFFFFF),
                ],
                widgetColor: ProviderColor(red: 64 / 255, green: 156 / 255, blue: 255 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Zed cost summary is not supported." }),
            presentation: ProviderUsagePresentation(
                costPresenter: { _ in ProviderCostPresentation(menuCardStyle: .hidden) }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    let cookies = context.settings?[ZedProviderSettingsKey.self]?.cookieSource ?? .off
                    if context.sourceMode == .api || (context.sourceMode == .auto && cookies == .off) {
                        return [ZedLocalFetchStrategy()]
                    }
                    return [ScriptFetchStrategy(
                        id: "zed.web",
                        provider: .zed,
                        bundledPlugin: "zed",
                        sourceLabel: "web",
                        kind: .web,
                        resolveValues: { context in
                            guard context.settings?[ZedProviderSettingsKey.self]?.cookieSource != nil,
                                  context.settings?[ZedProviderSettingsKey.self]?.cookieSource != .off
                            else { return nil }
                            return .init(settings: ["SOURCE": "web"])
                        },
                        isEnabled: { _ in true })]
                })),
            cli: ProviderCLIConfig(
                name: "zed",
                versionDetector: nil))
    }
}

struct ZedLocalFetchStrategy: ProviderFetchStrategy {
    let id: String = "zed.local"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let snapshot = try await ZedStatusProbe().fetch()
        return self.makeResult(usage: snapshot, sourceLabel: "local")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

public enum ZedProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.zed
    public typealias Section = CookieProviderSettings
}
