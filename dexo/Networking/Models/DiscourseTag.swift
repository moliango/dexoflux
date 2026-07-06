import Foundation

struct DiscourseTagList: Decodable {
    let tags: [DiscourseTag]
}

struct DiscourseTag: Decodable, Identifiable {
    var id: String { text }
    let text: String
    let count: Int
}
