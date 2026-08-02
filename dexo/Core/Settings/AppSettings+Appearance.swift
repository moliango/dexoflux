import UIKit
import ObjectiveC
import CoreText

// MARK: - Appearance
extension AppSettings {

    enum AppearanceMode: Int, CaseIterable {
        case system = 0
        case light = 1
        case dark = 2

        var title: String {
            switch self {
            case .system: return String(localized: "appearance.system")
            case .light: return String(localized: "appearance.light")
            case .dark: return String(localized: "appearance.dark")
            }
        }

        var userInterfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum PluginDockSide: String, CaseIterable {
        case left
        case right
    }

    enum AppLanguage: String, CaseIterable {
        case simplifiedChinese = "zh-Hans"
        case traditionalChineseTaiwan = "zh-Hant-TW"
        case traditionalChineseHongKong = "zh-Hant-HK"
        case english = "en"

        var title: String {
            switch self {
            case .simplifiedChinese: return String(localized: "settings.language.zh_hans")
            case .traditionalChineseTaiwan: return String(localized: "settings.language.zh_hant_tw")
            case .traditionalChineseHongKong: return String(localized: "settings.language.zh_hk")
            case .english: return String(localized: "settings.language.en")
            }
        }

        var preferredLanguageCodes: [String] {
            switch self {
            case .simplifiedChinese:
                return ["zh-Hans"]
            case .traditionalChineseTaiwan:
                return ["zh-Hant-TW", "zh-Hant", "zh-Hans"]
            case .traditionalChineseHongKong:
                return ["zh-Hant-HK", "zh-HK", "zh-Hant", "zh-Hans"]
            case .english:
                return ["en"]
            }
        }

        static func storedValue(_ rawValue: String) -> AppLanguage? {
            switch rawValue {
            case "zh-Hant", "zh-TW":
                return .traditionalChineseTaiwan
            case "zh-HK":
                return .traditionalChineseHongKong
            default:
                return AppLanguage(rawValue: rawValue)
            }
        }
    }

    enum ThemeStyle: Int, CaseIterable {
        case systemDefault = 0
        case eyeCare = 1
        case xiaohongshu = 2
        case telegram = 3

        var title: String {
            switch self {
            case .systemDefault: return String(localized: "settings.theme.default")
            case .eyeCare: return String(localized: "settings.theme.eye_care")
            case .xiaohongshu: return String(localized: "settings.theme.xiaohongshu")
            case .telegram: return String(localized: "settings.theme.telegram")
            }
        }

        var accentColor: UIColor {
            switch self {
            case .systemDefault: return .systemBlue
            case .eyeCare: return UIColor(red: 0.24, green: 0.55, blue: 0.34, alpha: 1)
            case .xiaohongshu: return UIColor(red: 0.92, green: 0.13, blue: 0.22, alpha: 1)
            case .telegram: return UIColor(red: 0.13, green: 0.55, blue: 0.82, alpha: 1)
            }
        }

        var topicCardBackgroundColor: UIColor {
            switch self {
            case .systemDefault:
                return .secondarySystemGroupedBackground
            case .xiaohongshu:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.18, green: 0.11, blue: 0.12, alpha: 1)
                        : UIColor.white
                }
            case .eyeCare, .telegram:
                return contentBackgroundColor
            }
        }

        var topicListBackgroundColor: UIColor {
            switch self {
            case .systemDefault:
                return .systemGroupedBackground
            case .eyeCare, .xiaohongshu, .telegram:
                return mutedContentBackgroundColor
            }
        }

        var topicChipBackgroundColor: UIColor {
            switch self {
            case .systemDefault:
                return .secondarySystemGroupedBackground
            case .eyeCare, .xiaohongshu, .telegram:
                return mutedContentBackgroundColor
            }
        }

        var topicCountForegroundColor: UIColor {
            switch self {
            case .systemDefault: return .secondaryLabel
            case .eyeCare, .xiaohongshu, .telegram: return accentColor
            }
        }

        var topicCountBackgroundColor: UIColor {
            switch self {
            case .systemDefault: return .tertiarySystemFill
            case .eyeCare, .xiaohongshu, .telegram: return accentColor.withAlphaComponent(0.12)
            }
        }

        var hotTopicColor: UIColor {
            switch self {
            case .systemDefault: return .systemOrange
            case .eyeCare: return UIColor(red: 0.72, green: 0.47, blue: 0.18, alpha: 1)
            case .xiaohongshu: return UIColor(red: 1.0, green: 0.34, blue: 0.40, alpha: 1)
            case .telegram: return UIColor(red: 0.0, green: 0.56, blue: 0.86, alpha: 1)
            }
        }

