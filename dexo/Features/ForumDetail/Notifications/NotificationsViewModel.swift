import Foundation

@MainActor
final class NotificationsViewModel: DexoObservableObject {
    var notifications: [DiscourseNotification] { coordinator.notifications }
    var isLoading: Bool { coordinator.isLoading }
    var errorMessage: String? { coordinator.errorMessage }
    var requiresLogin: Bool { coordinator.requiresLogin }

    private let coordinator: ForumNotificationCoordinator

    init(coordinator: ForumNotificationCoordinator) {
        self.coordinator = coordinator
    }

    func loadNotifications() async {
        await coordinator.refresh(forceList: true, deliverAlerts: false)
    }

    func markNotificationRead(id: Int) async {
        await coordinator.markNotificationRead(id: id)
    }

    func markAllRead() async {
        await coordinator.markAllRead()
    }
}
