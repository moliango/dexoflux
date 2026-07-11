import Alamofire
import Foundation
import UniformTypeIdentifiers

enum PrivateMessageFilter: Int, CaseIterable {
    case inbox
    case sent
    case archive

    var title: String {
        switch self {
        case .inbox: return String(localized: "messages.filter.inbox")
        case .sent: return String(localized: "messages.filter.sent")
        case .archive: return String(localized: "messages.filter.archive")
        }
    }
}

private enum DiscourseRequestAuthMode: String {
    case none
    case cloudflareOnly = "cfOnly"
    case webCookie
}

private func discourseRequestAuthMode(baseURL _: String, url: URL) -> DiscourseRequestAuthMode {
    if WebCookieStore.shared.hasDiscourseWebSessionCookie(for: url) {
        return .webCookie
    }
    if WebCookieStore.shared.hasCookie(named: "cf_clearance", for: url) {
        return .cloudflareOnly
    }
    return .none
}

private func discourseRequestHasAuthCredentials(baseURL: String, url: URL) -> Bool {
    switch discourseRequestAuthMode(baseURL: baseURL, url: url) {
    case .webCookie:
        return true
    case .cloudflareOnly, .none:
        return false
    }
}

private func shouldMergeWebCookieResponseHeaders(baseURL: String, responseURL: URL) -> Bool {
    discourseRequestAuthMode(baseURL: baseURL, url: responseURL) == .webCookie
}

struct DiscourseReactionToggleResponse: Decodable {
    let reactions: [DiscourseTopicDetail.Reaction]
    let reactionUsersCount: Int?
    let currentUserReaction: DiscourseTopicDetail.Reaction?

    enum CodingKeys: String, CodingKey {
        case reactions
        case reactionUsersCount = "reaction_users_count"
        case currentUserReaction = "current_user_reaction"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reactions = (try? container.decodeIfPresent([DiscourseTopicDetail.Reaction].self, forKey: .reactions)) ?? []
        reactionUsersCount = container.decodeLossyAPIInt(forKey: .reactionUsersCount)
        currentUserReaction = try? container.decodeIfPresent(
            DiscourseTopicDetail.Reaction.self,
            forKey: .currentUserReaction
        )
    }
}

struct DiscourseSharedIssueResponse: Decodable {
    let count: Int
    let userCreatedSharedIssue: Bool

    enum CodingKeys: String, CodingKey {
        case count
        case userCreatedSharedIssue = "user_created_shared_issue"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = container.decodeLossyAPIInt(forKey: .count) ?? 0
        userCreatedSharedIssue = (try? container.decodeIfPresent(Bool.self, forKey: .userCreatedSharedIssue)) ?? false
    }
}

final class DiscourseAPI {
    static let cloudflareChallengeDetectedNotification = Notification.Name("DiscourseAPI.cloudflareChallengeDetected")
    static let cloudflareVerificationCompletedNotification = Notification.Name("DiscourseAPI.cloudflareVerificationCompleted")
    static let cloudflareBaseURLUserInfoKey = "baseURL"
    static let cloudflareResponseURLUserInfoKey = "responseURL"

    let baseURL: String
    private(set) var emojiReady: Bool = false
    private let interceptor: DiscourseAuthInterceptor
    private let composerUploadClientId = UUID().uuidString.lowercased()

    private let sessionLock = NSLock()
    private var sessionStorage: Session?
    private var sessionSignature = ""
    private var retiredSessions: [Session] = []
    private var session: Session {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        let service = LightweightDohProxyService.shared
        let signature = service.sessionConfigurationSignature
        if let sessionStorage, sessionSignature == signature {
            return sessionStorage
        }
        let oldSession = sessionStorage
        let newSession = DiscourseAPI.makeSession(baseURL: baseURL, interceptor: interceptor)
        sessionStorage = newSession
        sessionSignature = service.sessionConfigurationSignature
        if let oldSession {
            retainRetiredSession(oldSession)
        }
        return newSession
    }

    init(forum: ForumInstance) {
        self.baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.interceptor = DiscourseAuthInterceptor(baseURL: baseURL)
    }

