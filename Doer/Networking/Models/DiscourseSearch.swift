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
        let createdAt: String?
        let likeCount: Int

        enum CodingKeys: String, CodingKey {
            case id, username, blurb
            case avatarTemplate = "avatar_template"
            case topicId = "topic_id"
            case postNumber = "post_number"
            case topicTitleHeadline = "topic_title_headline"
            case createdAt = "created_at"
            case likeCount = "like_count"
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
            createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
            likeCount = (try? container.decodeIfPresent(Int.self, forKey: .likeCount)) ?? 0
        }

        init(
            id: Int,
            username: String,
            avatarTemplate: String?,
            blurb: String?,
            topicId: Int,
            postNumber: Int,
            topicTitleHeadline: String?,
            createdAt: String?,
            likeCount: Int
        ) {
            self.id = id
            self.username = username
            self.avatarTemplate = avatarTemplate
            self.blurb = blurb
            self.topicId = topicId
            self.postNumber = postNumber
            self.topicTitleHeadline = topicTitleHeadline
            self.createdAt = createdAt
            self.likeCount = likeCount
        }
    }

    struct SearchTopic: Decodable, Identifiable {
        let id: Int
        let title: String
        let fancyTitle: String?
        let slug: String?
        let postsCount: Int
        let categoryId: Int?
        let tags: [String]
        let closed: Bool
        let archived: Bool
        let views: Int

        enum CodingKeys: String, CodingKey {
            case id, title, slug, tags, closed, archived, views
            case fancyTitle = "fancy_title"
            case postsCount = "posts_count"
            case categoryId = "category_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decode(Int.self, forKey: .id)) ?? 0
            title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
            fancyTitle = try? container.decodeIfPresent(String.self, forKey: .fancyTitle)
            slug = try? container.decodeIfPresent(String.self, forKey: .slug)
            postsCount = (try? container.decodeIfPresent(Int.self, forKey: .postsCount)) ?? 0
            categoryId = try? container.decodeIfPresent(Int.self, forKey: .categoryId)
            closed = (try? container.decodeIfPresent(Bool.self, forKey: .closed)) ?? false
            archived = (try? container.decodeIfPresent(Bool.self, forKey: .archived)) ?? false
            views = (try? container.decodeIfPresent(Int.self, forKey: .views)) ?? 0
            if let names = try? container.decodeIfPresent([String].self, forKey: .tags) {
                tags = names
            } else if let objects = try? container.decodeIfPresent([[String: String]].self, forKey: .tags) {
                tags = objects.compactMap { $0["name"] ?? $0["id"] }
            } else {
                tags = []
            }
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
