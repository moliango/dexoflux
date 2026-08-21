import Alamofire
import Foundation

// MARK: - Models

struct DiscourseChatChannel: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String?
    let slug: String?
    let lastMessageSentAt: String?
    let currentUserMembership: Membership?
    let iconUploadURL: String?
    /// Nested upload object used by some Discourse chat serializers.
    let iconUpload: IconUpload?
    let chatableType: String?
    let chatable: Chatable?

    struct Membership: Decodable, Equatable {
        let following: Bool?
        let unreadCount: Int?
        let lastReadMessageId: Int?

        enum CodingKeys: String, CodingKey {
            case following
            case unreadCount = "unread_count"
            case lastReadMessageId = "last_read_message_id"
        }
    }

    struct IconUpload: Decodable, Equatable {
        let url: String?
        let origin: String?

        enum CodingKeys: String, CodingKey {
            case url
            case origin = "original_url"
        }

        var resolvedURL: String? {
            let raw = (url ?? origin)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : raw
        }
    }

    /// Category / DirectMessage payload. DM carries peer avatars.
    struct Chatable: Decodable, Equatable {
        let users: [ChatUser]?
        let color: String?
        let name: String?

        struct ChatUser: Decodable, Equatable {
            let id: Int?
            let username: String?
            let name: String?
            let avatarTemplate: String?

            enum CodingKeys: String, CodingKey {
                case id, username, name
                case avatarTemplate = "avatar_template"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, slug
        case lastMessageSentAt = "last_message_sent_at"
        case currentUserMembership = "current_user_membership"
        case iconUploadURL = "icon_upload_url"
        case iconUpload = "icon_upload"
        case chatableType = "chatable_type"
        case chatable
    }

    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        // DM channels often have empty title — use peer usernames.
        if let users = chatable?.users, !users.isEmpty {
            let names = users.compactMap { user -> String? in
                let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !name.isEmpty { return name }
                let username = user.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return username.isEmpty ? nil : username
            }
            if !names.isEmpty {
                return names.joined(separator: ", ")
            }
        }
        let s = slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "#\(id)" : s
    }

    var unreadCount: Int {
        max(currentUserMembership?.unreadCount ?? 0, 0)
    }

    /// Best-effort channel avatar: custom icon → first DM peer → nil.
    func avatarURL(baseURL: String) -> URL? {
        if let raw = resolvedIconURLString {
            return Self.absoluteURL(raw, baseURL: baseURL)
        }
        if let template = chatable?.users?.first(where: {
            ($0.avatarTemplate?.isEmpty == false)
        })?.avatarTemplate {
            return AvatarImageLoader.url(from: template, baseURL: baseURL, size: 96)
        }
        return nil
    }

    var avatarTemplate: String? {
        chatable?.users?.first(where: { $0.avatarTemplate?.isEmpty == false })?.avatarTemplate
    }

    /// Category color (hex without #) for letter-tile fallback when no icon.
    var accentHexColor: String? {
        chatable?.color
    }

    private var resolvedIconURLString: String? {
        if let raw = iconUploadURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return iconUpload?.resolvedURL
    }

    private static func absoluteURL(_ raw: String, baseURL: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if raw.hasPrefix("/") {
            return URL(string: base + raw)
        }
        return URL(string: base + "/" + raw)
    }
}

struct DiscourseChatChannelsResponse: Decodable {
    let publicChannels: [DiscourseChatChannel]
    let directMessageChannels: [DiscourseChatChannel]

    enum CodingKeys: String, CodingKey {
        case publicChannels = "public_channels"
        case directMessageChannels = "direct_message_channels"
        case channels
    }

