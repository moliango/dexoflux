import Foundation

struct DiscourseBookmarkList: Decodable {
    let bookmarks: [DiscourseBookmark]

    enum CodingKeys: String, CodingKey {
        case bookmarks = "user_bookmark_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let inner = try container.decode(InnerList.self, forKey: .bookmarks)
        self.bookmarks = inner.bookmarks
    }

    private struct InnerList: Decodable {
        let bookmarks: [DiscourseBookmark]
    }
}

struct DiscourseCreateBookmarkResponse: Decodable {
    let id: Int
}

struct DiscourseBookmark: Decodable, Identifiable {
    let id: Int
    let name: String?
    let title: String?
    let topicId: Int?
    let excerpt: String?
    let username: String?
    let avatarTemplate: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, title, excerpt, username, user
        case topicId = "topic_id"
        case avatarTemplate = "avatar_template"
        case postUserAvatarTemplate = "post_user_avatar_template"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        topicId = try container.decodeIfPresent(Int.self, forKey: .topicId)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)

        let directAvatar = try container.decodeIfPresent(String.self, forKey: .avatarTemplate)
        let postUserAvatar = try container.decodeIfPresent(String.self, forKey: .postUserAvatarTemplate)
        let nestedUser = try container.decodeIfPresent(BookmarkUser.self, forKey: .user)
        avatarTemplate = directAvatar ?? postUserAvatar ?? nestedUser?.avatarTemplate
    }

    private struct BookmarkUser: Decodable {
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case avatarTemplate = "avatar_template"
        }
    }
}
