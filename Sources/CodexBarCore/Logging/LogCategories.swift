public enum LogCategories {
    public static let iCloudSync = "icloud-sync"

    public static func providerInstance(_ instanceID: ProviderInstanceID, scope: String? = nil) -> String {
        // Provider-specific by design: preserve OpenCode Go's established hyphenated log category.
        let base = instanceID.firstPartyProvider == .opencodego ? "opencode-go" : instanceID.rawValue
        return scope.map { "\(base)-\($0)" } ?? base
    }

    public static func provider(_ provider: UsageProvider, scope: String? = nil) -> String {
        self.providerInstance(provider.instanceID, scope: scope)
    }

    public static let adaptiveRefresh = "adaptive-refresh"
    public static let app = "app"
    public static let auggieCLI = "auggie-cli"
    public static let browserCookieGate = "browser-cookie-gate"
    public static let configMigration = "config-migration"
    public static let configStore = "config-store"
    public static let confetti = "confetti"
    public static let cookieCache = "cookie-cache"
    public static let cookieHeaderStore = "cookie-header-store"
    public static let creditsPurchase = "creditsPurchase"
    public static let hooks = "hooks"
    public static let keychainCache = "keychain-cache"
    public static let keychainMigration = "keychain-migration"
    public static let keychainPreflight = "keychain-preflight"
    public static let keychainPrompt = "keychain-prompt"
    public static let launchAtLogin = "launch-at-login"
    public static let login = "login"
    public static let logging = "logging"
    public static let memoryPressure = "memory-pressure"
    public static let notifications = "notifications"
    public static let notion = Self.provider(.notion)
    public static let openAIWeb = Self.provider(.openai, scope: "web")
    public static let openAIWebview = Self.provider(.openai, scope: "webview")
    public static let ollama = Self.provider(.ollama)
    public static let opencodeUsage = Self.provider(.opencode, scope: "usage")
    public static let opencodeGoUsage = Self.provider(.opencodego, scope: "usage")
    public static let openRouterUsage = Self.provider(.openrouter, scope: "usage")
    public static let perplexityAPI = Self.provider(.perplexity, scope: "api")
    public static let perplexityCookie = Self.provider(.perplexity, scope: "cookie")
    public static let perplexityWeb = Self.provider(.perplexity, scope: "web")
    /// Diagnostic channel for the model-name fallback resolver subsystem
    /// (see `Research/018-model-fallback-pricing.md`). Emits one warning
    /// per *first* observation of an unknown model name; subsequent hits
    /// for the same model are tracked silently in
    /// `UnknownModelDiagnostics` and surfaced in the Debug pane.
    public static let pricing = "pricing"
    public static let poeUsage = Self.provider(.poe, scope: "usage")
    public static let providerDetection = "provider-detection"
    public static let providers = "providers"
    public static let quotaWarningNotifications = "quotaWarningNotifications"
    public static let sessionQuota = "sessionQuota"
    public static let sessionQuotaNotifications = "sessionQuotaNotifications"
    public static let settings = "settings"
    public static let subprocess = "subprocess"
    public static let terminal = "terminal"
    public static let tokenAccounts = "token-accounts"
    public static let tokenCost = "token-cost"
    public static let ttyRunner = "tty-runner"
    public static let webkitTeardown = "webkit-teardown"
}
