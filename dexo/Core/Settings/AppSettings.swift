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

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: "appearanceMode")) ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: "appearanceMode")
            applyAppearance()
            notifyChanged()
        }
    }

    func applyAppearance() {
        let style = appearanceMode.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
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
