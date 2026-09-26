import Foundation

/// Shared parser for Alibaba Token Plan Personal/Solo rolling-window responses.
/// Both mainland and international variants expose the same payload contract.
enum AlibabaTokenPlanPersonalUsageParser {
    static func parse(
        from usageData: Data,
        subscriptionData: Data?,
        quotaConfigData: Data?,
        now: Date) throws -> AlibabaTokenPlanUsageSnapshot
    {
        guard !usageData.isEmpty else {
            throw AlibabaTokenPlanUsageError.parseFailed("Empty response body")
        }

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: usageData)
        } catch {
            if let text = String(data: usageData, encoding: .utf8)?.lowercased(),
               text.contains("<html"),
               text.contains("login") || text.contains("sign in") || text.contains("signin")
            {
                throw AlibabaTokenPlanUsageError.loginRequired
            }
            throw AlibabaTokenPlanUsageError.parseFailed("Invalid JSON response")
        }

        let expanded = OneConsoleJSON.expandEmbeddedJSON(raw)
        guard let dictionary = expanded as? [String: Any] else {
            throw AlibabaTokenPlanUsageError.parseFailed("Unexpected payload")
        }
        try AlibabaTokenPlanUsageFetcher.throwIfErrorPayload(dictionary)
        guard let snapshot = AlibabaTokenPlanUsageSnapshot.personalUsage(
            in: expanded,
            subscriptionData: subscriptionData,
            quotaConfigData: quotaConfigData,
            defaultPlanName: "Personal",
            now: now)
        else {
            throw AlibabaTokenPlanUsageError.usageWindowsUnavailable
        }
        return snapshot
    }
}
