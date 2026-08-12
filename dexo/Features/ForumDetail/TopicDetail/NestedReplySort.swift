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
            return String(localized: "topic.nested.sort.old")
        case .new:
            return String(localized: "topic.nested.sort.new")
        case .top:
            return String(localized: "topic.nested.sort.top")
        }
    }

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
