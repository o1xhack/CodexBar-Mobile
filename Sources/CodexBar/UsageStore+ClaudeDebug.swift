import AppKit
import CodexBarCore
import Foundation
import SweetCookieKit

@MainActor
extension UsageStore {
    func debugClaudeDump() async -> String {
        await ClaudeStatusProbe.latestDumps()
    }
}

extension UsageStore {
    struct ClaudeDebugLogConfiguration {
        let runtime: CodexBarCore.ProviderRuntime
        let sourceMode: ProviderSourceMode
        let environment: [String: String]
        let webExtrasEnabled: Bool
        let usageDataSource: ClaudeUsageDataSource
        let cookieSource: ProviderCookieSource
        let cookieHeader: String
        let keepCLISessionsAlive: Bool
    }

    static func debugClaudeLog(
        browserDetection: BrowserDetection,
        configuration: ClaudeDebugLogConfiguration) async -> String
    {
        struct OAuthDebugProbe: Sendable {
            let hasCredentials: Bool
            let ownerRawValue: String
            let sourceRawValue: String
            let isExpired: Bool
        }

        return await runWithTimeout(seconds: 15) {
            var lines: [String] = []
            let manualHeader = configuration.cookieSource == .manual
                ? CookieHeaderNormalizer.normalize(configuration.cookieHeader)
                : nil
            let hasKey = if configuration.cookieSource == .off {
                false
            } else if let manualHeader {
                ClaudeWebAPIFetcher.hasSessionKey(cookieHeader: manualHeader)
            } else {
                ClaudeWebAPIFetcher.hasSessionKey(browserDetection: browserDetection) { msg in lines.append(msg) }
            }
            let oauthProbe = await withTaskGroup(of: OAuthDebugProbe.self) { group in
                // Preserve task-local test overrides while keeping the keychain read off the calling task.
                group.addTask(priority: .utility) {
                    let oauthRecord = try? ClaudeOAuthCredentialsStore.loadRecord(
                        environment: configuration.environment,
                        allowKeychainPrompt: false,
                        respectKeychainPromptCooldown: true,
                        allowClaudeKeychainRepairWithoutPrompt: false)
                    return OAuthDebugProbe(
                        hasCredentials: oauthRecord?.credentials.scopes.contains("user:profile") == true,
                        ownerRawValue: oauthRecord?.owner.rawValue ?? "none",
                        sourceRawValue: oauthRecord?.source.rawValue ?? "none",
                        isExpired: oauthRecord?.credentials.isExpired ?? false)
                }
                return await group.next() ?? OAuthDebugProbe(
                    hasCredentials: false,
                    ownerRawValue: "none",
                    sourceRawValue: "none",
                    isExpired: false)
            }
            let hasOAuthCredentials = ClaudeOAuthPlanningAvailability.isAvailable(
                runtime: configuration.runtime,
                sourceMode: configuration.sourceMode,
                environment: configuration.environment)
            let hasClaudeBinary = ClaudeCLIResolver.isAvailable(environment: configuration.environment)
            let delegatedCooldownSeconds = ClaudeOAuthDelegatedRefreshCoordinator.cooldownRemainingSeconds()
            let planningInput = ClaudeSourcePlanningInput(
                runtime: configuration.runtime,
                selectedDataSource: configuration.usageDataSource,
                webExtrasEnabled: configuration.webExtrasEnabled,
                hasWebSession: hasKey,
                hasCLI: hasClaudeBinary,
                hasOAuthCredentials: hasOAuthCredentials)
            let plan = ClaudeSourcePlanner.resolve(input: planningInput)
            let strategy = plan.compatibilityStrategy

            lines.append(contentsOf: plan.debugLines())
            lines.append("hasSessionKey=\(hasKey)")
            lines.append("hasOAuthCredentials=\(hasOAuthCredentials)")
            lines.append("oauthCredentialOwner=\(oauthProbe.ownerRawValue)")
            lines.append("oauthCredentialSource=\(oauthProbe.sourceRawValue)")
            lines.append("oauthCredentialExpired=\(oauthProbe.isExpired)")
            lines.append("delegatedRefreshCLIAvailable=\(hasClaudeBinary)")
            lines.append("delegatedRefreshCooldownActive=\(delegatedCooldownSeconds != nil)")
            if let delegatedCooldownSeconds {
                lines.append("delegatedRefreshCooldownSeconds=\(delegatedCooldownSeconds)")
            }
            lines.append("hasClaudeBinary=\(hasClaudeBinary)")
            if strategy?.useWebExtras == true {
                lines.append("web_extras=enabled")
            }
            lines.append("")

            guard let strategy else {
                lines.append("No planner-selected Claude source.")
                return lines.joined(separator: "\n")
            }

            switch strategy.dataSource {
            case .auto:
                lines.append("Auto source selected.")
                return lines.joined(separator: "\n")
            case .api:
                let hasAdminKey = ProviderTokenResolver.claudeAdminAPIToken(
                    environment: configuration.environment) != nil
                lines.append("Admin API source selected.")
                lines.append("hasAdminAPIKey=\(hasAdminKey)")
                return lines.joined(separator: "\n")
            case .web:
                do {
                    let web: ClaudeWebAPIFetcher.WebUsageData =
                        if let manualHeader {
                            try await ClaudeWebAPIFetcher.fetchUsage(cookieHeader: manualHeader) { msg in
                                lines.append(msg)
                            }
                        } else {
                            try await ClaudeWebAPIFetcher.fetchUsage(browserDetection: browserDetection) { msg in
                                lines.append(msg)
                            }
                        }
                    lines.append("")
                    lines.append("Web API summary:")

                    let sessionReset = web.sessionResetsAt?.description ?? "nil"
                    lines.append("session_used=\(web.sessionPercentUsed)% resetsAt=\(sessionReset)")

                    if let weekly = web.weeklyPercentUsed {
                        let weeklyReset = web.weeklyResetsAt?.description ?? "nil"
                        lines.append("weekly_used=\(weekly)% resetsAt=\(weeklyReset)")
                    } else {
                        lines.append("weekly_used=nil")
                    }

                    lines.append("opus_used=\(web.opusPercentUsed?.description ?? "nil")")

                    if let extra = web.extraUsageCost {
                        let resetsAt = extra.resetsAt?.description ?? "nil"
                        let period = extra.period ?? "nil"
                        let line =
                            "extra_usage used=\(extra.used) limit=\(extra.limit) " +
                            "currency=\(extra.currencyCode) period=\(period) resetsAt=\(resetsAt)"
                        lines.append(line)
                    } else {
                        lines.append("extra_usage=nil")
                    }

                    return lines.joined(separator: "\n")
                } catch {
                    lines.append("Web API failed: \(error.localizedDescription)")
                    return lines.joined(separator: "\n")
                }
            case .cli:
                let fetcher = ClaudeUsageFetcher(
                    browserDetection: browserDetection,
                    environment: configuration.environment,
                    runtime: configuration.runtime,
                    dataSource: configuration.usageDataSource,
                    keepCLISessionsAlive: configuration.keepCLISessionsAlive)
                let cli = await fetcher.debugRawProbe(model: "sonnet")
                lines.append(cli)
                return lines.joined(separator: "\n")
            case .oauth:
                lines.append("OAuth source selected.")
                return lines.joined(separator: "\n")
            }
        }
    }
}

