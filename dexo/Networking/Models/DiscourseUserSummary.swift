import Foundation

struct DiscourseUserSummaryResponse: Decodable {
    let userSummary: DiscourseUserSummary

    enum CodingKeys: String, CodingKey {
        case userSummary = "user_summary"
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
