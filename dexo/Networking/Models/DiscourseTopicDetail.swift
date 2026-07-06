import Foundation

struct DiscourseTopicDetail: Decodable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let postsCount: Int
    let replyCount: Int
    let views: Int
    let categoryId: Int?
    let createdAt: String
    let tags: [Tag]
    var postStream: PostStream
    let validReactions: [String]
    let bookmarked: Bool
    let bookmarkId: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, tags, bookmarked, views
        case fancyTitle = "fancy_title"
        case postsCount = "posts_count"
        case replyCount = "reply_count"
        case categoryId = "category_id"
        case createdAt = "created_at"
        case postStream = "post_stream"
        case validReactions = "valid_reactions"
        case bookmarkId = "bookmark_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fancyTitle = try? container.decodeIfPresent(String.self, forKey: .fancyTitle)
        postsCount = try container.decode(Int.self, forKey: .postsCount)
        replyCount = try container.decode(Int.self, forKey: .replyCount)
        views = container.decodeLossyInt(forKey: .views) ?? 0
        categoryId = try? container.decodeIfPresent(Int.self, forKey: .categoryId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        tags = (try? container.decodeIfPresent([Tag].self, forKey: .tags)) ?? []
        postStream = try container.decode(PostStream.self, forKey: .postStream)
        validReactions = (try? container.decodeIfPresent([String].self, forKey: .validReactions)) ?? []
        bookmarked = (try? container.decodeIfPresent(Bool.self, forKey: .bookmarked)) ?? false
        bookmarkId = try? container.decodeIfPresent(Int.self, forKey: .bookmarkId)
    }

    struct PostStream: Decodable {
        var posts: [Post]
        let stream: [Int]?
    }

    struct Tag: Decodable {
        let id: Int
        let name: String
        let slug: String
    }

    struct ReplyToUser: Decodable {
        let username: String
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case username
            case avatarTemplate = "avatar_template"
        }
    }

    struct Reaction: Decodable {
        let id: String
        let type: String
        let count: Int
    }

    struct LinkCount: Decodable, Hashable {
        let url: String
        let title: String?
        let clicks: Int
        let internalLink: Bool
        let reflection: Bool

        enum CodingKeys: String, CodingKey {
            case url, title, clicks, reflection
            case internalLink = "internal"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? ""
            title = (try? container.decodeIfPresent(String.self, forKey: .title))
                .flatMap { $0.isEmpty ? nil : $0 }
            clicks = container.decodeLossyInt(forKey: .clicks) ?? 0
            internalLink = (try? container.decodeIfPresent(Bool.self, forKey: .internalLink)) ?? false
            reflection = (try? container.decodeIfPresent(Bool.self, forKey: .reflection)) ?? false
        }
    }

    struct BoostUser: Decodable, Hashable {
        let id: Int
        let username: String
        let name: String?
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case id, username, name
            case avatarTemplate = "avatar_template"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeLossyInt(forKey: .id) ?? 0
            username = (try? container.decodeIfPresent(String.self, forKey: .username)) ?? ""
            name = (try? container.decodeIfPresent(String.self, forKey: .name))
                .flatMap { $0.isEmpty ? nil : $0 }
            avatarTemplate = (try? container.decodeIfPresent(String.self, forKey: .avatarTemplate))
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        init(id: Int, username: String, name: String?, avatarTemplate: String?) {
            self.id = id
            self.username = username
            self.name = name
            self.avatarTemplate = avatarTemplate
        }
    }

    struct Boost: Decodable, Identifiable, Hashable {
        let id: Int
        let cooked: String
        let user: BoostUser
        let canDelete: Bool
        let canFlag: Bool

        enum CodingKeys: String, CodingKey {
            case id, cooked, user
            case canDelete = "can_delete"
            case canFlag = "can_flag"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeLossyInt(forKey: .id) ?? 0
            cooked = (try? container.decodeIfPresent(String.self, forKey: .cooked)) ?? ""
            user = (try? container.decodeIfPresent(BoostUser.self, forKey: .user))
                ?? BoostUser(id: 0, username: "", name: nil, avatarTemplate: nil)
            canDelete = (try? container.decodeIfPresent(Bool.self, forKey: .canDelete)) ?? false
            canFlag = (try? container.decodeIfPresent(Bool.self, forKey: .canFlag)) ?? false
        }

        init(id: Int, cooked: String, user: BoostUser, canDelete: Bool, canFlag: Bool) {
            self.id = id
            self.cooked = cooked
            self.user = user
            self.canDelete = canDelete
            self.canFlag = canFlag
        }
    }

    struct Post: Decodable, Identifiable {
        let id: Int
        let name: String?
        let username: String
        let avatarTemplate: String?
        let createdAt: String
        let cooked: String
        let postNumber: Int
        let replyCount: Int
        let replyToPostNumber: Int?
        let replyToUser: ReplyToUser?
        let actionCode: String?
        let userTitle: String?
        let flairUrl: String?
        let flairBgColor: String?
        var bookmarked: Bool
        var bookmarkId: Int?
        var reactions: [Reaction]
        var reactionUsersCount: Int
        var currentUserReaction: Reaction?
        var currentUserUsedMainReaction: Bool
        let linkCounts: [LinkCount]
        var boosts: [Boost]
        var canBoost: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, username, cooked
            case avatarTemplate = "avatar_template"
            case createdAt = "created_at"
            case postNumber = "post_number"
            case replyCount = "reply_count"
            case replyToPostNumber = "reply_to_post_number"
            case replyToUser = "reply_to_user"
            case actionCode = "action_code"
            case userTitle = "user_title"
            case flairUrl = "flair_url"
            case flairBgColor = "flair_bg_color"
            case bookmarked
            case bookmarkId = "bookmark_id"
            case reactions
            case reactionUsersCount = "reaction_users_count"
            case currentUserReaction = "current_user_reaction"
            case currentUserUsedMainReaction = "current_user_used_main_reaction"
            case linkCounts = "link_counts"
            case boosts
            case canBoost = "can_boost"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            username = try container.decode(String.self, forKey: .username)
            name = (try? container.decodeIfPresent(String.self, forKey: .name))
                .flatMap { $0.isEmpty ? nil : $0 } ?? username
            avatarTemplate = try container.decodeIfPresent(String.self, forKey: .avatarTemplate)
            createdAt = try container.decode(String.self, forKey: .createdAt)
            cooked = try container.decode(String.self, forKey: .cooked)
            postNumber = try container.decode(Int.self, forKey: .postNumber)
            replyCount = try container.decode(Int.self, forKey: .replyCount)
            replyToPostNumber = try? container.decodeIfPresent(Int.self, forKey: .replyToPostNumber)
            replyToUser = try? container.decodeIfPresent(ReplyToUser.self, forKey: .replyToUser)
            actionCode = try? container.decodeIfPresent(String.self, forKey: .actionCode)
            userTitle = try? container.decodeIfPresent(String.self, forKey: .userTitle)
            flairUrl = try? container.decodeIfPresent(String.self, forKey: .flairUrl)
            flairBgColor = try? container.decodeIfPresent(String.self, forKey: .flairBgColor)
            bookmarked = (try? container.decodeIfPresent(Bool.self, forKey: .bookmarked)) ?? false
            bookmarkId = try? container.decodeIfPresent(Int.self, forKey: .bookmarkId)
            reactions = (try? container.decodeIfPresent([Reaction].self, forKey: .reactions)) ?? []
            reactionUsersCount = (try? container.decodeIfPresent(Int.self, forKey: .reactionUsersCount)) ?? 0
            currentUserReaction = try? container.decodeIfPresent(Reaction.self, forKey: .currentUserReaction)
            currentUserUsedMainReaction = (try? container.decodeIfPresent(Bool.self, forKey: .currentUserUsedMainReaction)) ?? false
            linkCounts = (try? container.decodeIfPresent([LinkCount].self, forKey: .linkCounts)) ?? []
            boosts = (try? container.decodeIfPresent([Boost].self, forKey: .boosts)) ?? []
            canBoost = (try? container.decodeIfPresent(Bool.self, forKey: .canBoost)) ?? false
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

struct DiscourseTopicPostsResponse: Decodable {
    let postStream: PostStreamPosts

    enum CodingKeys: String, CodingKey {
        case postStream = "post_stream"
    }

    struct PostStreamPosts: Decodable {
        let posts: [DiscourseTopicDetail.Post]
    }
}
