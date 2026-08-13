import UIKit

/// FluxDO-aligned progress-bar gesture actions.
/// Swipe directions bind one action; long-press radial menu binds up to `menuMaxCount`.
enum ProgressGestureAction: String, CaseIterable, Codable, Equatable {
    case none
    case openTimeline
    case scrollToTop
    case jumpToUnread
    case nextPost
    case previousPost
    case reply
    case share
    case shareImage
    case exportArticle
    case openInBrowser
    case bookmark
    case readLater
    case notification
    case filter
    case toggleNestedView
    case aiAssistant
    case readingSettings
    case search
    case refresh
    case goBack

    static let menuMaxCount = 8

    static let defaultMenuActions: [ProgressGestureAction] = [
        .openTimeline, .scrollToTop, .reply, .bookmark, .share, .aiAssistant,
    ]

    /// Actions that may appear in the long-press radial menu (excludes `.none`).
    static var menuCandidates: [ProgressGestureAction] {
        allCases.filter { $0 != .none }
    }

    var title: String {
        switch self {
        case .none:
            return String(localized: "progress_gesture.action.none", defaultValue: "无")
        case .openTimeline:
            return String(localized: "progress_gesture.action.timeline", defaultValue: "时间线")
        case .scrollToTop:
            return String(localized: "progress_gesture.action.top", defaultValue: "回到顶部")
        case .jumpToUnread:
            return String(localized: "progress_gesture.action.jump_unread", defaultValue: "跳到未读")
        case .nextPost:
            return String(localized: "progress_gesture.action.next_post", defaultValue: "下一层")
        case .previousPost:
            return String(localized: "progress_gesture.action.previous_post", defaultValue: "上一层")
        case .reply:
            return String(localized: "progress_gesture.action.reply", defaultValue: "回复")
        case .share:
            return String(localized: "progress_gesture.action.share", defaultValue: "分享链接")
        case .shareImage:
            return String(localized: "progress_gesture.action.share_image", defaultValue: "分享图片")
        case .exportArticle:
            return String(localized: "progress_gesture.action.export", defaultValue: "导出话题")
        case .openInBrowser:
            return String(localized: "progress_gesture.action.browser", defaultValue: "浏览器打开")
        case .bookmark:
            return String(localized: "progress_gesture.action.bookmark", defaultValue: "书签")
        case .readLater:
            return String(localized: "progress_gesture.action.read_later", defaultValue: "稍后再看")
        case .notification:
            return String(localized: "progress_gesture.action.notification", defaultValue: "通知")
        case .filter:
            return String(localized: "progress_gesture.action.filter", defaultValue: "只看楼主")
        case .toggleNestedView:
            return String(localized: "progress_gesture.action.nested", defaultValue: "树形视图")
        case .aiAssistant:
            return String(localized: "progress_gesture.action.ai", defaultValue: "AI 助手")
        case .readingSettings:
            return String(localized: "progress_gesture.action.reading_settings", defaultValue: "阅读设置")
        case .search:
            return String(localized: "progress_gesture.action.search", defaultValue: "搜索")
        case .refresh:
            return String(localized: "progress_gesture.action.refresh", defaultValue: "刷新")
        case .goBack:
            return String(localized: "progress_gesture.action.back", defaultValue: "返回")
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "minus.circle"
        case .openTimeline: return "list.bullet.rectangle"
        case .scrollToTop: return "arrow.up.to.line"
        case .jumpToUnread: return "text.badge.star"
        case .nextPost: return "arrow.down"
        case .previousPost: return "arrow.up"
        case .reply: return "arrowshape.turn.up.left"
        case .share: return "link"
        case .shareImage: return "photo"
        case .exportArticle: return "square.and.arrow.down"
        case .openInBrowser: return "safari"
        case .bookmark: return "bookmark"
        case .readLater: return "clock.arrow.circlepath"
        case .notification: return "bell"
        case .filter: return "line.3.horizontal.decrease.circle"
        case .toggleNestedView: return "list.bullet.indent"
        case .aiAssistant: return "sparkles"
        case .readingSettings: return "textformat.size"
        case .search: return "magnifyingglass"
        case .refresh: return "arrow.clockwise"
        case .goBack: return "chevron.backward"
        }
    }
}

enum ProgressGestureSettings {
    static func encodeActions(_ actions: [ProgressGestureAction]) -> [String] {
        actions.map(\.rawValue)
    }

    static func decodeActions(_ raw: [String]?, fallback: [ProgressGestureAction]) -> [ProgressGestureAction] {
        guard let raw, !raw.isEmpty else { return fallback }
        let decoded = raw.compactMap(ProgressGestureAction.init(rawValue:))
        return decoded.isEmpty ? fallback : decoded
    }

    static func decodeAction(_ raw: String?, fallback: ProgressGestureAction) -> ProgressGestureAction {
        guard let raw, let action = ProgressGestureAction(rawValue: raw) else { return fallback }
        return action
    }
}
