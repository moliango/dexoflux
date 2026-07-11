import Foundation

final class TopicReadLaterStore {
    static let shared = TopicReadLaterStore()

    private let defaults: UserDefaults
    private let storageKey = "topic.read_later.entries"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(topicId: Int, baseURL: String, username: String?) -> Bool {
        entries.contains(key(topicId: topicId, baseURL: baseURL, username: username))
    }

    @discardableResult
    func toggle(topicId: Int, baseURL: String, username: String?) -> Bool {
        let value = key(topicId: topicId, baseURL: baseURL, username: username)
        var updated = entries
        let isAdded: Bool
        if updated.contains(value) {
            updated.remove(value)
            isAdded = false
        } else {
            updated.insert(value)
            isAdded = true
        }
        defaults.set(Array(updated).sorted(), forKey: storageKey)
        return isAdded
    }

    private var entries: Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    private func key(topicId: Int, baseURL: String, username: String?) -> String {
        let normalizedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let account = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "guest"
        return "\(normalizedBase)|\(account)|\(topicId)"
    }
}
