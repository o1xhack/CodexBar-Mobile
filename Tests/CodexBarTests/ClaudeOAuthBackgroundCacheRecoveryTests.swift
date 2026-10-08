#if os(macOS)
import Foundation
import Security
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeOAuthBackgroundCacheRecoveryTests {
    enum CacheScenario: CaseIterable {
        case available, writeRejected, writeRejectedWithoutExpiry, temporarilyUnavailable, memoryOlderThanThirtyMinutes
        case expiredFile, expiredMemory, invalidated, neverPrompt, pendingInvalidation, profileChanged
        case writeRejectedOlderThanThirtyMinutes, writeRejectedExpiredMemory, writeRejectedAgain, lostRecoveryGeneration
        case invalidatedByAnotherProcess, revokedForAnotherProfile, rejectedWriteInvalidatedByAnotherProcess

        var rejectsWrite: Bool {
            self == .writeRejected || self == .writeRejectedWithoutExpiry || self == .writeRejectedAgain
                || self == .lostRecoveryGeneration
                || self == .writeRejectedOlderThanThirtyMinutes || self == .writeRejectedExpiredMemory
                || self == .revokedForAnotherProfile
                || self == .rejectedWriteInvalidatedByAnotherProcess
        }

        var expectsRecovery: Bool {
            switch self {
            case .available, .writeRejected, .writeRejectedOlderThanThirtyMinutes, .writeRejectedAgain,
                 .temporarilyUnavailable,
                 .memoryOlderThanThirtyMinutes, .expiredFile: true
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
        let pending = GenerationRaceStore()
        let revocationContext = ClaudeOAuthCredentialsStore
            .$taskDirectKeychainReadConsentRevocationMarkerStoreOverride
        let service = "com.steipete.codexbar.cache.background-tests.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["HOME": root.path, "CLAUDE_CONFIG_DIR": root.path]
        let data = self.credentialsData(expiresIn: scenario == .writeRejectedWithoutExpiry ? nil : 7200)

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
                                                                    try await revocationContext.withValue(.init()) {
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
    }

    private func verifyRecovery(
        scenario: CacheScenario,
        environment: [String: String],
        data: Data,
        memory: ClaudeOAuthCredentialsStore.MemoryCacheStore,
        pending: GenerationRaceStore) async throws
    {
        if scenario == .expiredFile {
            try self.credentialsData(expiresIn: -3600)
                .write(to: ClaudeOAuthCredentialsStore.resolvedCredentialsURLForTesting)
            #expect(ClaudeOAuthCredentialsStore
                .invalidateCacheIfCredentialsFileChanged(environment: environment))
        }
        let loadFailure: OSStatus? = scenario == .available || scenario.rejectsWrite
            || scenario == .invalidatedByAnotherProcess
            ? nil : errSecInteractionNotAllowed
        let interactiveRead: @Sendable () throws -> Data = { data }
        try await KeychainCacheStore.withLoadFailureStatusOverrideForTesting(loadFailure) {
            try await ClaudeOAuthCredentialsStore.withInteractiveClaudeKeychainReadOverridesForTesting(
                read: interactiveRead)
            {
                try KeychainCacheStore.withStoreFailureStatusOverrideForTesting(
                    scenario.rejectsWrite ? errSecInteractionNotAllowed : nil)
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
            if scenario == .writeRejectedOlderThanThirtyMinutes || scenario == .writeRejectedExpiredMemory
                || scenario == .writeRejectedAgain || scenario == .lostRecoveryGeneration
                || scenario == .revokedForAnotherProfile
                || scenario == .rejectedWriteInvalidatedByAnotherProcess
                || (scenario != .available && scenario != .temporarilyUnavailable && !scenario.rejectsWrite)
            {
                memory.timestamp = Date(timeIntervalSinceNow: -1860)
            }
            if scenario == .expiredMemory || scenario == .writeRejectedExpiredMemory {
                memory.record = try ClaudeOAuthCredentialRecord(
                    credentials: ClaudeOAuthCredentials.parse(data: self.credentialsData(expiresIn: -60)),
                    owner: .claudeCLI,
                    source: .memoryCache)
            }
            if scenario == .invalidated {
                ClaudeOAuthCredentialsStore.invalidateCache(environment: environment)
            }
            if scenario == .invalidatedByAnotherProcess || scenario == .revokedForAnotherProfile
                || scenario == .rejectedWriteInvalidatedByAnotherProcess
            {
                KeychainCacheStore.withClearFailureStatusOverrideForTesting(errSecInteractionNotAllowed) {
                    ClaudeOAuthCredentialsStore.$taskMemoryCacheStoreOverride.withValue(.init()) {
                        if scenario == .revokedForAnotherProfile {
                            ClaudeOAuthCredentialsStore.withCredentialsProfileIdentifierOverrideForTesting(
                                "another-synthetic-profile")
                            {
                                ClaudeOAuthCredentialsStore
                                    .revokeDirectKeychainReadConsent(environment: environment)
                            }
                        } else {
                            ClaudeOAuthCredentialsStore.invalidateCache(environment: environment)
                        }
                    }
                }
                #expect(memory.record != nil)
                if scenario == .revokedForAnotherProfile {
                    #expect(ClaudeOAuthCredentialsStore
                        .taskDirectKeychainReadConsentRevocationMarkerStoreOverride?.marker != nil)
                    #expect(pending.isPending(profileIdentifier: "another-synthetic-profile"))
                }
            }
            if scenario == .profileChanged {
                memory.profileIdentifier = "different-synthetic-profile"
            }
            if scenario == .pendingInvalidation {
                try pending.markPending(profileIdentifier: #require(memory.profileIdentifier))
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
                            if scenario == .lostRecoveryGeneration { pending.invalidateAfterOperation = true }
                            if scenario.expectsRecovery {
                                if scenario == .writeRejectedAgain {
                                    let timestamp = memory.timestamp
                                    let first = try KeychainCacheStore.withStoreFailureStatusOverrideForTesting(
                                        errSecInteractionNotAllowed, operation: load)
                                    #expect(first.credentials.accessToken == "synthetic-manual-token")
                                    #expect(memory.timestamp == timestamp)
                                }
                                let automatic = try load()
                                #expect(automatic.credentials.accessToken == "synthetic-manual-token")
                                #expect(automatic.source == .memoryCache)
                                if scenario.rejectsWrite {
                                    let profile = try #require(memory.profileIdentifier)
                                    let key = ClaudeOAuthCredentialsStore
                                        .cacheKeyForTesting(profileIdentifier: profile)
                                    guard case let .found(entry) = KeychainCacheStore.load(
                                        key: key, as: ClaudeOAuthCredentialsStore.CacheEntry.self)
                                    else {
                                        Issue
                                            .record(
                                                "Recovered credentials must be persisted for subsequent refreshes")
                                        return
                                    }
                                    let persisted = try ClaudeOAuthCredentials.parse(data: entry.data)
                                    #expect(persisted.accessToken == automatic.credentials.accessToken)
                                    #expect(persisted.expiresAt == automatic.credentials.expiresAt)
                                    #expect(entry.owner == .claudeCLI)
                                }
                            } else {
                                // Pending invalidation must be cleared before a retained credential can be
                                // reused.
                                #expect(throws: ClaudeOAuthCredentialsError.self, performing: load)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test(ClaudeOAuthDefaultsFixtures())
    func `a rejected cache write during token refresh retains an in-memory recovery`() async throws {
        let memory = ClaudeOAuthCredentialsStore.MemoryCacheStore()
        let pending = ClaudeOAuthCredentialsStore.PendingCacheClearMemoryStore()
        let memoryContext = ClaudeOAuthCredentialsStore.$taskMemoryCacheStoreOverride
        let service = "com.steipete.codexbar.cache.refresh-recovery-tests.\(UUID().uuidString)"
        let profileIdentifier = "synthetic-refresh-recovery-profile"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["HOME": root.path, "CLAUDE_CONFIG_DIR": root.path]

        let registered = URLProtocol.registerClass(ClaudeOAuthRefreshRecoveryStubURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(ClaudeOAuthRefreshRecoveryStubURLProtocol.self)
        }
        try #require(registered)
        try await KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }
            try await KeychainAccessGate.withTaskOverrideForTesting(false) {
                try await ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                    try await ClaudeOAuthKeychainPromptPreference
                        .withTaskOverrideForTesting(.onlyOnUserAction) {
                            try await ClaudeOAuthCredentialsStore
                                .withPendingCacheClearStoreOverrideForTesting(pending) {
                                    try await ClaudeOAuthCredentialsStore
                                        .withIsolatedCredentialsFileTrackingForTesting {
                                            try await ClaudeOAuthCredentialsStore
                                                .withCredentialsURLOverrideForTesting(
                                                    root.appendingPathComponent(".credentials.json"))
                                                {
                                                    try await ClaudeOAuthCredentialsStore
                                                        .withCredentialsProfileIdentifierOverrideAsyncForTesting(
                                                            profileIdentifier)
                                                        {
                                                            try await memoryContext.withValue(memory) {
                                                                try await self
                                                                    .verifyRefreshRecovery(
                                                                        environment: environment,
                                                                        profileIdentifier: profileIdentifier,
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

    private func verifyRefreshRecovery(
        environment: [String: String],
        profileIdentifier: String,
        memory: ClaudeOAuthCredentialsStore.MemoryCacheStore,
        pending: ClaudeOAuthCredentialsStore.PendingCacheClearMemoryStore) async throws
    {
        try await ClaudeOAuthRefreshFailureGate.$shouldAttemptOverride.withValue(true) {
            // The refresh completes even when the persistent cache rejects the write; the armed
            // tombstone must keep a matching in-memory recovery or the next load drops the fresh
            // credential.
            try await KeychainCacheStore.withStoreFailureStatusOverrideForTesting(
                errSecInteractionNotAllowed)
            {
                let refreshed = try await ClaudeOAuthCredentialsStore.refreshAccessToken(
                    refreshToken: "synthetic-refresh-token",
                    existingScopes: ["user:profile"],
                    existingRateLimitTier: nil)
                #expect(refreshed.accessToken == "synthetic-refreshed-token")
                #expect(refreshed.refreshToken == "synthetic-rotated-refresh")
            }
            #expect(memory.record?.credentials.accessToken == "synthetic-refreshed-token")
            let recovery = try #require(memory.rejectedWrite)
            #expect(recovery.entry.profileIdentifier == profileIdentifier)
            #expect(pending.isPending(profileIdentifier: profileIdentifier))

            // Once the memory freshness window lapses, the next load must restore the recovered
            // entry instead of degrading to missing credentials.
            memory.timestamp = Date(timeIntervalSinceNow: -1860)
            try KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting { _, _ in
                Issue.record("Recovery must not probe the foreign Keychain item")
                return .interactionRequired
            } operation: {
                let loaded = try ClaudeOAuthCredentialsStore.loadRecord(
                    environment: environment,
                    allowKeychainPrompt: false,
                    respectKeychainPromptCooldown: true,
                    allowClaudeKeychainRepairWithoutPrompt: false)
                #expect(loaded.credentials.accessToken == "synthetic-refreshed-token")
                #expect(loaded.source == .memoryCache)
                #expect(loaded.owner == .codexbar)

                #expect(!pending.isPending(profileIdentifier: profileIdentifier))
                let key = ClaudeOAuthCredentialsStore.cacheKeyForTesting(profileIdentifier: profileIdentifier)
                guard case let .found(entry) = KeychainCacheStore.load(
                    key: key, as: ClaudeOAuthCredentialsStore.CacheEntry.self)
                else {
                    Issue.record("Recovered credentials must be persisted for subsequent refreshes")
                    return
                }
                let persisted = try ClaudeOAuthCredentials.parse(data: entry.data)
                #expect(persisted.accessToken == loaded.credentials.accessToken)
                let persistedExpiry = try #require(persisted.expiresAt)
                let loadedExpiry = try #require(loaded.credentials.expiresAt)
                #expect(abs(persistedExpiry.timeIntervalSince(loadedExpiry)) < 0.01)
                #expect(entry.owner == .codexbar)
            }
        }
    }

    @Test(ClaudeOAuthDefaultsFixtures())
    func `an older rejected write cannot replace a newer credential's recovery`() async throws {
        // While write A's tombstone commits, a concurrent write installs credential B with recovery B.
        // A's recovery must not overwrite B's; otherwise the next aged load clears B's tombstone
        // without a matching recovery and strands the newer credential.
        let memory = ClaudeOAuthCredentialsStore.MemoryCacheStore()
        let pending = InterposingPendingStore()
        let memoryContext = ClaudeOAuthCredentialsStore.$taskMemoryCacheStoreOverride
        let service = "com.steipete.codexbar.cache.stale-recovery-tests.\(UUID().uuidString)"
        let profileIdentifier = "synthetic-stale-recovery-profile"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["HOME": root.path, "CLAUDE_CONFIG_DIR": root.path]
        let credentialsURL = root.appendingPathComponent(".credentials.json")
        try self.credentialsData(accessToken: "synthetic-older-token").write(to: credentialsURL)

        let newerData = self.credentialsData(accessToken: "synthetic-newer-token")
        let newerCredentials = try ClaudeOAuthCredentials.parse(data: newerData)
        let newerRecovery = ClaudeOAuthCredentialsStore.CacheWriteRecovery(
            entry: .init(
                data: newerData,
                storedAt: Date(),
                owner: .claudeCLI,
                profileIdentifier: profileIdentifier))
        pending.onTombstoneArmed = {
            memory.record = ClaudeOAuthCredentialRecord(
                credentials: newerCredentials,
                owner: .claudeCLI,
                source: .memoryCache)
            memory.timestamp = Date()
            memory.profileIdentifier = profileIdentifier
            memory.rejectedWrite = newerRecovery
        }

        let load = {
            try ClaudeOAuthCredentialsStore.loadRecord(
                environment: environment,
                allowKeychainPrompt: false,
                respectKeychainPromptCooldown: true,
                allowClaudeKeychainRepairWithoutPrompt: false)
        }
        try await KeychainCacheStore.withServiceOverrideForTesting(service) {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }
            try await KeychainAccessGate.withTaskOverrideForTesting(false) {
                try await ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                    try await ClaudeOAuthKeychainPromptPreference
                        .withTaskOverrideForTesting(.onlyOnUserAction) {
                            try await ClaudeOAuthCredentialsStore
                                .withPendingCacheClearStoreOverrideForTesting(pending) {
                                    try await ClaudeOAuthCredentialsStore
                                        .withIsolatedCredentialsFileTrackingForTesting {
                                            try await ClaudeOAuthCredentialsStore
                                                .withCredentialsURLOverrideForTesting(credentialsURL) {
                                                    try await ClaudeOAuthCredentialsStore
                                                        .withCredentialsProfileIdentifierOverrideAsyncForTesting(
                                                            profileIdentifier)
                                                        {
                                                            try memoryContext.withValue(memory) {
                                                                try KeychainCacheStore
                                                                    .withStoreFailureStatusOverrideForTesting(
                                                                        errSecInteractionNotAllowed)
                                                                    {
                                                                        let loaded = try load()
                                                                        #expect(
                                                                            loaded.credentials.accessToken
                                                                                == "synthetic-older-token")
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

        #expect(memory.record?.credentials.accessToken == "synthetic-newer-token")
        #expect(memory.rejectedWrite?.id == newerRecovery.id)
    }

    private final class InterposingPendingStore: ClaudeOAuthPendingCacheClearStore, @unchecked Sendable {
        let base = ClaudeOAuthCredentialsStore.PendingCacheClearMemoryStore()
        var onTombstoneArmed: (() -> Void)?

        var isPending: Bool {
            self.base.isPending
        }

        func isPending(profileIdentifier: String) -> Bool { self.base.isPending(profileIdentifier: profileIdentifier) }
        func markPending(profileIdentifier: String) { self.base.markPending(profileIdentifier: profileIdentifier) }

        @discardableResult
        func withCacheTransaction(
            profileIdentifier: String,
            includingGeneration operation: (inout Bool, inout Bool, inout Bool, inout String?) -> Void) -> Bool
        {
            var armed = false
            let committed = self.base.withCacheTransaction(
                profileIdentifier: profileIdentifier,
                includingGeneration: { profilePending, cleanup, recheck, generation in
                    operation(&profilePending, &cleanup, &recheck, &generation)
                    armed = profilePending && generation != nil
                })
            if committed, armed {
                self.onTombstoneArmed?()
            }
            return committed
        }
    }

    private final class GenerationRaceStore: ClaudeOAuthPendingCacheClearStore, @unchecked Sendable {
        let base = ClaudeOAuthCredentialsStore.PendingCacheClearMemoryStore()
        var invalidateAfterOperation = false

        var isPending: Bool {
            self.base.isPending
        }

        func isPending(profileIdentifier: String) -> Bool { self.base.isPending(profileIdentifier: profileIdentifier) }
        func markPending(profileIdentifier: String) { self.base.markPending(profileIdentifier: profileIdentifier) }

        @discardableResult
        func withCacheTransaction(
            profileIdentifier: String,
            includingGeneration operation: (inout Bool, inout Bool, inout Bool, inout String?) -> Void) -> Bool
        {
            var rejected = false
            let committed = self.base.withCacheTransaction(
                profileIdentifier: profileIdentifier,
                includingGeneration: { pending, cleanup, recheck, generation in
                    operation(&pending, &cleanup, &recheck, &generation)
                    if self.invalidateAfterOperation {
                        self.invalidateAfterOperation = false
                        rejected = true
                        pending = true
                        generation = UUID().uuidString
                    }
                })
            return committed && !rejected
        }
    }

    private func credentialsData(
        accessToken: String = "synthetic-manual-token",
        expiresIn: TimeInterval? = 7200) -> Data
    {
        let expiry = expiresIn.map { Int(Date(timeIntervalSinceNow: $0).timeIntervalSince1970 * 1000) }
        let expiryField = expiry.map { "\"expiresAt\":\($0)," } ?? ""
        return Data("""
        {"claudeAiOauth":{"accessToken":"\(accessToken)",
        \(expiryField)
        "scopes":["user:profile"]}}
        """.utf8)
    }
}

private final class ClaudeOAuthRefreshRecoveryStubURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "platform.claude.com" && request.url?.path == "/v1/oauth/token"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = self.request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let data = Data("""
        {"access_token":"synthetic-refreshed-token","refresh_token":"synthetic-rotated-refresh",
        "expires_in":7200,"token_type":"Bearer"}
        """.utf8)
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: data)
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
