import Foundation

// MARK: - ZoomMate credits (upstream v0.46.0)

/// One calendar day's ZoomMate credit consumption.
public struct SyncZoomMateDailyPoint: Codable, Sendable, Equatable {
    public let dayKey: String
    public let creditsUsed: Double

    public init(dayKey: String, creditsUsed: Double) {
        self.dayKey = dayKey
        self.creditsUsed = creditsUsed
    }
}

/// ZoomMate plan credit status plus the optional 30-day consumption history.
/// Every property is optional/additive so an old payload, a partially available
/// ZoomMate response, or a future API shape still renders through the generic
/// quota card without breaking the provider envelope.
public struct SyncZoomMateCredits: Codable, Sendable, Equatable {
    public let budgetCap: Double?
    public let usedCredits: Double?
    public let remainingCredits: Double?
    public let overageCredits: Double?
    public let allowsOverage: Bool?
    public let cycleStartAt: Date?
    public let cycleEndAt: Date?
    public let isQuotaAvailable: Bool?
    public let isUnlimited: Bool?
    public let todayCreditsUsed: Double?
    public let daily: [SyncZoomMateDailyPoint]
    public let updatedAt: Date

    public init(
        budgetCap: Double? = nil,
        usedCredits: Double? = nil,
        remainingCredits: Double? = nil,
        overageCredits: Double? = nil,
        allowsOverage: Bool? = nil,
        cycleStartAt: Date? = nil,
        cycleEndAt: Date? = nil,
        isQuotaAvailable: Bool? = nil,
        isUnlimited: Bool? = nil,
        todayCreditsUsed: Double? = nil,
        daily: [SyncZoomMateDailyPoint] = [],
        updatedAt: Date)
    {
        self.budgetCap = budgetCap
        self.usedCredits = usedCredits
        self.remainingCredits = remainingCredits
        self.overageCredits = overageCredits
        self.allowsOverage = allowsOverage
        self.cycleStartAt = cycleStartAt
        self.cycleEndAt = cycleEndAt
        self.isQuotaAvailable = isQuotaAvailable
        self.isUnlimited = isUnlimited
        self.todayCreditsUsed = todayCreditsUsed
        self.daily = daily
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.budgetCap = try container.decodeIfPresent(Double.self, forKey: .budgetCap)
        self.usedCredits = try container.decodeIfPresent(Double.self, forKey: .usedCredits)
        self.remainingCredits = try container.decodeIfPresent(Double.self, forKey: .remainingCredits)
        self.overageCredits = try container.decodeIfPresent(Double.self, forKey: .overageCredits)
        self.allowsOverage = try container.decodeIfPresent(Bool.self, forKey: .allowsOverage)
        self.cycleStartAt = try container.decodeIfPresent(Date.self, forKey: .cycleStartAt)
        self.cycleEndAt = try container.decodeIfPresent(Date.self, forKey: .cycleEndAt)
        self.isQuotaAvailable = try container.decodeIfPresent(Bool.self, forKey: .isQuotaAvailable)
        self.isUnlimited = try container.decodeIfPresent(Bool.self, forKey: .isUnlimited)
        self.todayCreditsUsed = try container.decodeIfPresent(Double.self, forKey: .todayCreditsUsed)
        self.daily = try container.decodeIfPresent([SyncZoomMateDailyPoint].self, forKey: .daily) ?? []
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}
