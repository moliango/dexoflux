import Foundation

/// Local highest-seen floor cache. Merges with Discourse `last_read_post_number`
/// so list styling and resume-reading stay correct when timings lag or offline.
final class TopicReadProgressStore {
    static let shared = TopicReadProgressStore()

    private let defaults: UserDefaults
    private let storageKey = "topic.read_progress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func highestSeen(topicId: Int, baseURL: String, username: String?) -> Int {
        let map = loadMap()
        return map[key(topicId: topicId, baseURL: baseURL, username: username)] ?? 0
    }

    /// Records a new high-water mark (monotonic).
    func record(topicId: Int, highestSeen: Int, baseURL: String, username: String?) {
        guard topicId > 0, highestSeen > 0 else { return }
        var map = loadMap()
        let k = key(topicId: topicId, baseURL: baseURL, username: username)
        let previous = map[k] ?? 0
        guard highestSeen > previous else { return }
        map[k] = highestSeen
        // Cap growth — drop oldest by rewriting only current map (fine for typical use).
        if map.count > 2_000 {
            let trimmed = map.sorted { $0.value > $1.value }.prefix(1_500)
            map = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }
        defaults.set(map, forKey: storageKey)
    }

    /// Effective last-read = max(server, local).
    func mergedLastRead(
        serverLastRead: Int?,
        topicId: Int,
        baseURL: String,
        username: String?
    ) -> Int {
        max(serverLastRead ?? 0, highestSeen(topicId: topicId, baseURL: baseURL, username: username))
    }

    func applyLocalProgress(
        to topic: DiscourseTopicList.Topic,
        baseURL: String,
        username: String?
    ) -> DiscourseTopicList.Topic {
        let local = highestSeen(topicId: topic.id, baseURL: baseURL, username: username)
        guard local > 0 else { return topic }
        let server = topic.lastReadPostNumber ?? 0
        guard local > server || topic.unseen else { return topic }
        return topic.updatingReadProgress(highestSeen: max(local, server))
    }

    private func loadMap() -> [String: Int] {
        (defaults.dictionary(forKey: storageKey) as? [String: Int]) ?? [:]
    }

    private func key(topicId: Int, baseURL: String, username: String?) -> String {
        let normalizedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let account = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "guest"
        return "\(normalizedBase)|\(account)|\(topicId)"
    }
}
