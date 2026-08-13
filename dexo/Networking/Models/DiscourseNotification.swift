import Foundation
import UIKit

struct DiscourseNotificationList: Decodable {
    let notifications: [DiscourseNotification]
    let totalRowsNotifications: Int?
    let seenNotificationId: Int?
    let loadMoreNotifications: String?

    var username: String? {
        guard let loadMoreNotifications,
              let url = URLComponents(string: loadMoreNotifications),
              let item = url.queryItems?.first(where: { $0.name == "username" })
        else {
            return nil
        }
        return item.value
    }

    enum CodingKeys: String, CodingKey {
        case notifications
        case totalRowsNotifications = "total_rows_notifications"
        case seenNotificationId = "seen_notification_id"
        case loadMoreNotifications = "load_more_notifications"
    }
}

struct DiscourseNotification: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let notificationType: Int
    let read: Bool
    let highPriority: Bool
    let createdAt: String
    let postNumber: Int?
    let topicId: Int?
    let slug: String?
    let fancyTitle: String?
    let actingUserAvatarTemplate: String?
    let data: NotificationData

    enum CodingKeys: String, CodingKey {
        case id, read, slug, data
        case userId = "user_id"
        case notificationType = "notification_type"
        case highPriority = "high_priority"
        case createdAt = "created_at"
        case postNumber = "post_number"
        case topicId = "topic_id"
        case fancyTitle = "fancy_title"
        case actingUserAvatarTemplate = "acting_user_avatar_template"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        notificationType = try container.decode(Int.self, forKey: .notificationType)
        read = try container.decodeIfPresent(Bool.self, forKey: .read) ?? false
        highPriority = try container.decodeIfPresent(Bool.self, forKey: .highPriority) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        postNumber = try container.decodeIfPresent(Int.self, forKey: .postNumber)
        topicId = try container.decodeIfPresent(Int.self, forKey: .topicId)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        fancyTitle = try container.decodeIfPresent(String.self, forKey: .fancyTitle)
        actingUserAvatarTemplate = try container.decodeIfPresent(String.self, forKey: .actingUserAvatarTemplate)
        data = (try? container.decode(NotificationData.self, forKey: .data)) ?? NotificationData()
    }

    private init(
        id: Int,
        userId: Int?,
        notificationType: Int,
        read: Bool,
        highPriority: Bool,
        createdAt: String,
        postNumber: Int?,
        topicId: Int?,
        slug: String?,
        fancyTitle: String?,
        actingUserAvatarTemplate: String?,
        data: NotificationData
    ) {
        self.id = id
        self.userId = userId
        self.notificationType = notificationType
        self.read = read
        self.highPriority = highPriority
        self.createdAt = createdAt
        self.postNumber = postNumber
        self.topicId = topicId
        self.slug = slug
        self.fancyTitle = fancyTitle
        self.actingUserAvatarTemplate = actingUserAvatarTemplate
        self.data = data
    }

    func markingRead(_ read: Bool = true) -> DiscourseNotification {
        DiscourseNotification(
            id: id,
            userId: userId,
            notificationType: notificationType,
            read: read,
            highPriority: highPriority,
            createdAt: createdAt,
            postNumber: postNumber,
            topicId: topicId,
            slug: slug,
            fancyTitle: fancyTitle,
            actingUserAvatarTemplate: actingUserAvatarTemplate,
            data: data
        )
    }

    /// Actor shown in action subtitles (FluxDo `displayUsername ?? originalUsername`).
    var actorName: String {
        let raw = data.displayUsername ?? data.originalUsername ?? data.username ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "notifications.someone", defaultValue: "有人") : trimmed
    }

    /// Localization helper: StaticString key + Chinese default with interpolation.
    /// Using interpolated keys without catalog entries previously showed raw key text
    /// (e.g. `notifications.action.boost_with_content…`).
    private static func L(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue)
    }

    /// FluxDo-aligned list title: topic title for topic events; specialized copy otherwise.
    var displayTitle: String {
        switch notificationType {
        case 12: // granted_badge
            if let name = data.badgeName, !name.isEmpty {
                return Self.L("notifications.title.badge_granted", "获得勋章：\(name)")
            }
            return String(localized: "notifications.type.badge", defaultValue: "勋章")
        case 8: // invitee_accepted
            return Self.L("notifications.title.invitee_accepted", "\(actorName) 接受了邀请")
        case 800: // following (discourse-follow)
            return Self.L("notifications.title.following", "\(actorName) 关注了你")
        case 19: // liked_consolidated
            let count = data.count ?? 0
            if count > 0 {
                return Self.L("notifications.title.liked_consolidated", "\(actorName) 点赞了你的 \(count) 个帖子")
            }
            return String(localized: "notifications.type.liked", defaultValue: "点赞")
        case 39: // linked_consolidated
            let count = data.count ?? 0
            if count > 0 {
                return Self.L("notifications.title.linked_consolidated", "\(actorName) 链接了你的 \(count) 个帖子")
            }
            return String(localized: "notifications.type.linked", defaultValue: "链接")
        case 16: // group_message_summary
            let count = Int(data.inboxCount ?? "") ?? (data.count ?? 0)
            let group = data.groupName ?? ""
            return Self.L("notifications.title.group_message_summary", "\(group) 有 \(count) 条新消息")
        case 22: // membership_request_accepted
            let group = data.groupName ?? ""
            return Self.L("notifications.title.membership_accepted", "已加入 \(group)")
        case 23: // membership_request_consolidated
            let count = data.count ?? 0
            let group = data.groupName ?? ""
            return Self.L("notifications.title.membership_pending", "\(count) 人申请加入 \(group)")
        case 37: // new_features
            return String(localized: "notifications.title.new_features", defaultValue: "有新功能可用")
        case 38: // admin_problems
            return String(localized: "notifications.title.admin_problems", defaultValue: "站点有新的管理建议")
        default:
            break
        }

        if let title = data.topicTitle, !title.isEmpty {
            return title
        }
        if let title = fancyTitle, !title.isEmpty {
            return title
        }

        return typeLabel
    }

    /// Post id of the acting post (reply / mention / like target), when Discourse includes it.
    var actingPostId: Int? {
        guard let raw = data.originalPostId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let value = Int(raw),
              value > 0
        else { return nil }
        return value
    }

    /// FluxDo-aligned subtitle: "user + action" for topic events.
    var displayDescription: String {
        let actor = actorName
        switch notificationType {
        case 1:
            return Self.L("notifications.action.mentioned", "\(actor) 在帖子中提及了你")
        case 2:
            return Self.L("notifications.action.replied", "\(actor) 回复了你的帖子")
        case 3:
            return Self.L("notifications.action.quoted", "\(actor) 引用了你的帖子")
        case 4:
            return Self.L("notifications.action.edited", "\(actor) 编辑了帖子")
        case 5:
            let count = data.count ?? 1
            if count <= 1 {
                return Self.L("notifications.action.liked", "\(actor) 赞了你的帖子")
            }
            if count == 2, let other = data.username2, !other.isEmpty {
                return Self.L("notifications.action.liked_by_two", "\(actor)、\(other) 赞了你的帖子")
            }
            let others = count - 1
            return Self.L("notifications.action.liked_by_many", "\(actor) 和其他 \(others) 人赞了你的帖子")
        case 6:
            return Self.L("notifications.action.private_message", "\(actor) 发来了私信")
        case 7:
            return Self.L("notifications.action.invited_to_pm", "\(actor) 邀请你加入私信")
        case 8:
            return String(localized: "notifications.type.invitee_accepted", defaultValue: "接受邀请")
        case 9:
            return Self.L("notifications.action.posted", "\(actor) 发布了新帖")
        case 10:
            return Self.L("notifications.action.moved", "\(actor) 移动了帖子")
        case 11:
            return Self.L("notifications.action.linked", "\(actor) 链接了你的帖子")
        case 12:
            if let badgeName = data.badgeName, !badgeName.isEmpty {
                return Self.L("notifications.action.badge_granted", "获得了勋章 \(badgeName)")
            }
            return String(localized: "notifications.action.badge", defaultValue: "获得了勋章")
        case 13:
            return Self.L("notifications.action.invited_to_topic", "\(actor) 邀请你加入话题")
        case 15:
            let group = data.groupName ?? ""
            if group.isEmpty {
                return Self.L("notifications.action.group_mentioned", "\(actor) 提及了群组")
            }
            return Self.L("notifications.action.group_mentioned_named", "\(actor) @\(group)")
        case 16:
            return String(localized: "notifications.type.group_message", defaultValue: "群组消息")
        case 17:
            return String(localized: "notifications.action.watching_first_post", defaultValue: "有新话题")
        case 18:
            return String(localized: "notifications.action.topic_reminder", defaultValue: "话题提醒")
        case 19:
            return String(localized: "notifications.type.liked", defaultValue: "点赞")
        case 20:
            return String(localized: "notifications.action.post_approved", defaultValue: "帖子已通过审核")
        case 24:
            return String(localized: "notifications.action.bookmark", defaultValue: "书签提醒")
        case 25:
            return Self.L("notifications.action.reaction", "\(actor) 对你的帖子做出了反应")
        case 26:
            return String(localized: "notifications.action.votes_released", defaultValue: "投票结果已公布")
        case 27:
            return String(localized: "notifications.action.event_reminder", defaultValue: "活动提醒")
        case 28:
            return Self.L("notifications.action.event_invitation", "\(actor) 邀请你参加活动")
        case 29:
            return Self.L("notifications.action.chat_mention", "\(actor) 在聊天中提及了你")
        case 30:
            return Self.L("notifications.action.chat_message", "\(actor) 发来了聊天消息")
        case 31:
            return Self.L("notifications.action.chat_invitation", "\(actor) 邀请你加入聊天")
        case 32:
            return String(localized: "notifications.action.chat_group_mention", defaultValue: "聊天群组提及")
        case 33:
            return Self.L("notifications.action.chat_quoted", "\(actor) 在聊天中引用了你")
        case 34:
            return String(localized: "notifications.action.assigned", defaultValue: "话题已分配给你")
        case 35:
            return Self.L("notifications.action.qa_commented", "\(actor) 评论了你的问答")
        case 36:
            return Self.L("notifications.action.watching_category", "\(actor) 在关注的分类/标签发了新帖")
        case 37:
            return String(localized: "notifications.type.new_features", defaultValue: "新功能")
        case 38:
            return String(localized: "notifications.type.admin_problems", defaultValue: "管理建议")
        case 39:
            return String(localized: "notifications.type.linked", defaultValue: "链接")
        case 40:
            return String(localized: "notifications.action.chat_watched_thread", defaultValue: "关注的聊天线程有更新")
        case 43:
            // FluxDo: "{username} Boost 了你的帖子" / with content / multi
            let count = data.count ?? 1
            if count > 1 {
                let others = count - 1
                return Self.L("notifications.action.boost_by_many", "\(actor) 等 \(others) 人 Boost 了你的帖子")
            }
            if let raw = data.boostRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return Self.L("notifications.action.boost_with_content", "\(actor): \(raw)")
            }
            return Self.L("notifications.action.boost", "\(actor) Boost 了你的帖子")
        case 800:
            return String(localized: "notifications.type.following", defaultValue: "新关注")
        case 801:
            return Self.L("notifications.action.following_created_topic", "\(actor) 创建了新话题")
        case 802:
            return Self.L("notifications.action.following_replied", "\(actor) 回复了话题")
        case 900:
            return String(localized: "notifications.action.circles", defaultValue: "圈子动态")
        default:
            if data.topicTitle != nil || actor != String(localized: "notifications.someone", defaultValue: "有人") {
                return Self.L("notifications.action.from", "来自 \(actor)")
            }
            return typeLabel
        }
    }

    /// Human label for the notification type (FluxDo `NotificationType.label`).
    var typeLabel: String {
        switch notificationType {
        case 1: return String(localized: "notifications.type.mentioned", defaultValue: "提及")
        case 2: return String(localized: "notifications.type.replied", defaultValue: "回复")
        case 3: return String(localized: "notifications.type.quoted", defaultValue: "引用")
        case 4: return String(localized: "notifications.type.edited", defaultValue: "编辑")
        case 5, 19: return String(localized: "notifications.type.liked", defaultValue: "点赞")
        case 6, 7: return String(localized: "notifications.type.private_message", defaultValue: "私信")
        case 8: return String(localized: "notifications.type.invitee_accepted", defaultValue: "接受邀请")
        case 9: return String(localized: "notifications.type.posted", defaultValue: "新帖")
        case 10: return String(localized: "notifications.type.moved", defaultValue: "移动帖子")
        case 11, 39: return String(localized: "notifications.type.linked", defaultValue: "链接")
        case 12: return String(localized: "notifications.type.badge", defaultValue: "勋章")
        case 13: return String(localized: "notifications.type.invited_to_topic", defaultValue: "话题邀请")
        case 14: return String(localized: "notifications.type.custom", defaultValue: "自定义通知")
        case 15: return String(localized: "notifications.type.group_mentioned", defaultValue: "群组提及")
        case 16: return String(localized: "notifications.type.group_message", defaultValue: "群组消息")
        case 17: return String(localized: "notifications.type.watching_first_post", defaultValue: "关注首帖")
        case 18: return String(localized: "notifications.type.topic_reminder", defaultValue: "话题提醒")
        case 20: return String(localized: "notifications.type.post_approved", defaultValue: "帖子通过")
        case 24: return String(localized: "notifications.type.bookmark", defaultValue: "书签")
        case 25: return String(localized: "notifications.type.reaction", defaultValue: "反应")
        case 26: return String(localized: "notifications.type.votes", defaultValue: "投票")
        case 27, 28: return String(localized: "notifications.type.event", defaultValue: "活动")
        case 29, 30, 31, 32, 33, 40:
            return String(localized: "notifications.type.chat", defaultValue: "聊天")
        case 34: return String(localized: "notifications.type.assigned", defaultValue: "分配")
        case 35: return String(localized: "notifications.type.qa", defaultValue: "问答")
        case 36: return String(localized: "notifications.type.watching_category", defaultValue: "分类/标签")
        case 37: return String(localized: "notifications.type.new_features", defaultValue: "新功能")
        case 38: return String(localized: "notifications.type.admin_problems", defaultValue: "管理建议")
        case 43: return String(localized: "notifications.type.boost", defaultValue: "Boost")
        case 800: return String(localized: "notifications.type.following", defaultValue: "新关注")
        case 801: return String(localized: "notifications.type.following_topic", defaultValue: "关注的人发帖")
        case 802: return String(localized: "notifications.type.following_reply", defaultValue: "关注的人回复")
        case 900: return String(localized: "notifications.type.circles", defaultValue: "圈子")
        default: return String(localized: "notifications.type.default", defaultValue: "通知")
        }
    }

    /// SF Symbol / asset name for the avatar corner badge (FluxDo notification_item icons).
    /// Boost (43) uses custom asset `BoostRocket` — never flame.
    var badgeSystemImageName: String {
        switch notificationType {
        case 1: return "at"
        case 2: return "arrowshape.turn.up.left.fill"
        case 3: return "quote.bubble.fill"
        case 4: return "pencil"
        case 5, 19: return "heart.fill"
        case 6, 7, 13: return "envelope.fill"
        case 8: return "checkmark.circle.fill"
        case 9: return "plus.bubble.fill"
        case 10: return "folder.fill"
        case 11, 39: return "link"
        case 12: return "medal.fill"
        case 15: return "person.2.fill"
        case 16: return "tray.full.fill"
        case 17: return "eye.fill"
        case 18, 27: return "alarm.fill"
        case 20: return "checkmark.seal.fill"
        case 24: return "bookmark.fill"
        case 25: return "hand.thumbsup.fill"
        case 26: return "chart.bar.fill"
        case 28: return "calendar"
        case 29, 30, 31, 32, 33, 40: return "bubble.left.and.bubble.right.fill"
        case 34: return "checklist"
        case 35: return "questionmark.bubble.fill"
        case 36: return "tag.fill"
        case 37: return "sparkles"
        case 38: return "exclamationmark.triangle.fill"
        case 43:
            // Asset name only — boost uses custom `BoostRocket` (FluxDo rocket), not SF flame.
            return "BoostRocket"
        case 800, 801, 802: return "person.badge.plus"
        case 900: return "circle.grid.2x2.fill"
        default: return "bell.fill"
        }
    }

    /// Resolve a concrete badge UIImage (never nil) so empty circles never appear.
    /// Boost always uses the custom `BoostRocket` asset — no flame/bolt substitute.
    func badgeImage(pointSize: CGFloat = 13) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)

        // Type 43 Boost: always the small rocket (FluxDo rocket_launch), never flame.
        if notificationType == 43 {
            if let rocket = UIImage(named: "BoostRocket") {
                // Scale template rocket to badge size.
                let side = pointSize + 2
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
                let scaled = renderer.image { _ in
                    rocket.withRenderingMode(.alwaysTemplate)
                        .draw(in: CGRect(x: 0, y: 0, width: side, height: side))
                }
                return scaled.withRenderingMode(.alwaysTemplate)
            }
            // Last resort: draw a simple template rocket path (still a rocket, not flame).
            return Self.makeTemplateRocketImage(pointSize: pointSize)
        }

        let primary = badgeSystemImageName
        if let image = UIImage(systemName: primary, withConfiguration: config) {
            return image.withRenderingMode(.alwaysTemplate)
        }
        return (UIImage(systemName: "bell.fill", withConfiguration: config) ?? UIImage())
            .withRenderingMode(.alwaysTemplate)
    }

    /// Minimal template rocket for Boost when the asset catalog entry is missing.
    private static func makeTemplateRocketImage(pointSize: CGFloat) -> UIImage {
        let side = max(pointSize + 2, 14)
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor.black.cgColor)
            // Nose cone
            let tip = CGPoint(x: side * 0.5, y: side * 0.08)
            let left = CGPoint(x: side * 0.32, y: side * 0.38)
            let right = CGPoint(x: side * 0.68, y: side * 0.38)
            let nose = UIBezierPath()
            nose.move(to: tip)
            nose.addLine(to: left)
            nose.addLine(to: right)
            nose.close()
            nose.fill()
            // Body
            let body = UIBezierPath(
                roundedRect: CGRect(
                    x: side * 0.36,
                    y: side * 0.36,
                    width: side * 0.28,
                    height: side * 0.36
                ),
                cornerRadius: side * 0.04
            )
            body.fill()
            // Fins
            let finL = UIBezierPath()
            finL.move(to: CGPoint(x: side * 0.36, y: side * 0.62))
            finL.addLine(to: CGPoint(x: side * 0.18, y: side * 0.82))
            finL.addLine(to: CGPoint(x: side * 0.36, y: side * 0.78))
            finL.close()
            finL.fill()
            let finR = UIBezierPath()
            finR.move(to: CGPoint(x: side * 0.64, y: side * 0.62))
            finR.addLine(to: CGPoint(x: side * 0.82, y: side * 0.82))
            finR.addLine(to: CGPoint(x: side * 0.64, y: side * 0.78))
            finR.close()
            finR.fill()
            // Exhaust (still part of rocket, not a flame badge)
            let exhaust = UIBezierPath()
            exhaust.move(to: CGPoint(x: side * 0.42, y: side * 0.72))
            exhaust.addLine(to: CGPoint(x: side * 0.5, y: side * 0.92))
            exhaust.addLine(to: CGPoint(x: side * 0.58, y: side * 0.72))
            exhaust.close()
            exhaust.fill()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    struct NotificationData: Decodable {
        let badgeId: Int?
        let badgeName: String?
        let badgeSlug: String?
        let boostRaw: String?
        let count: Int?
        let topicTitle: String?
        let displayUsername: String?
        let groupName: String?
        let inboxCount: String?
        let originalPostId: String?
        let originalPostType: Int?
        let originalUsername: String?
        let revisionNumber: Int?
        let username: String?
        let username2: String?
        let avatarTemplate: String?

        init(
            badgeId: Int? = nil,
            badgeName: String? = nil,
            badgeSlug: String? = nil,
            boostRaw: String? = nil,
            count: Int? = nil,
            topicTitle: String? = nil,
            displayUsername: String? = nil,
            groupName: String? = nil,
            inboxCount: String? = nil,
            originalPostId: String? = nil,
            originalPostType: Int? = nil,
            originalUsername: String? = nil,
            revisionNumber: Int? = nil,
            username: String? = nil,
            username2: String? = nil,
            avatarTemplate: String? = nil
        ) {
            self.badgeId = badgeId
            self.badgeName = badgeName
            self.badgeSlug = badgeSlug
            self.boostRaw = boostRaw
            self.count = count
            self.topicTitle = topicTitle
            self.displayUsername = displayUsername
            self.groupName = groupName
            self.inboxCount = inboxCount
            self.originalPostId = originalPostId
            self.originalPostType = originalPostType
            self.originalUsername = originalUsername
            self.revisionNumber = revisionNumber
            self.username = username
            self.username2 = username2
            self.avatarTemplate = avatarTemplate
        }

        enum CodingKeys: String, CodingKey {
            case badgeId = "badge_id"
            case badgeName = "badge_name"
            case badgeSlug = "badge_slug"
            case boostRaw = "boost_raw"
            case count
            case topicTitle = "topic_title"
            case displayUsername = "display_username"
            case groupName = "group_name"
            case inboxCount = "inbox_count"
            case originalPostId = "original_post_id"
            case originalPostType = "original_post_type"
            case originalUsername = "original_username"
            case revisionNumber = "revision_number"
            case username
            case username2
            case avatarTemplate = "avatar_template"
            case actingUserAvatarTemplate = "acting_user_avatar_template"
        }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self) {
                self.init(
                    badgeId: try container.decodeLossyIntIfPresent(forKey: .badgeId),
                    badgeName: try container.decodeIfPresent(String.self, forKey: .badgeName),
                    badgeSlug: try container.decodeIfPresent(String.self, forKey: .badgeSlug),
                    boostRaw: try container.decodeIfPresent(String.self, forKey: .boostRaw),
                    count: try container.decodeLossyIntIfPresent(forKey: .count),
                    topicTitle: try container.decodeIfPresent(String.self, forKey: .topicTitle),
                    displayUsername: try container.decodeIfPresent(String.self, forKey: .displayUsername),
                    groupName: try container.decodeIfPresent(String.self, forKey: .groupName),
                    inboxCount: try container.decodeLossyStringIfPresent(forKey: .inboxCount),
                    originalPostId: try container.decodeLossyStringIfPresent(forKey: .originalPostId),
                    originalPostType: try container.decodeLossyIntIfPresent(forKey: .originalPostType),
                    originalUsername: try container.decodeIfPresent(String.self, forKey: .originalUsername),
                    revisionNumber: try container.decodeLossyIntIfPresent(forKey: .revisionNumber),
                    username: try container.decodeIfPresent(String.self, forKey: .username),
                    username2: try container.decodeIfPresent(String.self, forKey: .username2),
                    avatarTemplate: try container.decodeIfPresent(String.self, forKey: .actingUserAvatarTemplate)
                        ?? container.decodeIfPresent(String.self, forKey: .avatarTemplate)
                )
                return
            }

            let singleValue = try decoder.singleValueContainer()
            guard let json = try? singleValue.decode(String.self),
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.init()
                return
            }
            self.init(
                badgeId: Self.intValue(object["badge_id"]),
                badgeName: Self.stringValue(object["badge_name"]),
                badgeSlug: Self.stringValue(object["badge_slug"]),
                boostRaw: Self.stringValue(object["boost_raw"]),
                count: Self.intValue(object["count"]),
                topicTitle: Self.stringValue(object["topic_title"]),
                displayUsername: Self.stringValue(object["display_username"]),
                groupName: Self.stringValue(object["group_name"]),
                inboxCount: Self.stringValue(object["inbox_count"]),
                originalPostId: Self.stringValue(object["original_post_id"]),
                originalPostType: Self.intValue(object["original_post_type"]),
                originalUsername: Self.stringValue(object["original_username"]),
                revisionNumber: Self.intValue(object["revision_number"]),
                username: Self.stringValue(object["username"]),
                username2: Self.stringValue(object["username2"]),
                avatarTemplate: Self.stringValue(object["acting_user_avatar_template"])
                    ?? Self.stringValue(object["avatar_template"])
            )
        }

        private static func stringValue(_ value: Any?) -> String? {
            if let string = value as? String, !string.isEmpty {
                return string
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            return nil
        }

        private static func intValue(_ value: Any?) -> Int? {
            if let int = value as? Int {
                return int
            }
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let string = value as? String {
                return Int(string)
            }
            return nil
        }
    }
}

