import ObjectiveC
import CoreText
import UIKit

final class AppSettings: DexoObservableObject {
    static let shared = AppSettings()
    static let topicTitleReferencePointSize: CGFloat = 15
    static let minimumFontScalePercent = 30
    static let maximumFontScalePercent = 150
    static let fontScaleStepPercent = 5
    static let defaultFontScalePercent = 100
    static let defaultInterfaceFontScalePercent = 100
    private static let legacyInterfaceFontDefaultPercent = 85
    private static let interfaceFontDefaultVisualMultiplier: CGFloat = 0.85

    private let defaults = UserDefaults.standard

    private override init() {
        super.init()
        migrateFontScaleSettingsIfNeeded()
        migrateLegacyCustomContentFontIfNeeded()
        registerStoredContentFonts()
        applyLanguage()
    }

    static func normalizedFontScalePercent(_ value: Int) -> Int {
        min(max(value, minimumFontScalePercent), maximumFontScalePercent)
    }

    private func migrateFontScaleSettingsIfNeeded() {
        if defaults.object(forKey: "contentFontScalePercent") == nil,
           defaults.object(forKey: "contentFontSize") != nil {
            let legacySize = ContentFontSize(rawValue: defaults.integer(forKey: "contentFontSize")) ?? .standard
            defaults.set(legacySize.legacyScalePercent, forKey: "contentFontScalePercent")
            defaults.set(ContentFontSize.standard.rawValue, forKey: "contentFontSize")
        }
        migrateInterfaceFontScaleBaselineIfNeeded()
    }

