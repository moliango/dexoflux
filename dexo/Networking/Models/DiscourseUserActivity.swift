import Foundation

struct DiscourseUserCardResponse: Decodable {
    let user: DiscourseUserProfile
}

struct DiscourseUserActionResponse: Decodable {
    let userActions: [DiscourseUserAction]

    enum CodingKeys: String, CodingKey {
        case userActions = "user_actions"
    }
}

struct DiscourseUserAction: Decodable, Identifiable, Hashable {
    var id: String {
        "\(actionType ?? 0):\(topicId):\(postNumber ?? 0):\(actingAt ?? createdAt ?? "")"
    }

    let actionType: Int?
    let topicId: Int
    let title: String
    let slug: String?
    let postNumber: Int?
    let username: String?
    let avatarTemplate: String?
    let actingAt: String?
    let createdAt: String?
    let categoryId: Int?
    let excerpt: String?

    enum CodingKeys: String, CodingKey {
        case actionType = "action_type"
        case topicId = "topic_id"
        case title, slug
        case postNumber = "post_number"
        case actingUsername = "acting_username"
        case username
        case actingAvatarTemplate = "acting_avatar_template"
        case avatarTemplate = "avatar_template"
        case actingAt = "acting_at"
        case createdAt = "created_at"
        case categoryId = "category_id"
        case excerpt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionType = try container.decodeIfPresent(Int.self, forKey: .actionType)
        topicId = try container.decodeIfPresent(Int.self, forKey: .topicId) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        postNumber = try container.decodeIfPresent(Int.self, forKey: .postNumber)
        username = try container.decodeIfPresent(String.self, forKey: .actingUsername)
            ?? container.decodeIfPresent(String.self, forKey: .username)
        avatarTemplate = try container.decodeIfPresent(String.self, forKey: .actingAvatarTemplate)
            ?? container.decodeIfPresent(String.self, forKey: .avatarTemplate)
        actingAt = try container.decodeIfPresent(String.self, forKey: .actingAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
    }
}

struct DiscourseUserReactionResponse: Decodable {
    let reactions: [DiscourseUserReaction]

    private enum CodingKeys: String, CodingKey {
        case reactions, posts
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let reactions = try? container.decode([DiscourseUserReaction].self) {
            self.reactions = reactions
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        reactions = try container.decodeIfPresent([DiscourseUserReaction].self, forKey: .reactions)
            ?? container.decodeIfPresent([DiscourseUserReaction].self, forKey: .posts)
            ?? []
    }
}

struct DiscourseUserReaction: Decodable, Identifiable, Hashable {
    let id: Int
    let postId: Int
    let topicId: Int
    let postNumber: Int?
    let topicTitle: String?
    let excerpt: String?
    let reactionValue: String?
    let createdAt: String?

    private struct Post: Decodable {
        let topicId: Int?
        let postNumber: Int?
        let topicTitle: String?
        let excerpt: String?

        enum CodingKeys: String, CodingKey {
            case topicId = "topic_id"
            case postNumber = "post_number"
            case topicTitle = "topic_title"
            case excerpt
        }
    }

    private struct Reaction: Decodable {
        let reactionValue: String?

        enum CodingKeys: String, CodingKey {
            case reactionValue = "reaction_value"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case topicId = "topic_id"
        case postNumber = "post_number"
        case topicTitle = "topic_title"
        case excerpt
        case reactionValue = "reaction_value"
        case createdAt = "created_at"
        case post, reaction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let post = try container.decodeIfPresent(Post.self, forKey: .post)
        let reaction = try container.decodeIfPresent(Reaction.self, forKey: .reaction)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        postId = try container.decodeIfPresent(Int.self, forKey: .postId) ?? 0
        topicId = try container.decodeIfPresent(Int.self, forKey: .topicId) ?? post?.topicId ?? 0
        postNumber = try container.decodeIfPresent(Int.self, forKey: .postNumber) ?? post?.postNumber
        topicTitle = try container.decodeIfPresent(String.self, forKey: .topicTitle) ?? post?.topicTitle
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) ?? post?.excerpt
        reactionValue = try container.decodeIfPresent(String.self, forKey: .reactionValue) ?? reaction?.reactionValue
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct DiscourseFollowUser: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarTemplate = "avatar_template"
    }
}

struct DiscourseDraftListResponse: Decodable {
    let drafts: [DiscourseDraft]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case drafts
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drafts = try container.decodeIfPresent([DiscourseDraft].self, forKey: .drafts) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

enum DiscourseDraftDestination: Equatable {
    case newTopic
    case topicReply(topicId: Int, postNumber: Int?)
    case privateMessage(recipient: String?)
    case unsupported
}

struct DiscourseDraft: Decodable, Identifiable, Hashable {
    var id: String { draftKey }

