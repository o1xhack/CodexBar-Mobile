import CodexBarSync
import Foundation
import SwiftData

/// Writes CloudKit-sourced snapshots into the local SwiftData store.
///
/// P2a: parallel-write only. `CloudSyncReader` calls `upsert` *after* the
/// legacy in-memory merge path has completed, so views keep reading the old
/// `@Observable SyncedUsageData`. P2b will flip views to `@Query` against
/// these @Model types.
///
/// Idempotency guarantees:
/// - `ProviderSnapshotModel` is keyed by `compositeKey = deviceID|providerID|accountEmail`.
///   Re-upserting the same snapshot updates fields in place, never duplicates.
/// - `UtilizationEntryModel` has no schema-level unique key. This bridge dedups
///   by `(provider, seriesName, capturedAt)` when inserting.
/// - `DeviceRecord` is keyed by `deviceID`. Legacy snapshots without a
///   deviceID use the fallback synthesised from the device name (see
///   `deviceIDFallback`) so multiple anonymous devices with different names
///   don't collide into one row.
enum SwiftDataBridge {
    // MARK: - Public entry points

    /// Upsert the *merged* snapshot that the legacy path currently produces.
    /// Upsert raw per-device snapshots (the unmerged array returned by
    /// `CloudSyncReader.fetchAllDeviceSnapshots`). Each snapshot becomes (or
    /// updates) its own `DeviceRecord` with its own set of providers.
    ///
    /// Note: there is intentionally no separate "merged snapshot" upsert API.
    /// A merged snapshot's `deviceName` is derived from the set of
    /// contributing devices, which changes as devices are added/removed —
    /// storing it as a row under a `"legacy:<deviceName>"` fallback key
    /// orphans the old merged row every time the set changes. P2b views
    /// instead re-derive the merged view on the fly via `@Query` against
    /// per-device rows, which are keyed by stable deviceID.
    ///
    /// Legacy snapshots from the KVS fallback path (single-device Macs that
    /// predate CloudKit sync) still arrive with `deviceID == nil` but carry
    /// a stable single `deviceName`; they land in a `"legacy:<deviceName>"`
    /// row via `deviceIDFallback` — that's fine because the name IS stable
    /// for a single device.
    static func upsert(
        deviceSnapshots: [SyncedUsageSnapshot],
        into context: ModelContext,
        saveChanges: Bool = true) throws
    {
        // Build the set of deviceIDs that should exist after this upsert. Anything
        // currently in the store but NOT in this set has been removed upstream
        // (user disconnected a Mac, reset sync, etc.) and must be pruned. Without
        // this, stale DeviceRecord rows accumulate forever. Flagged in Codex review (P2).
        var incomingDeviceIDs: Set<String> = []
        for snapshot in deviceSnapshots {
            let deviceID = snapshot.deviceID ?? Self.deviceIDFallback(for: snapshot)
            incomingDeviceIDs.insert(deviceID)
            try Self.upsertSnapshot(snapshot, into: context)
        }

        // Prune DeviceRecord rows that correspond to devices that disappeared
        // from upstream. Cascades to ProviderSnapshotModel and UtilizationEntryModel
        // via @Relationship(deleteRule: .cascade).
        let allDevicesDescriptor = FetchDescriptor<DeviceRecord>()
        let existingDevices = try context.fetch(allDevicesDescriptor)
        for device in existingDevices where !incomingDeviceIDs.contains(device.deviceID) {
            context.delete(device)
        }

        // One save includes all device writes and pruning. Incremental batch
        // callers defer this boundary until the change token is staged too.
        if saveChanges { try context.save() }
    }

    /// Mirror the cache state after an incremental refresh.
    ///
    /// `SnapshotCache.buildDeviceSnapshots()` supplies the complete, filtered
    /// provider set for every included device. Missing providers are therefore
    /// removed for those devices. The device array is not authoritative at the
    /// global level, so devices absent from this call are preserved.
    static func upsertIncrementalCacheMirror(
        cacheDeviceSnapshots: [SyncedUsageSnapshot],
        deletedRecordNames: [String] = [],
        into context: ModelContext,
        saveChanges: Bool = true) throws
    {
        // Upsert first so an email-key → opaque-key identity upgrade can
        // rekey its provider and long ledger history before the same delta's
        // old-record deletion arrives. The subsequent delete then no-ops on
        // the migrated key; pure deletions are still removed below.
        for snapshot in cacheDeviceSnapshots {
            try self.upsertSnapshot(snapshot, into: context)
        }
        try self.deleteProviderRecords(named: deletedRecordNames, from: context, saveChanges: false)
        if saveChanges { try context.save() }
    }

