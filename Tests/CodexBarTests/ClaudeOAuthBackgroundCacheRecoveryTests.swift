#if os(macOS)
import Foundation
import Security
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeOAuthBackgroundCacheRecoveryTests {
    enum CacheScenario: CaseIterable {
        case available, writeRejected, temporarilyUnavailable, memoryOlderThanThirtyMinutes
        case expiredFile, expiredMemory, invalidated, neverPrompt, pendingInvalidation, profileChanged

        var expectsRecovery: Bool {
            switch self {
            case .available, .temporarilyUnavailable, .memoryOlderThanThirtyMinutes, .expiredFile: true
            default: false
            }
        }
    }

    @Test(arguments: CacheScenario.allCases)
    func `automatic refresh retains valid manual credentials while honoring invalidation`(
        scenario: CacheScenario) async throws
    {
        let memory = ClaudeOAuthCredentialsStore.MemoryCacheStore()
        let denied = ClaudeOAuthKeychainAccessGate.DeniedUntilStore()
        let pending = ClaudeOAuthCredentialsStore.PendingCacheClearMemoryStore()
        let service = "com.steipete.codexbar.cache.background-tests.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["HOME": root.path, "CLAUDE_CONFIG_DIR": root.path]
        let data = self.credentialsData()

        try await KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }
            try await KeychainAccessGate.withTaskOverrideForTesting(false) {
                try await ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                    try await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                        try await ClaudeOAuthKeychainReadStrategyPreference
                            .withTaskOverrideForTesting(.securityFramework) {
                                try await ClaudeOAuthKeychainAccessGate.withDeniedUntilStoreOverrideForTesting(denied) {
                                    try await ClaudeOAuthCredentialsStore
                                        .withPendingCacheClearStoreOverrideForTesting(pending) {
                                            try await ClaudeOAuthCredentialsStore
                                                .withIsolatedCredentialsFileTrackingForTesting {
                                                    try await ClaudeOAuthCredentialsStore
                                                        .withCredentialsURLOverrideForTesting(
                                                            root.appendingPathComponent(".credentials.json"))
                                                        {
                                                            try await ClaudeOAuthCredentialsStore
                                                                .$taskMemoryCacheStoreOverride
                                                                .withValue(memory) {
                                                                    try await self.verifyRecovery(
                                                                        scenario: scenario,
                                                                        environment: environment,
                                                                        data: data,
                                                                        memory: memory,
                                                                        pending: pending)
                                                                }
                                                        }
                                                }
                                        }
                                }
                            }
                    }
                }
            }
        }
    }

    private func verifyRecovery(
        scenario: CacheScenario,
        environment: [String: String],
        data: Data,
        memory: ClaudeOAuthCredentialsStore.MemoryCacheStore,
        pending: ClaudeOAuthCredentialsStore.PendingCacheClearMemoryStore) async throws
    {
        if scenario == .expiredFile {
            try self.credentialsData(expiresIn: -3600)
                .write(to: ClaudeOAuthCredentialsStore.resolvedCredentialsURLForTesting)
            #expect(ClaudeOAuthCredentialsStore.invalidateCacheIfCredentialsFileChanged(environment: environment))
        }
        let loadFailure: OSStatus? = scenario == .available || scenario == .writeRejected
            ? nil : errSecInteractionNotAllowed
        let interactiveRead: @Sendable () throws -> Data = { data }
        try await KeychainCacheStore.withLoadFailureStatusOverrideForTesting(loadFailure) {
            try await ClaudeOAuthCredentialsStore.withInteractiveClaudeKeychainReadOverridesForTesting(
                read: interactiveRead)
            {
                try KeychainCacheStore.withStoreFailureStatusOverrideForTesting(
                    scenario == .writeRejected ? errSecInteractionNotAllowed : nil)
                {
                    let manual = try ProviderInteractionContext.$current.withValue(.userInitiated) {
                        try ClaudeOAuthCredentialsStore.loadRecord(
                            environment: environment,
                            allowKeychainPrompt: true,
                            respectKeychainPromptCooldown: false,
                            allowClaudeKeychainRepairWithoutPrompt: false)
                    }
                    #expect(manual.credentials.accessToken == "synthetic-manual-token")
                    #expect(manual.source == .claudeKeychain)
                    #expect(memory.record?.credentials.accessToken == "synthetic-manual-token")
                }
            }
            if scenario != .available, scenario != .temporarilyUnavailable, scenario != .writeRejected {
                memory.timestamp = Date(timeIntervalSinceNow: -1860)
            }
            if scenario == .expiredMemory {
                memory.record = try ClaudeOAuthCredentialRecord(
                    credentials: ClaudeOAuthCredentials.parse(data: self.credentialsData(expiresIn: -60)),
                    owner: .claudeCLI,
                    source: .memoryCache)
            }
            if scenario == .invalidated {
                ClaudeOAuthCredentialsStore.invalidateCache(environment: environment)
            }
            if scenario == .profileChanged {
                memory.profileIdentifier = "different-synthetic-profile"
            }
            if scenario == .pendingInvalidation {
                pending.markPending()
            }
            try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                Issue.record("Recovery must not probe the foreign Keychain item")
                return .interactionRequired
            } operation: {
                try KeychainCacheStore.withClearFailureStatusOverrideForTesting(
                    scenario == .pendingInvalidation ? errSecInteractionNotAllowed : nil)
                {
                    try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                        scenario == .neverPrompt ? .never : .onlyOnUserAction)
                    {
                        try ProviderInteractionContext.$current.withValue(.background) {
                            let load = {
                                try ClaudeOAuthCredentialsStore.loadRecord(
                                    environment: environment,
                                    allowKeychainPrompt: false,
                                    respectKeychainPromptCooldown: true,
                                    allowClaudeKeychainRepairWithoutPrompt: false)
                            }
                            if scenario.expectsRecovery {
                                let automatic = try load()
                                #expect(automatic.credentials.accessToken == "synthetic-manual-token")
                                #expect(automatic.source == .memoryCache)
                            } else {
                                // A retained credential must not bypass pending invalidation after a rejected write.
                                #expect(throws: ClaudeOAuthCredentialsError.self, performing: load)
                            }
                        }
                    }
                }
            }
        }
    }

    private func credentialsData(expiresIn: TimeInterval = 7200) -> Data {
        Data("""
        {"claudeAiOauth":{"accessToken":"synthetic-manual-token",
        "expiresAt":\(Int(Date(timeIntervalSinceNow: expiresIn).timeIntervalSince1970 * 1000)),
        "scopes":["user:profile"]}}
        """.utf8)
    }
}
#endif
