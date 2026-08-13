import Foundation

struct DiscourseUserSummaryResponse: Decodable {
    let userSummary: DiscourseUserSummary
    let topics: [DiscourseUserSummaryTopic]

    enum CodingKeys: String, CodingKey {
        case userSummary = "user_summary"
        case topics
        case badges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topics = (try? container.decodeIfPresent([DiscourseUserSummaryTopic].self, forKey: .topics)) ?? []
        let badges = (try? container.decodeIfPresent([DiscourseBadge].self, forKey: .badges)) ?? []
        let decoded = try container.decode(DiscourseUserSummary.self, forKey: .userSummary)
        let topicMap = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        userSummary = decoded.merging(
            topics: topics,
            replies: decoded.replies.map { $0.merging(topic: $0.topicId.flatMap { topicMap[$0] }) },
            links: decoded.links.map { $0.merging(topic: $0.topicId.flatMap { topicMap[$0] }) },
            badges: badges
        )
    }
}

struct DiscourseUserSummary: Codable {
    let topicCount: Int
    let postCount: Int
    let likesGiven: Int
    let likesReceived: Int
    let daysVisited: Int
    let postsReadCount: Int
    let timeRead: Int
    let bookmarkCount: Int
    let topicsEntered: Int
    let recentTimeRead: Int
    let topics: [DiscourseUserSummaryTopic]
    let replies: [DiscourseUserSummaryReply]
    let links: [DiscourseUserSummaryLink]
    let mostRepliedToUsers: [DiscourseUserSummaryUser]
    let mostLikedByUsers: [DiscourseUserSummaryUser]
    let mostLikedUsers: [DiscourseUserSummaryUser]
    let topCategories: [DiscourseUserSummaryCategory]
    let badges: [DiscourseBadge]

    enum CodingKeys: String, CodingKey {
        case topicCount = "topic_count"
        case postCount = "post_count"
        case likesGiven = "likes_given"
        case likesReceived = "likes_received"
        case daysVisited = "days_visited"
        case postsReadCount = "posts_read_count"
        case timeRead = "time_read"
        case bookmarkCount = "bookmark_count"
        case topicsEntered = "topics_entered"
        case recentTimeRead = "recent_time_read"
        case topics, replies, links
        case mostRepliedToUsers = "most_replied_to_users"
        case mostLikedByUsers = "most_liked_by_users"
        case mostLikedUsers = "most_liked_users"
        case topCategories = "top_categories"
        case badges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topicCount = try container.decodeIfPresent(Int.self, forKey: .topicCount) ?? 0
        postCount = try container.decodeIfPresent(Int.self, forKey: .postCount) ?? 0
        likesGiven = try container.decodeIfPresent(Int.self, forKey: .likesGiven) ?? 0
        likesReceived = try container.decodeIfPresent(Int.self, forKey: .likesReceived) ?? 0
        daysVisited = try container.decodeIfPresent(Int.self, forKey: .daysVisited) ?? 0
        postsReadCount = try container.decodeIfPresent(Int.self, forKey: .postsReadCount) ?? 0
        timeRead = try container.decodeIfPresent(Int.self, forKey: .timeRead) ?? 0
        bookmarkCount = try container.decodeIfPresent(Int.self, forKey: .bookmarkCount) ?? 0
        topicsEntered = try container.decodeIfPresent(Int.self, forKey: .topicsEntered) ?? 0
        recentTimeRead = try container.decodeIfPresent(Int.self, forKey: .recentTimeRead) ?? 0
        topics = try container.decodeIfPresent([DiscourseUserSummaryTopic].self, forKey: .topics) ?? []
        replies = try container.decodeIfPresent([DiscourseUserSummaryReply].self, forKey: .replies) ?? []
        links = try container.decodeIfPresent([DiscourseUserSummaryLink].self, forKey: .links) ?? []
        mostRepliedToUsers = try container.decodeIfPresent([DiscourseUserSummaryUser].self, forKey: .mostRepliedToUsers) ?? []
        mostLikedByUsers = try container.decodeIfPresent([DiscourseUserSummaryUser].self, forKey: .mostLikedByUsers) ?? []
        mostLikedUsers = try container.decodeIfPresent([DiscourseUserSummaryUser].self, forKey: .mostLikedUsers) ?? []
        topCategories = try container.decodeIfPresent([DiscourseUserSummaryCategory].self, forKey: .topCategories) ?? []
        // `user_summary.badges` can contain badge references (`badge_id`, `count`)
        // while complete badge definitions are sideloaded at the response root.
        badges = (try? container.decodeIfPresent([DiscourseBadge].self, forKey: .badges)) ?? []
    }