        func topicTagColor(for seed: String) -> UIColor {
            paletteColor(for: seed, palette: topicTagPalette)
        }

        func topicCategoryColor(for seed: String?, fallback: UIColor?) -> UIColor {
            // Default theme (and optional "original colors" mode) keep server/fallback hues.
            guard self != .systemDefault, AppSettings.shared.themeTaxonomyColorsEnabled else {
                return fallback ?? .systemGray
            }
            return paletteColor(for: seed ?? "", palette: topicCategoryPalette)
        }

        var contentBackgroundColor: UIColor {
            switch self {
            case .systemDefault:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor.secondarySystemGroupedBackground
                        : UIColor.white
                }
            case .eyeCare:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.12, green: 0.16, blue: 0.12, alpha: 1)
                        : UIColor(red: 0.94, green: 0.97, blue: 0.90, alpha: 1)
                }
            case .xiaohongshu:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.18, green: 0.11, blue: 0.12, alpha: 1)
                        : UIColor(red: 1.0, green: 0.96, blue: 0.96, alpha: 1)
                }
            case .telegram:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.08, green: 0.13, blue: 0.18, alpha: 1)
                        : UIColor(red: 0.93, green: 0.97, blue: 1.0, alpha: 1)
                }
            }
        }

        var mutedContentBackgroundColor: UIColor {
            switch self {
            case .systemDefault:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor.tertiarySystemGroupedBackground
                        : UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1)
                }
            case .eyeCare:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.16, green: 0.20, blue: 0.15, alpha: 1)
                        : UIColor(red: 0.89, green: 0.94, blue: 0.84, alpha: 1)
                }
            case .xiaohongshu:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.23, green: 0.12, blue: 0.15, alpha: 1)
                        : UIColor(red: 1.0, green: 0.91, blue: 0.92, alpha: 1)
                }
            case .telegram:
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.10, green: 0.17, blue: 0.23, alpha: 1)
                        : UIColor(red: 0.86, green: 0.94, blue: 1.0, alpha: 1)
                }
            }
        }

        var webAccentHex: String {
            switch self {
            case .systemDefault: return "#0079d3"
            case .eyeCare: return "#3d8c56"
            case .xiaohongshu: return "#eb3349"
            case .telegram: return "#229ed9"
            }
        }

        var webBackgroundHex: String {
            switch self {
            case .systemDefault: return "transparent"
            case .eyeCare: return "#f0f7e7"
            case .xiaohongshu: return "#fff5f5"
            case .telegram: return "#edf8ff"
            }
        }

        var webMutedBackgroundHex: String {
            switch self {
            case .systemDefault: return "#f6f8ff"
            case .eyeCare: return "#e3efd7"
            case .xiaohongshu: return "#ffe8eb"
            case .telegram: return "#dff1ff"
            }
        }

        var webQuoteBorderHex: String {
            switch self {
            case .systemDefault: return "#cccccc"
            case .eyeCare, .xiaohongshu, .telegram: return webAccentHex
            }
        }

        var webBlockquoteBackgroundHex: String {
            switch self {
            case .systemDefault: return "transparent"
            case .eyeCare, .xiaohongshu, .telegram: return webMutedBackgroundHex
            }
        }

        private var topicTagPalette: [UIColor] {
            switch self {
            case .systemDefault:
                return [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal, .systemIndigo]
            case .eyeCare:
                return [
                    UIColor(red: 0.24, green: 0.55, blue: 0.34, alpha: 1),
                    UIColor(red: 0.38, green: 0.62, blue: 0.31, alpha: 1),
                    UIColor(red: 0.57, green: 0.52, blue: 0.25, alpha: 1),
                    UIColor(red: 0.31, green: 0.61, blue: 0.53, alpha: 1),
                    UIColor(red: 0.63, green: 0.45, blue: 0.24, alpha: 1),
                ]
            case .xiaohongshu:
                return [
                    UIColor(red: 0.92, green: 0.13, blue: 0.22, alpha: 1),
                    UIColor(red: 1.0, green: 0.54, blue: 0.42, alpha: 1),
                    UIColor(red: 0.96, green: 0.67, blue: 0.18, alpha: 1),
                    UIColor(red: 0.26, green: 0.71, blue: 0.50, alpha: 1),
                    UIColor(red: 0.18, green: 0.66, blue: 0.78, alpha: 1),
                    UIColor(red: 0.63, green: 0.42, blue: 0.95, alpha: 1),
                    UIColor(red: 0.98, green: 0.38, blue: 0.61, alpha: 1),
                ]
            case .telegram:
                return [
                    UIColor(red: 0.13, green: 0.55, blue: 0.82, alpha: 1),
                    UIColor(red: 0.0, green: 0.64, blue: 0.88, alpha: 1),
                    UIColor(red: 0.26, green: 0.70, blue: 0.93, alpha: 1),
                    UIColor(red: 0.08, green: 0.45, blue: 0.69, alpha: 1),
                    UIColor(red: 0.30, green: 0.62, blue: 0.95, alpha: 1),
                ]
            }
        }

        private var topicCategoryPalette: [UIColor] {
            switch self {
            case .systemDefault:
                return topicTagPalette
            case .eyeCare:
                return [
                    UIColor(red: 0.19, green: 0.48, blue: 0.29, alpha: 1),
                    UIColor(red: 0.45, green: 0.60, blue: 0.25, alpha: 1),
                    UIColor(red: 0.33, green: 0.55, blue: 0.42, alpha: 1),
                ]
            case .xiaohongshu:
                return [
                    UIColor(red: 0.92, green: 0.13, blue: 0.22, alpha: 1),
                    UIColor(red: 1.0, green: 0.50, blue: 0.36, alpha: 1),
                    UIColor(red: 0.25, green: 0.68, blue: 0.46, alpha: 1),
                    UIColor(red: 0.21, green: 0.62, blue: 0.82, alpha: 1),
                    UIColor(red: 0.92, green: 0.58, blue: 0.17, alpha: 1),
                ]
            case .telegram:
                return [
                    UIColor(red: 0.13, green: 0.55, blue: 0.82, alpha: 1),
                    UIColor(red: 0.0, green: 0.47, blue: 0.74, alpha: 1),
                    UIColor(red: 0.27, green: 0.66, blue: 0.90, alpha: 1),
                ]
            }
        }

        private func paletteColor(for seed: String, palette: [UIColor]) -> UIColor {
            guard !palette.isEmpty else { return accentColor }
            let hash = seed.unicodeScalars.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1.value) }
            return palette[Int(hash % UInt64(palette.count))]
        }
    }

    /// Currently only the primary app icon ships. Alternate icons can be reintroduced later.
    enum AppIconStyle: String, CaseIterable {
        case primary

        var alternateIconName: String? { nil }

        var title: String {
            String(localized: "settings.app_icon.default")
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: "appearanceMode")) ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: "appearanceMode")
            applyAppearance()
            notifyChanged()
        }
    }

    var appLanguage: AppLanguage {
        get {
            guard let rawValue = defaults.string(forKey: "appLanguage") else {
                return .simplifiedChinese
            }
            return AppLanguage.storedValue(rawValue) ?? .simplifiedChinese
        }
        set {
            defaults.set(newValue.rawValue, forKey: "appLanguage")
            defaults.set(newValue.preferredLanguageCodes, forKey: "AppleLanguages")
            RuntimeLanguageBundle.shared.apply(language: newValue)
            notifyChanged()
        }
    }

    var themeStyle: ThemeStyle {
        get { ThemeStyle(rawValue: defaults.integer(forKey: "themeStyle")) ?? .systemDefault }
        set {
            defaults.set(newValue.rawValue, forKey: "themeStyle")
            applyAppearance()
            notifyChanged()
        }
    }

    var pluginDockEnabled: Bool {
        get { bool(forKey: "pluginDockEnabled", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "pluginDockEnabled")
            notifyChanged()
        }
    }

    var miniProgramsEnabled: Bool {
        get {
            if defaults.object(forKey: "miniProgramsEnabled") != nil {
                return defaults.bool(forKey: "miniProgramsEnabled")
            }
            return bool(forKey: "pluginDockEnabled", defaultValue: true)
        }
        set {
            guard miniProgramsEnabled != newValue else { return }
            defaults.set(newValue, forKey: "miniProgramsEnabled")
            notifyChanged()
        }
    }

    /// FluxDo 风格：左缘右滑打开分类/标签侧栏。关闭时保持现有分类 tab + 下拉菜单。
    var homeCategoryDrawerSwipeEnabled: Bool {
        get { bool(forKey: "homeCategoryDrawerSwipeEnabled", defaultValue: false) }
        set {
            defaults.set(newValue, forKey: "homeCategoryDrawerSwipeEnabled")
            notifyChanged()
        }
    }

    var autoCheckForUpdates: Bool {
        get { bool(forKey: "autoCheckForUpdates", defaultValue: true) }
        set {
            guard autoCheckForUpdates != newValue else { return }
            defaults.set(newValue, forKey: "autoCheckForUpdates")
            notifyChanged()
        }
    }

    var pluginDockSide: PluginDockSide {
        get {
            defaults.string(forKey: "pluginDockSide").flatMap(PluginDockSide.init(rawValue:)) ?? .right
        }
        set {
            guard pluginDockSide != newValue else { return }
            defaults.set(newValue.rawValue, forKey: "pluginDockSide")
            notifyChanged()
        }
    }

    var pluginDockVerticalPosition: Double {
        get {
            guard defaults.object(forKey: "pluginDockVerticalPosition") != nil else { return 0.72 }
            return Self.normalizedPluginDockVerticalPosition(defaults.double(forKey: "pluginDockVerticalPosition"))
        }
        set {
            let value = Self.normalizedPluginDockVerticalPosition(newValue)
            guard abs(pluginDockVerticalPosition - value) > 0.0001 else { return }
            defaults.set(value, forKey: "pluginDockVerticalPosition")
            notifyChanged()
        }
    }

    private static func normalizedPluginDockVerticalPosition(_ value: Double) -> Double {
        guard value.isFinite else { return 0.72 }
        return min(max(value, 0), 1)
    }

    var xiaohongshuCardsStaggered: Bool {
        get { bool(forKey: "xiaohongshuCardsStaggered", defaultValue: false) }
        set {
            defaults.set(newValue, forKey: "xiaohongshuCardsStaggered")
            notifyChanged()
        }
    }

    /// When true, category/tag chips use the active theme palettes.
    /// When false, keep Discourse/default colors (same as the default theme path).
    var themeTaxonomyColorsEnabled: Bool {
        get { bool(forKey: "themeTaxonomyColorsEnabled", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "themeTaxonomyColorsEnabled")
            notifyChanged()
        }
    }

    var appIconStyle: AppIconStyle {
        get {
            if let activeName = UIApplication.shared.alternateIconName,
               let active = AppIconStyle(rawValue: activeName) {
                return active
            }
            guard let storedValue = defaults.string(forKey: "appIconStyle") else {
                return .primary
            }
            return AppIconStyle(rawValue: storedValue) ?? .primary
        }
    }

    func setAppIconStyle(_ style: AppIconStyle, completion: ((Error?) -> Void)? = nil) {
        let applyStoredValue = {
            self.defaults.set(style.rawValue, forKey: "appIconStyle")
            self.notifyChanged()
            completion?(nil)
        }

        guard style != appIconStyle else {
            completion?(nil)
            return
        }

        guard UIApplication.shared.supportsAlternateIcons else {
            completion?(AppIconChangeError.unsupported)
            return
        }

        UIApplication.shared.setAlternateIconName(style.alternateIconName) { error in
            DispatchQueue.main.async {
                if let error {
                    completion?(error)
                    return
                }
                applyStoredValue()
            }
        }
    }

    enum AppIconChangeError: LocalizedError {
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return String(localized: "settings.app_icon.unsupported")
            }
        }
    }

    func applyAppearance() {
        let style = appearanceMode.userInterfaceStyle
        let tintColor = themeStyle.accentColor
        UINavigationBar.appearance().tintColor = tintColor
        UITabBar.appearance().tintColor = tintColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
                window.tintColor = tintColor
            }
        }
        refreshVisibleAppFonts()
        resetUnsupportedAlternateAppIconIfNeeded()
    }

    /// Alternate icons were removed; force primary if an old alternate is still active.
    private func resetUnsupportedAlternateAppIconIfNeeded() {
        guard UIApplication.shared.alternateIconName != nil else {
            if defaults.string(forKey: "appIconStyle") != AppIconStyle.primary.rawValue {
                defaults.set(AppIconStyle.primary.rawValue, forKey: "appIconStyle")
            }
            return
        }
        UIApplication.shared.setAlternateIconName(nil) { [weak self] _ in
            self?.defaults.set(AppIconStyle.primary.rawValue, forKey: "appIconStyle")
        }
    }

    func applyLanguage() {
        RuntimeLanguageBundle.shared.apply(language: appLanguage)
    }
}
