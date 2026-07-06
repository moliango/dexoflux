import Foundation

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

    var displayTitle: String {
        if let title = data.topicTitle, !title.isEmpty {
            return title
        }
        if let title = fancyTitle, !title.isEmpty {
            return title
        }
        switch notificationType {
        case 1:
            return String(localized: "notifications.type.mentioned")
        case 2:
            return String(localized: "notifications.type.replied")
        case 3:
            return String(localized: "notifications.type.quoted")
        case 5, 19:
            return String(localized: "notifications.type.liked")
        case 6, 7:
            return String(localized: "notifications.type.private_message")
        case 9:
            return String(localized: "notifications.type.posted")
        case 11, 39:
            return String(localized: "notifications.type.linked")
        case 12:
            return data.badgeName ?? String(localized: "notifications.type.badge")
        case 24:
            return String(localized: "notifications.type.bookmark")
        case 25:
            return String(localized: "notifications.type.reaction")
        case 43:
            return String(localized: "notifications.type.boost")
        default:
            return String(localized: "notifications.type.default")
        }
    }

    var displayDescription: String {
        let actor = data.displayUsername ?? data.originalUsername ?? data.username ?? ""
        let displayActor = actor.isEmpty ? String(localized: "notifications.someone") : actor
        switch notificationType {
        case 1:
            return String(localized: "notifications.action.mentioned \(displayActor)")
        case 2:
            return String(localized: "notifications.action.replied \(displayActor)")
        case 3:
            return String(localized: "notifications.action.quoted \(displayActor)")
        case 5, 19:
            return String(localized: "notifications.action.liked \(displayActor)")
        case 6:
            return String(localized: "notifications.action.private_message \(displayActor)")
        case 9:
            return String(localized: "notifications.action.posted \(displayActor)")
        case 11, 39:
            return String(localized: "notifications.action.linked \(displayActor)")
        case 24:
            return String(localized: "notifications.action.bookmark")
        case 25:
            return String(localized: "notifications.action.reaction \(displayActor)")
        case 43:
            return String(localized: "notifications.action.boost \(displayActor)")
        default:
            if actor.isEmpty {
                return String(localized: "notifications.action.default")
            }
            return String(localized: "notifications.action.from \(actor)")
        }
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
