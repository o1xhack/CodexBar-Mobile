import CodexBarSync
import Foundation

/// Display values for one synced provider detail row.
///
/// Rows stay canonical display strings on the wire; newer Macs also send optional numeric
/// progress and usage so iOS can draw a bar and re-render a few first-party rows in the
/// user's language. Older payloads without those fields keep their verbatim text.
struct ProviderDetailRowPresentation: Equatable {
    static let claudeCloudCreditsRowID = "claude-cloud-credits"

    let value: String
    let secondaryValue: String?
    /// Fraction of the total consumed, clamped to 0...1 for drawing.
    let progressFraction: Double?
    let isExpired: Bool

    init(
        providerID: String,
        row: SyncProviderDetailSection.Row,
        sectionTitle: String?,
        now: Date = Date(),
        locale: Locale = .current)
    {
        if providerID == "claude", row.id == Self.claudeCloudCreditsRowID {
            self = Self.claudeCloudCredits(row: row, now: now, locale: locale)
            return
        }
        self.value = ProviderDetailLocalization.localizedValue(
            row.value, providerID: providerID, rowLabel: row.label, sectionTitle: sectionTitle, locale: locale)
        self.secondaryValue = row.secondaryValue.map {
            ProviderDetailLocalization.localizedValue(
                $0, providerID: providerID, rowLabel: row.label, sectionTitle: sectionTitle, locale: locale)
        }
        self.progressFraction = row.progress.map(Self.fraction)
        self.isExpired = false
    }

    private init(value: String, secondaryValue: String?, progressFraction: Double?, isExpired: Bool) {
        self.value = value
        self.secondaryValue = secondaryValue
        self.progressFraction = progressFraction
        self.isExpired = isExpired
    }

    static func fraction(_ progress: SyncProviderDetailSection.Row.Progress) -> Double {
        min(1, max(0, progress.used / progress.total))
    }

    /// The Mac writes "Expires <ISO-8601>" or "Expired <ISO-8601>" and an English amount.
    /// The expiry observed by the Mac stays authoritative: once it passes, the cached balance
    /// is shown as expired instead of still spendable.
    private static func claudeCloudCredits(
        row: SyncProviderDetailSection.Row,
        now: Date,
        locale: Locale) -> Self
    {
        let expiry = row.secondaryValue.flatMap(Self.expiryDate)
        let expired = row.value == "Expired" || expiry.map { $0 <= now } == true
        let expiryText = expiry.map { date in
            let formatted = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
            return String(
                format: MobileLocalizedString.value(
                    expired ? "Expired %@" : "Expires %@",
                    defaultValue: expired ? "Expired %@" : "Expires %@",
                    locale: locale),
                locale: locale,
                arguments: [formatted])
        } ?? row.secondaryValue
        if expired {
            return Self(
                value: MobileLocalizedString.value("Expired", defaultValue: "Expired", locale: locale),
                secondaryValue: expiryText,
                progressFraction: nil,
                isExpired: true)
        }
        if row.value == "Unavailable" {
            return Self(
                value: MobileLocalizedString.value("Unavailable", defaultValue: "Unavailable", locale: locale),
                secondaryValue: expiryText,
                progressFraction: nil,
                isExpired: false)
        }
        guard let progress = row.progress, let remaining = row.usageValue else {
            return Self(value: row.value, secondaryValue: expiryText, progressFraction: nil, isExpired: false)
        }
        let currency = FloatingPointFormatStyle<Double>.Currency(code: "USD").locale(locale)
        let format = MobileLocalizedString.value(
            "%@ of %@ remaining",
            defaultValue: "%@ of %@ remaining",
            locale: locale)
        return Self(
            value: String(
                format: format,
                locale: locale,
                arguments: [remaining.formatted(currency), progress.total.formatted(currency)]),
            secondaryValue: expiryText,
            progressFraction: Self.fraction(progress),
            isExpired: false)
    }

    private static func expiryDate(_ secondary: String) -> Date? {
        guard let raw = secondary.split(separator: " ").last else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: String(raw)) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: String(raw))
    }
}
