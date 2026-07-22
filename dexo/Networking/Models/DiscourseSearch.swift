import Foundation

struct DiscourseSearchResult: Decodable {
    let posts: [SearchPost]?
    let topics: [SearchTopic]?
    let users: [SearchUser]?
    let groupedSearchResult: GroupedSearchResult?

    enum CodingKeys: String, CodingKey {
        case posts, topics, users
        case groupedSearchResult = "grouped_search_result"
    }

    struct SearchPost: Decodable, Identifiable {
        let id: Int
        let username: String
        let avatarTemplate: String?
        let blurb: String?
        let topicId: Int
        let postNumber: Int
        let topicTitleHeadline: String?

        enum CodingKeys: String, CodingKey {
            case id, username, blurb
            case avatarTemplate = "avatar_template"
            case topicId = "topic_id"
            case postNumber = "post_number"
            case topicTitleHeadline = "topic_title_headline"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decode(Int.self, forKey: .id)) ?? 0
            username = (try? container.decodeIfPresent(String.self, forKey: .username)) ?? ""
            avatarTemplate = try? container.decodeIfPresent(String.self, forKey: .avatarTemplate)
            blurb = try? container.decodeIfPresent(String.self, forKey: .blurb)
            topicId = (try? container.decode(Int.self, forKey: .topicId)) ?? 0
            postNumber = max(1, (try? container.decode(Int.self, forKey: .postNumber)) ?? 1)
            topicTitleHeadline = try? container.decodeIfPresent(String.self, forKey: .topicTitleHeadline)
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

    struct SearchUser: Decodable, Identifiable {
        let id: Int
        let username: String
        let name: String?
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case id, username, name
            case avatarTemplate = "avatar_template"
        }
    }

    struct GroupedSearchResult: Decodable {
        let morePosts: Bool?
        let moreFullPageResults: Bool?
        let term: String?

        enum CodingKeys: String, CodingKey {
            case morePosts = "more_posts"
            case moreFullPageResults = "more_full_page_results"
            case term
        }
    }
}
