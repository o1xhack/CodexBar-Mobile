import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Research/064 — Usage card expansion, pins and ordering for iOS 2.5.0.
@Suite("Usage card ordering and preferences")
struct UsageCardOrderingTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(period: SyncRateWindowPeriod? = nil, minutes: Int?, resetIn hours: Double?)
        -> SyncRateWindow
    {
        SyncRateWindow(
            label: nil,
            usedPercent: 10,
            windowMinutes: minutes,
            period: period,
            resetsAt: hours.map { Self.now.addingTimeInterval($0 * 3600) },
            resetDescription: nil)
    }

    private static func snapshot(
        _ providerID: String,
        name: String? = nil,
        email: String? = nil,
        identities: [String]? = nil,
        recordKey: String? = nil,
        weeklyResetIn hours: Double? = nil) -> ProviderUsageSnapshot
    {
        let windows = hours.map { [Self.window(minutes: 10080, resetIn: $0)] } ?? []
        return ProviderUsageSnapshot(
            providerID: providerID,
            providerName: name ?? providerID.capitalized,
            primary: nil,
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.now,
            rateWindows: windows,
            accountIdentities: identities,
            accountRecordKey: recordKey)
    }

    private static func descriptor(_ key: String, _ name: String, reset: Double? = nil, secondary: String = "")
        -> UsageCardSortDescriptor
    {
        UsageCardSortDescriptor(
            key: key,
            name: name,
            secondaryName: secondary,
            weeklyResetAt: reset.map { Self.now.addingTimeInterval($0 * 3600) })
    }

    private static let sample = [
        descriptor("provider:codex", "Codex", reset: 50),
        descriptor("provider:claude", "Claude", reset: 10),
        descriptor("provider:openrouter", "OpenRouter"),
        descriptor("provider:antigravity", "Antigravity", reset: 30),
        descriptor("provider:zai", "z.ai"),
    ]

    // MARK: Default rules

    @Test
    func `upgrade default keeps the Mac source order`() {
        let result = UsageCardOrdering.arrange(Self.sample, preferences: UsageCardPreferences())
        #expect(result.pinned.isEmpty)
        #expect(result.others == Self.sample.map(\.key))
    }

    @Test
    func `name A to Z and Z to A sort each section independently`() {
        var preferences = UsageCardPreferences()
        preferences.usesDefaultSort = true
        preferences.pinnedCardKeys = ["provider:zai", "provider:codex"]
        preferences.defaultSortRule = .alphabeticalAscending
        var result = UsageCardOrdering.arrange(Self.sample, preferences: preferences)
        #expect(result.pinned == ["provider:codex", "provider:zai"])
        #expect(result.others == ["provider:antigravity", "provider:claude", "provider:openrouter"])

        preferences.defaultSortRule = .alphabeticalDescending
        result = UsageCardOrdering.arrange(Self.sample, preferences: preferences)
        #expect(result.pinned == ["provider:zai", "provider:codex"])
        #expect(result.others == ["provider:openrouter", "provider:claude", "provider:antigravity"])
    }

    @Test
    func `weekly reset puts the soonest first and cards without a reset last by name`() {
        var preferences = UsageCardPreferences()
        preferences.usesDefaultSort = true
        preferences.defaultSortRule = .weeklyReset
        let result = UsageCardOrdering.arrange(Self.sample, preferences: preferences)
        #expect(result.others == [
            "provider:claude", "provider:antigravity", "provider:codex",
            "provider:openrouter", "provider:zai",
        ])
    }

    @Test
    func `equal names fall back to account label then source order`() {
        var preferences = UsageCardPreferences()
        preferences.usesDefaultSort = true
        let cards = [
            Self.descriptor("account:b", "Codex", secondary: "work"),
            Self.descriptor("account:a", "Codex", secondary: "personal"),
            Self.descriptor("account:c", "Codex", secondary: "personal"),
        ]
        for rule in UsageDefaultSortRule.allCases {
            preferences.defaultSortRule = rule
            let result = UsageCardOrdering.arrange(cards, preferences: preferences)
            #expect(result.others == ["account:a", "account:c", "account:b"])
        }
    }

    @Test
    func `weekly reset detection uses period first and the 7 day window otherwise`() {
        #expect(UsageCardOrdering.isWeekly(Self.window(period: .weekly, minutes: nil, resetIn: 1)))
        #expect(!UsageCardOrdering.isWeekly(Self.window(period: .monthly, minutes: 10080, resetIn: 1)))
        #expect(UsageCardOrdering.isWeekly(Self.window(minutes: 10080, resetIn: 1)))
        #expect(!UsageCardOrdering.isWeekly(Self.window(minutes: 300, resetIn: 1)))
    }

    @Test
    func `a weekly reset in the past rolls forward to the next week`() {
        let stale = Self.snapshot("codex", weeklyResetIn: -24)
        let next = UsageCardOrdering.weeklyResetDate(for: stale, now: Self.now)
        #expect(next == Self.now.addingTimeInterval(6 * 24 * 3600))
        #expect(UsageCardOrdering.weeklyResetDate(for: Self.snapshot("openrouter"), now: Self.now) == nil)
    }

    @Test
    func `refreshed reset times re-sort the weekly order`() {
        var preferences = UsageCardPreferences()
        preferences.usesDefaultSort = true
        preferences.defaultSortRule = .weeklyReset
        let before = [Self.descriptor("provider:a", "A", reset: 10), Self.descriptor("provider:b", "B", reset: 20)]
        let after = [Self.descriptor("provider:a", "A", reset: 170), Self.descriptor("provider:b", "B", reset: 20)]
        #expect(UsageCardOrdering.arrange(before, preferences: preferences).others == ["provider:a", "provider:b"])
        #expect(UsageCardOrdering.arrange(after, preferences: preferences).others == ["provider:b", "provider:a"])
    }

    // MARK: Manual order and pins

    @Test
    func `manual order places unseen cards after ordered ones in source order`() {
        var preferences = UsageCardPreferences()
        preferences.manualOrder = ["provider:zai", "provider:claude", "provider:gone"]
        let result = UsageCardOrdering.arrange(Self.sample, preferences: preferences)
        #expect(result.others == [
            "provider:zai", "provider:claude", "provider:codex", "provider:openrouter", "provider:antigravity",
        ])
    }

    @Test
    func `pinning in manual mode moves the card to the top and unpinning to the top of the rest`() {
        var preferences = UsageCardPreferences()
        let displayed = Self.sample.map(\.key)
        preferences.setPinned(true, cardKey: "provider:openrouter", displayedOrder: displayed)
        preferences.setPinned(
            true,
            cardKey: "provider:zai",
            displayedOrder: UsageCardOrdering
                .arrange(Self.sample, preferences: preferences).all)
        var result = UsageCardOrdering.arrange(Self.sample, preferences: preferences)
        #expect(result.pinned == ["provider:zai", "provider:openrouter"])
        #expect(result.others == ["provider:codex", "provider:claude", "provider:antigravity"])

        preferences.setPinned(false, cardKey: "provider:openrouter", displayedOrder: result.all)
        result = UsageCardOrdering.arrange(Self.sample, preferences: preferences)
        #expect(result.pinned == ["provider:zai"])
        #expect(result.others.first == "provider:openrouter")
    }

    @Test
    func `pinning in default mode only changes the section`() {
        var preferences = UsageCardPreferences()
        preferences.usesDefaultSort = true
        preferences.setPinned(true, cardKey: "provider:zai", displayedOrder: Self.sample.map(\.key))
        #expect(preferences.manualOrder.isEmpty)
        #expect(UsageCardOrdering.arrange(Self.sample, preferences: preferences).pinned == ["provider:zai"])
    }

    @Test
    func `switching to manual starts from the visible default order and keeps offline cards`() {
        var preferences = UsageCardPreferences()
        preferences.manualOrder = ["provider:offline"]
        preferences.usesDefaultSort = true
        preferences.defaultSortRule = .alphabeticalDescending
        let visible = UsageCardOrdering.arrange(Self.sample, preferences: preferences).all
        preferences.setUsesDefaultSort(false, displayedOrder: visible)
        #expect(!preferences.usesDefaultSort)
        #expect(preferences.manualOrder == visible + ["provider:offline"])
        #expect(UsageCardOrdering.arrange(Self.sample, preferences: preferences).all == visible)
    }

    @Test
    func `editing sections stores pinned then others and keeps unseen keys`() {
        var preferences = UsageCardPreferences()
        preferences.usesDefaultSort = true
        preferences.manualOrder = ["provider:offline", "provider:codex"]
        preferences.pinnedCardKeys = ["provider:claude"]
        preferences.setManualOrder(pinned: ["provider:claude"], others: ["provider:zai", "provider:codex"])
        #expect(!preferences.usesDefaultSort)
        #expect(preferences.manualOrder == ["provider:claude", "provider:zai", "provider:codex", "provider:offline"])
    }

    // MARK: Expansion migration

    @Test
    func `expanding hands the provider pin and slot to its accounts`() {
        var preferences = UsageCardPreferences()
        preferences.pinnedCardKeys = ["provider:codex"]
        preferences.manualOrder = ["provider:claude", "provider:codex", "provider:zai"]
        preferences.setExpanded(true, providerID: "codex", accountKeys: ["account:a", "account:b"])
        #expect(preferences.isExpanded("codex"))
        #expect(preferences.pinnedCardKeys == ["account:a", "account:b"])
        #expect(preferences.manualOrder == ["provider:claude", "account:a", "account:b", "provider:zai"])
    }

    @Test
    func `collapsing gives the provider card the first account slot and any pin`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        preferences.accountAnchors = [
            UsageAccountAnchor(id: "a", providerID: "codex", tokens: ["codex:email:a"]),
            UsageAccountAnchor(id: "b", providerID: "codex", tokens: ["codex:email:b"]),
            UsageAccountAnchor(id: "offline", providerID: "codex", tokens: ["codex:email:c"]),
        ]
        preferences.pinnedCardKeys = ["account:b"]
        preferences.manualOrder = ["provider:claude", "account:b", "provider:zai", "account:a", "account:offline"]
        preferences.setExpanded(false, providerID: "codex", accountKeys: ["account:a", "account:b"])
        #expect(!preferences.isExpanded("codex"))
        #expect(preferences.pinnedCardKeys == ["provider:codex"])
        #expect(preferences.manualOrder == ["provider:claude", "provider:codex", "provider:zai"])
    }

    @Test
    func `expand then collapse restores the provider card without manual history`() {
        var preferences = UsageCardPreferences()
        preferences.setExpanded(true, providerID: "codex", accountKeys: ["account:a"])
        preferences.setExpanded(false, providerID: "codex", accountKeys: ["account:a"])
        #expect(preferences == {
            var expected = UsageCardPreferences()
            expected.expandedProviderIDs = []
            return expected
        }())
    }

    // MARK: Account anchors

    @Test
    func `builder renders one card per account only for expanded providers`() {
        let groups = [
            Self.snapshot("codex", email: "a@x.com", identities: ["codex:email:a@x.com"], recordKey: "r1"),
            Self.snapshot("codex", email: "b@x.com", identities: ["codex:email:b@x.com"], recordKey: "r2"),
            Self.snapshot("claude", email: "c@x.com"),
            Self.snapshot("claude", email: "d@x.com"),
        ].groupedByProvider()
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        preferences.reconcileAnchors(groups: groups)
        let cards = UsageCardBuilder.cards(groups: groups, preferences: preferences)
        #expect(cards.map(\.id) == ["account:codex|r1", "account:codex|r2", "provider:claude"])
        #expect(cards.map(\.accountOrdinal) == [1, 2, nil])
        #expect(cards[0].detailGroup.accounts.count == 1)
        #expect(cards[2].detailGroup.accounts.count == 2)
    }

    @Test
    func `card keys survive a record key flip from another Mac`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        let macA = [Self.snapshot("codex", email: "a@x.com", identities: ["codex:email:a@x.com"], recordKey: "mac-a")]
        preferences.reconcileAnchors(groups: macA.groupedByProvider())
        let before = UsageCardBuilder.cards(groups: macA.groupedByProvider(), preferences: preferences).map(\.id)

        let macB = [Self.snapshot("codex", email: "a@x.com", identities: ["codex:email:a@x.com"], recordKey: "mac-b")]
        let after = UsageCardBuilder.cards(groups: macB.groupedByProvider(), preferences: preferences).map(\.id)
        #expect(before == after)
        preferences.reconcileAnchors(groups: macB.groupedByProvider())
        #expect(preferences.accountAnchors.count == 1)
        #expect(preferences.accountAnchors[0].tokens.contains("codex:record:mac-b"))
    }

    @Test
    func `card keys survive a renamed label and a new account`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["openai"]
        let original = [
            Self.snapshot("openai", email: "Admin", recordKey: "uuid-1"),
            Self.snapshot("openai", email: "Billing", recordKey: "uuid-2"),
        ]
        preferences.reconcileAnchors(groups: original.groupedByProvider())
        let keys = UsageCardBuilder.cards(groups: original.groupedByProvider(), preferences: preferences).map(\.id)

        let renamed = [
            Self.snapshot("openai", email: "New Hire", recordKey: "uuid-3"),
            Self.snapshot("openai", email: "Billing 2", recordKey: "uuid-2"),
            Self.snapshot("openai", email: "Admin Renamed", recordKey: "uuid-1"),
        ]
        let renamedKeys = UsageCardBuilder.cards(groups: renamed.groupedByProvider(), preferences: preferences)
            .map(\.id)
        #expect(renamedKeys[1] == keys[1])
        #expect(renamedKeys[2] == keys[0])
        #expect(!keys.contains(renamedKeys[0]))
    }

    @Test
    func `two accounts never share an anchor and the best overlap wins`() {
        var preferences = UsageCardPreferences()
        preferences.accountAnchors = [
            // Stale anchor that once saw both accounts while they were linked.
            UsageAccountAnchor(id: "merged", providerID: "codex", tokens: ["codex:email:a", "codex:email:b"]),
            UsageAccountAnchor(id: "b-own", providerID: "codex", tokens: ["codex:email:b", "codex:record:rb"]),
        ]
        let accounts = [
            Self.snapshot("codex", identities: ["codex:email:b"], recordKey: "rb"),
            Self.snapshot("codex", identities: ["codex:email:a"]),
        ]
        #expect(preferences.anchorIDs(forAccounts: accounts) == ["b-own", "merged"])
    }

    @Test
    func `accounts without any identity still get distinct keys`() {
        let preferences = UsageCardPreferences()
        let ids = preferences.anchorIDs(forAccounts: [
            Self.snapshot("legacy"),
            Self.snapshot("legacy"),
        ])
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    @Test
    func `a reused record slot with a different account does not inherit the old card`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        let before = [Self.snapshot("codex", identities: ["codex:email:a"], recordKey: "slot-1")]
        preferences.reconcileAnchors(groups: before.groupedByProvider())
        preferences.pinnedCardKeys = ["account:codex|slot-1"]
        let after = [Self.snapshot("codex", identities: ["codex:email:b"], recordKey: "slot-1")]
        let ids = preferences.anchorIDs(forAccounts: after)
        #expect(ids == ["codex|slot-1#2"])
        #expect(!preferences.isPinned(UsageCardKey.account(anchorID: ids[0])))
    }

    @Test
    func `global matching lets a later account keep its better anchor`() {
        var preferences = UsageCardPreferences()
        preferences.accountAnchors = [
            UsageAccountAnchor(id: "shared", providerID: "codex", tokens: ["codex:email:a", "codex:record:r1"]),
            UsageAccountAnchor(id: "first", providerID: "codex", tokens: ["codex:email:x"]),
        ]
        let accounts = [
            // Weak record overlap with "shared", no stable identity of its own.
            Self.snapshot("codex", recordKey: "r1"),
            Self.snapshot("codex", identities: ["codex:email:a"], recordKey: "r1"),
        ]
        let ids = preferences.anchorIDs(forAccounts: accounts)
        #expect(ids[1] == "shared")
        #expect(ids[0] != "shared")
    }

    @Test
    func `a confirmed linkage folds the legacy card into the named card with its pin`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        preferences.accountAnchors = [
            UsageAccountAnchor(id: "legacy", providerID: "codex", tokens: ["codex:record:L"]),
            UsageAccountAnchor(id: "named", providerID: "codex", tokens: ["codex:email:a", "codex:record:R"]),
        ]
        preferences.pinnedCardKeys = ["account:legacy"]
        preferences.manualOrder = ["account:legacy", "provider:claude", "account:named"]
        // After the merge the latest values happen to come from the legacy Mac.
        let merged = [Self.snapshot("codex", identities: ["codex:email:a"], recordKey: "L")]
        #expect(preferences.anchorIDs(forAccounts: merged) == ["named"])
        preferences.reconcileAnchors(groups: merged.groupedByProvider())
        #expect(preferences.accountAnchors.map(\.id) == ["named"])
        #expect(preferences.pinnedCardKeys == ["account:named"])
        #expect(preferences.manualOrder == ["account:named", "provider:claude"])
    }

    @Test
    func `collapsing does not promote the pin of an account that is gone`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        preferences.accountAnchors = [
            UsageAccountAnchor(id: "a", providerID: "codex", tokens: ["codex:email:a"]),
            UsageAccountAnchor(id: "gone", providerID: "codex", tokens: ["codex:email:gone"]),
        ]
        preferences.pinnedCardKeys = ["account:gone"]
        preferences.setExpanded(false, providerID: "codex", accountKeys: ["account:a"])
        #expect(!preferences.isPinned("provider:codex"))
    }

    @Test
    func `stable identities outrank shared record slots`() {
        #expect(UsageAccountIdentity.score(
            account: ["c:email:a", "c:record:1"],
            anchor: ["c:email:a"]) == 110)
        #expect(UsageAccountIdentity.score(
            account: ["c:account:x", "c:record:1"],
            anchor: ["c:account:x", "c:record:1"]) == 101)
        #expect(UsageAccountIdentity.score(
            account: ["c:email:a", "c:record:1"],
            anchor: ["c:email:b", "c:record:1"]) == 0)
        #expect(UsageAccountIdentity.score(account: ["c:record:1"], anchor: ["c:email:b", "c:record:1"]) == 1)
    }

    @Test
    func `unmerge on an account card only targets a linkage of that account`() {
        let groups = [
            Self.snapshot("codex", identities: ["codex:email:a"], recordKey: "ra"),
            Self.snapshot("codex", identities: ["codex:email:b"], recordKey: "rb"),
        ].groupedByProvider()
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        let cards = UsageCardBuilder.cards(groups: groups, preferences: preferences)
        let linkage = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iphone")
        let linkages = ["codex": [linkage]]
        #expect(UsageCardPresentation.activeLinkage(for: cards[0], in: linkages) == linkage)
        #expect(UsageCardPresentation.activeLinkage(for: cards[1], in: linkages) == nil)

        preferences.expandedProviderIDs = []
        let providerCard = UsageCardBuilder.cards(groups: groups, preferences: preferences)[0]
        #expect(UsageCardPresentation.activeLinkage(for: providerCard, in: linkages) == linkage)
    }

    @Test
    func `a confirmed linkage absorbs an identity-less legacy card even when the named Mac is newer`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        preferences.accountAnchors = [
            UsageAccountAnchor(id: "codex|", providerID: "codex", tokens: ["codex:card:codex|"]),
            UsageAccountAnchor(id: "named", providerID: "codex", tokens: ["codex:email:a", "codex:record:R"]),
        ]
        preferences.pinnedCardKeys = ["account:codex|"]
        let merged = [Self.snapshot("codex", identities: ["codex:email:a"], recordKey: "R")]
        // Without the linkage nothing ties the legacy anchor to the account.
        var withoutLinkage = preferences
        withoutLinkage.reconcileAnchors(groups: merged.groupedByProvider())
        #expect(withoutLinkage.accountAnchors.count == 2)

        let linkage = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iphone")
        preferences.reconcileAnchors(groups: merged.groupedByProvider(), linkages: [linkage])
        #expect(preferences.accountAnchors.map(\.id) == ["named"])
        #expect(preferences.pinnedCardKeys == ["account:named"])

        // An unmerge record does not absorb anything.
        var unmerged = withoutLinkage
        let inverse = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: linkage.linkedIdentifiers,
            confirmedFromDeviceID: "iphone",
            unmerge: true)
        unmerged.reconcileAnchors(groups: merged.groupedByProvider(), linkages: [inverse])
        #expect(unmerged.accountAnchors.count == 2)
    }

    @Test
    func `a personal email match beats a shared workspace identity`() {
        let preferences = {
            var value = UsageCardPreferences()
            value.accountAnchors = [UsageAccountAnchor(
                id: "a",
                providerID: "codex",
                tokens: ["codex:account:X", "codex:email:a"])]
            return value
        }()
        let accounts = [
            // c joined workspace X; a moved to workspace Y.
            Self.snapshot("codex", identities: ["codex:account:X", "codex:email:c"]),
            Self.snapshot("codex", identities: ["codex:account:Y", "codex:email:a"]),
        ]
        let ids = preferences.anchorIDs(forAccounts: accounts)
        #expect(ids[1] == "a")
        #expect(ids[0] != "a")
    }

    @Test
    func `revoked linkages and offline label accounts are never absorbed`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        preferences.accountAnchors = [
            UsageAccountAnchor(id: "codex|", providerID: "codex", tokens: ["codex:card:codex|"]),
            UsageAccountAnchor(id: "named", providerID: "codex", tokens: ["codex:email:a"]),
            // A label-fallback token account on a Mac that is offline now.
            UsageAccountAnchor(id: "label", providerID: "codex", tokens: ["codex:record:T"]),
        ]
        preferences.pinnedCardKeys = ["account:codex|", "account:label"]
        let merge = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iphone")
        let revoke = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: merge.linkedIdentifiers,
            confirmedFromDeviceID: "iphone",
            unmerge: true)
        let named = [Self.snapshot("codex", identities: ["codex:email:a"])]

        var revoked = preferences
        revoked.reconcileAnchors(groups: named.groupedByProvider(), linkages: [merge, revoke])
        #expect(revoked.accountAnchors.count == 3)
        #expect(UsageCardLinkages.effective([merge, revoke]).isEmpty)

        preferences.reconcileAnchors(groups: named.groupedByProvider(), linkages: [merge])
        #expect(preferences.accountAnchors.map(\.id).sorted() == ["label", "named"])
        #expect(preferences.pinnedCardKeys == ["account:named", "account:label"])
    }

    @Test
    func `the legacy card itself never absorbs other anchors through the placeholder`() {
        var preferences = UsageCardPreferences()
        preferences.expandedProviderIDs = ["codex"]
        preferences.accountAnchors = [
            UsageAccountAnchor(id: "offline", providerID: "codex", tokens: ["codex:email:z"]),
        ]
        let merge = ProviderAccountLinkage(
            providerID: "codex",
            linkedIdentifiers: ["codex:email:a", "codex:legacy-no-identity"],
            confirmedFromDeviceID: "iphone")
        let legacyOnly = [Self.snapshot("codex")]
        preferences.reconcileAnchors(groups: legacyOnly.groupedByProvider(), linkages: [merge])
        #expect(preferences.accountAnchors.contains { $0.id == "offline" })
    }

    // MARK: Persistence

    @MainActor
    private static func makeDefaults() -> UserDefaults {
        let name = "UsageCardOrderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test @MainActor
    func `store persists every change and reloads it`() {
        let defaults = Self.makeDefaults()
        let store = UsageCardPreferencesStore(defaults: defaults)
        let groups = [
            Self.snapshot("codex", email: "a@x.com", recordKey: "r1"),
            Self.snapshot("codex", email: "b@x.com", recordKey: "r2"),
        ].groupedByProvider()
        store.setExpanded(true, group: groups[0])
        store.setPinned(true, cardKey: "account:codex|r2", displayedOrder: ["account:codex|r1", "account:codex|r2"])
        store.setUsesDefaultSort(true, displayedOrder: [])
        store.setDefaultSortRule(.weeklyReset)

        let reloaded = UsageCardPreferencesStore(defaults: defaults).preferences
        #expect(reloaded == store.preferences)
        #expect(reloaded.isExpanded("codex"))
        #expect(reloaded.accountAnchors.map(\.id) == ["codex|r1", "codex|r2"])
        #expect(reloaded.isPinned("account:codex|r2"))
        #expect(reloaded.defaultSortRule == .weeklyReset)
    }

    @Test @MainActor
    func `in memory demo store never touches user defaults`() {
        let store = UsageCardPreferencesStore.inMemory()
        store.setUsesDefaultSort(true, displayedOrder: [])
        #expect(store.preferences.usesDefaultSort)
        #expect(UsageCardPreferencesStore.inMemory().preferences == UsageCardPreferences())
    }

    @Test @MainActor
    func `corrupt data and unknown rules fall back to defaults`() {
        let defaults = Self.makeDefaults()
        defaults.set(Data("not json".utf8), forKey: UsageCardPreferencesStore.defaultsKey)
        #expect(UsageCardPreferencesStore(defaults: defaults).preferences == UsageCardPreferences())

        let partial = #"{"schemaVersion":1,"usesDefaultSort":true,"defaultSortRule":"byColor"}"#
        defaults.set(Data(partial.utf8), forKey: UsageCardPreferencesStore.defaultsKey)
        let loaded = UsageCardPreferencesStore(defaults: defaults).preferences
        #expect(loaded.usesDefaultSort)
        #expect(loaded.defaultSortRule == .alphabeticalAscending)
        #expect(loaded.manualOrder.isEmpty)
    }

    @Test @MainActor
    func `a newer schema is ignored and never overwritten`() {
        let defaults = Self.makeDefaults()
        let future = Data(#"{"schemaVersion":99,"usesDefaultSort":true,"futureField":[1,2]}"#.utf8)
        defaults.set(future, forKey: UsageCardPreferencesStore.defaultsKey)
        let store = UsageCardPreferencesStore(defaults: defaults)
        #expect(store.preferences == UsageCardPreferences())
        store.setDefaultSortRule(.weeklyReset)
        #expect(store.preferences.defaultSortRule == .weeklyReset)
        #expect(defaults.data(forKey: UsageCardPreferencesStore.defaultsKey) == future)
    }
}