    private init(
        source: DiscourseUserSummary,
        topics: [DiscourseUserSummaryTopic],
        replies: [DiscourseUserSummaryReply],
        links: [DiscourseUserSummaryLink],
        badges: [DiscourseBadge]
    ) {
        topicCount = source.topicCount
        postCount = source.postCount
        likesGiven = source.likesGiven
        likesReceived = source.likesReceived
        daysVisited = source.daysVisited
        postsReadCount = source.postsReadCount
        timeRead = source.timeRead
        bookmarkCount = source.bookmarkCount
        topicsEntered = source.topicsEntered
        recentTimeRead = source.recentTimeRead
        self.topics = topics
        self.replies = replies
        self.links = links
        mostRepliedToUsers = source.mostRepliedToUsers
        mostLikedByUsers = source.mostLikedByUsers
        mostLikedUsers = source.mostLikedUsers
        topCategories = source.topCategories
        self.badges = badges
    }

    fileprivate func merging(
        topics: [DiscourseUserSummaryTopic],
        replies: [DiscourseUserSummaryReply],
        links: [DiscourseUserSummaryLink],
        badges: [DiscourseBadge]
    ) -> DiscourseUserSummary {
        DiscourseUserSummary(source: self, topics: topics, replies: replies, links: links, badges: badges)
    }
}

struct DiscourseUserSummaryTopic: Codable, Identifiable {
    let id: Int
    let title: String
    let likesCount: Int?
    let postsCount: Int?
    let views: Int?
    let slug: String?
    let categoryId: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case likesCount = "like_count"
        case postsCount = "posts_count"
        case views
        case slug
        case categoryId = "category_id"
        case createdAt = "created_at"
    }
}

struct DiscourseUserSummaryReply: Codable, Identifiable {
    var id: String { "\(topicId ?? 0):\(postNumber)" }
    let topicId: Int?
    let postNumber: Int
    let likeCount: Int
    let createdAt: String?
    let topic: DiscourseUserSummaryTopic?

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case postNumber = "post_number"
        case likeCount = "like_count"
        case createdAt = "created_at"
        case topic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topic = try container.decodeIfPresent(DiscourseUserSummaryTopic.self, forKey: .topic)
        topicId = try container.decodeIfPresent(Int.self, forKey: .topicId) ?? topic?.id
        postNumber = try container.decodeIfPresent(Int.self, forKey: .postNumber) ?? 0
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    private init(source: DiscourseUserSummaryReply, topic: DiscourseUserSummaryTopic?) {
        topicId = source.topicId ?? topic?.id
        postNumber = source.postNumber
        likeCount = source.likeCount
        createdAt = source.createdAt
        self.topic = topic ?? source.topic
    }

    fileprivate func merging(topic: DiscourseUserSummaryTopic?) -> DiscourseUserSummaryReply {
        DiscourseUserSummaryReply(source: self, topic: topic)
    }
}

struct DiscourseUserSummaryLink: Codable, Identifiable {
    var id: String { "\(topicId ?? 0):\(postNumber ?? 0):\(url)" }
    let url: String
    let title: String?
    let clicks: Int
    let postNumber: Int?
    let topicId: Int?
    let topic: DiscourseUserSummaryTopic?

    enum CodingKeys: String, CodingKey {
        case url, title, clicks
        case postNumber = "post_number"
        case topicId = "topic_id"
        case topic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topic = try container.decodeIfPresent(DiscourseUserSummaryTopic.self, forKey: .topic)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
        clicks = try container.decodeIfPresent(Int.self, forKey: .clicks) ?? 0
        postNumber = try container.decodeIfPresent(Int.self, forKey: .postNumber)
        topicId = try container.decodeIfPresent(Int.self, forKey: .topicId) ?? topic?.id
    }

    private init(source: DiscourseUserSummaryLink, topic: DiscourseUserSummaryTopic?) {
        url = source.url
        title = source.title
        clicks = source.clicks
        postNumber = source.postNumber
        topicId = source.topicId ?? topic?.id
        self.topic = topic ?? source.topic
    }

    fileprivate func merging(topic: DiscourseUserSummaryTopic?) -> DiscourseUserSummaryLink {
        DiscourseUserSummaryLink(source: self, topic: topic)
    }
}

struct DiscourseUserSummaryUser: Codable, Identifiable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case id, username, name, count
        case avatarTemplate = "avatar_template"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        avatarTemplate = try container.decodeIfPresent(String.self, forKey: .avatarTemplate)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

struct DiscourseUserSummaryCategory: Codable, Identifiable {
    let id: Int
    let name: String
    let color: String?
    let slug: String?
    let topicCount: Int
    let postCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, color, slug
        case topicCount = "topic_count"
        case postCount = "post_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try container.decodeIfPresent(String.self, forKey: .color)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        topicCount = try container.decodeIfPresent(Int.self, forKey: .topicCount) ?? 0
        postCount = try container.decodeIfPresent(Int.self, forKey: .postCount) ?? 0
    }
}
