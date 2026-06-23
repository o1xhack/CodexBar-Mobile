import Foundation

// Provider-specific sync envelope blocks added in iOS 1.15.0 / Mac 0.37.2.1
// (sync 033) to carry upstream v0.37 Codex rate-limit reset credits and
// confidence metadata to iOS. These ride inside the existing compressed payload;
// all fields are optional at the ProviderUsageSnapshot level, so old Mac and old
// iOS versions remain wire-compatible.

// MARK: - Codex manual rate-limit reset credits (upstream v0.37.0)

/// Structured Codex manual reset-credit state. Populated only on the `codex`
/// provider snapshot when Mac fetched OpenAI's rate-limit reset-credit endpoint.
public struct SyncCodexResetCredits: Codable, Sendable, Equatable {
    public let availableCount: Int
    public let nextExpiresAt: Date?
    public let credits: [SyncCodexResetCredit]
    public let updatedAt: Date

    public init(
        availableCount: Int,
        nextExpiresAt: Date?,
        credits: [SyncCodexResetCredit] = [],
        updatedAt: Date)
    {
        self.availableCount = availableCount
        self.nextExpiresAt = nextExpiresAt
        self.credits = credits
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.availableCount = try container.decodeIfPresent(Int.self, forKey: .availableCount) ?? 0
        self.nextExpiresAt = try container.decodeIfPresent(Date.self, forKey: .nextExpiresAt)
        self.credits = try container.decodeIfPresent([SyncCodexResetCredit].self, forKey: .credits) ?? []
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

/// One manual reset credit. Status is stored as the upstream raw string so future
/// statuses decode without dropping the rest of the payload.
public struct SyncCodexResetCredit: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let resetType: String
    public let status: String
    public let grantedAt: Date
    public let expiresAt: Date?
    public let redeemStartedAt: Date?
    public let redeemedAt: Date?
    public let title: String?
    public let detail: String?

    public init(
        id: String,
        resetType: String,
        status: String,
        grantedAt: Date,
        expiresAt: Date?,
        redeemStartedAt: Date?,
        redeemedAt: Date?,
        title: String? = nil,
        detail: String? = nil)
    {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.redeemStartedAt = redeemStartedAt
        self.redeemedAt = redeemedAt
        self.title = title
        self.detail = detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? "unknown"
        self.resetType = try container.decodeIfPresent(String.self, forKey: .resetType) ?? "unknown"
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        self.grantedAt = try container.decodeIfPresent(Date.self, forKey: .grantedAt) ?? .distantPast
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        self.redeemStartedAt = try container.decodeIfPresent(Date.self, forKey: .redeemStartedAt)
        self.redeemedAt = try container.decodeIfPresent(Date.self, forKey: .redeemedAt)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }
}
