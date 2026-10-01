import Foundation

public enum HuggingFaceProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor(
        credentials: Self.credentials,
        fetchPlan: ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [HuggingFaceScriptFetchStrategy.shared] })))
    private static let credentials = ProviderCredentialAdapter.apiKey(
        environmentKey: HuggingFaceSettingsReader.configAPIKeyEnvironmentKey,
        resolve: { HuggingFaceSettingsReader.apiKey(environment: $0) },
        tokenAccountSupport: TokenAccountSupport(
            title: "API tokens",
            subtitle: "Store multiple Hugging Face access tokens.",
            placeholder: "Paste access token…",
            injection: .environment(key: HuggingFaceSettingsReader.configAPIKeyEnvironmentKey),
            requiresManualCookieSource: false,
            cookieName: nil),
        missingCredentialMessage: { _ in
            "Missing Hugging Face token. Add one in Settings, set HF_TOKEN, or run hf auth login."
        })

    public static let spec = PluginProviderSpec(
        id: .huggingface,
        displayName: "Hugging Face",
        sessionLabel: "Inference",
        weeklyLabel: "ZeroGPU",
        dashboardURL: "https://huggingface.co/settings/billing",
        statusPageURL: "https://status.huggingface.co",
        color: ProviderColor(hex: 0xFFD21E),
        confetti: [0xFFD21E, 0xFF9D00, 0x6B7280],
        noDataMessage: "Hugging Face usage comes from the billing API; cost history is not tracked.",
        environmentKey: HuggingFaceSettingsReader.configAPIKeyEnvironmentKey,
        environmentAliases: HuggingFaceSettingsReader.apiKeyEnvironmentKeys,
        menuBarMetrics: ProviderMenuBarMetricCapabilities(supported: [.automatic, .secondary]),
        presentation: ProviderUsagePresentation(
            costPresenter: { _ in
                ProviderCostPresentation(showsGenericFallback: false, menuCardStyle: .hidden)
            }),
        aliases: ["hf"],
        apiKeyField: .init(
            id: "huggingface-api-token",
            title: "Access token",
            subtitle: "Create a token at huggingface.co/settings/tokens. Classic read tokens work; "
                + "fine-grained tokens need the Billing read permission.",
            placeholder: "Paste access token…",
            action: ("huggingface-open-tokens", "Open Hugging Face", "https://huggingface.co/settings/tokens")),
        showsAPIDetail: true,
        availability: .configuredKeyOrAccount)
}

final class HuggingFaceScriptFetchStrategy: ProviderFetchStrategy {
    static let shared = HuggingFaceScriptFetchStrategy()
    let id = "huggingface.js"
    let kind: ProviderFetchKind = .apiToken
    private let gate = AsyncOperationGate()
    private let script: ScriptFetchStrategy

    init(transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) {
        self.script = ScriptFetchStrategy(
            id: "huggingface.js",
            provider: .huggingface,
            bundledPlugin: "huggingface",
            secretKey: "HF_TOKEN",
            sourceLabel: "api",
            transport: transport,
            resolveSecret: { HuggingFaceSettingsReader.apiKey(environment: $0) },
            isEnabled: { _ in true })
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        await self.script.isAvailable(context)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        // Keep the token-scoped identity cache alive without overlapping the engine's fetch watchdogs.
        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await self.gate.acquire(id: id)
        } onCancel: {
            Task { await self.gate.cancel(id: id) }
        }
        guard acquired else { throw CancellationError() }
        do {
            try Task.checkCancellation()
            let result = try await self.script.fetch(context)
            try Task.checkCancellation()
            await self.gate.release(id: id)
            return result
        } catch {
            await self.gate.release(id: id)
            throw error
        }
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool { false }
}
