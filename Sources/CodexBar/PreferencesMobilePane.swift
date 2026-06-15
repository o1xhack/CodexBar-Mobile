import CloudKit
import CodexBarCore
import CodexBarSync
import SwiftUI

@MainActor
struct MobilePane: View {
    @Bindable var settings: SettingsStore
    let syncCoordinator: SyncCoordinator

    /// True when running in development mode. Checks:
    /// 1. Debug bundle ID (.debug suffix)
    /// 2. CODEXBAR_DEV=1 environment variable
    /// 3. Debug menu enabled in Settings → Advanced
    private var isDevelopmentBuild: Bool {
        Bundle.main.bundleIdentifier?.contains(".debug") == true
            || ProcessInfo.processInfo.environment["CODEXBAR_DEV"] == "1"
            || self.settings.debugMenuEnabled
    }

    @State private var lastTestResult: String?

    /// Mock provider toggle. Bound to UserDefaults key
    /// `CodexBarMockProvidersEnabled` so the same flag toggles whether
    /// `MockProviderInjector` injects 8 synthetic snapshots into every
    /// sync cycle. Visible in Settings whenever `iCloudSyncEnabled` is
    /// on so QA can flip the switch and immediately see iPhone behavior.
    @AppStorage("CodexBarMockProvidersEnabled")
    private var mockProvidersEnabled: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                // iCloud Sync
                SettingsSection(contentSpacing: 12) {
                    Text(L("mobile_section_icloud_sync"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    PreferenceToggleRow(
                        title: L("mobile_toggle_sync_title"),
                        subtitle: L("mobile_toggle_sync_subtitle"),
                        binding: self.$settings.iCloudSyncEnabled)

                    if self.settings.iCloudSyncEnabled {
                        self.syncStatusView
                    }
                }

                Divider()

                // iOS Push Notifications (independent of Mac local notifications)
                SettingsSection(contentSpacing: 12) {
                    Text(L("mobile_section_push"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    PreferenceToggleRow(
                        title: L("mobile_toggle_push_title"),
                        subtitle: L("mobile_toggle_push_subtitle"),
                        binding: self.$settings.notificationPushToiOSEnabled)
                }

                // Mock Provider Data section is gated behind the
                // CODEXBAR_MOCK_PROVIDERS env var — normal launches
                // (Finder / Dock / login item) never see it. Only when
                // Mac is launched with the env var set does the
                // section render. This preserves a clean Settings pane
                // for end users while making the toggle reachable
                // during debug sessions.
                if MockProviderInjector.isMockToolingVisible {
                    Divider()
                    self.mockProviderSection
                }

                if self.isDevelopmentBuild {
                    Divider()
                    self.devTestSection
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Mock Provider Data (env-var gated; invisible to normal users)

    /// Reference list of all 8 mocks the injector emits when active.
    /// Hardcoded here so the Settings UI can show side-by-side
    /// "what should appear on my iPhone" vs. what actually appears.
    /// Kept in sync with `MockProviderInjector` mocks (see Mac 0.23.6+
    /// docstring there for the mix design rationale).
    private struct MockReferenceCard: Identifiable {
        let id: String
        let displayName: String
        let subtitle: String
        let badge: String
    }

    private static let mockReference: [MockReferenceCard] = [
        MockReferenceCard(
            id: "codex|alice",
            displayName: "Codex (Alice · Mock)",
            subtitle: "café-mock@codex.test · 35% / 60%",
            badge: "first-class"),
        MockReferenceCard(
            id: "codex|bob",
            displayName: "Codex (Bob · Mock)",
            subtitle: "bob-mock@codex.test · 75% / 100%",
            badge: "first-class"),
        MockReferenceCard(
            id: "codex|carol",
            displayName: "Codex (Carol · Mock)",
            subtitle: "carol-mock@codex.test · 0% / 12%",
            badge: "first-class"),
        MockReferenceCard(
            id: "claude|personal",
            displayName: "Claude (Personal · Mock)",
            subtitle: "personal-mock@claude.test · 5h+Sonnet+Opus",
            badge: "first-class"),
        MockReferenceCard(
            id: "claude|work",
            displayName: "Claude (Work · Mock)",
            subtitle: "work-mock@claude.test · 5h+Sonnet",
            badge: "first-class"),
        MockReferenceCard(
            id: "perplexity|pro",
            displayName: "Perplexity (Pro · Mock)",
            subtitle: "pro-mock@perplexity.test · $410 credits",
            badge: "first-class"),
        MockReferenceCard(
            id: "_mock_cursor_unknown",
            displayName: "Cursor (Cookie expired · Mock)",
            subtitle: "expired-mock@cursor.test · isError=true",
            badge: "fallback"),
        MockReferenceCard(
            id: "_mock_synthetic_unknown",
            displayName: "Synthetic (3-lane fallback · Mock)",
            subtitle: "lanes-mock@synthetic.test · 30-day history",
            badge: "fallback"),
    ]

    private var mockProviderSection: some View {
        SettingsSection(contentSpacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "testtube.2")
                    .foregroundStyle(.purple)
                    .font(.caption)
                Text(L("mobile_section_mock_data"))
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .textCase(.uppercase)
            }

            PreferenceToggleRow(
                title: L("mobile_toggle_mock_title"),
                subtitle: L("mobile_toggle_mock_subtitle"),
                binding: self.$mockProvidersEnabled)

            if self.mockProvidersEnabled {
                Divider()
                Text(L("mobile_mock_reference_header"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Self.mockReference) { card in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(card.badge == "first-class" ? "●" : "◌")
                                .font(.caption2.monospaced())
                                .foregroundStyle(
                                    card.badge == "first-class"
                                        ? Color.green
                                        : Color.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.displayName)
                                    .font(.caption)
                                Text(card.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(L("mobile_mock_cost_note"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - DEV Test

    private var devTestSection: some View {
        SettingsSection(contentSpacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(L("mobile_section_dev_test"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
            }

            Text(L("mobile_dev_test_intro"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            // Codex
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex").font(.caption.bold())
                HStack(spacing: 12) {
                    Button {
                        self.runTestPush(provider: "Codex", providerID: "codex", state: "depleted")
                    } label: {
                        Label(L("mobile_dev_depleted"), systemImage: "bell.badge")
                    }
                    .controlSize(.small)
                    Button {
                        self.runTestPush(provider: "Codex", providerID: "codex", state: "restored")
                    } label: {
                        Label(L("mobile_dev_restored"), systemImage: "bell")
                    }
                    .controlSize(.small)
                    self.warningMenu(provider: "Codex", providerID: "codex")
                }
            }
            .disabled(!self.settings.notificationPushToiOSEnabled)

            // Claude
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude").font(.caption.bold())
                HStack(spacing: 12) {
                    Button {
                        self.runTestPush(provider: "Claude", providerID: "claude", state: "depleted")
                    } label: {
                        Label(L("mobile_dev_depleted"), systemImage: "bell.badge")
                    }
                    .controlSize(.small)
                    Button {
                        self.runTestPush(provider: "Claude", providerID: "claude", state: "restored")
                    } label: {
                        Label(L("mobile_dev_restored"), systemImage: "bell")
                    }
                    .controlSize(.small)
                    self.warningMenu(provider: "Claude", providerID: "claude")
                }
            }
            .disabled(!self.settings.notificationPushToiOSEnabled)

            Button {
                self.runBurstWarningTest()
            } label: {
                Label("Burst Test (5×)", systemImage: "bolt.fill")
            }
            .controlSize(.small)
            .disabled(!self.settings.notificationPushToiOSEnabled)

            Button {
                self.dumpIOSNSELog()
            } label: {
                Label("Dump iOS NSE Log", systemImage: "doc.text")
            }
            .controlSize(.small)

            Button {
                self.verifyPushSetup()
            } label: {
                Label(L("mobile_dev_verify_push"), systemImage: "checklist")
            }
            .controlSize(.small)

            if let lastTestResult {
                Text(lastTestResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verifyPushSetup() {
        self.lastTestResult = "Querying CloudKit…"
        Task {
            let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
            var lines = ["=== Verify Push Setup ==="]

            // 1. List subscriptions on BOTH databases
            for (label, db) in [
                ("Private", container.privateCloudDatabase),
                ("Public", container.publicCloudDatabase),
            ] {
                do {
                    let subs = try await db.allSubscriptions()
                    lines.append("\(label) DB Subscriptions: \(subs.count)")
                    for sub in subs {
                        var desc = "  [\(sub.subscriptionID)] \(type(of: sub))"
                        if let q = sub as? CKQuerySubscription {
                            desc += " rt=\(q.recordType ?? "nil") zone=\(q.zoneID?.zoneName ?? "default")"
                            desc += " pred=\(q.predicate.predicateFormat)"
                        }
                        if let info = sub.notificationInfo {
                            desc += " alert=\(info.alertBody ?? "nil") sound=\(info.soundName ?? "nil")"
                            desc += " mutableContent=\(info.shouldSendMutableContent)"
                        }
                        lines.append(desc)
                    }
                } catch {
                    lines.append("\(label) DB Subscriptions ERROR: \(error.localizedDescription)")
                }
            }

            // 2. Query QuotaTransition records on PUBLIC DB (where build 46+ writes)
            let publicDB = container.publicCloudDatabase
            do {
                let query = CKQuery(
                    recordType: CloudSyncConstants.quotaTransitionRecordType,
                    predicate: NSPredicate(value: true))
                let (results, _) = try await publicDB.records(matching: query)
                lines.append("Public DB QuotaTransition records: \(results.count)")
                for (id, result) in results {
                    switch result {
                    case let .success(record):
                        let prov = (record["providerName"] as? String) ?? "?"
                        let st = (record["state"] as? String) ?? "?"
                        lines.append("  \(id.recordName): \(prov) \(st)")
                    case let .failure(err):
                        lines.append("  \(id.recordName): ERROR \(err.localizedDescription)")
                    }
                }
            } catch {
                lines.append("Public DB QuotaTransition ERROR: \(error.localizedDescription)")
            }

            // Old: also show private DB custom zone records for reference
            let privateDB = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: CloudSyncConstants.customZoneName,
                ownerName: CKCurrentUserDefaultName)
            do {
                let query = CKQuery(
                    recordType: CloudSyncConstants.quotaTransitionRecordType,
                    predicate: NSPredicate(value: true))
                let (results, _) = try await privateDB.records(
                    matching: query, inZoneWith: zoneID)
                lines.append("Private DB (custom zone) QuotaTransition records: \(results.count)")
            } catch {
                lines.append("Private DB QuotaTransition: \(error.localizedDescription)")
            }

            // 3. Try to create a test subscription on PUBLIC DB to surface errors
            let db = container.publicCloudDatabase
            lines.append("")
            // --- Test A: CKQuerySubscription persistence ---
            lines.append("")
            lines.append("--- Test A: CKQuerySubscription persistence ---")
            let testQuerySubID = "mac-test-query-sub"
            defer { Task { try? await db.deleteSubscription(withID: testQuerySubID) } }
            do {
                _ = try? await db.deleteSubscription(withID: testQuerySubID)
                let sub = CKQuerySubscription(
                    recordType: CloudSyncConstants.quotaTransitionRecordType,
                    predicate: NSPredicate(format: "state == %@", "depleted"),
                    subscriptionID: testQuerySubID,
                    options: [.firesOnRecordCreation])
                let info = CKSubscription.NotificationInfo()
                info.alertBody = "Test"
                info.soundName = "default"
                sub.notificationInfo = info
                _ = try await db.modifySubscriptions(saving: [sub], deleting: [])
                lines.append("  save: ✓")

                // NOW check if it actually persisted
                let allSubs = try await db.allSubscriptions()
                let found = allSubs.first(where: { $0.subscriptionID == testQuerySubID })
                if found != nil {
                    lines.append("  allSubscriptions: ✓ FOUND — CKQuerySubscription persists!")
                } else {
                    lines.append("  allSubscriptions: ✗ NOT FOUND — save succeeded but didn't persist")
                    lines.append("  (total subs: \(allSubs.count))")
                }
            } catch {
                lines.append("  ✗ Error: \(error.localizedDescription)")
            }

            // --- Test B: CKRecordZoneSubscription persistence (on private DB) ---
            lines.append("")
            lines.append("--- Test B: CKRecordZoneSubscription persistence ---")
            let testZoneSubID = "mac-test-zone-sub"
            defer { Task { try? await container.privateCloudDatabase.deleteSubscription(withID: testZoneSubID) } }
            let privDB = container.privateCloudDatabase
            let testZoneID = CKRecordZone.ID(
                zoneName: CloudSyncConstants.quotaTransitionsZoneName,
                ownerName: CKCurrentUserDefaultName)
            do {
                // Ensure zone exists before creating a zone subscription
                do {
                    _ = try await privDB.recordZone(for: testZoneID)
                } catch let ckErr as CKError where ckErr.code == .zoneNotFound {
                    _ = try await privDB.modifyRecordZones(
                        saving: [CKRecordZone(zoneID: testZoneID)], deleting: [])
                }
                _ = try? await privDB.deleteSubscription(withID: testZoneSubID)
                let sub = CKRecordZoneSubscription(
                    zoneID: testZoneID, subscriptionID: testZoneSubID)
                let info = CKSubscription.NotificationInfo()
                info.alertBody = "Test zone"
                info.soundName = "default"
                sub.notificationInfo = info
                _ = try await privDB.modifySubscriptions(saving: [sub], deleting: [])
                lines.append("  save: ✓")

                let allSubs = try await privDB.allSubscriptions()
                let found = allSubs.first(where: { $0.subscriptionID == testZoneSubID })
                if found != nil {
                    lines.append("  allSubscriptions: ✓ FOUND — CKRecordZoneSubscription persists!")
                } else {
                    lines.append("  allSubscriptions: ✗ NOT FOUND")
                    lines.append("  (total subs: \(allSubs.count))")
                }
            } catch {
                lines.append("  ✗ Error: \(error.localizedDescription)")
            }

            self.lastTestResult = lines.joined(separator: "\n")
        }
    }

    private func runTestPush(provider: String, providerID: String, state: String) {
        self.lastTestResult = "Writing \(provider) \(state)…"
        Task {
            let result = await CloudSyncManager.shared.writeQuotaTransition(
                providerName: provider,
                providerID: providerID,
                state: state,
                transitionAt: Date())
            if result.succeeded {
                self.lastTestResult = "✓ Wrote \(state) record at \(self.shortTime()). " +
                    "Check iPhone for push within ~10s."
            } else {
                self.lastTestResult = "✗ Write failed: \(result.message ?? "unknown")"
            }
        }
    }

    private func warningMenu(provider: String, providerID: String) -> some View {
        Menu {
            ForEach(["session", "weekly"], id: \.self) { window in
                Section(window.capitalized) {
                    ForEach([50, 20, 10], id: \.self) { threshold in
                        Button("\(threshold)%") {
                            self.runTestWarningPush(
                                provider: provider,
                                providerID: providerID,
                                window: window,
                                threshold: threshold)
                        }
                    }
                }
            }
        } label: {
            Label(L("mobile_dev_warning"), systemImage: "exclamationmark.triangle")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
    }

    /// Rolling history of the most recent push-test outcomes so the user
    /// can read all clicks in one glance, instead of `lastTestResult`
    /// being overwritten by every press.
    private func appendTestResult(_ line: String) {
        let max = 15
        var lines = (self.lastTestResult ?? "").split(separator: "\n\n", omittingEmptySubsequences: true)
            .map(String.init)
        lines.append(line)
        if lines.count > max {
            lines.removeFirst(lines.count - max)
        }
        self.lastTestResult = lines.joined(separator: "\n\n")
    }

    private func updateTestResultLast(_ line: String) {
        // Replace just the last entry instead of appending — used to
        // upgrade a "writing…" placeholder into a final ✓/✗ outcome.
        var lines = (self.lastTestResult ?? "").split(separator: "\n\n", omittingEmptySubsequences: true)
            .map(String.init)
        if lines.isEmpty {
            lines.append(line)
        } else {
            lines[lines.count - 1] = line
        }
        self.lastTestResult = lines.joined(separator: "\n\n")
    }

    /// Reads the iOS NSE invocation log from the shared `NSUbiquitousKeyValueStore`
    /// (key `NSEInvocationLog.entries`, written by `CodexBarMobilePushExtension`)
    /// and dumps every entry as plain text into `lastTestResult` so the user can
    /// copy from the Mac UI without hopping to the iPhone and screenshotting.
    ///
    /// The Mac and iOS app share `com.codexbar.shared` as their
    /// `ubiquity-kvstore-identifier`, so `NSUbiquitousKeyValueStore.default`
    /// resolves to the same iCloud-backed KV store on both sides.
    private func dumpIOSNSELog() {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let data = store.data(forKey: "NSEInvocationLog.entries") else {
            self.lastTestResult = "[\(self.shortTime())] iOS NSE log: (empty — no data in iCloud KV)"
            return
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            self.lastTestResult = "[\(self.shortTime())] iOS NSE log: decode failed " +
                "(raw bytes=\(data.count))"
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        var lines = ["[\(self.shortTime())] iOS NSE log — \(raw.count) entries:"]
        for e in raw {
            let ts: String
            if let n = e["timestamp"] as? Double {
                // JSONEncoder default encodes Date as seconds-since-reference-date
                // (2001-01-01). Convert to wall time.
                let d = Date(timeIntervalSinceReferenceDate: n)
                ts = formatter.string(from: d)
            } else {
                ts = "?"
            }
            let event = (e["event"] as? String) ?? "?"
            let zone = (e["zoneName"] as? String) ?? "-"
            let detail = (e["detail"] as? String) ?? ""
            lines.append("\(ts) \(event.uppercased()) \(zone) | \(detail)")
        }
        self.lastTestResult = lines.joined(separator: "\n")
    }

    /// Fires 5 distinct warning records spaced 5s apart so we can measure
    /// push-coalesce behavior end-to-end without relying on the Menu UI
    /// (SwiftUI Menu can't be reliably driven via AppleScript for QA
    /// automation). Combinations vary `(provider, window, threshold)` so
    /// each recordName is unique and CK shouldn't dedupe.
    private func runBurstWarningTest() {
        let burst: [(String, String, String, Int)] = [
            ("Codex", "codex", "session", 50),
            ("Claude", "claude", "session", 20),
            ("Codex", "codex", "weekly", 50),
            ("Claude", "claude", "weekly", 10),
            ("Codex", "codex", "session", 10),
        ]
        self.appendTestResult(
            "[\(self.shortTime())] === BURST start (5 distinct combos, 5s spacing) ===")
        Task {
            for (i, item) in burst.enumerated() {
                let (provider, providerID, window, threshold) = item
                self.runTestWarningPush(
                    provider: provider,
                    providerID: providerID,
                    window: window,
                    threshold: threshold)
                if i < burst.count - 1 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
            self.appendTestResult("[\(self.shortTime())] === BURST end (5 fired) ===")
        }
    }

    private func runTestWarningPush(
        provider: String, providerID: String, window: String, threshold: Int)
    {
        let now = Date()
        let hourBucket = Int(now.timeIntervalSince1970 / 3600)
        let recordName = "\(providerID)-\(window)-t\(threshold)-\(hourBucket)"
        let header = "[\(self.shortTime())] \(provider) warning \(window) \(threshold)%"
        self.appendTestResult("\(header)\n  record: \(recordName)\n  writing…")
        Task {
            let result = await CloudSyncManager.shared.writeQuotaWarningTransition(
                providerName: provider,
                providerID: providerID,
                window: window,
                threshold: threshold,
                transitionAt: now)
            if result.succeeded {
                self.updateTestResultLast(
                    "\(header)\n  record: \(recordName)\n  ✓ CK write OK")
            } else {
                self.updateTestResultLast(
                    "\(header)\n  record: \(recordName)\n  ✗ CK FAIL: \(result.message ?? "?")")
            }
        }
    }

    private func shortTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    // MARK: - Sync Status

    private var syncStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if self.syncCoordinator.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("mobile_sync_status_syncing"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let lastSync = self.syncCoordinator.lastSyncTime {
                    Image(systemName: self.syncCoordinator.lastSyncSucceeded
                        ? "checkmark.icloud"
                        : "exclamationmark.icloud")
                        .foregroundColor(self.syncCoordinator.lastSyncSucceeded
                            ? Color.secondary
                            : Color.red)
                        .font(.footnote)
                    Text(
                        self.syncCoordinator.lastSyncSucceeded
                            ? L("mobile_sync_status_last_sync_format", Self.formatSyncTime(lastSync))
                            : L("mobile_sync_status_last_attempt_format", Self.formatSyncTime(lastSync)))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "icloud")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                    Text(L("mobile_sync_status_no_sync"))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            if let message = self.syncCoordinator.lastSyncMessage, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(L("mobile_button_sync_now")) {
                Task {
                    await self.syncCoordinator.pushCurrentSnapshot()
                }
            }
            .controlSize(.small)
            .disabled(self.syncCoordinator.isSyncing)
        }
    }

    private static func formatSyncTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
