import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

@Suite("Summary metric bindings and local preferences")
@MainActor
struct SummaryCardTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(
        id: String = "primary", used: Double = 34, known: Bool = true,
        minutes: Int = 300, resetIn: TimeInterval? = 3600,
        blocked: Bool = false, placeholder: Bool = false) -> SyncRateWindow
    {
        SyncRateWindow(
            id: id, label: id == "secondary" ? "Weekly" : "Session", usedPercent: used,
            usageKnown: known, windowMinutes: minutes,
            resetsAt: resetIn.map { Self.now.addingTimeInterval($0) }, resetDescription: nil,
            isSyntheticPlaceholder: placeholder,
            blockingQuota: blocked ? SyncBlockingQuota(
                windowID: "weekly", rawUsedPercent: 100, rawResetsAt: self.now.addingTimeInterval(86400),
                rawResetDescription: nil, rawNextRegenPercent: nil) : nil)
    }

    private static func account(
        provider: String = "claude", identity: String = "fictional-account-a",
        email: String = "fictional-a@example.invalid", organization: String? = nil, record: String = "install-a",
        windows: [SyncRateWindow]? = nil, captured: Date? = nil,
        isError: Bool = false, balance: SyncProviderAmount? = nil,
        extra: SyncClaudeExtraUsage? = nil, confidence: String? = nil,
        identities: [String]? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: provider, providerName: provider.capitalized,
            primary: nil, secondary: nil, accountEmail: email, loginMethod: "Max 5x",
            statusMessage: nil, isError: isError, lastUpdated: captured ?? self.now.addingTimeInterval(-60),
            rateWindows: windows ?? [self.window(), self.window(id: "secondary", minutes: 10080, resetIn: 3 * 86400)],
            accountIdentities: identities ?? ["\(provider):account:\(identity)"],
            claudeExtraUsage: extra, usageDataConfidence: confidence,
            providerAmount: balance, accountRecordKey: record, accountOrganization: organization)
    }

    private static func only(
        _ metric: SummaryCardMetric, account: ProviderUsageSnapshot,
        store: SummaryPreferencesStore) throws -> SummaryResolvedCard
    {
        let candidate = try #require(store.catalog(accounts: [account], now: Self.now).first { $0.metric == metric })
        return store.resolve(candidate.configuration(), accounts: [account], now: Self.now)
    }

    @Test
    func `text card headings use provider names unless the user names them`() throws {
        let store = SummaryPreferencesStore.inMemory()
        let account = Self.account(organization: "Personal")
        store.reconcile(accounts: [account], now: Self.now)
        let cards = store.resolvedCards(accounts: [account], now: Self.now)
        #expect(cards.allSatisfy { $0.compactTitle == "Claude" })
        #expect(cards.allSatisfy { $0.accountTitle == "Claude Personal Max 5x" })
        var first = try #require(cards.first?.configuration)
        store.setAccountAlias("Work", accountAnchorID: first.accountAnchorID)
        first.title = "C 5x"
        store.update(first)
        let renamed = store.resolvedCards(accounts: [account], now: Self.now)
        #expect(renamed.first?.compactTitle == "C 5x")
        #expect(renamed.dropFirst().allSatisfy { $0.compactTitle == "Work" })
    }

    @Test
    func `provider headings omit automatic account details while bindings remain distinct`() {
        let store = SummaryPreferencesStore.inMemory()
        let first = Self.account(organization: "Work")
        let second = Self.account(
            identity: "fictional-account-b", email: "fictional-b@example.invalid", organization: "Work",
            record: "install-b")
        store.reconcile(accounts: [first, second], now: Self.now)
        let cards = store.resolvedCards(accounts: [first, second], now: Self.now)
        #expect(Set(cards.map(\.compactTitle)) == ["Claude"])
        #expect(Set(cards.map(\.accountTitle)).count == 2)
        #expect(Set(cards.map { SummaryPresentation.redact($0.accountTitle, enabled: true) }).count == 2)
        #expect(Set(cards.map(\.configuration.accountAnchorID)).count == 2)
        #expect(cards
            .allSatisfy { !SummaryPresentation.redact($0.compactTitle, enabled: true).contains("@example.invalid") })
        let privateNames = Set(cards.map { SummaryPresentation.redact($0.privateTitle, enabled: true) })
        #expect(privateNames == ["Claude"])
        let reversed = store.resolvedCards(accounts: [second, first], now: Self.now)
        #expect(Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.accountTitle) })
            == Dictionary(uniqueKeysWithValues: reversed.map { ($0.id, $0.accountTitle) }))
    }

    @Test
    func `initial empty sync waits for data and user empty board stays empty after relaunch`() throws {
        let persistence = MemoryPersistence()
        let store = SummaryPreferencesStore(persistence: persistence)
        store.reconcile(accounts: [], now: Self.now)
        #expect(!store.preferences.hasInitialized)
        let account = Self.account()
        store.reconcile(accounts: [account], now: Self.now)
        #expect(store.preferences.cards.count == 2)
        #expect(store.preferences.cards.allSatisfy { $0.color == .white })
        for card in store.preferences.cards {
            store.remove(id: card.id)
        }
        let reopened = SummaryPreferencesStore(persistence: persistence)
        reopened.reconcile(accounts: [account], now: Self.now)
        #expect(reopened.preferences.hasInitialized)
        #expect(reopened.preferences.cards.isEmpty)
        #expect(try JSONDecoder().decode(SummaryPreferences.self, from: #require(persistence.data)).hasInitialized)
    }

    @Test
    func `account rename and record flip retain card identity and alias`() throws {
        let store = SummaryPreferencesStore.inMemory()
        let original = Self.account()
        store.reconcile(accounts: [original], now: Self.now)
        let configuration = try #require(store.preferences.cards.first)
        store.setAccountAlias("C 5x", accountAnchorID: configuration.accountAnchorID)
        let renamed = Self.account(email: "renamed@example.invalid", record: "install-b")
        store.reconcile(accounts: [renamed], now: Self.now)
        let resolved = store.resolvedCards(accounts: [renamed], now: Self.now)
        #expect(resolved.first?.id == configuration.id)
        #expect(resolved.first?.state == .available)
        #expect(resolved.first?.accountTitle == "Claude C 5x Max 5x")
        #expect(resolved.first?.configuration.providerID == "claude")
        #expect(store.preferences.accountAnchors.count == 1)
    }

    @Test
    func `default titles retain complete email so privacy redaction can identify it`() {
        let account = Self.account(email: "fictional-private@example.invalid")
        let candidate = SummaryPreferencesStore.inMemory().catalog(accounts: [account], now: Self.now).first
        #expect(candidate?.accountTitle == "Claude fictional-private@example.invalid Max 5x")
    }

    @Test
    func `same label and reused record slot cannot rebind a card to another stable account`() {
        let store = SummaryPreferencesStore.inMemory()
        let original = Self.account()
        store.reconcile(accounts: [original], now: Self.now)
        let existingIDs = store.preferences.cards.map(\.id)
        let replacement = Self.account(identity: "fictional-account-b")
        store.reconcile(accounts: [replacement], now: Self.now)
        #expect(store.preferences.accountAnchors.count == 2)
        let unresolved = store.resolvedCards(accounts: [replacement], now: Self.now)
        #expect(unresolved.map(\.id) == existingIDs)
        #expect(unresolved.allSatisfy { $0.state == .missingAccount && $0.provider == nil })
        store.reconcile(accounts: [replacement, original], now: Self.now)
        #expect(store.resolvedCards(accounts: [replacement, original], now: Self.now)
            .allSatisfy { $0.state == .available })
    }

    @Test
    func `confirmed identity bridge keeps both existing card bindings while picker has one account`() {
        let store = SummaryPreferencesStore.inMemory()
        let first = Self.account()
        let second = Self.account(
            identity: "fictional-account-b",
            email: "fictional-b@example.invalid",
            record: "install-b")
        store.reconcile(accounts: [first, second], now: Self.now)
        let original = store.preferences.cards
        #expect(original.count == 4)
        let merged = Self.account(identities: [
            "claude:account:fictional-account-a",
            "claude:account:fictional-account-b",
        ])
        store.reconcile(accounts: [merged], now: Self.now)
        let resolved = store.resolvedCards(accounts: [merged], now: Self.now)
        #expect(resolved.count == 4)
        #expect(resolved.allSatisfy { $0.state == .available })
        #expect(resolved.map(\.configuration.accountAnchorID) == original.map(\.accountAnchorID))
        #expect(Set(store.catalog(accounts: [merged], now: Self.now).map(\.accountAnchorID)).count == 1)
        store.reconcile(accounts: [second], now: Self.now)
        let split = store.resolvedCards(accounts: [second], now: Self.now)
        #expect(split.prefix(2).allSatisfy { $0.state == .missingAccount })
        #expect(split.suffix(2).allSatisfy { $0.state == .available })
    }

    @Test
    func `latest-side explicit account link is reversible without rewriting either anchor identity`() {
        let store = SummaryPreferencesStore.inMemory()
        let first = Self.account()
        let second = Self.account(
            identity: "fictional-account-b",
            email: "fictional-b@example.invalid",
            record: "install-b")
        store.reconcile(accounts: [first, second], now: Self.now)
        let anchors = store.preferences.accountAnchors
        let link = ProviderAccountLinkage(
            providerID: "claude",
            linkedIdentifiers: ["claude:account:fictional-account-a", "claude:account:fictional-account-b"],
            confirmedFromDeviceID: "fictional-iphone")
        store.reconcile(accounts: [second], linkages: [link], now: Self.now)
        #expect(store.resolvedCards(accounts: [second], now: Self.now).allSatisfy { $0.state == .available })
        #expect(store.preferences.accountAnchors == anchors)
        let inverse = link.inverseUnmerge(confirmedFromDeviceID: "fictional-iphone")
        store.reconcile(accounts: [second], linkages: [link, inverse], now: Self.now)
        let split = store.resolvedCards(accounts: [second], now: Self.now)
        #expect(split.prefix(2).allSatisfy { $0.state == .missingAccount })
        #expect(split.suffix(2).allSatisfy { $0.state == .available })
        store.reconcile(accounts: [first, second], linkages: [link, inverse], now: Self.now)
        #expect(store.resolvedCards(accounts: [first, second], now: Self.now).allSatisfy { $0.state == .available })
        #expect(store.preferences.accountAnchors == anchors)
    }

    @Test
    func `explicit legacy linkage restores anonymous cards and unmerge removes that bridge`() throws {
        let store = SummaryPreferencesStore.inMemory()
        let legacy = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: Self.window(), secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false, lastUpdated: Self.now)
        store.reconcile(accounts: [legacy], now: Self.now)
        let original = try #require(store.preferences.cards.first)
        let named = Self.account()
        let link = ProviderAccountLinkage(
            providerID: "claude",
            linkedIdentifiers: ["claude:legacy-no-identity", "claude:account:fictional-account-a"],
            confirmedFromDeviceID: "fictional-iphone")
        store.reconcile(accounts: [named], linkages: [link], now: Self.now)
        #expect(store.resolve(original, accounts: [named], now: Self.now).state == .available)
        #expect(store.preferences.cards.first?.accountAnchorID == original.accountAnchorID)
        store.reconcile(
            accounts: [named],
            linkages: [link, link.inverseUnmerge(confirmedFromDeviceID: "fictional-iphone")],
            now: Self.now)
        #expect(store.resolve(original, accounts: [named], now: Self.now).state == .missingAccount)
        store.reconcile(accounts: [legacy, named], linkages: [], now: Self.now)
        #expect(store.resolve(original, accounts: [legacy, named], now: Self.now).provider?.accountEmail == nil)
    }

    @Test
    func `catalog retains every real window including unknown scoped windows and omits placeholders`() {
        let account = Self.account(windows: [
            Self.window(), Self.window(id: "secondary", minutes: 10080, resetIn: 3 * 86400),
            Self.window(id: "claude-weekly-scoped-fictional", known: false, minutes: 10080),
            Self.window(id: "fake-placeholder", placeholder: true),
        ])
        let store = SummaryPreferencesStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        let quotaIDs = store.catalog(accounts: [account], now: Self.now).compactMap { candidate -> String? in
            if case let .quota(windowID) = candidate.metric { return windowID }
            return nil
        }
        #expect(quotaIDs == ["primary", "secondary", "claude-weekly-scoped-fictional"])
        #expect(store.preferences.cards.count == 2)
    }

    @Test
    func `short session cannot invent depletion and weekly forecast uses capture time`() throws {
        let account = Self.account(windows: [
            Self.window(), Self.window(id: "secondary", used: 80, minutes: 10080, resetIn: 3 * 86400),
        ])
        let store = SummaryPreferencesStore.inMemory()
        store.reconcile(accounts: [account], now: Self.now)
        let catalog = store.catalog(accounts: [account], now: Self.now)
        #expect(!catalog.contains { $0.metric == .depletion(windowID: "primary") })
        let candidate = try #require(catalog.first { $0.metric == .depletion(windowID: "secondary") })
        let expected = QuotaPace(
            window: account.rateWindows[1], capturedAt: account.lastUpdated,
            referenceDate: Self.now, providerID: "claude")?.forecast
        let initial = store.resolve(candidate.configuration(), accounts: [account], now: Self.now)
        let later = store.resolve(
            candidate.configuration(),
            accounts: [account],
            now: Self.now.addingTimeInterval(3600))
        #expect(initial.forecast == expected)
        #expect(later.forecast == initial.forecast)
        #expect(initial.forecast != nil)
        let estimated = Self.account(provider: "opencodego", confidence: "estimated")
        #expect(!store.catalog(accounts: [estimated], now: Self.now).contains {
            if case .depletion = $0.metric {
                true
            } else {
                false
            }
        })
    }

    @Test
    func `lasts until reset is preserved rather than turned into a made up empty date`() throws {
        let account = Self.account(windows: [Self.window(id: "secondary", used: 1, minutes: 10080, resetIn: 86400)])
        let resolved = try Self.only(.depletion(windowID: "secondary"), account: account, store: .inMemory())
        guard case .lastsUntilReset = resolved.forecast else {
            Issue.record("Expected the existing forecast's lastsUntilReset semantic")
            return
        }
        #expect(resolved.state == .available)
    }

    @Test
    func `quota age and forecast follow source capture rather than newer envelope metadata`() throws {
        let captured = Self.now.addingTimeInterval(-7 * 3600)
        var account = Self.account(windows: [
            Self.window(id: "secondary", used: 80, minutes: 10080, resetIn: 3 * 86400),
        ])
        account.sourceReport = SyncProviderSourceReport(
            sourceDeviceID: "fictional-mac", sourceDeviceName: "Fictional Mac", sourceCapturedAt: captured,
            failures: [], deviceCount: 2)
        let resolved = try Self.only(.depletion(windowID: "secondary"), account: account, store: .inMemory())
        #expect(resolved.state == .stale)
        #expect(resolved.observedAt == captured)
        #expect(resolved.forecast == QuotaPace(
            window: account.rateWindows[0], capturedAt: captured, referenceDate: Self.now, providerID: "claude")?
            .forecast)
    }

    @Test
    func `unknown zero blocked expired stale and missing metric remain distinct`() throws {
        let store = SummaryPreferencesStore.inMemory()
        let knownZero = Self.account(windows: [Self.window(used: 0)])
        store.reconcile(accounts: [knownZero], now: Self.now)
        let configuration = try #require(store.preferences.cards.first)
        let zero = store.resolve(configuration, accounts: [knownZero], now: Self.now)
        #expect(zero.state == .available && zero.usedPercent == 0)
        let unknown = store.resolve(
            configuration,
            accounts: [Self.account(windows: [Self.window(used: 0, known: false)])],
            now: Self.now)
        #expect(unknown.state == .unknown && unknown.usedPercent == nil)
        let blocked = store.resolve(
            configuration,
            accounts: [Self.account(windows: [Self.window(blocked: true)])],
            now: Self.now)
        #expect(blocked.state == .blocked && blocked.usedPercent == nil)
        let expired = store.resolve(
            configuration,
            accounts: [Self.account(windows: [Self.window(resetIn: -1)])],
            now: Self.now)
        #expect(expired.state == .resetPassed && expired.usedPercent == nil)
        let stale = store.resolve(
            configuration,
            accounts: [Self.account(captured: Self.now.addingTimeInterval(-7 * 3600))],
            now: Self.now)
        #expect(stale.state == .stale && stale.isStale)
        let missing = store.resolve(configuration, accounts: [Self.account(windows: [])], now: Self.now)
        #expect(missing.state == .missingMetric)
        #expect(missing.configuration.metric == configuration.metric)
    }

    @Test
    func `balance freshness follows its own observation and spend is not a balance`() throws {
        let oldBalance = SyncProviderAmount(
            kind: "balance", amount: 0, currencyCode: "USD", period: nil, isEstimated: false,
            observedAt: Self.now.addingTimeInterval(-8 * 3600))
        let account = Self.account(balance: oldBalance)
        let resolved = try Self.only(.balance, account: account, store: .inMemory())
        #expect(resolved.state == .stale && resolved.isStale)
        #expect(resolved.amount?.value == 0)
        let spend = SyncProviderAmount(kind: "spend", amount: 99, currencyCode: "USD", period: nil, isEstimated: false)
        #expect(!SummaryPreferencesStore.inMemory().catalog(accounts: [Self.account(balance: spend)])
            .contains { $0.metric == .balance })
        let badValue = SyncProviderAmount(
            kind: "balance",
            amount: .nan,
            currencyCode: "USD",
            period: nil,
            isEstimated: false)
        let unknown = try Self.only(.balance, account: Self.account(balance: badValue), store: .inMemory())
        #expect(unknown.state == .unknown && unknown.amount == nil)
    }

    @Test
    func `countdown is per card and safely falls back when reset disappears`() throws {
        let store = SummaryPreferencesStore.inMemory()
        let account = Self.account()
        store.reconcile(accounts: [account], now: Self.now)
        var card = try #require(store.preferences.cards.first)
        card.emphasis = .countdown
        card.color = .purple
        card.title = "C 5x"
        store.update(card)
        let selected = store.resolve(card, accounts: [account], now: Self.now)
        #expect(selected.effectiveEmphasis == .countdown)
        let resetGone = Self.account(windows: [Self.window(resetIn: nil)])
        let fallback = store.resolve(card, accounts: [resetGone], now: Self.now)
        #expect(fallback.effectiveEmphasis == .percent)
        #expect(fallback.configuration.emphasis == .countdown)
        #expect(fallback.title == "C 5x")
        let aliased = store.resolve(card, accounts: [account], accountAlias: "Preview account", now: Self.now)
        #expect(aliased.accountTitle == "Claude Preview account Max 5x")
        #expect(store.preferences.accountAliases.isEmpty)
        #expect(store.preferences.cards[1].color == .white)
        #expect(store.preferences.cards[1].emphasis == .percent)
    }

    @Test
    func `reordering a filtered provider preserves the other providers cards`() {
        let store = SummaryPreferencesStore.inMemory()
        let accounts = [Self.account(), Self.account(provider: "codex")]
        store.reconcile(accounts: accounts, now: Self.now)
        let original = store.preferences.cards
        #expect(original.count == 4)
        store.move(id: original[3].id, before: original[2].id)
        #expect(store.preferences.cards.map(\.id) == [original[0].id, original[1].id, original[3].id, original[2].id])
        #expect(store.preferences.cards.filter { $0.providerID == "claude" } == Array(original.prefix(2)))
        store.reorder(ids: [original[1].id, original[0].id, original[1].id, UUID()])
        #expect(store.preferences.cards.map(\.id) == [original[1].id, original[0].id, original[3].id, original[2].id])
    }

    @Test
    func `disabled extra usage does not fabricate a percentage`() throws {
        let extra = SyncClaudeExtraUsage(
            utilization: nil, monthlySpendUSD: nil, monthlyLimitUSD: nil, isEnabled: false,
            planTier: nil, updatedAt: Self.now)
        let resolved = try Self.only(.extraUsage, account: Self.account(extra: extra), store: .inMemory())
        #expect(resolved.state == .disabled)
        #expect(resolved.usedPercent == nil && resolved.amount == nil)
    }

    @Test
    func `newer or corrupted stored preferences stay byte for byte intact`() throws {
        for data in try [Data("not json".utf8), JSONEncoder().encode(Self.futurePreferences())] {
            let persistence = MemoryPersistence(data: data)
            let store = SummaryPreferencesStore(persistence: persistence)
            #expect(store.isReadOnly)
            store.reconcile(accounts: [Self.account()], now: Self.now)
            store.setAccountAlias("temporary", accountAnchorID: "anything")
            #expect(persistence.data == data)
            #expect(persistence.saveCount == 0)
        }
    }

    @Test
    func `legacy Summary preferences keep metrics aliases and order without automatically adding a chart`() throws {
        let original = SummaryPreferencesStore.inMemory()
        original.reconcile(accounts: [Self.account()], now: Self.now)
        let anchor = try #require(original.preferences.cards.first?.accountAnchorID)
        original.setAccountAlias("Personal", accountAnchorID: anchor)
        let data = try JSONEncoder().encode(original.preferences)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "quotaModule")
        let persistence = try MemoryPersistence(data: JSONSerialization.data(withJSONObject: legacy))
        let restored = SummaryPreferencesStore(persistence: persistence)
        #expect(!restored.isReadOnly)
        #expect(restored.preferences.quotaModule == nil)
        #expect(restored.preferences.cards == original.preferences.cards)
        #expect(restored.preferences.accountAliases == original.preferences.accountAliases)
        #expect(restored.preferences.orderedItemIDs == original.preferences.cards.map(\.id))
    }

    @Test
    func `quota module is opt in persistent removable and sortable alongside metrics`() throws {
        let persistence = MemoryPersistence()
        let store = SummaryPreferencesStore(persistence: persistence)
        store.reconcile(accounts: [Self.account(), Self.account(provider: "codex")], now: Self.now)
        let cards = store.preferences.cards
        store.addQuotaModule()
        let module = try #require(store.preferences.quotaModule)
        store.addQuotaModule()
        #expect(store.preferences.quotaModule == module)
        #expect(store.preferences.orderedItemIDs.last == module.id)
        let order = [cards[0].id, module.id] + cards.dropFirst().map(\.id)
        store.reorderItems(ids: order)
        #expect(store.preferences.orderedItemIDs == order)
        let restored = SummaryPreferencesStore(persistence: persistence)
        #expect(restored.preferences == store.preferences)
        restored.removeItem(id: cards[0].id)
        #expect(restored.preferences.orderedItemIDs.first == module.id)
        restored.removeItem(id: module.id)
        #expect(restored.preferences.quotaModule == nil)
        #expect(restored.preferences.cards == Array(cards.dropFirst()))
        let reopened = SummaryPreferencesStore(persistence: persistence)
        reopened.reconcile(accounts: [Self.account()], now: Self.now)
        #expect(reopened.preferences.quotaModule == nil)
    }

    @Test
    func `filtered module reordering preserves unlisted cards and rejects unknown duplicate ids`() throws {
        let store = SummaryPreferencesStore.inMemory()
        store.reconcile(accounts: [Self.account(), Self.account(provider: "codex")], now: Self.now)
        store.addQuotaModule()
        let module = try #require(store.preferences.quotaModule)
        let ids = store.preferences.cards.map(\.id)
        store.reorderItems(ids: [module.id, ids[0], module.id, UUID()])
        #expect(store.preferences.orderedItemIDs == [module.id, ids[1], ids[2], ids[3], ids[0]])
    }

    @Test
    func `four tile chart packs alongside two rows of Duo cards and spans compact phone width`() {
        let duo = SummaryModulePacking.placements(modules: [true, false, false, false, false], columns: 4)
        #expect(duo[0] == .init(row: 0, column: 0, columns: 2, rows: 2))
        #expect(duo[1] == .init(row: 0, column: 2, columns: 1, rows: 1))
        #expect(duo[4] == .init(row: 1, column: 3, columns: 1, rows: 1))
        let phone = SummaryModulePacking.placements(modules: [true, false], columns: 2)
        #expect(phone[1].row == 2)
        let accessible = SummaryModulePacking.placements(modules: [true, false], columns: 1)
        #expect(accessible == [
            .init(row: 0, column: 0, columns: 1, rows: 1),
            .init(row: 1, column: 0, columns: 1, rows: 1),
        ])
    }

    @Test
    func `a chart between two phone cards preserves the requested visual order without backfilling`() {
        let positions = SummaryModulePacking.placements(modules: [false, true, false], columns: 2)
        #expect(positions == [
            .init(row: 0, column: 0, columns: 1, rows: 1),
            .init(row: 1, column: 0, columns: 2, rows: 2),
            .init(row: 3, column: 0, columns: 1, rows: 1),
        ])
    }

    @Test(arguments: [2, 3, 4])
    func `mixed module layouts preserve monotonic reading order and never overlap`(columns: Int) {
        for modules in [
            [false, true, false, false, false],
            [false, false, false, true, false, true, false],
            [true, false, false, false, false, true],
        ] {
            let positions = SummaryModulePacking.placements(modules: modules, columns: columns)
            let starts = positions.map { $0.row * columns + $0.column }
            #expect(zip(starts, starts.dropFirst()).allSatisfy { $0.0 < $0.1 })
            var cells = Set<Int>()
            for position in positions {
                #expect(position.column + position.columns <= columns)
                for dy in 0..<position.rows {
                    for dx in 0..<position.columns {
                        #expect(cells.insert((position.row + dy) * columns + position.column + dx).inserted)
                    }
                }
            }
        }
    }

    @Test
    func `Summary columns use available width independently of split view and respect short height`() {
        #expect(SummaryModulePacking.columnCount(width: 390, shortHeight: false, accessibility: false) == 2)
        #expect(SummaryModulePacking.columnCount(width: 668, shortHeight: false, accessibility: false) == 3)
        #expect(SummaryModulePacking.columnCount(width: 952, shortHeight: false, accessibility: false) == 4)
        #expect(SummaryModulePacking.columnCount(width: 844, shortHeight: true, accessibility: false) == 2)
        #expect(SummaryModulePacking.columnCount(width: 952, shortHeight: false, accessibility: true) == 1)
    }

    private static func futurePreferences() -> SummaryPreferences {
        var preferences = SummaryPreferences()
        preferences.schemaVersion = 999
        return preferences
    }
}

@MainActor
private final class MemoryPersistence: SummaryPreferencesPersistence {
    var data: Data?
    var saveCount = 0
    init(data: Data? = nil) { self.data = data }
    func load() -> Data? { self.data }
    func save(_ data: Data) { self.data = data; self.saveCount += 1 }
}
