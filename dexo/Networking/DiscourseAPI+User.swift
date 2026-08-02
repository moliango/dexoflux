import Alamofire
import Foundation
import UniformTypeIdentifiers

// MARK: - user
extension DiscourseAPI {
    func fetchCurrentUser() async throws -> DiscourseCurrentUser {
        let response: DiscourseCurrentUserResponse = try await request(route: .currentUser)
        guard let currentUser = response.currentUser else {
            throw DiscourseAPIError(messages: [String(localized: "login.required.message")], errorType: "not_logged_in")
        }
        return currentUser
    }

    func toggleReaction(postId: Int, reactionId: String) async throws -> DiscourseReactionToggleResponse? {
        let route = DiscourseRouter.toggleReaction(postId: postId, reactionId: reactionId)
        let url = baseURL + route.path
        let response = await session.request(url, method: route.method).serializingData().response
        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if handleCloudflareChallengeIfNeeded(route: route, response: response, source: "api.action") {
            throw Self.cloudflareChallengeError()
        }
        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            throw DiscourseAPIError(messages: ["Failed to toggle reaction"], errorType: nil)
        }

        guard let data = response.data, !data.isEmpty else {
            return nil
        }
        do {
            return try JSONDecoder().decode(DiscourseReactionToggleResponse.self, from: data)
        } catch {
            throw DiscourseDecodingError(
                route: route,
                url: url,
                statusCode: response.response?.statusCode,
                underlying: error,
                bodyPreview: Self.bodyPreview(from: data)
            )
        }
    }

    func fetchBookmarks(username: String) async throws -> DiscourseBookmarkList {
        try await request(route: .bookmarks(username: username))
    }

    func fetchUserSummary(username: String) async throws -> DiscourseUserSummary {
        let response: DiscourseUserSummaryResponse = try await request(route: .userSummary(username: username))
        return response.userSummary
    }

    func fetchUserSummaryResponse(username: String) async throws -> DiscourseUserSummaryResponse {
        try await request(route: .userSummary(username: username))
    }

    func fetchUserProfile(username: String) async throws -> DiscourseUserProfile {
        let response: DiscourseUserProfileResponse = try await request(route: .userProfile(username: username))
        return response.user
    }

    func fetchUserCard(username: String) async throws -> DiscourseUserProfile {
        let response: DiscourseUserCardResponse = try await request(route: .userCard(username: username))
        return response.user
    }

    func followUser(username: String) async throws {
        try await requestVoid(route: .follow(username: username))
    }

    func unfollowUser(username: String) async throws {
        try await requestVoid(route: .unfollow(username: username))
    }

    func fetchUserActions(username: String, filter: String, offset: Int = 0) async throws -> [DiscourseUserAction] {
        let response: DiscourseUserActionResponse = try await request(
            route: .userActions(username: username, filter: filter, offset: offset)
        )
        return response.userActions
    }

    func fetchUserReactions(username: String, beforeReactionUserId: Int? = nil) async throws -> [DiscourseUserReaction] {
        let response: DiscourseUserReactionResponse = try await request(
            route: .userReactions(username: username, beforeReactionUserId: beforeReactionUserId)
        )
        return response.reactions
    }

    func fetchFollowing(username: String) async throws -> [DiscourseFollowUser] {
        try await request(route: .following(username: username))
    }

    func fetchFollowers(username: String) async throws -> [DiscourseFollowUser] {
        try await request(route: .followers(username: username))
    }

    func fetchDrafts(offset: Int = 0, limit: Int = 20) async throws -> DiscourseDraftListResponse {
        try await request(route: .drafts(offset: offset, limit: limit))
    }

    func deleteDraft(key: String, sequence: Int) async throws {
        do {
            try await requestVoid(route: .deleteDraft(key: key, sequence: sequence))
        } catch let error as DiscourseAPIError where error.errorType == "http_404" {
            return
        }
    }

    func fetchUserBadges(username: String) async throws -> DiscourseUserBadgesResponse {
        try await request(route: .userBadges(username: username))
    }

    func fetchPendingPosts(username: String) async throws -> [DiscoursePendingPost] {
        let response: DiscoursePendingPostsResponse = try await request(route: .pendingPosts(username: username))
        return response.pendingPosts
    }

    func deleteSession(username: String) async {
        let url = baseURL + "/session/\(username)"
        _ = await session.request(url, method: .delete).serializingData().response
    }
}