    let draftKey: String
    let data: DiscourseDraftData
    let sequence: Int
    let title: String?
    let excerpt: String?
    let updatedAt: String?
    let username: String?
    let avatarTemplate: String?
    let topicId: Int?

    var replyToPostNumber: Int? {
        guard let match = draftKey.range(of: #"_post_\d+$"#, options: .regularExpression) else { return nil }
        return Int(draftKey[match].dropFirst("_post_".count))
    }

    var isNewTopic: Bool {
        draftKey == "new_topic" || draftKey.hasPrefix("new_topic_") || data.action == "createTopic"
    }

    var isPrivateMessage: Bool {
        draftKey == "new_private_message" || draftKey.hasPrefix("new_private_message_")
    }

    var destination: DiscourseDraftDestination {
        if isPrivateMessage {
            return .privateMessage(recipient: firstTargetRecipient)
        }
        if isNewTopic {
            return .newTopic
        }
        if let topicId {
            return .topicReply(topicId: topicId, postNumber: replyToPostNumber)
        }
        return .unsupported
    }

    private var firstTargetRecipient: String? {
        let recipients = data.targetRecipients ?? username
        return recipients?
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    enum CodingKeys: String, CodingKey {
        case draftKey = "draft_key"
        case data
        case draftSequence = "draft_sequence"
        case sequence
        case title, excerpt
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case username
        case avatarTemplate = "avatar_template"
        case topicId = "topic_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        draftKey = try container.decodeIfPresent(String.self, forKey: .draftKey) ?? ""
        sequence = try container.decodeIfPresent(Int.self, forKey: .draftSequence)
            ?? container.decodeIfPresent(Int.self, forKey: .sequence)
            ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .createdAt)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatarTemplate = try container.decodeIfPresent(String.self, forKey: .avatarTemplate)

        if let explicitTopicId = try container.decodeIfPresent(Int.self, forKey: .topicId) {
            topicId = explicitTopicId
        } else if draftKey.hasPrefix("topic_") {
            topicId = Int(draftKey.dropFirst("topic_".count).split(separator: "_").first ?? "")
        } else {
            topicId = nil
        }

        if let object = try? container.decode(DiscourseDraftData.self, forKey: .data) {
            data = object
        } else if let raw = try? container.decode(String.self, forKey: .data),
                  let rawData = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(DiscourseDraftData.self, from: rawData) {
            data = decoded
        } else {
            data = DiscourseDraftData()
        }
    }
}

struct DiscourseDraftData: Decodable, Hashable {
    let title: String?
    let reply: String?
    let categoryId: Int?
    let tags: [String]
    let action: String?
    let archetypeId: String?
    let targetRecipients: String?

    init(
        title: String? = nil,
        reply: String? = nil,
        categoryId: Int? = nil,
        tags: [String] = [],
        action: String? = nil,
        archetypeId: String? = nil,
        targetRecipients: String? = nil
    ) {
        self.title = title
        self.reply = reply
        self.categoryId = categoryId
        self.tags = tags
        self.action = action
        self.archetypeId = archetypeId
        self.targetRecipients = targetRecipients
    }

    enum CodingKeys: String, CodingKey {
        case title, reply, tags, action
        case categoryId
        case categoryIdSnake = "category_id"
        case archetypeId
        case archetypeIdSnake = "archetype_id"
        case targetRecipients
        case targetRecipientsSnake = "target_recipients"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        reply = try container.decodeIfPresent(String.self, forKey: .reply)
        categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId)
            ?? container.decodeIfPresent(Int.self, forKey: .categoryIdSnake)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        action = try container.decodeIfPresent(String.self, forKey: .action)
        archetypeId = try container.decodeIfPresent(String.self, forKey: .archetypeId)
            ?? container.decodeIfPresent(String.self, forKey: .archetypeIdSnake)
        targetRecipients = try container.decodeIfPresent(String.self, forKey: .targetRecipients)
            ?? container.decodeIfPresent(String.self, forKey: .targetRecipientsSnake)
    }
}
