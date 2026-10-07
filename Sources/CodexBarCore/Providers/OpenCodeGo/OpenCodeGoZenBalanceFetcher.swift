import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension OpenCodeGoUsageFetcher {
    static let optionalZenBalanceTimeout: TimeInterval = 5
    static let optionalZenBalanceStartDelay: Duration = .milliseconds(25)
    static let optionalZenBalanceJoinGrace: Duration = .milliseconds(250)

    public static func zenDashboardURL(workspaceID raw: String?) -> URL {
        guard let workspaceID = OpenCodeWebParsing.normalizeWorkspaceID(raw),
              let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)")
        else {
            return URL(string: "https://opencode.ai")!
        }
        return url
    }

    static func fetchOptionalZenBalance(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> Double?
    {
        do {
            let balance = try await self.fetchZenBalance(
                workspaceID: workspaceID,
                cookieHeader: cookieHeader,
                timeout: timeout,
                session: session)
            try Task.checkCancellation()
            return balance
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            return nil
        }
    }

    static func completedOptionalZenBalance(
        from task: Task<Double?, Error>,
        timeout: Duration? = Self.optionalZenBalanceJoinGrace) async throws -> Double?
    {
        do {
            return try await self.completedZenBalance(from: task, timeout: timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// The optional balance join bound, measured from when the balance task was created so a slow
    /// subscription cannot stack a second full wait on top of the balance request. The app's short
    /// grace is unchanged; only completeness reads use the optional-balance timeout.
    static func optionalZenBalanceJoinTimeout(
        since startedAt: ContinuousClock.Instant,
        waitForZenBalance: Bool,
        now: ContinuousClock.Instant = ContinuousClock.now) -> Duration
    {
        guard waitForZenBalance else { return self.optionalZenBalanceJoinGrace }
        let elapsed = startedAt.duration(to: now)
        let remaining = Duration.seconds(Self.optionalZenBalanceTimeout) - elapsed
        return max(Duration.zero, remaining)
    }

    static func completedRequiredZenBalance(from task: Task<Double?, Error>) async throws -> Double? {
        try await self.completedZenBalance(from: task, timeout: nil)
    }

    private static func completedZenBalance(
        from task: Task<Double?, Error>,
        timeout: Duration?) async throws -> Double?
    {
        switch await BoundedTaskJoin(sourceTask: task).value(joinGrace: timeout) {
        case let .value(value): value
        case .timedOut: nil
        case let .failure(error): throw error
        }
    }

    static func parseZenBalance(text: String) -> Double? {
        OpenCodeGoZenBalanceParser.parse(text: text)
    }

    static func fetchZenBalance(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> Double?
    {
        try await OpenCodeLegacyFallback.fetch(
            cookieHeader: cookieHeader,
            isUsableLegacyValue: { $0 != nil },
            console: {
                let text = try await self.fetchConsoleText(
                    url: self.consoleBillingStatusURL,
                    workspaceID: workspaceID,
                    cookieHeader: cookieHeader,
                    timeout: timeout,
                    session: session)
                return try OpenCodeGoZenBalanceParser.parseConsoleBillingStatus(text: text)
            },
            legacy: {
                try await self.fetchLegacyZenBalance(
                    workspaceID: workspaceID,
                    cookieHeader: cookieHeader,
                    timeout: timeout,
                    session: session)
            })
    }

    private static func fetchLegacyZenBalance(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> Double?
    {
        let text = try await self.fetchPageText(
            url: self.zenDashboardURL(workspaceID: workspaceID),
            cookieHeader: cookieHeader,
            timeout: timeout,
            session: session)
        if self.looksSignedOut(text: text) {
            throw OpenCodeGoUsageError.invalidCredentials
        }
        if let balance = self.parseZenBalance(text: text) {
            return balance
        }

        let billingText = try await self.fetchZenBillingText(
            workspaceID: workspaceID,
            cookieHeader: cookieHeader,
            timeout: timeout,
            session: session)
        if self.looksSignedOut(text: billingText) {
            throw OpenCodeGoUsageError.invalidCredentials
        }
        return OpenCodeGoZenBalanceParser.parseBillingServerResponse(text: billingText)
    }
}
