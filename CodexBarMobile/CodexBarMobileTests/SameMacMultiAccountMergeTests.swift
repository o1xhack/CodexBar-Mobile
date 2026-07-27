// swiftlint:disable multiline_arguments
import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// iOS-side merge tests for the R1+R2 same-Mac multi-account scenario:
/// when **one** Mac pushes multiple `ProviderUsageSnapshot`s for the same
/// provider but different `accountEmail`s (Codex multi-managed-account or
/// token-based multi-account expansion), `CloudSyncReader.mergeSnapshots`
/// must preserve them as distinct entries — no collapse.
///
/// Pre-existing `CloudKitMergeTests` covers cross-Mac cases (one account
/// per Mac). This file fills the **same-Mac multi-account gap** introduced
/// by R1+R2, plus combined cross-Mac × multi-account scenarios.
///
/// See `Research/020-multi-account-comprehensive.md` R5 §D.
@Suite
struct SameMacMultiAccountMergeTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeProvider(
        id: String,
        name: String? = nil,
        email: String?,
        lastUpdated: Date? = nil,
        usedPercent: Double = 50.0,
        accountIdentities: [String]? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name ?? id.capitalized,
            primary: SyncRateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            accountEmail: email,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated ?? self.baseDate,
            accountIdentities: accountIdentities)
    }

    private func makeSnapshot(
        deviceName: String,
        deviceID: String,
        providers: [ProviderUsageSnapshot]) -> SyncedUsageSnapshot
    {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: providers.map(\.lastUpdated).max() ?? self.baseDate,
            deviceName: deviceName,
            deviceID: deviceID)
    }

    // MARK: - Same Mac, multiple accounts, same provider

    @Test("R5 D1: Single Mac with 2 Codex accounts (different emails) → 2 distinct merged cards")
    func singleMacTwoCodexAccountsKeptDistinct() throws {
        let alice = self.makeProvider(
            id: "codex", email: "alice@example.com",
            usedPercent: 25,
            accountIdentities: ["codex:email:alice%40example.com"])
        let bob = self.makeProvider(
            id: "codex", email: "bob@example.com",
            usedPercent: 75,
            accountIdentities: ["codex:email:bob%40example.com"])
        let mac = self.makeSnapshot(
            deviceName: "Mac mini", deviceID: "uuid-mini",
            providers: [alice, bob])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.count == 2, "same Mac, 2 codex accounts → 2 cards")
        let emails = Set(merged.providers.compactMap(\.accountEmail))
        #expect(emails == ["alice@example.com", "bob@example.com"])
        let percents = Set(merged.providers.compactMap(\.primary?.usedPercent))
        #expect(percents == [25, 75], "each account's usedPercent preserved")
    }

    @Test("R5 D2: Single Mac with 3 Codex accounts → 3 distinct merged cards")
    func singleMacThreeCodexAccountsKeptDistinct() throws {
        let providers = (1 ... 3).map { i in
            self.makeProvider(
                id: "codex", email: "user\(i)@example.com",
                usedPercent: Double(i) * 20,
                accountIdentities: ["codex:email:user\(i)%40example.com"])
        }
        let mac = self.makeSnapshot(
            deviceName: "Mac Studio", deviceID: "uuid-studio",
            providers: providers)

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.count == 3, "same Mac, 3 codex accounts → 3 cards")
        let emails = Set(merged.providers.compactMap(\.accountEmail))
        #expect(emails == [
            "user1@example.com", "user2@example.com", "user3@example.com",
        ])
    }

    @Test("R5 D3: Single Mac, mixed Codex (multi) + Claude (multi) preserved by provider")
    func singleMacMixedProviderMultiAccountPreserved() throws {
        let codexA = self.makeProvider(
            id: "codex", email: "alice@codex.com",
            accountIdentities: ["codex:email:alice%40codex.com"])
        let codexB = self.makeProvider(
            id: "codex", email: "bob@codex.com",
            accountIdentities: ["codex:email:bob%40codex.com"])
        let claudeC = self.makeProvider(
            id: "claude", email: "carol@claude.com",
            accountIdentities: ["claude:email:carol%40claude.com"])
        let claudeD = self.makeProvider(
            id: "claude", email: "dave@claude.com",
            accountIdentities: ["claude:email:dave%40claude.com"])
        let mac = self.makeSnapshot(
            deviceName: "MacBook Pro", deviceID: "uuid-pro",
            providers: [codexA, codexB, claudeC, claudeD])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.count == 4)
        let codexEmails = Set(
            merged.providers.filter { $0.providerID == "codex" }
                .compactMap(\.accountEmail))
        let claudeEmails = Set(
            merged.providers.filter { $0.providerID == "claude" }
                .compactMap(\.accountEmail))
        #expect(codexEmails == ["alice@codex.com", "bob@codex.com"])
        #expect(claudeEmails == ["carol@claude.com", "dave@claude.com"])
    }

    // MARK: - Cross-Mac × multi-account combinations

    @Test("R5 D4: Mac-A 2 codex + Mac-B 1 codex (no overlap) → 3 distinct cards")
    func crossMacMultiAccountDistinctEmails() throws {
        let alice = self.makeProvider(
            id: "codex", email: "alice@x.com",
            accountIdentities: ["codex:email:alice%40x.com"])
        let bob = self.makeProvider(
            id: "codex", email: "bob@x.com",
            accountIdentities: ["codex:email:bob%40x.com"])
        let carol = self.makeProvider(
            id: "codex", email: "carol@x.com",
            accountIdentities: ["codex:email:carol%40x.com"])
        let macA = self.makeSnapshot(
            deviceName: "Mac A", deviceID: "uuid-a", providers: [alice, bob])
        let macB = self.makeSnapshot(
            deviceName: "Mac B", deviceID: "uuid-b", providers: [carol])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 3)
        let emails = Set(merged.providers.compactMap(\.accountEmail))
        #expect(emails == ["alice@x.com", "bob@x.com", "carol@x.com"])
    }

    @Test("R5 D5: Mac-A 2 codex + Mac-B same alice + new dave → 3 cards (alice deduped)")
    func crossMacMultiAccountWithOverlap() throws {
        // Both Mac-A and Mac-B have alice. Mac-A also has bob. Mac-B
        // also has dave. iOS should merge alice across Macs (1 card)
        // and keep bob, dave distinct (2 cards). Total 3 cards.
        let aliceFromA = self.makeProvider(
            id: "codex", email: "alice@x.com",
            lastUpdated: self.baseDate,
            usedPercent: 30,
            accountIdentities: ["codex:email:alice%40x.com"])
        let bob = self.makeProvider(
            id: "codex", email: "bob@x.com",
            accountIdentities: ["codex:email:bob%40x.com"])
        let aliceFromB = self.makeProvider(
            id: "codex", email: "alice@x.com",
            lastUpdated: self.baseDate.addingTimeInterval(60),
            usedPercent: 35,
            accountIdentities: ["codex:email:alice%40x.com"])
        let dave = self.makeProvider(
            id: "codex", email: "dave@x.com",
            accountIdentities: ["codex:email:dave%40x.com"])
        let macA = self.makeSnapshot(
            deviceName: "Mac A", deviceID: "uuid-a",
            providers: [aliceFromA, bob])
        let macB = self.makeSnapshot(
            deviceName: "Mac B", deviceID: "uuid-b",
            providers: [aliceFromB, dave])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 3, "alice deduped across Macs; bob + dave distinct")
        let emails = Set(merged.providers.compactMap(\.accountEmail))
        #expect(emails == ["alice@x.com", "bob@x.com", "dave@x.com"])
    }

    @Test("R5 D6: Mixed-version Macs — both share accountEmail merge into single card")
    func mixedVersionMacsMergeByEmail() throws {
        // Both Macs run modern code (post-Build 23) and emit
        // accountIdentities for Tier-A providers. They merge via the
        // shared `codex:email:alice%40x.com` identifier.
        //
        // The "really old Mac without accountIdentities" + new Mac
        // scenario is documented in `AccountIdentityMergeTests §8.7`:
        // legacy email synthesis on iOS uses the same normalization
        // form, so they merge correctly. Here we verify the simpler
        // both-modern case so this test is independent of legacy
        // synthesis details (which are tested in §8.7).
        let aliceA = self.makeProvider(
            id: "codex", email: "alice@x.com",
            lastUpdated: self.baseDate,
            accountIdentities: ["codex:email:alice%40x.com"])
        let aliceB = self.makeProvider(
            id: "codex", email: "alice@x.com",
            lastUpdated: self.baseDate.addingTimeInterval(120),
            accountIdentities: ["codex:email:alice%40x.com"])
        let macA = self.makeSnapshot(
            deviceName: "Mac A", deviceID: "uuid-a", providers: [aliceA])
        let macB = self.makeSnapshot(
            deviceName: "Mac B", deviceID: "uuid-b", providers: [aliceB])

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(
            merged.providers.count == 1,
            "alice on both Macs (sharing accountIdentities) merges to 1 card")
    }

    // MARK: - Edge cases

    @Test("R5 D7: Same Mac, 2 codex accounts both with nil email → fall to legacy bucket distinct?")
    func sameMacTwoNilEmailAccountsBehavior() throws {
        // Edge case: 2 codex entries both with accountEmail=nil from same
        // Mac. With no accountIdentities either, both fall to the
        // "legacy-no-identity" bucket. CurrentSyncReader policy: per
        // §8.10 of Research/019, all-legacy with nil email = single
        // shared bucket, so they would COLLAPSE. This is a known
        // behavior — Mac side normally has email, so this is unlikely.
        let nilA = self.makeProvider(
            id: "codex", email: nil, accountIdentities: nil)
        let nilB = self.makeProvider(
            id: "codex", email: nil, accountIdentities: nil)
        let mac = self.makeSnapshot(
            deviceName: "Mac", deviceID: "uuid-1",
            providers: [nilA, nilB])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        // Both fall into legacy-no-identity bucket → merge into 1.
        // This documents the existing behavior; if R1+R2 ever produces
        // two nil-email codex entries from the same Mac, they would
        // unfortunately collapse. We avoid this by always emitting
        // accountIdentities for Codex (Tier-A provider), so this is
        // structural protection.
        #expect(merged.providers.count == 1, "all-nil-email same-provider entries collapse to legacy bucket (documented behavior)")
    }

    @Test("R5 D8: Same Mac, 2 codex accounts, one with empty-string email + one with real email → 2 cards")
    func emptyEmailVsRealEmailKeptDistinct() throws {
        // Empty-string accountEmail is distinct from a populated email
        // in the merge logic (per existing CloudKitMergeTests "Provider
        // with nil email is treated as separate from one with email").
        let alice = self.makeProvider(
            id: "codex", email: "alice@x.com",
            accountIdentities: ["codex:email:alice%40x.com"])
        let empty = self.makeProvider(
            id: "codex", email: "",
            accountIdentities: nil)
        let mac = self.makeSnapshot(
            deviceName: "Mac", deviceID: "uuid-1",
            providers: [alice, empty])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.count == 2)
    }

    // MARK: - Token-provider multi-account (R2)

    @Test("R5 D9: Same Mac, R2 token expansion — Claude with 2 accounts merges correctly")
    func claudeMultiAccountFromSameMac() throws {
        let alice = self.makeProvider(
            id: "claude", email: "alice@anthropic.com",
            accountIdentities: ["claude:email:alice%40anthropic.com"])
        let bob = self.makeProvider(
            id: "claude", email: "bob@anthropic.com",
            accountIdentities: ["claude:email:bob%40anthropic.com"])
        let mac = self.makeSnapshot(
            deviceName: "Dev Mac", deviceID: "uuid-dev",
            providers: [alice, bob])

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.count == 2)
    }

    @Test("R5 D10: Same Mac with Codex (R1) + Claude (R2) both multi-account in one push")
    func codexAndClaudeMultiAccountSimultaneous() throws {
        // Real-world R5 scenario: user has 3 Codex accounts AND 2 Claude
        // accounts on a single Mac with R1+R2. Single push contains
        // 3+2=5 ProviderUsageSnapshots. iOS must render 5 cards.
        let codexProviders = (1 ... 3).map { i in
            self.makeProvider(
                id: "codex", email: "codex\(i)@x.com",
                accountIdentities: ["codex:email:codex\(i)%40x.com"])
        }
        let claudeProviders = (1 ... 2).map { i in
            self.makeProvider(
                id: "claude", email: "claude\(i)@x.com",
                accountIdentities: ["claude:email:claude\(i)%40x.com"])
        }
        let mac = self.makeSnapshot(
            deviceName: "Power Mac",
            deviceID: "uuid-power",
            providers: codexProviders + claudeProviders)

        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.count == 5, "3 codex + 2 claude all distinct")
        let codexCount = merged.providers.filter { $0.providerID == "codex" }.count
        let claudeCount = merged.providers.filter { $0.providerID == "claude" }.count
        #expect(codexCount == 3)
        #expect(claudeCount == 2)
    }

    @Test("R5 D11: Two-Mac × multi-account each — 2-2-1 = 5 cards (no overlap)")
    func twoMacEachMultiAccountAllDistinct() throws {
        let macAProviders = (1 ... 2).map { i in
            self.makeProvider(
                id: "codex", email: "macA-\(i)@x.com",
                accountIdentities: ["codex:email:maca-\(i)%40x.com"])
        }
        let macBProviders = (3 ... 5).map { i in
            self.makeProvider(
                id: "codex", email: "macB-\(i)@x.com",
                accountIdentities: ["codex:email:macb-\(i)%40x.com"])
        }
        let macA = self.makeSnapshot(
            deviceName: "Mac A", deviceID: "uuid-a", providers: macAProviders)
        let macB = self.makeSnapshot(
            deviceName: "Mac B", deviceID: "uuid-b", providers: macBProviders)

        let merged = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))
        #expect(merged.providers.count == 5)
    }

    @Test("R5 D12: Sort stability — same Mac multi-account merge produces alphabetical ordering")
    func multiAccountMergeAlphabetical() throws {
        // Pre-existing tests ensure merged providers are sorted alphabetically
        // by name. Multi-account entries share providerName ("Codex"), so the
        // account identity provides the deterministic tie-breaker.
        let zeb = self.makeProvider(
            id: "codex", name: "Codex", email: "zeb@x.com",
            accountIdentities: ["codex:email:zeb%40x.com"])
        let aro = self.makeProvider(
            id: "codex", name: "Codex", email: "aro@x.com",
            accountIdentities: ["codex:email:aro%40x.com"])
        let mac = self.makeSnapshot(
            deviceName: "Mac", deviceID: "uuid",
            providers: [zeb, aro])
        let merged = try #require(CloudSyncReader.mergeSnapshots([mac]))
        #expect(merged.providers.count == 2)
        let merged2 = try #require(CloudSyncReader.mergeSnapshots([mac]))
        let order1 = merged.providers.map(\.accountEmail)
        let order2 = merged2.providers.map(\.accountEmail)
        #expect(order1 == ["aro@x.com", "zeb@x.com"])
        #expect(order1 == order2, "merge ordering must be deterministic")
    }
}

// swiftlint:enable multiline_arguments
