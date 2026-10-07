import CodexBarSync
import Foundation
import SwiftData

struct CostHistoryPresentation: Sendable {
    let scope: String
    let insights: CostDashboardInsights?
}

struct CostHistoryRequest: Sendable {
    let snapshot: SyncedUsageSnapshot
    let sourceSnapshots: [SyncedUsageSnapshot]
    let activeDeviceIDs: Set<String>?
    let windowDays: Int
    let useLedger: Bool
    let isDemoMode: Bool
    let clearTombstone: Date?
}

/// Owns its ModelContext on the actor executor. No SwiftData models cross back
/// to SwiftUI, and cancellation prevents obsolete queued requests doing work.
actor CostHistoryWorker {
    static let shared = CostHistoryWorker(container: ModelContainerFactory.shared())
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(self.container)
        context.autosaveEnabled = false
        return context
    }

    func loadToken(zoneName: String) throws -> Data? {
        try SwiftDataBridge.loadChangeToken(
            forZone: zoneName,
            from: self.makeContext())
    }

    func resetToken(zoneName: String) throws {
        try SwiftDataBridge.saveChangeToken(
            forZone: zoneName,
            tokenData: nil,
            context: self.makeContext())
    }

    func persistFull(_ snapshots: [SyncedUsageSnapshot]) throws {
        try Task.checkCancellation()
        let context = self.makeContext()
        do {
            try SwiftDataBridge.upsert(
                deviceSnapshots: snapshots,
                into: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func persistIncremental(
        snapshots: [SyncedUsageSnapshot],
        deletedRecordNames: [String],
        replacingAllDevices: Bool,
        zoneName: String,
        tokenData: Data?) throws
    {
        try Task.checkCancellation()
        try SwiftDataBridge.commitIncrementalBatch(
            snapshots: snapshots,
            deletedRecordNames: deletedRecordNames,
            replacingAllDevices: replacingAllDevices,
            zoneName: zoneName,
            tokenData: tokenData,
            in: self.makeContext())
    }

    func clear(persistentStorageAvailable: Bool) throws {
        try CostLedgerService.clearAll(
            in: self.makeContext(),
            persistentStorageAvailable: persistentStorageAvailable)
    }

    func diagnostics(seed: Bool) throws -> CostLedgerDiagnostics {
        try Task.checkCancellation()
        let context = self.makeContext()
        if seed { try CostLedgerService.seedFromExistingBlobsRespectingClearTombstone(in: context) }
        return try CostLedgerService.diagnostics(in: context)
    }

    func aggregate(
        windowDays: Int,
        activeDeviceIDs: Set<String>?,
        sourceSnapshots: [SyncedUsageSnapshot],
        accountLinks: [CostLedgerAccountLink] = []) throws -> CostLedgerAggregation
    {
        try Task.checkCancellation()
        return try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: windowDays,
            in: self.makeContext(),
            activeDeviceIDs: activeDeviceIDs,
            sourceSnapshots: sourceSnapshots,
            accountLinks: accountLinks)
    }

    func snapshotTokenActivity(
        providers: [ProviderUsageSnapshot], referenceDate: Date) throws -> [TokenActivitySeries]
    {
        try Task.checkCancellation()
        return TokenActivity.series(providers: providers, rollups: nil, referenceDate: referenceDate)
    }

    func tokenActivity(
        providers: [ProviderUsageSnapshot],
        sourceSnapshots: [SyncedUsageSnapshot],
        referenceDate: Date = Date()) throws -> [TokenActivitySeries]
    {
        try Task.checkCancellation()
        let aggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 365,
            in: self.makeContext(),
            asOf: referenceDate,
            activeDeviceIDs: CostLedgerDeviceFilter.activeDeviceIDs(for: sourceSnapshots),
            sourceSnapshots: sourceSnapshots,
            accountLinks: CostLedgerService.accountLinks(for: providers))
        try Task.checkCancellation()
        return TokenActivity.series(providers: providers, rollups: aggregation.sortedProviderRollups)
    }

    func load(_ request: CostHistoryRequest) throws -> CostDashboardInsights? {
        try Task.checkCancellation()
        let aggregation: CostLedgerAggregation?
        if request.useLedger {
            let context = self.makeContext()
            aggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
                windowDays: request.windowDays,
                in: context,
                activeDeviceIDs: request.activeDeviceIDs,
                sourceSnapshots: request.sourceSnapshots,
                accountLinks: CostLedgerService.accountLinks(for: request.snapshot.providers))
        } else {
            aggregation = nil
        }
        try Task.checkCancellation()
        let insights = CostTabInsightsResolver.make(
            snapshot: request.snapshot,
            ledgerAggregation: aggregation,
            isLedgerEnabled: request.useLedger,
            isDemoMode: request.isDemoMode,
            localHistoryClearedAt: request.clearTombstone,
            ledgerWindowDays: request.windowDays)
        try Task.checkCancellation()
        return insights
    }
}
