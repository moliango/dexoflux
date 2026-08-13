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

    enum CodingKeys: String, CodingKey {
        case defaultArchetype = "default_archetype"
        case notificationTypes = "notification_types"
        case customEmoji = "custom_emoji"
        case categories
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
