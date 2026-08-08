import CodexBarCore
import Foundation

extension Notification.Name {
    static let codexbarOpenSettings = Notification.Name("codexbarOpenSettings")
    static let codexbarDebugBlinkNow = Notification.Name("codexbarDebugBlinkNow")
    #if DEBUG
    static let codexbarDebugSimulateMemoryPressure =
        Notification.Name("com.steipete.codexbar.debug.simulateMemoryPressure")
    #endif
    static let codexbarSessionLimitReset = Notification.Name("codexbarSessionLimitReset")
    static let codexbarWeeklyLimitReset = Notification.Name("codexbarWeeklyLimitReset")
    static let codexbarProviderConfigDidChange = Notification.Name("codexbarProviderConfigDidChange")
    static let codexbarUsageSnapshotsDidChange = Notification.Name("codexbarUsageSnapshotsDidChange")
    static let codexbarQuotaWarningDidPost = Notification.Name("codexbarQuotaWarningDidPost")
}

final class UsageSnapshotsDidChangeEvent: NSObject, @unchecked Sendable {
    let snapshots: [AccountSnapshotSyncPayload]
    let authoritativeProviders: Set<UsageProvider>
    let providerConfigRevisions: [UsageProvider: UInt64]
    let tokenAccountIDsByRecordName: [String: UUID]

    init(
        snapshots: [AccountSnapshotSyncPayload],
        authoritativeProviders: Set<UsageProvider>,
        providerConfigRevisions: [UsageProvider: UInt64],
        tokenAccountIDsByRecordName: [String: UUID])
    {
        self.snapshots = snapshots
        self.authoritativeProviders = authoritativeProviders
        self.providerConfigRevisions = providerConfigRevisions
        self.tokenAccountIDsByRecordName = tokenAccountIDsByRecordName
    }
}

@MainActor
final class SessionLimitResetEvent: NSObject {
    let provider: UsageProvider
    let accountIdentifier: String
    let accountLabel: String?
    let usedPercent: Double

    init(provider: UsageProvider, accountIdentifier: String, accountLabel: String?, usedPercent: Double) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.accountLabel = accountLabel
        self.usedPercent = usedPercent
    }
}

@MainActor
final class WeeklyLimitResetEvent: NSObject {
    let provider: UsageProvider
    let accountIdentifier: String
    let accountLabel: String?
    let usedPercent: Double

    init(provider: UsageProvider, accountIdentifier: String, accountLabel: String?, usedPercent: Double) {
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.accountLabel = accountLabel
        self.usedPercent = usedPercent
    }
}

@MainActor
final class QuotaWarningPostedEvent: NSObject {
    let provider: UsageProvider
    let window: QuotaWarningWindow
    let threshold: Int
    let postedAt: Date

    init(provider: UsageProvider, window: QuotaWarningWindow, threshold: Int, postedAt: Date) {
        self.provider = provider
        self.window = window
        self.threshold = threshold
        self.postedAt = postedAt
    }
}