extension UsageStore {
    func debugDumpClaude() async {
        let fetcher = ClaudeUsageFetcher(
            browserDetection: self.browserDetection,
            keepCLISessionsAlive: self.settings.debugKeepCLISessionsAlive)
        let output = await fetcher.debugRawProbe(model: "sonnet")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codexbar-claude-probe.txt")
        try? output.write(to: url, atomically: true, encoding: .utf8)
        await MainActor.run {
            let snippet = String(output.prefix(180)).replacingOccurrences(of: "\n", with: " ")
            self.errors[.claude] = "[Claude] \(snippet) (saved: \(url.path))"
            NSWorkspace.shared.open(url)
        }
    }

    func dumpLog(toFileFor provider: UsageProvider) async -> URL? {
        let text = await self.debugLog(for: provider)
        let filename = "codexbar-\(provider.rawValue)-probe.txt"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
            return url
        } catch {
            await MainActor.run {
                self.errors[provider] = "Failed to save log: \(error.localizedDescription)"
            }
            return nil
        }
    }

    func debugAugmentDump() async -> String {
        await AugmentStatusProbe.latestDumps()
    }

    // swiftlint:disable:next function_body_length
    func debugLog(for provider: UsageProvider) async -> String {
        if let cached = self.probeLogs[provider], !cached.isEmpty {
            return cached
        }

        let claudeWebExtrasEnabled = self.settings.claudeWebExtrasEnabled
        let claudeUsageDataSource = self.settings.claudeUsageDataSource
        let claudeCookieSource = self.settings.claudeCookieSource
        let claudeCookieHeader = self.settings.claudeCookieHeader
        let claudeDebugConfiguration: ClaudeDebugLogConfiguration? = if provider == .claude {
            await self.makeClaudeDebugConfiguration(
                fallbackUsageDataSource: claudeUsageDataSource,
                fallbackWebExtrasEnabled: claudeWebExtrasEnabled,
                fallbackCookieSource: claudeCookieSource,
                fallbackCookieHeader: claudeCookieHeader)
        } else {
            nil
        }
        let cursorCookieSource = self.settings.cursorCookieSource
        let cursorCookieHeader = self.settings.cursorCookieHeader
        let ampCookieSource = self.settings.ampCookieSource
        let ampCookieHeader = self.settings.ampCookieHeader
        let ollamaCookieSource = self.settings.ollamaCookieSource
        let ollamaCookieHeader = self.settings.ollamaCookieHeader
        let processEnvironment = self.environmentBase
        let openAIDebugContext = self.openAIAPIKeyDebugContext(processEnvironment: processEnvironment)
        let azureOpenAIDebugContext = self.azureOpenAIAPIKeyDebugContext(processEnvironment: processEnvironment)
        let openRouterDebugContext = self.openRouterAPIKeyDebugContext(processEnvironment: processEnvironment)
        let elevenLabsDebugContext = self.elevenLabsAPIKeyDebugContext(processEnvironment: processEnvironment)
        let deepSeekHasEnvToken = DeepSeekSettingsReader.apiKey(environment: processEnvironment) != nil
        let deepSeekHasTokenAccount = self.settings.selectedTokenAccount(for: .deepseek) != nil
        let deepSeekEnvironment = ProviderRegistry.makeEnvironment(
            base: processEnvironment,
            provider: .deepseek,
            settings: self.settings,
            tokenOverride: nil)
        let codexFetcher = self.codexFetcher
        let browserDetection = self.browserDetection
        let claudeDebugExecutionContext = self.currentClaudeDebugExecutionContext()
        let text = await Task.detached(priority: .utility) { () -> String in
            let unimplementedDebugLogMessages: [UsageProvider: String] = [
                .gemini: "Gemini debug log not yet implemented",
                .antigravity: "Antigravity debug log not yet implemented",
                .opencode: "OpenCode debug log not yet implemented",
                .alibaba: "Alibaba Coding Plan debug log not yet implemented",
                .alibabatokenplan: "Alibaba Token Plan debug log not yet implemented",
                .factory: "Droid debug log not yet implemented",
                .copilot: "Copilot debug log not yet implemented",
                .manus: "Manus debug log not yet implemented",
                .vertexai: "Vertex AI debug log not yet implemented",
                .kilo: "Kilo debug log not yet implemented",
                .kiro: "Kiro debug log not yet implemented",
                .kimi: "Kimi debug log not yet implemented",
                .kimik2: "Kimi K2 debug log not yet implemented",
                .jetbrains: "JetBrains AI debug log not yet implemented",
                .mimo: "Xiaomi MiMo debug log not yet implemented",
                .doubao: "Doubao debug log not yet implemented",
                .venice: "Venice debug log not yet implemented",
                .commandcode: "Command Code debug log not yet implemented",
                .stepfun: "StepFun debug log not yet implemented",
                .bedrock: "Bedrock debug log not yet implemented",
                .grok: "Grok debug log not yet implemented",
                .groq: "Groq debug log not yet implemented",
                .t3chat: "T3 Chat debug log not yet implemented",
                .llmproxy: "LLM Proxy debug log not yet implemented",
                .deepgram: "Deepgram debug log not yet implemented",
            ]
            let buildText = {
                switch provider {
                case .codex:
                    return await codexFetcher.debugRawRateLimits()
                case .openai:
                    return Self.apiKeyDebugLine(openAIDebugContext)
                case .azureopenai:
                    return Self.apiKeyDebugLine(azureOpenAIDebugContext)
                case .claude:
                    guard let claudeDebugConfiguration else {
                        return "Claude debug log configuration unavailable"
                    }
                    return await claudeDebugExecutionContext.apply {
                        await Self.debugClaudeLog(
                            browserDetection: browserDetection,
                            configuration: claudeDebugConfiguration)
                    }
                case .zai:
                    let resolution = ProviderTokenResolver.zaiResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "Z_AI_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .synthetic:
                    let resolution = ProviderTokenResolver.syntheticResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "SYNTHETIC_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .cursor:
                    return await Self.debugCursorLog(
                        browserDetection: browserDetection,
                        cursorCookieSource: cursorCookieSource,
                        cursorCookieHeader: cursorCookieHeader)
                case .minimax:
                    let tokenResolution = ProviderTokenResolver.minimaxTokenResolution()
                    let cookieResolution = ProviderTokenResolver.minimaxCookieResolution()
                    let tokenSource = tokenResolution?.source.rawValue ?? "none"
                    let cookieSource = cookieResolution?.source.rawValue ?? "none"
                    return "MINIMAX_API_KEY=\(tokenResolution == nil ? "missing" : "present") " +
                        "source=\(tokenSource) MINIMAX_COOKIE=\(cookieResolution == nil ? "missing" : "present") " +
                        "source=\(cookieSource)"
                case .alibaba:
                    let resolution = ProviderTokenResolver.alibabaTokenResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "ALIBABA_CODING_PLAN_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .augment:
                    return await Self.debugAugmentLog()
                case .amp:
                    return await Self.debugAmpLog(
                        browserDetection: browserDetection,
                        ampCookieSource: ampCookieSource,
                        ampCookieHeader: ampCookieHeader)
                case .ollama:
                    return await Self.debugOllamaLog(
                        browserDetection: browserDetection,
                        ollamaCookieSource: ollamaCookieSource,
                        ollamaCookieHeader: ollamaCookieHeader)
                case .openrouter:
                    return Self.apiKeyDebugLine(openRouterDebugContext)
                case .elevenlabs:
                    return Self.apiKeyDebugLine(elevenLabsDebugContext)
                case .warp:
                    let resolution = ProviderTokenResolver.warpResolution()
                    let hasAny = resolution != nil
                    let source = resolution?.source.rawValue ?? "none"
                    return "WARP_API_KEY=\(hasAny ? "present" : "missing") source=\(source)"
                case .deepseek:
                    return Self.apiKeyDebugLine(
                        label: "DEEPSEEK_API_KEY",
                        resolution: ProviderTokenResolver.deepseekResolution(environment: deepSeekEnvironment),
                        configToken: nil,
                        hasEnvToken: deepSeekHasEnvToken,
                        hasTokenAccount: deepSeekHasTokenAccount)
                case .gemini, .antigravity, .opencode, .opencodego, .alibabatokenplan, .factory, .copilot,
                     .vertexai, .kilo, .kiro, .kimi, .kimik2, .moonshot, .jetbrains, .perplexity, .mimo, .doubao,
                     .abacus, .mistral, .codebuff, .crof, .windsurf, .venice, .manus, .commandcode, .stepfun, .bedrock,
                     .grok, .groq, .t3chat, .llmproxy, .deepgram:
                    return unimplementedDebugLogMessages[provider] ?? "Debug log not yet implemented"
                }
            }
            return await claudeDebugExecutionContext.apply {
                await buildText()
            }
        }.value
        self.probeLogs[provider] = text
        return text
    }

    private func makeClaudeDebugConfiguration(
        fallbackUsageDataSource: ClaudeUsageDataSource,
        fallbackWebExtrasEnabled: Bool,
        fallbackCookieSource: ProviderCookieSource,
        fallbackCookieHeader: String) async -> ClaudeDebugLogConfiguration
    {
        await MainActor.run {
            let sourceMode = self.sourceMode(for: .claude)
            let snapshot = ProviderRegistry.makeSettingsSnapshot(settings: self.settings, tokenOverride: nil)
            let environment = ProviderRegistry.makeEnvironment(
                base: self.environmentBase,
                provider: .claude,
                settings: self.settings,
                tokenOverride: nil)
            let claudeSettings = snapshot.claude ?? ProviderSettingsSnapshot.ClaudeProviderSettings(
                usageDataSource: fallbackUsageDataSource,
                webExtrasEnabled: fallbackWebExtrasEnabled,
                cookieSource: fallbackCookieSource,
                manualCookieHeader: fallbackCookieHeader)
            return ClaudeDebugLogConfiguration(
                runtime: CodexBarCore.ProviderRuntime.app,
                sourceMode: sourceMode,
                environment: environment,
                webExtrasEnabled: claudeSettings.webExtrasEnabled,
                usageDataSource: claudeSettings.usageDataSource,
                cookieSource: claudeSettings.cookieSource,
                cookieHeader: claudeSettings.manualCookieHeader ?? "",
                keepCLISessionsAlive: snapshot.debugKeepCLISessionsAlive)
        }
    }

    private struct ClaudeDebugExecutionContext {
        let interaction: ProviderInteraction
        let refreshPhase: ProviderRefreshPhase
        #if DEBUG
        let keychainServiceOverride: String?
        let credentialsURLOverride: URL?
        let testingOverrides: ClaudeOAuthCredentialsStore.TestingOverridesSnapshot
        let keychainDeniedUntilStoreOverride: ClaudeOAuthKeychainAccessGate.DeniedUntilStore?
        let keychainPromptModeOverride: ClaudeOAuthKeychainPromptMode?
        let keychainReadStrategyOverride: ClaudeOAuthKeychainReadStrategy?
        let cliPathOverride: String?
        let statusFetchOverride: ClaudeStatusProbe.FetchOverride?
        #endif

        func apply<T>(_ operation: () async -> T) async -> T {
            await ProviderInteractionContext.$current.withValue(self.interaction) {
                await ProviderRefreshContext.$current.withValue(self.refreshPhase) {
                    #if DEBUG
                    return await KeychainCacheStore.withServiceOverrideForTesting(self.keychainServiceOverride) {
                        await ClaudeOAuthCredentialsStore
                            .withCredentialsURLOverrideForTesting(self.credentialsURLOverride) {
                                await ClaudeOAuthCredentialsStore
                                    .withTestingOverridesSnapshotForTask(self.testingOverrides) {
                                        await ClaudeOAuthKeychainAccessGate
                                            .withDeniedUntilStoreOverrideForTesting(self
                                                .keychainDeniedUntilStoreOverride)
                                            {
                                                await ClaudeOAuthKeychainPromptPreference
                                                    .withTaskOverrideForTesting(self.keychainPromptModeOverride) {
                                                        await ClaudeOAuthKeychainReadStrategyPreference
                                                            .withTaskOverrideForTesting(self
                                                                .keychainReadStrategyOverride)
                                                            {
                                                                await ClaudeCLIResolver
                                                                    .withResolvedBinaryPathOverrideForTesting(self
                                                                        .cliPathOverride)
                                                                    {
                                                                        await ClaudeStatusProbe
                                                                            .withFetchOverrideForTesting(self
                                                                                .statusFetchOverride)
                                                                            {
                                                                                await operation()
                                                                            }
                                                                    }
                                                            }
                                                    }
                                            }
                                    }
                            }
                    }
                    #else
                    return await operation()
                    #endif
                }
            }
        }
    }

    private func currentClaudeDebugExecutionContext() -> ClaudeDebugExecutionContext {
        #if DEBUG
        ClaudeDebugExecutionContext(
            interaction: ProviderInteractionContext.current,
            refreshPhase: ProviderRefreshContext.current,
            keychainServiceOverride: KeychainCacheStore.currentServiceOverrideForTesting,
            credentialsURLOverride: ClaudeOAuthCredentialsStore.currentCredentialsURLOverrideForTesting,
            testingOverrides: ClaudeOAuthCredentialsStore.currentTestingOverridesSnapshotForTask,
            keychainDeniedUntilStoreOverride: ClaudeOAuthKeychainAccessGate.currentDeniedUntilStoreOverrideForTesting,
            keychainPromptModeOverride: ClaudeOAuthKeychainPromptPreference.currentTaskOverrideForTesting,
            keychainReadStrategyOverride: ClaudeOAuthKeychainReadStrategyPreference.currentTaskOverrideForTesting,
            cliPathOverride: ClaudeCLIResolver.currentResolvedBinaryPathOverrideForTesting,
            statusFetchOverride: ClaudeStatusProbe.currentFetchOverrideForTesting)
        #else
        ClaudeDebugExecutionContext(
            interaction: ProviderInteractionContext.current,
            refreshPhase: ProviderRefreshContext.current)
        #endif
    }

    private struct APIKeyDebugContext {
        let label: String
        let resolution: ProviderTokenResolution?
        let configToken: String?
        let hasEnvToken: Bool
        let hasTokenAccount: Bool
    }

    private func openAIAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .openai)
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .openai,
            config: config)
        return APIKeyDebugContext(
            label: "OPENAI_API_KEY",
            resolution: ProviderTokenResolver.openAIAPIResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: OpenAIAPISettingsReader.apiKey(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }

    private func azureOpenAIAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .azureopenai)
        let environment = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: processEnvironment,
            provider: .azureopenai,
            config: config)
        return APIKeyDebugContext(
            label: "AZURE_OPENAI_API_KEY",
            resolution: ProviderTokenResolver.azureOpenAIResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: AzureOpenAISettingsReader.apiKey(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }

    private func openRouterAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .openrouter)
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .openrouter,
            config: config)
        return APIKeyDebugContext(
            label: "OPENROUTER_API_KEY",
            resolution: ProviderTokenResolver.openRouterResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: OpenRouterSettingsReader.apiToken(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }

    private func elevenLabsAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .elevenlabs)
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .elevenlabs,
            config: config)
        return APIKeyDebugContext(
            label: "ELEVENLABS_API_KEY",
            resolution: ProviderTokenResolver.elevenLabsResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: ElevenLabsSettingsReader.apiKey(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }

    private nonisolated static func apiKeyDebugLine(_ context: APIKeyDebugContext) -> String {
        self.apiKeyDebugLine(
            label: context.label,
            resolution: context.resolution,
            configToken: context.configToken,
            hasEnvToken: context.hasEnvToken,
            hasTokenAccount: context.hasTokenAccount)
    }

    private nonisolated static func apiKeyDebugLine(
        label: String,
        resolution: ProviderTokenResolution?,
        configToken: String?,
        hasEnvToken: Bool,
        hasTokenAccount: Bool = false) -> String
    {
        let hasAny = resolution != nil
        let hasConfigToken = !(configToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let source: String = if resolution == nil {
            "none"
        } else if hasTokenAccount, hasEnvToken {
            "settings-token-account (overrides env)"
        } else if hasTokenAccount {
            "settings-token-account"
        } else if hasConfigToken, hasEnvToken {
            "settings-config (overrides env)"
        } else if hasConfigToken {
            "settings-config"
        } else {
            resolution?.source.rawValue ?? "environment"
        }
        return "\(label)=\(hasAny ? "present" : "missing") source=\(source)"
    }

    private static func debugCursorLog(
        browserDetection: BrowserDetection,
        cursorCookieSource: ProviderCookieSource,
        cursorCookieHeader: String) async -> String
    {
        await runWithTimeout(seconds: 15) {
            var lines: [String] = []

            do {
                let probe = CursorStatusProbe(browserDetection: browserDetection)
                let snapshot: CursorStatusSnapshot = if cursorCookieSource == .manual,
                                                        let normalizedHeader = CookieHeaderNormalizer
                                                            .normalize(cursorCookieHeader)
                {
                    try await probe.fetchWithManualCookies(normalizedHeader)
                } else {
                    try await probe.fetch { msg in lines.append("[cursor-cookie] \(msg)") }
                }

                lines.append("")
                lines.append("Cursor Status Summary:")
                lines.append("membershipType=\(snapshot.membershipType ?? "nil")")
                lines.append("accountEmail=\(EmailRedaction.redact(snapshot.accountEmail))")
                lines.append("planPercentUsed=\(snapshot.planPercentUsed)%")
                lines.append("planUsedUSD=$\(snapshot.planUsedUSD)")
                lines.append("planLimitUSD=$\(snapshot.planLimitUSD)")
                lines.append("onDemandUsedUSD=$\(snapshot.onDemandUsedUSD)")
                lines.append("onDemandLimitUSD=\(snapshot.onDemandLimitUSD.map { "$\($0)" } ?? "nil")")
                if let teamUsed = snapshot.teamOnDemandUsedUSD {
                    lines.append("teamOnDemandUsedUSD=$\(teamUsed)")
                }
                if let teamLimit = snapshot.teamOnDemandLimitUSD {
                    lines.append("teamOnDemandLimitUSD=$\(teamLimit)")
                }
                lines.append("billingCycleEnd=\(snapshot.billingCycleEnd?.description ?? "nil")")

                if let rawJSON = snapshot.rawJSON {
                    lines.append("")
                    lines.append("Raw API Response:")
                    lines.append(rawJSON)
                }

                return lines.joined(separator: "\n")
            } catch {
                lines.append("")
                lines.append("Cursor probe failed: \(error.localizedDescription)")
                return lines.joined(separator: "\n")
            }
        }
    }

    private static func debugAugmentLog() async -> String {
        await runWithTimeout(seconds: 15) {
            let probe = AugmentStatusProbe()
            return await probe.debugRawProbe()
        }
    }

    private static func debugAmpLog(
        browserDetection: BrowserDetection,
        ampCookieSource: ProviderCookieSource,
        ampCookieHeader: String) async -> String
    {
        await runWithTimeout(seconds: 15) {
            let fetcher = AmpUsageFetcher(browserDetection: browserDetection)
            let manualHeader = ampCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(ampCookieHeader)
                : nil
            return await fetcher.debugRawProbe(cookieHeaderOverride: manualHeader)
        }
    }

    private static func debugOllamaLog(
        browserDetection: BrowserDetection,
        ollamaCookieSource: ProviderCookieSource,
        ollamaCookieHeader: String) async -> String
    {
        await runWithTimeout(seconds: 15) {
            let fetcher = OllamaUsageFetcher(browserDetection: browserDetection)
            let manualHeader = ollamaCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(ollamaCookieHeader)
                : nil
            return await fetcher.debugRawProbe(
                cookieHeaderOverride: manualHeader,
                manualCookieMode: ollamaCookieSource == .manual)
        }
    }
}
