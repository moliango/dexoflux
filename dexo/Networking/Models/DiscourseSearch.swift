import Foundation

struct DiscourseSearchResult: Decodable {
    let posts: [SearchPost]?
    let topics: [SearchTopic]?
    let groupedSearchResult: GroupedSearchResult?

    enum CodingKeys: String, CodingKey {
        case posts, topics
        case groupedSearchResult = "grouped_search_result"
    }

    struct SearchPost: Decodable, Identifiable {
        let id: Int
        let username: String
        let avatarTemplate: String?
        let blurb: String?
        let topicId: Int
        let topicTitleHeadline: String?

        enum CodingKeys: String, CodingKey {
            case id, username, blurb
            case avatarTemplate = "avatar_template"
            case topicId = "topic_id"
            case topicTitleHeadline = "topic_title_headline"
        }
    }

    struct SearchTopic: Decodable, Identifiable {
        let id: Int
        let title: String
        let postsCount: Int
        let categoryId: Int?

        enum CodingKeys: String, CodingKey {
            case id, title
            case postsCount = "posts_count"
            case categoryId = "category_id"
        }
    }

    struct GroupedSearchResult: Decodable {
        let morePosts: Bool?
        let term: String?

        enum CodingKeys: String, CodingKey {
            case morePosts = "more_posts"
            case term
        }
    }
}
