import Alamofire
import Foundation

// MARK: - Models

struct DiscourseChatChannel: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String?
    let slug: String?
    let lastMessageSentAt: String?
    let currentUserMembership: Membership?

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

    enum CodingKeys: String, CodingKey {
        case id, title, slug
        case lastMessageSentAt = "last_message_sent_at"
        case currentUserMembership = "current_user_membership"
    }

    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        let s = slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "#\(id)" : s
    }

    var unreadCount: Int {
        max(currentUserMembership?.unreadCount ?? 0, 0)
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
    let user: User?
    let cooked: String?

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
    }

    var displayBody: String {
        let raw = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }
        // Strip minimal tags from cooked fallback.
        let cookedText = (cooked ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cookedText
    }
}

struct DiscourseChatMessagesResponse: Decodable {
    let messages: [DiscourseChatMessage]

    enum CodingKeys: String, CodingKey {
        case messages
        case chatMessages = "chat_messages"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = (try? c.decodeIfPresent([DiscourseChatMessage].self, forKey: .messages))
            ?? (try? c.decodeIfPresent([DiscourseChatMessage].self, forKey: .chatMessages))
            ?? []
    }
}

// MARK: - API

extension DiscourseAPI {
    func fetchChatChannels() async throws -> DiscourseChatChannelsResponse {
        let url = baseURL + "/chat/api/me/channels"
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
        let url = baseURL + "/chat/api/channels/\(channelId)/messages?page_size=\(pageSize)"
        let response = await session.request(url, method: .get).serializingData().response
        if let error = response.error { throw error }
        guard let data = response.data, !data.isEmpty else { return [] }
        let decoded = try JSONDecoder().decode(DiscourseChatMessagesResponse.self, from: data)
        return decoded.messages
    }

    func sendChatMessage(channelId: Int, message: String) async throws {
        let url = baseURL + "/chat/api/channels/\(channelId)/messages"
        let parameters: Parameters = ["message": message]
        let response = await session.request(
            url,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default
        ).serializingData().response
        if let status = response.response?.statusCode, !(200 ..< 300).contains(status) {
            let body = response.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw DiscourseAPIError(messages: [body.isEmpty ? "chat send failed (\(status))" : body], errorType: "chat_send_failed")
        }
        if let error = response.error { throw error }
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

