import CodexBarSync
import Foundation

/// UI view of a merged card's source report: which Mac supplied the data, how old it is, and which
/// Macs failed to refresh more recently. The merger computes the report while grouping, so it always
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

    var newerFailures: [SyncProviderSourceReport.Failure] {
        self.report.failures
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
        return !self.newerFailures.isEmpty || self.isStale(at: now)
    }

    /// Newer failures make the notice a warning; old data alone is informational.
    var isWarning: Bool {
        self.allFailed || !self.newerFailures.isEmpty
    }
}
