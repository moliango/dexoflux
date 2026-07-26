import Foundation

/// Lightweight Discourse presence heartbeat while composing.
final class PresenceService {
    static let shared = PresenceService()

    private var clientId = UUID().uuidString
    private var activeChannel: String?
    private var timer: Timer?
    private weak var api: DiscourseAPI?

    private init() {}

    func attach(api: DiscourseAPI) {
        self.api = api
    }

    func enter(topicId: Int) {
        let channel = "/discourse-presence/reply/\(topicId)"
        activeChannel = channel
        send(present: [channel], leave: [])
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, let channel = self.activeChannel else { return }
            self.send(present: [channel], leave: [])
        }
    }

    func leave() {
        guard let channel = activeChannel else { return }
        send(present: [], leave: [channel])
        activeChannel = nil
        timer?.invalidate()
        timer = nil
    }

    private func send(present: [String], leave: [String]) {
        guard let api else { return }
        Task {
            try? await api.updatePresence(clientId: clientId, presentChannels: present, leaveChannels: leave)
        }
    }
}
