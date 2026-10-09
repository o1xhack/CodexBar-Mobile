import Foundation

/// One quota window a provider reported in its latest synced snapshot
/// (Research/071). Titles are resolved by the app, which owns the window-label
/// localization, for every shipped localization so the configuration
/// extension can name windows in the reader's language without the sync
/// models.
struct WidgetProviderWindowRecord: Codable, Hashable, Sendable {
    /// Stable window id (`primary`, `secondary`, `claude-weekly-scoped-fable`, ...).
    let id: String
    /// Raw label from the Mac, kept as the last-resort title.
    let label: String?
    let windowMinutes: Int?
    /// Localization identifier (`en`, `zh-Hans`, `zh-Hant`, `ja`) to title.
    let titles: [String: String]?

    init(id: String, label: String?, windowMinutes: Int?, titles: [String: String]? = nil) {
        self.id = id
        self.label = label
        self.windowMinutes = windowMinutes
        self.titles = titles
    }

    func title(preferredLocalizations: [String]) -> String {
        for localization in preferredLocalizations + ["en"] {
            if let title = self.titles?[localization], !title.isEmpty { return title }
        }
        if let label, !label.isEmpty { return label }
        return self.id
    }
}

struct WidgetProviderRecord: Codable, Hashable, Sendable {
    let id: String
    let name: String
    /// Selectable quota windows (Research/071). Nil in catalogues written
    /// before 2.6.0 (237); such providers only offer the default window.
    let windows: [WidgetProviderWindowRecord]?
    /// The window the default choice follows, when there is one.
    let defaultWindowID: String?

    init(
        id: String,
        name: String,
        windows: [WidgetProviderWindowRecord]? = nil,
        defaultWindowID: String? = nil)
    {
        self.id = id
        self.name = name
        self.windows = windows
        self.defaultWindowID = defaultWindowID
    }
}

/// A configuration-only empty slot; never persisted in the provider catalogue.
enum StatusWidgetProviderChoice {
    static let emptyIdentifier = "codexbar-widget-choice:none"

    /// Title of the unused slot, resolved in the calling extension's bundle.
    static var emptyTitle: String {
        String(
            localized: "Not selected",
            comment: "An unused provider slot; leaving every slot unused selects providers automatically.")
    }

    struct Choice: Equatable, Sendable {
        let id: String
        let name: String
    }

    /// Provider picker choices for both widget generations: "Not selected"
    /// first, then the catalogue. An unreadable catalogue still offers
    /// "Not selected", so the picker never fails.
    static func choices(reading read: () throws -> [WidgetProviderRecord]) -> [Choice] {
        let records = (try? read()) ?? []
        return [Choice(id: self.emptyIdentifier, name: self.emptyTitle)]
            + records.map { Choice(id: $0.id, name: $0.name) }
    }
}

/// Quota pace widget window choices (Research/071). A choice identifier is
/// `<providerID>|<windowID>` so a choice made for one provider never applies
/// to another one after the provider changes; the default choice follows the
/// weekly window.
enum QuotaPaceWindowChoice {
    static let defaultIdentifier = "codexbar-widget-window:default"

    struct Option: Equatable, Sendable {
        let identifier: String
        let title: String
        let subtitle: String?
    }

    /// Title of the default choice, resolved in the calling extension's bundle.
    static var defaultTitle: String {
        String(
            localized: "Default (Weekly)",
            comment: "Quota pace widget window choice that follows the weekly quota when the provider has one.")
    }

    /// Window length such as "7 days" or "5 hours", localized by the system.
    static func durationText(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = minutes % 1440 == 0 ? [.day] : minutes % 60 == 0 ? [.hour] : [.minute]
        return formatter.string(from: TimeInterval(minutes * 60))
    }

    static func identifier(providerID: String, windowID: String) -> String {
        "\(providerID)|\(windowID)"
    }

    /// The window id a stored choice selects for `providerID`; nil for the
    /// default choice, an unset value, or a choice made for another provider.
    static func windowID(from identifier: String?, providerID: String) -> String? {
        guard let identifier, identifier != self.defaultIdentifier,
              let separator = identifier.firstIndex(of: "|")
        else { return nil }
        guard identifier[..<separator] == providerID else { return nil }
        let windowID = String(identifier[identifier.index(after: separator)...])
        return windowID.isEmpty ? nil : windowID
    }

    /// Picker options for the configured provider: the default (weekly)
    /// choice first, then every window when the provider has more than one.
    /// A single window is listed only when the default does not reach it
    /// (a lone 5-hour window, or Claude with only a Sonnet or Fable-only
    /// limit); Codex and muse.ai, whose single weekly window is the default,
    /// have nothing to choose.
    static func options(
        for record: WidgetProviderRecord?,
        preferredLocalizations: [String],
        defaultTitle: String,
        durationText: (Int) -> String?) -> [Option]
    {
        let defaultOption = Option(identifier: self.defaultIdentifier, title: defaultTitle, subtitle: nil)
        guard let record, let windows = record.windows, !windows.isEmpty else { return [defaultOption] }
        if windows.count == 1, windows[0].id == record.defaultWindowID { return [defaultOption] }
        let titles = windows.map { $0.title(preferredLocalizations: preferredLocalizations) }
        var counts: [String: Int] = [:]
        for title in titles {
            counts[title, default: 0] += 1
        }
        var seen = Set<String>()
        let windowOptions = zip(windows, titles).compactMap { window, title -> Option? in
            guard seen.insert(window.id).inserted else { return nil }
            let duration = window.windowMinutes.flatMap(durationText)
            // Equal titles (e.g. two "Weekly" lanes) are told apart by length.
            let display = if counts[title, default: 0] > 1, let duration {
                "\(title) · \(duration)"
            } else {
                title
            }
            return Option(
                identifier: self.identifier(providerID: record.id, windowID: window.id),
                title: display,
                subtitle: duration)
        }
        return [defaultOption] + windowOptions
    }
}

enum WidgetProviderCatalogue {
    static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.o1xhack.codexbar")?
            .appendingPathComponent("widget-provider-catalogue-v1.json")
    }

    static func read(from url: URL? = fileURL()) throws -> [WidgetProviderRecord] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([WidgetProviderRecord].self, from: Data(contentsOf: url))
    }

    static func write(_ providers: [WidgetProviderRecord], to url: URL? = fileURL()) throws {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self.merged(providers))
        // Every sync refresh publishes the catalogue; skip unchanged writes.
        if let existing = try? Data(contentsOf: url), existing == data { return }
        try data.write(to: url, options: .atomic)
    }

    /// One record per provider id, sorted by name. Several accounts of one
    /// provider contribute the union of their windows in first-seen order.
    static func merged(_ providers: [WidgetProviderRecord]) -> [WidgetProviderRecord] {
        var order: [String] = []
        var byID: [String: WidgetProviderRecord] = [:]
        for provider in providers {
            guard let existing = byID[provider.id] else {
                order.append(provider.id)
                byID[provider.id] = provider
                continue
            }
            guard let extra = provider.windows else { continue }
            var windows = existing.windows ?? []
            var seen = Set(windows.map(\.id))
            windows += extra.filter { seen.insert($0.id).inserted }
            byID[provider.id] = WidgetProviderRecord(
                id: existing.id,
                name: existing.name,
                windows: windows,
                defaultWindowID: existing.defaultWindowID ?? provider.defaultWindowID)
        }
        return order.compactMap { byID[$0] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
