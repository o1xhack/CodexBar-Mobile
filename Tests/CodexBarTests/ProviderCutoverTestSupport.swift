import Foundation
@testable import CodexBarCore

enum ProviderCutoverTestSupport {
    static func context(
        environment: [String: String] = [:],
        settings: ProviderSettingsSnapshot? = nil,
        runtime: ProviderRuntime = .app,
        includeCredits: Bool = false,
        includeOptionalUsage: Bool = true) -> ProviderFetchContext
    {
        ProviderFetchContext(
            runtime: runtime,
            sourceMode: .auto,
            includeCredits: includeCredits,
            includeOptionalUsage: includeOptionalUsage,
            webTimeout: 15,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: settings,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: UnusedClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    private struct UnusedClaudeFetcher: ClaudeUsageFetching {
        func detectVersion() -> String? { nil }
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ProviderPluginError.script("unused")
        }

        func debugRawProbe(model _: String) async -> String { "unused" }
    }
}
