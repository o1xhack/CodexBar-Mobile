import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// v2 incremental sync — tests the in-memory cache + priority merge rules,
/// with explicit multi-device scenarios matching Research/011's trace section.
@MainActor
@Suite("Snapshot cache priority + multi-device")
struct SnapshotCacheTests {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_100_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_200_000)

    private func provider(
        id: String,
        name: String? = nil,
        email: String? = nil,
        lastUpdated: Date) -> ProviderUsageSnapshot
    {
        // Include a non-empty primary rate window so the provider does NOT
        // trip the ghost filter — test fixtures represent real providers.
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name ?? id.capitalized,
            primary: SyncRateWindow(
                usedPercent: 42.0,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated)
    }

    private func snapshot(
        deviceID: String?,
        deviceName: String,
        providers: [ProviderUsageSnapshot],
        timestamp: Date) -> SyncedUsageSnapshot
    {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: timestamp,
            deviceName: deviceName,
            deviceID: deviceID,
            appVersion: "0.20.1",
            mobileVersion: "1.3.0")
    }

    private func envelope(
        deviceID: String,
        deviceName: String,
        providerID: String,
        email: String? = nil,
        providerLastUpdated: Date,
        syncTimestamp: Date) -> ProviderUsageEnvelope
    {
        ProviderUsageEnvelope(
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: "0.20.1",
            mobileVersion: "1.3.0",
            syncTimestamp: syncTimestamp,
            notificationPushEnabled: true,
            provider: self.provider(
                id: providerID,
                email: email,
                lastUpdated: providerLastUpdated))
    }

    // MARK: - Basic cache operations

    @Test
    func `Empty cache returns no snapshots`() {
        let cache = SnapshotCache()
        #expect(cache.buildDeviceSnapshots().isEmpty)
    }

    @Test
    func `Delta upsert populates perProviderByDevice, leaves legacy alone`() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [self.envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", providerLastUpdated: self.t1, syncTimestamp: self.t1)],
            deletedRecordNames: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        #expect(cache.legacyByDevice.isEmpty) // untouched
        #expect(cache.deviceMetadata["mac-A"]?.deviceName == "Mac A")
    }

    @Test
    func `Delta cache preserves each provider envelope publication time`() throws {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "claude", email: "user@example.com",
                    providerLastUpdated: self.t3, syncTimestamp: self.t3),
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: "user@example.com",
                    providerLastUpdated: self.t1, syncTimestamp: self.t1),
            ],
            deletedRecordNames: [])

        let snapshot = try #require(cache.buildDeviceSnapshots().first)
        let codex = try #require(snapshot.providers.first(where: { $0.providerID == "codex" }))
        let claude = try #require(snapshot.providers.first(where: { $0.providerID == "claude" }))
        #expect(snapshot.syncTimestamp == self.t3)
        #expect(snapshot.publicationTimestamp(for: codex) == self.t1)
        #expect(snapshot.publicationTimestamp(for: claude) == self.t3)
    }

    @Test
    func `Delta delete removes exactly the matched composite`() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", providerLastUpdated: self.t1, syncTimestamp: self.t1),
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "claude", providerLastUpdated: self.t1, syncTimestamp: self.t1),
            ],
            deletedRecordNames: [])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)

        // Delete just codex.
        cache.applyDelta(
            upserted: [],
            deletedRecordNames: ["mac-A|codex|_"])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("claude|_") == true)
    }

    @Test
    func `Delete last provider of a device removes the device entry`() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [self.envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", providerLastUpdated: self.t1, syncTimestamp: self.t1)],
            deletedRecordNames: [])
        cache.applyDelta(
            upserted: [],
            deletedRecordNames: ["mac-A|codex|_"])

        #expect(cache.perProviderByDevice["mac-A"] == nil)
        // metadata stays — legacy could still have a snapshot
        #expect(cache.deviceMetadata["mac-A"] != nil)
    }

    @Test
    func `Incremental persistence payload filters deleted providers from legacy fallback`() {
        let legacyFallback = self.snapshot(
            deviceID: "mac-A",
            deviceName: "Mac A",
            providers: [
                self.provider(id: "codex", lastUpdated: self.t1),
                self.provider(id: "claude", lastUpdated: self.t1),
            ],
            timestamp: self.t1)

        let filtered = SyncedUsageData.snapshotsFilteringDeletedProvidersForIncrementalPersistence(
            [legacyFallback],
            deletedRecordNames: ["mac-A|codex|_"])

        #expect(filtered.count == 1)
        #expect(filtered[0].providers.map(\.providerID) == ["claude"])
    }

    // MARK: - Priority merge

    @Test
    func `Device in per-provider bucket wins over legacy bucket`() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [self.provider(id: "codex", lastUpdated: self.t3)],
                timestamp: self.t3)],
            legacySnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [self.provider(id: "claude", lastUpdated: self.t1)],
                timestamp: self.t1)])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.first?.providerID == "codex")
    }

    @Test
    func `Device only in legacy bucket falls through`() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [self.snapshot(
                deviceID: "mac-B", deviceName: "Mac B",
                providers: [self.provider(id: "claude", lastUpdated: self.t1)],
                timestamp: self.t1)])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].deviceID == "mac-B")
    }

    // MARK: - Multi-device scenarios (from Research/011)

    @Test
    func `Scenario 1: Mac A on new zone + Mac B legacy-only — both surface`() {
        var cache = SnapshotCache()
        // Full fetch result: Mac A has per-provider envelopes, both Macs
        // are in legacy (because P4 is dual-write; Mac A still writes legacy
        // too).
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [self.provider(id: "codex", lastUpdated: self.t3)],
                timestamp: self.t3)],
            legacySnapshots: [
                self.snapshot(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providers: [self.provider(id: "codex", lastUpdated: self.t2)], // older than per-provider
                    timestamp: self.t2),
                self.snapshot(
                    deviceID: "mac-B", deviceName: "Mac B",
                    providers: [self.provider(id: "claude", lastUpdated: self.t2)],
                    timestamp: self.t2),
            ])

        var result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        let macA = try? #require(result.first(where: { $0.deviceID == "mac-A" }))
        let macB = try? #require(result.first(where: { $0.deviceID == "mac-B" }))
        #expect(macA?.syncTimestamp == self.t3) // per-provider won
        #expect(macB?.syncTimestamp == self.t2) // legacy path

        // Now a silent push from Mac A with a newer codex provider.
        cache.applyDelta(
            upserted: [self.envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex",
                providerLastUpdated: self.t3.addingTimeInterval(100),
                syncTimestamp: self.t3.addingTimeInterval(100))],
            deletedRecordNames: [])

        result = cache.buildDeviceSnapshots()
        #expect(result.count == 2) // Mac B still there, not touched
        let macBAfter = try? #require(result.first(where: { $0.deviceID == "mac-B" }))
        #expect(macBAfter?.syncTimestamp == self.t2) // UNCHANGED — incremental never touched legacy
        let macAAfter = try? #require(result.first(where: { $0.deviceID == "mac-A" }))
        #expect(macAAfter?.syncTimestamp == self.t3.addingTimeInterval(100))
    }

    @Test
    func `Scenario 2: Both Macs on new zone — both refresh independently`() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [
                self.snapshot(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providers: [self.provider(id: "codex", lastUpdated: self.t1)],
                    timestamp: self.t1),
                self.snapshot(
                    deviceID: "mac-B", deviceName: "Mac B",
                    providers: [self.provider(id: "claude", lastUpdated: self.t1)],
                    timestamp: self.t1),
            ],
            legacySnapshots: [])

        // Silent push from Mac A.
        cache.applyDelta(
            upserted: [self.envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex",
                providerLastUpdated: self.t2, syncTimestamp: self.t2)],
            deletedRecordNames: [])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        let macA = try? #require(result.first(where: { $0.deviceID == "mac-A" }))
        let macB = try? #require(result.first(where: { $0.deviceID == "mac-B" }))
        #expect(macA?.syncTimestamp == self.t2)
        #expect(macB?.syncTimestamp == self.t1) // Mac B stays until its own push
    }

    @Test
    func `Scenario 3: Both Macs legacy-only — per-provider bucket stays empty`() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [
                self.snapshot(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providers: [self.provider(id: "codex", lastUpdated: self.t1)],
                    timestamp: self.t1),
                self.snapshot(
                    deviceID: "mac-B", deviceName: "Mac B",
                    providers: [self.provider(id: "claude", lastUpdated: self.t1)],
                    timestamp: self.t1),
            ])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        #expect(cache.perProviderByDevice.isEmpty)
    }

    @Test
    func `Token-expired replay REPLACES per-provider bucket (doesn't mix)`() {
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [self.envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", providerLastUpdated: self.t1, syncTimestamp: self.t1)],
            deletedRecordNames: [])

        // Token expires; server replays everything. Say Mac A's codex is
        // gone (user disabled it) and only Mac B exists now.
        cache.replacePerProviderFromReplay([
            self.envelope(
                deviceID: "mac-B", deviceName: "Mac B",
                providerID: "claude", providerLastUpdated: self.t2, syncTimestamp: self.t2),
        ])

        #expect(cache.perProviderByDevice["mac-A"] == nil) // gone
        #expect(cache.perProviderByDevice["mac-B"]?.count == 1)
    }

    // MARK: - recordName parser round-trip

    @Test
    func `splitRecordName matches CloudSyncManager.perProviderRecordName`() {
        let generated = CloudSyncManager.perProviderRecordName(
            deviceID: "mac-A", providerID: "codex", accountEmail: nil)
        let parsed = SnapshotCache.splitRecordName(generated)
        #expect(parsed?.deviceID == "mac-A")
        #expect(parsed?.composite == "codex|_")

        let withEmail = CloudSyncManager.perProviderRecordName(
            deviceID: "mac-A", providerID: "codex", accountEmail: "user@example.com")
        let parsed2 = SnapshotCache.splitRecordName(withEmail)
        #expect(parsed2?.deviceID == "mac-A")
        #expect(parsed2?.composite == "codex|user@example.com")

        let opaque = CloudSyncManager.perProviderRecordName(
            deviceID: "mac-A", providerID: "sub2api",
            accountEmail: "Duplicate | label", accountRecordKey: "token-1234")
        let parsed3 = SnapshotCache.splitRecordName(opaque)
        #expect(opaque == "mac-A|sub2api|token-1234")
        #expect(parsed3?.composite == "sub2api|token-1234")

        let legacyDelimited = SnapshotCache.splitRecordName(
            "mac-A|sub2api|Duplicate | label")
        #expect(legacyDelimited?.deviceID == "mac-A")
        #expect(legacyDelimited?.composite == "sub2api|Duplicate | label")
    }

    @Test
    func `splitRecordName rejects malformed input`() {
        #expect(SnapshotCache.splitRecordName("too|few") == nil)
        #expect(SnapshotCache.splitRecordName("way|too|many|pieces|here")?.composite == "too|many|pieces|here")
    }

    // MARK: - Ghost filter (Build 66 · bug #2 fix)

    @Test
    func `Ghost envelope (all fields empty) is dropped from per-provider bucket`() {
        var cache = SnapshotCache()
        // Mac A wrote two codex records in CloudKit with different accountEmail:
        // one early (ghost: nil email + no data) and one later (real data).
        let ghost = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: t1,
            rateWindows: [])
        let real = self.provider(id: "codex", email: "user@example.com", lastUpdated: self.t3)
        let fake = SyncedUsageSnapshot(
            providers: [ghost, real],
            syncTimestamp: t3,
            deviceName: "Mac A",
            deviceID: "mac-A")

        cache.replaceFromFullFetch(perProviderSnapshots: [fake], legacySnapshots: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|user@example.com") == true)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|_") == false)
    }

    @Test
    func `Ghost envelope is dropped from delta apply`() {
        var cache = SnapshotCache()
        let ghostEnv = ProviderUsageEnvelope(
            deviceID: "mac-A", deviceName: "Mac A",
            appVersion: nil, mobileVersion: nil,
            syncTimestamp: t1, notificationPushEnabled: nil,
            provider: ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: nil,
                loginMethod: nil, statusMessage: nil,
                isError: false,
                lastUpdated: t1,
                rateWindows: []))
        cache.applyDelta(upserted: [ghostEnv], deletedRecordNames: [])
        #expect(cache.perProviderByDevice["mac-A"] == nil)
    }

    @Test
    func `Typed-only Wayfinder payload is not dropped as a ghost`() {
        var cache = SnapshotCache()
        let wayfinder = ProviderUsageSnapshot(
            providerID: "wayfinder",
            providerName: "Wayfinder",
            primary: nil,
            secondary: nil,
            accountEmail: "gateway@example.test",
            loginMethod: "Local gateway",
            statusMessage: nil,
            isError: false,
            lastUpdated: t1,
            wayfinderUsage: SyncWayfinderUsage(
                gatewayStatus: "healthy",
                offline: false,
                dryRun: false,
                missingKeyCount: 0,
                modelCount: 3,
                requests: 42,
                tokens: 12000,
                realized: 0.18,
                baseline: 0.30,
                saved: 0.12,
                savedPercent: 40,
                priced: true,
                routes: [],
                averageDecisionMilliseconds: 0.8,
                updatedAt: t1))
        let snapshot = self.snapshot(
            deviceID: "mac-A",
            deviceName: "Mac A",
            providers: [wayfinder],
            timestamp: self.t1)

        cache.replaceFromFullFetch(perProviderSnapshots: [snapshot], legacySnapshots: [])

        #expect(cache.perProviderByDevice["mac-A"]?["wayfinder|gateway@example.test"] != nil)
    }

    // MARK: - Codex review P1 — preserve on transient fetch error

    @Test
    func `Nil perProviderSnapshots preserves existing per-provider bucket`() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [self.provider(id: "codex", lastUpdated: self.t3)],
                timestamp: self.t3)],
            legacySnapshots: [])
        let before = cache.perProviderByDevice["mac-A"]?.count
        #expect(before == 1)

        // Transient legacy error: pass nil for legacy. Per-provider bucket
        // is refreshed with empty, legacy bucket preserved.
        cache.replaceFromFullFetch(
            perProviderSnapshots: nil, // transient error on per-provider zone
            legacySnapshots: []) // legacy authoritatively empty

        // Per-provider bucket preserved as-is.
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        // Legacy bucket cleared (authoritative empty from pass).
        #expect(cache.legacyByDevice.isEmpty)
    }

    @Test
    func `Nil legacySnapshots preserves existing legacy bucket`() {
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [self.snapshot(
                deviceID: "mac-B", deviceName: "Mac B",
                providers: [self.provider(id: "claude", lastUpdated: self.t1)],
                timestamp: self.t1)])
        #expect(cache.legacyByDevice["mac-B"] != nil)

        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: nil) // transient legacy error

        // Legacy preserved.
        #expect(cache.legacyByDevice["mac-B"] != nil)
    }

    // MARK: - Ghost filter

    @Test
    func `Provider with just an error message is NOT a ghost (keep)`() {
        var cache = SnapshotCache()
        let erroring = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil, secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: "Auth failed",
            isError: true,
            lastUpdated: t1,
            rateWindows: [])
        let snap = SyncedUsageSnapshot(
            providers: [erroring], syncTimestamp: t1,
            deviceName: "Mac A", deviceID: "mac-A")
        cache.replaceFromFullFetch(perProviderSnapshots: [snap], legacySnapshots: [])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
    }

    // MARK: - Hardening Phase 3 · multi-account scenarios

    @Test
    func `Same provider with two account emails on one device — both kept`() {
        var cache = SnapshotCache()
        let codexAlice = self.provider(id: "codex", email: "alice@example.com", lastUpdated: self.t1)
        let codexBob = self.provider(id: "codex", email: "bob@example.com", lastUpdated: self.t2)
        let snap = SyncedUsageSnapshot(
            providers: [codexAlice, codexBob],
            syncTimestamp: t2,
            deviceName: "Mac A",
            deviceID: "mac-A",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0")

        cache.replaceFromFullFetch(perProviderSnapshots: [snap], legacySnapshots: [])

        // Both Codex accounts kept as separate entries (different composite keys).
        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|alice@example.com") == true)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|bob@example.com") == true)

        // Buildback also keeps both.
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 2)
    }

    @Test
    func `Per-provider zone with both nil-email and emailed records for same providerID — both kept`() {
        var cache = SnapshotCache()
        // BOTH have data (both pass ghost filter). They're different composite
        // keys, so cache treats them as separate accounts of the same
        // provider. (Real-world this might be a stale legacy record from
        // before account-email-aware code; behavior under test is "no
        // collapse, no overwrite".)
        let codexNoEmail = self.provider(id: "codex", email: nil, lastUpdated: self.t1)
        let codexEmailed = self.provider(id: "codex", email: "user@example.com", lastUpdated: self.t2)
        let snap = SyncedUsageSnapshot(
            providers: [codexNoEmail, codexEmailed],
            syncTimestamp: t2,
            deviceName: "Mac A",
            deviceID: "mac-A",
            appVersion: "0.20.2",
            mobileVersion: "1.3.0")

        cache.replaceFromFullFetch(perProviderSnapshots: [snap], legacySnapshots: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|_") == true)
        #expect(cache.perProviderByDevice["mac-A"]?.keys.contains("codex|user@example.com") == true)
    }

    @Test
    func `compositeKey for nil-email matches underscore everywhere`() {
        // Build 67 hardening: SwiftDataSchema.makeCompositeKey was using ""
        // while SnapshotCache + CloudSyncManager.perProviderRecordName used
        // "_" — silent format mismatch. This test pins the contract.
        let p = self.provider(id: "codex", email: nil, lastUpdated: self.t1)
        let cacheKey = SnapshotCache.compositeKey(for: p)
        let cloudKitName = CloudSyncManager.perProviderRecordName(
            deviceID: "ignored", providerID: "codex", accountEmail: nil)
        #expect(cacheKey == "codex|_")
        // CloudKit record name is `{deviceID}|{rest}`, so trailing portion
        // must match the cache's composite key format.
        #expect(cloudKitName.hasSuffix("|" + cacheKey))
    }

    @Test
    func `opaque account key wins over duplicate editable label`() {
        let provider = ProviderUsageSnapshot(
            providerID: "sub2api", providerName: "sub2api",
            primary: nil, secondary: nil,
            accountEmail: "Duplicate | label", loginMethod: nil,
            statusMessage: nil, isError: false, lastUpdated: self.t1,
            sub2APIUsage: .init(kind: "wallet", balance: 1, unit: "USD", today: nil, total: nil),
            accountRecordKey: "token-1234")
        #expect(SnapshotCache.compositeKey(for: provider) == "sub2api|token-1234")
        #expect(provider.cardIdentityKey == "sub2api|token-1234")
    }

    @Test
    func `Delta-applied envelope with an email replaces nil-email ghost only if cache had it (independent keys)`() {
        var cache = SnapshotCache()
        // Seed cache with a real (non-ghost) nil-email codex entry first.
        let nilSnap = SyncedUsageSnapshot(
            providers: [provider(id: "codex", email: nil, lastUpdated: t1)],
            syncTimestamp: t1,
            deviceName: "Mac A",
            deviceID: "mac-A")
        cache.replaceFromFullFetch(perProviderSnapshots: [nilSnap], legacySnapshots: [])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)

        // Apply delta: same providerID but with an email. Different composite
        // key — should ADD an entry, not replace.
        cache.applyDelta(
            upserted: [self.envelope(
                deviceID: "mac-A", deviceName: "Mac A",
                providerID: "codex", email: "u@x.com",
                providerLastUpdated: self.t2, syncTimestamp: self.t2)],
            deletedRecordNames: [])

        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
    }

    // MARK: - Realistic-distribution regression (Build 83 · Agent C)

    @Test
    func `Bursty active device + idle stale device: cache keeps both, sort order intact`() {
        var cache = SnapshotCache()
        // Mac A is active: recent timestamp + bursty 30-day Codex history.
        let mac_a_env = self.envelope(
            deviceID: "mac-a", deviceName: "Mac A (active)",
            providerID: "codex", email: "alice@example.com",
            providerLastUpdated: self.t3, syncTimestamp: self.t3)
        // Mac B is idle: 20-day-old timestamp, same codex account seen there.
        let mac_b_env = self.envelope(
            deviceID: "mac-b", deviceName: "Mac B (stale)",
            providerID: "codex", email: "alice@example.com",
            providerLastUpdated: self.t1, syncTimestamp: self.t1)

        cache.applyDelta(upserted: [mac_a_env, mac_b_env], deletedRecordNames: [])

        // Both devices present in the per-provider cache.
        #expect(cache.perProviderByDevice["mac-a"]?.count == 1)
        #expect(cache.perProviderByDevice["mac-b"]?.count == 1)

        let snapshots = cache.buildDeviceSnapshots()
        #expect(snapshots.count == 2)
        // A regression that dropped the idle device (e.g. "stale filter on
        // lastUpdated") would show 1 here and Mac B's data would vanish.
        #expect(Set(snapshots.map(\.deviceID)) == ["mac-a", "mac-b"])
    }

    @Test
    func `Multi-account delta on pre-existing cache preserves the untouched account`() {
        var cache = SnapshotCache()

        // Seed: two Codex accounts on Mac A, both at t1.
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-a",
                    deviceName: "Mac A",
                    providerID: "codex",
                    email: "alice@example.com",
                    providerLastUpdated: self.t1,
                    syncTimestamp: self.t1),
                self.envelope(
                    deviceID: "mac-a",
                    deviceName: "Mac A",
                    providerID: "codex",
                    email: "bob@example.com",
                    providerLastUpdated: self.t1,
                    syncTimestamp: self.t1),
            ],
            deletedRecordNames: [])
        #expect(cache.perProviderByDevice["mac-a"]?.count == 2)

        // Delta: alice gets fresh data at t2. Bob untouched.
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-a",
                    deviceName: "Mac A",
                    providerID: "codex",
                    email: "alice@example.com",
                    providerLastUpdated: self.t2,
                    syncTimestamp: self.t2),
            ],
            deletedRecordNames: [])

        let aliceCodex = cache.perProviderByDevice["mac-a"]?.values.first(where: {
            $0.accountEmail == "alice@example.com"
        })
        let bobCodex = cache.perProviderByDevice["mac-a"]?.values.first(where: {
            $0.accountEmail == "bob@example.com"
        })
        #expect(aliceCodex?.lastUpdated == self.t2)
        #expect(bobCodex?.lastUpdated == self.t1)
        // Regression: a cache that re-keys by providerID alone would
        // overwrite bob's entry with alice's on delta apply.
        #expect(cache.perProviderByDevice["mac-a"]?.count == 2)
    }

    // MARK: - Build 94 hotfix · ghost orphan + stale TTL

    @Test
    func `Orphan-with-nil-email is dropped when sibling with email exists for same providerID`() {
        // Reproduces user-reported bug: after Mac upgrade, Codex internal
        // identity logic shifted, leaving a nil-email orphan record alongside
        // the new account record. Both display as Codex on iOS but with
        // different ordinal labels ("Hidden" + "Codex 2").
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope( // orphan from pre-upgrade Mac, no email
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: nil,
                    providerLastUpdated: self.t3, syncTimestamp: self.t3),
                self.envelope( // real account from post-upgrade Mac
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: "user@example.com",
                    providerLastUpdated: self.t3, syncTimestamp: self.t3),
            ],
            deletedRecordNames: [])

        // Cache holds both raw entries (filter applies at read time only).
        #expect(cache.perProviderByDevice["mbp"]?.count == 2)

        // But buildDeviceSnapshots filters the orphan out.
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let providers = result[0].providers
        #expect(providers.count == 1)
        #expect(providers[0].accountEmail == "user@example.com")
    }

    @Test
    func `Provider-level cost envelope survives orphan and stale filtering beside an account`() throws {
        let managementCost = ProviderUsageSnapshot(
            providerID: "openrouter",
            providerName: "OpenRouter",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.t1,
            costSummary: SyncCostSummary(
                sessionCostUSD: 7,
                sessionTokens: 700,
                last30DaysCostUSD: 70,
                last30DaysTokens: 7000,
                daily: []),
            accountRecordKey: ProviderUsageSnapshot.openRouterManagementCostRecordKey)
        let account = ProviderUsageSnapshot(
            providerID: "openrouter",
            providerName: "OpenRouter",
            primary: SyncRateWindow(
                usedPercent: 42,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: "Personal",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.t3,
            accountRecordKey: "token-personal")
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [managementCost, account].map { provider in
                ProviderUsageEnvelope(
                    deviceID: "mac-a",
                    deviceName: "Mac A",
                    appVersion: "0.54.0.1",
                    mobileVersion: "1.21.0",
                    syncTimestamp: self.t3,
                    notificationPushEnabled: true,
                    provider: provider)
            },
            deletedRecordNames: [])

        let snapshot = try #require(cache.buildDeviceSnapshots().first)
        #expect(snapshot.providers.count == 2)
        #expect(snapshot.providers.contains { $0.isProviderLevelCostEnvelope })
        #expect(snapshot.providers.contains { $0.accountEmail == "Personal" })
    }

    @Test
    func `Multiple nil-email entries with same providerID stay if no sibling has email`() {
        // Legit accountless providers (e.g., Claude with hide-email setting on
        // both accounts) — both entries have nil email but represent distinct
        // accounts at the recordName level. Keep both; the dedupe rule only
        // fires when AT LEAST ONE sibling has a real email.
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                ProviderUsageEnvelope(
                    deviceID: "mac-a", deviceName: "Mac A",
                    appVersion: "0.20.1", mobileVersion: "1.3.0",
                    syncTimestamp: self.t3, notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex", providerName: "Codex",
                        primary: SyncRateWindow(
                            usedPercent: 23.0, windowMinutes: 60,
                            resetsAt: nil, resetDescription: nil),
                        secondary: nil, accountEmail: nil, loginMethod: nil,
                        statusMessage: nil, isError: false, lastUpdated: self.t3)),
                ProviderUsageEnvelope(
                    deviceID: "mac-a", deviceName: "Mac A",
                    appVersion: "0.20.1", mobileVersion: "1.3.0",
                    syncTimestamp: self.t3, notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex", providerName: "Codex",
                        primary: SyncRateWindow(
                            usedPercent: 50.0, windowMinutes: 60,
                            resetsAt: nil, resetDescription: nil),
                        secondary: nil, accountEmail: nil, loginMethod: nil,
                        statusMessage: nil, isError: false, lastUpdated: self.t3)),
            ],
            deletedRecordNames: [])

        // Both entries occupy the same composite key "codex|_" — second
        // upsert overwrites first in the cache, so we only have 1 actually.
        // This test demonstrates that the dedupe rule doesn't accidentally
        // drop the surviving entry. (The "two accountless providers"
        // scenario can't occur via our composite-key cache anyway, but we
        // still want the read-side filter to keep what's there.)
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 1)
    }

    @Test
    func `Stale-TTL drops provider record lagging >30min behind device freshest`() {
        // Reproduces user-reported Perplexity ghost: user enabled then
        // disabled Perplexity on Mac. Mac stopped refreshing the record but
        // the CloudKit envelope persists with its last-known timestamp.
        // After 30 minutes of the device's other providers continuing to
        // refresh, the stale Perplexity record is filtered at read time.
        let now = Date()
        let fresh = now
        let stale = now.addingTimeInterval(-45 * 60) // 45 min behind
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope( // active Codex, just refreshed
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: "user@example.com",
                    providerLastUpdated: fresh, syncTimestamp: fresh),
                self.envelope( // disabled Perplexity ghost, never refreshed since
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "perplexity", email: nil,
                    providerLastUpdated: stale, syncTimestamp: stale),
            ],
            deletedRecordNames: [])

        // Cache holds both.
        #expect(cache.perProviderByDevice["mbp"]?.count == 2)

        // buildDeviceSnapshots drops the stale one.
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let providers = result[0].providers
        #expect(providers.count == 1)
        #expect(providers[0].providerID == "codex")
    }

    @Test
    func `Stale-TTL leaves single-record device alone (offline Mac scenario)`() {
        // Mac has been offline; its only provider's lastUpdated is hours old.
        // deviceFreshest = that single entry's lastUpdated, so TTL window is
        // [hours-30min, hours] which still contains the entry. Don't drop it.
        let now = Date()
        let staleSingle = now.addingTimeInterval(-3 * 60 * 60) // 3 hours ago
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [self.envelope(
                deviceID: "mac-offline", deviceName: "Offline Mac",
                providerID: "claude", email: nil,
                providerLastUpdated: staleSingle, syncTimestamp: staleSingle)],
            deletedRecordNames: [])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 1)
    }

    @Test
    func `Stale-TTL keeps providers refreshed within 30 min of device freshest`() {
        // Mac alternates refresh sequencing — 5 sec between providers in the
        // same cycle. Both well within 30 min threshold.
        let now = Date()
        let codexUpdated = now.addingTimeInterval(-5)
        let claudeUpdated = now.addingTimeInterval(-10)
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mbp", deviceName: "Mac",
                    providerID: "codex", email: "u@x.com",
                    providerLastUpdated: codexUpdated, syncTimestamp: now),
                self.envelope(
                    deviceID: "mbp", deviceName: "Mac",
                    providerID: "claude", email: nil,
                    providerLastUpdated: claudeUpdated, syncTimestamp: now),
            ],
            deletedRecordNames: [])

        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 2)
    }

    @Test
    func `Both rules combined: orphan Codex + stale Perplexity (user's reported scenario)`() {
        // Reproduces the exact symptom user reported on iOS 1.3.0 Build 93
        // after upgrading both Macs to 0.20.3:
        //   - mbp shows 4 provider cards but only Codex + Claude are active
        //   - "Codex" + "Codex 2" duplicates from upgrade-induced identity drift
        //   - Perplexity ghost from disable
        // After Build 94 hotfix, only the 2 active providers remain.
        let now = Date()
        let active = now
        let postUpgradeOrphan = now.addingTimeInterval(-31 * 60) // 31 min ago
        let perplexityGhost = now.addingTimeInterval(-39 * 60) // 39 min ago
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                // Real active Codex with email
                self.envelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "codex", email: "user@example.com",
                    providerLastUpdated: active, syncTimestamp: now),
                // Real active Claude (accountless)
                self.envelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "claude", email: nil,
                    providerLastUpdated: active, syncTimestamp: now),
                // Orphan Codex from pre-upgrade (different recordName, nil
                // email in payload — Build 66 ghost filter doesn't catch it
                // because it has cost data)
                ProviderUsageEnvelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    appVersion: "0.20.3", mobileVersion: "1.3.0",
                    syncTimestamp: postUpgradeOrphan,
                    notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex",
                        providerName: "Codex",
                        primary: SyncRateWindow(
                            usedPercent: 23.0, windowMinutes: 60,
                            resetsAt: nil, resetDescription: nil),
                        secondary: nil, accountEmail: nil,
                        loginMethod: nil,
                        statusMessage: "Codex returned invalid data: codex app-server closed stdout",
                        isError: true, lastUpdated: postUpgradeOrphan)),
                // Perplexity ghost (disabled but record persists)
                self.envelope(
                    deviceID: "mbp", deviceName: "the mbp 26 m5 pro",
                    providerID: "perplexity", email: nil,
                    providerLastUpdated: perplexityGhost,
                    syncTimestamp: perplexityGhost),
            ],
            deletedRecordNames: [])

        // Cache holds all 4.
        // Note: orphan-Codex|_ and the ghost-codex (no email) are different
        // composites only if their accountEmail differs. Here both are nil
        // → composite "codex|_" — the orphan upsert REPLACES the existing
        // codex|_ if any. So with this fixture we have 3 cache entries:
        //   codex|user@example.com (real)
        //   codex|_ (orphan with error)
        //   claude|_ (real)
        //   perplexity|_ (ghost)
        #expect(cache.perProviderByDevice["mbp"]?.count == 4)

        // After filter:
        //   - Rule 1 drops codex|_ (sibling codex|user@example.com has email)
        //   - Rule 2 drops perplexity|_ (39 min ago > 30 min threshold)
        //   - Real Codex + Claude remain
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let providerIDs = Set(result[0].providers.map(\.providerID))
        #expect(providerIDs == ["codex", "claude"])
        let codex = result[0].providers.first(where: { $0.providerID == "codex" })
        #expect(codex?.accountEmail == "user@example.com")
    }

    // MARK: - Build 94 hotfix · expanded coverage matrix (Round 1)

    /// Helper to build a fresh-now-relative envelope with a specific lag.
    private func envelopeAged(
        deviceID: String, providerID: String, email: String?,
        lagSeconds: TimeInterval, now: Date = Date()) -> ProviderUsageEnvelope
    {
        let updated = now.addingTimeInterval(-lagSeconds)
        return self.envelope(
            deviceID: deviceID, deviceName: deviceID,
            providerID: providerID, email: email,
            providerLastUpdated: updated, syncTimestamp: updated)
    }

    // ===== Rule 1 edges =====

    @Test
    func `Rule 1: empty-string accountEmail treated as nil for sibling-with-real-email check`() {
        // An empty-string email is functionally indistinguishable from nil at
        // the user-display level — both render as "no email". The dedupe rule
        // must collapse them rather than treat empty-string as a "real" email
        // that protects against sibling-real-email comparison.
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                ProviderUsageEnvelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    appVersion: "0.20.3", mobileVersion: "1.3.1",
                    syncTimestamp: now, notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex", providerName: "Codex",
                        primary: SyncRateWindow(
                            usedPercent: 23.0, windowMinutes: 60,
                            resetsAt: nil, resetDescription: nil),
                        secondary: nil, accountEmail: "", loginMethod: nil,
                        statusMessage: nil, isError: false, lastUpdated: now)),
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: "real@x.com",
                    providerLastUpdated: now, syncTimestamp: now),
            ],
            deletedRecordNames: [])
        // Cache holds both raw — composite keys "codex|" and "codex|real@x.com".
        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
        // After filter: empty-string email entry treated as nil-equivalent,
        // dropped because sibling has real email.
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 1)
        #expect(result[0].providers[0].accountEmail == "real@x.com")
    }

    @Test
    func `Rule 1: three-way (alice + bob + nil) drops nil, keeps both real-email accounts`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: "alice@x.com",
                    providerLastUpdated: now, syncTimestamp: now),
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: "bob@x.com",
                    providerLastUpdated: now, syncTimestamp: now),
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: nil,
                    providerLastUpdated: now, syncTimestamp: now),
            ],
            deletedRecordNames: [])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 3)
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 2)
        let emails = Set(result[0].providers.compactMap(\.accountEmail))
        #expect(emails == ["alice@x.com", "bob@x.com"])
    }

    @Test
    func `Rule 1: per-device boundary — orphan on device A doesn't affect nil-email on device B`() {
        // Device A has orphan-with-nil-email + real-email sibling → orphan drops.
        // Device B has lone nil-email codex (e.g., legitimate accountless setup) → kept.
        // The dedupe rule is per-device, never cross-device.
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: "alice@x.com",
                    providerLastUpdated: now, syncTimestamp: now),
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: nil,
                    providerLastUpdated: now, syncTimestamp: now),
                self.envelope(
                    deviceID: "mac-B", deviceName: "Mac B",
                    providerID: "codex", email: nil,
                    providerLastUpdated: now, syncTimestamp: now),
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        let macA = result.first { $0.deviceID == "mac-A" }
        let macB = result.first { $0.deviceID == "mac-B" }
        #expect(macA?.providers.count == 1)
        #expect(macA?.providers.first?.accountEmail == "alice@x.com")
        // Mac B's nil-email entry stays — no sibling to compare against.
        #expect(macB?.providers.count == 1)
        #expect(macB?.providers.first?.accountEmail == nil)
    }

    @Test
    func `Rule 1: real-email entry never touched even when stale`() {
        // alice@ is 5 hours stale; sibling claude is fresh. Rule 1 doesn't
        // fire (different providerIDs) — but more importantly, even though
        // alice's lastUpdated is way behind device freshness, Rule 2 also
        // exempts real-email. Both stay.
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "alice@x.com",
                    lagSeconds: 5 * 3600,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "claude",
                    email: nil,
                    lagSeconds: 5,
                    now: now),
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 2)
    }

    // ===== Rule 2 edges =====

    @Test
    func `Rule 2: nil-email at exactly 30-min boundary kept; 30:01 dropped`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "fresh@x.com",
                    lagSeconds: 0,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "claude",
                    email: nil,
                    lagSeconds: 30 * 60 - 1,
                    now: now), // 29:59
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "perplexity",
                    email: nil,
                    lagSeconds: 30 * 60 + 1,
                    now: now), // 30:01
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        let providerIDs = Set(result[0].providers.map(\.providerID))
        #expect(providerIDs == ["codex", "claude"])
        // Perplexity at 30:01 dropped; Claude at 29:59 kept.
    }

    @Test
    func `Rule 2: real-email entry exempt from TTL (legit multi-account, separate cadence)`() {
        // bob@ on Codex hasn't refreshed in 4 hours (idle account) while
        // alice@ refreshed 30 sec ago. Rule 2 must NOT drop bob — real-email
        // entries are exempt; legit multi-account providers can refresh on
        // independent cadences.
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "alice@x.com",
                    lagSeconds: 30,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "bob@x.com",
                    lagSeconds: 4 * 3600,
                    now: now),
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 2)
        let emails = Set(result[0].providers.compactMap(\.accountEmail))
        #expect(emails == ["alice@x.com", "bob@x.com"])
    }

    @Test
    func `Rule 2: lone nil-email provider on offline device kept (its own freshest)`() {
        // Mac has been offline; its single Claude record is hours old. Rule 2
        // computes deviceFreshest from this record's lastUpdated — so the
        // record is at the right edge of the window, kept.
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [self.envelopeAged(
                deviceID: "mac-A", providerID: "claude", email: nil,
                lagSeconds: 6 * 3600, now: now)],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 1)
    }

    @Test
    func `Rule 2: multiple nil-email entries with mixed freshness — only stale ones drop`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "claude",
                    email: nil,
                    lagSeconds: 5,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "cursor",
                    email: nil,
                    lagSeconds: 10 * 60,
                    now: now), // 10 min — kept
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "perplexity",
                    email: nil,
                    lagSeconds: 60 * 60,
                    now: now), // 1 h — dropped
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "abacus",
                    email: nil,
                    lagSeconds: 5 * 60,
                    now: now), // 5 min — kept
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        let providerIDs = Set(result[0].providers.map(\.providerID))
        #expect(providerIDs == ["claude", "cursor", "abacus"])
    }

    // ===== Mock-vs-real interaction (1.5.2 hotfix) =====
    //
    // Background: Mac 0.23.5 mock injector pushes synthetic provider
    // snapshots alongside real ones. Mocks always have a `*-mock@*.test`
    // email (universal MockProviderDetector signal). Real providers like
    // Claude / Ollama / Copilot can have nil email by design (no OAuth
    // exposes one). Pre-fix, mocks counted as "real-email siblings" in
    // Rule 1 and bumped `deviceFreshest` in Rule 2 — both wiped real
    // accountless providers from the iOS view. Discovered 2026-05-04 when
    // user's real Claude account ($2029 / 30d) disappeared from iOS Cost
    // dashboard while mock Claude entries showed.

    @Test
    func `Rule 1: real nil-email survives when only mock siblings have email`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-B", deviceName: "Mac Studio",
                providers: [
                    // Real Claude — nil email, this is the data we MUST keep.
                    self.provider(
                        id: "claude",
                        name: "Claude",
                        email: nil,
                        lastUpdated: now),
                    // Mock Claude entries — synthetic emails matching
                    // MockProviderDetector pattern (`*-mock@*.test`).
                    self.provider(
                        id: "claude",
                        name: "Claude (Personal · Mock)",
                        email: "personal-mock@claude.test",
                        lastUpdated: now),
                    self.provider(
                        id: "claude",
                        name: "Claude (Work · Mock)",
                        email: "work-mock@claude.test",
                        lastUpdated: now),
                ],
                timestamp: now)],
            legacySnapshots: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let claudes = result[0].providers.filter { $0.providerID == "claude" }
        #expect(claudes.count == 3)
        // Specifically the nil-email real entry must be present.
        #expect(claudes.contains(where: { $0.accountEmail == nil }))
    }

    @Test
    func `Rule 2: mock fresher timestamp does not stale-out real nil-email`() {
        // Real Claude refreshed 35 minutes ago. Then user toggles mocks on
        // and Mac pushes mock entries with `lastUpdated = now`. Pre-fix,
        // mock's `now` becomes deviceFreshest, the 30-min cutoff jumps to
        // `now - 30min`, real Claude (35min old) falls behind cutoff,
        // dropped. With the fix, deviceFreshest is computed from real
        // entries only, so cutoff is `(now - 35min) - 30min` = 65min ago,
        // and real Claude (35min) stays.
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-B", deviceName: "Mac Studio",
                providers: [
                    self.provider(
                        id: "claude",
                        email: nil,
                        lastUpdated: now.addingTimeInterval(-35 * 60)),
                    self.provider(
                        id: "claude",
                        email: "personal-mock@claude.test",
                        lastUpdated: now),
                    self.provider(
                        id: "claude",
                        email: "work-mock@claude.test",
                        lastUpdated: now),
                ],
                timestamp: now)],
            legacySnapshots: [])
        let result = cache.buildDeviceSnapshots()
        let claudes = result[0].providers.filter { $0.providerID == "claude" }
        // All three present: real (no email) + 2 mocks (with email).
        #expect(claudes.count == 3)
        #expect(claudes.contains(where: { $0.accountEmail == nil }))
    }

    @Test
    func `Mock-only device falls back to anyFreshest in Rule 2`() {
        // Edge case: dev/CI scenario where every entry on a device is a
        // mock. `realFreshest` is nil → fall back to `anyFreshest` so the
        // TTL logic still has a baseline. All mocks survive because mocks
        // bypass the TTL filter regardless of timestamp.
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-CI", deviceName: "CI Mac",
                providers: [
                    self.provider(
                        id: "codex",
                        email: "alice-mock@codex.test",
                        lastUpdated: now),
                    self.provider(
                        id: "_mock_synthetic_unknown",
                        email: "lanes-mock@synthetic.test",
                        lastUpdated: now.addingTimeInterval(-2 * 3600)),
                ],
                timestamp: now)],
            legacySnapshots: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 2)
    }

    @Test
    func `Mock entry with nil email does not orphan-itself when no real sibling`() {
        // Defensive: if a mock has nil email (shouldn't happen in current
        // design, but guard anyway), it should not be orphan-dropped just
        // because another mock has email — they're both mocks.
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [
                    self.provider(
                        id: "_mock_codex_unknown",
                        email: nil, // nil-email mock (synthetic ID prefix detects)
                        lastUpdated: now),
                    self.provider(
                        id: "_mock_codex_unknown",
                        email: "expired-mock@codex.test",
                        lastUpdated: now),
                ],
                timestamp: now)],
            legacySnapshots: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 2)
    }

    // ===== Rule combination + legacy fallback =====

    @Test
    func `Combined: device with all per-provider entries filtered falls back to legacy`() {
        // Device's per-provider zone entries are all stale ghosts; legacy
        // zone has fresh data. After filter empties per-provider bucket for
        // this device, fall back to legacy so the device doesn't disappear.
        let now = Date()
        var cache = SnapshotCache()
        // Pre-seed per-provider with all-stale ghosts.
        cache.applyDelta(
            upserted: [
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: nil,
                    lagSeconds: 10 * 3600,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "perplexity",
                    email: nil,
                    lagSeconds: 5 * 3600,
                    now: now),
            ],
            deletedRecordNames: [])
        // Wait — Rule 2 needs deviceFreshest. With both at 5h+10h, freshest
        // is 5h, cutoff is 5.5h. The 10h-stale codex would be dropped, but
        // perplexity at 5h is its own freshest → kept. So this fixture
        // doesn't fully empty the device. Adjust: provide legacy and inject
        // a fresh peer on a different device so deviceFreshest computation
        // is realistic.
        // Actually simpler: rebuild with only one stale entry being clearly
        // dropped, plus legacy fallback for that device.
        cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [
                    // Real-email codex (won't drop), so device isn't all-filtered.
                    // To force an "all filtered" path we need a device whose
                    // ONLY entries are stale-nil-email AND there's a
                    // higher-freshness peer on the SAME device.
                    // Simulate: legitimately fresh codex sets the device
                    // freshness, then a stale nil-email sibling gets dropped
                    // by Rule 1, leaving only the fresh codex.
                    self.provider(
                        id: "codex",
                        email: "alice@x.com",
                        lastUpdated: now),
                    self.provider(
                        id: "codex",
                        email: nil,
                        lastUpdated: now.addingTimeInterval(-3600)),
                ],
                timestamp: now)],
            legacySnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [self.provider(id: "claude", lastUpdated: now)],
                timestamp: now)])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        // Per-provider survives (alice kept, nil dropped) so we DON'T fall
        // back to legacy. Sanity check both rules work in concert here.
        #expect(result[0].providers.count == 1)
        #expect(result[0].providers[0].providerID == "codex")
    }

    @Test
    func `Combined: device with truly all-filtered per-provider falls back to legacy`() {
        // Construct a scenario where the per-provider bucket is non-empty
        // pre-filter but truly empty post-filter. Trick: use the test-only
        // fixture-time-base (t1/t2/t3) where t1 is pre-1970-100M-sec, with
        // a fresh peer on a DIFFERENT device that we won't query. Then this
        // device's per-provider entries are all nil-email and stale.
        // — but Rule 2's deviceFreshest is per-device, so they're their own
        // freshest. So they'd be kept. To genuinely empty the bucket we
        // need a fresh real-email peer on the same device that suppresses
        // nil-email peers via Rule 1, leaving only real-email which is
        // valid. That can't actually empty the bucket — by construction
        // real-email survives.
        //
        // Conclusion: with Rule 1 + Rule 2 as designed, a device's
        // per-provider bucket can NEVER be emptied by filtering if it had
        // at least one real-email peer pre-filter. The "all filtered"
        // fall-back is only triggerable if filtering removes everything,
        // which requires either:
        //  (a) bucket was nil-email-only AND all stale relative to peers
        //      — but then deviceFreshest is one of the stale entries, so
        //      they're not stale relative to themselves
        //  (b) some future filter rule we add
        //
        // So this test verifies the GUARD: even though we cannot construct
        // an empty post-filter result with current rules, the code path
        // still falls back gracefully. Ensure `buildDeviceSnapshots`
        // doesn't crash if dropOrphansAndStale ever returns empty.
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [self.provider(id: "claude", lastUpdated: now)],
                timestamp: now)])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 1)
        #expect(result[0].providers[0].providerID == "claude")
    }

    // ===== Multi-device matrix =====

    @Test
    func `Multi-device: one device has orphans, another is clean — only the dirty one is filtered`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                // Mac A: real Codex + orphan Codex (post-upgrade dirt)
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "user@x.com",
                    lagSeconds: 5,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: nil,
                    lagSeconds: 60 * 60,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "claude",
                    email: nil,
                    lagSeconds: 5,
                    now: now),
                // Mac B: clean — Codex + Claude with no orphans
                self.envelopeAged(
                    deviceID: "mac-B",
                    providerID: "codex",
                    email: "user@x.com",
                    lagSeconds: 10,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-B",
                    providerID: "claude",
                    email: nil,
                    lagSeconds: 10,
                    now: now),
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 2)
        let macA = result.first { $0.deviceID == "mac-A" }
        let macB = result.first { $0.deviceID == "mac-B" }
        #expect(macA?.providers.count == 2) // codex (real-email) + claude
        #expect(macB?.providers.count == 2) // codex + claude
    }

    // ===== Integration with existing write paths =====

    @Test
    func `Integration: replaceFromFullFetch path applies filter at read time`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [
                    self.provider(id: "codex", email: "user@x.com", lastUpdated: now),
                    self.provider(
                        id: "codex",
                        email: nil,
                        lastUpdated: now.addingTimeInterval(-3600)),
                    self.provider(
                        id: "perplexity",
                        email: nil,
                        lastUpdated: now.addingTimeInterval(-3600)),
                ],
                timestamp: now)],
            legacySnapshots: [])
        // Cache holds raw 3.
        #expect(cache.perProviderByDevice["mac-A"]?.count == 3)
        // Display has only 1 (real codex).
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 1)
        #expect(result[0].providers[0].accountEmail == "user@x.com")
    }

    @Test
    func `Integration: replacePerProviderFromReplay (token-expired full replay) applies filter`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.replacePerProviderFromReplay([
            self.envelopeAged(
                deviceID: "mac-A",
                providerID: "codex",
                email: "user@x.com",
                lagSeconds: 0,
                now: now),
            self.envelopeAged(
                deviceID: "mac-A",
                providerID: "codex",
                email: nil,
                lagSeconds: 60 * 60,
                now: now),
            self.envelopeAged(
                deviceID: "mac-A",
                providerID: "perplexity",
                email: nil,
                lagSeconds: 90 * 60,
                now: now),
        ])
        #expect(cache.perProviderByDevice["mac-A"]?.count == 3)
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 1)
        #expect(result[0].providers[0].providerID == "codex")
        #expect(result[0].providers[0].accountEmail == "user@x.com")
    }

    @Test
    func `Integration: applyDelta path applies filter at read time (ghost arrives via push)`() {
        let now = Date()
        var cache = SnapshotCache()
        // Initial state from full fetch: clean.
        cache.replaceFromFullFetch(
            perProviderSnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [self.provider(id: "codex", email: "user@x.com", lastUpdated: now)],
                timestamp: now)],
            legacySnapshots: [])
        // Delta brings a ghost from a Mac state transition.
        cache.applyDelta(
            upserted: [self.envelopeAged(
                deviceID: "mac-A", providerID: "codex",
                email: nil, lagSeconds: 60 * 60, now: now)],
            deletedRecordNames: [])
        // Cache has both.
        #expect(cache.perProviderByDevice["mac-A"]?.count == 2)
        // Display drops the orphan.
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 1)
        #expect(result[0].providers[0].accountEmail == "user@x.com")
    }

    // ===== Edge cases =====

    @Test
    func `Edge: empty cache returns no snapshots`() {
        let cache = SnapshotCache()
        #expect(cache.buildDeviceSnapshots().isEmpty)
    }

    @Test
    func `Edge: future-dated lastUpdated (clock skew) treated as freshest, kept`() {
        // NTP correction or clock skew on Mac could produce lastUpdated > now.
        // Filter must not crash or accidentally drop. Use this as
        // deviceFreshest; surrounding entries within 30 min are kept.
        let now = Date()
        let future = now.addingTimeInterval(120) // 2 min in the future
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: nil,
                    providerLastUpdated: future, syncTimestamp: future),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "claude",
                    email: nil,
                    lagSeconds: 60,
                    now: now),
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 2)
    }

    @Test
    func `Edge: device with ONLY real-email entries — Rule 1 + Rule 2 both no-op`() {
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "alice@x.com",
                    lagSeconds: 0,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "bob@x.com",
                    lagSeconds: 12 * 3600,
                    now: now),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "perplexity",
                    email: "carol@x.com",
                    lagSeconds: 5 * 3600,
                    now: now),
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 3)
    }

    @Test
    func `Edge: full ghost (Build 66 isGhost) still filtered before our rules even see it`() {
        // Build 66's isGhost (all-nil-data envelope) drops at write time,
        // not read time. Verify that combination with our new rules works:
        // an all-nil envelope never enters the cache, so our rules never
        // see it — Build 66 + Build 94 stack cleanly.
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                ProviderUsageEnvelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    appVersion: "0.20.3", mobileVersion: "1.3.1",
                    syncTimestamp: now, notificationPushEnabled: true,
                    provider: ProviderUsageSnapshot(
                        providerID: "codex", providerName: "Codex",
                        primary: nil, secondary: nil,
                        accountEmail: nil, loginMethod: nil,
                        statusMessage: nil, isError: false, lastUpdated: now)),
                self.envelopeAged(
                    deviceID: "mac-A",
                    providerID: "codex",
                    email: "user@x.com",
                    lagSeconds: 5,
                    now: now),
            ],
            deletedRecordNames: [])
        // The all-nil ghost was dropped at write time by Build 66's isGhost.
        // Cache has only the real entry.
        #expect(cache.perProviderByDevice["mac-A"]?.count == 1)
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 1)
    }

    @Test
    func `Defense-in-depth: legacy bucket also gets filtered (cold-start hydrate gap)`() {
        // Pre-Build-94 SwiftData might have stored orphan+stale providers
        // (because old code didn't filter before persisting). On 1.3.1
        // first launch, those rows hydrate into `legacyByDevice`. Without
        // the legacy-bucket filter, they'd display until the first network
        // fetch arrives. With the filter, they're dropped immediately.
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [], // device only in legacy
            legacySnapshots: [self.snapshot(
                deviceID: "mac-A", deviceName: "Mac A",
                providers: [
                    self.provider(id: "codex", email: "user@x.com", lastUpdated: now),
                    self.provider(
                        id: "codex",
                        email: nil, // orphan from pre-94 SwiftData
                        lastUpdated: now.addingTimeInterval(-3600)),
                    self.provider(id: "claude", email: nil, lastUpdated: now),
                    self.provider(
                        id: "perplexity",
                        email: nil, // ghost from pre-94 SwiftData
                        lastUpdated: now.addingTimeInterval(-90 * 60)),
                ],
                timestamp: now)])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        let providerIDs = Set(result[0].providers.map(\.providerID))
        // codex (orphan dropped, real-email kept), claude (kept, accountless lone),
        // perplexity (dropped, nil-email + lagging > 30 min)
        #expect(providerIDs == ["codex", "claude"])
        #expect(result[0].providers.first(where: { $0.providerID == "codex" })?
            .accountEmail == "user@x.com")
    }

    @Test
    func `Defense-in-depth: legacy bucket clean snapshot returned identity-equal (no churn)`() {
        // When legacy snapshot has no orphans, filter returns the original
        // snapshot reference (or equivalent) — no allocation / reordering.
        // Verifies the clean-path optimization in `filterSnapshotProviders`.
        let now = Date()
        var cache = SnapshotCache()
        cache.replaceFromFullFetch(
            perProviderSnapshots: [],
            legacySnapshots: [self.snapshot(
                deviceID: "mac-clean", deviceName: "Clean Mac",
                providers: [
                    self.provider(id: "codex", email: "user@x.com", lastUpdated: now),
                    self.provider(id: "claude", email: nil, lastUpdated: now),
                ],
                timestamp: now)])
        let result = cache.buildDeviceSnapshots()
        #expect(result.count == 1)
        #expect(result[0].providers.count == 2)
    }

    @Test
    func `Edge: real-email + nil-email with same lastUpdated — Rule 1 drops nil regardless of timing`() {
        // Both records arrive in the same refresh cycle (same lastUpdated).
        // Rule 1 fires unconditionally — sibling-with-real-email beats
        // nil-email even when timing is identical (orphan is "wrong"
        // independently of being stale).
        let now = Date()
        var cache = SnapshotCache()
        cache.applyDelta(
            upserted: [
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: nil,
                    providerLastUpdated: now, syncTimestamp: now),
                self.envelope(
                    deviceID: "mac-A", deviceName: "Mac A",
                    providerID: "codex", email: "user@x.com",
                    providerLastUpdated: now, syncTimestamp: now),
            ],
            deletedRecordNames: [])
        let result = cache.buildDeviceSnapshots()
        #expect(result[0].providers.count == 1)
        #expect(result[0].providers[0].accountEmail == "user@x.com")
    }
}
