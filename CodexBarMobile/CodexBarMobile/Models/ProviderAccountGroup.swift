import CodexBarSync
import Foundation

/// A provider plus all of its account snapshots, packaged for the
/// post-merge UI layer. The Usage tab renders **one row per group**
/// (matching the Mac menu's "one card per provider" layout) and the
/// detail view shows a segmented account tab bar at the top when the
/// group has more than one account.
///
/// **Where it sits in the pipeline:**
///
///     Mac CKRecord (per device, per account)
///       ↓
///     CloudSyncManager.fetchAllDeviceSnapshots()
///       ↓
///     CloudSyncReader.mergeSnapshots()        ← cross-Mac union-find
///                                                 by accountIdentities
///       ↓ [ProviderUsageSnapshot] (post-merge, one per logical account)
///     [ProviderUsageSnapshot].groupedByProvider()  ← this file
///       ↓ [ProviderAccountGroup] (one per providerID)
///     ContentView UsageTab → ProviderDetailView(group:)
///
/// The cross-Mac merge step collapses "same account on 2 Macs" into
/// one snapshot. The groupedByProvider step then collapses "different
/// accounts of the same provider" into one group. So a user with
/// OpenAI admin keys `msxiao113` + `outlook` on their Mac (which Mac
/// renders as two tabs in one menu card) sees one row labeled
/// "OpenAI API · 2" in the iOS Usage list and two tabs in the
/// detail view — mirroring Mac UX exactly.
///
/// Phase G fix — before this struct, iOS rendered multi-account
/// providers as N separate rows in the Usage list with no detail-view
/// tab UI, which both diverged from Mac and made it impossible to
/// compare account-level metrics side-by-side.
struct ProviderAccountGroup: Identifiable {
    let providerID: String
    let providerName: String
    let accounts: [ProviderUsageSnapshot]

    /// Identifier-stable across renders: `providerID` is unique per
    /// group (the whole point of grouping).
    var id: String {
        self.providerID
    }

    var hasMultipleAccounts: Bool {
        self.accounts.count > 1
    }

    /// First account in the group — used for list-row preview
    /// (`ProviderUsageView` rendering) and as the default initially-
    /// selected tab in the detail view.
    var representative: ProviderUsageSnapshot {
        self.accounts[0]
    }

    /// Short label for tab `index`. Used by the segmented control at
    /// the top of `ProviderDetailView` when `hasMultipleAccounts`.
    /// Strategy (first non-empty wins): account-email local-part →
    /// loginMethod → `Account N`.
    func tabLabel(forIndex index: Int, locale: Locale = .current) -> String {
        guard self.accounts.indices.contains(index) else { return "" }
        let snapshot = self.accounts[index]
        if let email = snapshot.accountEmail,
           !email.isEmpty
        {
            // Prefer the local-part (before @) for compactness in the
            // segmented control. Mac shows "admin-msxiao113" — same
            // shape after stripping the @openai.com domain.
            let local = email.split(separator: "@").first.map(String.init) ?? email
            if !local.isEmpty { return local }
        }
        if let login = snapshot.loginMethod, !login.isEmpty {
            return ProviderDetailLocalization.localizedValue(
                login,
                providerID: self.providerID,
                locale: locale)
        }
        let format = MobileLocalizedString.value(
            "Account %lld",
            defaultValue: "Account %lld",
            locale: locale)
        return String(format: format, locale: locale, arguments: [Int64(index + 1)])
    }

    /// Stable accessibility identifier for the tab at `index` — used
    /// by `MultiAccountTabRenderingTests` to pin the tab order.
    func tabAccessibilityIdentifier(forIndex index: Int) -> String {
        "provider-account-tab-\(self.providerID)-\(index)"
    }
}

extension [ProviderUsageSnapshot] {
    /// Group post-merge snapshots by `providerID`, preserving first-
    /// appearance order so the resulting Usage list mirrors the
    /// Mac-side provider enable order (which the wire format already
    /// honors).
    ///
    /// Cross-Mac merging via `CloudSyncReader.mergeSnapshots` must run
    /// FIRST so that "same account on 2 Macs" is already collapsed to
    /// one snapshot by the time this grouping runs. Calling this on
    /// raw per-device snapshots would over-group (mixing same-account
    /// duplicates from different Macs with truly-different accounts).
    func groupedByProvider() -> [ProviderAccountGroup] {
        var orderedIDs: [String] = []
        var bucket: [String: [ProviderUsageSnapshot]] = [:]
        for snapshot in self {
            if bucket[snapshot.providerID] == nil {
                orderedIDs.append(snapshot.providerID)
            }
            bucket[snapshot.providerID, default: []].append(snapshot)
        }
        return orderedIDs.compactMap { providerID in
            guard let accounts = bucket[providerID], !accounts.isEmpty else {
                return nil
            }
            // Group `providerName` is taken from the first account.
            // Mac sometimes annotates per-account display names like
            // "OpenAI API (admin-msxiao113 · Mock)" — we keep the
            // representative's name on the group, and the tab labels
            // surface the per-account distinction.
            return ProviderAccountGroup(
                providerID: providerID,
                providerName: accounts[0].providerName,
                accounts: accounts)
        }
    }
}
