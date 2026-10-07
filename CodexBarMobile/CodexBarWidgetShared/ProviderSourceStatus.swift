import CodexBarSync
import Foundation

/// Where a merged provider card's data came from, and which other Macs failed more recently.
///
/// Every Mac publishes its own result for a provider. When one Mac cannot refresh (for example
/// it has no browser session for the provider) while another Mac still has real data, the card
/// keeps the real data; this status tells the user which Mac it came from, how old it is, and
/// which Mac reported a newer failure.
struct ProviderSourceStatus: Equatable {
    struct Failure: Equatable {
        let deviceName: String
        let reportedAt: Date
        let message: String?
    }

    /// Data older than this is called out even without a newer failure.
    static let staleInterval: TimeInterval = 6 * 3600

    /// Mac whose observation the card shows; nil when every Mac failed.
    let sourceDeviceName: String?
    let sourceCapturedAt: Date?
    /// Failures from other Macs reported after the shown data was captured, newest first.
    let newerFailures: [Failure]
    /// True when no Mac has any data for this account, only failures.
    let allFailed: Bool

    func isStale(at now: Date) -> Bool {
        guard let sourceCapturedAt else { return false }
        return now.timeIntervalSince(sourceCapturedAt) > Self.staleInterval
    }

    /// Whether the detail page should explain the source. Single-Mac, fresh, successful data needs no note.
    func needsNotice(at now: Date) -> Bool {
        self.allFailed || !self.newerFailures.isEmpty || self.isStale(at: now)
    }

    /// Resolve the status of one merged provider from the per-device snapshots that produced it.
    /// Returns nil when no device entry for this account can be found (e.g. demo data).
    static func resolve(
        provider: ProviderUsageSnapshot,
        deviceSnapshots: [SyncedUsageSnapshot]) -> ProviderSourceStatus?
    {
        let mergedIdentifiers = Set(ProviderSnapshotMerger.effectiveIdentifiers(for: provider))
        let legacyIdentifier = "\(provider.providerID):legacy-no-identity"
        var observations: [(deviceName: String, deviceKey: String, capturedAt: Date)] = []
        var failures: [(deviceKey: String, failure: Failure)] = []
        for snapshot in deviceSnapshots {
            let deviceKey = snapshot.deviceID ?? "legacy:\(snapshot.deviceName)"
            for entry in snapshot.providers where entry.providerID == provider.providerID {
                // An error is current as of its publication. Legacy records without per-provider
                // publication metadata fall back to the device's sync time, not the data's age.
                let reportedAt = snapshot.providerPublicationTimestamps[
                    SyncedUsageSnapshot.providerPublicationKey(for: entry)] ?? snapshot.syncTimestamp
                let identifiers = ProviderSnapshotMerger.effectiveIdentifiers(for: entry)
                let failureOnly = ProviderSnapshotMerger.isFailureOnly(entry)
                // Identity-less failures are folded into the observed account by the merger.
                let belongs = !mergedIdentifiers.isDisjoint(with: identifiers)
                    || (failureOnly && identifiers == [legacyIdentifier])
                guard belongs else { continue }
                if failureOnly {
                    failures.append((deviceKey, Failure(
                        deviceName: snapshot.deviceName,
                        reportedAt: reportedAt,
                        message: entry.statusMessage)))
                } else {
                    observations.append((snapshot.deviceName, deviceKey, entry.lastUpdated))
                    if entry.isError {
                        // Data kept from an earlier refresh plus a current error on that Mac.
                        failures.append((deviceKey, Failure(
                            deviceName: snapshot.deviceName,
                            reportedAt: reportedAt,
                            message: entry.statusMessage)))
                    }
                }
            }
        }
        guard !observations.isEmpty || !failures.isEmpty else { return nil }
        let source = observations.max { lhs, rhs in
            lhs.capturedAt == rhs.capturedAt ? lhs.deviceKey < rhs.deviceKey : lhs.capturedAt < rhs.capturedAt
        }
        let newer = failures
            .filter { failure in
                guard let source else { return true }
                return failure.deviceKey != source.deviceKey && failure.failure.reportedAt > source.capturedAt
            }
            .map(\.failure)
            .sorted { $0.reportedAt > $1.reportedAt }
        return ProviderSourceStatus(
            sourceDeviceName: source?.deviceName,
            sourceCapturedAt: source?.capturedAt,
            newerFailures: newer,
            allFailed: source == nil)
    }
}
