import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// One Mac cannot refresh a provider (e.g. no browser session) while another Mac has real data.
@Suite("Multi-Mac failure fallback")
struct MultiMacFailureFallbackTests {
    private let now = Date(timeIntervalSince1970: 1_791_600_000)

    private func observation(
        _ provider: String = "museai",
        used: Double = 21,
        capturedAt: Date,
        email: String? = nil,
        isError: Bool = false,
        details: [SyncProviderDetailSection] = [SyncProviderDetailSection(
            title: "Credits",
            rows: [.init(label: "Left", value: "79")])]) -> ProviderUsageSnapshot
    {
        let window = SyncRateWindow(
            id: "primary", label: "Weekly", usedPercent: used, windowMinutes: 10080,
            resetsAt: capturedAt.addingTimeInterval(86400), resetDescription: nil)
        return ProviderUsageSnapshot(
            providerID: provider,
            providerName: "Muse (muse.ai)",
            primary: window,
            secondary: nil,
            accountEmail: email,
            loginMethod: "Power",
            statusMessage: isError ? "Cookie access needs browser permission." : nil,
            isError: isError,
            lastUpdated: capturedAt,
            rateWindows: [window],
            details: details)
    }

    private func failure(_ provider: String = "museai", at date: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: provider,
            providerName: "Muse (muse.ai)",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: "Separate cookie access needs browser permission. Use Refresh.",
            isError: true,
            lastUpdated: date)
    }

    private func device(_ name: String, _ providers: [ProviderUsageSnapshot], at date: Date) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(providers: providers, syncTimestamp: date, deviceName: name, deviceID: name)
    }

    private func merged(_ devices: [SyncedUsageSnapshot]) throws -> [ProviderUsageSnapshot] {
        var results: [[ProviderUsageSnapshot]] = []
        for ordered in [devices, Array(devices.reversed())] {
            results.append(try #require(ProviderSnapshotMerger.mergeSnapshots(ordered)).providers)
        }
        #expect(results[0] == results[1], "merge must not depend on device order")
        return results[0]
    }

    @Test func `a newer failure-only entry does not replace another Mac's data`() throws {
        let studio = self.device("Mac Studio", [self.observation(capturedAt: self.now.addingTimeInterval(-600))],
                                 at: self.now.addingTimeInterval(-600))
        let macbook = self.device("MacBook Pro", [self.failure(at: self.now)], at: self.now)
        let providers = try self.merged([studio, macbook])
        let card = try #require(providers.first)
        #expect(providers.count == 1)
        #expect(card.primary?.usedPercent == 21)
        #expect(card.isError == false)
        #expect(card.statusMessage == nil)
        #expect(card.loginMethod == "Power")
        #expect(card.details.first?.rows.first?.value == "79")
        #expect(card.lastUpdated == self.now.addingTimeInterval(-600))

        let status = try #require(ProviderSourceStatus.resolve(provider: card))
        #expect(status.sourceDeviceName == "Mac Studio")
        #expect(status.newerFailures.map(\.deviceName) == ["MacBook Pro"])
        #expect(status.newerFailures.first?.message?.contains("browser permission") == true)
        #expect(status.allFailed == false)
        #expect(status.needsNotice(at: self.now))
    }

    @Test func `very old data stays visible but is flagged as stale next to a fresh failure`() throws {
        let old = self.now.addingTimeInterval(-3 * 86400)
        let studio = self.device("Mac Studio", [self.observation(capturedAt: old)], at: old)
        let macbook = self.device("MacBook Pro", [self.failure(at: self.now)], at: self.now)
        let card = try #require(try self.merged([studio, macbook]).first)
        #expect(card.primary?.usedPercent == 21)
        let status = try #require(ProviderSourceStatus.resolve(provider: card))
        #expect(status.isStale(at: self.now))
        let content = try #require(ProviderSourceNoticeContent(status: status, now: self.now, locale: Locale(identifier: "en")))
        #expect(content.isWarning)
        #expect(content.title == "Showing data from another Mac")
        #expect(content.lines.count == 2)
        #expect(content.lines[0].text.contains("Mac Studio"))
        #expect(content.lines[0].text.contains("3 days ago"))
        #expect(content.lines[1].text.contains("MacBook Pro"))
        #expect(content.lines[1].detail?.contains("browser permission") == true)
    }

    @Test func `the newest real observation wins over older data kept with an error`() throws {
        let studio = self.device(
            "Mac Studio",
            [self.observation(used: 30, capturedAt: self.now.addingTimeInterval(-120))],
            at: self.now.addingTimeInterval(-120))
        let macbook = self.device(
            "MacBook Pro",
            [self.observation(used: 5, capturedAt: self.now.addingTimeInterval(-7200), isError: true)],
            at: self.now)
        let card = try #require(try self.merged([studio, macbook]).first)
        #expect(card.primary?.usedPercent == 30)
        #expect(card.isError == false)
        let status = try #require(ProviderSourceStatus.resolve(provider: card))
        #expect(status.sourceDeviceName == "Mac Studio")
        #expect(status.newerFailures.map(\.deviceName) == ["MacBook Pro"])
    }

    @Test func `when every Mac fails the newest failure is shown`() throws {
        let studio = self.device("Mac Studio", [self.failure(at: self.now.addingTimeInterval(-60))],
                                 at: self.now.addingTimeInterval(-60))
        let macbook = self.device("MacBook Pro", [self.failure(at: self.now)], at: self.now)
        let providers = try self.merged([studio, macbook])
        let card = try #require(providers.first)
        #expect(providers.count == 1)
        #expect(card.isError)
        #expect(card.primary == nil)
        let status = try #require(ProviderSourceStatus.resolve(provider: card))
        #expect(status.allFailed)
        #expect(Set(status.newerFailures.map(\.deviceName)) == ["Mac Studio", "MacBook Pro"])
        let content = try #require(ProviderSourceNoticeContent(status: status, now: self.now, locale: Locale(identifier: "en")))
        #expect(content.title == "No Mac could refresh this provider")
    }

    @Test func `an identity-less failure does not become a second account next to an observed account`() throws {
        let studio = self.device(
            "Mac Studio",
            [self.observation("cursor", capturedAt: self.now.addingTimeInterval(-300), email: "fixture@example.invalid")],
            at: self.now.addingTimeInterval(-300))
        let macbook = self.device("MacBook Pro", [self.failure("cursor", at: self.now)], at: self.now)
        let providers = try self.merged([studio, macbook])
        #expect(providers.count == 1)
        #expect(providers.first?.accountEmail == "fixture@example.invalid")
        #expect(providers.first?.isError == false)
        #expect([providers.first].compactMap(\.self).groupedByProvider().first?.accounts.count == 1)
        let account = try #require(providers.first)
        let status = try #require(ProviderSourceStatus.resolve(provider: account))
        #expect(status.newerFailures.map(\.deviceName) == ["MacBook Pro"])
    }

    @Test func `a single Mac failure keeps today's error card`() throws {
        let macbook = self.device("MacBook Pro", [self.failure(at: self.now)], at: self.now)
        let card = try #require(try self.merged([macbook]).first)
        #expect(card.isError)
        #expect(card.statusMessage?.contains("browser permission") == true)
    }

    @Test func `fresh single-Mac data needs no notice and the card says nothing extra`() throws {
        let studio = self.device("Mac Studio", [self.observation(capturedAt: self.now.addingTimeInterval(-60))],
                                 at: self.now.addingTimeInterval(-60))
        let card = try #require(try self.merged([studio]).first)
        let status = try #require(ProviderSourceStatus.resolve(provider: card))
        #expect(status.needsNotice(at: self.now) == false)
        #expect(ProviderSourceNoticeContent(status: status, now: self.now) == nil)
        #expect(status.newerFailures.isEmpty)
    }

    @Test func `older failures than the shown data are not reported`() throws {
        let studio = self.device("Mac Studio", [self.observation(capturedAt: self.now)], at: self.now)
        let macbook = self.device("MacBook Pro", [self.failure(at: self.now.addingTimeInterval(-3600))],
                                  at: self.now.addingTimeInterval(-3600))
        let card = try #require(try self.merged([studio, macbook]).first)
        let status = try #require(ProviderSourceStatus.resolve(provider: card))
        #expect(status.newerFailures.isEmpty)
        #expect(status.needsNotice(at: self.now) == false)
    }

    @Test func `different providers and accounts are unaffected`() throws {
        let studio = self.device("Mac Studio", [
            self.observation(capturedAt: self.now.addingTimeInterval(-60)),
            self.observation("claude", used: 40, capturedAt: self.now.addingTimeInterval(-60), email: "a@example.invalid"),
        ], at: self.now.addingTimeInterval(-60))
        let macbook = self.device("MacBook Pro", [
            self.failure(at: self.now),
            self.observation("claude", used: 10, capturedAt: self.now, email: "b@example.invalid"),
        ], at: self.now)
        let providers = try self.merged([studio, macbook])
        #expect(providers.filter { $0.providerID == "claude" }.count == 2)
        #expect(providers.first { $0.providerID == "museai" }?.primary?.usedPercent == 21)
    }

    @Test func `notice text is localized in four languages`() throws {
        let studio = self.device("Mac Studio", [self.observation(capturedAt: self.now.addingTimeInterval(-600))],
                                 at: self.now.addingTimeInterval(-600))
        let macbook = self.device("MacBook Pro", [self.failure(at: self.now)], at: self.now)
        let card = try #require(try self.merged([studio, macbook]).first)
        let status = try #require(ProviderSourceStatus.resolve(provider: card))
        for (language, title) in [
            ("en", "Showing data from another Mac"),
            ("zh-Hans", "正在显示另一台 Mac 的数据"),
            ("zh-Hant", "正在顯示另一台 Mac 的資料"),
            ("ja", "別の Mac のデータを表示しています"),
        ] {
            let content = try #require(ProviderSourceNoticeContent(
                status: status, now: self.now, locale: Locale(identifier: language)))
            #expect(content.title == title, "\(language)")
            #expect(content.lines.allSatisfy { !$0.text.contains("%@") }, "\(language)")
        }
    }

    @Test @MainActor
    func `a Mac still reporting an error keeps its older data past the identity-less TTL`() {
        let fresh = self.observation("codex", capturedAt: self.now, email: "fixture@example.invalid")
        let keptWithError = self.observation(capturedAt: self.now.addingTimeInterval(-2 * 3600), isError: true)
        let ghost = self.observation("perplexity", capturedAt: self.now.addingTimeInterval(-2 * 3600))
        let kept = SnapshotCache.dropOrphansAndStale(["a": fresh, "b": keptWithError, "c": ghost])
        #expect(kept["a"] != nil)
        #expect(kept["b"] != nil, "an actively reported error is not a ghost record")
        #expect(kept["c"] == nil, "a silent identity-less record lagging 30 min is still a ghost")
    }

    private func costSummary(_ cost: Double) -> SyncCostSummary {
        SyncCostSummary(
            sessionCostUSD: nil, sessionTokens: nil, last30DaysCostUSD: cost, last30DaysTokens: 10,
            daily: [SyncDailyPoint(dayKey: "2026-10-07", costUSD: cost, totalTokens: 10)])
    }

    @Test func `an absorbed failure still contributes its Mac's local costs`() throws {
        var studioClaude = self.observation(
            "claude", capturedAt: self.now.addingTimeInterval(-300), email: "fixture@example.invalid")
        studioClaude = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: studioClaude.primary, secondary: nil,
            accountEmail: "fixture@example.invalid", loginMethod: "Max", statusMessage: nil, isError: false,
            lastUpdated: studioClaude.lastUpdated, costSummary: self.costSummary(10),
            rateWindows: studioClaude.rateWindows)
        let macbookFailure = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: nil, secondary: nil, accountEmail: nil,
            loginMethod: nil, statusMessage: "OAuth token unavailable", isError: true, lastUpdated: self.now,
            costSummary: self.costSummary(5))
        #expect(ProviderSnapshotMerger.isFailureOnly(macbookFailure))
        let providers = try self.merged([
            self.device("Mac Studio", [studioClaude], at: self.now.addingTimeInterval(-300)),
            self.device("MacBook Pro", [macbookFailure], at: self.now),
        ])
        let card = try #require(providers.first)
        #expect(providers.count == 1)
        #expect(card.isError == false)
        #expect(card.costSummary?.daily.first?.costUSD == 15)
        #expect(card.sourceReport?.failures.first?.message == "OAuth token unavailable")
    }

    @Test func `a provider-level cost envelope or a mock does not hide a real provider's failure`() throws {
        let failure = self.failure("openrouter", at: self.now)
        let envelope = ProviderUsageSnapshot(
            providerID: "openrouter", providerName: "OpenRouter", primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: "Management", statusMessage: nil, isError: false,
            lastUpdated: self.now, costSummary: self.costSummary(3),
            accountRecordKey: ProviderUsageSnapshot.openRouterManagementCostRecordKey)
        #expect(envelope.isProviderLevelCostEnvelope)
        let providers = try self.merged([self.device("MacBook Pro", [failure, envelope], at: self.now)])
        #expect(providers.contains { $0.providerID == "openrouter" && $0.isError && !$0.isProviderLevelCostEnvelope })

        let mock = self.observation(capturedAt: self.now.addingTimeInterval(-60), email: "alice-mock@example.test")
        let withMock = try self.merged([
            self.device("Mac Studio", [mock], at: self.now.addingTimeInterval(-60)),
            self.device("MacBook Pro", [self.failure(at: self.now)], at: self.now),
        ])
        #expect(withMock.contains { $0.isError }, "a mock account must not absorb the real failure")
    }

    @Test func `one physical Mac's alias collapse keeps its newest failure`() throws {
        let retired = self.device(
            "Mac Studio (old)", [self.observation(capturedAt: self.now.addingTimeInterval(-3 * 86400))],
            at: self.now.addingTimeInterval(-3 * 86400))
        let current = self.device("Mac Studio", [self.failure(at: self.now)], at: self.now)
        let collapsed = try #require(ProviderSnapshotMerger.mergeSnapshots(
            [retired, current], sumLocalCostsAcrossDevices: false, prefersObservationsOverFailures: false))
        #expect(collapsed.providers.count == 1)
        #expect(collapsed.providers.first?.isError == true)
        #expect(collapsed.providers.first?.sourceReport == nil)
    }

    @Test func `a confirmed linkage reports the Mac whose data the card shows`() throws {
        let studio = self.device(
            "Mac Studio",
            [self.observation("cursor", used: 50, capturedAt: self.now.addingTimeInterval(-7200), email: "x@example.invalid")],
            at: self.now.addingTimeInterval(-7200))
        let macbook = self.device(
            "MacBook Pro",
            [self.observation("cursor", used: 12, capturedAt: self.now.addingTimeInterval(-60))],
            at: self.now.addingTimeInterval(-60))
        let linkage = ProviderAccountLinkage(
            providerID: "cursor",
            linkedIdentifiers: ["cursor:email:x@example.invalid", "cursor:legacy-no-identity"],
            confirmedAt: self.now,
            confirmedFromDeviceID: "iphone")
        let merged = try #require(ProviderSnapshotMerger.mergeSnapshots([studio, macbook], linkages: [linkage]))
        let card = try #require(merged.providers.first { $0.providerID == "cursor" })
        #expect(merged.providers.filter { $0.providerID == "cursor" }.count == 1)
        #expect(card.primary?.usedPercent == 12)
        #expect(card.sourceReport?.sourceDeviceName == "MacBook Pro")
        #expect(card.sourceReport?.failures.isEmpty == true)
    }

    @Test func `old data alone is informational and a lone Mac failure adds no notice`() throws {
        let old = self.now.addingTimeInterval(-8 * 3600)
        let studio = self.device("Mac Studio", [self.observation(capturedAt: old)], at: old)
        let staleCard = try #require(try self.merged([studio]).first)
        let stale = try #require(ProviderSourceStatus.resolve(provider: staleCard))
        #expect(stale.needsNotice(at: self.now))
        #expect(stale.isWarning == false)

        let lone = self.device("MacBook Pro", [self.failure(at: self.now)], at: self.now)
        let loneCard = try #require(try self.merged([lone]).first)
        let lonely = try #require(ProviderSourceStatus.resolve(provider: loneCard))
        #expect(lonely.allFailed)
        #expect(lonely.needsNotice(at: self.now) == false)
    }
}
