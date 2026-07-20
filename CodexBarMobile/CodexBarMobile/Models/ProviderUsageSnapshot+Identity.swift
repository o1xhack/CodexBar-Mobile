import CodexBarSync
import Foundation

/// iOS-only identity helpers for `ProviderUsageSnapshot`.
///
/// The Shared layer has always keyed providers by `providerID` alone, but
/// `CloudSyncReader.mergeSnapshots` keys by `providerID|accountEmail` so
/// multi-account providers (Codex, in particular, after upstream 0.20's
/// workspace / system-account refactor) correctly split into distinct
/// cards. iOS render layer needs a matching key to avoid SwiftUI's ForEach
/// collapsing duplicates back into one view instance — this extension
/// exposes it without touching the Shared module (kept iOS-scoped because
/// the Mac target doesn't render cards).
extension ProviderUsageSnapshot {
    /// Identity used by SwiftUI `ForEach` and view-scoped accessibility
    /// identifiers. Matches `CloudSyncReader.mergeSnapshots`'s bucket key
    /// so that two `providerID == "codex"` entries with different
    /// `accountEmail`s get distinct view identities. Empty string falls back
    /// when `accountEmail == nil` — consistent with the merger's own
    /// fallback.
    var cardIdentityKey: String {
        "\(self.providerID)|\(self.accountRecordKey ?? self.accountEmail ?? "")"
    }
}
