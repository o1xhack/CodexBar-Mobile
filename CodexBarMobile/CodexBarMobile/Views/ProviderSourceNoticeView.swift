import CodexBarSync
import SwiftUI

/// Text for the provider source notice, kept separate from the view so it can be tested per language.
struct ProviderSourceNoticeContent: Equatable {
    struct Line: Equatable {
        let text: String
        let detail: String?
    }

    static let resolutionHintKey =
        "To clear this, fix the error on that Mac or turn the provider off there. Archive Macs you no longer use in Settings → About & Sync."

    let title: String
    let lines: [Line]
    let isWarning: Bool

    init?(status: ProviderSourceStatus, now: Date, locale: Locale = .current) {
        guard status.needsNotice(at: now) else { return nil }
        func relative(_ date: Date) -> String {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .named
            return formatter.localizedString(for: min(date, now), relativeTo: now)
        }
        func format(_ key: String, _ arguments: [String]) -> String {
            String(
                format: MobileLocalizedString.value(key, defaultValue: key, locale: locale),
                locale: locale,
                arguments: arguments)
        }

        var lines: [Line] = []
        if let device = status.sourceDeviceName, let captured = status.sourceCapturedAt {
            self.title = status.showsDataFromAnotherMac(at: now)
                ? MobileLocalizedString.value(
                    "Showing data from another Mac",
                    defaultValue: "Showing data from another Mac",
                    locale: locale)
                : MobileLocalizedString.value(
                    "Data may be out of date",
                    defaultValue: "Data may be out of date",
                    locale: locale)
            lines.append(Line(text: format("Data from %@, updated %@.", [device, relative(captured)]), detail: nil))
        } else {
            self.title = MobileLocalizedString.value(
                "No Mac could refresh this provider",
                defaultValue: "No Mac could refresh this provider",
                locale: locale)
        }
        let failures = status.failures(at: now)
        for failure in failures {
            let message = failure.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = failure.isError == false
                ? format("%@ has no usage data for this account.", [failure.deviceName])
                : format("%@ could not refresh %@.", [failure.deviceName, relative(failure.reportedAt)])
            lines.append(Line(text: text, detail: message?.isEmpty == false ? message : nil))
        }
        if let sourceDeviceID = status.report.sourceDeviceID,
           failures.contains(where: { $0.deviceID != sourceDeviceID && $0.isError != false })
        {
            lines.append(Line(
                text: MobileLocalizedString.value(
                    Self.resolutionHintKey,
                    defaultValue: Self.resolutionHintKey,
                    locale: locale),
                detail: nil))
        }
        self.lines = lines
        self.isWarning = status.isWarning(at: now)
    }
}

/// Shown at the top of a provider's detail page when its data comes from another Mac, is old,
/// or another Mac fails to refresh. Callers insert it only when `ProviderSourceNoticeContent`
/// exists, so an empty notice never adds stack spacing; the timeline keeps relative times current.
struct ProviderSourceNoticeView: View {
    let status: ProviderSourceStatus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let content = ProviderSourceNoticeContent(status: self.status, now: context.date) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        content.title,
                        systemImage: content.isWarning ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(content.isWarning ? Color.orange : Color.secondary)
                    ForEach(Array(content.lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .font(.footnote)
                            if let detail = line.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    (content.isWarning ? Color.orange : Color.secondary).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("provider-source-notice")
            }
        }
    }
}
