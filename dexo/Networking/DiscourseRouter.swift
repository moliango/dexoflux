import Alamofire
import Foundation

enum DiscourseRouter {
    case latestTopics(page: Int)
    case topicsByIds([Int])
    case newTopics(page: Int)
    case unreadTopics(page: Int)
    case readTopics(page: Int)
    case hotTopics(page: Int)
    case topTopics(page: Int)
    case categories
    case topic(id: Int, trackVisit: Bool)
    case topicPosts(topicId: Int, postIds: [Int])
    case topicNotificationLevel(topicId: Int)
    case updateTopic(topicId: Int)
    case notifications
    case privateMessages(username: String)
    case privateMessagesSent(username: String)
    case privateMessagesArchive(username: String)
    case createTopic
    case postReplies(postId: Int)
    case categoryTopics(slug: String, id: Int, page: Int)
    case categoryFilteredTopics(slug: String, id: Int, filter: String, page: Int)
    case tagTopics(name: String, page: Int)
    case siteInfo
    case basicInfo
    case currentUser
    case emojis
    case search(term: String, page: Int, typeFilter: String?)
    case tags
    case tagSearch(query: String, categoryId: Int?)
    case bookmarks(username: String)
    case userSummary(username: String)
    case userProfile(username: String)
    case userCard(username: String)
    case follow(username: String)
    case unfollow(username: String)
    case userNotificationLevel(username: String)
    case userActions(username: String, filter: String, offset: Int)
    case userReactions(username: String, beforeReactionUserId: Int?)
    case following(username: String)
    case followers(username: String)
    case drafts(offset: Int, limit: Int)
    case deleteDraft(key: String, sequence: Int)
    case createdTopics(username: String, page: Int)
    case userBadges(username: String)
    case pendingInvites(username: String)
    case createInvite
    case createBookmark
    case deleteBookmark(id: Int)
    case toggleReaction(postId: Int, reactionId: String)
    case toggleSharedIssue
    case createBoost(postId: Int)
    case votePoll
    case upload(clientId: String)
    
    var method: HTTPMethod {
        switch self {
        case .createTopic, .createBookmark, .createInvite, .toggleSharedIssue, .createBoost, .upload,
             .topicNotificationLevel:
            return .post
        case .toggleReaction, .votePoll, .follow, .userNotificationLevel, .updateTopic:
            return .put
        case .deleteBookmark, .unfollow, .deleteDraft:
            return .delete
        default:
            return .get
        }
    }
    
    var path: String {
        switch self {
        case .latestTopics(let page):
            return "/latest.json?page=\(page)"
        case .topicsByIds(let ids):
            let joinedIds = ids.map(String.init).joined(separator: ",")
            return "/latest.json?topic_ids=\(joinedIds)"
        case .newTopics(let page):
            return "/new.json?page=\(page)"
        case .unreadTopics(let page):
            return "/unread.json?page=\(page)"
        case .readTopics(let page):
            return "/read.json?page=\(page)"
        case .hotTopics(let page):
            return "/hot.json?page=\(page)"
        case .topTopics(let page):
            return "/top.json?page=\(page)"
        case .categories:
            return "/categories.json?include_subcategories=true"
        case .topic(let id, let trackVisit):
            var path = "/t/\(id).json"
            if trackVisit {
                path += "?track_visit=true"
            }
            return path
        case .topicPosts(let topicId, let postIds):
            let ids = postIds.map { "post_ids[]=\($0)" }.joined(separator: "&")
            return "/t/\(topicId)/posts.json?\(ids)"
        case .topicNotificationLevel(let topicId):
            return "/t/\(topicId)/notifications"
        case .updateTopic(let topicId):
            return "/t/-/\(topicId).json"
        case .notifications:
            return "/notifications.json"
        case .privateMessages(let username):
            return "/topics/private-messages/\(username).json"
        case .privateMessagesSent(let username):
            return "/topics/private-messages-sent/\(username).json"
        case .privateMessagesArchive(let username):
            return "/topics/private-messages-archive/\(username).json"
        case .createTopic:
            return "/posts.json"
        case .postReplies(let postId):
            return "/posts/\(postId)/replies.json"
        case .categoryTopics(let slug, let id, let page):
            return "/c/\(slug)/\(id).json?page=\(page)"
        case .categoryFilteredTopics(let slug, let id, let filter, let page):
            return "/c/\(slug)/\(id)/l/\(filter).json?page=\(page)"
        case .tagTopics(let name, let page):
            return "/tag/\(name).json?page=\(page)"
        case .siteInfo:
            return "/site.json"
        case .basicInfo:
            return "/site/basic-info.json"
        case .currentUser:
            return "/session/current.json"
        case .emojis:
            return "/emojis.json"
        case .search(let term, let page, let typeFilter):
            let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
            let filter = typeFilter.map { "&type_filter=\(Self.queryValue($0))" } ?? ""
            return "/search.json?q=\(encoded)&page=\(page)\(filter)"
        case .tags:
            return "/tags.json"
        case .tagSearch(let query, let categoryId):
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            var path = "/tags/filter/search?q=\(encoded)&limit=5"
            //            if let categoryId {
            //                path += "&categoryId=\(categoryId)"
            //            }
            return path
        case .bookmarks(let username):
            return "/u/\(username)/bookmarks.json"
        case .userSummary(let username):
            return "/u/\(username)/summary.json"
        case .userProfile(let username):
            return "/u/\(username).json"
        case .userCard(let username):
            return "/u/\(Self.pathComponent(username))/card.json"
        case .follow(let username), .unfollow(let username):
            return "/follow/\(Self.pathComponent(username))"
        case .userNotificationLevel(let username):
            return "/u/\(Self.pathComponent(username))/notification_level.json"
        case .userActions(let username, let filter, let offset):
            return "/user_actions.json?username=\(Self.queryValue(username))&filter=\(Self.queryValue(filter))&offset=\(offset)"
        case .userReactions(let username, let beforeReactionUserId):
            var path = "/discourse-reactions/posts/reactions.json?username=\(Self.queryValue(username))"
            if let beforeReactionUserId {
                path += "&before_reaction_user_id=\(beforeReactionUserId)"
            }
            return path
        case .following(let username):
            return "/u/\(Self.pathComponent(username))/follow/following"
        case .followers(let username):
            return "/u/\(Self.pathComponent(username))/follow/followers"
        case .drafts(let offset, let limit):
            return "/drafts.json?offset=\(offset)&limit=\(limit)"
        case .deleteDraft(let key, let sequence):
            return "/drafts/\(Self.pathComponent(key)).json?sequence=\(sequence)"
        case .createdTopics(let username, let page):
            return "/topics/created-by/\(Self.pathComponent(username)).json?page=\(page)"
        case .userBadges(let username):
            return "/user-badges/\(username.lowercased()).json?grouped=true"
        case .pendingInvites(let username):
            return "/u/\(username)/invited/pending"
        case .createInvite:
            return "/invites"
        case .createBookmark:
            return "/bookmarks.json"
        case .deleteBookmark(let id):
            return "/bookmarks/\(id).json"
        case .toggleReaction(let postId, let reactionId):
            let encoded = reactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reactionId
            return "/discourse-reactions/posts/\(postId)/custom-reactions/\(encoded)/toggle.json"
        case .toggleSharedIssue:
            return "/solution/shared_issue"
        case .createBoost(let postId):
            return "/discourse-boosts/posts/\(postId)/boosts"
        case .votePoll:
            return "/polls/vote"
        case .upload(let clientId):
            return "/uploads.json?client_id=\(clientId)"
        }
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
