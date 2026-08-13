import Combine
import Foundation

@MainActor
final class NotificationsViewModel: DoerObservableObject {
    var notifications: [DiscourseNotification] { coordinator.notifications }
    var unreadCount: Int { coordinator.unreadCount }
    var isLoading: Bool { coordinator.isLoading }
    var errorMessage: String? { coordinator.errorMessage }
    var requiresLogin: Bool { coordinator.requiresLogin }

    private let coordinator: ForumNotificationCoordinator
    private var coordinatorObservation: AnyCancellable?

    init(coordinator: ForumNotificationCoordinator) {
        self.coordinator = coordinator
        super.init()
        // Coordinator owns list/unread state and calls notifyChanged(); forward so
        // pages that observe this ViewModel actually refresh after pull-to-refresh.
        coordinatorObservation = coordinator.objectWillChange.sink { [weak self] _ in
            self?.notifyChanged()
        }
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