    init(publicChannels: [DiscourseChatChannel] = [], directMessageChannels: [DiscourseChatChannel] = []) {
        self.publicChannels = publicChannels
        self.directMessageChannels = directMessageChannels
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        publicChannels = (try? c.decodeIfPresent([DiscourseChatChannel].self, forKey: .publicChannels))
            ?? (try? c.decodeIfPresent([DiscourseChatChannel].self, forKey: .channels))
            ?? []
        directMessageChannels = (try? c.decodeIfPresent([DiscourseChatChannel].self, forKey: .directMessageChannels)) ?? []
    }

    var all: [DiscourseChatChannel] {
        publicChannels + directMessageChannels
    }
}

struct DiscourseChatMessage: Decodable, Identifiable, Equatable {
    let id: Int
    let message: String?
    let createdAt: String?
    private(set) var user: User?
    let cooked: String?
    let inReplyToId: Int?
    let userId: Int?

    struct User: Decodable, Equatable {
        let id: Int?
        let username: String?
        let name: String?
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case id, username, name
            case avatarTemplate = "avatar_template"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, message, cooked, user
        case createdAt = "created_at"
        case inReplyToId = "in_reply_to_id"
        case userId = "user_id"
    }

    mutating func resolveUser(from usersById: [Int: User]) {
        if user?.avatarTemplate?.isEmpty == false { return }
        let key = user?.id ?? userId
        guard let key, let resolved = usersById[key] else { return }
        // Prefer sideloaded user when nested user is missing avatar.
        if user == nil || (user?.avatarTemplate?.isEmpty != false) {
            user = resolved
        }
    }

    var displayBody: String {
        let raw = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            // Prefer raw when it already carries shortcodes (e.g. `:smile:`).
            if TitleEmojiRenderer.containsShortcode(raw) {
                return raw
            }
            // Raw may be plain text while cooked still has emoji <img alt=":code:">.
            if let cooked, cooked.contains("<img") || cooked.contains("<IMG") {
                let recovered = TitleEmojiRenderer.recoverShortcodesFromHTML(cooked)
                if TitleEmojiRenderer.containsShortcode(recovered) {
                    return recovered
                }
            }
            return raw
        }
        // Fall back to cooked HTML → shortcodes, then strip remaining tags.
        let cookedHTML = cooked ?? ""
        if cookedHTML.contains("<") {
            let recovered = TitleEmojiRenderer.recoverShortcodesFromHTML(cookedHTML)
            if TitleEmojiRenderer.containsShortcode(recovered) {
                return recovered
            }
        }
        return cookedHTML
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DiscourseChatMessagesResponse: Decodable {
    let messages: [DiscourseChatMessage]

    enum CodingKeys: String, CodingKey {
        case messages
        case chatMessages = "chat_messages"
        case users
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var raw = (try? c.decodeIfPresent([DiscourseChatMessage].self, forKey: .messages))
            ?? (try? c.decodeIfPresent([DiscourseChatMessage].self, forKey: .chatMessages))
            ?? []
        let users = (try? c.decodeIfPresent([DiscourseChatMessage.User].self, forKey: .users)) ?? []
        if !users.isEmpty {
            var byId: [Int: DiscourseChatMessage.User] = [:]
            for user in users {
                if let id = user.id {
                    byId[id] = user
                }
            }
            for index in raw.indices {
                raw[index].resolveUser(from: byId)
            }
        }
        messages = raw
    }
}

// MARK: - Routes
//
// Discourse Chat keeps two families:
// - REST `/chat/api/*` for list/read (linux.do + current Discourse)
// - Legacy `POST /chat/:id` to create a message (linux.do / FluxDo).
//   `POST /chat/api/channels/:id/messages` 404s on linux.do with
//   `error_type: not_found` / 「找不到请求的 URL 或资源。」

enum DiscourseChatEndpoint {
    static func channels() -> String { "/chat/api/me/channels" }

    static func messages(channelId: Int, pageSize: Int) -> String {
        "/chat/api/channels/\(channelId)/messages?page_size=\(pageSize)"
    }

    static func sendMessage(channelId: Int) -> String {
        "/chat/\(channelId)"
    }

