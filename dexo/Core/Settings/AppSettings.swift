import UIKit

final class AppSettings: DexoObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

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
        case traditionalChineseTaiwan = "zh-Hant"
        case traditionalChineseHongKong = "zh-HK"
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
                return ["zh-Hant", "zh-Hans"]
            case .traditionalChineseHongKong:
                return ["zh-HK", "zh-Hant", "zh-Hans"]
            case .english:
                return ["en"]
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
            return AppLanguage(rawValue: rawValue) ?? .simplifiedChinese
        }
        set {
            defaults.set(newValue.rawValue, forKey: "appLanguage")
            defaults.set(newValue.preferredLanguageCodes, forKey: "AppleLanguages")
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
