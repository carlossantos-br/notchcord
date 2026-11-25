import Foundation

/// Tiny localization helper: English by default, Brazilian Portuguese when the
/// user's preferred macOS language is Portuguese (or, if no language is set,
/// when the region is Brazil/Portugal).
enum L {
    static let isPortuguese: Bool = {
        if let lang = Locale.preferredLanguages.first?.lowercased(), !lang.isEmpty {
            return lang.hasPrefix("pt")
        }
        let region = Locale.current.region?.identifier ?? ""
        return region == "BR" || region == "PT"
    }()

    /// Returns the string for the current language.
    static func t(_ en: String, _ pt: String) -> String { isPortuguese ? pt : en }
}
