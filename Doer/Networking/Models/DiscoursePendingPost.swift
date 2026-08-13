import Foundation

struct DiscoursePendingPostsResponse: Decodable {
    let pendingPosts: [DiscoursePendingPost]
    enum CodingKeys: String, CodingKey { case pendingPosts = "pending_posts" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pendingPosts = (try? c.decodeIfPresent([DiscoursePendingPost].self, forKey: .pendingPosts)) ?? []
    }
}

struct DiscoursePendingPost: Decodable, Identifiable {
    let id: Int
    let raw: String
    let title: String?
    let topicId: Int?
    let categoryId: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case raw
        case rawText = "raw_text"
        case topicId = "topic_id"
        case categoryId = "category_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLossyInt(forKey: .id) ?? 0
        raw = (try? c.decodeIfPresent(String.self, forKey: .raw))
            ?? (try? c.decodeIfPresent(String.self, forKey: .rawText))
            ?? ""
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        topicId = c.decodeLossyInt(forKey: .topicId)
        categoryId = c.decodeLossyInt(forKey: .categoryId)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    var isNewTopic: Bool { topicId == nil }
}
