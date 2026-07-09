import Foundation

struct DiscourseUserSummaryResponse: Decodable {
    let userSummary: DiscourseUserSummary
    let topics: [DiscourseUserSummaryTopic]

    enum CodingKeys: String, CodingKey {
        case userSummary = "user_summary"
        case topics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userSummary = try container.decode(DiscourseUserSummary.self, forKey: .userSummary)
        topics = (try? container.decodeIfPresent([DiscourseUserSummaryTopic].self, forKey: .topics)) ?? []
    }
}

struct DiscourseUserSummary: Codable {
    let topicCount: Int
    let postCount: Int
    let likesGiven: Int
    let likesReceived: Int
    let daysVisited: Int

    enum CodingKeys: String, CodingKey {
        case topicCount = "topic_count"
        case postCount = "post_count"
        case likesGiven = "likes_given"
        case likesReceived = "likes_received"
        case daysVisited = "days_visited"
    }
}

struct DiscourseUserSummaryTopic: Codable, Identifiable {
    let id: Int
    let title: String
    let likesCount: Int?
    let postsCount: Int?
    let views: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case likesCount = "like_count"
        case postsCount = "posts_count"
        case views
    }
}
