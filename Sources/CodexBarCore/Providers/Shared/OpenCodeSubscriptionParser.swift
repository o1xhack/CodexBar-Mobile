import Foundation

/// Legacy dashboard parsing shared by both OpenCode providers. The base provider requires
/// two windows and supports unnamed candidates; Go keeps weekly and monthly windows optional.
struct OpenCodeSubscriptionParser {
    let requiresWeeklyUsage: Bool

    func parseSubscriptionJSON(text: String, now: Date) -> OpenCodeGoUsageSnapshot? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }

        guard let dict = object as? [String: Any] else {
            return self.requiresWeeklyUsage ? self.parseUsageFromCandidates(object: object, now: now) : nil
        }

        let renewsAt = OpenCodeWebParsing.dateValue(from: OpenCodeWebParsing.value(
            from: dict,
            keys: OpenCodeWebParsing.renewAtKeys))
        if let snapshot = self.parseUsageDictionary(dict, now: now, inheritedRenewsAt: renewsAt) {
            return snapshot
        }
        for key in ["data", "result", "usage", "billing", "payload"] {
            if let nested = dict[key] as? [String: Any],
               let snapshot = self.parseUsageDictionary(nested, now: now, inheritedRenewsAt: renewsAt)
            {
                return snapshot
            }
        }
        if let snapshot = self.parseUsageNested(dict, now: now, depth: 0, inheritedRenewsAt: renewsAt) {
            return snapshot
        }
        return self.parseUsageFromCandidates(object: object, now: now, inheritedRenewsAt: renewsAt)
    }

    private func parseUsageDictionary(
        _ dict: [String: Any],
        now: Date,
        inheritedRenewsAt: Date?) -> OpenCodeGoUsageSnapshot?
    {
        let renewsAt = OpenCodeWebParsing
            .dateValue(from: OpenCodeWebParsing.value(from: dict, keys: OpenCodeWebParsing.renewAtKeys)) ??
            inheritedRenewsAt
        if let usage = dict["usage"] as? [String: Any],
           let snapshot = self.parseUsageDictionary(usage, now: now, inheritedRenewsAt: renewsAt)
        {
            return snapshot
        }

        let rollingKeys = ["rollingUsage", "rolling", "rolling_usage", "rollingWindow", "rolling_window"]
        let weeklyKeys = ["weeklyUsage", "weekly", "weekly_usage", "weeklyWindow", "weekly_window"]
        let monthlyKeys = ["monthlyUsage", "monthly", "monthly_usage", "monthlyWindow", "monthly_window"]

        let rolling = rollingKeys.lazy.compactMap { dict[$0] as? [String: Any] }.first
        let weekly = weeklyKeys.lazy.compactMap { dict[$0] as? [String: Any] }.first
        let monthly = self.requiresWeeklyUsage ? nil : monthlyKeys.lazy.compactMap { dict[$0] as? [String: Any] }.first

        guard let rolling, !self.requiresWeeklyUsage || weekly != nil else { return nil }

        return self.buildSnapshot(rolling: rolling, weekly: weekly, monthly: monthly, now: now, renewsAt: renewsAt)
    }

    private func parseUsageNested(
        _ dict: [String: Any],
        now: Date,
        depth: Int,
        inheritedRenewsAt: Date?) -> OpenCodeGoUsageSnapshot?
    {
        if depth > 3 { return nil }
        let renewsAt = OpenCodeWebParsing
            .dateValue(from: OpenCodeWebParsing.value(from: dict, keys: OpenCodeWebParsing.renewAtKeys)) ??
            inheritedRenewsAt
        var rolling: [String: Any]?
        var weekly: [String: Any]?
        var monthly: [String: Any]?

        for (key, value) in dict {
            guard let sub = value as? [String: Any] else { continue }
            let lower = key.lowercased()
            if lower.contains("rolling") || lower.contains("hour") || lower.contains("5h") || lower.contains("5-hour") {
                rolling = sub
            } else if lower.contains("weekly") || lower.contains("week") {
                weekly = sub
            } else if !self.requiresWeeklyUsage, lower.contains("monthly") || lower.contains("month") {
                monthly = sub
            }
        }

        if let rolling, !self.requiresWeeklyUsage || weekly != nil {
            let snapshot = self.buildSnapshot(
                rolling: rolling,
                weekly: weekly,
                monthly: monthly,
                now: now,
                renewsAt: renewsAt)
            if let snapshot { return snapshot }
        }

        for value in dict.values {
            if let sub = value as? [String: Any],
               let snapshot = self.parseUsageNested(
                   sub,
                   now: now,
                   depth: depth + 1,
                   inheritedRenewsAt: renewsAt)
            {
                return snapshot
            }
        }

        return nil
    }

    private func parseUsageFromCandidates(
        object: Any,
        now: Date,
        inheritedRenewsAt: Date? = nil) -> OpenCodeGoUsageSnapshot?
    {
        let candidates = OpenCodeWebParsing.collectWindowCandidates(object: object) { self.parseWindow($0, now: now) }
        guard !candidates.isEmpty else { return nil }

        let rollingCandidates = candidates.filter { candidate in
            candidate.pathLower.contains("rolling") ||
                candidate.pathLower.contains("hour") ||
                candidate.pathLower.contains("5h") ||
                candidate.pathLower.contains("5-hour")
        }
        let weeklyCandidates = candidates.filter { candidate in
            candidate.pathLower.contains("weekly") ||
                candidate.pathLower.contains("week")
        }
        let monthlyCandidates = candidates.filter { candidate in
            candidate.pathLower.contains("monthly") ||
                candidate.pathLower.contains("month")
        }

        let nonRollingIDs = Set((weeklyCandidates + monthlyCandidates).map(\.id))
        let rolling = OpenCodeWebParsing.pickCandidate(
            preferred: rollingCandidates,
            fallback: self.requiresWeeklyUsage ? candidates : candidates.filter { !nonRollingIDs.contains($0.id) },
            pickShorter: true)
        let weekly = OpenCodeWebParsing.pickCandidate(
            preferred: weeklyCandidates,
            fallback: self.requiresWeeklyUsage ? candidates : weeklyCandidates,
            pickShorter: false,
            excluding: rolling?.id)
        let monthly = self.requiresWeeklyUsage ? nil : OpenCodeWebParsing.pickCandidate(
            from: monthlyCandidates.filter { candidate in
                candidate.id != rolling?.id && candidate.id != weekly?.id
            },
            pickShorter: false)

        guard let rolling, !self.requiresWeeklyUsage || weekly != nil else { return nil }

        let renewsAt = OpenCodeWebParsing.dateValue(from: OpenCodeWebParsing.value(
            from: object as? [String: Any] ?? [:],
            keys: OpenCodeWebParsing.renewAtKeys))
            ?? inheritedRenewsAt
        return OpenCodeGoUsageSnapshot(
            hasWeeklyUsage: weekly != nil,
            hasMonthlyUsage: monthly != nil,
            rollingUsagePercent: rolling.percent,
            weeklyUsagePercent: weekly?.percent ?? 0,
            monthlyUsagePercent: monthly?.percent ?? 0,
            rollingResetInSec: rolling.resetInSec,
            weeklyResetInSec: weekly?.resetInSec ?? 0,
            monthlyResetInSec: monthly?.resetInSec ?? 0,
            renewsAt: renewsAt,
            updatedAt: now)
    }

    private func parseWindow(_ dict: [String: Any], now: Date) -> (percent: Double, resetInSec: Int)? {
        OpenCodeGoUsageFetcher.parseWindow(dict, now: now, usesBaseFields: self.requiresWeeklyUsage)
    }

    private func buildSnapshot(
        rolling: [String: Any],
        weekly: [String: Any]?,
        monthly: [String: Any]?,
        now: Date,
        renewsAt: Date?) -> OpenCodeGoUsageSnapshot?
    {
        OpenCodeGoUsageFetcher.buildSnapshot(
            rolling: rolling,
            weekly: weekly,
            monthly: monthly,
            now: now,
            renewsAt: renewsAt,
            usesBaseFields: self.requiresWeeklyUsage)
    }
}
