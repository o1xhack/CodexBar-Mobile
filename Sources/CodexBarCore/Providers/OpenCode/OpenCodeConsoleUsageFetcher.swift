import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Console reads stay scoped to one workspace, even when its legacy session is also available.
enum OpenCodeConsoleUsageFetcher {
    static func fetchWorkspaceID(
        cookieHeader: String,
        timeout: TimeInterval,
        transport: any ProviderHTTPTransport) async throws -> String
    {
        let text = try await self.fetchText(
            url: OpenCodeGoUsageFetcher.consoleWorkspacesURL,
            workspaceID: nil,
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        guard let workspaceID = OpenCodeGoUsageFetcher.parseConsoleWorkspaceIDs(text: text).first else {
            throw OpenCodeUsageError.parseFailed("Missing Console workspace id.")
        }
        return workspaceID
    }

    static func fetchUsage(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        now: Date,
        transport: any ProviderHTTPTransport) async throws -> OpenCodeUsageSnapshot
    {
        let text = try await self.fetchText(
            url: OpenCodeGoUsageFetcher.consoleGoStatusURL,
            workspaceID: workspaceID,
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        if let quota = OpenCodeGoUsageFetcher.parseConsoleGoStatus(text: text, now: now) {
            return OpenCodeUsageSnapshot(quota: quota)
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              object is NSNull || (object as? [String: Any])?["access"] is NSNull
        else { throw OpenCodeUsageError.parseFailed("Invalid Console usage payload.") }

        // A successful null Go status means no quota. Confirm the workspace's subscription state
        // before publishing spend alone; malformed or inaccessible quota is not a PAYG account.
        let organizationText = try await self.fetchText(
            url: URL(string: "https://opencode.ai/console/api/orgs/current")!,
            workspaceID: workspaceID,
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        guard let organizationData = organizationText.data(using: .utf8),
              let organization = try? JSONDecoder().decode(Organization.self, from: organizationData),
              !organization.hasGoSubscription
        else { throw OpenCodeUsageError.parseFailed("Console subscription usage is unavailable.") }

        let billingText = try await self.fetchText(
            url: OpenCodeGoUsageFetcher.consoleBillingStatusURL,
            workspaceID: workspaceID,
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        guard let billingData = billingText.data(using: .utf8),
              let billing = try? JSONDecoder().decode(Billing.self, from: billingData),
              billing.mode == "pay-as-you-go"
        else { throw OpenCodeUsageError.parseFailed("No supported Console pay-as-you-go billing is available.") }

        let summaryText = try await self.fetchText(
            url: URL(string: "https://opencode.ai/console/api/usage/summary?range=30d")!,
            workspaceID: workspaceID,
            cookieHeader: cookieHeader,
            timeout: timeout,
            transport: transport)
        let usageUSD = try self.parseSummary(text: summaryText)
        // Unsupported or missing balance data does not erase spend for a confirmed PAYG account.
        let balanceUSD = try? OpenCodeGoZenBalanceParser.parseConsoleBillingStatus(text: billingText)
        return .payAsYouGo(
            .init(monthlyUsageUSD: usageUSD, monthlyLimitUSD: nil, balanceUSD: balanceUSD, period: .last30Days),
            updatedAt: now)
    }

    private struct Organization: Decodable {
        let hasGoSubscription: Bool
    }

    private struct Billing: Decodable {
        let mode: String
    }

    static func parseSummary(text: String) throws -> Double {
        guard let data = text.data(using: .utf8),
              let summary = try? JSONDecoder().decode(Summary.self, from: data)
        else { throw OpenCodeUsageError.parseFailed("Invalid Console usage summary.") }
        return summary.totalCostMicroCents / 100_000_000
    }

    private struct Summary: Decodable {
        let totalCostMicroCents: Double

        private enum CodingKeys: String, CodingKey {
            case totalCostMicroCents
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let raw = try? container.decode(String.self, forKey: .totalCostMicroCents),
               !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
               let value = Double(raw), value.isFinite
            {
                self.totalCostMicroCents = value
            } else {
                self.totalCostMicroCents = try Double(container.decode(UInt64.self, forKey: .totalCostMicroCents))
            }
        }
    }

    private static func fetchText(
        url: URL,
        workspaceID: String?,
        cookieHeader: String,
        timeout: TimeInterval,
        transport: any ProviderHTTPTransport) async throws -> String
    {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("CodexBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let workspaceID {
            request.setValue(workspaceID, forHTTPHeaderField: OpenCodeGoUsageFetcher.consoleWorkspaceHeaderField)
        }
        let response = try await transport.response(for: request)
        try Task.checkCancellation()
        if response.statusCode == 401 { throw OpenCodeUsageError.invalidCredentials }
        guard response.statusCode == 200 else {
            // Console JSON is not a legacy sign-in page. A scope/permission failure is not expired auth.
            throw OpenCodeUsageError.apiError("Console HTTP \(response.statusCode)")
        }
        guard let text = String(data: response.data, encoding: .utf8) else {
            throw OpenCodeUsageError.parseFailed("Console response was not UTF-8.")
        }
        return text
    }
}
