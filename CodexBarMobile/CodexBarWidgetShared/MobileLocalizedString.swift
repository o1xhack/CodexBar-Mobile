import Foundation

/// Locale-explicit lookup in the running bundle (app or widget extension),
/// so reader-language copy can be produced and tested for any locale.
enum MobileLocalizedString {
    static func value(
        _ key: String,
        defaultValue: String,
        locale: Locale = .current) -> String
    {
        let localization = Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: [locale.identifier]).first
        guard let localization,
              let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
        }
        return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
