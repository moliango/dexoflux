import Foundation

/// FluxDo nested-tree sort chips under the OP (`/n/topic` roots).
enum NestedReplySort: String, CaseIterable, Hashable {
    case old
    case new
    case top

    var apiValue: String { rawValue }

    var title: String {
        switch self {
        case .old:
            return String(localized: "topic.nested.sort.old", defaultValue: "最早")
        case .new:
            return String(localized: "topic.nested.sort.new", defaultValue: "最新")
        case .top:
            return String(localized: "topic.nested.sort.top", defaultValue: "热门")
        }
    }

    /// FluxDo chip order under OP: 热门 → 最新 → 最早.
    static var chipOrder: [NestedReplySort] { [.top, .new, .old] }

    static func from(apiValue: String?) -> NestedReplySort {
        guard let apiValue, let value = NestedReplySort(rawValue: apiValue) else {
            return .old
        }
        return value
    }
}

/// Diffable data-source sentinel ids that are not real post ids.
enum TopicDetailListItem {
    /// Inserted under OP while nested view is on; must not collide with Discourse post ids.
    static let nestedSortBarID: Int = -9_101_001
}
