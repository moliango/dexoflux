import Foundation

struct DiscourseTopicList: Decodable {
    let users: [User]?
    let categories: [DiscourseCategory]?
    let topicList: TopicList

    enum CodingKeys: String, CodingKey {
        case users, categories
        case topicList = "topic_list"
    }

    struct User: Decodable {
        let id: Int
        let username: String
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case id, username
            case avatarTemplate = "avatar_template"
        }
    }

    struct Poster: Decodable {
        let userId: Int
        let extras: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case extras
        }
    }

    struct TopicList: Decodable {
        let topics: [Topic]
        let moreTopicsUrl: String?

        enum CodingKeys: String, CodingKey {
            case topics
            case moreTopicsUrl = "more_topics_url"
        }
    }

    struct Topic: Decodable, Identifiable {
        let id: Int
        let fancyTitle: String
        let title: String
        let postsCount: Int
        let replyCount: Int
        let views: Int
        let categoryId: Int?
        let createdAt: String
        let lastPostedAt: String?
        let pinned: Bool?
        let excerpt: String?
        let posters: [Poster]?
        let tags: [String]?

        enum CodingKeys: String, CodingKey {
            case id, title, views, pinned, excerpt, posters, tags
            case fancyTitle = "fancy_title"
            case postsCount = "posts_count"
            case replyCount = "reply_count"
            case categoryId = "category_id"
            case createdAt = "created_at"
            case lastPostedAt = "last_posted_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            fancyTitle = try container.decode(String.self, forKey: .fancyTitle)
            title = try container.decode(String.self, forKey: .title)
            postsCount = try container.decode(Int.self, forKey: .postsCount)
            replyCount = try container.decode(Int.self, forKey: .replyCount)
            views = try container.decode(Int.self, forKey: .views)
            categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId)
            createdAt = try container.decode(String.self, forKey: .createdAt)
            lastPostedAt = try container.decodeIfPresent(String.self, forKey: .lastPostedAt)
            pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned)
            excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
            posters = try container.decodeIfPresent([Poster].self, forKey: .posters)
            tags = Self.decodeTags(from: container)
        }

        private static func decodeTags(from container: KeyedDecodingContainer<CodingKeys>) -> [String]? {
            if let names = try? container.decodeIfPresent([String].self, forKey: .tags) {
                return names
            }
            if let tagObjects = try? container.decodeIfPresent([TopicTag].self, forKey: .tags) {
                return tagObjects.compactMap(\.displayName)
            }
            return nil
        }

        private struct TopicTag: Decodable {
            let name: String?
            let text: String?
            let id: String?

            enum CodingKeys: String, CodingKey {
                case name, text, id
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name)
                text = try container.decodeIfPresent(String.self, forKey: .text)
                if let stringId = try? container.decodeIfPresent(String.self, forKey: .id) {
                    id = stringId
                } else if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) {
                    id = String(intId)
                } else {
                    id = nil
                }
            }

            var displayName: String? {
                name ?? text ?? id
            }
        }
    }
}
