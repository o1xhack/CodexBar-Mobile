import Foundation

enum ProviderPluginDate {
    static func nextDailyReset(now: Date, hour: Double, timeZone identifier: String) throws -> Double {
        guard hour.isFinite, hour.rounded() == hour, (0...23).contains(hour),
              let timeZone = TimeZone(identifier: identifier)
        else {
            throw ProviderPluginError.script("invalid daily reset time zone or hour")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        var candidate = calendar.date(byAdding: .hour, value: Int(hour), to: start)!
        if candidate <= now {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
        }
        return candidate.timeIntervalSince1970 * 1000
    }

    static func addMonths(milliseconds: Double, months: Double, timeZone identifier: String) throws -> Double {
        guard milliseconds.isFinite, abs(milliseconds) <= 8_640_000_000_000_000,
              months.isFinite, months.rounded() == months, abs(months) <= 120_000,
              let timeZone = TimeZone(identifier: identifier)
        else {
            throw ProviderPluginError.script("invalid date, calendar month offset, or time zone")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let result = calendar.date(
            byAdding: .month, value: Int(months), to: Date(timeIntervalSince1970: milliseconds / 1000)),
            abs(result.timeIntervalSince1970) <= 8_640_000_000_000
        else {
            throw ProviderPluginError.script("calendar month result is out of range")
        }
        return result.timeIntervalSince1970 * 1000
    }
}
