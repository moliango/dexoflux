import Foundation

enum NestedReplyOrdering {
    struct Item {
        let post: DiscourseTopicDetail.Post
        let depth: Int
    }

    static func ordered(_ posts: [DiscourseTopicDetail.Post]) -> [Item] {
        let real = posts.filter { $0.actionCode == nil }.sorted { $0.postNumber < $1.postNumber }
        var byNumber: [Int: DiscourseTopicDetail.Post] = [:]
        for p in real { byNumber[p.postNumber] = p }
        var children: [Int: [DiscourseTopicDetail.Post]] = [:]
        var roots: [DiscourseTopicDetail.Post] = []
        for p in real {
            if let parent = p.replyToPostNumber, byNumber[parent] != nil {
                children[parent, default: []].append(p)
            } else {
                roots.append(p)
            }
        }
        for key in children.keys {
            children[key]?.sort { $0.postNumber < $1.postNumber }
        }
        var result: [Item] = []
        func walk(_ post: DiscourseTopicDetail.Post, depth: Int) {
            result.append(Item(post: post, depth: min(depth, 8)))
            for child in children[post.postNumber] ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        for root in roots { walk(root, depth: 0) }
        // append any orphans not visited
        let seen = Set(result.map { $0.post.id })
        for p in real where !seen.contains(p.id) {
            result.append(Item(post: p, depth: 0))
        }
        return result
    }
}
