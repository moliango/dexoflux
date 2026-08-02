import Alamofire
import Foundation
import UniformTypeIdentifiers

// MARK: - messages
extension DiscourseAPI {
    func fetchNotifications() async throws -> DiscourseNotificationList {
        try await request(route: .notifications)
    }

    func markNotificationRead(id: Int) async throws {
        try await markNotificationsRead(parameters: ["id": id])
    }

    func markAllNotificationsRead() async throws {
        try await markNotificationsRead(parameters: nil)
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
}
