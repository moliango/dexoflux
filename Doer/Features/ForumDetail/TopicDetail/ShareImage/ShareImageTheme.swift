import UIKit

enum ShareImageTheme: Int, CaseIterable {
    case classic = 0
    case light
    case dark
    case black
    case blue
    case green

    var title: String {
        switch self {
        case .classic: return String(localized: "share.theme.classic", defaultValue: "经典")
        case .light: return String(localized: "share.theme.white", defaultValue: "纯白")
        case .dark: return String(localized: "share.theme.dark", defaultValue: "深色")
        case .black: return String(localized: "share.theme.black", defaultValue: "纯黑")
        case .blue: return String(localized: "share.theme.blue", defaultValue: "蓝调")
        case .green: return String(localized: "share.theme.green", defaultValue: "绿野")
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .classic: return UIColor(red: 0xF9/255, green: 0xF1/255, blue: 0xE4/255, alpha: 1)
        case .light: return .white
        case .dark: return UIColor(red: 0x1E/255, green: 0x1E/255, blue: 0x1E/255, alpha: 1)
        case .black: return .black
        case .blue: return UIColor(red: 0xE8/255, green: 0xF4/255, blue: 0xFC/255, alpha: 1)
        case .green: return UIColor(red: 0xE8/255, green: 0xF5/255, blue: 0xE9/255, alpha: 1)
        }
    }

    var cardColor: UIColor {
        switch self {
        case .classic, .blue, .green: return .white
        case .light: return UIColor(white: 0.96, alpha: 1)
        case .dark: return UIColor(red: 0x2D/255, green: 0x2D/255, blue: 0x2D/255, alpha: 1)
        case .black: return UIColor(white: 0.10, alpha: 1)
        }
    }

    var isDark: Bool {
        self == .dark || self == .black
    }

    var primaryTextColor: UIColor { isDark ? .white : .black }
    var secondaryTextColor: UIColor { isDark ? UIColor.white.withAlphaComponent(0.6) : UIColor.black.withAlphaComponent(0.55) }
    var borderColor: UIColor { isDark ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.08) }

    static func fromIndex(_ index: Int) -> ShareImageTheme {
        ShareImageTheme(rawValue: index) ?? .classic
    }
}

enum ShareImagePreferences {
    private static let themeKey = "share_image_theme_index"

    static var theme: ShareImageTheme {
        get { ShareImageTheme.fromIndex(UserDefaults.standard.integer(forKey: themeKey)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: themeKey) }
    }
}
