import CloudKit
import CodexBarSync
import Foundation
import Observation

/// Minimal diagnostic store for the alert-push subscription setup.
/// Stores the result of each setup attempt so the user can see it in
/// Settings → Developer Tools without needing Xcode Console.
@Observable
@MainActor
final class PushSetupDiagnostic {
    static let shared = PushSetupDiagnostic()

    private(set) var zoneStatus: String = "pending"
    private(set) var depletedSubStatus: String = "pending"
    private(set) var restoredSubStatus: String = "pending"
    private(set) var notificationPermission: String = "pending"
    private(set) var remoteRegistration: String = "pending"
    private(set) var subscriptionList: String = "pending"
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?

    private init() {}

    func recordZone(_ status: String) {
        self.zoneStatus = status
        self.lastUpdated = Date()
    }

    func recordDepletedSub(_ status: String) {
        self.depletedSubStatus = status
        self.lastUpdated = Date()
    }

    func recordRestoredSub(_ status: String) {
        self.restoredSubStatus = status
        self.lastUpdated = Date()
    }

    func recordPermission(_ status: String) {
        self.notificationPermission = status
        self.lastUpdated = Date()
    }

    func recordRegistration(_ status: String) {
        self.remoteRegistration = status
        self.lastUpdated = Date()
    }

    func recordError(_ error: String) {
        self.lastError = error
        self.lastUpdated = Date()
    }

    /// Queries CloudKit for the actual subscription list from THIS app's perspective.
    ///
    /// Since iOS 1.13.0 the app registers 159 quota push subscriptions (one per
    /// `(provider, depleted/restored/warning)` pair) — printing them one by one
    /// drowns the real info. We group by subscription-ID pattern and show
    /// counts + a sample `alertBody` per group, so the output stays concise
    /// while still letting a reader spot whether a specific group is missing /
    /// has drifted text.
    func refreshSubscriptionList() async {
        let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        // Must match QuotaTransitionSubscriptions which uses privateCloudDatabase
        let db = container.privateCloudDatabase
        do {
            let subs = try await db.allSubscriptions()
            self.subscriptionList = Self.formatSubscriptions(subs)
        } catch {
            self.subscriptionList = "ERROR: \(error.localizedDescription)"
        }
        self.lastUpdated = Date()
    }

    /// Groups subscriptions by ID pattern and returns a compact human-readable
    /// summary. Pure function — no CloudKit calls — so it can be unit tested
    /// without mocks.
    nonisolated static func formatSubscriptions(_ subs: [CKSubscription]) -> String {
        guard !subs.isEmpty else { return "0 subscriptions" }

        var depleted: [CKSubscription] = []
        var restored: [CKSubscription] = []
        var warning: [CKSubscription] = []
        var deviceSnapshot: [CKSubscription] = []
        var legacy: [CKSubscription] = []
        var other: [CKSubscription] = []

        for sub in subs {
            let id = sub.subscriptionID
            if id.hasPrefix("quota-"), id.hasSuffix("-depleted-sub") {
                depleted.append(sub)
            } else if id.hasPrefix("quota-"), id.hasSuffix("-restored-sub") {
                restored.append(sub)
            } else if id.hasPrefix("quota-"), id.hasSuffix("-warning-sub") {
                warning.append(sub)
            } else if id == "device-snapshot-changes" {
                deviceSnapshot.append(sub)
            } else if id.hasPrefix("quota-transition") {
                // Build 42–53 legacy subs that should have been deleted on
                // upgrade. Seeing these means setupIfNeeded didn't finish.
                legacy.append(sub)
            } else {
                other.append(sub)
            }
        }

        var lines: [String] = ["\(subs.count) subscription(s):"]
        Self.appendGroup(
            label: "device-snapshot-changes",
            subs: deviceSnapshot, to: &lines)
        Self.appendGroup(
            label: "quota-*-depleted-sub",
            subs: depleted, to: &lines)
        Self.appendGroup(
            label: "quota-*-restored-sub",
            subs: restored, to: &lines)
        Self.appendGroup(
            label: "quota-*-warning-sub",
            subs: warning, to: &lines)
        if !legacy.isEmpty {
            Self.appendGroup(
                label: "quota-transition-* (LEGACY — should be 0)",
                subs: legacy, to: &lines)
        }
        if !other.isEmpty {
            Self.appendGroup(label: "other", subs: other, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    /// Appends one line per group with `count × label` and a sample `alertBody`
    /// / type info. Skips the group entirely if it's empty.
    private nonisolated static func appendGroup(
        label: String, subs: [CKSubscription], to lines: inout [String])
    {
        guard !subs.isEmpty else { return }
        var line = "  • \(subs.count) × \(label)"
        if let first = subs.first {
            let typeName = String(describing: type(of: first))
                .replacingOccurrences(of: "CKRecord", with: "Record")
                .replacingOccurrences(of: "Subscription", with: "Sub")
            line += " [\(typeName)"
            if let body = first.notificationInfo?.alertBody, !body.isEmpty {
                let trimmed = body.count > 40
                    ? body.prefix(37) + "…"
                    : body[...]
                line += " body=\"\(trimmed)\""
            }
            line += "]"
        }
        lines.append(line)
    }
}