    private func migrateInterfaceFontScaleBaselineIfNeeded() {
        let migrationKey = "interfaceFontScaleBaselineV2"
        guard !defaults.bool(forKey: migrationKey) else { return }
        if defaults.object(forKey: "interfaceFontScalePercent") != nil {
            let oldValue = Self.normalizedFontScalePercent(defaults.integer(forKey: "interfaceFontScalePercent"))
            let migratedValue = Int((CGFloat(oldValue) / CGFloat(Self.legacyInterfaceFontDefaultPercent) * CGFloat(Self.defaultInterfaceFontScalePercent)).rounded())
            defaults.set(Self.normalizedFontScalePercent(migratedValue), forKey: "interfaceFontScalePercent")
        }
        defaults.set(true, forKey: migrationKey)
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
        refreshVisibleAppFonts()
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

    var clearImageCacheOnLaunch: Bool {
        get { defaults.bool(forKey: "clearImageCacheOnLaunch") }
        set {
            defaults.set(newValue, forKey: "clearImageCacheOnLaunch")
            notifyChanged()
        }
    }

    func makePreferencesBackupData() throws -> Data {
        let file = PreferencesBackupFile(
            format: Self.preferencesBackupFormat,
            version: 1,
            exportedAt: Date(),
            preferences: PreferencesBackupPayload(
                appearanceMode: appearanceMode.rawValue,
                appLanguage: appLanguage.rawValue,
                themeStyle: themeStyle.rawValue,
                autoOpenLastForum: autoOpenLastForum,
                lastOpenedForumId: lastOpenedForumId,
                hasShownAutoOpenPrompt: hasShownAutoOpenPrompt,
                readingComfortMode: readingComfortMode,
                hideScrollIndicators: hideScrollIndicators,
                contentFontSize: contentFontSize.rawValue,
                contentFontScalePercent: contentFontScalePercent,
                contentFontFamily: contentFontFamily.rawValue,
                contentFontScope: contentFontScope.rawValue,
                interfaceFontScalePercent: interfaceFontScalePercent,
                openExternalLinksInAppBrowser: openExternalLinksInAppBrowser,
                defaultExpandRelatedLinks: defaultExpandRelatedLinks,
                bottomBarAutoHideEnabled: bottomBarAutoHideEnabled,
                forumDynamicTabItems: forumDynamicTabItems.map(\.rawValue),
                homePinnedCategoryIds: homePinnedCategoryIds,
                dohEnabled: dohEnabled,
                dohProvider: dohProvider.rawValue,
                dohCustomURL: dohCustomURL,
                clearImageCacheOnLaunch: clearImageCacheOnLaunch
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    func importPreferencesBackupData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(PreferencesBackupFile.self, from: data)
        guard file.format == Self.preferencesBackupFormat else {
            throw PreferencesBackupError.invalidFile
        }

        let preferences = file.preferences
        if let rawValue = preferences.appearanceMode,
           let value = AppearanceMode(rawValue: rawValue) {
            appearanceMode = value
        }
        if let rawValue = preferences.appLanguage,
           let value = AppLanguage.storedValue(rawValue) {
            appLanguage = value
        }
        if let rawValue = preferences.themeStyle,
           let value = ThemeStyle(rawValue: rawValue) {
            themeStyle = value
        }
        if let value = preferences.autoOpenLastForum {
            autoOpenLastForum = value
        }
        if let value = preferences.lastOpenedForumId {
            lastOpenedForumId = value
        }
        if let value = preferences.hasShownAutoOpenPrompt {
            hasShownAutoOpenPrompt = value
        }
        if let value = preferences.readingComfortMode {
            readingComfortMode = value
        }
        if let value = preferences.hideScrollIndicators {
            hideScrollIndicators = value
        }
        if let rawValue = preferences.contentFontSize,
           let value = ContentFontSize(rawValue: rawValue) {
            if preferences.contentFontScalePercent == nil {
                contentFontSize = .standard
                contentFontScalePercent = value.legacyScalePercent
            } else {
                contentFontSize = value
            }
        }
        if let value = preferences.contentFontScalePercent {
            contentFontScalePercent = value
        }
        if let rawValue = preferences.contentFontFamily,
           let value = ContentFontFamily(rawValue: rawValue) {
            contentFontFamily = isContentFontFamilyAvailable(value) ? value : .system
        }
        if let rawValue = preferences.contentFontScope,
           let value = ContentFontScope(rawValue: rawValue) {
            contentFontScope = value
        }
        if let value = preferences.interfaceFontScalePercent {
            interfaceFontScalePercent = value
        }
        if let value = preferences.openExternalLinksInAppBrowser {
            openExternalLinksInAppBrowser = value
        }
        if let value = preferences.defaultExpandRelatedLinks {
            defaultExpandRelatedLinks = value
        }
        if let value = preferences.bottomBarAutoHideEnabled {
            bottomBarAutoHideEnabled = value
        }
        if let rawValues = preferences.forumDynamicTabItems {
            forumDynamicTabItems = rawValues.compactMap(ForumDynamicTabItem.storedValue)
        }
        if let values = preferences.homePinnedCategoryIds {
            homePinnedCategoryIds = values
        }
        if let value = preferences.dohEnabled {
            dohEnabled = value
        }
        if let rawValue = preferences.dohProvider,
           let value = DoHProvider(rawValue: rawValue) {
            dohProvider = value
        }
        if let value = preferences.dohCustomURL {
            dohCustomURL = value
        }
        if let value = preferences.clearImageCacheOnLaunch {
            clearImageCacheOnLaunch = value
        }
        applyLanguage()
        applyAppearance()
        notifyChanged()
    }

    enum PreferencesBackupError: LocalizedError {
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return String(localized: "settings.data.backup_invalid")
            }
        }
    }

    private static let preferencesBackupFormat = "dexo.preferences.backup"

    private struct PreferencesBackupFile: Codable {
        let format: String
        let version: Int
        let exportedAt: Date
        let preferences: PreferencesBackupPayload
    }

    private struct PreferencesBackupPayload: Codable {
        let appearanceMode: Int?
        let appLanguage: String?
        let themeStyle: Int?
        let autoOpenLastForum: Bool?
        let lastOpenedForumId: Int64?
        let hasShownAutoOpenPrompt: Bool?
        let readingComfortMode: Bool?
        let hideScrollIndicators: Bool?
        let contentFontSize: Int?
        let contentFontScalePercent: Int?
        let contentFontFamily: String?
        let contentFontScope: Int?
        let interfaceFontScalePercent: Int?
        let openExternalLinksInAppBrowser: Bool?
        let defaultExpandRelatedLinks: Bool?
        let bottomBarAutoHideEnabled: Bool?
        let forumDynamicTabItems: [String]?
        let homePinnedCategoryIds: [Int]?
        let dohEnabled: Bool?
        let dohProvider: Int?
        let dohCustomURL: String?
        let clearImageCacheOnLaunch: Bool?
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

    var openExternalLinksInAppBrowser: Bool {
        get { bool(forKey: "openExternalLinksInAppBrowser", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "openExternalLinksInAppBrowser")
            notifyChanged()
        }
    }

    var defaultExpandRelatedLinks: Bool {
        get { defaults.bool(forKey: "defaultExpandRelatedLinks") }
        set {
            defaults.set(newValue, forKey: "defaultExpandRelatedLinks")
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

        var legacyScalePercent: Int {
            switch self {
            case .small: return 90
            case .standard: return 100
            case .large: return 110
            case .extraLarge: return 120
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

    enum ContentFontScope: Int, CaseIterable {
        case readingOnly = 0
        case global = 1
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

    var contentFontScalePercent: Int {
        get {
            guard defaults.object(forKey: "contentFontScalePercent") != nil else {
                return Self.defaultFontScalePercent
            }
            return Self.normalizedFontScalePercent(defaults.integer(forKey: "contentFontScalePercent"))
        }
        set {
            defaults.set(Self.normalizedFontScalePercent(newValue), forKey: "contentFontScalePercent")
            notifyChanged()
        }
    }

    var interfaceFontScalePercent: Int {
        get {
            guard defaults.object(forKey: "interfaceFontScalePercent") != nil else {
                return Self.defaultInterfaceFontScalePercent
            }
            return Self.normalizedFontScalePercent(defaults.integer(forKey: "interfaceFontScalePercent"))
        }
        set {
            let previousMultiplier = interfaceFontScaleMultiplier
            defaults.set(Self.normalizedFontScalePercent(newValue), forKey: "interfaceFontScalePercent")
            refreshVisibleAppFonts(previousInterfaceFontScaleMultiplier: previousMultiplier)
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
            if newValue == .custom,
               selectedImportedCustomContentFont == nil,
               let firstFont = importedCustomContentFonts.first {
                defaults.set(firstFont.id, forKey: selectedImportedContentFontIdKey)
            }
            defaults.set(newValue.rawValue, forKey: "contentFontFamily")
            refreshVisibleAppFonts()
            notifyChanged()
        }
    }

    var contentFontScope: ContentFontScope {
        get {
            guard defaults.object(forKey: "contentFontScope") != nil else {
                return .readingOnly
            }
            return ContentFontScope(rawValue: defaults.integer(forKey: "contentFontScope")) ?? .readingOnly
        }
        set {
            defaults.set(newValue.rawValue, forKey: "contentFontScope")
            refreshVisibleAppFonts()
            notifyChanged()
        }
    }

    var customContentFontDisplayName: String? {
        selectedImportedCustomContentFont?.displayName
            ?? defaults.string(forKey: contentFontDisplayNameKey(for: .custom))
    }

    var miSansContentFontDisplayName: String? {
        defaults.string(forKey: contentFontDisplayNameKey(for: .miSans))
    }

    var importedCustomContentFonts: [ImportedContentFont] {
        storedImportedCustomFonts().filter { importedFontFileExists($0) }
    }

    var selectedImportedCustomContentFont: ImportedContentFont? {
        let fonts = importedCustomContentFonts
        guard !fonts.isEmpty else { return nil }
        if let selectedId = defaults.string(forKey: selectedImportedContentFontIdKey),
           let selectedFont = fonts.first(where: { $0.id == selectedId }) {
            return selectedFont
        }
        return fonts.first
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

    func importedCustomContentFontSubtitle(for font: ImportedContentFont) -> String {
        if selectedImportedCustomContentFont?.id == font.id, contentFontFamily == .custom {
            return String(localized: "settings.font.custom.selected")
        }
        return String(localized: "settings.font.custom.available")
    }

    func selectImportedContentFont(id: String) {
        guard importedCustomContentFonts.contains(where: { $0.id == id }) else { return }
        defaults.set(id, forKey: selectedImportedContentFontIdKey)
        contentFontFamily = .custom
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
            return UIFont.dexoOriginalSystemFont(ofSize: pointSize, weight: weight)
        }
        return font.applying(weight: weight)
    }

    func effectiveContentPointSize(for pointSize: CGFloat) -> CGFloat {
        let scale = CGFloat(contentFontScalePercent) / CGFloat(Self.defaultFontScalePercent)
        let basePointSize: CGFloat
        if activeFontName(for: contentFontFamily) == nil {
            basePointSize = max(pointSize - systemContentFontCompensation(for: pointSize), 1)
        } else {
            basePointSize = pointSize
        }
        // PingFang reads visibly larger than imported content fonts at the same point size,
        // especially in Topic Detail with Dynamic Type scaling.
        return max(basePointSize * scale, 1)
    }

    func effectiveInterfacePointSize(for pointSize: CGFloat) -> CGFloat {
        guard activeGlobalAppFontName() == nil else {
            return pointSize
        }
        if pointSize >= 20 {
            return max(pointSize - 4, 11)
        }
        if pointSize >= 16 {
            return max(pointSize - 3, 11)
        }
        if pointSize >= 13 {
            return max(pointSize - 1.5, 11)
        }
        return pointSize
    }

    func sourceInterfacePointSize(matchingEffectivePointSize effectivePointSize: CGFloat) -> CGFloat {
        var bestPointSize = effectivePointSize
        var bestDelta = CGFloat.greatestFiniteMagnitude
        var candidate = max(effectivePointSize, 11)
        let upperBound = effectivePointSize + 6
        while candidate <= upperBound {
            let delta = abs(effectiveInterfacePointSize(for: candidate) - effectivePointSize)
            if delta < bestDelta {
                bestDelta = delta
                bestPointSize = candidate
            }
            candidate += 0.5
        }
        return bestPointSize
    }

    private func systemContentFontCompensation(for pointSize: CGFloat) -> CGFloat {
        if pointSize >= 22 {
            return 4
        }
        if pointSize >= 20 {
            return 3.5
        }
        return 3
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

    func installGlobalFontSupport() {
        UIFont.installDexoAppFontOverride()
        refreshVisibleAppFonts()
    }

    func appInterfaceFont(ofSize pointSize: CGFloat, weight: UIFont.Weight, fallback: UIFont) -> UIFont {
        let scaledPointSize = scaledInterfacePointSize(for: pointSize)
        guard let fontName = activeGlobalAppFontName(),
              let font = UIFont(name: fontName, size: scaledPointSize)
        else {
            return UIFont.dexoOriginalSystemFont(ofSize: scaledPointSize, weight: weight)
                .dexoMarkAppFontSourcePointSize(pointSize)
        }
        return font.applying(weight: weight).dexoMarkAppFontSourcePointSize(pointSize)
    }

    func appInterfaceFont(matching font: UIFont) -> UIFont {
        guard !font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) else {
            return font
        }

        let sourcePointSize = font.dexoAppFontSourcePointSize ?? font.pointSize
        let pointSize = scaledInterfacePointSize(for: sourcePointSize)
        let weight = font.dexoDetectedWeight
        let traits = font.fontDescriptor.symbolicTraits
        let baseFont: UIFont
        if let fontName = activeGlobalAppFontName(),
           let customFont = UIFont(name: fontName, size: pointSize) {
            baseFont = customFont.applying(weight: weight)
        } else {
            baseFont = UIFont.dexoOriginalSystemFont(ofSize: pointSize, weight: weight)
        }

        guard traits.contains(.traitItalic),
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(baseFont.fontDescriptor.symbolicTraits.union(.traitItalic))
        else {
            return baseFont.dexoMarkAppFontSourcePointSize(sourcePointSize)
        }
        return UIFont(descriptor: descriptor, size: pointSize).dexoMarkAppFontSourcePointSize(sourcePointSize)
    }

    func tabBarItemFont(selected: Bool) -> UIFont {
        UIFont.dexoOriginalSystemFont(ofSize: 10, weight: selected ? .semibold : .regular)
    }

    private func activeGlobalAppFontName() -> String? {
        guard contentFontScope == .global else { return nil }
        return activeFontName(for: contentFontFamily)
    }

    private var interfaceFontScaleMultiplier: CGFloat {
        Self.interfaceFontDefaultVisualMultiplier * CGFloat(interfaceFontScalePercent) / CGFloat(Self.defaultInterfaceFontScalePercent)
    }

    private func scaledInterfacePointSize(for pointSize: CGFloat) -> CGFloat {
        max(pointSize * interfaceFontScaleMultiplier, 1)
    }

    private func refreshVisibleAppFonts(previousInterfaceFontScaleMultiplier: CGFloat? = nil) {
        let baseMultiplier = previousInterfaceFontScaleMultiplier ?? interfaceFontScaleMultiplier
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                refreshAppFonts(in: window, previousInterfaceFontScaleMultiplier: baseMultiplier)
                window.setNeedsLayout()
                window.layoutIfNeeded()
            }
        }
    }

    private func refreshAppFonts(in view: UIView, previousInterfaceFontScaleMultiplier: CGFloat) {
        if view is UITabBar {
            return
        }
        if let label = view as? UILabel {
            label.font = appInterfaceFont(
                matching: baseInterfaceFont(
                    for: label,
                    currentFont: label.font,
                    previousInterfaceFontScaleMultiplier: previousInterfaceFontScaleMultiplier
                )
            )
            invalidateFontLayout(for: label)
        }
        if let button = view as? UIButton, let font = button.titleLabel?.font {
            button.titleLabel?.font = appInterfaceFont(
                matching: baseInterfaceFont(
                    for: button,
                    currentFont: font,
                    previousInterfaceFontScaleMultiplier: previousInterfaceFontScaleMultiplier
                )
            )
            if let titleLabel = button.titleLabel {
                invalidateFontLayout(for: titleLabel)
            }
            invalidateFontLayout(for: button)
        }
        if let textField = view as? UITextField, let font = textField.font {
            textField.font = appInterfaceFont(
                matching: baseInterfaceFont(
                    for: textField,
                    currentFont: font,
                    previousInterfaceFontScaleMultiplier: previousInterfaceFontScaleMultiplier
                )
            )
            invalidateFontLayout(for: textField)
        }
        if let textView = view as? UITextView,
           textView.attributedText.length == textView.text.count,
           let font = textView.font {
            textView.font = appInterfaceFont(
                matching: baseInterfaceFont(
                    for: textView,
                    currentFont: font,
                    previousInterfaceFontScaleMultiplier: previousInterfaceFontScaleMultiplier
                )
            )
            invalidateFontLayout(for: textView)
        }
        for subview in view.subviews {
            refreshAppFonts(in: subview, previousInterfaceFontScaleMultiplier: previousInterfaceFontScaleMultiplier)
        }
    }

    private func baseInterfaceFont(
        for view: UIView,
        currentFont: UIFont,
        previousInterfaceFontScaleMultiplier: CGFloat
    ) -> UIFont {
        if let baseFont = view.dexoBaseInterfaceFont {
            return baseFont
        }
        let safePreviousMultiplier = max(previousInterfaceFontScaleMultiplier, 0.01)
        let sourcePointSize = currentFont.dexoAppFontSourcePointSize ?? (currentFont.pointSize / safePreviousMultiplier)
        let baseFont = UIFont(descriptor: currentFont.fontDescriptor, size: sourcePointSize)
        view.dexoBaseInterfaceFont = baseFont
        return baseFont
    }

    private func invalidateFontLayout(for view: UIView) {
        view.invalidateIntrinsicContentSize()
        view.setNeedsUpdateConstraints()
        view.setNeedsLayout()
        view.superview?.setNeedsUpdateConstraints()
        view.superview?.setNeedsLayout()
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
        let destination = directory.appendingPathComponent(
            targetFamily == .custom
                ? customFontFileName(metadata: metadata, sourceURL: sourceURL)
                : fontFileName(for: targetFamily, sourceURL: sourceURL)
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try registerFont(at: destination)

        let importedFont = ImportedContentFont(
            id: metadata.postScriptName,
            postScriptName: metadata.postScriptName,
            displayName: metadata.displayName,
            fileName: destination.lastPathComponent,
            importedAt: Date()
        )

        defaults.set(destination.lastPathComponent, forKey: contentFontFileNameKey(for: targetFamily))
        defaults.set(metadata.postScriptName, forKey: contentFontPostScriptNameKey(for: targetFamily))
        defaults.set(metadata.displayName, forKey: contentFontDisplayNameKey(for: targetFamily))
        if targetFamily == .custom {
            upsertImportedCustomFont(importedFont)
            defaults.set(importedFont.id, forKey: selectedImportedContentFontIdKey)
        }
        contentFontFamily = targetFamily
        return importedFont
    }

    @discardableResult
    func importCustomContentFonts(from sourceURLs: [URL]) throws -> [ImportedContentFont] {
        var importedFonts: [ImportedContentFont] = []
        for sourceURL in sourceURLs {
            let importedFont = try importContentFont(from: sourceURL, targetFamily: .custom)
            importedFonts.append(importedFont)
        }
        return importedFonts
    }

    struct ImportedContentFont: Codable, Equatable {
        let id: String
        let postScriptName: String
        let displayName: String
        let fileName: String
        let importedAt: Date
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
        registerImportedCustomContentFonts()
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

    private func registerImportedCustomContentFonts() {
        for font in importedCustomContentFonts {
            let url = contentFontsDirectoryURL.appendingPathComponent(font.fileName)
            try? registerFont(at: url)
        }
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
            if let font = activeImportedCustomFont() {
                return font.postScriptName
            }
            guard let storedName = defaults.string(forKey: contentFontPostScriptNameKey(for: .custom)),
                  UIFont(name: storedName, size: 17) != nil
            else { return nil }
            return storedName
        }
    }

    private func activeImportedCustomFont() -> ImportedContentFont? {
        let fonts = importedCustomContentFonts
        guard !fonts.isEmpty else { return nil }
        if let selectedId = defaults.string(forKey: selectedImportedContentFontIdKey),
           let selectedFont = fonts.first(where: { $0.id == selectedId }),
           UIFont(name: selectedFont.postScriptName, size: 17) != nil {
            return selectedFont
        }
        return fonts.first { UIFont(name: $0.postScriptName, size: 17) != nil }
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

    private func customFontFileName(metadata: FontMetadata, sourceURL: URL) -> String {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "ttf" : sourceURL.pathExtension.lowercased()
        let name = sanitizedFontFileComponent(metadata.postScriptName)
        let nonce = UUID().uuidString.prefix(8)
        return "CustomContentFont-\(name)-\(nonce).\(fileExtension)"
    }

    private func sanitizedFontFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces = value.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let sanitized = pieces.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? "Imported" : sanitized
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

    private var importedCustomContentFontsKey: String {
        "contentFont.custom.importedFonts"
    }

    private var selectedImportedContentFontIdKey: String {
        "contentFont.custom.selectedImportedFontId"
    }

    private var legacyCustomFontMigrationKey: String {
        "contentFont.custom.importedFontsMigrated"
    }

    private func storedImportedCustomFonts() -> [ImportedContentFont] {
        guard let data = defaults.data(forKey: importedCustomContentFontsKey),
              let fonts = try? JSONDecoder().decode([ImportedContentFont].self, from: data)
        else {
            return []
        }
        return fonts
    }

    private func saveImportedCustomFonts(_ fonts: [ImportedContentFont]) {
        guard let data = try? JSONEncoder().encode(fonts) else { return }
        defaults.set(data, forKey: importedCustomContentFontsKey)
    }

    private func importedFontFileExists(_ font: ImportedContentFont) -> Bool {
        let url = contentFontsDirectoryURL.appendingPathComponent(font.fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func upsertImportedCustomFont(_ font: ImportedContentFont) {
        let storedFonts = storedImportedCustomFonts()
        if let oldFont = storedFonts.first(where: { $0.id == font.id }),
           oldFont.fileName != font.fileName {
            let oldURL = contentFontsDirectoryURL.appendingPathComponent(oldFont.fileName)
            try? FileManager.default.removeItem(at: oldURL)
        }

        let fonts = storedFonts.filter { $0.id != font.id } + [font]
        saveImportedCustomFonts(fonts)
    }

    private func migrateLegacyCustomContentFontIfNeeded() {
        guard !defaults.bool(forKey: legacyCustomFontMigrationKey) else { return }
        defer {
            defaults.set(true, forKey: legacyCustomFontMigrationKey)
        }
        guard storedImportedCustomFonts().isEmpty,
              let fileName = defaults.string(forKey: contentFontFileNameKey(for: .custom)),
              let postScriptName = defaults.string(forKey: contentFontPostScriptNameKey(for: .custom))
        else {
            return
        }
        let legacyFont = ImportedContentFont(
            id: postScriptName,
            postScriptName: postScriptName,
            displayName: defaults.string(forKey: contentFontDisplayNameKey(for: .custom)) ?? postScriptName,
            fileName: fileName,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        guard importedFontFileExists(legacyFont) else { return }
        saveImportedCustomFonts([legacyFont])
        if defaults.string(forKey: "contentFontFamily") == ContentFontFamily.custom.rawValue {
            defaults.set(legacyFont.id, forKey: selectedImportedContentFontIdKey)
        }
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

private enum DexoAppFontOverrideState {
    static var didInstall = false
    static var didExchangeSystemFont = false
    static var didExchangeWeightedSystemFont = false
    static var didExchangeBoldSystemFont = false
    static var didExchangeItalicSystemFont = false
}

private enum DexoAppFontAssociatedKeys {
    static var sourcePointSize: UInt8 = 0
    static var baseInterfaceFont: UInt8 = 0
}

fileprivate extension UIView {
    var dexoBaseInterfaceFont: UIFont? {
        get {
            objc_getAssociatedObject(self, &DexoAppFontAssociatedKeys.baseInterfaceFont) as? UIFont
        }
        set {
            objc_setAssociatedObject(
                self,
                &DexoAppFontAssociatedKeys.baseInterfaceFont,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

fileprivate extension UIFont {
    var dexoAppFontSourcePointSize: CGFloat? {
        (objc_getAssociatedObject(self, &DexoAppFontAssociatedKeys.sourcePointSize) as? NSNumber)
            .map { CGFloat(truncating: $0) }
    }

    func dexoMarkAppFontSourcePointSize(_ pointSize: CGFloat) -> UIFont {
        objc_setAssociatedObject(
            self,
            &DexoAppFontAssociatedKeys.sourcePointSize,
            pointSize,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return self
    }

    static func installDexoAppFontOverride() {
        guard !DexoAppFontOverrideState.didInstall else { return }
        DexoAppFontOverrideState.didInstall = true

        DexoAppFontOverrideState.didExchangeSystemFont = exchangeClassMethod(
            #selector(UIFont.systemFont(ofSize:)),
            with: #selector(UIFont.dexo_systemFont(ofSize:))
        )
        DexoAppFontOverrideState.didExchangeWeightedSystemFont = exchangeClassMethod(
            Selector(("systemFontOfSize:weight:")),
            with: #selector(UIFont.dexo_systemFont(ofSize:weight:))
        )
        DexoAppFontOverrideState.didExchangeBoldSystemFont = exchangeClassMethod(
            #selector(UIFont.boldSystemFont(ofSize:)),
            with: #selector(UIFont.dexo_boldSystemFont(ofSize:))
        )
        DexoAppFontOverrideState.didExchangeItalicSystemFont = exchangeClassMethod(
            #selector(UIFont.italicSystemFont(ofSize:)),
            with: #selector(UIFont.dexo_italicSystemFont(ofSize:))
        )
        exchangeClassMethod(Selector(("preferredFontForTextStyle:")), with: #selector(UIFont.dexo_preferredFont(forTextStyle:)))
        exchangeClassMethod(
            Selector(("preferredFontForTextStyle:compatibleWithTraitCollection:")),
            with: #selector(UIFont.dexo_preferredFont(forTextStyle:compatibleWith:))
        )
    }

    static func dexoOriginalSystemFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        if DexoAppFontOverrideState.didExchangeWeightedSystemFont {
            return UIFont.dexo_systemFont(ofSize: pointSize, weight: weight.rawValue)
        }
        if weight.rawValue >= UIFont.Weight.semibold.rawValue,
           DexoAppFontOverrideState.didExchangeBoldSystemFont {
            return UIFont.dexo_boldSystemFont(ofSize: pointSize)
        }
        if DexoAppFontOverrideState.didExchangeSystemFont {
            return UIFont.dexo_systemFont(ofSize: pointSize)
        }
        return UIFont.systemFont(ofSize: pointSize, weight: weight)
    }

    var dexoDetectedWeight: UIFont.Weight {
        if let traits = fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any],
           let weight = traits[.weight] as? CGFloat {
            return UIFont.Weight(rawValue: weight)
        }
        if fontDescriptor.symbolicTraits.contains(.traitBold) {
            return .semibold
        }
        return .regular
    }

    @discardableResult
    private static func exchangeClassMethod(_ originalSelector: Selector, with swizzledSelector: Selector) -> Bool {
        guard let originalMethod = class_getClassMethod(UIFont.self, originalSelector),
              let swizzledMethod = class_getClassMethod(UIFont.self, swizzledSelector)
        else { return false }
        method_exchangeImplementations(originalMethod, swizzledMethod)
        return true
    }

    @objc class func dexo_systemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.dexo_systemFont(ofSize: pointSize)
        return AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: .regular, fallback: original)
    }

    @objc(dexo_systemFontOfSize:weight:)
    class func dexo_systemFont(ofSize pointSize: CGFloat, weight rawWeight: CGFloat) -> UIFont {
        let weight = UIFont.Weight(rawValue: rawWeight)
        let original = UIFont.dexo_systemFont(ofSize: pointSize, weight: rawWeight)
        return AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: weight, fallback: original)
    }

    @objc class func dexo_boldSystemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.dexo_boldSystemFont(ofSize: pointSize)
        return AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: .bold, fallback: original)
    }

    @objc class func dexo_italicSystemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.dexo_italicSystemFont(ofSize: pointSize)
        let font = AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: .regular, fallback: original)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
            .dexoMarkAppFontSourcePointSize(pointSize)
    }

    @objc(dexo_preferredFontForTextStyle:)
    class func dexo_preferredFont(forTextStyle style: String) -> UIFont {
        let original = UIFont.dexo_preferredFont(forTextStyle: style)
        return AppSettings.shared.appInterfaceFont(matching: original)
    }

    @objc(dexo_preferredFontForTextStyle:compatibleWithTraitCollection:)
    class func dexo_preferredFont(forTextStyle style: String, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        let original = UIFont.dexo_preferredFont(forTextStyle: style, compatibleWith: traitCollection)
        return AppSettings.shared.appInterfaceFont(matching: original)
    }

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
