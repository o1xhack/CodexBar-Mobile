import CodexBarSync
import Foundation

/// UI view of a merged card's source report: which Mac supplied the data, how old it is, and which
/// Macs currently fail to refresh. The merger computes the report while grouping, so it always
/// describes exactly the entries that formed the card.
struct ProviderSourceStatus: Equatable {
    /// Data older than this is called out even without a newer failure.
    static let staleInterval: TimeInterval = 6 * 3600

    let report: SyncProviderSourceReport

    var sourceDeviceName: String? {
        self.report.sourceDeviceName
    }

    var sourceCapturedAt: Date? {
        self.report.sourceCapturedAt
    }

    /// Each listed failure is that Mac's latest state, newest first.
    var failures: [SyncProviderSourceReport.Failure] {
        self.report.failures
    }

    /// The shown data comes from a Mac other than one that is failing.
    var showsDataFromAnotherMac: Bool {
        guard let sourceDeviceID = self.report.sourceDeviceID else { return false }
        return self.failures.contains { $0.deviceID != sourceDeviceID }
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

    func isStale(at now: Date) -> Bool {
        guard let sourceCapturedAt else { return false }
        return now.timeIntervalSince(sourceCapturedAt) > Self.staleInterval
    }

    /// A single Mac's own failure is already shown by the card; the notice adds value when several
    /// Macs are involved or the shown data is old.
    func needsNotice(at now: Date) -> Bool {
        if self.allFailed { return self.report.deviceCount >= 2 }
        return !self.failures.isEmpty || self.isStale(at: now)
    }

    /// Failures make the notice a warning; old data alone is informational.
    var isWarning: Bool {
        self.allFailed || !self.failures.isEmpty
    }
}
