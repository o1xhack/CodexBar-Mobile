// swiftlint:disable multiline_arguments type_body_length
//
// `type_body_length` bumped past the 800-line default in iOS 1.6.0 when
// 11 simple-mock entries were appended for the v0.24+v0.25 providers
// (commit bbf9d0a2 / commit 4a8e1b0e era). The whole point of this enum
// is to be a flat declarative catalog of mock profiles; splitting it
// into multiple types just to satisfy the line limit would hurt
// readability without changing the structure. The enum is private to
// MockProviderInjector and has a clear single responsibility, so the
// lint suppression is scoped and intentional.
import CodexBarSync
import Foundation

/// Synthetic provider data for end-to-end iCloud sync testing without
/// real provider subscriptions.
///
/// **Mix design** (Mac 0.23.6+): 6 mocks use real provider IDs (`codex`,
/// `claude`, `perplexity`) so iOS renders them with first-class provider
/// styling — exercising the critical multi-account first-class rendering
/// path that real users hit. The remaining 2 mocks use `_mock_*`
/// prefixed IDs to also exercise the unknown-provider fallback rendering
/// path (forward-compat insurance: when a future Mac adds a new provider
/// the iOS app doesn't yet know about, that fallback path must still
/// work).
///
/// 8 total `ProviderUsageSnapshot` entries across 5 distinct
/// `providerID` values:
///
/// 1. **`codex`** × 3 (Alice / Bob / Carol) — REAL providerID. Exercises
///    R1 Codex multi-account cache + per-account record emission +
///    cross-Mac `accountIdentities` merge — and renders with **the real
///    Codex card UI on iPhone** (icon, color, native multi-account
///    affordances). This is the critical "3 Codex accounts on Mac, 1 on
///    iPhone" path the user originally hit.
/// 2. **`claude`** × 2 (Personal / Work) — REAL providerID. Exercises R2
///    token-based multi-account expansion + Claude-specific UI (3-lane
///    Sonnet/Opus rendering when present).
/// 3. **`perplexity`** × 1 — REAL providerID. Exercises Perplexity's
///    3-segment credit breakdown card on iPhone (recurring + promo +
///    purchased + plan badge + renewal countdown).
/// 4. **`_mock_cursor_unknown`** × 1 — fallback test. Mock providerID
///    iOS doesn't recognize → renders generic blue fallback card. Carries
///    `isError = true` + statusMessage so the fallback's error-state
///    rendering is also exercised.
/// 5. **`_mock_synthetic_unknown`** × 1 — fallback test. Mock providerID
///    + 30-day utilization history + 3-lane rate windows + budget. Tests
///    that fallback rendering doesn't choke on rich data.
///
/// All real-providerID mocks include synthetic cost data (session +
/// 30-day total + daily breakdown for Alice) so iPhone's Cost dashboard
/// aggregation (Daily Spend, per-provider share, model breakdown,
/// month-over-month) is end-to-end testable.
///
/// **Account email convention**: every mock uses the `*-mock@*.test` TLD
/// (RFC 6761 reserved for testing) so even though some mocks share
/// providerID with real providers, the synthetic accounts are
/// unambiguously distinguishable on iPhone via email subtitle. iOS
/// 1.5.2+ also uses the `.test` TLD as the trigger for the MOCK badge +
/// purple-striped card treatment.
///
/// **Activation** — requires launching Mac CodexBar with the
/// environment variable `CODEXBAR_MOCK_PROVIDERS` set:
///
/// 1. **Quick test (env var truthy)** — `CODEXBAR_MOCK_PROVIDERS=1
///    open -a /Applications/CodexBar.app`. Mocks active immediately;
///    Settings → Mobile → Debug · Mock Provider Data section appears
///    so you can toggle off without restarting if needed.
/// 2. **Persistent UI control** — `CODEXBAR_MOCK_PROVIDERS=0
///    open -a /Applications/CodexBar.app`. Section appears, mocks
///    initially OFF, UI toggle drives the actual state (persisted in
///    UserDefaults). Subsequent debug-launches honor the toggle state.
///
/// **Production safety**:
/// - Default is OFF. A user launching CodexBar normally (Finder /
///   Dock / login item) never has the env var set, so they never see
///   the Settings section and `isEnabled` always returns false
///   regardless of any UserDefaults state.
/// - Mock account emails always use `.test` TLD (RFC 6761 reserved).
///   Synthetic providerID branches use `_mock_` prefix.
/// - Mock CKRecords are stored under composite keys distinct from real
///   data: `{deviceID}|{providerID}|*-mock@*.test` does NOT collide with
///   any real `{deviceID}|{providerID}|{realEmail}` because the email
///   bucket is different.
/// - When the flag is turned off, the next sync cycle stops emitting
///   mock records and the L1 ghost-records cleanup automatically deletes
///   the orphaned CKRecords from CloudKit. Real provider data is in
///   different CKRecords and is never touched.
///
/// **Cost data + your real numbers**: Daily Spend / per-provider share /
/// model breakdown on iPhone aggregates ALL providers' cost. While mocks
/// are active, totals are inflated by ~$48/30day from synthetic data.
/// Once you toggle off and CloudKit cleanup runs (~1 cycle / ~30s), real
/// numbers automatically restore. Real CKRecords are never modified.
@MainActor
enum MockProviderInjector {
    /// Returns mock `ProviderUsageSnapshot` entries when activation is
    /// enabled; empty array otherwise. SyncCoordinator's default
    /// `mockInjector` closure calls this in production.
    static func injectedSnapshots() -> [ProviderUsageSnapshot] {
        guard self.isEnabled else { return [] }
        return self.allMocks()
    }

    /// Returns ALL mock ProviderUsageSnapshot entries unconditionally,
    /// regardless of global activation state. Tests that want to
    /// exercise the SyncCoordinator hook with predictable mock data
    /// pass `mockInjector: { MockProviderInjector.allMocks() }` to
    /// SyncCoordinator's init — this avoids depending on the global
    /// `isEnabled` state, which doesn't isolate cleanly across
    /// parallel `@MainActor` test suites.
    ///
    /// **Composition** (Mac 0.23.6+):
    /// - 8 rich mocks (codex × 3 multi-account + claude × 2 multi-account
    ///   + perplexity 3-credit-segment + 2 synthetic `_mock_*` fallback
    ///   error/rich) — exercise the high-traffic UI paths.
    /// - 35 simple single-account mocks (cursor, opencode, opencodego,
    ///   alibaba, factory, gemini, antigravity, copilot, zai, minimax,
    ///   kimi, kilo, kiro, vertexai, augment, jetbrains, kimik2, amp,
    ///   ollama, synthetic, warp, openrouter, abacus, mistral) — exercise
    ///   each provider's first-class card on iPhone, plus 30-day
    ///   aggregate cost dashboard contribution.
    ///
    /// Total: **45 ProviderUsageSnapshot entries across 42 distinct
    /// providerIDs** (40 real-borrowed + 2 synthetic). iOS 1.9.0 bumps a few
    /// headline providers to realistic heavy spend + synthesizes ~55-day daily
    /// histories so the CWL ledger / Cost dashboard are testable at scale; the
    /// aggregate 30-day cost is now several thousand USD, not ~$100.
    static func allMocks() -> [ProviderUsageSnapshot] {
        let rich: [ProviderUsageSnapshot] = [
            self.mockCodexAlice(),
            self.mockCodexBob(),
            self.mockCodexCarol(),
            self.mockClaudePersonal(),
            self.mockClaudeWork(),
            self.mockPerplexityPro(),
            self.mockCursorErrorFallback(),
            self.mockSyntheticThreeLaneFallback(),
        ]
        let simple: [ProviderUsageSnapshot] = Self.simpleProviderProfiles
            .map { Self.makeSimpleProviderMock(profile: $0) }
        return rich + simple
    }

    /// True when mock provider injection is active. **Env var
    /// `CODEXBAR_MOCK_PROVIDERS` MUST be set on launch** — without it
    /// this always returns false regardless of UserDefaults state.
    /// Within an env-var-launched process: an env var value of `1`,
    /// `true`, or `yes` (case-insensitive) activates immediately;
    /// other values fall through to the UserDefaults toggle so the
    /// Settings UI can drive the runtime state.
    static var isEnabled: Bool {
        Self.isEnabled(
            environment: ProcessInfo.processInfo.environment,
            userDefaults: UserDefaults.standard)
    }

    /// Testable variant — same logic as `isEnabled`, but with injected
    /// environment + UserDefaults so unit tests can verify the env-var
    /// parsing and precedence rules without spawning a subprocess or
    /// mutating the real launch environment.
    static func isEnabled(
        environment: [String: String],
        userDefaults: UserDefaults) -> Bool
    {
        // Hard gate: env var must be present at launch. Without it,
        // mock tooling is fully invisible to the process — Settings UI
        // hides the section, defaults are ignored.
        guard let raw = environment[environmentVariableName] else {
            return false
        }
        let normalized = raw.lowercased()
        let truthy: Set<String> = ["1", "true", "yes"]
        if truthy.contains(normalized) {
            return true
        }
        // Env var present but not truthy — UI toggle (defaults) drives.
        return userDefaults.bool(forKey: Self.userDefaultsKey)
    }