    static func sendMessageModern(channelId: Int) -> String {
        "/chat/api/channels/\(channelId)/messages"
    }
}

// MARK: - API

extension DiscourseAPI {
    func fetchChatChannels() async throws -> DiscourseChatChannelsResponse {
        let url = baseURL + DiscourseChatEndpoint.channels()
        let response = await session.request(url, method: .get).serializingData().response
        if let http = response.response, let responseURL = http.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(http.allHeaderFields, for: responseURL)
        }
        if let error = response.error { throw error }
        guard let data = response.data, !data.isEmpty else {
            return DiscourseChatChannelsResponse()
        }
        return (try? JSONDecoder().decode(DiscourseChatChannelsResponse.self, from: data))
            ?? DiscourseChatChannelsResponse()
    }

    func fetchChatMessages(channelId: Int, pageSize: Int = 50) async throws -> [DiscourseChatMessage] {
        let url = baseURL + DiscourseChatEndpoint.messages(channelId: channelId, pageSize: pageSize)
        let response = await session.request(url, method: .get).serializingData().response
        try throwIfUnsuccessfulChatResponse(response)
        guard let data = response.data, !data.isEmpty else { return [] }
        let decoded = try JSONDecoder().decode(DiscourseChatMessagesResponse.self, from: data)
        return decoded.messages
    }

    func sendChatMessage(channelId: Int, message: String, inReplyToId: Int? = nil) async throws {
        var parameters: Parameters = ["message": message]
        if let inReplyToId {
            parameters["in_reply_to_id"] = inReplyToId
        }
        do {
            try await postChatMessage(
                path: DiscourseChatEndpoint.sendMessage(channelId: channelId),
                parameters: parameters
            )
        } catch let error as DiscourseAPIError where error.errorType == "not_found" {
            try await postChatMessage(
                path: DiscourseChatEndpoint.sendMessageModern(channelId: channelId),
                parameters: parameters
            )
        }
    }

    private func postChatMessage(path: String, parameters: Parameters) async throws {
        let response = await session.request(
            baseURL + path,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default
        ).serializingData().response
        try throwIfUnsuccessfulChatResponse(response)
    }

    private func throwIfUnsuccessfulChatResponse(_ response: AFDataResponse<Data>) throws {
        if let http = response.response, let responseURL = http.url,
           shouldMergeWebCookieResponseHeaders(baseURL: baseURL, responseURL: responseURL) {
            WebCookieStore.shared.mergeResponseHeaders(http.allHeaderFields, for: responseURL)
        }
        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let error = response.error { throw error }
        guard let status = response.response?.statusCode, !(200 ..< 300).contains(status) else {
            return
        }
        if let data = response.data {
            if let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data),
               !errBody.errors.isEmpty {
                throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
            }
        }
        throw DiscourseAPIError(
            messages: [String(localized: "chat.request.failed", defaultValue: "请求失败")],
            errorType: "chat_request_failed"
        )
    }

    func castPostVotingVote(postId: Int, direction: String) async throws {
        let url = baseURL + "/post_voting/vote"
        let parameters: Parameters = [
            "post_id": postId,
            "direction": direction,
        ]
        try await requestVoidURL(url, method: .put, parameters: parameters)
    }

    func removePostVotingVote(postId: Int) async throws {
        let url = baseURL + "/post_voting/vote"
        let parameters: Parameters = ["post_id": postId]
        try await requestVoidURL(url, method: .delete, parameters: parameters)
    }

    private func requestVoidURL(_ url: String, method: HTTPMethod, parameters: Parameters) async throws {
        let response = await session.request(
            url,
            method: method,
            parameters: parameters,
            encoding: JSONEncoding.default
        ).serializingData().response
        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let error = response.error { throw error }
        if let status = response.response?.statusCode, !(200 ..< 300).contains(status) {
            throw DiscourseAPIError(messages: ["HTTP \(status)"], errorType: nil)
        }
    }
}

