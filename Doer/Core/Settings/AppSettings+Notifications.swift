import Foundation

extension AppSettings {
    /// Local banner push filter for background-synced Discourse notifications.
    enum LocalNotificationFilter: String, CaseIterable {
        case all
        case highPriority
        case mentionsAndMessages
        case mentionsOnly
        case none

        var title: String {
            switch self {
            case .all:
                return String(localized: "settings.notifications.filter.all", defaultValue: "全部")
            case .highPriority:
                return String(localized: "settings.notifications.filter.high", defaultValue: "仅高优")
            case .mentionsAndMessages:
                return String(localized: "settings.notifications.filter.mentions_messages", defaultValue: "@我与私信")
            case .mentionsOnly:
                return String(localized: "settings.notifications.filter.mentions", defaultValue: "仅 @我")
            case .none:
                return String(localized: "settings.notifications.filter.none", defaultValue: "不推送横幅")
            }
        }

        var subtitle: String {
            switch self {
            case .all:
                return String(localized: "settings.notifications.filter.all.sub", defaultValue: "同步到的未读都可能弹出")
            case .highPriority:
                return String(localized: "settings.notifications.filter.high.sub", defaultValue: "仅 high_priority 通知")
            case .mentionsAndMessages:
                return String(localized: "settings.notifications.filter.mentions_messages.sub", defaultValue: "减少刷屏，保留关键互动")
            case .mentionsOnly:
                return String(localized: "settings.notifications.filter.mentions.sub", defaultValue: "只保留被提及")
            case .none:
                return String(localized: "settings.notifications.filter.none.sub", defaultValue: "仍更新角标，不发横幅")
            }
        }

        func allows(_ notification: DiscourseNotification) -> Bool {
            switch self {
            case .all:
                return true
            case .highPriority:
                return notification.highPriority || [1, 6, 7].contains(notification.notificationType)
            case .mentionsAndMessages:
                return [1, 6, 7].contains(notification.notificationType)
            case .mentionsOnly:
                return notification.notificationType == 1
            case .none:
                return false
            }
        }
    }

    var localNotificationFilter: LocalNotificationFilter {
        get {
            let raw = defaults.string(forKey: "localNotificationFilter") ?? LocalNotificationFilter.mentionsAndMessages.rawValue
            return LocalNotificationFilter(rawValue: raw) ?? .mentionsAndMessages
        }
        set {
            defaults.set(newValue.rawValue, forKey: "localNotificationFilter")
            notifyChanged()
        }
    }
}