    static func deleteProviderRecords(
        named recordNames: [String],
        from context: ModelContext,
        saveChanges: Bool = true) throws
    {
        guard !recordNames.isEmpty else { return }

        for recordName in recordNames {
            guard let parsed = splitProviderRecordName(recordName) else {
                continue
            }

            let compositeKey = ProviderSnapshotModel.makeCompositeKey(
                deviceID: parsed.deviceID,
                providerID: parsed.providerID,
                accountEmail: nil,
                accountRecordKey: parsed.identityComponent)
            let providerDescriptor = FetchDescriptor<ProviderSnapshotModel>(
                predicate: #Predicate { $0.compositeKey == compositeKey })
            // A deleted record (renamed account key, removed account or provider) removes the
            // snapshot only; its cost history stays in the ledger.
            for provider in try context.fetch(providerDescriptor) {
                context.delete(provider)
            }
        }

        if saveChanges { try context.save() }
    }

    /// Commit one CloudKit batch and its cursor together. Failed writes must
    /// leave the previous cursor replayable, including after app relaunch.
    static func commitIncrementalBatch(
        snapshots: [SyncedUsageSnapshot],
        deletedRecordNames: [String],
        replacingAllDevices: Bool,
        zoneName: String,
        tokenData: Data?,
        in context: ModelContext,
        beforeSave: () throws -> Void = {}) throws
    {
        let autosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosaveEnabled }
        do {
            if replacingAllDevices {
                try self.upsert(deviceSnapshots: snapshots, into: context, saveChanges: false)
            } else {
                try self.upsertIncrementalCacheMirror(
                    cacheDeviceSnapshots: snapshots,
                    deletedRecordNames: deletedRecordNames,
                    into: context, saveChanges: false)
            }
            if let tokenData {
                try self.saveChangeToken(
                    forZone: zoneName, tokenData: tokenData, context: context, saveChanges: false)
            }
            try beforeSave()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Core upsert

    private static func upsertSnapshot(
        _ snapshot: SyncedUsageSnapshot,
        into context: ModelContext) throws
    {
        let deviceID = snapshot.deviceID ?? Self.deviceIDFallback(for: snapshot)
        let device = try Self.fetchOrCreateDevice(
            deviceID: deviceID,
            deviceName: snapshot.deviceName,
            appVersion: snapshot.appVersion,
            lastSyncAt: snapshot.syncTimestamp,
            in: context)
        device.providerPublicationTimestampsData = try CloudSyncConstants.makeJSONEncoder()
            .encode(snapshot.providerPublicationTimestamps)
        device.providerQuotaSourcesData = try CloudSyncConstants.makeJSONEncoder()
            .encode(snapshot.providerQuotaSources)

        // Build the set of composite keys present in this snapshot. Anything on the
        // existing DeviceRecord that is NOT in this set has been removed upstream
        // (user disconnected a provider on Mac) and must be pruned locally to keep
        // the SwiftData mirror in lockstep. Without this, phantom provider rows
        // accumulate forever. Flagged in Codex review (P2).
        let incomingKeys: Set<String> = Set(snapshot.providers.map { provider in
            ProviderSnapshotModel.makeCompositeKey(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey)
        })

        // Capture the persisted rows before inserting/updating the bounded
        // snapshot. A selected local-cost account can disappear entirely from
        // an incremental payload, so no wire tombstone remains from which to
        // discover the previous owner of CWL's longer history.
        let staleDescriptor = FetchDescriptor<ProviderSnapshotModel>(
            predicate: #Predicate { $0.deviceID == deviceID })
        let existingForDevice = try context.fetch(staleDescriptor)

        // A provider-shared local-cost summary can move between token accounts
        // when the selected account changes. Preserve CWL's longer history by
        // atomically rekeying old-owner rows to the single incoming owner
        // before processing clear tombstones and bounded replacement blobs.
        for (providerID, providers) in Dictionary(grouping: snapshot.providers, by: \.providerID) {
            let costOwners = providers.filter { $0.costSummary != nil }
            guard costOwners.count == 1, let costOwner = costOwners.first else { continue }
            // Account-native summaries must never move between accounts, even
            // if an older producer accidentally emitted a clear tombstone.
            guard !Self.usesAccountNativeCostOwnership(providerID: providerID) else { continue }
            for oldOwner in providers where oldOwner.costSummaryCleared == true {
                try CostLedgerService.migrateCostOwnership(
                    deviceID: deviceID,
                    providerID: providerID,
                    fromAccountEmail: oldOwner.accountEmail,
                    fromAccountRecordKey: oldOwner.accountRecordKey,
                    to: costOwner,
                    in: context)
            }

            // Incremental cache snapshots omit deleted accounts rather than
            // retaining their clear tombstone. Recover the previous owner from
            // SwiftData before stale-row pruning so ledger-only days do not get
            // deleted. Mistral is deliberately excluded: its summaries are
            // account-native, so transferring a removed account's spend would
            // incorrectly merge two independent accounts.
            let costOwnerKey = ProviderSnapshotModel.makeCompositeKey(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: costOwner.accountEmail,
                accountRecordKey: costOwner.accountRecordKey)
            for oldOwner in existingForDevice where
                oldOwner.providerID == providerID
                && oldOwner.compositeKey != costOwnerKey
                && !incomingKeys.contains(oldOwner.compositeKey)
            {
                let ownsPersistedCostHistory = try oldOwner.costSummaryData != nil
                    || (CostLedgerService.hasRows(
                        deviceID: deviceID,
                        providerID: providerID,
                        accountEmail: oldOwner.accountEmail,
                        accountRecordKey: oldOwner.accountRecordKey,
                        in: context))
                guard ownsPersistedCostHistory else { continue }
                try CostLedgerService.migrateCostOwnership(
                    deviceID: deviceID,
                    providerID: providerID,
                    fromAccountEmail: oldOwner.accountEmail,
                    fromAccountRecordKey: oldOwner.accountRecordKey,
                    to: costOwner,
                    in: context)
            }

            // History kept while the provider had no known account has no snapshot row any more.
            // A machine's local costs belong to its single current owner, so move it there too;
            // otherwise the same days could count under both the old and the new account.
            // Account-level spend (API dashboards) is never moved between accounts.
            for ledgerOwner in try CostLedgerService.ledgerOwners(
                deviceID: deviceID, providerID: providerID, in: context)
            where ProviderSnapshotMerger.usesLocalCostMerge(providerID: providerID)
            {
                let ledgerOwnerKey = ProviderSnapshotModel.makeCompositeKey(
                    deviceID: deviceID,
                    providerID: providerID,
                    accountEmail: ledgerOwner.accountEmail,
                    accountRecordKey: ledgerOwner.accountRecordKey)
                guard ledgerOwnerKey != costOwnerKey, !incomingKeys.contains(ledgerOwnerKey) else { continue }
                try CostLedgerService.migrateCostOwnership(
                    deviceID: deviceID,
                    providerID: providerID,
                    fromAccountEmail: ledgerOwner.accountEmail,
                    fromAccountRecordKey: ledgerOwner.accountRecordKey,
                    to: costOwner,
                    in: context)
            }
        }

        // A clear tombstone may drop leftovers only where this snapshot named the single new
        // owner and its history was just moved there; otherwise the days stay in the ledger.
        let movedCostProviderIDs = Set(
            Dictionary(grouping: snapshot.providers, by: \.providerID)
                .filter { providerID, providers in
                    providers.count(where: { $0.costSummary != nil }) == 1
                        && !Self.usesAccountNativeCostOwnership(providerID: providerID)
                }
                .keys)
        for provider in snapshot.providers {
            try Self.upsertProvider(
                provider,
                deviceID: deviceID,
                device: device,
                clearedHistoryWasMoved: movedCostProviderIDs.contains(provider.providerID),
                in: context)
        }

        // Prune snapshot rows that belonged to this device but disappeared from
        // the incoming snapshot. Cascade delete on the provider → utilization
        // relationship cleans up orphan entries automatically. Cost history is
        // never deleted for an absence: the account may be temporarily unknown,
        // the cache may have filtered the entry, or the provider was turned
        // off; the ledger keeps days the Mac's own logs may no longer hold
        // (Research 024 / 069). Unmatched history is simply not displayed.
        for existing in existingForDevice where !incomingKeys.contains(existing.compositeKey) {
            context.delete(existing)
        }


    }

    /// Providers whose cost summaries describe one account rather than a
    /// provider-shared local token ledger. Keep this list synchronized with
    /// Mac-side multi-account snapshot mapping; adding an account-native cost
    /// producer requires an explicit entry here before it can sync safely.
    private static func usesAccountNativeCostOwnership(providerID: String) -> Bool {
        providerID.caseInsensitiveCompare("mistral") == .orderedSame
    }

    private static func fetchOrCreateDevice(
        deviceID: String,
        deviceName: String,
        appVersion: String?,
        lastSyncAt: Date,
        in context: ModelContext) throws -> DeviceRecord
    {
        let descriptor = FetchDescriptor<DeviceRecord>(
            predicate: #Predicate { $0.deviceID == deviceID })
        if let existing = try context.fetch(descriptor).first {
            existing.deviceName = deviceName
            existing.appVersion = appVersion
            existing.lastSyncAt = lastSyncAt
            return existing
        }
        let record = DeviceRecord(
            deviceID: deviceID,
            deviceName: deviceName,
            appVersion: appVersion,
            lastSyncAt: lastSyncAt)
        context.insert(record)
        return record
    }

    private static func upsertProvider(
        _ provider: ProviderUsageSnapshot,
        deviceID: String,
        device: DeviceRecord,
        clearedHistoryWasMoved: Bool,
        in context: ModelContext) throws
    {
        let compositeKey = ProviderSnapshotModel.makeCompositeKey(
            deviceID: deviceID,
            providerID: provider.providerID,
            accountEmail: provider.accountEmail,
            accountRecordKey: provider.accountRecordKey)
        let descriptor = FetchDescriptor<ProviderSnapshotModel>(
            predicate: #Predicate { $0.compositeKey == compositeKey })

        if let accountRecordKey = provider.accountRecordKey {
            try CostLedgerService.migrateLegacyAccountKey(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: accountRecordKey,
                accountIdentityKeys: CostLedgerService.accountIdentityKeys(for: provider),
                in: context)
        }

        // Encode opaque blobs via the project-wide factory so date strategy
        // stays in lockstep with the decoder in `readAllDeviceSnapshots` and
        // every other JSON site in the codebase. Build 66 root-cause: hand
        // rolled `JSONEncoder()` defaulted to `.deferredToDate` and dropped
        // every Date through the round-trip.
        let encoder = CloudSyncConstants.makeJSONEncoder()
        let rateWindowsData = (try? encoder.encode(provider.allRateWindows)) ?? Data("[]".utf8)
        let costSummaryData = provider.costSummary.flatMap { try? encoder.encode($0) }
        let budgetData = provider.budget.flatMap { try? encoder.encode($0) }
        let perplexityCreditsData = provider.perplexityCredits.flatMap { try? encoder.encode($0) }
        let providerPayloadData = try? encoder.encode(provider)

        let model: ProviderSnapshotModel
        if let existing = try context.fetch(descriptor).first {
            model = existing
        } else if provider.accountRecordKey != nil {
            let legacyKey = ProviderSnapshotModel.makeCompositeKey(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail)
            let legacyDescriptor = FetchDescriptor<ProviderSnapshotModel>(
                predicate: #Predicate { $0.compositeKey == legacyKey })
            if let legacy = try context.fetch(legacyDescriptor).first {
                legacy.compositeKey = compositeKey
                model = legacy
            } else {
                model = ProviderSnapshotModel(
                    deviceID: deviceID,
                    providerID: provider.providerID,
                    providerName: provider.providerName,
                    accountEmail: provider.accountEmail,
                    accountRecordKey: provider.accountRecordKey,
                    lastUpdated: provider.lastUpdated)
                context.insert(model)
            }
        } else {
            let created = ProviderSnapshotModel(
                deviceID: deviceID,
                providerID: provider.providerID,
                providerName: provider.providerName,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey,
                loginMethod: provider.loginMethod,
                statusMessage: provider.statusMessage,
                isError: provider.isError,
                lastUpdated: provider.lastUpdated,
                subscriptionExpiresAt: provider.subscriptionExpiresAt,
                subscriptionRenewsAt: provider.subscriptionRenewsAt,
                providerPayloadData: providerPayloadData,
                rateWindowsData: rateWindowsData,
                costSummaryData: costSummaryData,
                budgetData: budgetData,
                perplexityCreditsData: perplexityCreditsData,
                device: device)
            context.insert(created)
            model = created
        }

        model.providerName = provider.providerName
        model.accountEmail = provider.accountEmail
        model.accountRecordKey = provider.accountRecordKey
        model.loginMethod = provider.loginMethod
        model.statusMessage = provider.statusMessage
        model.isError = provider.isError
        model.lastUpdated = provider.lastUpdated
        model.subscriptionExpiresAt = provider.subscriptionExpiresAt
        model.subscriptionRenewsAt = provider.subscriptionRenewsAt
        model.providerPayloadData = providerPayloadData
        model.rateWindowsData = rateWindowsData
        model.costSummaryData = costSummaryData
        model.budgetData = budgetData
        model.perplexityCreditsData = perplexityCreditsData
        model.device = device

        try Self.upsertUtilization(
            history: provider.utilizationHistory ?? [],
            into: model,
            context: context)

        // Cost Window Ledger writer hook. The default-on flag lives in
        // `MobileSettingsKeys.cwlEnabled`. The blob path above always runs —
        // even with CWL on, the ledger and blob stay in sync (blob acts as the
        // authoritative current-window snapshot, ledger accumulates a longer
        // rolling history).
        // A wire tombstone is authoritative even while the optional ledger UI
        // is disabled. Otherwise stale rows survive and reappear if CWL is
        // enabled later. Contradictory payloads fail closed: clear wins over a
        // simultaneously supplied summary.
        if provider.costSummaryCleared == true {
            guard clearedHistoryWasMoved else { return }
            try CostLedgerService.deleteRows(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey,
                in: context, saveChanges: false)
        } else if CostLedgerService.isEnabled() {
            try CostLedgerService.upsertFromSnapshot(
                provider, deviceID: deviceID, in: context)
        }
    }

    private static func upsertUtilization(
        history: [SyncUtilizationSeries],
        into provider: ProviderSnapshotModel,
        context: ModelContext) throws
    {
        // Upstream utilization history is a rolling window on Mac (session cap 730 entries).
        // Entries that age out upstream must also be pruned locally, otherwise the mirror
        // grows forever and P2b @Query charts would show stale buckets. If the incoming
        // history is empty we clear everything on this provider. Flagged in Codex review (P2).
        guard !history.isEmpty else {
            for existing in provider.utilizationEntries {
                context.delete(existing)
            }
            return
        }

        // Index existing entries by (seriesName, capturedAt.timeIntervalSince1970)
        // for O(1) dedup. Using the Unix timestamp as the key avoids the
        // Date equality pitfalls around sub-microsecond rounding in SQLite.
        struct EntryKey: Hashable {
            let series: String
            let captured: TimeInterval
        }
        var existingByKey: [EntryKey: UtilizationEntryModel] = [:]
        for entry in provider.utilizationEntries {
            let key = EntryKey(series: entry.seriesName, captured: entry.capturedAt.timeIntervalSince1970)
            existingByKey[key] = entry
        }

        // Build the set of keys present in the incoming history — the eventual "kept" set.
        var incomingKeys: Set<EntryKey> = []
        for series in history {
            for entry in series.entries {
                let key = EntryKey(series: series.name, captured: entry.capturedAt.timeIntervalSince1970)
                incomingKeys.insert(key)
                if let existing = existingByKey[key] {
                    existing.usedPercent = entry.usedPercent
                    existing.resetsAt = entry.resetsAt
                    existing.windowMinutes = series.windowMinutes
                } else {
                    let model = UtilizationEntryModel(
                        seriesName: series.name,
                        capturedAt: entry.capturedAt,
                        usedPercent: entry.usedPercent,
                        resetsAt: entry.resetsAt,
                        windowMinutes: series.windowMinutes,
                        provider: provider)
                    context.insert(model)
                    existingByKey[key] = model
                }
            }
        }

        // Prune entries that existed locally but disappeared from the rolling-window
        // history upstream.
        for (key, existing) in existingByKey where !incomingKeys.contains(key) {
            context.delete(existing)
        }
    }

    // MARK: - Read (P3 · hydrate view state from SwiftData on cold start)

    /// Reconstruct `[SyncedUsageSnapshot]` — one per `DeviceRecord` — from the
    /// local SwiftData store. Used by `SyncedUsageData` at app launch to show
    /// the last-known merged state INSTANTLY, before the (slow) CloudKit fetch
    /// returns. Without this, cold-start shows KVS fallback (single device's
    /// partial data) and visibly jumps when CloudKit eventually lands.
    ///
    /// Returns `[]` when the store is empty (first launch on this device) —
    /// the caller should then fall back to KVS.
    static func readAllDeviceSnapshots(from context: ModelContext) throws -> [SyncedUsageSnapshot] {
        let deviceDescriptor = FetchDescriptor<DeviceRecord>(
            sortBy: [SortDescriptor(\.deviceID)])
        let devices = try context.fetch(deviceDescriptor)
        guard !devices.isEmpty else { return [] }

        let decoder = CloudSyncConstants.makeJSONDecoder()

        var snapshots: [SyncedUsageSnapshot] = []
        snapshots.reserveCapacity(devices.count)

        for device in devices {
            var providers: [ProviderUsageSnapshot] = []
            providers.reserveCapacity(device.providers.count)

            for row in device.providers {
                if let payload = row.providerPayloadData,
                   let provider = try? decoder.decode(ProviderUsageSnapshot.self, from: payload)
                {
                    providers.append(provider)
                    continue
                }

                let rateWindows = (try? decoder.decode([SyncRateWindow].self, from: row.rateWindowsData)) ?? []
                let costSummary = row.costSummaryData.flatMap {
                    try? decoder.decode(SyncCostSummary.self, from: $0)
                }
                let budget = row.budgetData.flatMap {
                    try? decoder.decode(SyncBudgetSnapshot.self, from: $0)
                }
                let perplexityCredits = row.perplexityCreditsData.flatMap {
                    try? decoder.decode(SyncPerplexityCreditSummary.self, from: $0)
                }

                // Reconstruct utilization history by grouping the flat entry rows
                // back into series. Sort by series name for stability, and by
                // `capturedAt` within each series so downstream `.last` semantics
                // (e.g. UtilizationHistoryView latest-capture lookups) match the
                // CloudKit shape.
                let grouped = Dictionary(grouping: row.utilizationEntries, by: { $0.seriesName })
                var seriesList: [SyncUtilizationSeries] = []
                seriesList.reserveCapacity(grouped.count)
                for (seriesName, entries) in grouped.sorted(by: { $0.key < $1.key }) {
                    let sortedEntries = entries.sorted(by: { $0.capturedAt < $1.capturedAt })
                    let windowMinutes = sortedEntries.first?.windowMinutes ?? 0
                    let syncEntries = sortedEntries.map {
                        SyncUtilizationEntry(
                            capturedAt: $0.capturedAt,
                            usedPercent: $0.usedPercent,
                            resetsAt: $0.resetsAt)
                    }
                    seriesList.append(SyncUtilizationSeries(
                        name: seriesName,
                        windowMinutes: windowMinutes,
                        entries: syncEntries))
                }

                providers.append(ProviderUsageSnapshot(
                    providerID: row.providerID,
                    providerName: row.providerName,
                    primary: nil,
                    secondary: nil,
                    accountEmail: row.accountEmail,
                    loginMethod: row.loginMethod,
                    statusMessage: row.statusMessage,
                    isError: row.isError,
                    lastUpdated: row.lastUpdated,
                    costSummary: costSummary,
                    budget: budget,
                    subscriptionExpiresAt: row.subscriptionExpiresAt,
                    subscriptionRenewsAt: row.subscriptionRenewsAt,
                    rateWindows: rateWindows,
                    utilizationHistory: seriesList.isEmpty ? nil : seriesList,
                    perplexityCredits: perplexityCredits,
                    accountRecordKey: row.accountRecordKey))
            }

            // Skip devices that have no provider rows — they're placeholders from
            // a partial upsert and would produce an empty snapshot that confuses
            // the merge layer.
            guard !providers.isEmpty else { continue }

            let publications = device.providerPublicationTimestampsData.flatMap {
                try? decoder.decode([String: Date].self, from: $0)
            } ?? [:]
            var quotaSources = device.providerQuotaSourcesData.flatMap {
                try? decoder.decode([String: SyncProviderQuotaSource].self, from: $0)
            } ?? [:]
            // Older caches stored a device-wide version from the newest sibling
            // envelope. It cannot prove that a Kimi clear came from a capable writer.
            for provider in providers where provider.providerID == "kimi" {
                let key = SyncedUsageSnapshot.providerPublicationKey(for: provider)
                if quotaSources[key] == nil {
                    quotaSources[key] = SyncProviderQuotaSource(
                        appVersion: nil,
                        publicationTimestamp: publications[key] ?? device.lastSyncAt,
                        deviceID: device.deviceID,
                        capturedAt: provider.lastUpdated,
                        isError: provider.isError)
                }
            }

            snapshots.append(SyncedUsageSnapshot(
                providers: providers,
                syncTimestamp: device.lastSyncAt,
                deviceName: device.deviceName,
                deviceID: device.deviceID.hasPrefix("legacy:") ? nil : device.deviceID,
                appVersion: device.appVersion,
                mobileVersion: nil,
                notificationPushEnabled: nil,
                providerPublicationTimestamps: publications,
                providerQuotaSources: quotaSources))
        }

        return snapshots
    }

    // MARK: - Provider record-name parsing

    private static func splitProviderRecordName(_ recordName: String) -> (
        deviceID: String,
        providerID: String,
        identityComponent: String?)?
    {
        let parts = recordName.split(
            separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let rawIdentity = String(parts[2])
        return (
            deviceID: String(parts[0]),
            providerID: String(parts[1]),
            identityComponent: rawIdentity == "_" ? nil : rawIdentity)
    }

    // MARK: - Fallbacks

    /// Deterministic synthetic deviceID for snapshots that arrive without one
    /// (KVS fallback path, or merged snapshots where the source IDs were
    /// collapsed). Using `deviceName` as the seed keeps per-name rows stable
    /// across relaunches while still distinguishing between devices.
    static func deviceIDFallback(for snapshot: SyncedUsageSnapshot) -> String {
        "legacy:" + snapshot.deviceName
    }

    // MARK: - Change-token persistence (v2 P6 re-introduction)

    //
    // v1 P6 (Build 59) stored the token here AND also wrote incremental
    // per-provider rows here via applyPerProviderDelta. The delta writer was
    // the source of the multi-device regression and has been removed. Only
    // token load/save remain — that's fine because tokens are scoped by
    // zoneName explicitly, no ambiguity with legacy data.

    /// Reads the persisted `CKServerChangeToken` for the named zone, if any.
    /// Returns `nil` on first-ever sync or after a token-expiry reset.
    static func loadChangeToken(
        forZone zoneName: String,
        from context: ModelContext) throws -> Data?
    {
        let descriptor = FetchDescriptor<SyncStateRecord>(
            predicate: #Predicate { $0.zoneName == zoneName })
        return try context.fetch(descriptor).first?.changeTokenData
    }

    /// Persists the server change token for `zoneName`. Pass `tokenData: nil`
    /// to clear (called after `.changeTokenExpired` so the next fetch is a
    /// full replay).
    static func saveChangeToken(
        forZone zoneName: String,
        tokenData: Data?,
        context: ModelContext,
        saveChanges: Bool = true) throws
    {
        let descriptor = FetchDescriptor<SyncStateRecord>(
            predicate: #Predicate { $0.zoneName == zoneName })
        if let existing = try context.fetch(descriptor).first {
            existing.changeTokenData = tokenData
            existing.lastSyncAt = Date()
        } else {
            context.insert(SyncStateRecord(
                zoneName: zoneName,
                changeTokenData: tokenData,
                lastSyncAt: Date()))
        }
        if saveChanges { try context.save() }
    }
}
