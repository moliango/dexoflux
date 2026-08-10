import Foundation

/// FluxDo nested/tree topic node (`/n/topic/:id.json`).
struct DiscourseNestedNode: Decodable {
    let post: DiscourseTopicDetail.Post
    var children: [DiscourseNestedNode]
    let directReplyCount: Int
    let totalDescendantCount: Int
    let isDeletedPlaceholder: Bool

    enum ExtraKeys: String, CodingKey {
        case children
        case directReplyCount = "direct_reply_count"
        case totalDescendantCount = "total_descendant_count"
        case deletedPostPlaceholder = "deleted_post_placeholder"
    }

    init(from decoder: Decoder) throws {
        post = try DiscourseTopicDetail.Post(from: decoder)
        let container = try decoder.container(keyedBy: ExtraKeys.self)
        children = try container.decodeIfPresent([DiscourseNestedNode].self, forKey: .children) ?? []
        directReplyCount = try container.decodeIfPresent(Int.self, forKey: .directReplyCount) ?? 0
        totalDescendantCount = try container.decodeIfPresent(Int.self, forKey: .totalDescendantCount) ?? 0
        isDeletedPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .deletedPostPlaceholder) ?? false
    }

    init(
        post: DiscourseTopicDetail.Post,
        children: [DiscourseNestedNode] = [],
        directReplyCount: Int = 0,
        totalDescendantCount: Int = 0,
        isDeletedPlaceholder: Bool = false
    ) {
        self.post = post
        self.children = children
        self.directReplyCount = directReplyCount
        self.totalDescendantCount = totalDescendantCount
        self.isDeletedPlaceholder = isDeletedPlaceholder
    }

    var hasMoreChildren: Bool { directReplyCount > children.count }

    func copyWith(children: [DiscourseNestedNode]? = nil, directReplyCount: Int? = nil) -> DiscourseNestedNode {
        DiscourseNestedNode(
            post: post,
            children: children ?? self.children,
            directReplyCount: directReplyCount ?? self.directReplyCount,
            totalDescendantCount: totalDescendantCount,
            isDeletedPlaceholder: isDeletedPlaceholder
        )
    }
}

struct DiscourseNestedRootsResponse: Decodable {
    let opPost: DiscourseTopicDetail.Post?
    let sort: String?
    let roots: [DiscourseNestedNode]
    let hasMoreRoots: Bool
    let page: Int

    enum CodingKeys: String, CodingKey {
        case opPost = "op_post"
        case sort, roots, page
        case hasMoreRoots = "has_more_roots"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opPost = try container.decodeIfPresent(DiscourseTopicDetail.Post.self, forKey: .opPost)
        sort = try container.decodeIfPresent(String.self, forKey: .sort)
        roots = try container.decodeIfPresent([DiscourseNestedNode].self, forKey: .roots) ?? []
        hasMoreRoots = try container.decodeIfPresent(Bool.self, forKey: .hasMoreRoots) ?? false
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 0
    }
}

struct DiscourseNestedChildrenResponse: Decodable {
    let children: [DiscourseNestedNode]
    let hasMore: Bool
    let page: Int

    enum CodingKeys: String, CodingKey {
        case children, page
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        children = try container.decodeIfPresent([DiscourseNestedNode].self, forKey: .children) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 0
    }
}

/// Flattened row for UITableView in nested mode.
struct NestedDisplayRow: Hashable {
    let postId: Int
    let postNumber: Int
    let depth: Int
    let directReplyCount: Int
    let loadedChildCount: Int
    let hasMoreChildren: Bool
    let isExpanded: Bool

    var remainingChildCount: Int {
        max(directReplyCount - loadedChildCount, 0)
    }
}
