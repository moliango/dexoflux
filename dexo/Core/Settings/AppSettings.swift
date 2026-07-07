import ObjectiveC
import CoreText
import UIKit

final class AppSettings: DexoObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        registerStoredContentFonts()
        applyLanguage()
    }

    // MARK: - Appearance

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
            guard self != .systemDefault else { return fallback ?? .systemGray }
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

    enum AppIconStyle: String, CaseIterable {
        case primary
        case fluxOrbit = "DexoFluxOrbit"
        case fluxCards = "DexoFluxCards"
        case fluxSignal = "DexoFluxSignal"

        var alternateIconName: String? {
            switch self {
            case .primary: return nil
            case .fluxOrbit, .fluxCards, .fluxSignal: return rawValue
            }
        }

        var title: String {
            switch self {
            case .primary: return String(localized: "settings.app_icon.default")
            case .fluxOrbit: return String(localized: "settings.app_icon.orbit")
            case .fluxCards: return String(localized: "settings.app_icon.cards")
            case .fluxSignal: return String(localized: "settings.app_icon.signal")
            }
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
    }

    func applyLanguage() {
        RuntimeLanguageBundle.shared.apply(language: appLanguage)
    }

    // MARK: - General

    var autoOpenLastForum: Bool {
        get { defaults.bool(forKey: "autoOpenLastForum") }
        set {
            defaults.set(newValue, forKey: "autoOpenLastForum")
            notifyChanged()
        }
    }

    var lastOpenedForumId: Int64? {
        get {
            guard defaults.object(forKey: "lastOpenedForumId") != nil else { return nil }
            return Int64(defaults.integer(forKey: "lastOpenedForumId"))
        }
        set {
            if let value = newValue {
                defaults.set(Int(value), forKey: "lastOpenedForumId")
            } else {
                defaults.removeObject(forKey: "lastOpenedForumId")
            }
            notifyChanged()
        }
    }

    var hasShownAutoOpenPrompt: Bool {
        get { defaults.bool(forKey: "hasShownAutoOpenPrompt") }
        set {
            defaults.set(newValue, forKey: "hasShownAutoOpenPrompt")
            notifyChanged()
        }
    }

    // MARK: - Reading

    var readingComfortMode: Bool {
        get { defaults.bool(forKey: "readingComfortMode") }
        set {
            defaults.set(newValue, forKey: "readingComfortMode")
            notifyChanged()
        }
    }

    var hideScrollIndicators: Bool {
        get { bool(forKey: "hideScrollIndicators", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "hideScrollIndicators")
            notifyChanged()
        }
    }

    enum ContentFontSize: Int, CaseIterable {
        case small = 0
        case standard = 1
        case large = 2
        case extraLarge = 3

        var title: String {
            switch self {
            case .small: return String(localized: "settings.content_font.small")
            case .standard: return String(localized: "settings.content_font.standard")
            case .large: return String(localized: "settings.content_font.large")
            case .extraLarge: return String(localized: "settings.content_font.extra_large")
            }
        }

        var basePointSize: CGFloat {
            switch self {
            case .small: return 16
            case .standard: return 18
            case .large: return 20
            case .extraLarge: return 22
            }
        }
    }

    enum ContentFontFamily: String, CaseIterable {
        case system
        case miSans
        case custom

        var title: String {
            switch self {
            case .system: return String(localized: "settings.font.system")
            case .miSans: return "MiSans"
            case .custom: return String(localized: "settings.font.custom")
            }
        }
    }

    var contentFontSize: ContentFontSize {
        get {
            guard defaults.object(forKey: "contentFontSize") != nil else {
                return .standard
            }
            return ContentFontSize(rawValue: defaults.integer(forKey: "contentFontSize")) ?? .standard
        }
        set {
            defaults.set(newValue.rawValue, forKey: "contentFontSize")
            notifyChanged()
        }
    }

    var contentFontFamily: ContentFontFamily {
        get {
            guard let rawValue = defaults.string(forKey: "contentFontFamily") else {
                return .system
            }
            return ContentFontFamily(rawValue: rawValue) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: "contentFontFamily")
            notifyChanged()
        }
    }

    var customContentFontDisplayName: String? {
        defaults.string(forKey: contentFontDisplayNameKey(for: .custom))
    }

    var miSansContentFontDisplayName: String? {
        defaults.string(forKey: contentFontDisplayNameKey(for: .miSans))
    }

    func contentFontSubtitle(for family: ContentFontFamily) -> String {
        switch family {
        case .system:
            return String(localized: "settings.font.system.subtitle")
        case .miSans:
            if isContentFontFamilyAvailable(.miSans) {
                return miSansContentFontDisplayName ?? String(localized: "settings.font.misans.subtitle")
            }
            return String(localized: "settings.font.misans.need_upload")
        case .custom:
            if let name = customContentFontDisplayName {
                return String(format: String(localized: "settings.font.custom.imported"), name)
            }
            return String(localized: "settings.font.custom.subtitle")
        }
    }

    func isContentFontFamilyAvailable(_ family: ContentFontFamily) -> Bool {
        switch family {
        case .system:
            return true
        case .miSans:
            return activeFontName(for: .miSans) != nil
        case .custom:
            return activeFontName(for: .custom) != nil
        }
    }

    func contentFont(ofSize pointSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        guard let fontName = activeFontName(for: contentFontFamily),
              let font = UIFont(name: fontName, size: pointSize)
        else {
            return .systemFont(ofSize: pointSize, weight: weight)
        }
        return font.applying(weight: weight)
    }

    func contentMonospacedFont(ofSize pointSize: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: pointSize, weight: weight)
    }

    var webContentFontFamilyCSS: String {
        guard let fontName = activeFontName(for: contentFontFamily) else {
            return "-apple-system, BlinkMacSystemFont, sans-serif"
        }
        let escapedName = fontName.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedName)\", -apple-system, BlinkMacSystemFont, sans-serif"
    }

    @discardableResult
    func importContentFont(from sourceURL: URL, targetFamily: ContentFontFamily) throws -> ImportedContentFont {
        guard targetFamily != .system else {
            throw ContentFontImportError.invalidFont
        }

        let allowedExtensions: Set<String> = ["ttf", "otf", "ttc"]
        guard allowedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw ContentFontImportError.unsupportedFileType
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let metadata = try fontMetadata(from: sourceURL)
        if targetFamily == .miSans, !metadata.matchesMiSans {
            throw ContentFontImportError.notMiSans
        }

        let directory = try contentFontsDirectory()
        let destination = directory.appendingPathComponent(fontFileName(for: targetFamily, sourceURL: sourceURL))
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try registerFont(at: destination)

        defaults.set(destination.lastPathComponent, forKey: contentFontFileNameKey(for: targetFamily))
        defaults.set(metadata.postScriptName, forKey: contentFontPostScriptNameKey(for: targetFamily))
        defaults.set(metadata.displayName, forKey: contentFontDisplayNameKey(for: targetFamily))
        contentFontFamily = targetFamily
        return ImportedContentFont(
            postScriptName: metadata.postScriptName,
            displayName: metadata.displayName,
            fileName: destination.lastPathComponent
        )
    }

    struct ImportedContentFont {
        let postScriptName: String
        let displayName: String
        let fileName: String
    }

    enum ContentFontImportError: LocalizedError {
        case invalidFont
        case unsupportedFileType
        case notMiSans

        var errorDescription: String? {
            switch self {
            case .invalidFont:
                return String(localized: "settings.font.import_invalid")
            case .unsupportedFileType:
                return String(localized: "settings.font.import_unsupported")
            case .notMiSans:
                return String(localized: "settings.font.import_not_misans")
            }
        }
    }

    private struct FontMetadata {
        let postScriptName: String
        let displayName: String

        var matchesMiSans: Bool {
            let searchable = "\(postScriptName) \(displayName)".lowercased()
            return searchable.contains("misans") || searchable.contains("mi sans")
        }
    }

    private func registerStoredContentFonts() {
        registerBundledMiSansIfPresent()
        registerStoredContentFont(for: .miSans)
        registerStoredContentFont(for: .custom)
    }

    private func registerBundledMiSansIfPresent() {
        let candidates = [
            ("MiSans-Regular", "ttf"),
            ("MiSans", "ttf"),
            ("MiSans-Regular", "otf"),
            ("MiSans", "otf"),
        ]
        for candidate in candidates {
            guard let url = Bundle.main.url(forResource: candidate.0, withExtension: candidate.1) else {
                continue
            }
            try? registerFont(at: url)
            if defaults.string(forKey: contentFontPostScriptNameKey(for: .miSans)) == nil,
               let metadata = try? fontMetadata(from: url) {
                defaults.set(metadata.postScriptName, forKey: contentFontPostScriptNameKey(for: .miSans))
                defaults.set(metadata.displayName, forKey: contentFontDisplayNameKey(for: .miSans))
            }
            return
        }
    }

    private func registerStoredContentFont(for family: ContentFontFamily) {
        guard family != .system,
              let fileName = defaults.string(forKey: contentFontFileNameKey(for: family))
        else {
            return
        }
        let url = contentFontsDirectoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? registerFont(at: url)
    }

    private func activeFontName(for family: ContentFontFamily) -> String? {
        switch family {
        case .system:
            return nil
        case .miSans:
            if let storedName = defaults.string(forKey: contentFontPostScriptNameKey(for: .miSans)),
               UIFont(name: storedName, size: 17) != nil {
                return storedName
            }
            let candidates = ["MiSans", "MiSans-Regular", "MiSans-Normal"]
            return candidates.first { UIFont(name: $0, size: 17) != nil }
        case .custom:
            guard let storedName = defaults.string(forKey: contentFontPostScriptNameKey(for: .custom)),
                  UIFont(name: storedName, size: 17) != nil
            else {
                return nil
            }
            return storedName
        }
    }

    private var contentFontsDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    private func contentFontsDirectory() throws -> URL {
        let url = contentFontsDirectoryURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fontFileName(for family: ContentFontFamily, sourceURL: URL) -> String {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "ttf" : sourceURL.pathExtension.lowercased()
        switch family {
        case .system:
            return "SystemFont.\(fileExtension)"
        case .miSans:
            return "MiSansImported.\(fileExtension)"
        case .custom:
            return "CustomContentFont.\(fileExtension)"
        }
    }

    private func fontMetadata(from url: URL) throws -> FontMetadata {
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let descriptor = descriptors.first,
           let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
            let displayName = (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String)
                ?? postScriptName
            return FontMetadata(postScriptName: postScriptName, displayName: displayName)
        }
        guard let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider),
              let postScriptName = font.postScriptName as String?
        else {
            throw ContentFontImportError.invalidFont
        }
        let displayName = (font.fullName as String?) ?? postScriptName
        return FontMetadata(postScriptName: postScriptName, displayName: displayName)
    }

    private func registerFont(at url: URL) throws {
        var registrationError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
        if didRegister {
            return
        }
        if let error = registrationError?.takeRetainedValue() {
            let nsError = error as Error as NSError
            if nsError.domain == kCTFontManagerErrorDomain as String,
               nsError.code == CTFontManagerError.alreadyRegistered.rawValue {
                return
            }
        }
        throw ContentFontImportError.invalidFont
    }

    private func contentFontFileNameKey(for family: ContentFontFamily) -> String {
        "contentFont.\(family.rawValue).fileName"
    }

    private func contentFontPostScriptNameKey(for family: ContentFontFamily) -> String {
        "contentFont.\(family.rawValue).postScriptName"
    }

    private func contentFontDisplayNameKey(for family: ContentFontFamily) -> String {
        "contentFont.\(family.rawValue).displayName"
    }

    // MARK: - Bottom Bar

    enum ForumDynamicTabItem: String, CaseIterable {
        case history
        case search
        case notifications
        case messages
        case bookmarks

        var title: String {
            switch self {
            case .history: return String(localized: "tab.history")
            case .search: return String(localized: "search.title")
            case .notifications: return String(localized: "tab.notifications")
            case .messages: return String(localized: "tab.messages")
            case .bookmarks: return String(localized: "me.bookmarks")
            }
        }

        var subtitle: String {
            switch self {
            case .history: return "查看已读和看过的话题"
            case .search: return "搜索帖子和回复"
            case .notifications: return "查看回复、点赞和系统通知"
            case .messages: return "查看论坛私信"
            case .bookmarks: return "查看已收藏内容"
            }
        }

        var symbolName: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .search: return "magnifyingglass"
            case .notifications: return "bell"
            case .messages: return "envelope"
            case .bookmarks: return "bookmark"
            }
        }

        static func storedValue(_ rawValue: String) -> ForumDynamicTabItem? {
            if rawValue == "categories" {
                return .history
            }
            return ForumDynamicTabItem(rawValue: rawValue)
        }
    }

    static let minimumConfiguredForumDynamicTabItems = 1
    static let maximumConfiguredForumDynamicTabItems = 5
    static let maximumVisibleForumDynamicTabItems = 3
    static let defaultForumDynamicTabItems: [ForumDynamicTabItem] = [
        .history,
        .notifications,
        .bookmarks,
    ]

    var bottomBarAutoHideEnabled: Bool {
        get { bool(forKey: "bottomBarAutoHideEnabled", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "bottomBarAutoHideEnabled")
            notifyChanged()
        }
    }

    var forumDynamicTabItems: [ForumDynamicTabItem] {
        get {
            guard let rawValues = defaults.stringArray(forKey: "forumDynamicTabItemIds") else {
                return Self.defaultForumDynamicTabItems
            }
            return Self.sanitizedForumDynamicTabItems(rawValues.compactMap(ForumDynamicTabItem.storedValue))
        }
        set {
            let items = Self.sanitizedForumDynamicTabItems(newValue)
            defaults.set(items.map(\.rawValue), forKey: "forumDynamicTabItemIds")
            notifyChanged()
        }
    }

    var forumVisibleDynamicTabItems: [ForumDynamicTabItem] {
        Array(forumDynamicTabItems.prefix(Self.maximumVisibleForumDynamicTabItems))
    }

    func resetForumDynamicTabItems() {
        forumDynamicTabItems = Self.defaultForumDynamicTabItems
    }

    // MARK: - Home

    var homePinnedCategoryIds: [Int] {
        get {
            defaults.stringArray(forKey: "homePinnedCategoryIds")?
                .compactMap(Int.init) ?? []
        }
        set {
            let uniqueIds = Self.uniqueCategoryIds(newValue)
            defaults.set(uniqueIds.map(String.init), forKey: "homePinnedCategoryIds")
            notifyChanged()
        }
    }

    func addHomePinnedCategoryId(_ categoryId: Int) {
        var ids = homePinnedCategoryIds
        guard !ids.contains(categoryId) else { return }
        ids.append(categoryId)
        homePinnedCategoryIds = ids
    }

    func removeHomePinnedCategoryId(_ categoryId: Int) {
        let ids = homePinnedCategoryIds.filter { $0 != categoryId }
        homePinnedCategoryIds = ids
    }

    // MARK: - DNS over HTTPS

    enum DoHProvider: Int, CaseIterable {
        case cloudflare = 0
        case google = 1
        case quad9 = 2
        case alidns = 3
        case custom = 4
        case dnspod = 5

        var title: String {
            switch self {
            case .cloudflare: return "Cloudflare (1.1.1.1)"
            case .google: return "Google (8.8.8.8)"
            case .quad9: return "Quad9 (9.9.9.9)"
            case .alidns: return "AliDNS (223.5.5.5)"
            case .custom: return String(localized: "doh.provider.custom")
            case .dnspod: return "DNSPod (doh.pub)"
            }
        }

        var url: String {
            switch self {
            case .cloudflare: return "https://cloudflare-dns.com/dns-query"
            case .google: return "https://dns.google/dns-query"
            case .quad9: return "https://dns.quad9.net/dns-query"
            case .alidns: return "https://dns.alidns.com/dns-query"
            case .custom: return ""
            case .dnspod: return "https://doh.pub/dns-query"
            }
        }
    }

    var dohEnabled: Bool {
        get { defaults.bool(forKey: "dohEnabled") }
        set {
            defaults.set(newValue, forKey: "dohEnabled")
            notifyChanged()
        }
    }

    var dohProvider: DoHProvider {
        get {
            guard defaults.object(forKey: "dohProvider") != nil else { return .alidns }
            return DoHProvider(rawValue: defaults.integer(forKey: "dohProvider")) ?? .alidns
        }
        set {
            defaults.set(newValue.rawValue, forKey: "dohProvider")
            notifyChanged()
        }
    }

    var dohCustomURL: String {
        get { defaults.string(forKey: "dohCustomURL") ?? "" }
        set {
            defaults.set(newValue, forKey: "dohCustomURL")
            notifyChanged()
        }
    }

    var dohServerURL: String {
        if dohProvider == .custom {
            return dohCustomURL
        }
        return dohProvider.url
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func uniqueCategoryIds(_ ids: [Int]) -> [Int] {
        var seen = Set<Int>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func sanitizedForumDynamicTabItems(_ items: [ForumDynamicTabItem]) -> [ForumDynamicTabItem] {
        var seen = Set<ForumDynamicTabItem>()
        let uniqueItems = items.filter { seen.insert($0).inserted }
        let limitedItems = Array(uniqueItems.prefix(maximumConfiguredForumDynamicTabItems))
        if limitedItems.count >= minimumConfiguredForumDynamicTabItems {
            return limitedItems
        }
        return Array(defaultForumDynamicTabItems.prefix(minimumConfiguredForumDynamicTabItems))
    }
}

private extension UIFont {
    func applying(weight: UIFont.Weight) -> UIFont {
        guard weight.rawValue >= UIFont.Weight.semibold.rawValue,
              let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitBold))
        else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private final class RuntimeLanguageBundle {
    static let shared = RuntimeLanguageBundle()

    private var didInstallRuntimeBundle = false
    fileprivate var selectedBundle: Bundle?

    func apply(language: AppSettings.AppLanguage) {
        installRuntimeBundleIfNeeded()
        selectedBundle = language.preferredLanguageCodes.lazy.compactMap { code -> Bundle? in
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
            return Bundle(path: path)
        }.first
    }

    private func installRuntimeBundleIfNeeded() {
        guard !didInstallRuntimeBundle else { return }
        object_setClass(Bundle.main, RuntimeLocalizedBundle.self)
        didInstallRuntimeBundle = true
    }
}

private final class RuntimeLocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = RuntimeLanguageBundle.shared.selectedBundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
