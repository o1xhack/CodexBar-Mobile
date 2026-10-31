import CodexBarSync
import Foundation
import Testing
import UIKit
@testable import CodexBarMobile

@Suite("Account-scoped usage quota overview")
@MainActor
struct UsageQuotaOverviewTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(
        id: String = "primary", used: Double = 20, minutes: Int? = 300,
        reset: Date? = Self.now.addingTimeInterval(3600), known: Bool = true,
        blocked: Bool = false) -> SyncRateWindow
    {
        SyncRateWindow(
            id: id,
            label: id == "secondary" ? "Weekly" : id.hasPrefix("claude-weekly-scoped-") ? "Fable only" : "Session",
            usedPercent: used, usageKnown: known, windowMinutes: minutes, resetsAt: reset, resetDescription: nil,
            blockingQuota: blocked ? SyncBlockingQuota(
                windowID: "secondary", rawUsedPercent: 100, rawResetsAt: reset,
                rawResetDescription: nil, rawNextRegenPercent: nil) : nil)
    }

    private static func account(
        id: String = "fictional-a", record: String? = "install-a", providerID: String = "claude",
        capturedAt: Date = Self.now, windows: [SyncRateWindow]? = nil,
        wireHistory: [SyncUtilizationSeries]? = nil,
        identities: [String]? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID, providerName: providerID.capitalized, primary: nil, secondary: nil,
            accountEmail: "\(id)@example.invalid", loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: capturedAt, rateWindows: windows ?? [self.window()], utilizationHistory: wireHistory,
            accountIdentities: identities ?? ["\(providerID):account:\(id)"], accountRecordKey: record)
    }

    private static func sampledStore(id: String = "fictional-a") -> UsageQuotaOverviewStore {
        let store = UsageQuotaOverviewStore.inMemory()
        let amounts: [Double] = [10, 10, 12, 18, 18, 20, 25, 25, 30]
        for (index, used) in amounts.enumerated() {
            let captured = Self.now.addingTimeInterval(Double(index - 8) * 300)
            store.reconcile(accounts: [Self.account(
                id: id, capturedAt: captured, windows: [Self.window(used: used)])], now: Self.now)
        }
        return store
    }

    private static func weakAccount(
        capturedAt: Date, used: Double, providerID: String = "claude", minutes: Int = 300,
        reset: Date = Self.now.addingTimeInterval(3600)) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID, providerName: providerID.capitalized,
            primary: nil, secondary: nil, accountEmail: nil, loginMethod: "Fictional plan",
            statusMessage: nil, isError: false, lastUpdated: capturedAt,
            rateWindows: [self.window(used: used, minutes: minutes, reset: reset)],
            accountIdentities: ["\(providerID):record:install-a"], accountRecordKey: "install-a")
    }

    @Test
    func `defaults initialize only once and clearing survives persistence reload`() throws {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        store.reconcile(accounts: [], now: Self.now)
        #expect(!store.preferences.hasInitialized)
        store.reconcile(accounts: [Self.account()], now: Self.now)
        #expect(store.preferences.selections.count == 1)
        try store.remove(id: #require(store.preferences.selections.first).id)
        let reopened = UsageQuotaOverviewStore(persistence: memory)
        reopened.reconcile(accounts: [Self.account()], now: Self.now)
        #expect(reopened.preferences.hasInitialized)
        #expect(reopened.preferences.selections.isEmpty)
    }

    @Test
    func `selection cap uniqueness colors and scoped windows are independent`() throws {
        let windows = (0..<8).map { index in
            Self.window(id: index == 0 ? "primary" : "claude-weekly-scoped-fictitious-\(index)", minutes: 10080)
        }
        let account = Self.account(windows: windows)
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        for selection in store.preferences.selections {
            store.remove(id: selection.id)
        }
        let candidates = store.catalog(accounts: [account], now: Self.now)
        #expect(candidates.count == 8)
        for candidate in candidates.prefix(5) {
            #expect(store.add(candidate))
        }
        #expect(!store.add(candidates[5]))
        #expect(!store.add(candidates[0]))
        #expect(store.preferences.selections.count == 5)
        #expect(Set(store.preferences.selections.map(\.colorHex)).count == 5)
        var first = try #require(store.preferences.selections.first)
        first.colorHex = "#12abef"
        #expect(store.update(first))
        #expect(store.preferences.selections.first?.colorHex == "12ABEF")
        first.colorHex = "invalid"
        #expect(!store.update(first))
        #expect(store.preferences.selections.first?.colorHex == "12ABEF")
    }

    @Test
    func `default colors come from the existing provider palette`() {
        for providerID in ["grok", "cursor", "claude", "codex"] {
            let expected = UIColor(ProviderColorPalette.color(for: providerID, tintHex: nil))
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let actualHex = UsageQuotaColor.suggested(providerID: providerID, ordinal: 0)
            let value = UInt32(actualHex, radix: 16) ?? 0
            let actual = UIColor(
                red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
            var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
            var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
            #expect(expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea))
            #expect(actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa))
            #expect(abs(er - ar) <= 0.5 / 255)
            #expect(abs(eg - ag) <= 0.5 / 255)
            #expect(abs(eb - ab) <= 0.5 / 255)
        }
        #expect(UsageQuotaColor.suggested(providerID: "claude", ordinal: 0) !=
            UsageQuotaColor.suggested(providerID: "claude", ordinal: 1))
        #expect(UsageQuotaColor.normalized("#aAbB33") == "AABB33")
        #expect(UsageQuotaColor.normalized("fff") == nil)
    }

    @Test
    func `first run gives other providers a weekly line before adding second Claude accounts`() {
        let windows = [Self.window(), Self.window(id: "secondary", minutes: 10080)]
        let accounts = [
            Self.account(id: "claude-a", windows: windows),
            Self.account(id: "claude-b", windows: windows),
            Self.account(id: "codex-a", providerID: "codex", windows: windows),
            Self.account(id: "codex-b", providerID: "codex", windows: windows),
            Self.account(id: "muse-a", providerID: "muse", windows: windows),
            Self.account(id: "grok-a", providerID: "grok", windows: windows),
        ]
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: accounts, now: Self.now)
        #expect(store.preferences.selections.map(\.providerID) == ["claude", "claude", "codex", "muse", "grok"])
        #expect(store.preferences.selections.map(\.windowID) == [
            "secondary",
            "primary",
            "secondary",
            "secondary",
            "secondary",
        ])
        #expect(Set(store.preferences.selections.prefix(2).map(\.accountAnchorID)).count == 1)
        let original = store.preferences.selections
        store.reconcile(accounts: accounts.reversed(), now: Self.now)
        #expect(store.preferences.selections == original)
    }

    @Test
    func `read only provider history restores observations without becoming verified local account history`() throws {
        let history = SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [
            SyncUtilizationEntry(capturedAt: Self.now.addingTimeInterval(-1800), usedPercent: 1, resetsAt: nil),
            SyncUtilizationEntry(capturedAt: Self.now.addingTimeInterval(-900), usedPercent: 19, resetsAt: nil),
            SyncUtilizationEntry(capturedAt: Self.now.addingTimeInterval(-300), usedPercent: 19, resetsAt: nil),
        ])
        let account = Self.account(wireHistory: [history])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        let line = try #require(store.overview(accounts: [account], now: Self.now).lines.first)
        #expect(line.localObservationCount == 1)
        #expect(line.usesSyncedProviderHistory)
        #expect(line.observedSamples.map(\.remainingPercent) == [99, 81, 81, 80])
        #expect(line.observedSamples.first?.date == Self.now.addingTimeInterval(-1800))
        #expect(line.observedSamples.allSatisfy { $0.segment == 0 })
    }

    @Test
    func `synced history uses exact source account cycle and local receipts win timestamp conflicts`() throws {
        let reset = Self.now.addingTimeInterval(2 * 86400)
        let old = Self.now.addingTimeInterval(-2 * 86400)
        let localTime = Self.now.addingTimeInterval(-300)
        let history = SyncUtilizationSeries(name: "weekly", windowMinutes: 10080, entries: [
            SyncUtilizationEntry(capturedAt: old, usedPercent: 2, resetsAt: reset),
            SyncUtilizationEntry(capturedAt: localTime, usedPercent: 10, resetsAt: reset),
            SyncUtilizationEntry(capturedAt: Self.now.addingTimeInterval(-120), usedPercent: 15, resetsAt: reset),
            SyncUtilizationEntry(capturedAt: Self.now, usedPercent: 20, resetsAt: reset),
            // Neither another cycle nor future readings may contaminate this curve.
            SyncUtilizationEntry(
                capturedAt: old.addingTimeInterval(60),
                usedPercent: 70,
                resetsAt: reset.addingTimeInterval(-7 * 86400)),
            SyncUtilizationEntry(capturedAt: Self.now.addingTimeInterval(60), usedPercent: 80, resetsAt: reset),
        ])
        let store = UsageQuotaOverviewStore.inMemory()
        let local = Self.account(capturedAt: localTime, windows: [Self.window(
            id: "secondary", used: 30, minutes: 10080, reset: reset)])
        store.reconcile(accounts: [local], now: localTime)
        let raw = Self.account(windows: [Self.window(
            id: "secondary", used: 40, minutes: 10080, reset: reset)], wireHistory: [history])
        let source = SyncedUsageSnapshot(
            providers: [raw], syncTimestamp: Self.now, deviceName: "Fictional source", deviceID: "source")
        let merged = Self.account(windows: [Self.window(
            id: "secondary", used: 40, minutes: 10080, reset: reset)], wireHistory: [
            SyncUtilizationSeries(name: "weekly", windowMinutes: 10080, entries: [
                SyncUtilizationEntry(capturedAt: old, usedPercent: 99, resetsAt: reset),
            ]),
        ])
        store.reconcile(accounts: [merged], sourceSnapshots: [source], now: Self.now)
        let line = try #require(store.overview(accounts: [merged], now: Self.now).lines.first)
        #expect(line.observedSamples.map(\.remainingPercent) == [98, 70, 60])
        #expect(line.observedSamples.map(\.date) == [old, localTime, Self.now])
    }

    @Test
    func `different account older writer and conflicting equal time histories cannot supply a curve`() {
        let past = Self.now.addingTimeInterval(-600)
        func history(_ used: Double) -> [SyncUtilizationSeries] {
            [SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [
                SyncUtilizationEntry(capturedAt: past, usedPercent: used, resetsAt: nil),
            ])]
        }
        func source(_ account: ProviderUsageSnapshot, _ id: String) -> SyncedUsageSnapshot {
            SyncedUsageSnapshot(providers: [account], syncTimestamp: Self.now, deviceName: id, deviceID: id)
        }
        let current = Self.account()
        let otherAccount = Self.account(id: "different-owner", wireHistory: history(1))
        let oldWriter = Self.account(capturedAt: Self.now.addingTimeInterval(-60), wireHistory: history(2))
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [current], sourceSnapshots: [
            source(current, "current"), source(otherAccount, "other"), source(oldWriter, "older"),
        ], now: Self.now)
        #expect(store.overview(accounts: [current], now: Self.now).lines.first?.observedSamples.count == 1)
        let first = Self.account(wireHistory: history(1))
        let second = Self.account(wireHistory: history(2))
        for sources in [
            [source(first, "first"), source(second, "second")],
            [source(second, "second"), source(first, "first")],
        ] {
            store.reconcile(accounts: [current], sourceSnapshots: sources, now: Self.now)
            #expect(store.overview(accounts: [current], now: Self.now).lines.first?.observedSamples.count == 1)
        }
    }

    @Test
    func `multiple visible accounts cannot duplicate provider wide history into independent account curves`() {
        let series = SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [
            SyncUtilizationEntry(capturedAt: Self.now.addingTimeInterval(-300), usedPercent: 1, resetsAt: nil),
        ])
        let accounts = [Self.account(wireHistory: [series]), Self.account(
            id: "other-owner", record: "other-record", wireHistory: [series])]
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: accounts, now: Self.now)
        let overview = store.overview(accounts: accounts, now: Self.now)
        #expect(overview.lines.count == 2)
        #expect(overview.lines.allSatisfy { !$0.usesSyncedProviderHistory && $0.observedSamples.count == 1 })
    }

    @Test
    func `real local observations preserve exact historical times values and pauses without forecasting`() throws {
        let store = Self.sampledStore()
        let latest = Self.account(windows: [Self.window(used: 30)])
        let overview = store.overview(accounts: [latest], now: Self.now)
        let line = try #require(overview.lines.first)
        #expect(line.observedSamples.map(\.remainingPercent) == [90, 90, 88, 82, 82, 80, 75, 75, 70])
        #expect(line.observedSamples.map(\.date) == (0...8).map { Self.now.addingTimeInterval(Double($0 - 8) * 300) })
        #expect(overview.start == Self.now.addingTimeInterval(-6 * 86400))
        #expect(overview.end == Self.now)
        #expect(line.observedSamples.last?.remainingPercent == 70)
        #expect(line.observedSamples.allSatisfy { $0.date <= Self.now })
    }

    @Test(arguments: [60, 300])
    func `frequent weekly observations retain elapsed span and real busy idle observations`(
        intervalSeconds: Int) throws
    {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        let start = Self.now.addingTimeInterval(-8 * 3600)
        let reset = Self.now.addingTimeInterval(3 * 86400)
        func reading(at elapsed: Int) -> ProviderUsageSnapshot {
            let periods = elapsed / 1200
            let activeSeconds = max(0, elapsed % 1200 - 600)
            let used = 10 + Double(periods) * 2 + Double(activeSeconds) / 300
            return Self.account(
                capturedAt: start.addingTimeInterval(Double(elapsed)),
                windows: [Self.window(used: used, minutes: 10080, reset: reset)])
        }
        for elapsed in stride(from: 0, through: 8 * 3600, by: intervalSeconds) {
            let account = reading(at: elapsed)
            store.reconcile(accounts: [account], now: account.lastUpdated)
        }
        func assertHistory(elapsed: Int) throws {
            let account = reading(at: elapsed)
            let line = try #require(store.overview(accounts: [account], now: account.lastUpdated).lines.first)
            let archive = try JSONDecoder().decode(UsageQuotaArchive.self, from: #require(memory.data))
            let observations = try #require(archive.histories.first).observations
            let first = try #require(observations.first)
            let latest = try #require(observations.last)
            #expect(observations.count <= UsageQuotaOverviewStore.maximumObservationsPerStream)
            #expect(latest.capturedAt.timeIntervalSince(first.capturedAt) >= 6 * 3600)
            #expect(latest.capturedAt == account.lastUpdated)
            #expect(latest.usedPercent == account.rateWindows[0].usedPercent)
            #expect(line.observedSamples.count > 1)
            #expect(line.observedSamples.last?.date == account.lastUpdated)
            #expect(line.observedSamples.last?.remainingPercent == line.currentRemainingPercent)
            let pairs = Array(zip(line.observedSamples, line.observedSamples.dropFirst()))
            #expect(pairs.contains { $0.remainingPercent == $1.remainingPercent })
            #expect(pairs.contains { $0.remainingPercent > $1.remainingPercent })
            #expect(pairs.allSatisfy { $0.remainingPercent >= $1.remainingPercent })
            #expect(line.observedSamples.allSatisfy { $0.date <= reset })
        }
        try assertHistory(elapsed: 8 * 3600)
        let beforeDuplicate = memory.data
        store.reconcile(accounts: [reading(at: 8 * 3600)], now: Self.now.addingTimeInterval(30))
        #expect(memory.data == beforeDuplicate, "A reader refresh cannot advance a source observation")
        // Once full, trimming old endpoints must continue to retain the minimum elapsed span.
        for elapsed in stride(from: 8 * 3600 + intervalSeconds, through: 9 * 3600, by: intervalSeconds) {
            let account = reading(at: elapsed)
            store.reconcile(accounts: [account], now: account.lastUpdated)
        }
        try assertHistory(elapsed: 9 * 3600)
    }

    @Test
    func `subminute sampling retains the latest actual endpoint`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        let start = Self.now.addingTimeInterval(-1830)
        for elapsed in stride(from: 0, through: 1830, by: 30) {
            let used = 10 + Double(elapsed / 300)
            let account = Self.account(
                capturedAt: start.addingTimeInterval(Double(elapsed)), windows: [Self.window(used: used)])
            store.reconcile(accounts: [account], now: account.lastUpdated)
        }
        let latest = Self.account(windows: [Self.window(used: 16)])
        let line = try #require(store.overview(accounts: [latest], now: Self.now).lines.first)
        #expect(line.observedAt == Self.now)
        #expect(line.currentRemainingPercent == 84)
        #expect(line.observedSamples.count > 1)
        #expect(line.observedSamples.last == UsageQuotaPoint(date: Self.now, remainingPercent: 84))
        #expect(line.localObservationCount <= UsageQuotaOverviewStore.maximumObservationsPerStream)
    }

    @Test
    func `time aware retention never relabels a long missing interval as measured idle time`() throws {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        let reset = Self.now.addingTimeInterval(3 * 86400)
        for step in 0...72 {
            let capture = Self.now.addingTimeInterval(-10 * 3600 + Double(step) * 300)
            let account = Self.account(
                capturedAt: capture, windows: [Self.window(used: 10, minutes: 10080, reset: reset)])
            store.reconcile(accounts: [account], now: capture)
        }
        let current = Self.account(windows: [Self.window(used: 10, minutes: 10080, reset: reset)])
        store.reconcile(accounts: [current], now: Self.now)
        let archive = try JSONDecoder().decode(UsageQuotaArchive.self, from: #require(memory.data))
        let observations = try #require(archive.histories.first).observations
        #expect(observations.count >= 4)
        let first = try #require(observations.first)
        let latest = try #require(observations.last)
        #expect(latest.capturedAt.timeIntervalSince(first.capturedAt) >= 6 * 3600)
        #expect(zip(observations, observations.dropFirst()).contains {
            $1.capturedAt.timeIntervalSince($0.capturedAt) > 2 * 3600
        })
        let line = try #require(store.overview(accounts: [current], now: Self.now).lines.first)
        #expect(Set(line.observedSamples.map(\.segment)).count == 2)
    }

    @Test
    func `an old gap does not suppress a newer complete contiguous observation span`() throws {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        let reset = Self.now.addingTimeInterval(3 * 86400)
        func record(_ capture: Date) {
            let account = Self.account(
                capturedAt: capture, windows: [Self.window(used: 10, minutes: 10080, reset: reset)])
            store.reconcile(accounts: [account], now: capture)
        }
        // Keep an older three-hour gap in the archive, followed by six complete hours
        // of direct five-minute observations. The newer period is sufficient on its own.
        for step in 0...12 {
            record(Self.now.addingTimeInterval(-10 * 3600 + Double(step) * 300))
        }
        for step in 0...72 {
            record(Self.now.addingTimeInterval(-6 * 3600 + Double(step) * 300))
        }
        let archive = try JSONDecoder().decode(UsageQuotaArchive.self, from: #require(memory.data))
        let observations = try #require(archive.histories.first).observations
        #expect(zip(observations, observations.dropFirst()).contains {
            $1.capturedAt.timeIntervalSince($0.capturedAt) > 2 * 3600
        })
        let current = Self.account(windows: [Self.window(used: 10, minutes: 10080, reset: reset)])
        let line = try #require(store.overview(accounts: [current], now: Self.now).lines.first)
        #expect(line.observedSamples.count > 1)
        #expect(line.observedSamples.last?.date == Self.now)
        #expect(line.observedSamples.allSatisfy { $0.remainingPercent == 90 })
    }

    @Test(arguments: [10080, 43200])
    func `full cycle compaction preserves endpoints and real continuity rather than inventing gaps`(
        minutes: Int) throws
    {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        let interval = minutes == 10080 ? 300 : 3600
        let count = minutes * 60 / interval - 1
        let start = Self.now.addingTimeInterval(-Double(count * interval))
        let reset = Self.now.addingTimeInterval(Double(interval))
        var latest = Self.account()
        for step in 0...count {
            latest = Self.account(
                capturedAt: start.addingTimeInterval(Double(step * interval)),
                windows: [Self.window(used: Double(step) / Double(count) * 60, minutes: minutes, reset: reset)])
            store.reconcile(accounts: [latest], now: latest.lastUpdated)
        }
        let line = try #require(store.overview(accounts: [latest], now: Self.now).lines.first)
        #expect(line.observedSamples.count == UsageQuotaOverviewStore.maximumObservationsPerStream)
        #expect(line.observedSamples.first?.date == start)
        #expect(line.observedSamples.first?.remainingPercent == 100)
        #expect(line.observedSamples.last?.date == Self.now)
        #expect(line.observedSamples.last?.remainingPercent == 40)
        #expect(Set(line.observedSamples.map(\.segment)) == [0])
        #expect(line.observedSamples.allSatisfy { point in
            let step = point.date.timeIntervalSince(start) / Double(interval)
            return step.rounded() == step && abs(point.remainingPercent - (100 - step / Double(count) * 60)) < 0.000001
        })
        let beforeDuplicate = memory.data
        store.reconcile(accounts: [latest], now: Self.now.addingTimeInterval(30))
        #expect(memory.data == beforeDuplicate)
        let reloaded = UsageQuotaOverviewStore(persistence: memory)
        #expect(reloaded.overview(accounts: [latest], now: Self.now).lines.first?.observedSamples == line
            .observedSamples)
        let corrected = Self.account(windows: [Self.window(used: 61, minutes: minutes, reset: reset)])
        let beforeReconcile = try #require(store.overview(accounts: [corrected], now: Self.now).lines.first)
        #expect(Set(beforeReconcile.observedSamples.map(\.segment)) == [0])
        #expect(beforeReconcile.observedSamples.last?.remainingPercent == 39)
        store.reconcile(accounts: [corrected], now: Self.now)
        let afterReconcile = try #require(store.overview(accounts: [corrected], now: Self.now).lines.first)
        #expect(Set(afterReconcile.observedSamples.map(\.segment)) == [0])
        #expect(afterReconcile.observedSamples.last?.remainingPercent == 39)
    }

    @Test
    func `compaction retains genuine source interruptions and isolated actual readings`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        let reset = Self.now.addingTimeInterval(86400)
        var latest = Self.account()
        for step in 0...240 {
            let gap = step >= 120 ? 4 * 3600 : 0
            let capture = Self.now.addingTimeInterval(Double((step - 240) * 600 + gap - 4 * 3600))
            latest = Self.account(capturedAt: capture, windows: [Self.window(
                used: Double(step) / 4, minutes: 10080, reset: reset)])
            store.reconcile(accounts: [latest], now: capture)
        }
        let line = try #require(store.overview(accounts: [latest], now: Self.now).lines.first)
        #expect(Set(line.observedSamples.map(\.segment)) == [0, 1])
        #expect(line.observedSamples.last?.date == Self.now)
    }

    @Test
    func `isolated real readings survive as distinct single point segments`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        var latest = Self.account()
        for step in 0...2 {
            let capture = Self.now.addingTimeInterval(Double(step - 2) * 3 * 3600)
            latest = Self.account(capturedAt: capture, windows: [Self.window(
                used: Double(10 + step * 5), minutes: 10080, reset: Self.now.addingTimeInterval(86400))])
            store.reconcile(accounts: [latest], now: capture)
        }
        let line = try #require(store.overview(accounts: [latest], now: Self.now).lines.first)
        #expect(line.observedSamples.map(\.remainingPercent) == [90, 85, 80])
        #expect(line.observedSamples.map(\.segment) == [0, 1, 2])
    }

    @Test
    func `observation stream capacity stays bounded and protects selected bindings`() throws {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        let accounts = (0..<70).map { Self.account(id: "fictional-\($0)", record: "fictional-record-\($0)") }
        store.reconcile(accounts: accounts, now: Self.now)
        let archive = try JSONDecoder().decode(UsageQuotaArchive.self, from: #require(memory.data))
        #expect(archive.histories.count == UsageQuotaOverviewStore.maximumHistoryStreams)
        let savedBindings = Set(archive.histories.map(\.binding))
        #expect(store.preferences.selections.allSatisfy { savedBindings.contains($0.binding) })
    }

    @Test
    func `new source metadata does not wash an old quota observation fresh`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        let old = Self.now.addingTimeInterval(-7 * 3600)
        var account = Self.account(capturedAt: Self.now)
        account.sourceReport = SyncProviderSourceReport(
            sourceDeviceID: "fictional-mac", sourceDeviceName: "Fictional Mac", sourceCapturedAt: old,
            failures: [], deviceCount: 2)
        let source = SyncedUsageSnapshot(
            providers: [Self.account(capturedAt: old)], syncTimestamp: Self.now,
            deviceName: "Fictional Mac", deviceID: "fictional-mac")
        store.reconcile(accounts: [account], sourceSnapshots: [source], now: Self.now)
        let line = try #require(store.overview(accounts: [account], now: Self.now).lines.first)
        #expect(line.observedAt == old)
        #expect(line.state == .stale)
        #expect(line.observedSamples.isEmpty)
        #expect(line.currentRemainingPercent == 80)
    }

    @Test
    func `reset rollover duration change and decreasing observations start separate segments`() {
        let store = Self.sampledStore()
        let newTime = Self.now.addingTimeInterval(60)
        let longer = Self.account(capturedAt: newTime, windows: [Self.window(used: 35, minutes: 600)])
        store.reconcile(accounts: [longer], now: newTime)
        #expect(store.overview(accounts: [longer], now: newTime).lines.first?.localObservationCount == 1)
        let resetTime = Self.now.addingTimeInterval(120)
        let rolled = Self.account(capturedAt: resetTime, windows: [Self.window(
            used: 2, minutes: 600, reset: Self.now.addingTimeInterval(36000))])
        store.reconcile(accounts: [rolled], now: resetTime)
        #expect(store.overview(accounts: [rolled], now: resetTime).lines.first?.localObservationCount == 1)
        let correctionTime = Self.now.addingTimeInterval(180)
        let correction = Self.account(capturedAt: correctionTime, windows: [Self.window(
            used: 1, minutes: 600, reset: Self.now.addingTimeInterval(36000))])
        store.reconcile(accounts: [correction], now: correctionTime)
        #expect(store.overview(accounts: [correction], now: correctionTime).lines.first?.localObservationCount == 1)
    }

    @Test
    func `two accounts never inherit each others local observed pattern`() throws {
        let store = Self.sampledStore()
        let first = Self.account(windows: [Self.window(used: 30)])
        let other = Self.account(id: "fictional-b", record: "install-b", windows: [Self.window(used: 45)])
        store.reconcile(accounts: [first, other], now: Self.now)
        let candidate = try #require(store.catalog(accounts: [first, other]).first {
            $0.accountAnchorID != store.preferences.selections.first?.accountAnchorID
        })
        #expect(store.add(candidate))
        let lines = store.overview(accounts: [first, other], now: Self.now).lines
        #expect(lines[0].observedSamples.count == 9)
        #expect(lines[1].localObservationCount == 1)
        #expect(lines[1].observedSamples.count == 1)
        #expect(lines[1].currentRemainingPercent == 55)
    }

    @Test(arguments: ["claude", "codex"])
    func `a known account linked to legacy anonymous publications still collects only its real readings`(
        providerID: String) throws
    {
        let store = UsageQuotaOverviewStore.inMemory()
        let link = ProviderAccountLinkage(
            providerID: providerID,
            linkedIdentifiers: ["\(providerID):account:fictional-a", "\(providerID):legacy-no-identity"],
            confirmedFromDeviceID: "fictional-phone")
        var latest = Self.account(providerID: providerID)
        var latestSources: [SyncedUsageSnapshot] = []
        for step in 0...2 {
            let capture = Self.now.addingTimeInterval(Double(step - 2) * 300)
            latest = Self.account(
                providerID: providerID,
                capturedAt: capture,
                windows: [Self.window(used: Double(10 + step))])
            let anonymous = ProviderUsageSnapshot(
                providerID: providerID, providerName: providerID.capitalized,
                primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
                statusMessage: nil, isError: false, lastUpdated: capture.addingTimeInterval(30),
                rateWindows: [Self.window(used: 90)], accountIdentities: ["\(providerID):legacy-no-identity"])
            latestSources = [
                SyncedUsageSnapshot(
                    providers: [latest],
                    syncTimestamp: capture,
                    deviceName: "Known owner Mac",
                    deviceID: "known-mac"),
                SyncedUsageSnapshot(
                    providers: [anonymous],
                    syncTimestamp: capture.addingTimeInterval(30),
                    deviceName: "Legacy Mac",
                    deviceID: "legacy-mac"),
            ]
            store.reconcile(accounts: [latest], sourceSnapshots: latestSources, linkages: [link], now: Self.now)
        }
        let line = try #require(store.overview(accounts: [latest], now: Self.now).lines.first)
        #expect(line.localObservationCount == 3)
        #expect(line.observedSamples.map(\.remainingPercent) == [90, 89, 88])
        #expect(line.observedSamples.map(\.date) == [-600.0, -300, 0].map(Self.now.addingTimeInterval))
        #expect(line.observedAt == Self.now)
        let anonymousOnly = UsageQuotaOverviewStore.inMemory()
        anonymousOnly.reconcile(
            accounts: [latest], sourceSnapshots: latestSources.filter { $0.deviceID == "legacy-mac" },
            linkages: [link], now: Self.now)
        let missing = try #require(anonymousOnly.overview(accounts: [latest], now: Self.now).lines.first)
        #expect(missing.localObservationCount == 0)
        #expect(missing.observedSamples.isEmpty)
    }

    @Test(arguments: ["legacy-no-identity", "record:shared-slot", "card:shared-card"])
    func `indirect weak aliases cannot join two stable owners and unmerge recomputes the component`(
        alias: String)
    {
        let account = Self.account()
        let first = ProviderAccountLinkage(
            providerID: "claude", linkedIdentifiers: ["claude:account:fictional-a", "claude:\(alias)"],
            confirmedFromDeviceID: "fictional-phone")
        let second = ProviderAccountLinkage(
            providerID: "claude", linkedIdentifiers: ["claude:account:fictional-b", "claude:\(alias)"],
            confirmedFromDeviceID: "fictional-phone")
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], linkages: [first, second], now: Self.now)
        #expect(store.overview(accounts: [account], now: Self.now).lines.first?.localObservationCount == 0)
        store.reconcile(
            accounts: [account],
            linkages: [first, second, second.inverseUnmerge(confirmedFromDeviceID: "fictional-phone")], now: Self.now)
        #expect(store.overview(accounts: [account], now: Self.now).lines.first?.localObservationCount == 1)
    }

    @Test
    func `linked accounts do not mix samples and unmerge preserves original binding`() throws {
        let store = Self.sampledStore()
        let first = Self.account(windows: [Self.window(used: 30)])
        let other = Self.account(id: "fictional-b", record: "install-b", windows: [Self.window(used: 55)])
        store.reconcile(accounts: [first, other], now: Self.now)
        let link = ProviderAccountLinkage(
            providerID: "claude", linkedIdentifiers: ["claude:account:fictional-a", "claude:account:fictional-b"],
            confirmedFromDeviceID: "fictional-phone")
        store.reconcile(accounts: [other], linkages: [link], now: Self.now)
        let linked = try #require(store.overview(accounts: [other], now: Self.now).lines.first)
        #expect(linked.observedSamples.count == 1)
        #expect(linked.localObservationCount == 0)
        store.reconcile(
            accounts: [other],
            linkages: [link, link.inverseUnmerge(confirmedFromDeviceID: "fictional-phone")],
            now: Self.now)
        #expect(store.overview(accounts: [other], now: Self.now).lines.first?.state == .missingAccount)
        store.reconcile(accounts: [first, other], now: Self.now)
        #expect(store.overview(accounts: [first, other], now: Self.now).lines.first?.localObservationCount == 9)
    }

    @Test
    func `combined stable identities cannot reuse a matching old account pattern by timestamp coincidence`() throws {
        let store = Self.sampledStore()
        let first = Self.account(windows: [Self.window(used: 30)])
        let other = Self.account(id: "fictional-b", record: "install-b", windows: [Self.window(used: 55)])
        store.reconcile(accounts: [first, other], now: Self.now)
        let combined = Self.account(
            windows: [Self.window(used: 30)],
            identities: ["claude:account:fictional-a", "claude:account:fictional-b"])
        store.reconcile(accounts: [combined], now: Self.now)
        let line = try #require(store.overview(accounts: [combined], now: Self.now).lines.first)
        #expect(line.localObservationCount == 0)
        #expect(line.observedSamples.count == 1)
        store.reconcile(accounts: [first, other], now: Self.now)
        #expect(store.overview(accounts: [first, other], now: Self.now).lines.first?.localObservationCount == 9)
    }

    @Test
    func `identity record flip preserves selection while an unrelated reused slot cannot rebind it`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [Self.account()], now: Self.now)
        let original = try #require(store.preferences.selections.first)
        let flipped = Self.account(record: "other-mac-install")
        store.reconcile(accounts: [flipped], now: Self.now)
        #expect(store.preferences.selections.first?.id == original.id)
        #expect(store.overview(accounts: [flipped], now: Self.now).lines.first?.state == .available)
        let unrelated = Self.account(id: "unrelated", record: "install-a")
        store.reconcile(accounts: [unrelated], now: Self.now)
        #expect(store.overview(accounts: [unrelated], now: Self.now).lines.first?.state == .missingAccount)
    }

    @Test(arguments: [false, true])
    func `a stable account becoming anonymous breaks history before the same owner returns`(
        originalSources: Bool) throws
    {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        func publish(_ raw: ProviderUsageSnapshot) throws -> ProviderUsageSnapshot {
            if originalSources {
                let snapshot = SyncedUsageSnapshot(
                    providers: [raw], syncTimestamp: raw.lastUpdated,
                    deviceName: "Fictional Mac", deviceID: "fictional-mac")
                let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([snapshot]))
                store.reconcile(
                    accounts: merged.providers, sourceSnapshots: [snapshot], quotaSources: merged.providerQuotaSources,
                    now: raw.lastUpdated)
                return try #require(merged.providers.first)
            }
            store.reconcile(accounts: [raw], now: raw.lastUpdated)
            return raw
        }
        for (index, used) in [10.0, 20, 30].enumerated() {
            _ = try publish(Self.account(
                capturedAt: Self.now.addingTimeInterval(Double(index - 3) * 300),
                windows: [Self.window(used: used)]))
        }
        var selection = try #require(store.preferences.selections.first)
        selection.colorHex = "123ABC"
        #expect(store.update(selection))
        let saved = store.preferences.selections
        let anonymous = try publish(Self.weakAccount(capturedAt: Self.now, used: 40))
        let weakLine = try #require(store.overview(accounts: [anonymous], now: Self.now).lines.first)
        #expect(weakLine.state == .available)
        #expect(weakLine.currentRemainingPercent == 60)
        #expect(weakLine.localObservationCount == 0)
        #expect(weakLine.observedSamples.count == 1)
        let weakArchive = try JSONDecoder().decode(UsageQuotaArchive.self, from: #require(memory.data))
        #expect(weakArchive.histories.isEmpty)
        #expect(store.preferences.selections == saved)

        let time = Self.now.addingTimeInterval(300)
        let returned = try publish(Self.account(capturedAt: time, windows: [Self.window(used: 50)]))
        let returnedLine = try #require(store.overview(accounts: [returned], now: time).lines.first)
        #expect(returnedLine.localObservationCount == 1)
        #expect(returnedLine.observedSamples.count == 1)
        #expect(returnedLine.currentRemainingPercent == 50)
        #expect(store.preferences.selections == saved)
    }

    @Test
    func `record only credential slots never collect account history even without an identity transition`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        var latest: ProviderUsageSnapshot?
        for (index, used) in [10.0, 20, 30, 40].enumerated() {
            let raw = Self.weakAccount(
                capturedAt: Self.now.addingTimeInterval(Double(index - 3) * 7200), used: used,
                providerID: "futureagi", minutes: 43200, reset: Self.now.addingTimeInterval(10 * 86400))
            let snapshot = SyncedUsageSnapshot(
                providers: [raw], syncTimestamp: raw.lastUpdated,
                deviceName: "Fictional API Mac", deviceID: "fictional-api-mac")
            let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([snapshot]))
            store.reconcile(
                accounts: merged.providers, sourceSnapshots: [snapshot], quotaSources: merged.providerQuotaSources,
                now: raw.lastUpdated)
            latest = merged.providers.first
        }
        let current = try #require(latest)
        let line = try #require(store.overview(accounts: [current], now: Self.now).lines.first)
        #expect(line.state == .available)
        #expect(line.currentRemainingPercent == 60)
        #expect(line.localObservationCount == 0)
        #expect(line.observedSamples.count == 1)
    }

    /// Grok read through browser cookies: no email, organization, identity list or credential slot.
    private static func identityLessGrok(capturedAt: Date, used: Double) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "grok", providerName: "Grok", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false, lastUpdated: capturedAt,
            rateWindows: [Self.window(used: used, minutes: nil, reset: Self.now.addingTimeInterval(5 * 86400))])
    }

    private static func publishMerged(
        _ raw: ProviderUsageSnapshot, others: [ProviderUsageSnapshot] = [], linkages: [ProviderAccountLinkage] = [],
        into store: UsageQuotaOverviewStore) throws -> [ProviderUsageSnapshot]
    {
        let snapshot = SyncedUsageSnapshot(
            providers: [raw] + others, syncTimestamp: raw.lastUpdated,
            deviceName: "Fictional Mac", deviceID: "fictional-mac")
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([snapshot]))
        store.reconcile(
            accounts: merged.providers, sourceSnapshots: [snapshot], quotaSources: merged.providerQuotaSources,
            linkages: linkages, now: raw.lastUpdated)
        return merged.providers
    }

    @Test
    func `an identity-less provider singleton collects its own readings and keeps them across reloads`() throws {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        var latest: [ProviderUsageSnapshot] = []
        for (index, used) in [10.0, 20, 30, 40].enumerated() {
            latest = try Self.publishMerged(
                Self.identityLessGrok(capturedAt: Self.now.addingTimeInterval(Double(index - 3) * 1800), used: used),
                into: store)
        }
        let line = try #require(store.overview(accounts: latest, now: Self.now).lines.first)
        #expect(line.selection.providerID == "grok")
        #expect(line.localObservationCount == 4)
        #expect(line.observedSamples.map(\.remainingPercent) == [90, 80, 70, 60])

        let archive = try JSONDecoder().decode(UsageQuotaArchive.self, from: #require(memory.data))
        let history = try #require(archive.histories.first)
        #expect(history.stableAccountTokens == nil)
        #expect(history.anonymousSingletonToken?.hasPrefix("grok:card:") == true)

        let reloaded = UsageQuotaOverviewStore(persistence: memory)
        #expect(!reloaded.isReadOnly)
        #expect(reloaded.overview(accounts: latest, now: Self.now).lines.first?.localObservationCount == 4)
    }

    @Test
    func `a second account or a linkage withdraws an identity-less singleton stream for good`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        for (index, used) in [10.0, 20, 30].enumerated() {
            _ = try Self.publishMerged(
                Self.identityLessGrok(capturedAt: Self.now.addingTimeInterval(Double(index - 4) * 1800), used: used),
                into: store)
        }
        let named = Self.account(id: "grok-named", record: nil, providerID: "grok", windows: [Self.window(used: 70)])
        let both = try Self.publishMerged(
            Self.identityLessGrok(capturedAt: Self.now.addingTimeInterval(-1800), used: 35), others: [named],
            into: store)
        #expect(both.filter { $0.providerID == "grok" }.count == 2)
        let ambiguous = try #require(store.overview(accounts: both, now: Self.now).lines.first)
        #expect(ambiguous.localObservationCount == 0)

        let alone = try Self.publishMerged(Self.identityLessGrok(capturedAt: Self.now, used: 40), into: store)
        let resumed = try #require(store.overview(accounts: alone, now: Self.now).lines.first)
        #expect(resumed.localObservationCount == 1)
        #expect(resumed.observedSamples.map(\.remainingPercent) == [60])

        let link = ProviderAccountLinkage(
            providerID: "grok", linkedIdentifiers: ["grok:account:grok-named", "grok:legacy-no-identity"],
            confirmedFromDeviceID: "fictional-phone")
        let linked = try Self.publishMerged(
            Self.identityLessGrok(capturedAt: Self.now.addingTimeInterval(60), used: 41), linkages: [link],
            into: store)
        #expect(store.overview(accounts: linked, now: Self.now.addingTimeInterval(60))
            .lines.first?.localObservationCount == 0)
    }

    @Test
    func `the widget receives the verified singleton stream and loses it with a second account`() throws {
        let sink = UsageQuotaWidgetHistoryRecorder()
        let store = UsageQuotaOverviewStore(widgetHistory: sink)
        for (index, used) in [10.0, 20, 30].enumerated() {
            _ = try Self.publishMerged(
                Self.identityLessGrok(capturedAt: Self.now.addingTimeInterval(Double(index - 3) * 1800), used: used),
                into: store)
        }
        let stream = try #require(sink.exported.last?.streams.first)
        #expect(sink.exported.last?.streams.count == 1)
        #expect(stream.providerID == "grok")
        #expect(stream.windowDuration == 7 * 86400)
        #expect(stream.entries.map(\.usedPercent) == [10, 20, 30])

        let named = Self.account(id: "grok-named", record: nil, providerID: "grok", windows: [Self.window(used: 70)])
        _ = try Self.publishMerged(
            Self.identityLessGrok(capturedAt: Self.now.addingTimeInterval(-60), used: 35), others: [named],
            into: store)
        #expect(sink.exported.last?.streams.isEmpty == true)
    }

    @Test
    func `accounts with a stable identity are never exported to the widget`() {
        let sink = UsageQuotaWidgetHistoryRecorder()
        let store = UsageQuotaOverviewStore(widgetHistory: sink)
        for (index, used) in [10.0, 20, 30].enumerated() {
            store.reconcile(accounts: [Self.account(
                id: "gemini-a", record: nil, providerID: "gemini",
                capturedAt: Self.now.addingTimeInterval(Double(index - 3) * 300),
                windows: [Self.window(used: used)])], now: Self.now)
        }
        // The Summary keeps its own verified history; only the widget export is withheld,
        // because the widget cannot tell a replaced account from the recorded one.
        #expect(store.overview(accounts: [Self.account(
            id: "gemini-a", record: nil, providerID: "gemini", capturedAt: Self.now.addingTimeInterval(-300),
            windows: [Self.window(used: 30)])], now: Self.now).lines.first?.localObservationCount == 3)
        #expect(!sink.exported.isEmpty)
        #expect(sink.exported.allSatisfy { $0.streams.isEmpty })
    }

    @Test
    func `a reading whose cycle length cannot be inferred keeps the cycle observed with the same reset`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        // Five days before the reset Grok's window reads as weekly; three days before, its
        // length can no longer be inferred, yet the reset date proves it is the same cycle.
        let readings: [(offset: TimeInterval, used: Double)] = [
            (-3 * 3600, 10), (-3600, 20), (2 * 86400, 30), (2 * 86400 + 3600, 40),
        ]
        for (offset, used) in readings {
            _ = try Self.publishMerged(
                Self.identityLessGrok(capturedAt: Self.now.addingTimeInterval(offset), used: used), into: store)
        }
        let late = Self.now.addingTimeInterval(2 * 86400 + 3600)
        let accounts = try Self.publishMerged(Self.identityLessGrok(capturedAt: late, used: 40), into: store)
        let line = try #require(store.overview(accounts: accounts, now: late).lines.first)
        #expect(line.localObservationCount == 4)
        #expect(line.observedSamples.map(\.remainingPercent) == [90, 80, 70, 60])
    }

    @Test
    func `promoting a legacy anonymous anchor clears its old unproven history without resetting settings`() throws {
        let weak = Self.weakAccount(capturedAt: Self.now, used: 30)
        let anchor = UsageAccountAnchor(
            id: "legacy-anonymous-anchor", providerID: "claude",
            tokens: UsageAccountIdentity.tokens(for: weak).sorted())
        let selection = UsageQuotaSelection(
            providerID: "claude", accountAnchorID: anchor.id, windowID: "primary", colorHex: "12ABEF")
        var archive = UsageQuotaArchive()
        archive.preferences.hasInitialized = true
        archive.preferences.accountAnchors = [anchor]
        archive.preferences.selections = [selection]
        archive.histories = [UsageQuotaHistory(binding: selection.binding, observations: (0..<3).map {
            UsageQuotaObservation(
                capturedAt: Self.now.addingTimeInterval(Double($0 - 3) * 300), usedPercent: Double($0 + 1) * 10,
                resetDate: Self.now.addingTimeInterval(3600), windowDuration: 18000)
        })]
        let memory = try UsageQuotaMemoryPersistence(data: JSONEncoder().encode(archive))
        let store = UsageQuotaOverviewStore(persistence: memory)
        #expect(!store.isReadOnly)
        let stable = Self.account(id: "named-owner", windows: [Self.window(used: 40)])
        store.reconcile(accounts: [stable], now: Self.now)
        let line = try #require(store.overview(accounts: [stable], now: Self.now).lines.first)
        #expect(line.currentRemainingPercent == 60)
        #expect(line.localObservationCount == 1)
        #expect(line.observedSamples.count == 1)
        #expect(store.preferences.selections == [selection])
        let saved = try JSONDecoder().decode(UsageQuotaArchive.self, from: #require(memory.data))
        let history = try #require(saved.histories.first)
        #expect(history.observations.count == 1)
        #expect(history.observations.first?.capturedAt == Self.now)
        #expect(history.stableAccountTokens == ["claude:account:named-owner"])
    }

    @Test
    func `persisted history needs the exact stable anchor owner while legacy settings remain readable`() throws {
        let account = Self.account()
        let stable = UsageAccountIdentity.tokens(for: account).filter(UsageAccountIdentity.isStable).sorted()
        let anchor = UsageAccountAnchor(
            id: UsageAccountIdentity.proposedAnchorID(for: account), providerID: "claude",
            tokens: UsageAccountIdentity.tokens(for: account).sorted())
        let selection = UsageQuotaSelection(
            providerID: "claude", accountAnchorID: anchor.id, windowID: "primary", colorHex: "12ABEF")
        for proof in [nil, stable, ["claude:account:someone-else"]] as [[String]?] {
            var archive = UsageQuotaArchive()
            archive.preferences.hasInitialized = true
            archive.preferences.accountAnchors = [anchor]
            archive.preferences.selections = [selection]
            archive.histories = [UsageQuotaHistory(
                binding: selection.binding, observations: [10.0, 15, 15, 20].enumerated().map {
                    UsageQuotaObservation(
                        capturedAt: Self.now.addingTimeInterval(Double($0.offset - 3) * 300), usedPercent: $0.element,
                        resetDate: Self.now.addingTimeInterval(3600), windowDuration: 18000)
                }, stableAccountTokens: proof)]
            let memory = try UsageQuotaMemoryPersistence(data: JSONEncoder().encode(archive))
            let store = UsageQuotaOverviewStore(persistence: memory)
            #expect(!store.isReadOnly)
            let before = try #require(store.overview(accounts: [account], now: Self.now).lines.first)
            #expect(before.currentRemainingPercent == 80)
            #expect(before.observedSamples.count == (proof == stable ? 4 : 1))
            #expect(before.localObservationCount == (proof == stable ? 4 : 0))
            #expect(store.preferences.selections == [selection])
            store.reconcile(accounts: [account], now: Self.now)
            let after = try #require(store.overview(accounts: [account], now: Self.now).lines.first)
            #expect(after.localObservationCount == (proof == stable ? 4 : 1))
            #expect(after.observedSamples.count == (proof == stable ? 4 : 1))
        }
        var preferences = UsageQuotaPreferences()
        preferences.accountAnchors = [anchor]
        #expect(!UsageQuotaProjection.hasUnambiguousHistorySource(
            account, anchorID: "another-anchor", preferences: preferences, linkages: []))
    }

    @Test
    func `the nearest weekly reset anchors six elapsed days even when its line is unselected`() throws {
        let account = Self.account(windows: [
            Self.window(reset: Self.now.addingTimeInterval(3600)),
            Self.window(id: "secondary", minutes: 10080, reset: Self.now.addingTimeInterval(3 * 86400)),
        ])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        let overview = store.overview(accounts: [account], now: Self.now)
        #expect(overview.start == Self.now.addingTimeInterval(-3 * 86400))
        #expect(overview.end == Self.now.addingTimeInterval(3 * 86400))
        #expect(overview.lines
            .allSatisfy { $0.observedSamples == [UsageQuotaPoint(date: Self.now, remainingPercent: 80)] })
        let weekly = try #require(overview.lines.first { $0.selection.windowID == "secondary" })
        store.remove(id: weekly.id)
        #expect(store.overview(accounts: [account], now: Self.now).end == Self.now.addingTimeInterval(3 * 86400))
    }

    @Test
    func `shared weekly window preserves different cycle balances at the same left boundary`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        let start = Self.now.addingTimeInterval(-4 * 86400)
        var accounts: [ProviderUsageSnapshot] = []
        for hour in 0...96 {
            let captured = start.addingTimeInterval(Double(hour) * 3600)
            accounts = [
                Self.account(providerID: "claude", capturedAt: captured, windows: [Self.window(
                    id: "secondary", used: 30 + Double(hour) * 10 / 96, minutes: 10080,
                    reset: Self.now.addingTimeInterval(2 * 86400))]),
                Self.account(id: "fictional-codex", providerID: "codex", capturedAt: captured, windows: [Self.window(
                    id: "secondary", used: Double(hour) * 20 / 96, minutes: 10080,
                    reset: Self.now.addingTimeInterval(3 * 86400))]),
            ]
            store.reconcile(accounts: accounts, now: captured)
        }
        let overview = store.overview(accounts: accounts, now: Self.now)
        #expect(overview.start == start)
        #expect(overview.end == Self.now.addingTimeInterval(2 * 86400))
        let claude = try #require(overview.lines.first { $0.selection.providerID == "claude" })
        let codex = try #require(overview.lines.first { $0.selection.providerID == "codex" })
        #expect(claude.observedSamples.first == UsageQuotaPoint(date: start, remainingPercent: 70))
        #expect(codex.observedSamples.first == UsageQuotaPoint(date: start, remainingPercent: 100))
        #expect(claude.observedSamples.last == UsageQuotaPoint(date: Self.now, remainingPercent: 60))
        #expect(codex.observedSamples.last == UsageQuotaPoint(date: Self.now, remainingPercent: 80))
        #expect(overview.lines.allSatisfy { $0.observedSamples.allSatisfy { $0.date <= Self.now } })
    }

    @Test
    func `nearest reset on the 25th produces seven dates from the 19th through the 25th`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let end = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 25, hour: 15)))
        let overview = UsageQuotaOverview(start: end.addingTimeInterval(-6 * 86400), end: end, lines: [])
        #expect(overview.end.timeIntervalSince(overview.start) == 6 * 86400)
        #expect(overview.dateTicks(calendar: calendar).map { calendar.component(.day, from: $0) } == [
            19, 20, 21, 22, 23, 24, 25,
        ])
        #expect(overview.dateTicks(calendar: calendar).first == overview.start)
        #expect(overview.dateTicks(calendar: calendar).last == overview.end)
    }

    @Test
    func `clock expiry switches to the next weekly reset before fresh data arrives`() {
        let nearestReset = Self.now.addingTimeInterval(30)
        let nextReset = Self.now.addingTimeInterval(2 * 86400)
        let nearest = Self.account(windows: [Self.window(
            id: "secondary", minutes: 10080, reset: nearestReset)])
        let other = Self.account(id: "fictional-codex", providerID: "codex", windows: [Self.window(
            id: "secondary", minutes: 10080, reset: nextReset)])
        let store = UsageQuotaOverviewStore.inMemory()
        let accounts = [nearest, other]
        store.reconcile(accounts: accounts, now: Self.now)
        #expect(store.overview(accounts: accounts, now: Self.now).end == nearestReset)
        // No reconciliation or network receipt: a TimelineView clock tick alone advances the axis.
        let expired = store.overview(accounts: accounts, now: nearestReset)
        #expect(expired.end == nextReset)
        #expect(expired.start == nextReset.addingTimeInterval(-6 * 86400))
        #expect(expired.lines.first { $0.selection.providerID == "claude" }?.observedSamples.isEmpty == true)
        let refreshed = Self.account(capturedAt: nearestReset, windows: [Self.window(
            id: "secondary", used: 0, minutes: 10080, reset: nearestReset.addingTimeInterval(7 * 86400))])
        store.reconcile(accounts: [refreshed, other], now: nearestReset)
        let overview = store.overview(accounts: [refreshed, other], now: nearestReset)
        #expect(overview.end == nextReset)
        #expect(overview.lines.first { $0.selection.providerID == "claude" }?.observedSamples == [
            UsageQuotaPoint(date: nearestReset, remainingPercent: 100),
        ])
    }

    @Test
    func `different users and unselected accounts determine their own nearest weekly boundary`() throws {
        let nearest = Self.account(id: "fictional-nearest", windows: [Self.window(
            id: "secondary", minutes: 10080, reset: Self.now.addingTimeInterval(86400))])
        let later = Self.account(id: "fictional-later", record: "install-later", windows: [Self.window(
            id: "secondary", minutes: 10080, reset: Self.now.addingTimeInterval(4 * 86400))])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [nearest, later], now: Self.now)
        let selected = try #require(store.overview(accounts: [nearest, later], now: Self.now).lines.first {
            $0.resetDate == Self.now.addingTimeInterval(86400)
        })
        store.remove(id: selected.id)
        #expect(store.overview(accounts: [later, nearest], now: Self.now).end == Self.now.addingTimeInterval(86400))
        let anotherUser = UsageQuotaOverviewStore.inMemory()
        anotherUser.reconcile(accounts: [later], now: Self.now)
        #expect(anotherUser.overview(accounts: [later], now: Self.now).end == Self.now.addingTimeInterval(4 * 86400))
    }

    @Test
    func `seven absolute ticks retain endpoints and spacing through daylight saving transitions`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        for (month, day) in [(11, 7), (3, 14)] {
            for hour in [0, 12, 23] {
                let end = try #require(calendar.date(from: DateComponents(
                    year: 2026, month: month, day: day, hour: hour, minute: 30)))
                let start = end.addingTimeInterval(-6 * 86400)
                let overview = UsageQuotaOverview(start: start, end: end, lines: [])
                let ticks = overview.dateTicks(calendar: calendar)
                #expect(ticks.count == 7)
                #expect(Set(ticks).count == 7)
                #expect(ticks.first == start)
                #expect(ticks.last == end)
                #expect(zip(ticks, ticks.dropFirst()).allSatisfy { $0.1.timeIntervalSince($0.0) == 86400 })
                #expect(overview.end.timeIntervalSince(overview.start) == 6 * 86400)
            }
        }
    }

    @Test
    func `a newly reset week can put current readings before the six day domain without moving samples`() throws {
        let reset = Self.now.addingTimeInterval(7 * 86400 - 60)
        let account = Self.account(windows: [Self.window(id: "secondary", minutes: 10080, reset: reset)])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        let overview = store.overview(accounts: [account], now: Self.now)
        #expect(overview.end == reset)
        #expect(overview.start == Self.now.addingTimeInterval(86400 - 60))
        #expect(overview.start > Self.now)
        let line = try #require(overview.lines.first)
        #expect(line.observedSamples == [UsageQuotaPoint(date: Self.now, remainingPercent: 80)])
    }

    @Test
    func `a weekly reset beyond seven days cannot hide all current observations`() {
        let account = Self.account(windows: [
            Self.window(id: "secondary", minutes: 10080, reset: Self.now.addingTimeInterval(7 * 86400 + 60)),
        ])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        let overview = store.overview(accounts: [account], now: Self.now)
        #expect(overview.end == Self.now)
        #expect(overview.start == Self.now.addingTimeInterval(-6 * 86400))
        #expect(overview.lines.allSatisfy { $0.observedSamples.allSatisfy { $0.date <= overview.end } })
    }

    @Test
    func `monthly and invalid distant weekly resets cannot move the weekly plot into the future`() {
        let goodReset = Self.now.addingTimeInterval(2 * 86400)
        let account = Self.account(windows: [
            Self.window(id: "secondary", minutes: 10080, reset: goodReset),
            Self.window(id: "monthly", minutes: 43200, reset: Self.now.addingTimeInterval(20 * 86400)),
            Self.window(id: "invalid-weekly", minutes: 10080, reset: Self.now.addingTimeInterval(20 * 86400)),
        ])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        #expect(store.overview(accounts: [account], now: Self.now).end == goodReset)
    }

    @Test
    func `one observed reading stays at its capture time without projecting exhaustion or a full quota start`() throws {
        let captured = Self.now.addingTimeInterval(-1800)
        let account = Self.account(capturedAt: captured, windows: [Self.window(used: 80)])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        let line = try #require(store.overview(accounts: [account], now: Self.now).lines.first)
        #expect(line.currentRemainingPercent == 20)
        #expect(line.observedAt == captured)
        #expect(line.observedSamples == [UsageQuotaPoint(date: captured, remainingPercent: 20)])
        let later = Self.now.addingTimeInterval(60)
        #expect(store.overview(accounts: [account], now: later).lines.first?.observedSamples == line.observedSamples)
    }

    @Test
    func `unknown blocked and stale windows cannot capture the nearest weekly boundary`() {
        let near = Self.now.addingTimeInterval(3600)
        let far = Self.now.addingTimeInterval(60)
        let valid = Self.account(windows: [
            Self.window(id: "secondary", minutes: 10080, reset: near),
            Self.window(id: "unknown", minutes: 10080, reset: far, known: false),
            Self.window(id: "blocked", minutes: 10080, reset: far, blocked: true),
        ])
        let stale = Self.account(
            id: "stale",
            record: "stale-install",
            capturedAt: Self.now.addingTimeInterval(-7 * 3600),
            windows: [Self.window(id: "secondary", minutes: 10080, reset: far)])
        let store = UsageQuotaOverviewStore.inMemory()
        store.reconcile(accounts: [valid, stale], now: Self.now)
        #expect(store.overview(accounts: [valid, stale], now: Self.now).end == near)
    }

    @Test
    func `missing duration is not given a fictitious curve and known zero is not unknown`() throws {
        let store = UsageQuotaOverviewStore.inMemory()
        let account = Self.account(windows: [Self.window(used: 0, minutes: nil)])
        store.reconcile(accounts: [account], now: Self.now)
        let line = try #require(store.overview(accounts: [account], now: Self.now).lines.first)
        #expect(line.state == .available)
        #expect(line.currentRemainingPercent == 100)
        #expect(line.observedSamples == [UsageQuotaPoint(date: Self.now, remainingPercent: 100)])
        let unknown = Self.account(windows: [Self.window(used: 0, known: false)])
        #expect(store.overview(accounts: [unknown], now: Self.now).lines.first?.currentRemainingPercent == nil)
        let expired = Self.account(windows: [Self.window(reset: Self.now.addingTimeInterval(-1))])
        #expect(store.overview(accounts: [expired], now: Self.now).lines.first?.state == .resetPassed)
        let blocked = Self.account(windows: [Self.window(blocked: true)])
        #expect(store.overview(accounts: [blocked], now: Self.now).lines.first?.state == .blocked)
    }

    @Test
    func `local samples persist but repeated reads and duplicate syncs do not manufacture observations`() throws {
        let memory = UsageQuotaMemoryPersistence()
        let store = UsageQuotaOverviewStore(persistence: memory)
        let account = Self.account()
        store.reconcile(accounts: [account], now: Self.now)
        let writes = memory.writes
        store.reconcile(accounts: [account], now: Self.now.addingTimeInterval(60))
        #expect(memory.writes == writes)
        _ = store.overview(accounts: [account], now: Self.now.addingTimeInterval(120))
        #expect(memory.writes == writes)
        let reopened = UsageQuotaOverviewStore(persistence: memory)
        let line = try #require(reopened.overview(accounts: [account], now: Self.now).lines.first)
        #expect(line.localObservationCount == 1)
    }

    @Test
    func `demo fixture is deterministic and cannot seed live persistence`() throws {
        let account = Self.account(windows: [Self.window(used: 30)])
        let live = UsageQuotaOverviewStore(persistence: UsageQuotaMemoryPersistence())
        live.reconcile(accounts: [account], now: Self.now)
        let demo1 = UsageQuotaOverviewStore.demo(accounts: [account], now: Self.now)
        let demo2 = UsageQuotaOverviewStore.demo(accounts: [account], now: Self.now)
        let first = try #require(demo1.overview(accounts: [account], now: Self.now).lines.first)
        let second = try #require(demo2.overview(accounts: [account], now: Self.now).lines.first)
        #expect(first.observedSamples.count > 1)
        #expect(first.observedSamples == second.observedSamples)
        #expect(live.overview(accounts: [account], now: Self.now).lines.first?.localObservationCount == 1)
    }

    @Test
    func `future and corrupt archives are readonly and preserved verbatim`() throws {
        var future = UsageQuotaArchive()
        future.preferences.schemaVersion = 999
        for data in try [Data("invalid json".utf8), JSONEncoder().encode(future)] {
            let memory = UsageQuotaMemoryPersistence(data: data)
            let store = UsageQuotaOverviewStore(persistence: memory)
            #expect(store.isReadOnly)
            store.reconcile(accounts: [Self.account()], now: Self.now)
            #expect(store.preferences.selections.isEmpty)
            #expect(memory.data == data)
            #expect(memory.writes == 0)
        }
    }
}

@MainActor
private final class UsageQuotaWidgetHistoryRecorder: UsageQuotaWidgetHistorySink {
    var exported: [WidgetLocalQuotaHistory] = []
    func export(_ history: WidgetLocalQuotaHistory) { self.exported.append(history) }
}

@MainActor
private final class UsageQuotaMemoryPersistence: UsageQuotaPersistence {
    var data: Data?
    var writes = 0
    init(data: Data? = nil) { self.data = data }
    func load() -> Data? { self.data }
    func save(_ data: Data) { self.data = data; self.writes += 1 }
}