    init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.interceptor = DiscourseAuthInterceptor(baseURL: self.baseURL)
    }

    private func retainRetiredSession(_ session: Session) {
        let id = ObjectIdentifier(session)
        retiredSessions.append(session)
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self else { return }
            self.sessionLock.lock()
            defer { self.sessionLock.unlock() }
            self.retiredSessions.removeAll { ObjectIdentifier($0) == id }
        }
    }

    private static func makeSession(baseURL: String, interceptor: DiscourseAuthInterceptor) -> Session {
        let config = URLSessionConfiguration.af.default
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        if let proxy = LightweightDohProxyService.shared.connectionProxyDictionary(for: baseURL) {
            config.connectionProxyDictionary = proxy
        }
        return Session(configuration: config, interceptor: interceptor)
    }

    func resetSession() {
        sessionLock.lock()
        let oldSession = sessionStorage
        sessionStorage = nil
        sessionSignature = ""
        if let oldSession {
            retainRetiredSession(oldSession)
        }
        sessionLock.unlock()

        oldSession?.cancelAllRequests()
        interceptor.invalidateCSRFToken()
    }

    static func isExplicitlyCancelledRequest(_ error: Error) -> Bool {
        if let afError = error as? AFError,
           case .explicitlyCancelled = afError {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("request explicitly cancelled")
            || message.contains("request explicitly canceled")
            || message.contains("explicitly cancelled")
            || message.contains("explicitly canceled")
    }

    // MARK: - Public API

    func fetchLatestTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .latestTopics(page: page))
    }

    func fetchTopicsByIds(_ ids: [Int]) async throws -> DiscourseTopicList {
        try await request(route: .topicsByIds(ids))
    }

    func fetchNewTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .newTopics(page: page))
    }

    func fetchUnreadTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .unreadTopics(page: page))
    }

    func fetchReadTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .readTopics(page: page))
    }

    func fetchHotTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .hotTopics(page: page))
    }

    func fetchTopTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .topTopics(page: page))
    }

    func fetchCategories() async throws -> DiscourseCategoryList {
        try await request(route: .categories)
    }

    func fetchCategoryTopics(slug: String, id: Int, page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .categoryTopics(slug: slug, id: id, page: page))
    }

    func fetchCategoryTopics(slug: String, id: Int, filter: String, page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .categoryFilteredTopics(slug: slug, id: id, filter: filter, page: page))
    }

    func fetchTagTopics(name: String, page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .tagTopics(name: name, page: page))
    }

    func fetchSiteInfo() async throws -> DiscourseSiteInfo {
        try await request(route: .siteInfo)
    }

    func fetchSiteCategories() async throws -> [DiscourseCategory] {
        let info: DiscourseSiteCategoryInfo = try await request(route: .siteInfo)
        return info.categories ?? []
    }

    func fetchBasicInfo() async throws -> DiscourseBasicInfo {
        try await request(route: .basicInfo)
    }

    func fetchNotifications() async throws -> DiscourseNotificationList {
        try await request(route: .notifications)
    }

    func markNotificationRead(id: Int) async throws {
        try await markNotificationsRead(parameters: ["id": id])
    }

    func markAllNotificationsRead() async throws {
        try await markNotificationsRead(parameters: nil)
    }

    func fetchPrivateMessages(username: String) async throws -> DiscourseTopicList {
        try await request(route: .privateMessages(username: username))
    }

    func fetchPrivateMessages(username: String, filter: PrivateMessageFilter) async throws -> DiscourseTopicList {
        switch filter {
        case .inbox:
            return try await request(route: .privateMessages(username: username))
        case .sent:
            return try await request(route: .privateMessagesSent(username: username))
        case .archive:
            return try await request(route: .privateMessagesArchive(username: username))
        }
    }

    func fetchTopic(id: Int, trackVisit: Bool = false) async throws -> DiscourseTopicDetail {
        var headers: HTTPHeaders?
        if trackVisit {
            headers = [
                "Discourse-Track-View": "1",
                "Discourse-Track-View-Topic-Id": "\(id)",
            ]
        }
        return try await request(route: .topic(id: id, trackVisit: trackVisit), headers: headers)
    }

    func fetchTopicPosts(topicId: Int, postIds: [Int]) async throws -> DiscourseTopicPostsResponse {
        try await request(route: .topicPosts(topicId: topicId, postIds: postIds))
    }

    func fetchPostReplies(postId: Int) async throws -> [DiscourseTopicDetail.Post] {
        try await request(route: .postReplies(postId: postId))
    }

    func fetchCurrentUser() async throws -> DiscourseCurrentUser {
        let response: DiscourseCurrentUserResponse = try await request(route: .currentUser)
        guard let currentUser = response.currentUser else {
            throw DiscourseAPIError(messages: [String(localized: "login.required.message")], errorType: "not_logged_in")
        }
        return currentUser
    }

    func createReply(topicId: Int, replyToPostNumber: Int?, raw: String) async throws -> DiscourseCreatePostResponse {
        var params: [String: Any] = [
            "topic_id": topicId,
            "raw": raw,
        ]
        if let replyToPostNumber {
            params["reply_to_post_number"] = replyToPostNumber
        }
        return try await request(route: .createTopic, parameters: params)
    }

    func createTopic(title: String, raw: String, categoryId: Int?, tags: [String] = []) async throws -> DiscourseCreatePostResponse {
        var params: [String: Any] = [
            "title": title,
            "raw": raw,
            "archetype": "regular",
        ]
        if let categoryId {
            params["category"] = categoryId
        }
        if !tags.isEmpty {
            params["tags"] = tags
        }
        return try await request(route: .createTopic, parameters: params)
    }

    func fetchCustomEmojis() async throws -> [DiscourseCustomEmoji] {
        let siteInfo: DiscourseSiteInfo = try await request(route: .siteInfo)
        return siteInfo.customEmoji ?? []
    }

    func fetchEmojiGroups() async throws -> [DiscourseEmojiGroup] {
        async let emojiGroupsRequest: [String: [DiscourseEmojiEntry]] = request(route: .emojis)
        async let customEmojiRequest: [DiscourseCustomEmoji] = fetchCustomEmojis()

        let emojiGroups = try await emojiGroupsRequest
        let customEmojis = (try? await customEmojiRequest) ?? []
        let orderedKeys = [
            "smileys_&_emotion",
            "people_&_body",
            "animals_&_nature",
            "food_&_drink",
            "activities",
            "travel_&_places",
            "objects",
            "symbols",
            "flags",
        ]

        var result: [DiscourseEmojiGroup] = []
        var consumedKeys = Set<String>()
        for key in orderedKeys {
            guard let entries = emojiGroups[key], !entries.isEmpty else { continue }
            result.append(DiscourseEmojiGroup(key: key, emojis: entries))
            consumedKeys.insert(key)
        }

        let remainingKeys = emojiGroups.keys
            .filter { !consumedKeys.contains($0) }
            .sorted()
        for key in remainingKeys {
            guard let entries = emojiGroups[key], !entries.isEmpty else { continue }
            result.append(DiscourseEmojiGroup(key: key, emojis: entries))
        }

        if !customEmojis.isEmpty {
            let entries = customEmojis.map {
                DiscourseEmojiEntry(name: $0.name, url: $0.url, searchAliases: nil)
            }
            result.insert(DiscourseEmojiGroup(key: "custom", emojis: entries), at: 0)
        }

        EmojiStore.save(result.flatMap { $0.emojis }, for: baseURL)
        emojiReady = true
        return result
    }

    func uploadComposerFile(fileURL: URL, filename: String? = nil) async throws -> DiscourseUploadResponse {
        let route = DiscourseRouter.upload(clientId: composerUploadClientId)
        let url = baseURL + route.path
        let fileName = filename ?? fileURL.lastPathComponent
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let headers: HTTPHeaders = [
            "Accept": "application/json",
        ]

        let response = await session.upload(
            multipartFormData: { formData in
                formData.append(Data("composer".utf8), withName: "upload_type")
                formData.append(Data("true".utf8), withName: "synchronous")
                formData.append(fileURL, withName: "file", fileName: fileName, mimeType: mimeType)
            },
            to: url,
            method: route.method,
            headers: headers
        )
        .serializingData()
        .response

        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
            throw Self.cloudflareChallengeError()
        }

        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            if statusCode == 429 {
                throw DiscourseAPIError(messages: [String(localized: "error.rate_limited")], errorType: "rate_limited")
            }
            if statusCode == 413 {
                throw DiscourseAPIError(messages: [String(localized: "reply.upload.too_large")], errorType: "upload_too_large")
            }
            if let data = response.data,
               let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data),
               !errBody.errors.isEmpty {
                throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
            }
            throw DiscourseAPIError(messages: [String(localized: "reply.upload.failed")], errorType: "upload_failed")
        }

        switch response.result {
        case .success(let data):
            do {
                return try JSONDecoder().decode(DiscourseUploadResponse.self, from: data)
            } catch {
                throw DiscourseDecodingError(
                    route: route,
                    url: url,
                    statusCode: response.response?.statusCode,
                    underlying: error,
                    bodyPreview: Self.bodyPreview(from: data)
                )
            }
        case .failure(let error):
            throw Self.makeDecodingError(
                error,
                route: route,
                url: url,
                statusCode: response.response?.statusCode,
                data: response.data
            )
        }
    }

    func search(term: String, page: Int = 0, typeFilter: String? = nil) async throws -> DiscourseSearchResult {
        try await request(route: .search(term: term, page: page, typeFilter: typeFilter))
    }

    func searchTopic(topicId: Int, term: String, page: Int = 0) async throws -> DiscourseSearchResult {
        let query = "\(term.trimmingCharacters(in: .whitespacesAndNewlines)) topic:\(topicId)"
        return try await search(term: query, page: page)
    }

    func updateTopicNotificationLevel(topicId: Int, level: DiscourseTopicDetail.NotificationLevel) async throws {
        try await requestVoid(
            route: .topicNotificationLevel(topicId: topicId),
            parameters: ["notification_level": level.rawValue]
        )
    }

    func updateTopic(topicId: Int, title: String) async throws {
        try await requestVoid(
            route: .updateTopic(topicId: topicId),
            parameters: ["title": title]
        )
    }

    func fetchTags() async throws -> DiscourseTagList {
        try await request(route: .tags)
    }

    func searchTags(query: String = "", categoryId: Int? = nil) async throws -> [DiscourseTag] {
        struct TagSearchResponse: Decodable {
            let results: [TagSearchItem]
            struct TagSearchItem: Decodable {
                let name: String
                let count: Int?
            }
        }
        let response: TagSearchResponse = try await request(route: .tagSearch(query: query, categoryId: categoryId))
        return response.results.map { DiscourseTag(text: $0.name, count: $0.count ?? 0) }
    }

    func createBookmark(postId: Int) async throws -> DiscourseCreateBookmarkResponse {
        try await request(route: .createBookmark, parameters: [
            "bookmarkable_id": postId,
            "bookmarkable_type": "Post",
        ])
    }

    func createBookmark(topicId: Int) async throws -> DiscourseCreateBookmarkResponse {
        try await request(route: .createBookmark, parameters: [
            "bookmarkable_id": topicId,
            "bookmarkable_type": "Topic",
        ])
    }

    func deleteBookmark(id: Int) async throws {
        let route = DiscourseRouter.deleteBookmark(id: id)
        let url = baseURL + route.path
        let response = await session.request(url, method: route.method).serializingData().response
        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
            throw Self.cloudflareChallengeError()
        }
        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            throw DiscourseAPIError(messages: ["Failed to delete bookmark"], errorType: nil)
        }
    }

    @discardableResult
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
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
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

    func toggleSharedIssue(topicId: Int) async throws -> DiscourseSharedIssueResponse {
        let route = DiscourseRouter.toggleSharedIssue
        let url = baseURL + route.path
        let parameters: Parameters = ["topic_id": topicId]
        let response = await session.request(
            url,
            method: route.method,
            parameters: parameters,
            encoding: URLEncoding.httpBody
        )
        .serializingData()
        .response

        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
            throw Self.cloudflareChallengeError()
        }
        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            if statusCode == 429 {
                throw DiscourseAPIError(messages: [String(localized: "shared_issue.rate_limited")], errorType: "rate_limited")
            }
            if let data = response.data,
               let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data),
               !errBody.errors.isEmpty {
                throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
            }
            throw DiscourseAPIError(messages: [String(localized: "post.action.failed")], errorType: nil)
        }

        guard let data = response.data, !data.isEmpty else {
            throw DiscourseAPIError(messages: [String(localized: "post.action.failed")], errorType: nil)
        }

        do {
            return try JSONDecoder().decode(DiscourseSharedIssueResponse.self, from: data)
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

    func createBoost(postId: Int, raw: String) async throws -> DiscourseTopicDetail.Boost {
        let route = DiscourseRouter.createBoost(postId: postId)
        let url = baseURL + route.path
        let parameters: Parameters = ["raw": raw]
        let response = await session.request(
            url,
            method: route.method,
            parameters: parameters,
            encoding: URLEncoding.httpBody
        )
        .serializingData()
        .response

        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
            throw Self.cloudflareChallengeError()
        }
        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            if statusCode == 429 {
                throw DiscourseAPIError(messages: [String(localized: "error.rate_limited")], errorType: "rate_limited")
            }
            if let data = response.data,
               let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data),
               !errBody.errors.isEmpty {
                throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
            }
            throw DiscourseAPIError(messages: [String(localized: "post.boost.failed")], errorType: nil)
        }

        switch response.result {
        case .success(let data):
            do {
                return try JSONDecoder().decode(DiscourseTopicDetail.Boost.self, from: data)
            } catch {
                throw DiscourseDecodingError(
                    route: route,
                    url: url,
                    statusCode: response.response?.statusCode,
                    underlying: error,
                    bodyPreview: Self.bodyPreview(from: data)
                )
            }
        case .failure(let error):
            throw Self.makeDecodingError(
                error,
                route: route,
                url: url,
                statusCode: response.response?.statusCode,
                data: response.data
            )
        }
    }

    @discardableResult
    func votePoll(postId: Int, pollName: String, optionIds: [String]) async throws -> DiscoursePollVoteResponse {
        let cleanedOptions = optionIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard postId > 0, !pollName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !cleanedOptions.isEmpty else {
            throw DiscourseAPIError(messages: [String(localized: "post.poll.invalid_selection")], errorType: "invalid_poll_vote")
        }

        let route = DiscourseRouter.votePoll
        let url = baseURL + route.path
        let parameters: Parameters = [
            "post_id": postId,
            "poll_name": pollName,
            "options": cleanedOptions,
        ]
        let response = await session.request(
            url,
            method: route.method,
            parameters: parameters,
            encoding: URLEncoding.httpBody
        )
        .serializingData()
        .response

        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
            throw Self.cloudflareChallengeError()
        }
        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            if statusCode == 429 {
                throw DiscourseAPIError(messages: [String(localized: "error.rate_limited")], errorType: "rate_limited")
            }
            if let data = response.data,
               let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data),
               !errBody.errors.isEmpty {
                throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
            }
            throw DiscourseAPIError(messages: [String(localized: "post.poll.vote_failed")], errorType: nil)
        }
        if let error = response.error {
            throw error
        }
        guard let data = response.data, !data.isEmpty else {
            return DiscoursePollVoteResponse()
        }
        return (try? JSONDecoder().decode(DiscoursePollVoteResponse.self, from: data)) ?? DiscoursePollVoteResponse()
    }

    @discardableResult
    func sendTopicTimings(topicId: Int, topicTime: Int, timings: [Int: Int]) async -> Int? {
        let url = baseURL + "/topics/timings"
        guard URL(string: url).map({ discourseRequestHasAuthCredentials(baseURL: baseURL, url: $0) }) == true else {
            return nil
        }
        guard topicId > 0, topicTime > 0, !timings.isEmpty else {
            return nil
        }

        var parameters: Parameters = [
            "topic_id": topicId,
            "topic_time": topicTime,
        ]
        for (postNumber, milliseconds) in timings where postNumber > 0 && milliseconds > 0 {
            parameters["timings[\(postNumber)]"] = milliseconds
        }
        guard parameters.count > 2 else { return nil }

        let headers: HTTPHeaders = [
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "X-SILENCE-LOGGER": "true",
            "Discourse-Background": "true",
        ]
        let response = await session.request(
            url,
            method: .post,
            parameters: parameters,
            encoding: URLEncoding.httpBody,
            headers: headers
        )
        .serializingData()
        .response

        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
        }

        #if DEBUG
        if let error = response.error {
            print("[DiscourseAPI] topic timings failed: \(error)")
        } else if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            print("[DiscourseAPI] topic timings HTTP \(statusCode)")
        }
        #endif

        return response.response?.statusCode
    }

    private func markNotificationsRead(parameters: Parameters?) async throws {
        let url = baseURL + "/notifications/mark-read"
        let response = await session.request(url, method: .put, parameters: parameters, encoding: JSONEncoding.default)
            .serializingData()
            .response
        if let httpResponse = response.response, let responseURL = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: responseURL)
        }
        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
            throw Self.cloudflareChallengeError()
        }
        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            if statusCode == 429 {
                throw DiscourseAPIError(
                    messages: [String(localized: "error.rate_limited")],
                    errorType: "rate_limited"
                )
            }
            if statusCode == 403 {
                throw DiscourseAPIError(messages: ["Session expired, please log in again"], errorType: "forbidden")
            }
            throw DiscourseAPIError(messages: ["Failed to mark notifications read"], errorType: nil)
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

    func updateUserNotificationLevel(username: String, level: String, expiringAt: Date?) async throws {
        var parameters: Parameters = ["notification_level": level]
        if let expiringAt {
            parameters["expiring_at"] = ISO8601DateFormatter().string(from: expiringAt)
        }
        try await requestVoid(
            route: .userNotificationLevel(username: username),
            parameters: parameters
        )
    }

    func sendPrivateMessage(to username: String, title: String, raw: String) async throws -> DiscourseCreatePostResponse {
        try await request(
            route: .createTopic,
            parameters: [
                "archetype": "private_message",
                "target_recipients": username,
                "title": title,
                "raw": raw,
            ]
        )
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

    func fetchCreatedTopics(username: String, page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .createdTopics(username: username, page: page))
    }

    func fetchUserBadges(username: String) async throws -> DiscourseUserBadgesResponse {
        try await request(route: .userBadges(username: username))
    }

    func fetchPendingInvites(username: String) async throws -> [DiscourseInviteLink] {
        let response: DiscoursePendingInvitesResponse = try await request(route: .pendingInvites(username: username))
        return response.invites
    }

    func createInvite(description: String?, expiresAt: Date?) async throws -> DiscourseInviteLink {
        var params: [String: Any] = [
            "max_redemptions_allowed": 1,
        ]
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            params["description"] = description
        }
        if let expiresAt {
            params["expires_at"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        return try await request(route: .createInvite, parameters: params)
    }

    func loadOrFetchEmojiMap() async {
        if EmojiStore.load(for: baseURL) {
            emojiReady = true
            return
        }
        do {
            _ = try await fetchEmojiGroups()
            emojiReady = true
        } catch {
            // Silent failure — reactions won't show emoji images but functionality is unaffected
        }
    }

    func deleteSession(username: String) async {
        let url = baseURL + "/session/\(username)"
        _ = await session.request(url, method: .delete).serializingData().response
    }

    // MARK: - Private

    private func request<T: Decodable>(
        route: DiscourseRouter,
        parameters: Parameters? = nil,
        headers: HTTPHeaders? = nil,
        allowAuthRecovery: Bool = true
    ) async throws -> T {
        let response = try await performRequest(
            route: route,
            parameters: parameters,
            headers: headers,
            allowAuthRecovery: allowAuthRecovery
        )
        do {
            return try JSONDecoder().decode(T.self, from: response.data)
        } catch {
            throw DiscourseDecodingError(
                route: route,
                url: response.url,
                statusCode: response.statusCode,
                underlying: error,
                bodyPreview: Self.bodyPreview(from: response.data)
            )
        }
    }

    private func requestVoid(
        route: DiscourseRouter,
        parameters: Parameters? = nil,
        headers: HTTPHeaders? = nil,
        allowAuthRecovery: Bool = true
    ) async throws {
        _ = try await performRequest(
            route: route,
            parameters: parameters,
            headers: headers,
            allowAuthRecovery: allowAuthRecovery
        )
    }

    private func performRequest(
        route: DiscourseRouter,
        parameters: Parameters? = nil,
        headers: HTTPHeaders? = nil,
        allowAuthRecovery: Bool = true
    ) async throws -> RawDiscourseResponse {
        let url = baseURL + route.path
        let encoding: ParameterEncoding = route.method == .post ? JSONEncoding.default : URLEncoding.default
        let response = await session.request(url, method: route.method, parameters: parameters, encoding: encoding, headers: headers)
            .serializingData(emptyResponseCodes: [200, 201, 202, 204, 205])
            .response

        #if DEBUG
        if let data = response.data, let body = String(data: data, encoding: .utf8) {
            print("[DiscourseAPI] \(route.method.rawValue) \(url)\n\(body)")
        }
        #endif

        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }

        if Self.isCloudflareChallengeResponse(response.response, data: response.data) {
            Self.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: response.response?.url)
            throw Self.cloudflareChallengeError()
        }

        if allowAuthRecovery,
           await shouldRetryAfterWebSessionRefresh(
               route: route,
               statusCode: response.response?.statusCode,
               error: response.error,
               data: response.data
           ) {
            return try await performRequest(
                route: route,
                parameters: parameters,
                headers: headers,
                allowAuthRecovery: false
            )
        }

        if let httpResponse = response.response, let url = httpResponse.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: url) {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: url)
            await WebSessionRefreshService.shared.ensureInBackground(baseURL: baseURL, reason: "api_response_cookie")
        }

        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            if statusCode == 429 {
                throw DiscourseAPIError(
                    messages: [String(localized: "error.rate_limited")],
                    errorType: "rate_limited"
                )
            }
            if case .currentUser = route, statusCode == 401 {
                throw DiscourseAPIError(messages: [String(localized: "login.required.message")], errorType: "not_logged_in")
            }
            if statusCode == 403 {
                let data = response.data ?? Data()
                if let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data), !errBody.errors.isEmpty {
                    throw DiscourseAPIError(messages: errBody.errors, errorType: "forbidden")
                }
                throw DiscourseAPIError(messages: ["Session expired, please log in again"], errorType: "forbidden")
            }
            if let data = response.data {
                if let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data), !errBody.errors.isEmpty {
                    throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
                }
                if let failBody = try? JSONDecoder().decode(DiscourseFailedResponse.self, from: data), let message = failBody.message {
                    throw DiscourseAPIError(messages: [message], errorType: failBody.failed)
                }
            }
            throw Self.serverUnavailableError(statusCode: statusCode)
        }

        switch response.result {
        case .success(let data):
            return RawDiscourseResponse(
                data: data,
                url: url,
                statusCode: response.response?.statusCode
            )
        case .failure(let error):
            throw Self.makeDecodingError(
                error,
                route: route,
                url: url,
                statusCode: response.response?.statusCode,
                data: response.data
            )
        }
    }

    private func shouldRetryAfterWebSessionRefresh(
        route: DiscourseRouter,
        statusCode: Int?,
        error: AFError?,
        data: Data?
    ) async -> Bool {
        let isAuthStatus = statusCode == 401 || statusCode == 403
        let isEmptySerializedBody = Self.isInputDataNilOrZeroLength(error) || data?.isEmpty == true
        guard isAuthStatus || isEmptySerializedBody else { return false }
        guard let base = URL(string: baseURL),
              WebCookieStore.shared.hasDiscourseWebSessionCookie(for: base)
        else { return false }

        let reason = isAuthStatus
            ? "api_auth_status_\(statusCode ?? 0)"
            : "api_empty_auth_response"
        let refreshed = await WebSessionRefreshService.shared.ensureSynced(
            baseURL: baseURL,
            reason: reason,
            force: true
        )
        guard refreshed else { return false }

        interceptor.invalidateCSRFToken()
        DohDebugLog.record(
            "request \(route.method.rawValue) \(route.path) auth failure recovered; retrying once",
            subsystem: "Auth"
        )
        return true
    }

    private static func serverUnavailableError(statusCode: Int) -> DiscourseAPIError {
        if (500 ... 599).contains(statusCode) {
            return DiscourseAPIError(
                messages: [String(format: String(localized: "error.server_unavailable"), statusCode)],
                errorType: "server_unavailable"
            )
        }
        return DiscourseAPIError(
            messages: [String(format: String(localized: "error.http_status"), statusCode)],
            errorType: "http_\(statusCode)"
        )
    }

    private static func makeDecodingError(
        _ error: AFError,
        route: DiscourseRouter,
        url: String,
        statusCode: Int?,
        data: Data?
    ) -> Error {
        guard case let .responseSerializationFailed(reason) = error,
              case let .decodingFailed(decodingError) = reason
        else {
            if case .currentUser = route,
               case let .responseSerializationFailed(reason) = error,
               case .inputDataNilOrZeroLength = reason {
                return DiscourseAPIError(messages: [String(localized: "login.required.message")], errorType: "not_logged_in")
            }
            return error
        }

        return DiscourseDecodingError(
            route: route,
            url: url,
            statusCode: statusCode,
            underlying: decodingError,
            bodyPreview: data.flatMap(Self.bodyPreview(from:))
        )
    }

    private static func isInputDataNilOrZeroLength(_ error: AFError?) -> Bool {
        guard case let .responseSerializationFailed(reason) = error,
              case .inputDataNilOrZeroLength = reason
        else { return false }
        return true
    }

    private static func cloudflareChallengeError() -> DiscourseAPIError {
        DiscourseAPIError(
            messages: [String(localized: "error.cloudflare_challenge")],
            errorType: "cloudflare_challenge"
        )
    }

    static func postCloudflareChallengeDetected(baseURL: String, responseURL: URL?) {
        DohDebugLog.record(
            "challenge detected base=\(baseURL) response=\(responseURL?.absoluteString ?? "none")",
            subsystem: "CF"
        )
        var userInfo: [String: Any] = [
            cloudflareBaseURLUserInfoKey: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
        ]
        if let responseURL {
            userInfo[cloudflareResponseURLUserInfoKey] = responseURL
        }
        NotificationCenter.default.post(
            name: cloudflareChallengeDetectedNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    nonisolated static func isCloudflareChallengeResponse(_ response: HTTPURLResponse?, data: Data?) -> Bool {
        let cfMitigated = headerValue("cf-mitigated", in: response)
        if cfMitigated?.localizedCaseInsensitiveContains("challenge") == true {
            return true
        }

        let statusCode = response?.statusCode
        let server = headerValue("server", in: response)?.lowercased() ?? ""
        let contentType = headerValue("content-type", in: response)?.lowercased() ?? ""
        if (statusCode == 403 || statusCode == 429 || statusCode == 503),
           server.contains("cloudflare"),
           contentType.contains("text/html") {
            return true
        }

        guard let body = data.flatMap({ String(data: $0, encoding: .utf8) }) else {
            return false
        }
        let lowerBody = body.lowercased()
        let hasChallengeMarker = lowerBody.contains("cf_chl_opt")
            || lowerBody.contains("challenge-platform")
            || lowerBody.contains("cf-turnstile")
            || lowerBody.contains("challenge-running")
            || (lowerBody.contains("just a moment") && lowerBody.contains("cloudflare"))

        guard hasChallengeMarker else { return false }

        return server.contains("cloudflare")
            || contentType.contains("text/html")
            || lowerBody.contains("cloudflare")
    }

    nonisolated private static func headerValue(_ name: String, in response: HTTPURLResponse?) -> String? {
        guard let response else { return nil }
        for (key, value) in response.allHeaderFields {
            guard "\(key)".caseInsensitiveCompare(name) == .orderedSame else { continue }
            return "\(value)"
        }
        return nil
    }

    private static func bodyPreview(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let maxLength = 800
        let previewData = data.prefix(maxLength)
        guard var preview = String(data: previewData, encoding: .utf8) else { return nil }
        preview = preview.replacingOccurrences(of: "\n", with: " ")
        if data.count > maxLength {
            preview += "..."
        }
        return preview
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyAPIInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

// MARK: - Error Handling

private struct DiscourseDecodingError: LocalizedError {
    let route: DiscourseRouter
    let url: String
    let statusCode: Int?
    let underlying: Error
    let bodyPreview: String?

    var errorDescription: String? {
        var parts = [
            "Response could not be decoded.",
            "Route: \(route)",
            "URL: \(url)",
        ]
        if let statusCode {
            parts.append("HTTP: \(statusCode)")
        }
        parts.append("Decode: \(Self.describe(underlying))")
        if let bodyPreview {
            parts.append("Body: \(bodyPreview)")
        }
        return parts.joined(separator: "\n")
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .typeMismatch(let type, let context):
            return "typeMismatch(\(type)) at \(path(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "valueNotFound(\(type)) at \(path(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            let fullPath = path(context.codingPath + [key])
            return "keyNotFound(\(fullPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "dataCorrupted at \(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        let value = codingPath.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "<root>" : value
    }
}

private struct DiscourseErrorResponse: Decodable {
    let errors: [String]
    let errorType: String?

    enum CodingKeys: String, CodingKey {
        case errors
        case errorType = "error_type"
    }
}

private struct DiscourseFailedResponse: Decodable {
    let failed: String?
    let message: String?
}

private struct RawDiscourseResponse {
    let data: Data
    let url: String
    let statusCode: Int?
}

struct DiscourseAPIError: LocalizedError {
    let messages: [String]
    let errorType: String?

    var isNotLoggedIn: Bool {
        errorType == "not_logged_in"
    }

    var isForbidden: Bool {
        errorType == "forbidden"
    }

    var isRateLimited: Bool {
        errorType == "rate_limited"
    }

    var isCloudflareChallenge: Bool {
        errorType == "cloudflare_challenge"
    }

    var errorDescription: String? {
        messages.joined(separator: "\n")
    }
}

// MARK: - Auth Interceptor

private final class DiscourseAuthInterceptor: RequestInterceptor {
    private let baseURL: String
    private var csrfToken: String?
    private var isFetchingCSRF = false
    private var csrfWaiters: [(String?) -> Void] = []
    private let csrfLock = NSLock()
    private let authLogLock = NSLock()
    private var loggedAuthSignatures = Set<String>()

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        if let url = request.url {
            let authMode = discourseRequestAuthMode(baseURL: baseURL, url: url)
            switch authMode {
            case .webCookie:
                applyWebCookieHeaders(to: &request, url: url)
                logAuthMode(authMode, url: url, request: request)
                if isMutating(request) {
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    if request.value(forHTTPHeaderField: "Content-Type") == nil {
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                    getOrFetchCSRFToken(session: session) { token in
                        if let token {
                            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
                        }
                        completion(.success(request))
                    }
                    return
                }
            case .cloudflareOnly:
                applyCloudflareCookieHeaders(to: &request, url: url)
                logAuthMode(authMode, url: url, request: request)
            case .none:
                logAuthMode(authMode, url: url, request: request)
            }
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.httpMethod == "POST", request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        completion(.success(request))
    }

    func retry(_ request: Request, for session: Session, dueTo error: any Error, completion: @escaping (RetryResult) -> Void) {
        guard request.retryCount == 0,
              let httpMethod = request.request?.httpMethod,
              (httpMethod == "POST" || httpMethod == "PUT" || httpMethod == "DELETE"),
              let url = request.request?.url,
              discourseRequestAuthMode(baseURL: baseURL, url: url) == .webCookie
        else {
            completion(.doNotRetry)
            return
        }
        // Retry on 403/422 (CSRF token invalid or expired)
        let statusCode = request.response?.statusCode
        guard statusCode == 403 || statusCode == 422 || statusCode == nil else {
            completion(.doNotRetry)
            return
        }
        // Invalidate token so next getOrFetchCSRFToken will fetch fresh one.
        // If another retry already reset and is fetching, we just join the waiters.
        csrfLock.lock()
        let wasAlreadyInvalidated = csrfToken == nil
        csrfToken = nil
        if wasAlreadyInvalidated {
            // Another retry already invalidated — just wait for its fetch
            csrfLock.unlock()
        } else {
            // We are the first to invalidate — reset fetch state so a fresh fetch starts
            isFetchingCSRF = false
            csrfWaiters = []
            csrfLock.unlock()
        }
        getOrFetchCSRFToken(session: session) { token in
            completion(token != nil ? .retry : .doNotRetry)
        }
    }

    private func isMutating(_ request: URLRequest) -> Bool {
        request.httpMethod == "POST" || request.httpMethod == "PUT" || request.httpMethod == "DELETE"
    }

    private func applyWebCookieHeaders(to request: inout URLRequest, url: URL) {
        let header = WebCookieStore.shared.cookieHeader(for: url)
        if !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        if let userAgent = WebCookieStore.shared.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
    }

    private func applyCloudflareCookieHeaders(to request: inout URLRequest, url: URL) {
        let cfCookieHeader = WebCookieStore.shared.cookieHeader(for: url, names: ["cf_clearance"])
        if !cfCookieHeader.isEmpty {
            request.setValue(cfCookieHeader, forHTTPHeaderField: "Cookie")
            if let userAgent = WebCookieStore.shared.userAgent {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
        }
    }

    private func logAuthMode(
        _ authMode: DiscourseRequestAuthMode,
        url: URL,
        request: URLRequest
    ) {
        let method = request.httpMethod ?? "GET"
        let path = url.path.isEmpty ? "/" : url.path
        let cookieNames = WebCookieStore.shared.cookieNames(for: url)
        let cookiesText = cookieNames.isEmpty ? "none" : cookieNames.joined(separator: ",")
        let signature = "\(method) \(path) \(authMode.rawValue) \(cookiesText)"

        authLogLock.lock()
        if loggedAuthSignatures.count > 120 {
            loggedAuthSignatures.removeAll()
        }
        let shouldLog = loggedAuthSignatures.insert(signature).inserted
        authLogLock.unlock()

        guard shouldLog else { return }
        DohDebugLog.record(
            "request \(method) \(path) authMode=\(authMode.rawValue) cookies=\(cookiesText)",
            subsystem: "Auth"
        )
    }

    /// Returns cached CSRF token if available, otherwise fetches one.
    /// Concurrent callers wait for a single in-flight fetch to complete.
    private func getOrFetchCSRFToken(session: Session, completion: @escaping (String?) -> Void) {
        csrfLock.lock()
        if let token = csrfToken {
            csrfLock.unlock()
            completion(token)
            return
        }
        csrfWaiters.append(completion)
        let alreadyFetching = isFetchingCSRF
        isFetchingCSRF = true
        csrfLock.unlock()
        guard !alreadyFetching else { return }
        fetchCSRFToken(session: session) { [weak self] token in
            guard let self else { return }
            self.csrfLock.lock()
            self.csrfToken = token
            self.isFetchingCSRF = false
            let waiters = self.csrfWaiters
            self.csrfWaiters = []
            self.csrfLock.unlock()
            waiters.forEach { $0(token) }
        }
    }

    func invalidateCSRFToken() {
        csrfLock.lock()
        csrfToken = nil
        csrfLock.unlock()
    }

    func updateCSRFToken(_ token: String) {
        csrfLock.lock()
        csrfToken = token
        csrfLock.unlock()
    }

    private func fetchCSRFToken(session: Session, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/session/csrf.json") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
        if !cookieHeader.isEmpty { req.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
        if let ua = WebCookieStore.shared.userAgent { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
        session.request(req).responseData { response in
            guard let data = response.data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["csrf"] as? String
            else {
                completion(nil)
                return
            }
            completion(token)
        }
    }
}
