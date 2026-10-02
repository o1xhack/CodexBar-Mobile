import Foundation

enum QuotaResetDateText {
    /// A fixed Gregorian, 24-hour display in the reader's local time zone.
    static func compact(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "M.d HH:mm"
        return formatter.string(from: date)
    }
}
