import CloudKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CloudSyncBatchRecordProviderTests {
    private static let zoneID = CKRecordZone.ID(zoneName: "CodexBarSyncTests", ownerName: CKCurrentUserDefaultName)

    @Test
    func `delayed snapshot save results cannot confirm a newer payload`() throws {
        let (older, _) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        let (newer, newerHash) = try Self.snapshotRecord(used: 20, capturedAt: 2000.125)
        let name = newer.recordID.recordName
        var pending = [name: newerHash]
        var confirmed: [String: String] = [:]
        func finish(_ record: CKRecord) {
            let names = CloudSyncBatchRecordProvider.shouldApplySaveResult(
                record, desiredRecords: [newer.recordID: newer], pendingSaveHashes: pending)
                ? [record.recordID.recordName] : []
            CloudSyncSnapshotMigration.applyConfirmedSaveHashes(
                savedRecordNames: names, pendingSaveHashes: &pending, lastSnapshotHashes: &confirmed)
        }

        // The dropped old save completes after a replacement has already been queued.
        finish(older)
        #expect(pending[name] == newerHash)
        #expect(confirmed[name] == nil)
        finish(newer)
        #expect(pending[name] == nil)
        #expect(confirmed[name] == newerHash)
        #expect(!CloudSyncBatchRecordProvider.shouldApplySaveResult(
            older, desiredRecords: [newer.recordID: newer], pendingSaveHashes: pending))
        // A duplicate late result also cannot overwrite the already confirmed replacement.
        finish(older)
        #expect(confirmed[name] == newerHash)
    }

    @Test(arguments: [ProviderInstanceID.claude, .grok])
    func `live reset credit save results clear the pending marker without restoring cached inventory`(
        provider: ProviderInstanceID) throws
    {
        let (record, hash) = try Self.snapshotRecord(
            used: 10, capturedAt: 1000.125, provider: provider, resetCredits: 2)
        let restored = try #require(try CloudSyncBatchRecordProvider.snapshot(record))
        #expect(restored.usage.details.isEmpty, "Cache decoding must still discard live-only reset inventory")
        #expect(try CanonicalSyncJSON.hash(restored) != hash)
        var pending = [record.recordID.recordName: hash]
        var confirmed: [String: String] = [:]
        #expect(CloudSyncBatchRecordProvider.shouldApplySaveResult(
            record, desiredRecords: [record.recordID: record], pendingSaveHashes: pending))
        CloudSyncSnapshotMigration.applyConfirmedSaveHashes(
            savedRecordNames: [record.recordID.recordName],
            pendingSaveHashes: &pending,
            lastSnapshotHashes: &confirmed)
        #expect(pending.isEmpty)
        #expect(confirmed[record.recordID.recordName] == hash)
        #expect(!CloudSyncBatchRecordProvider.shouldApplySaveResult(
            record, desiredRecords: [record.recordID: record], pendingSaveHashes: pending))
    }

    @Test(arguments: [ProviderInstanceID.claude, .grok])
    func `a delayed result cannot confirm a newer reset credit inventory`(provider: ProviderInstanceID) throws {
        let (older, _) = try Self.snapshotRecord(
            used: 10, capturedAt: 1000.125, provider: provider, resetCredits: 1)
        let (newer, hash) = try Self.snapshotRecord(
            used: 10, capturedAt: 1000.125, provider: provider, resetCredits: 2)
        let pending = [newer.recordID.recordName: hash]
        let desired = [newer.recordID: newer]
        #expect(!CloudSyncBatchRecordProvider.shouldApplySaveResult(
            older, desiredRecords: desired, pendingSaveHashes: pending))
        #expect(CloudSyncBatchRecordProvider.shouldApplySaveResult(
            newer, desiredRecords: desired, pendingSaveHashes: pending))
        #expect(!CloudSyncBatchRecordProvider.shouldApplySaveResult(
            newer, desiredRecords: [:], pendingSaveHashes: pending))
    }

    @Test(arguments: ["schemaVersion", "provider", "deviceID", "accountKey", "fetchedAt", "displayLabel"])
    func `save confirmation compares all submitted metadata`(field: String) throws {
        let (desired, hash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        let (returned, _) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        switch field {
        case "schemaVersion": returned[field] = 2 as CKRecordValue
        case "fetchedAt": returned[field] = Date(timeIntervalSince1970: 2000) as CKRecordValue
        case "displayLabel": returned.encryptedValues[field] = "Changed" as CKRecordValue
        default: returned[field] = "changed" as CKRecordValue
        }
        #expect(!CloudSyncBatchRecordProvider.shouldApplySaveResult(
            returned,
            desiredRecords: [desired.recordID: desired],
            pendingSaveHashes: [desired.recordID.recordName: hash]))
    }

    @Test
    func `rebasing system fields keeps raw save confirmation intact`() throws {
        let (desired, hash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125, resetCredits: 2)
        let server = CKRecord(recordType: desired.recordType, recordID: desired.recordID)
        server["fetchedAt"] = Date(timeIntervalSince1970: 1) as CKRecordValue
        let rebased = CloudSyncEngine.copyUserFields(from: desired, onto: server)
        #expect(CloudSyncBatchRecordProvider.shouldApplySaveResult(
            rebased,
            desiredRecords: [desired.recordID: desired],
            pendingSaveHashes: [desired.recordID.recordName: hash]))
    }

    @Test
    func `a delete that replaces a queued save does not hold back a later publication`() throws {
        let (queued, queuedHash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        let (replacement, replacementHash) = try Self.snapshotRecord(used: 20, capturedAt: 2000.125)
        let recordID = queued.recordID
        let name = recordID.recordName
        var desired = [recordID: queued]
        var hashes = [name: queuedHash]
        var enginePending: Set<CKSyncEngine.PendingRecordZoneChange> = [.saveRecord(recordID)]

        // The provider is disabled while the save is still queued, so it is never sent.
        CloudSyncBatchRecordProvider.replaceSaveWithDelete(
            recordID, desiredRecords: &desired, pendingSaveHashes: &hashes)
        { remove, add in
            enginePending.remove(remove)
            enginePending.insert(add)
        }
        #expect(enginePending == [.deleteRecord(recordID)])
        #expect(desired.isEmpty)
        // pushAccountSnapshots parks a payload while its record name has a pending save hash.
        #expect(hashes[name] == nil)

        // Re-enabled in the same engine lifetime: the replacement is queued, and a late result of
        // the replaced save still cannot confirm it.
        desired[recordID] = replacement
        hashes[name] = replacementHash
        #expect(!CloudSyncBatchRecordProvider.shouldApplySaveResult(
            queued, desiredRecords: desired, pendingSaveHashes: hashes))
        #expect(CloudSyncBatchRecordProvider.shouldApplySaveResult(
            replacement, desiredRecords: desired, pendingSaveHashes: hashes))
    }

    @Test
    func `a sent save that is replaced by a delete cannot confirm anything afterwards`() throws {
        let (sent, sentHash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        var desired = [sent.recordID: sent]
        var hashes = [sent.recordID.recordName: sentHash]
        CloudSyncBatchRecordProvider.replaceSaveWithDelete(
            sent.recordID, desiredRecords: &desired, pendingSaveHashes: &hashes) { _, _ in }
        #expect(!CloudSyncBatchRecordProvider.shouldApplySaveResult(
            sent, desiredRecords: desired, pendingSaveHashes: hashes))
    }

    @Test
    func `disabling and re enabling a provider around a queued save publishes the new snapshot`() throws {
        let (queued, queuedHash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        let (replacement, replacementHash) = try Self.snapshotRecord(used: 20, capturedAt: 2000.125)
        var flow = try PublicationFlow(publishing: queued, hash: queuedHash)

        // Offline: the save stays queued, then the provider is disabled.
        flow.reconcile(currentSnapshots: [], enabledProviders: [])
        #expect(flow.enginePending == [.deleteRecord(flow.recordID)])
        #expect(flow.desired.isEmpty)

        // Re-enabled in the same engine lifetime.
        let republished = try flow.reconcileAndPublish(replacement, hash: replacementHash)
        #expect(republished, "the new snapshot must not stay parked behind the dropped save")
        #expect(flow.enginePending == [.saveRecord(flow.recordID)])
        #expect(flow.batchRecord() === replacement)

        flow.finishSave(returned: replacement)
        #expect(flow.confirmedHashes[flow.recordName] == replacementHash)
        #expect(flow.hashes.isEmpty)
    }

    @Test
    func `a late result of a replaced in flight save cannot confirm a different republication`() throws {
        let (sent, sentHash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        let (replacement, replacementHash) = try Self.snapshotRecord(used: 20, capturedAt: 2000.125)
        var flow = try PublicationFlow(publishing: sent, hash: sentHash)
        #expect(flow.batchRecord() === sent)
        flow.enginePending.remove(.saveRecord(flow.recordID)) // handed to CloudKit, result pending

        flow.reconcile(currentSnapshots: [], enabledProviders: [])
        #expect(try flow.reconcileAndPublish(replacement, hash: replacementHash))

        // Both a late success and a late failure of the replaced save are ignored.
        #expect(!flow.acceptsResult(sent))
        flow.finishSave(returned: sent)
        #expect(flow.confirmedHashes.isEmpty)
        #expect(flow.hashes[flow.recordName] == replacementHash)
        #expect(flow.batchRecord() === replacement)
    }

    @Test
    func `a late result of a replaced in flight save confirms an identical republication once`() throws {
        let (sent, hash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        let (identical, identicalHash) = try Self.snapshotRecord(used: 10, capturedAt: 1000.125)
        #expect(hash == identicalHash)
        var flow = try PublicationFlow(publishing: sent, hash: hash)
        #expect(flow.batchRecord() === sent)
        flow.enginePending.remove(.saveRecord(flow.recordID))

        flow.reconcile(currentSnapshots: [], enabledProviders: [])
        #expect(try flow.reconcileAndPublish(identical, hash: identicalHash))
        // Re-enabling cancelled the queued delete, so the server keeps the sent content.
        #expect(!flow.enginePending.contains(.deleteRecord(flow.recordID)))

        flow.finishSave(returned: sent)
        #expect(flow.confirmedHashes[flow.recordName] == hash)
        // The redundant queued save is dropped without leaving an in-flight marker behind.
        #expect(flow.batchRecord() == nil)
        #expect(flow.enginePending.isEmpty)
        #expect(flow.hashes.isEmpty)
    }

    @Test
    func `non snapshot saves keep their existing confirmation behavior`() {
        let record = CKRecord(recordType: "NonSnapshotFixture")
        #expect(CloudSyncBatchRecordProvider.shouldApplySaveResult(
            record, desiredRecords: [:], pendingSaveHashes: [:]))
    }

    /// Drives one snapshot record through the same static decisions `CloudSyncEngine` makes in
    /// `pushPendingSnapshots`, `makeChangeBatch` and `sentRecordZoneChanges`. The engine itself needs a
    /// CloudKit container, so this keeps the ordering under test without touching CloudKit.
    private struct PublicationFlow {
        let recordID: CKRecord.ID
        var desired: [CKRecord.ID: CKRecord] = [:]
        var hashes: [String: String] = [:]
        var confirmedHashes: [String: String] = [:]
        var fleetSnapshots: [String: AccountSnapshotSyncPayload] = [:]
        var enginePending: Set<CKSyncEngine.PendingRecordZoneChange> = []

        var recordName: String {
            self.recordID.recordName
        }

        init(publishing record: CKRecord, hash: String) throws {
            self.recordID = record.recordID
            #expect(try self.publish(record, hash: hash))
        }

        /// Mirrors the snapshot loop: a record name with an in-flight save parks the payload.
        mutating func publish(_ record: CKRecord, hash: String) throws -> Bool {
            let payload = try #require(try CloudSyncBatchRecordProvider.snapshot(record))
            if self.confirmedHashes[payload.recordName] == hash { return true }
            guard self.hashes[payload.recordName] == nil else { return false }
            self.desired[record.recordID] = record
            self.fleetSnapshots[payload.recordName] = payload
            self.hashes[payload.recordName] = hash
            self.enginePending.insert(.saveRecord(record.recordID))
            return true
        }

        mutating func reconcile(
            currentSnapshots: [AccountSnapshotSyncPayload],
            enabledProviders: Set<ProviderInstanceID>)
        {
            let plan = CloudSyncSnapshotReconciliation.plan(
                currentSnapshots: currentSnapshots,
                persistedSnapshots: self.fleetSnapshots,
                deviceID: "synthetic-device",
                enabledProviders: enabledProviders,
                authoritativeProviders: enabledProviders)
            for name in plan.recordNamesToCancelPendingDeletes where name == self.recordName {
                self.enginePending.remove(.deleteRecord(self.recordID))
            }
            let deletes = CloudSyncSnapshotMigration.immediateReconciliationDeletes(
                plan.recordNamesToDelete, protecting: [])
            for name in deletes where name == self.recordName {
                var pending = self.enginePending
                CloudSyncBatchRecordProvider.replaceSaveWithDelete(
                    self.recordID, desiredRecords: &self.desired, pendingSaveHashes: &self.hashes)
                { remove, add in
                    pending.remove(remove)
                    pending.insert(add)
                }
                self.enginePending = pending
            }
        }

        mutating func reconcileAndPublish(_ record: CKRecord, hash: String) throws -> Bool {
            let payload = try #require(try CloudSyncBatchRecordProvider.snapshot(record))
            self.reconcile(currentSnapshots: [payload], enabledProviders: [payload.provider])
            return try self.publish(record, hash: hash)
        }

        /// Mirrors `makeChangeBatch`, which only asks for records with a pending save.
        mutating func batchRecord() -> CKRecord? {
            guard self.enginePending.contains(.saveRecord(self.recordID)) else { return nil }
            var pending = self.enginePending
            let record = CloudSyncBatchRecordProvider.record(
                for: self.recordID, desiredRecords: self.desired, pendingSaveHashes: &self.hashes)
            { pending.remove($0) }
            self.enginePending = pending
            return record
        }

        func acceptsResult(_ record: CKRecord) -> Bool {
            CloudSyncBatchRecordProvider.shouldApplySaveResult(
                record, desiredRecords: self.desired, pendingSaveHashes: self.hashes)
        }

        /// Mirrors the saved-record filter in `sentRecordZoneChanges`.
        mutating func finishSave(returned record: CKRecord) {
            guard self.acceptsResult(record) else { return }
            self.desired.removeValue(forKey: record.recordID)
            CloudSyncSnapshotMigration.applyConfirmedSaveHashes(
                savedRecordNames: [record.recordID.recordName],
                pendingSaveHashes: &self.hashes,
                lastSnapshotHashes: &self.confirmedHashes)
        }
    }

    private static func snapshotRecord(
        used: Double,
        capturedAt: TimeInterval,
        provider: ProviderInstanceID = .claude,
        resetCredits: Int? = nil) throws -> (CKRecord, String)
    {
        let details: [ProviderDetailSection] = try resetCredits.map {
            try [ProviderDetailSection(rows: [.init(label: "Limit Reset Credits", value: String($0))])]
        } ?? []
        let payload = AccountSnapshotSyncPayload(
            provider: provider,
            deviceID: "synthetic-device",
            accountIdentity: "synthetic-account",
            displayLabel: "Synthetic",
            usage: UsageSnapshot(
                primary: RateWindow(usedPercent: used, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                details: details,
                updatedAt: Date(timeIntervalSince1970: capturedAt),
                identity: ProviderIdentitySnapshot(
                    providerID: provider, accountEmail: nil, accountOrganization: nil, loginMethod: nil)))
        let record = CKRecord(
            recordType: SyncRecordType.accountSnapshot.rawValue,
            recordID: CKRecord.ID(recordName: payload.recordName, zoneID: Self.zoneID))
        record["schemaVersion"] = payload.schemaVersion as CKRecordValue
        record["provider"] = payload.provider.rawValue as CKRecordValue
        record["deviceID"] = payload.deviceID as CKRecordValue
        record["accountKey"] = payload.accountKey as CKRecordValue
        record["fetchedAt"] = payload.fetchedAt as CKRecordValue
        record.encryptedValues["displayLabel"] = payload.displayLabel as CKRecordValue
        record.encryptedValues["usagePayload"] = try CanonicalSyncJSON.string(payload.usage) as CKRecordValue
        return try (record, CanonicalSyncJSON.hash(payload))
    }
}
