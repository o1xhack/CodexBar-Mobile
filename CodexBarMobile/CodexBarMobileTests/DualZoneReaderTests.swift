import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// P5 — unit tests for the pure reconstruct + priority-merge helpers that sit
/// in `CloudSyncManager`. Real CloudKit I/O is covered by real-device smoke
/// testing (deferred until Production schema is deployed).
@Suite("Dual-zone reader helpers")
struct DualZoneReaderTests {
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t2 = Date(timeIntervalSince1970: 1_700_100_000)
    private let t3 = Date(timeIntervalSince1970: 1_700_200_000)

    private func makeProvider(id: String, lastUpdated: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: id.capitalized,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated)
    }

    private func makeEnvelope(
        deviceID: String,
        deviceName: String,
        syncTimestamp: Date,
        providerID: String,
        providerLastUpdated: Date
    ) -> ProviderUsageEnvelope {
        ProviderUsageEnvelope(
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: "0.20.1",
            mobileVersion: "1.3.0",
            syncTimestamp: syncTimestamp,
            notificationPushEnabled: true,
            provider: makeProvider(id: providerID, lastUpdated: providerLastUpdated))
    }

    // MARK: - reconstructSnapshots

    @Test("Envelopes from the same device collapse into one snapshot")
    func reconstructGroupsByDeviceID() {
        let envelopesByDeviceID: [String: [ProviderUsageEnvelope]] = [
            "mac-1": [
                makeEnvelope(
                    deviceID: "mac-1", deviceName: "Mac 1",
                    syncTimestamp: t1, providerID: "codex", providerLastUpdated: t1),
                makeEnvelope(
                    deviceID: "mac-1", deviceName: "Mac 1",
                    syncTimestamp: t2, providerID: "claude", providerLastUpdated: t2),
            ],
        ]
        let snapshots = CloudSyncManager.reconstructSnapshots(
            envelopesByDeviceID: envelopesByDeviceID)

        #expect(snapshots.count == 1)
        let snapshot = snapshots[0]
        #expect(snapshot.deviceID == "mac-1")
        #expect(snapshot.providers.count == 2)
        // Device-level timestamp = max of constituent envelopes.
        #expect(snapshot.syncTimestamp == self.t2)
        // Providers sorted by lastUpdated desc.
        #expect(snapshot.providers.first?.providerID == "claude")
        #expect(snapshot.providers.last?.providerID == "codex")
        #expect(snapshot.publicationTimestamp(for: snapshot.providers[0]) == self.t2)
        #expect(snapshot.publicationTimestamp(for: snapshot.providers[1]) == self.t1)
    }

    @Test
    func `Multiple devices produce multiple snapshots, sorted newest-first`() {
        let envelopesByDeviceID: [String: [ProviderUsageEnvelope]] = [
            "mac-old": [
                makeEnvelope(
                    deviceID: "mac-old", deviceName: "Old Mac",
                    syncTimestamp: t1, providerID: "codex", providerLastUpdated: t1),
            ],
            "mac-new": [
                makeEnvelope(
                    deviceID: "mac-new", deviceName: "New Mac",
                    syncTimestamp: t3, providerID: "claude", providerLastUpdated: t3),
            ],
        ]
        let snapshots = CloudSyncManager.reconstructSnapshots(
            envelopesByDeviceID: envelopesByDeviceID)

        #expect(snapshots.count == 2)
        #expect(snapshots[0].deviceID == "mac-new")
        #expect(snapshots[1].deviceID == "mac-old")
    }

    @Test("Empty input produces empty output")
    func reconstructEmpty() {
        let snapshots = CloudSyncManager.reconstructSnapshots(envelopesByDeviceID: [:])
        #expect(snapshots.isEmpty)
    }

    // MARK: - prioritiseByDevice

    @Test("Per-provider snapshot wins over legacy for the same device")
    func priorityPerProviderOverLegacy() {
        let perProvider = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", lastUpdated: t3)],
            syncTimestamp: t3,
            deviceName: "Mac A",
            deviceID: "mac-a")
        // Legacy for the same device, but newer timestamp — per-provider still
        // wins because the rule is priority by tier, not by timestamp.
        let legacy = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", lastUpdated: t3.addingTimeInterval(1000))],
            syncTimestamp: t3.addingTimeInterval(1000),
            deviceName: "Mac A",
            deviceID: "mac-a")

        let merged = CloudSyncManager.prioritiseByDevice(
            perProvider: [perProvider], legacy: [legacy])

        #expect(merged.count == 1)
        #expect(merged[0].providers.first?.providerID == "codex")
    }

    @Test("Devices only in legacy pass through")
    func priorityLegacyFallback() {
        let perProvider = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", lastUpdated: t3)],
            syncTimestamp: t3, deviceName: "Mac A", deviceID: "mac-a")
        let legacy = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", lastUpdated: t2)],
            syncTimestamp: t2, deviceName: "Mac B", deviceID: "mac-b")

        let merged = CloudSyncManager.prioritiseByDevice(
            perProvider: [perProvider], legacy: [legacy])

        #expect(merged.count == 2)
        #expect(merged.contains(where: { $0.deviceID == "mac-a" }))
        #expect(merged.contains(where: { $0.deviceID == "mac-b" }))
    }

    @Test("Only legacy present — merged result matches legacy")
    func priorityOnlyLegacy() {
        let legacy = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", lastUpdated: t1)],
            syncTimestamp: t1, deviceName: "Old Mac", deviceID: "mac-old")

        let merged = CloudSyncManager.prioritiseByDevice(
            perProvider: [], legacy: [legacy])

        #expect(merged.count == 1)
        #expect(merged[0].deviceID == "mac-old")
    }

    @Test("Only per-provider present — merged result matches per-provider")
    func priorityOnlyPerProvider() {
        let perProvider = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", lastUpdated: t3)],
            syncTimestamp: t3, deviceName: "New Mac", deviceID: "mac-new")

        let merged = CloudSyncManager.prioritiseByDevice(
            perProvider: [perProvider], legacy: [])

        #expect(merged.count == 1)
        #expect(merged[0].deviceID == "mac-new")
    }

    @Test("Legacy snapshots without deviceID dedup by deviceName")
    func priorityDeviceNameFallback() {
        // Pre-UUID Mac builds wrote deviceID=nil, so the fallback key is the
        // deviceName. A per-provider snapshot for a device with a UUID should
        // NOT collide with a legacy device of the same name unless deviceIDs
        // match — which here they don't.
        let perProvider = SyncedUsageSnapshot(
            providers: [makeProvider(id: "codex", lastUpdated: t3)],
            syncTimestamp: t3, deviceName: "My Mac", deviceID: "mac-uuid")
        let legacy = SyncedUsageSnapshot(
            providers: [makeProvider(id: "claude", lastUpdated: t1)],
            syncTimestamp: t1, deviceName: "My Mac", deviceID: nil)

        let merged = CloudSyncManager.prioritiseByDevice(
            perProvider: [perProvider], legacy: [legacy])

        // Different keys — both kept.
        #expect(merged.count == 2)
    }

    // MARK: - Realistic-distribution fixtures (Build 83 · Agent C)
    //
    // Round 3 audit + Agent C flagged: dual-zone reconstruction has been
    // tested only on toy 1-2-provider snapshots. Real sparse-legacy +
    // dense-new setups, long-idle devices, and cross-date boundaries
    // were uncovered. These add the missing distributions.

    @Test("Reconstruct keeps 7-day-fresh + 30-day-old entries from same device ordered newest-first")
    func reconstructLongIdlePlusFreshMixedTimestamps() {
        let anchor = Date(timeIntervalSince1970: 1_745_500_000)
        let thirtyDaysAgo = anchor.addingTimeInterval(-30 * 86400)
        let sevenDaysAgo = anchor.addingTimeInterval(-7 * 86400)

        // Same device has written envelopes across a long gap: an old
        // Codex entry from 30 days ago and a fresh Claude entry from 7
        // days ago. Reconstructed snapshot must keep both providers and
        // sort them newest-first at the provider level.
        let envelopesByDeviceID: [String: [ProviderUsageEnvelope]] = [
            "mac-longrun": [
                makeEnvelope(
                    deviceID: "mac-longrun", deviceName: "Long-Running Mac",
                    syncTimestamp: thirtyDaysAgo,
                    providerID: "codex", providerLastUpdated: thirtyDaysAgo),
                makeEnvelope(
                    deviceID: "mac-longrun", deviceName: "Long-Running Mac",
                    syncTimestamp: sevenDaysAgo,
                    providerID: "claude", providerLastUpdated: sevenDaysAgo),
            ],
        ]
        let snapshots = CloudSyncManager.reconstructSnapshots(
            envelopesByDeviceID: envelopesByDeviceID)

        #expect(snapshots.count == 1)
        let snapshot = snapshots[0]
        #expect(snapshot.providers.count == 2)
        // Device sync timestamp reflects the freshest envelope, not the
        // stale one — pre-fix a "min" bug would misrepresent sync recency.
        #expect(snapshot.syncTimestamp == sevenDaysAgo)
        // Providers sorted newest first.
        #expect(snapshot.providers.first?.providerID == "claude")
        #expect(snapshot.providers.last?.providerID == "codex")
    }

    @Test("Priority merge keeps legacy intact when per-provider list is empty (transient zone error)")
    func priorityEmptyPerProviderKeepsLegacyIntact() {
        // CloudKit per-provider zone can return `[]` for two reasons:
        //   (a) Authoritative empty — the user really has no data there.
        //   (b) Transient error — request failed, caller still wants the
        //       priority-merge to degrade gracefully.
        // `prioritiseByDevice` sees just an array, so its job is "legacy
        // is the fallback when per-provider has no entry for that device".
        // Pin that behavior here with a legacy-only + empty-per-provider
        // input; every legacy device must survive.
        let legacy = [
            SyncedUsageSnapshot(
                providers: [makeProvider(id: "codex", lastUpdated: t1)],
                syncTimestamp: t1, deviceName: "Mac A", deviceID: "mac-a"),
            SyncedUsageSnapshot(
                providers: [makeProvider(id: "claude", lastUpdated: t2)],
                syncTimestamp: t2, deviceName: "Mac B", deviceID: "mac-b"),
        ]

        let merged = CloudSyncManager.prioritiseByDevice(
            perProvider: [], legacy: legacy)

        #expect(merged.count == 2)
        #expect(Set(merged.map(\.deviceID)) == ["mac-a", "mac-b"])
        // Provider identities preserved — a regression that drops legacy
        // on empty-per-provider would show 0 here.
        #expect(merged.compactMap { $0.providers.first?.providerID }.sorted() == ["claude", "codex"])
    }
}
