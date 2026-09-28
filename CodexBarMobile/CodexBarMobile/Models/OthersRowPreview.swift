import Foundation

enum OthersRowPreview {
    static func title(names: [String]) -> String {
        var seen = Set<String>()
        let distinct = names.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !distinct.isEmpty else { return String(localized: "Others") }

        let preview = distinct.prefix(2).joined(separator: ", ")
            + (distinct.count > 2 ? "…" : "")
        return String(format: String(localized: "Others (%@)"), preview)
    }
}
