import Foundation

/// Parses Qwen Cloud token-plan responses (current shape) and falls back to
/// the legacy Alibaba subscription-summary envelope when the current shape
/// does not contain usable usage data.
enum QwenCloudUsageParser {
    static func parse(
        from usageData: Data,
        subscriptionData: Data?,
        quotaConfigData: Data?,
        now: Date) throws -> QwenCloudUsageSnapshot
    {
        if let raw = try? JSONSerialization.jsonObject(with: usageData),
           let snapshot = QwenCloudUsageSnapshot.personalUsage(
               in: OneConsoleJSON.expandEmbeddedJSON(raw),
               subscriptionData: subscriptionData,
               quotaConfigData: quotaConfigData,
               now: now)
        {
            return snapshot
        }
        do {
            let alibaba = try AlibabaTokenPlanUsageFetcher.parseUsageSnapshot(from: usageData, now: now)
            return QwenCloudUsageSnapshot(alibabaSnapshot: alibaba)
        } catch let error as AlibabaTokenPlanUsageError {
            throw Self.map(error)
        }
    }

    static func parseUsageSnapshot(from data: Data, now: Date = Date()) throws -> QwenCloudUsageSnapshot {
        try self.parse(from: data, subscriptionData: nil, quotaConfigData: nil, now: now)
    }

    private static func map(_ error: AlibabaTokenPlanUsageError) -> QwenCloudUsageError {
        switch error {
        case .loginRequired: .loginRequired
        case .invalidCredentials: .invalidCredentials
        case let .apiError(message): .apiError(message)
        case let .networkError(message): .networkError(message)
        case let .parseFailed(message): .parseFailed(message)
        case .usageWindowsUnavailable: .parseFailed("Usage is temporarily unavailable.")
        }
    }
}
