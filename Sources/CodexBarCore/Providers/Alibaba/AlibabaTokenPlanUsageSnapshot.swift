import Foundation

public struct AlibabaTokenPlanUsageSnapshot: Sendable {
    public let planName: String?
    public let usedQuota: Double?
    public let totalQuota: Double?
    public let remainingQuota: Double?
    public let resetsAt: Date?
    public let fiveHourUsedPercent: Double?
    public let fiveHourTotalQuota: Double?
    public let fiveHourResetsAt: Date?
    /// Legacy Teams rate-limit window retained for the fork's authenticated
    /// fallback path. Personal/Solo plans use the `weekly*` fields below.
    public let sevenDayUsedPercent: Double?
    public let sevenDayResetsAt: Date?
    public let weeklyUsedPercent: Double?
    public let weeklyTotalQuota: Double?
    public let weeklyResetsAt: Date?
    public let updatedAt: Date

    public init(
        planName: String?,
        usedQuota: Double?,
        totalQuota: Double?,
        remainingQuota: Double?,
        resetsAt: Date?,
        fiveHourUsedPercent: Double? = nil,
        fiveHourTotalQuota: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayUsedPercent: Double? = nil,
        sevenDayResetsAt: Date? = nil,
        weeklyUsedPercent: Double? = nil,
        weeklyTotalQuota: Double? = nil,
        weeklyResetsAt: Date? = nil,
        updatedAt: Date)
    {
        self.planName = planName
        self.usedQuota = usedQuota
        self.totalQuota = totalQuota
        self.remainingQuota = remainingQuota
        self.resetsAt = resetsAt
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.fiveHourTotalQuota = fiveHourTotalQuota
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayUsedPercent = sevenDayUsedPercent
        self.sevenDayResetsAt = sevenDayResetsAt
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyTotalQuota = weeklyTotalQuota
        self.weeklyResetsAt = weeklyResetsAt
        self.updatedAt = updatedAt
    }
}

extension AlibabaTokenPlanUsageSnapshot {
    func mergingSubscriptionSummary(_ summary: Self) -> Self {
        Self(
            planName: summary.planName ?? self.planName,
            usedQuota: summary.usedQuota,
            totalQuota: summary.totalQuota,
            remainingQuota: summary.remainingQuota,
            resetsAt: summary.resetsAt,
            fiveHourUsedPercent: self.fiveHourUsedPercent,
            fiveHourTotalQuota: self.fiveHourTotalQuota,
            fiveHourResetsAt: self.fiveHourResetsAt,
            sevenDayUsedPercent: self.sevenDayUsedPercent,
            sevenDayResetsAt: self.sevenDayResetsAt,
            weeklyUsedPercent: self.weeklyUsedPercent,
            weeklyTotalQuota: self.weeklyTotalQuota,
            weeklyResetsAt: self.weeklyResetsAt,
            updatedAt: max(self.updatedAt, summary.updatedAt))
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let monthlyCredits: RateWindow? = Self.usedPercent(
            used: self.usedQuota,
            total: self.totalQuota,
            remaining: self.remainingQuota).map {
            RateWindow(
                usedPercent: $0,
                windowMinutes: 30 * 24 * 60,
                resetsAt: self.resetsAt,
                resetDescription: Self.quotaDetail(
                    used: self.usedQuota,
                    total: self.totalQuota,
                    remaining: self.remainingQuota))
        }
        let fiveHour = self.fiveHourUsedPercent.map {
            RateWindow(
                usedPercent: $0,
                windowMinutes: 5 * 60,
                resetsAt: self.fiveHourResetsAt,
                resetDescription: Self.quotaDetail(usedPercent: $0, total: self.fiveHourTotalQuota))
        }
        let weeklyPercent = self.weeklyUsedPercent ?? self.sevenDayUsedPercent
        let weeklyReset = self.weeklyUsedPercent == nil ? self.sevenDayResetsAt : self.weeklyResetsAt
        let weekly = weeklyPercent.map {
            RateWindow(
                usedPercent: $0,
                windowMinutes: 7 * 24 * 60,
                resetsAt: weeklyReset,
                resetDescription: Self.quotaDetail(usedPercent: $0, total: self.weeklyTotalQuota))
        }
        // Keep the rolling windows in their semantic lanes even when Alibaba
        // returns a partial response. Consumers such as CLI guard and dashboard
        // JSON interpret primary as session and secondary as weekly.
        let hasRollingWindows = fiveHour != nil || weekly != nil
        let primary = hasRollingWindows ? fiveHour : monthlyCredits
        let secondary = hasRollingWindows ? weekly : nil
        let tertiary = hasRollingWindows ? monthlyCredits : nil

        let planName = self.planName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let loginMethod = (planName?.isEmpty ?? true) ? nil : planName
        // Provider-specific by design: This co-located snapshot belongs to the Alibaba Token Plan variant.
        let identity = ProviderIdentitySnapshot(
            providerID: .alibabatokenplan,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: loginMethod)

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            providerCost: nil,
            alibabaTokenPlanUsage: self,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private static func usedPercent(used: Double?, total: Double?, remaining: Double?) -> Double? {
        guard let total, total > 0 else { return nil }
        let usedValue: Double? = if let used {
            used
        } else if let remaining {
            total - remaining
        } else {
            nil
        }
        guard let usedValue else { return nil }
        let normalizedUsed = max(0, min(usedValue, total))
        return normalizedUsed / total * 100
    }

    private static func quotaDetail(used: Double?, total: Double?, remaining: Double?) -> String? {
        if let used, let total, total > 0 {
            return "\(self.format(used)) / \(self.format(total)) credits used"
        }
        if let remaining, let total, total > 0 {
            return "\(Self.format(remaining)) / \(Self.format(total)) credits left"
        }
        if let remaining {
            return "\(Self.format(remaining)) credits left"
        }
        return nil
    }

    private static func quotaDetail(usedPercent: Double, total: Double?) -> String? {
        guard let total, total > 0 else { return nil }
        let used = total * usedPercent / 100
        return "\(Self.format(used)) / \(Self.format(total)) credits used"
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
