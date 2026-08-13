import Foundation
import UserNotifications

/// Local one-shot reminders for read-later / bookmarks (no server push required).
enum LocalReminderScheduler {
    enum Kind: String {
        case readLater = "read_later"
        case bookmark = "bookmark"
    }

    struct Request: Equatable {
        let kind: Kind
        let topicId: Int
        let baseURL: String
        let title: String
        let fireAt: Date
    }

    private static let center = UNUserNotificationCenter.current()
    private static let prefix = "dexo.reminder."

    static func requestId(kind: Kind, topicId: Int, baseURL: String) -> String {
        let host = baseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
            .replacingOccurrences(of: "://", with: ".")
        return "\(prefix)\(kind.rawValue).\(host).\(topicId)"
    }

    static func schedule(_ request: Request) async -> Bool {
        let granted = await ensureAuthorization()
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        switch request.kind {
        case .readLater:
            content.title = String(localized: "reminder.read_later.title", defaultValue: "稍后阅读提醒")
        case .bookmark:
            content.title = String(localized: "reminder.bookmark.title", defaultValue: "书签提醒")
        }
        content.body = request.title
        content.sound = .default
        content.userInfo = [
            ForumNotificationRoute.UserInfoKey.baseURL: request.baseURL,
            ForumNotificationRoute.UserInfoKey.topicId: request.topicId,
            "dexo.reminder.kind": request.kind.rawValue,
        ]

        let interval = max(request.fireAt.timeIntervalSinceNow, 5)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let id = requestId(kind: request.kind, topicId: request.topicId, baseURL: request.baseURL)
        let note = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(note)
            return true
        } catch {
            return false
        }
    }

    static func cancel(kind: Kind, topicId: Int, baseURL: String) {
        center.removePendingNotificationRequests(
            withIdentifiers: [requestId(kind: kind, topicId: topicId, baseURL: baseURL)]
        )
    }

    /// Presets: 1h / tonight 21:00 / tomorrow 9:00
    static func presetDates(from now: Date = Date()) -> [(title: String, date: Date)] {
        let calendar = Calendar.current
        let oneHour = now.addingTimeInterval(3600)
        var tonightComponents = calendar.dateComponents([.year, .month, .day], from: now)
        tonightComponents.hour = 21
        tonightComponents.minute = 0
        var tonight = calendar.date(from: tonightComponents) ?? now.addingTimeInterval(3600)
        if tonight <= now {
            tonight = calendar.date(byAdding: .day, value: 1, to: tonight) ?? tonight.addingTimeInterval(86400)
        }
        var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: now)
        tomorrowComponents.day = (tomorrowComponents.day ?? 1) + 1
        tomorrowComponents.hour = 9
        tomorrowComponents.minute = 0
        let tomorrow = calendar.date(from: tomorrowComponents)
            ?? now.addingTimeInterval(86400)
        return [
            (String(localized: "reminder.preset.1h", defaultValue: "1 小时后"), oneHour),
            (String(localized: "reminder.preset.tonight", defaultValue: "今晚 21:00"), tonight),
            (String(localized: "reminder.preset.tomorrow", defaultValue: "明天 9:00"), tomorrow),
        ]
    }

    private static func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        default:
            return false
        }
    }
}
