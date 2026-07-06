import Foundation

final class NotificationsViewModel: DexoObservableObject {
    var notifications: [DiscourseNotification] = []
    var isLoading = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        notifyChanged()
        do {
            let result = try await api.fetchNotifications()
            notifications = result.notifications
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }

    func markNotificationRead(id: Int) async {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        guard !notifications[index].read else { return }
        notifications[index] = notifications[index].markingRead()
        notifyChanged()
        do {
            try await api.markNotificationRead(id: id)
        } catch {
            // Keep the optimistic local read state; failing to mark-read should not block navigation.
        }
    }

    func markAllRead() async {
        guard notifications.contains(where: { !$0.read }) else { return }
        notifications = notifications.map { $0.markingRead() }
        notifyChanged()
        do {
            try await api.markAllNotificationsRead()
        } catch {
            errorMessage = error.localizedDescription
            notifyChanged()
        }
    }
}