    /// True when this process should expose the Settings → Mobile →
    /// Debug · Mock Provider Data section. Identical gate as
    /// `isEnabled` with respect to env-var presence — defaults state
    /// is irrelevant for visibility, only for the toggle's current
    /// position within the UI.
    static var isMockToolingVisible: Bool {
        Self.isMockToolingVisible(
            environment: ProcessInfo.processInfo.environment)
    }

    /// Testable variant of `isMockToolingVisible`.
    static func isMockToolingVisible(environment: [String: String]) -> Bool {
        environment[self.environmentVariableName] != nil
    }

    static let environmentVariableName = "CODEXBAR_MOCK_PROVIDERS"
    static let userDefaultsKey = "CodexBarMockProvidersEnabled"

    /// Real provider IDs that some mocks intentionally borrow so iOS
    /// renders them with first-class provider UI. Mocks using these IDs
    /// always pair them with `*-mock@*.test` accountEmails so the
    /// synthetic account is unambiguously distinct from any real account
    /// the user has on the same provider.
    ///
    /// Mac 0.23.6+ extended to all 27 real providers in
    /// `UsageProvider.allCases` (P2: full provider coverage). Three of
    /// these (`codex`, `claude`, `perplexity`) have rich multi-account
    /// or credit-breakdown mocks; the other 24 have simpler
    /// single-account mocks via `simpleProviderProfiles`.
    static let realProviderIDsBorrowedByMocks: Set<String> = [
        "codex", "claude", "cursor", "opencode", "opencodego",
        "alibaba", "factory", "gemini", "antigravity", "copilot",
        "zai", "minimax", "kimi", "kilo", "kiro",
        "vertexai", "augment", "jetbrains", "kimik2", "amp",
        "ollama", "synthetic", "warp", "openrouter", "perplexity",
        "abacus", "mistral",
        // iOS 1.6.0 catch-up — must stay in sync with `simpleProviderProfiles`
        // additions below and with `QuotaProviderList` (Shared/Notifications).
        "openai", "manus", "windsurf", "mimo", "doubao",
        "deepseek", "codebuff", "crof", "venice", "commandcode",
        "stepfun",
        // iOS 1.7.0 catch-up (upstream v0.26.0 new providers).
        "moonshot", "bedrock",
        // iOS 1.8.0 catch-up (upstream v0.27.0 new providers).
        "grok", "groq", "elevenlabs", "deepgram", "llmproxy",
        // iOS 1.9.0 catch-up (upstream v0.28.0+v0.29.0 new providers).
        // Must stay in sync with `simpleProviderProfiles` and `QuotaProviderList`.
        "azureopenai", "alibabatokenplan", "t3chat",
        // iOS 1.12.0 catch-up (upstream v0.34.0 new provider).
        "devin",
        // iOS 1.13.0 catch-up (upstream v0.36.0+v0.36.1 new providers).
        "litellm", "poe", "chutes", "zed",
        // iOS 1.17.0 catch-up (upstream v0.38.0-v0.39.0 new providers).
        "sakana", "qoder", "crossmodel", "clawrouter",
    ]

    /// Synthetic providerIDs unique to mocks. Always prefixed `_mock_`.
    /// iOS treats these as unknown providers and renders fallback cards.
    static let syntheticProviderIDs: Set<String> = [
        "_mock_cursor_unknown", "_mock_synthetic_unknown",
    ]

    /// All mock providerIDs (real-borrowed ∪ synthetic). Convenience
    /// for tests that need to gate "is this a mock provider?" without
    /// caring about which subset.
    static var allMockProviderIDs: Set<String> {
        realProviderIDsBorrowedByMocks.union(syntheticProviderIDs)
    }

    /// Universal mock-account email TLD. iOS 1.5.2+ inspects this to
    /// gate the MOCK badge + purple-striped card treatment.
    static let mockEmailTLD = ".test"

    // MARK: - Reference timestamp

    /// Reference timestamp captured per-call (NOT cached across calls).
    /// Each mock generation cycle uses a fresh `Date()`, which means
    /// `lastUpdated` and `resetsAt` track wall-clock and the mock data
    /// looks "live" on iOS. Side effect: every push generates a unique
    /// hash so the per-provider hash cache always uploads fresh records;
    /// this is acceptable because mock activation is opt-in and rare.
    private static var nowReference: Date {
        Date()
    }

    // MARK: - Cost helper

    /// Deterministically synthesizes a `days`-long daily-spend array centered
    /// on `avgPerDay`, with a per-provider phase offset so different mocks
    /// don't wobble in lockstep. Oldest→newest, rounded to cents. Gives the
    /// simple single-account mocks a real per-day cost history so they land in
    /// the CWL ledger and the daily-spend chart — not just the Codex mock.
    private static func synthDailyTotals(
        days: Int, avgPerDay: Double, seed: String) -> [Double]
    {
        guard days > 0, avgPerDay > 0 else { return [] }
        let phase = Double(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 100)
            / 100.0 * .pi * 2
        return (0..<days).map { day in
            let wobble = 1.0 + 0.35 * sin(Double(day) * 0.35 + phase)
            return ((avgPerDay * wobble) * 100).rounded() / 100
        }
    }

    /// Builds a SyncCostSummary with optional 30-day daily breakdown.
    /// `dailyTotals.count` should be 30 for a complete history; can be
    /// fewer if testing partial windows.
    private static func makeCostSummary(
        sessionUSD: Double,
        sessionTokens: Int,
        thirtyDayUSD: Double,
        thirtyDayTokens: Int,
        dailyTotals: [Double] = [],
        isEstimated: Bool? = false,
        // iOS 1.9.0 / Mac 0.29.0 gap F — non-nil drives the iOS "N Days"
        // cost-window label (nil/30 → "30 Days").
        historyDays: Int? = nil,
        // iOS 1.9.0 / Mac 0.29.0 gap A — populate the Codex standard/fast
        // (priority) cost split on each model breakdown so iOS renders the
        // "Std $X · Fast $Y" sub-line. Only pass true for Codex mocks (the
        // split is a Codex concept; iOS shows it wherever the fields exist).
        includeStandardFastSplit: Bool = false) -> SyncCostSummary
    {
        // dayKey format `YYYY-MM-DD` (UTC) matches the real cost
        // scanner's emission format. Days are ordered oldest→newest.
        let now = Self.nowReference
        let oneDay: TimeInterval = 86400
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        /// 60/40 standard/priority split — synthetic but representative.
        func breakdown(_ label: String, _ cost: Double) -> SyncCostBreakdown {
            SyncCostBreakdown(
                label: label,
                costUSD: cost,
                isEstimated: false,
                standardCostUSD: includeStandardFastSplit ? cost * 0.6 : nil,
                priorityCostUSD: includeStandardFastSplit ? cost * 0.4 : nil,
                standardTokens: includeStandardFastSplit ? Int(cost * 0.6 * 50000) : nil,
                priorityTokens: includeStandardFastSplit ? Int(cost * 0.4 * 50000) : nil)
        }
        let dailyPoints: [SyncDailyPoint] = dailyTotals.enumerated().map { idx, dailyUSD in
            let captured = now.addingTimeInterval(
                -Double(dailyTotals.count - 1 - idx) * oneDay)
            return SyncDailyPoint(
                dayKey: formatter.string(from: captured),
                costUSD: dailyUSD,
                totalTokens: Int(dailyUSD * 50000), // synthetic token ratio
                modelBreakdowns: [
                    breakdown("claude-sonnet-4-6", dailyUSD * 0.7),
                    breakdown("claude-opus-4-7", dailyUSD * 0.3),
                ],
                serviceBreakdowns: [],
                isEstimated: false)
        }
        return SyncCostSummary(
            sessionCostUSD: sessionUSD,
            sessionTokens: sessionTokens,
            last30DaysCostUSD: thirtyDayUSD,
            last30DaysTokens: thirtyDayTokens,
            daily: dailyPoints,
            isEstimated: isEstimated,
            historyDays: historyDays)
    }

    // MARK: - Codex multi-account (R1) — 3 managed-account-style entries

    // All three use the real `codex` providerID so iOS renders them with
    // the native Codex multi-account UI.