private struct LossyString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else {
            value = ""
        }
    }
}

private struct LossyInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self), let int = Int(string) {
            value = int
        } else {
            value = 0
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        try decodeIfPresent(LossyString.self, forKey: key)?.value
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        try decodeIfPresent(LossyInt.self, forKey: key)?.value
    }
}


// MARK: - List filters (Notifications screen)

enum NotificationListFilter: Int, CaseIterable, Hashable {
    case all
    case unread
    case replies
    case mentions
    case messages
    case badges
    case system

    var title: String {
        switch self {
        case .all:
            return String(localized: "notifications.filter.all", defaultValue: "全部")
        case .unread:
            return String(localized: "notifications.filter.unread", defaultValue: "未读")
        case .replies:
            return String(localized: "notifications.filter.replies", defaultValue: "回复")
        case .mentions:
            return String(localized: "notifications.filter.mentions", defaultValue: "@我")
        case .messages:
            return String(localized: "notifications.filter.messages", defaultValue: "私信")
        case .badges:
            return String(localized: "notifications.filter.badges", defaultValue: "勋章")
        case .system:
            return String(localized: "notifications.filter.system", defaultValue: "系统")
        }
    }

    func matches(_ notification: DiscourseNotification) -> Bool {
        switch self {
        case .all:
            return true
        case .unread:
            return !notification.read
        case .replies:
            // replied / quoted / posted in topic
            return [2, 3, 9].contains(notification.notificationType)
        case .mentions:
            return notification.notificationType == 1 || notification.notificationType == 15
        case .messages:
            // private message (+ group message type 7 if present)
            return [6, 7, 16].contains(notification.notificationType)
        case .badges:
            // granted badge (Discourse notification_type = 12)
            return notification.notificationType == 12
        case .system:
            // Catch-all for non-chat/social buckets. Keep badges here too so users
            // who stay on「系统」still see medal grants;「勋章」is a focused shortcut.
            return ![1, 2, 3, 5, 6, 7, 9, 15, 19, 25, 43].contains(notification.notificationType)
        }
    }
}
