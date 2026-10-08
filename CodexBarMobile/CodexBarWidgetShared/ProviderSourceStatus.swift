import CodexBarSync
import Foundation

/// UI view of a merged card's source report: which Mac supplied the data, how old it is, and which
/// Macs currently fail to refresh. The merger computes the report while grouping, so it always
/// describes exactly the entries that formed the card.
struct ProviderSourceStatus: Equatable {
    /// Data older than this is called out even without a failure.
    static let staleInterval: TimeInterval = 6 * 3600
    /// A failing Mac that has not synced at all for this long is treated as no longer in use.
    static let inactiveDeviceInterval: TimeInterval = 7 * 86400

    let report: SyncProviderSourceReport

    var sourceDeviceName: String? {
        self.report.sourceDeviceName
    }

    var sourceCapturedAt: Date? {
        self.report.sourceCapturedAt
    }

    var allFailed: Bool {
        self.report.allFailed
    }

    init(report: SyncProviderSourceReport) {
        self.report = report
    }

    static func resolve(provider: ProviderUsageSnapshot) -> ProviderSourceStatus? {
        provider.sourceReport.map(ProviderSourceStatus.init(report:))
    }

    /// Each failure is that Mac's latest state, newest first. Macs that stopped syncing are left out
    /// (the user can archive them in Settings) so a retired Mac cannot keep a notice up forever.
    func failures(at now: Date) -> [SyncProviderSourceReport.Failure] {
        self.report.failures.filter { failure in
            guard let syncedAt = failure.deviceSyncedAt else { return true }
            return now.timeIntervalSince(syncedAt) <= Self.inactiveDeviceInterval
        }
    }

    /// Failures that are real errors; the rest are Macs explaining why they have no data.
    func errors(at now: Date) -> [SyncProviderSourceReport.Failure] {
        self.failures(at: now).filter { $0.isError != false }
    }

    /// The shown data comes from a Mac other than one that is failing.
    func showsDataFromAnotherMac(at now: Date) -> Bool {
        guard let sourceDeviceID = self.report.sourceDeviceID else { return false }
        return self.failures(at: now).contains { $0.deviceID != sourceDeviceID }
    }

    func isStale(at now: Date) -> Bool {
        guard let sourceCapturedAt else { return false }
        return now.timeIntervalSince(sourceCapturedAt) > Self.staleInterval
    }

    /// A single Mac's own failure is already shown by the card; the notice adds value when several
    /// Macs are involved or the shown data is old.
    func needsNotice(at now: Date) -> Bool {
        // No observation anywhere is news only when a Mac failed or explained it; providers that
        // legitimately publish no quota (cost-only) stay quiet.
        if self.allFailed { return self.report.deviceCount >= 2 && !self.failures(at: now).isEmpty }
        return !self.failures(at: now).isEmpty || self.isStale(at: now)
    }

    /// Fresh data from another Mac is informational even while one Mac keeps failing (for example
    /// a provider never signed in there); old data next to a failure, or no data at all, is a warning.
    func isWarning(at now: Date) -> Bool {
        !self.errors(at: now).isEmpty && (self.allFailed || self.isStale(at: now))
    }
}