    private static func mockCodexAlice() -> ProviderUsageSnapshot {
        // Alice uses a non-ASCII email (`café-mock@codex.test`) on
        // purpose to exercise UTF-8 + percent-encoding round-trip
        // through the wire format and the AccountIdentityComputer.
        // A heavy Codex account (~$45/day) with a 55-day daily history so the
        // CWL ledger, the 90-day window, and the day-by-day chart + Std/Fast
        // split are all testable against realistic numbers. (Simple mocks also
        // synthesize daily now — see makeSimpleProviderMock.)
        let dailySpend: [Double] = (0..<55).map { day in
            // ~$30–$60/day sinusoidal pattern (≈$1,350 trailing-30-day).
            45.0 + 15.0 * sin(Double(day) * 0.4)
        }
        // Anchor the headline "30-day" cost to the trailing 30 days (not all
        // 55) so it reads like a real 30-day window.
        let trailing30 = dailySpend.suffix(30).reduce(0, +)
        return ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Alice · Mock)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 35,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(2700),
                resetDescription: "in 45 min"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 60,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(345_600),
                resetDescription: "in 4 days"),
            accountEmail: "café-mock@codex.test",
            loginMethod: "Pro $200",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: Self.makeCostSummary(
                sessionUSD: 0.42,
                sessionTokens: 12345,
                thirtyDayUSD: trailing30,
                thirtyDayTokens: Int(trailing30 * 50000),
                dailyTotals: dailySpend,
                // gap F: 90-day window → iOS shows "90 Days" (vs "30 Days").
                historyDays: 90,
                // gap A: emit the Codex standard/fast split sub-line.
                includeStandardFastSplit: true),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 35,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(2700),
                    resetDescription: "in 45 min"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 60,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(345_600),
                    resetDescription: "in 4 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "codex:email:caf%C3%A9-mock%40codex.test",
            ])
    }

    private static func mockCodexBob() -> ProviderUsageSnapshot {
        // Bob exercises the 100% boundary (weekly fully consumed) so
        // iOS rendering of "quota depleted" state is testable.
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Bob · Mock)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 75,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(1800),
                resetDescription: "in 30 min"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 100, // boundary: fully consumed
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(345_600),
                resetDescription: "in 4 days"),
            accountEmail: "bob-mock@codex.test",
            loginMethod: "Pro $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: self.makeCostSummary(
                sessionUSD: 1.27,
                sessionTokens: 45678,
                thirtyDayUSD: 18.20,
                thirtyDayTokens: 910_000),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 75,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(1800),
                    resetDescription: "in 30 min"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 100, // boundary
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(345_600),
                    resetDescription: "in 4 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "codex:email:bob-mock%40codex.test",
            ])
    }

    private static func mockCodexCarol() -> ProviderUsageSnapshot {
        // Carol exercises the 0% boundary (just-reset window) so iOS
        // rendering of "quota empty / fresh" state is testable.
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Carol · Mock)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 0, // boundary: fresh / just reset
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(14400),
                resetDescription: "in 4 hours"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 12,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(345_600),
                resetDescription: "in 4 days"),
            accountEmail: "carol-mock@codex.test",
            loginMethod: "Plus $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: self.makeCostSummary(
                sessionUSD: 0.05,
                sessionTokens: 1234,
                thirtyDayUSD: 1.10,
                thirtyDayTokens: 55000),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 0, // boundary
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(14400),
                    resetDescription: "in 4 hours"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 12,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(345_600),
                    resetDescription: "in 4 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "codex:email:carol-mock%40codex.test",
            ])
    }

    // MARK: - Claude multi-account (R2) — 2 token-account-style entries

    // Both use the real `claude` providerID so iOS renders the native
    // Claude card. Personal carries 3-lane rateWindows (5h + Weekly
    // Sonnet + Weekly Opus) which exercises the Claude-specific 3-lane
    // detail view.

    private static func mockClaudePersonal() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude (Personal · Mock)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(3600),
                resetDescription: "in 1 hour"),
            secondary: SyncRateWindow(
                label: "Weekly Sonnet",
                usedPercent: 65,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(259_200),
                resetDescription: "in 3 days"),
            accountEmail: "personal-mock@claude.test",
            loginMethod: "Pro $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: self.makeCostSummary(
                sessionUSD: 0.08,
                sessionTokens: 4200,
                thirtyDayUSD: 3.80,
                thirtyDayTokens: 190_000),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 50,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(3600),
                    resetDescription: "in 1 hour"),
                SyncRateWindow(
                    label: "Weekly Sonnet", usedPercent: 65,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(259_200),
                    resetDescription: "in 3 days"),
                SyncRateWindow(
                    label: "Weekly Opus", usedPercent: 90,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(259_200),
                    resetDescription: "in 3 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "claude:email:personal-mock%40claude.test",
            ])
    }

    private static func mockClaudeWork() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude (Work · Mock)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 22,
                windowMinutes: 300,
                resetsAt: self.nowReference.addingTimeInterval(7200),
                resetDescription: "in 2 hours"),
            secondary: SyncRateWindow(
                label: "Weekly Sonnet",
                usedPercent: 38,
                windowMinutes: 10080,
                resetsAt: self.nowReference.addingTimeInterval(259_200),
                resetDescription: "in 3 days"),
            accountEmail: "work-mock@claude.test",
            loginMethod: "Team $30",
            statusMessage: nil,
            isError: false,
            lastUpdated: self.nowReference,
            costSummary: self.makeCostSummary(
                sessionUSD: 0.15,
                sessionTokens: 6800,
                thirtyDayUSD: 6.20,
                thirtyDayTokens: 310_000),
            budget: nil,
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 22,
                    windowMinutes: 300,
                    resetsAt: self.nowReference.addingTimeInterval(7200),
                    resetDescription: "in 2 hours"),
                SyncRateWindow(
                    label: "Weekly Sonnet", usedPercent: 38,
                    windowMinutes: 10080,
                    resetsAt: self.nowReference.addingTimeInterval(259_200),
                    resetDescription: "in 3 days"),
            ],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "claude:email:work-mock%40claude.test",
            ])
    }

    // MARK: - Perplexity (real ID) — 1 entry with rich credit breakdown

    private static func mockPerplexityPro() -> ProviderUsageSnapshot {
        // Perplexity primary metric is "credits remaining" not a rate
        // window, but we synthesize a daily-message rate window so the
        // record isn't filtered as ghost in the per-provider write path
        // and so iOS can render a usage bar alongside the credit
        // breakdown.
        let primary = SyncRateWindow(
            label: "Daily messages",
            usedPercent: 32,
            windowMinutes: 1440,
            resetsAt: Self.nowReference.addingTimeInterval(28800),
            resetDescription: "in 8 hours")
        return ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity (Pro · Mock)",
            primary: primary,
            secondary: nil,
            accountEmail: "pro-mock@perplexity.test",
            loginMethod: "Pro $20",
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.nowReference,
            costSummary: Self.makeCostSummary(
                sessionUSD: 0.03,
                sessionTokens: 1500,
                thirtyDayUSD: 2.30,
                thirtyDayTokens: 115_000),
            budget: nil,
            rateWindows: [primary],
            utilizationHistory: nil,
            perplexityCredits: SyncPerplexityCreditSummary(
                recurringTotalCents: 50000,
                recurringUsedCents: 32500,
                promoTotalCents: 10000,
                promoUsedCents: 4200,
                promoExpiresAt: Self.nowReference
                    .addingTimeInterval(15 * 86400),
                purchasedTotalCents: 25000,
                purchasedUsedCents: 7800,
                renewalAt: Self.nowReference
                    .addingTimeInterval(20 * 86400),
                planName: "Pro",
                balanceCents: 41000),
            accountIdentities: [
                "perplexity:email:pro-mock%40perplexity.test",
            ])
    }

    // MARK: - Fallback: Cursor in error state (synthetic providerID)

    // Uses `_mock_cursor_unknown` so iOS treats it as an unknown
    // provider → renders the generic blue fallback card. Combined with
    // `isError = true` + statusMessage, this exercises both the
    // fallback path AND the error-state rendering.

    private static func mockCursorErrorFallback() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "_mock_cursor_unknown",
            providerName: "Cursor (Cookie expired · Mock)",
            primary: nil,
            secondary: nil,
            accountEmail: "expired-mock@cursor.test",
            loginMethod: nil,
            statusMessage: "Mock: Cookie expired — please sign in again.",
            isError: true,
            lastUpdated: self.nowReference,
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: nil)
    }

    // MARK: - Fallback: 3-lane + utilization history (synthetic providerID)

    // Uses `_mock_synthetic_unknown` to verify that the fallback
    // rendering path can handle rich data (3 rate windows + 30-day
    // utilization history + budget) without choking. This is forward-
    // compat insurance: when a future provider gets added that iOS
    // doesn't yet know about, the fallback must still render its data.

    private static func mockSyntheticThreeLaneFallback() -> ProviderUsageSnapshot {
        // Build 30 days of utilization entries.
        let oneDay: TimeInterval = 86400
        let now = Self.nowReference
        var sessionEntries: [SyncUtilizationEntry] = []
        var weeklyEntries: [SyncUtilizationEntry] = []
        var searchEntries: [SyncUtilizationEntry] = []
        for day in 0..<30 {
            let captured = now.addingTimeInterval(
                -Double(29 - day) * oneDay)
            let resets = captured.addingTimeInterval(oneDay)
            // Simple sinusoidal patterns so iOS chart shows variation.
            let sessionPct = 0.3 + 0.3 * sin(Double(day) * 0.5)
            let weeklyPct = 0.5 + 0.2 * cos(Double(day) * 0.3)
            let searchPct = 0.2 + 0.4 * sin(Double(day) * 0.7)
            sessionEntries.append(SyncUtilizationEntry(
                capturedAt: captured,
                usedPercent: max(0, min(1, sessionPct)),
                resetsAt: resets))
            weeklyEntries.append(SyncUtilizationEntry(
                capturedAt: captured,
                usedPercent: max(0, min(1, weeklyPct)),
                resetsAt: resets))
            searchEntries.append(SyncUtilizationEntry(
                capturedAt: captured,
                usedPercent: max(0, min(1, searchPct)),
                resetsAt: resets))
        }

        return ProviderUsageSnapshot(
            providerID: "_mock_synthetic_unknown",
            providerName: "Synthetic (3-lane fallback · Mock)",
            primary: SyncRateWindow(
                label: "5h",
                usedPercent: 45,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: "in 1 hour"),
            secondary: SyncRateWindow(
                label: "Weekly",
                usedPercent: 70,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(518_400),
                resetDescription: "in 6 days"),
            accountEmail: "lanes-mock@synthetic.test",
            loginMethod: "Builder",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: nil,
            budget: SyncBudgetSnapshot(
                usedAmount: 18.50,
                limitAmount: 50,
                currencyCode: "USD",
                period: "monthly",
                resetsAt: now.addingTimeInterval(20 * 86400)),
            rateWindows: [
                SyncRateWindow(
                    label: "5h", usedPercent: 45,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(3600),
                    resetDescription: "in 1 hour"),
                SyncRateWindow(
                    label: "Weekly", usedPercent: 70,
                    windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(518_400),
                    resetDescription: "in 6 days"),
                SyncRateWindow(
                    label: "Search hourly", usedPercent: 25,
                    windowMinutes: 60,
                    resetsAt: now.addingTimeInterval(900),
                    resetDescription: "in 15 min"),
            ],
            utilizationHistory: [
                SyncUtilizationSeries(
                    name: "session", windowMinutes: 300,
                    entries: sessionEntries),
                SyncUtilizationSeries(
                    name: "weekly", windowMinutes: 10080,
                    entries: weeklyEntries),
                SyncUtilizationSeries(
                    name: "search", windowMinutes: 60,
                    entries: searchEntries),
            ],
            perplexityCredits: nil,
            accountIdentities: [
                "_mock_synthetic_unknown:email:lanes-mock%40synthetic.test",
            ])
    }

    // MARK: - Simple single-account profiles for the remaining 24 providers

    /// Compact data row defining a simple single-account mock for one
    /// real providerID. Used by `makeSimpleProviderMock(profile:)` to
    /// generate `ProviderUsageSnapshot` values without 50+ lines of
    /// boilerplate per provider.
    ///
    /// The 3 high-traffic providers (codex, claude, perplexity) have
    /// hand-tuned rich mocks above; this struct is for the other 24.
    private struct SimpleProviderProfile {
        let providerID: String
        let providerName: String
        /// Local part of the synthetic email — full email is built as
        /// `{accountLocal}-mock@{providerID}.test`. Use a short label
        /// like `"plus"`, `"team"`, `"free"` to evoke the typical plan.
        let accountLocal: String
        let loginMethod: String
        /// Primary rate window usage 0-100. Set to nil to omit primary
        /// (and skip rate-window rendering entirely — exercises the
        /// "no metric" fallback path on iPhone).
        let primaryUsage: Double?
        let primaryLabel: String
        let primaryWindowMinutes: Int
        let primaryResetsInSeconds: TimeInterval
        let primaryResetDescription: String
        /// Optional secondary rate window. Most providers have only
        /// primary; set this when the provider exposes a 2nd metric
        /// (e.g. weekly + monthly).
        let secondary: SecondaryWindow?
        /// 30-day spend in USD; aggregated by iPhone Cost dashboard.
        /// Nil = provider has no cost reporting (e.g. ollama, local).
        let thirtyDayCostUSD: Double?
        /// Session-level spend (today). Nil if no cost.
        let sessionCostUSD: Double?

        struct SecondaryWindow {
            let label: String
            let usedPercent: Double
            let windowMinutes: Int
            let resetsInSeconds: TimeInterval
            let resetDescription: String
        }
    }

    /// Profile table for the simple mocks. Each profile yields one
    /// `ProviderUsageSnapshot`. iOS 1.9.0: each cost-bearing profile now
    /// synthesizes a ~55-day daily history (`makeSimpleProviderMock`) so it
    /// populates the CWL ledger, and a few headline providers (cursor /
    /// factory / gemini) carry realistic heavy 30-day totals to exercise the
    /// dashboard's big-number + top-5/Others paths. The old "<$100 aggregate"
    /// invariant is intentionally lifted for that reason.
    private static let simpleProviderProfiles: [SimpleProviderProfile] = [
        .init(
            providerID: "cursor", providerName: "Cursor",
            accountLocal: "team", loginMethod: "Business $40",
            primaryUsage: 45, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 12 * 86400,
            primaryResetDescription: "in 12 days",
            secondary: nil,
            thirtyDayCostUSD: 1450.00, sessionCostUSD: 52.00),
        .init(
            providerID: "opencode", providerName: "OpenCode Zen",
            accountLocal: "personal", loginMethod: "Pro",
            primaryUsage: 30, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 16,
            primaryResetDescription: "in 16 hours",
            secondary: nil,
            thirtyDayCostUSD: 1.20, sessionCostUSD: 0.04),
        .init(
            providerID: "opencodego", providerName: "OpenCode Go",
            accountLocal: "go", loginMethod: "Free",
            primaryUsage: 25, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 12,
            primaryResetDescription: "in 12 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.80, sessionCostUSD: 0.02),
        .init(
            providerID: "alibaba", providerName: "Qwen / Alibaba",
            accountLocal: "qwen", loginMethod: "Plus",
            primaryUsage: 20, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 8,
            primaryResetDescription: "in 8 hours",
            secondary: nil,
            thirtyDayCostUSD: 2.10, sessionCostUSD: 0.06),
        .init(
            providerID: "factory", providerName: "Factory",
            accountLocal: "build", loginMethod: "Builder",
            primaryUsage: 60, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 8 * 86400,
            primaryResetDescription: "in 8 days",
            secondary: nil,
            thirtyDayCostUSD: 620.00, sessionCostUSD: 22.00),
        .init(
            providerID: "gemini", providerName: "Gemini",
            accountLocal: "advanced", loginMethod: "Advanced",
            primaryUsage: 15, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 10,
            primaryResetDescription: "in 10 hours",
            secondary: nil,
            thirtyDayCostUSD: 2400.00, sessionCostUSD: 86.00),
        .init(
            providerID: "antigravity", providerName: "Antigravity",
            accountLocal: "pre", loginMethod: "Preview",
            primaryUsage: 5, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 22,
            primaryResetDescription: "in 22 hours",
            secondary: nil,
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "copilot", providerName: "GitHub Copilot",
            accountLocal: "ent", loginMethod: "Enterprise",
            primaryUsage: 70, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 6 * 86400,
            primaryResetDescription: "in 6 days",
            secondary: nil,
            thirtyDayCostUSD: 5.80, sessionCostUSD: 0.40),
        .init(
            providerID: "zai", providerName: "z.ai",
            accountLocal: "glm", loginMethod: "GLM Coding",
            primaryUsage: 40, primaryLabel: "5h",
            primaryWindowMinutes: 300,
            primaryResetsInSeconds: 60 * 30,
            primaryResetDescription: "in 30 min",
            secondary: .init(
                label: "Weekly", usedPercent: 65,
                windowMinutes: 10080,
                resetsInSeconds: 3 * 86400,
                resetDescription: "in 3 days"),
            thirtyDayCostUSD: 0.50, sessionCostUSD: 0.02),
        .init(
            providerID: "minimax", providerName: "MiniMax",
            accountLocal: "agent", loginMethod: "Agent",
            primaryUsage: 22, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 18,
            primaryResetDescription: "in 18 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.30, sessionCostUSD: 0.01),
        .init(
            providerID: "kimi", providerName: "Kimi",
            accountLocal: "k1", loginMethod: "K1",
            primaryUsage: 18, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 14,
            primaryResetDescription: "in 14 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.20, sessionCostUSD: 0.01),
        .init(
            providerID: "kilo", providerName: "Kilo Code",
            accountLocal: "agent", loginMethod: "Agent",
            primaryUsage: 33, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 15 * 86400,
            primaryResetDescription: "in 15 days",
            secondary: nil,
            thirtyDayCostUSD: 0.45, sessionCostUSD: 0.03),
        .init(
            providerID: "kiro", providerName: "Kiro",
            accountLocal: "spec", loginMethod: "Spec",
            primaryUsage: 12, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 6,
            primaryResetDescription: "in 6 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.10, sessionCostUSD: 0.005),
        .init(
            providerID: "vertexai", providerName: "Vertex AI",
            accountLocal: "gcp", loginMethod: "GCP",
            primaryUsage: 27, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 9,
            primaryResetDescription: "in 9 hours",
            secondary: .init(
                label: "Monthly", usedPercent: 50,
                windowMinutes: 43200,
                resetsInSeconds: 18 * 86400,
                resetDescription: "in 18 days"),
            thirtyDayCostUSD: 4.20, sessionCostUSD: 0.18),
        .init(
            providerID: "augment", providerName: "Augment",
            accountLocal: "team", loginMethod: "Team",
            primaryUsage: 55, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 14 * 86400,
            primaryResetDescription: "in 14 days",
            secondary: nil,
            thirtyDayCostUSD: 1.80, sessionCostUSD: 0.07),
        .init(
            providerID: "jetbrains", providerName: "JetBrains AI",
            accountLocal: "pro", loginMethod: "Pro",
            primaryUsage: 40, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 17 * 86400,
            primaryResetDescription: "in 17 days",
            secondary: nil,
            thirtyDayCostUSD: 2.40, sessionCostUSD: 0.10),
        .init(
            providerID: "kimik2", providerName: "Kimi K2",
            accountLocal: "k2", loginMethod: "K2",
            primaryUsage: 8, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 4,
            primaryResetDescription: "in 4 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.05, sessionCostUSD: 0.002),
        .init(
            providerID: "amp", providerName: "Amp",
            accountLocal: "build", loginMethod: "Builder",
            primaryUsage: 25, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 11,
            primaryResetDescription: "in 11 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.60, sessionCostUSD: 0.03),
        // Ollama is local inference (no quota, no spend in real life).
        // We give the mock a synthetic 0%-usage "Local" rate window
        // anyway so the per-provider write path doesn't ghost-filter
        // it (which would silently drop Ollama from iOS even though
        // the snapshot-level emission still includes it). The 0%
        // window also exercises iOS's "fresh / nothing used yet"
        // rendering path on the Ollama card.
        .init(
            providerID: "ollama", providerName: "Ollama",
            accountLocal: "local", loginMethod: "Local",
            primaryUsage: 0, primaryLabel: "Local inference",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 86400,
            primaryResetDescription: "in 24 hours",
            secondary: nil,
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "synthetic", providerName: "Synthetic",
            accountLocal: "build", loginMethod: "Builder",
            primaryUsage: 65, primaryLabel: "5h",
            primaryWindowMinutes: 300,
            primaryResetsInSeconds: 60 * 50,
            primaryResetDescription: "in 50 min",
            secondary: nil,
            thirtyDayCostUSD: 1.10, sessionCostUSD: 0.05),
        .init(
            providerID: "warp", providerName: "Warp",
            accountLocal: "term", loginMethod: "Pro",
            primaryUsage: 35, primaryLabel: "5h",
            primaryWindowMinutes: 300,
            primaryResetsInSeconds: 60 * 90,
            primaryResetDescription: "in 1.5 hours",
            secondary: .init(
                label: "Weekly", usedPercent: 80,
                windowMinutes: 10080,
                resetsInSeconds: 5 * 86400,
                resetDescription: "in 5 days"),
            thirtyDayCostUSD: 3.30, sessionCostUSD: 0.13),
        .init(
            providerID: "openrouter", providerName: "OpenRouter",
            accountLocal: "credits", loginMethod: "Credits",
            primaryUsage: 80, primaryLabel: "Hourly",
            primaryWindowMinutes: 60,
            primaryResetsInSeconds: 60 * 20,
            primaryResetDescription: "in 20 min",
            secondary: nil,
            thirtyDayCostUSD: 4.00, sessionCostUSD: 0.22),
        .init(
            providerID: "abacus", providerName: "Abacus AI",
            accountLocal: "ai", loginMethod: "Pro",
            primaryUsage: 28, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 11 * 86400,
            primaryResetDescription: "in 11 days",
            secondary: nil,
            thirtyDayCostUSD: 2.80, sessionCostUSD: 0.11),
        .init(
            providerID: "mistral", providerName: "Mistral",
            accountLocal: "le", loginMethod: "Le Chat",
            primaryUsage: 18, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 7,
            primaryResetDescription: "in 7 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.85, sessionCostUSD: 0.03),
        // iOS 1.6.0 catch-up: 11 simple mocks for the v0.24+v0.25
        // providers added in 1c95d6e7. providerIDs match Mac's
        // `UsageProvider` enum raw values (verified against upstream
        // ProviderDescriptors). Picked usage / cost values are
        // representative but arbitrary — the goal is exercising every
        // iOS native-render path (color, icon, card layout) for each
        // new provider, not modeling real billing.
        // Simple-mock count: 24 → 35; total mock count: 32 → 43.
        .init(
            providerID: "openai", providerName: "OpenAI",
            accountLocal: "api", loginMethod: "API Credits",
            primaryUsage: 35, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 18 * 86400,
            primaryResetDescription: "in 18 days",
            secondary: nil,
            thirtyDayCostUSD: 8.50, sessionCostUSD: 0.45),
        .init(
            providerID: "manus", providerName: "Manus",
            accountLocal: "agent", loginMethod: "Pro",
            primaryUsage: 50, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 14 * 86400,
            primaryResetDescription: "in 14 days",
            secondary: nil,
            thirtyDayCostUSD: 3.20, sessionCostUSD: 0.18),
        .init(
            providerID: "windsurf", providerName: "Windsurf",
            accountLocal: "dev", loginMethod: "Pro",
            primaryUsage: 42, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 15,
            primaryResetDescription: "in 15 hours",
            secondary: nil,
            thirtyDayCostUSD: 2.20, sessionCostUSD: 0.10),
        .init(
            providerID: "mimo", providerName: "Xiaomi MiMo",
            accountLocal: "ai", loginMethod: "Plus",
            primaryUsage: 15, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 13,
            primaryResetDescription: "in 13 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.40, sessionCostUSD: 0.02),
        .init(
            providerID: "doubao", providerName: "Doubao",
            accountLocal: "api", loginMethod: "Pro",
            primaryUsage: 22, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 9,
            primaryResetDescription: "in 9 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.55, sessionCostUSD: 0.02),
        .init(
            providerID: "deepseek", providerName: "DeepSeek",
            accountLocal: "credits", loginMethod: "Funded",
            primaryUsage: 38, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 21 * 86400,
            primaryResetDescription: "in 21 days",
            secondary: nil,
            thirtyDayCostUSD: 1.50, sessionCostUSD: 0.07),
        .init(
            providerID: "codebuff", providerName: "Codebuff",
            accountLocal: "team", loginMethod: "Pro",
            primaryUsage: 58, primaryLabel: "Weekly",
            primaryWindowMinutes: 10080,
            primaryResetsInSeconds: 3 * 86400,
            primaryResetDescription: "in 3 days",
            secondary: nil,
            thirtyDayCostUSD: 2.90, sessionCostUSD: 0.14),
        .init(
            providerID: "crof", providerName: "Crof",
            accountLocal: "api", loginMethod: "Funded",
            primaryUsage: 12, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 24 * 86400,
            primaryResetDescription: "in 24 days",
            secondary: nil,
            thirtyDayCostUSD: 0.30, sessionCostUSD: 0.01),
        .init(
            providerID: "venice", providerName: "Venice",
            accountLocal: "diem", loginMethod: "Trial",
            primaryUsage: 8, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 28 * 86400,
            primaryResetDescription: "in 28 days",
            secondary: nil,
            thirtyDayCostUSD: 0.15, sessionCostUSD: 0.005),
        .init(
            providerID: "commandcode", providerName: "Command Code",
            accountLocal: "build", loginMethod: "Pro",
            primaryUsage: 65, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 9 * 86400,
            primaryResetDescription: "in 9 days",
            secondary: nil,
            thirtyDayCostUSD: 6.50, sessionCostUSD: 0.32),
        .init(
            providerID: "stepfun", providerName: "StepFun",
            accountLocal: "plan", loginMethod: "Oasis",
            primaryUsage: 30, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 3600 * 11,
            primaryResetDescription: "in 11 hours",
            secondary: nil,
            thirtyDayCostUSD: 0.95, sessionCostUSD: 0.04),
        // iOS 1.7.0 — upstream v0.26.0 new providers.
        .init(
            providerID: "moonshot", providerName: "Moonshot / Kimi API",
            accountLocal: "balance", loginMethod: "Funded",
            primaryUsage: 42, primaryLabel: "Balance",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 18 * 86400,
            primaryResetDescription: "Top-up · ¥58.40 left",
            secondary: nil,
            thirtyDayCostUSD: 1.20, sessionCostUSD: 0.06),
        .init(
            providerID: "bedrock", providerName: "AWS Bedrock",
            accountLocal: "cost", loginMethod: "us-east-1",
            primaryUsage: 38, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 19 * 86400,
            primaryResetDescription: "Budget · $19.10 / $50",
            secondary: nil,
            thirtyDayCostUSD: 19.10, sessionCostUSD: 0.55),
        // iOS 1.8.0 — upstream v0.27.0 new providers. Each exercises
        // a different auth + reset shape so the iOS card layout is
        // covered against real-shape data:
        //  - Grok: CLI + grok.com fallback → web-billing daily cost
        //  - GroqCloud: Enterprise Prometheus → request quota window
        //  - ElevenLabs: API key → monthly credit reset (subscription)
        //  - Deepgram: API key → project-level usage breakdown
        //  - LLM Proxy: API key → aggregate quota across providers
        .init(
            providerID: "grok", providerName: "Grok",
            accountLocal: "grok-cli", loginMethod: "API key",
            primaryUsage: 17, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 22 * 86400,
            primaryResetDescription: "Billing · $4.20 / $25",
            secondary: nil,
            thirtyDayCostUSD: 4.20, sessionCostUSD: 0.11),
        .init(
            providerID: "groq", providerName: "GroqCloud",
            accountLocal: "enterprise", loginMethod: "API key (Prometheus)",
            primaryUsage: 24, primaryLabel: "Requests",
            primaryWindowMinutes: 60,
            primaryResetsInSeconds: 42 * 60,
            primaryResetDescription: "Hourly · 24% used",
            secondary: nil,
            thirtyDayCostUSD: 0.32, sessionCostUSD: 0.01),
        .init(
            providerID: "elevenlabs", providerName: "ElevenLabs",
            accountLocal: "voice", loginMethod: "API key",
            primaryUsage: 31, primaryLabel: "Characters",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 14 * 86400,
            primaryResetDescription: "Monthly · 30,500 / 100k chars",
            secondary: nil,
            // Subscription-based credit (character allowance), not USD
            // spend — same pattern as ollama (local) and antigravity-team
            // (preview): nil cost means "no cost reporting", excluded
            // from the iOS Cost dashboard.
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "deepgram", providerName: "Deepgram",
            accountLocal: "speech", loginMethod: "API key",
            primaryUsage: 11, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 12 * 86400,
            primaryResetDescription: "Project · $1.10 / $10",
            secondary: nil,
            thirtyDayCostUSD: 1.10, sessionCostUSD: 0.02),
        .init(
            providerID: "llmproxy", providerName: "LLM Proxy",
            accountLocal: "proxy", loginMethod: "API key",
            primaryUsage: 46, primaryLabel: "Daily quota",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 9 * 3600,
            primaryResetDescription: "Daily · 46% used (4 providers)",
            secondary: nil,
            thirtyDayCostUSD: 8.40, sessionCostUSD: 0.18),
        // iOS 1.9.0 — upstream v0.28.0+v0.29.0 new providers. All map to the
        // GENERIC UsageSnapshot path (primary/secondary RateWindows), so they
        // exercise the same generic iOS rendering as the simple mocks above:
        //  - Azure OpenAI: API key + endpoint → deployment-status usage window
        //  - Alibaba Token Plan (Bailian): cookies → monthly token-plan quota
        //  - T3 Chat: web session → 4-hour base window + monthly overage window
        // All three are credit/subscription/quota based (no USD spend), so cost
        // is nil — same pattern as elevenlabs/ollama (excluded from Cost board).
        .init(
            providerID: "azureopenai", providerName: "Azure OpenAI",
            accountLocal: "deployment", loginMethod: "API key",
            primaryUsage: 38, primaryLabel: "Deployment",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 11 * 3600,
            primaryResetDescription: "Daily · 38% used",
            secondary: nil,
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "alibabatokenplan", providerName: "Alibaba Token Plan",
            accountLocal: "bailian", loginMethod: "Bailian cookies",
            primaryUsage: 52, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 15 * 86400,
            primaryResetDescription: "Monthly · 520k / 1M credits used",
            secondary: nil,
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "t3chat", providerName: "T3 Chat",
            accountLocal: "pro", loginMethod: "Web session",
            primaryUsage: 27, primaryLabel: "Base",
            primaryWindowMinutes: 240,
            primaryResetsInSeconds: 2 * 3600,
            primaryResetDescription: "Base · resets in 2h",
            secondary: .init(
                label: "Overage", usedPercent: 9,
                windowMinutes: 43200,
                resetsInSeconds: 18 * 86400,
                resetDescription: "Overage · 9% used"),
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        // iOS 1.12.0 — upstream v0.34.0 new provider.
        .init(
            providerID: "devin", providerName: "Devin",
            accountLocal: "org", loginMethod: "Browser session",
            primaryUsage: 41, primaryLabel: "Daily",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 8 * 3600,
            primaryResetDescription: "Daily · 41% used",
            secondary: .init(
                label: "Weekly", usedPercent: 22,
                windowMinutes: 10080,
                resetsInSeconds: 5 * 86400,
                resetDescription: "Weekly · 22% used"),
            thirtyDayCostUSD: 12.00, sessionCostUSD: 0.35),
        // iOS 1.13.0 — upstream v0.36.0+v0.36.1 new providers. These
        // all use the generic shared snapshot path: primary/secondary
        // windows and optional cost summary. That is enough to exercise
        // iOS provider grouping, colors, quota subscriptions, and cost
        // dashboard inclusion without adding a new typed wire schema.
        .init(
            providerID: "litellm", providerName: "LiteLLM",
            accountLocal: "proxy", loginMethod: "Virtual key",
            primaryUsage: 63, primaryLabel: "Team budget",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 10 * 86400,
            primaryResetDescription: "Monthly · 63% used",
            secondary: .init(
                label: "Personal", usedPercent: 34,
                windowMinutes: 43200,
                resetsInSeconds: 10 * 86400,
                resetDescription: "Personal · 34% used"),
            thirtyDayCostUSD: 14.20, sessionCostUSD: 0.62),
        .init(
            providerID: "poe", providerName: "Poe",
            accountLocal: "points", loginMethod: "API key",
            primaryUsage: 28, primaryLabel: "Daily points",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 11 * 3600,
            primaryResetDescription: "Daily · 28% used",
            secondary: .init(
                label: "Monthly points", usedPercent: 44,
                windowMinutes: 43200,
                resetsInSeconds: 12 * 86400,
                resetDescription: "Monthly · 44% used"),
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "chutes", providerName: "Chutes",
            accountLocal: "api", loginMethod: "API key",
            primaryUsage: 52, primaryLabel: "Subscription",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 16 * 86400,
            primaryResetDescription: "Monthly · 52% used",
            secondary: .init(
                label: "PAYG", usedPercent: 18,
                windowMinutes: 43200,
                resetsInSeconds: 16 * 86400,
                resetDescription: "PAYG · 18% used"),
            thirtyDayCostUSD: 6.40, sessionCostUSD: 0.21),
        .init(
            providerID: "zed", providerName: "Zed",
            accountLocal: "pro", loginMethod: "Editor session",
            primaryUsage: 36, primaryLabel: "Monthly edits",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 13 * 86400,
            primaryResetDescription: "Monthly · 36% used",
            secondary: .init(
                label: "Plan", usedPercent: 58,
                windowMinutes: 43200,
                resetsInSeconds: 13 * 86400,
                resetDescription: "Zed Pro · 58% used"),
            thirtyDayCostUSD: 9.60, sessionCostUSD: 0.33),
        // iOS 1.17.0 — upstream v0.38.0-v0.39.0 new providers.
        .init(
            providerID: "sakana", providerName: "Sakana AI",
            accountLocal: "console", loginMethod: "Console cookie",
            primaryUsage: 47, primaryLabel: "5-hour",
            primaryWindowMinutes: 300,
            primaryResetsInSeconds: 74 * 60,
            primaryResetDescription: "5-hour · 47% used",
            secondary: .init(
                label: "Weekly", usedPercent: 31,
                windowMinutes: 10080,
                resetsInSeconds: 4 * 86400,
                resetDescription: "Weekly · 31% used"),
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "qoder", providerName: "Qoder",
            accountLocal: "global", loginMethod: "Web cookie",
            primaryUsage: 39, primaryLabel: "Credits",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 17 * 86400,
            primaryResetDescription: "1,950 / 5,000 credits used",
            secondary: nil,
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "crossmodel", providerName: "CrossModel",
            accountLocal: "wallet", loginMethod: "API key",
            primaryUsage: nil, primaryLabel: "Credits",
            primaryWindowMinutes: 1440,
            primaryResetsInSeconds: 0,
            primaryResetDescription: "",
            secondary: nil,
            thirtyDayCostUSD: 5.37, sessionCostUSD: 0.27),
        .init(
            providerID: "clawrouter", providerName: "ClawRouter",
            accountLocal: "router", loginMethod: "API token",
            primaryUsage: 33, primaryLabel: "Monthly budget",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 19 * 86400,
            primaryResetDescription: "Monthly budget · 33% used",
            secondary: .init(
                label: "Requests", usedPercent: 21,
                windowMinutes: 43200,
                resetsInSeconds: 19 * 86400,
                resetDescription: "Requests · 21% used"),
            thirtyDayCostUSD: 3.70, sessionCostUSD: 0.14),
        // Phase G — multi-account second-tab mocks. Each entry below
        // produces a SECOND ProviderUsageSnapshot for an already-
        // present providerID (same provider, different accountLocal
        // → distinct accountEmail → distinct cardIdentityKey). After
        // grouping by providerID in CloudSyncReader → ProviderAccountGroup,
        // iOS Usage list shows ONE row "{Provider} · 2" and the
        // detail view renders a 2-tab segmented control at the top —
        // mirroring Mac's per-provider account tabs.
        //
        // Why these 7 specifically: they're in the canonical
        // TokenAccountSupportCatalog.allProviders fan-out (Phase G1)
        // that was previously absent from the SyncCoordinator multi-
        // account list. Picking 7 from the catalog covers every
        // category (env-injected, cookie-header, manual cookie source,
        // OAuth multi-account) so the iOS tab UI gets exercised
        // against the realistic shape of each. Total mock count
        // 45 → 52, simple-mock count 37 → 44.
        .init(
            providerID: "openai", providerName: "OpenAI",
            accountLocal: "outlook", loginMethod: "API Admin",
            primaryUsage: 12, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 18 * 86400,
            primaryResetDescription: "in 18 days",
            secondary: nil,
            thirtyDayCostUSD: 2.40, sessionCostUSD: 0.09),
        .init(
            providerID: "deepseek", providerName: "DeepSeek",
            accountLocal: "alt", loginMethod: "API Paid",
            primaryUsage: 8, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 22 * 86400,
            primaryResetDescription: "in 22 days",
            secondary: nil,
            thirtyDayCostUSD: 0.42, sessionCostUSD: 0.02),
        .init(
            providerID: "antigravity", providerName: "Antigravity",
            accountLocal: "team", loginMethod: "OAuth",
            primaryUsage: 55, primaryLabel: "Weekly",
            primaryWindowMinutes: 10080,
            primaryResetsInSeconds: 3 * 86400,
            primaryResetDescription: "in 3 days",
            secondary: nil,
            // Antigravity is preview/no-billing — both account mocks
            // use nil cost to match the first-account entry's semantics.
            thirtyDayCostUSD: nil, sessionCostUSD: nil),
        .init(
            providerID: "manus", providerName: "Manus",
            accountLocal: "team", loginMethod: "Team",
            primaryUsage: 70, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 14 * 86400,
            primaryResetDescription: "in 14 days",
            secondary: nil,
            thirtyDayCostUSD: 5.10, sessionCostUSD: 0.28),
        .init(
            providerID: "copilot", providerName: "GitHub Copilot",
            accountLocal: "personal", loginMethod: "GitHub",
            primaryUsage: 22, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 21 * 86400,
            primaryResetDescription: "in 21 days",
            secondary: nil,
            thirtyDayCostUSD: 10.00, sessionCostUSD: 0.50),
        .init(
            providerID: "venice", providerName: "Venice",
            accountLocal: "alt", loginMethod: "Paid",
            primaryUsage: 18, primaryLabel: "Monthly",
            primaryWindowMinutes: 43200,
            primaryResetsInSeconds: 24 * 86400,
            primaryResetDescription: "in 24 days",
            secondary: nil,
            thirtyDayCostUSD: 0.42, sessionCostUSD: 0.015),
        .init(
            providerID: "stepfun", providerName: "StepFun",
            accountLocal: "team", loginMethod: "Step Plan",
            primaryUsage: 65, primaryLabel: "Weekly",
            primaryWindowMinutes: 10080,
            primaryResetsInSeconds: 2 * 86400,
            primaryResetDescription: "in 2 days",
            secondary: nil,
            thirtyDayCostUSD: 1.85, sessionCostUSD: 0.07),
    ]

    /// Returns the v0.26 typed-envelope extras for a given providerID,
    /// or nil. Used by `makeSimpleProviderMock` so the simple-profile
    /// mocks exercise the new iOS detail cards (Kiro / Bedrock /
    /// Moonshot / z.ai hourly / OpenAI Dashboard / Antigravity).
    /// Without this, mock injection mode would silently hide every new
    /// v0.26 card — a real regression vector.
    private static func v026ExtrasFor(providerID: String) -> V026MockExtras? {
        let now = Self.nowReference
        switch providerID {
        case "kiro":
            return V026MockExtras(kiroCredits: SyncKiroCredits(
                planName: "Pro (Mock)",
                creditsUsed: 320,
                creditsTotal: 1000,
                creditsPercent: 32,
                bonusUsed: 45,
                bonusTotal: 200,
                bonusExpiryDays: 19,
                resetsAt: now.addingTimeInterval(86400 * 11)))
        case "bedrock":
            return V026MockExtras(bedrockCost: SyncBedrockCost(
                monthlySpendUSD: 19.10,
                monthlyBudgetUSD: 50.0,
                inputTokens: 4_200_000,
                outputTokens: 1_100_000,
                region: "us-east-1",
                budgetUsedPercent: 38.2,
                updatedAt: now))
        case "moonshot":
            return V026MockExtras(moonshotBalance: SyncMoonshotBalance(
                balanceAmount: 58.40,
                balanceCurrency: "CNY",
                region: "cn-default",
                updatedAt: now))
        case "zai":
            // Build a 24h hourly series with two models — enough to
            // exercise the stacked-bar legend + selection logic.
            var xTime: [Date] = []
            for offset in 0..<24 {
                xTime.append(now.addingTimeInterval(TimeInterval(-3600 * (23 - offset))))
            }
            let glm: [Int?] = (0..<24).map { i in i % 4 == 0 ? 1500 + (i * 200) : nil }
            let glmPlus: [Int?] = (0..<24).map { i in i % 3 == 1 ? 800 + (i * 150) : nil }
            return V026MockExtras(zaiHourlyUsage: SyncZaiHourlyUsage(
                xTime: xTime,
                modelSeries: [
                    SyncZaiModelSeries(modelName: "glm-4.6", tokens: glm),
                    SyncZaiModelSeries(modelName: "glm-4.6-plus", tokens: glmPlus),
                ]))
        case "openai":
            // 30-day daily bucket + top models / line items so iOS
            // OpenAIDashboardSection renders end-to-end.
            let dailyBuckets: [SyncOpenAIDailyBucket] = (1...30).map { day in
                let cost = 1.0 + Double(day % 7) * 0.8
                return SyncOpenAIDailyBucket(
                    dayKey: String(format: "2026-04-%02d", day),
                    costUSD: cost,
                    requests: 60 + day * 5,
                    inputTokens: 12000 + day * 700,
                    cachedInputTokens: 1500 + day * 100,
                    outputTokens: 4000 + day * 200,
                    totalTokens: 16000 + day * 900)
            }
            return V026MockExtras(openAIAPIDashboard: SyncOpenAIAPIDashboard(
                last30Days: SyncOpenAISummary(totalCostUSD: 142.33, totalRequests: 4201, totalTokens: 1_234_567),
                last7Days: SyncOpenAISummary(totalCostUSD: 38.50, totalRequests: 1103, totalTokens: 312_000),
                latestDay: SyncOpenAISummary(totalCostUSD: 5.21, totalRequests: 142, totalTokens: 45321),
                dailyBuckets: dailyBuckets,
                topModels: [
                    SyncOpenAIModelBreakdown(modelName: "gpt-5", requests: 2100, totalTokens: 800_000, costUSD: 0),
                    SyncOpenAIModelBreakdown(modelName: "gpt-5.5", requests: 1400, totalTokens: 380_000, costUSD: 0),
                    SyncOpenAIModelBreakdown(modelName: "gpt-4o-mini", requests: 540, totalTokens: 110_000, costUSD: 0),
                ],
                topLineItems: [
                    SyncOpenAILineItem(name: "Completions", costUSD: 100.40),
                    SyncOpenAILineItem(name: "Embeddings", costUSD: 22.10),
                    SyncOpenAILineItem(name: "Audio", costUSD: 12.83),
                ]))
        case "antigravity":
            return V026MockExtras(antigravityAccounts: SyncMultiAccountList(
                accounts: [
                    SyncMultiAccountEntry(
                        email: "primary-mock@antigravity.test",
                        isActive: true,
                        expiresAt: now.addingTimeInterval(3600 * 12)),
                    SyncMultiAccountEntry(
                        email: "alt-mock@antigravity.test",
                        isActive: false,
                        expiresAt: now.addingTimeInterval(3600 * 36)),
                ],
                activeIndex: 0))
        // iOS 1.9.0 / Mac 0.29.0 parity gap-fills (D / E / G). Each attaches
        // the typed envelope block so the simple mock renders the new iOS
        // detail card instead of only a generic rate window.
        case "openrouter":
            return V026MockExtras(openRouterStats: SyncOpenRouterStats(
                balanceUSD: 7.50,
                totalCreditsUSD: 50.0,
                totalUsageUSD: 42.50,
                usedPercent: 85.0,
                keyUsageDailyUSD: 1.25,
                keyUsageWeeklyUSD: 8.10,
                keyUsageMonthlyUSD: 30.40,
                keyLimitUSD: 100.0,
                rateLimitRequests: 20,
                rateLimitInterval: "10s",
                updatedAt: now))
        case "azureopenai":
            return V026MockExtras(azureOpenAIInfo: SyncAzureOpenAIInfo(
                endpointHost: "my-resource.openai.azure.com",
                deploymentName: "gpt-4o-prod",
                model: "gpt-4o",
                apiVersion: "2024-10-21",
                updatedAt: now))
        case "alibabatokenplan":
            return V026MockExtras(alibabaTokenPlan: SyncAlibabaTokenPlan(
                planName: "Bailian Pro (Mock)",
                usedCredits: 520_000,
                totalCredits: 1_000_000,
                remainingCredits: 480_000,
                resetsAt: now.addingTimeInterval(15 * 86400),
                updatedAt: now))
        case "deepseek":
            return V026MockExtras(deepSeekUsage: SyncDeepSeekUsage(
                todayTokens: 1_250_000,
                monthTokens: 28_400_000,
                todayCost: 0.42,
                monthCost: 9.85,
                todayRequests: 312,
                monthRequests: 7240,
                topModel: "deepseek-chat",
                currency: "USD",
                totalBalanceUSD: nil,
                grantedBalanceUSD: nil,
                toppedUpBalanceUSD: nil,
                daily: [],
                updatedAt: now))
        default:
            return nil
        }
    }

    /// Bundle of v0.26 typed envelope payloads for a single mock. Only
    /// the one matching the provider's specialty is populated. iOS
    /// reads via `ProviderUsageSnapshot.{kiroCredits|bedrockCost|...}`
    /// and dispatches the dedicated detail card per
    /// `Views/ProviderDetailView.swift`.
    private struct V026MockExtras {
        var openAIAPIDashboard: SyncOpenAIAPIDashboard?
        var zaiHourlyUsage: SyncZaiHourlyUsage?
        var kiroCredits: SyncKiroCredits?
        var bedrockCost: SyncBedrockCost?
        var moonshotBalance: SyncMoonshotBalance?
        var antigravityAccounts: SyncMultiAccountList?
        // iOS 1.9.0 / Mac 0.29.0 parity gap-fills (D / E / G).
        var openRouterStats: SyncOpenRouterStats?
        var azureOpenAIInfo: SyncAzureOpenAIInfo?
        var alibabaTokenPlan: SyncAlibabaTokenPlan?
        /// iOS 1.10.0 / Mac 0.31.0 sync 025.
        var deepSeekUsage: SyncDeepSeekUsage?

        init(
            openAIAPIDashboard: SyncOpenAIAPIDashboard? = nil,
            zaiHourlyUsage: SyncZaiHourlyUsage? = nil,
            kiroCredits: SyncKiroCredits? = nil,
            bedrockCost: SyncBedrockCost? = nil,
            moonshotBalance: SyncMoonshotBalance? = nil,
            antigravityAccounts: SyncMultiAccountList? = nil,
            openRouterStats: SyncOpenRouterStats? = nil,
            azureOpenAIInfo: SyncAzureOpenAIInfo? = nil,
            alibabaTokenPlan: SyncAlibabaTokenPlan? = nil,
            deepSeekUsage: SyncDeepSeekUsage? = nil)
        {
            self.openAIAPIDashboard = openAIAPIDashboard
            self.zaiHourlyUsage = zaiHourlyUsage
            self.kiroCredits = kiroCredits
            self.bedrockCost = bedrockCost
            self.moonshotBalance = moonshotBalance
            self.antigravityAccounts = antigravityAccounts
            self.openRouterStats = openRouterStats
            self.azureOpenAIInfo = azureOpenAIInfo
            self.alibabaTokenPlan = alibabaTokenPlan
            self.deepSeekUsage = deepSeekUsage
        }
    }

    private static func v039CrossModelUsage(providerID: String, now: Date) -> SyncCrossModelUsage? {
        guard providerID == "crossmodel" else { return nil }
        return SyncCrossModelUsage(
            currency: "USD",
            balance: 8.06,
            uncollected: 0.42,
            daily: SyncCrossModelUsage.Window(
                cost: 0.27,
                promptTokens: 5200,
                completionTokens: 7267,
                totalTokens: 12467,
                requestCount: 84,
                successCount: 83),
            weekly: SyncCrossModelUsage.Window(
                cost: 1.92,
                promptTokens: 41000,
                completionTokens: 52000,
                totalTokens: 93000,
                requestCount: 526,
                successCount: 520),
            monthly: SyncCrossModelUsage.Window(
                cost: 5.37,
                promptTokens: 110_000,
                completionTokens: 150_000,
                totalTokens: 260_000,
                requestCount: 3166,
                successCount: 3140),
            updatedAt: now)
    }

    /// Builds a `ProviderUsageSnapshot` from a `SimpleProviderProfile`.
    /// Centralizes the boilerplate so the profile table stays compact.
    /// Email format `{accountLocal}-mock@{providerID}.test` matches the
    /// universal mock-detection contract (`.test` TLD).
    private static func makeSimpleProviderMock(
        profile: SimpleProviderProfile) -> ProviderUsageSnapshot
    {
        let now = Self.nowReference
        let email = "\(profile.accountLocal)-mock@\(profile.providerID).test"
        let identityValue = email
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? email
        let primary: SyncRateWindow?
        var rateWindows: [SyncRateWindow] = []
        if let usage = profile.primaryUsage {
            let window = SyncRateWindow(
                label: profile.primaryLabel,
                usedPercent: usage,
                windowMinutes: profile.primaryWindowMinutes,
                resetsAt: now.addingTimeInterval(profile.primaryResetsInSeconds),
                resetDescription: profile.primaryResetDescription)
            primary = window
            rateWindows.append(window)
        } else {
            primary = nil
        }
        var secondary: SyncRateWindow?
        if let secondaryProfile = profile.secondary {
            let window = SyncRateWindow(
                label: secondaryProfile.label,
                usedPercent: secondaryProfile.usedPercent,
                windowMinutes: secondaryProfile.windowMinutes,
                resetsAt: now.addingTimeInterval(secondaryProfile.resetsInSeconds),
                resetDescription: secondaryProfile.resetDescription)
            secondary = window
            rateWindows.append(window)
        }
        var costSummary: SyncCostSummary?
        if let thirtyDayUSD = profile.thirtyDayCostUSD,
           let sessionUSD = profile.sessionCostUSD
        {
            // Synthesize ~55 days of daily history so the CWL ledger + the
            // daily-spend chart have real per-day data (previously only the one
            // Codex mock did, so CWL looked nearly empty). The headline stays
            // anchored to the trailing 30 days — `last30DaysCostUSD` is the
            // 30-day total and `historyDays` is left at the 30-day default, so
            // the provider-detail "N Days" label AND the Cost dashboard's
            // 30-day figure agree. The daily array is intentionally longer than
            // the billing window: it's the history CWL accumulates + the chart
            // renders, not a claim that the window is 55 days.
            let daily = Self.synthDailyTotals(
                days: 55,
                avgPerDay: thirtyDayUSD / 30.0,
                seed: profile.providerID)
            let trailing30 = daily.suffix(30).reduce(0, +)
            costSummary = Self.makeCostSummary(
                sessionUSD: sessionUSD,
                sessionTokens: Int(sessionUSD * 50000),
                thirtyDayUSD: trailing30,
                thirtyDayTokens: Int(trailing30 * 50000),
                dailyTotals: daily)
        }
        let extras = Self.v026ExtrasFor(providerID: profile.providerID)
        let crossModelUsage = Self.v039CrossModelUsage(providerID: profile.providerID, now: now)
        return ProviderUsageSnapshot(
            providerID: profile.providerID,
            providerName: "\(profile.providerName) (\(profile.accountLocal) · Mock)",
            primary: primary,
            secondary: secondary,
            accountEmail: email,
            loginMethod: profile.loginMethod,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: costSummary,
            budget: nil,
            rateWindows: rateWindows,
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "\(profile.providerID):email:\(identityValue)",
            ],
            quotaWarnings: nil,
            openAIAPIDashboard: extras?.openAIAPIDashboard,
            zaiHourlyUsage: extras?.zaiHourlyUsage,
            kiroCredits: extras?.kiroCredits,
            bedrockCost: extras?.bedrockCost,
            moonshotBalance: extras?.moonshotBalance,
            antigravityAccounts: extras?.antigravityAccounts,
            openRouterStats: extras?.openRouterStats,
            azureOpenAIInfo: extras?.azureOpenAIInfo,
            alibabaTokenPlan: extras?.alibabaTokenPlan,
            deepSeekUsage: extras?.deepSeekUsage,
            crossModelUsage: crossModelUsage)
    }
}

// swiftlint:enable multiline_arguments type_body_length
