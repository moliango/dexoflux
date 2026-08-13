import Foundation

// Private messages use the same TopicList format as /latest.json
// This file defines supplementary types for message-specific data

struct DiscourseMessage: Decodable, Identifiable {
    let id: Int
    let title: String
    let postsCount: Int
    let lastPostedAt: String?
    let participants: [Participant]?

    enum CodingKeys: String, CodingKey {
        case id, title, participants
        case postsCount = "posts_count"
        case lastPostedAt = "last_posted_at"
    }

    struct Participant: Decodable {
        let userId: Int
        let username: String
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case username
            case userId = "user_id"
            case avatarTemplate = "avatar_template"
        }
    }
}

// Site info models

struct DiscourseSiteInfo: Decodable {
    let defaultArchetype: String?
    let notificationTypes: [String: Int]?
    let customEmoji: [DiscourseCustomEmoji]?
    let categories: [DiscourseCategory]?
    let postActionTypes: [DiscourseFlagType]?

    enum CodingKeys: String, CodingKey {
        case defaultArchetype = "default_archetype"
        case notificationTypes = "notification_types"
        case customEmoji = "custom_emoji"
        case categories
        case postActionTypes = "post_action_types"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultArchetype = try? container.decodeIfPresent(String.self, forKey: .defaultArchetype)
        notificationTypes = try? container.decodeIfPresent([String: Int].self, forKey: .notificationTypes)
        customEmoji = try? container.decodeIfPresent([DiscourseCustomEmoji].self, forKey: .customEmoji)
        categories = try? container.decodeIfPresent([DiscourseCategory].self, forKey: .categories)
        postActionTypes = try? container.decodeIfPresent([DiscourseFlagType].self, forKey: .postActionTypes)
    }
}

/// Discourse `post_action_types` row used by Boost / post flag sheets (FluxDo FlagType).
struct DiscourseFlagType: Decodable, Equatable, Hashable {
    let id: Int
    let nameKey: String
    let name: String
    let description: String
    let isFlag: Bool
    let requireMessage: Bool
    let enabled: Bool
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case nameKey = "name_key"
        case name
        case description
        case isFlag = "is_flag"
        case requireMessage = "require_message"
        case enabled
        case position
    }

    init(
        id: Int,
        nameKey: String,
        name: String,
        description: String,
        isFlag: Bool,
        requireMessage: Bool,
        enabled: Bool,
        position: Int
    ) {
        self.id = id
        self.nameKey = nameKey
        self.name = name
        self.description = description
        self.isFlag = isFlag
        self.requireMessage = requireMessage
        self.enabled = enabled
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id) ?? 0
        nameKey = (try? container.decodeIfPresent(String.self, forKey: .nameKey)) ?? ""
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? ""
        isFlag = (try? container.decodeIfPresent(Bool.self, forKey: .isFlag)) ?? false
        requireMessage = (try? container.decodeIfPresent(Bool.self, forKey: .requireMessage)) ?? false
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        position = container.decodeLossyInt(forKey: .position) ?? 0
    }

    /// Discourse built-in flag types used when site.json is unavailable (FluxDo defaultTypes).
    static var defaultTypes: [DiscourseFlagType] {
        [
            DiscourseFlagType(
                id: 3,
                nameKey: "off_topic",
                name: String(localized: "flag.off_topic", defaultValue: "跑题"),
                description: String(
                    localized: "flag.off_topic.desc",
                    defaultValue: "此内容与讨论主题无关。"
                ),
                isFlag: true,
                requireMessage: false,
                enabled: true,
                position: 1
            ),
            DiscourseFlagType(
                id: 4,
                nameKey: "inappropriate",
                name: String(localized: "flag.inappropriate", defaultValue: "不当内容"),
                description: String(
                    localized: "flag.inappropriate.desc",
                    defaultValue: "此内容违反社区准则。"
                ),
                isFlag: true,
                requireMessage: false,
                enabled: true,
                position: 2
            ),
            DiscourseFlagType(
                id: 8,
                nameKey: "spam",
                name: String(localized: "flag.spam", defaultValue: "垃圾信息"),
                description: String(
                    localized: "flag.spam.desc",
                    defaultValue: "此内容是广告或垃圾信息。"
                ),
                isFlag: true,
                requireMessage: false,
                enabled: true,
                position: 3
            ),
            DiscourseFlagType(
                id: 7,
                nameKey: "notify_moderators",
                name: String(localized: "flag.notify_moderators", defaultValue: "其他"),
                description: String(
                    localized: "flag.notify_moderators.desc",
                    defaultValue: "由于其他原因通知版主。请说明原因。"
                ),
                isFlag: true,
                requireMessage: true,
                enabled: true,
                position: 4
            ),
        ]
    }
}

struct DiscourseBasicInfo: Decodable {
    let title: String
    let description: String?
    let logoURL: String?
    let faviconURL: String?
    let appleTouchIconURL: String?

    enum CodingKeys: String, CodingKey {
        case title, description
        case logoURL = "logo_url"
        case faviconURL = "favicon_url"
        case appleTouchIconURL = "apple_touch_icon_url"
    }
}
