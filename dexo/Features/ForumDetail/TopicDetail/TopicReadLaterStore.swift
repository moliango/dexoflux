import Foundation

extension Notification.Name {
    static let topicReadLaterDidChange = Notification.Name("topicReadLaterDidChange")
}

/// Lightweight "read later" queue — local, account-scoped, lighter than bookmarks.
final class TopicReadLaterStore {
    static let shared = TopicReadLaterStore()

    struct Entry: Codable, Equatable, Identifiable {
        var id: String { storageKey }
        let topicId: Int
        let baseURL: String
        let username: String
        var title: String
        var addedAt: Date
        var lastReadPostNumber: Int?

        var storageKey: String {
            TopicReadLaterStore.key(topicId: topicId, baseURL: baseURL, username: username)
        }
    }

    private let defaults: UserDefaults
    private let legacyKey = "topic.read_later.entries"
    private let entriesKey = "topic.read_later.entries.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacyIfNeeded()
    }

    func contains(topicId: Int, baseURL: String, username: String?) -> Bool {
        let k = Self.key(topicId: topicId, baseURL: baseURL, username: username)
        return loadEntries().contains { $0.storageKey == k }
    }

    func entries(baseURL: String, username: String?) -> [Entry] {
        let normalizedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let account = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "guest"
        return loadEntries()
            .filter {
                $0.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == normalizedBase
                    && $0.username == account
            }
            .sorted { $0.addedAt > $1.addedAt }
    }

    @discardableResult
    func toggle(
        topicId: Int,
        baseURL: String,
        username: String?,
        title: String? = nil,
        lastReadPostNumber: Int? = nil
    ) -> Bool {
        if contains(topicId: topicId, baseURL: baseURL, username: username) {
            remove(topicId: topicId, baseURL: baseURL, username: username)
            return false
        }
        add(
            topicId: topicId,
            baseURL: baseURL,
            username: username,
            title: title ?? "#\(topicId)",
            lastReadPostNumber: lastReadPostNumber
        )
        return true
    }

    func add(
        topicId: Int,
        baseURL: String,
        username: String?,
        title: String,
        lastReadPostNumber: Int? = nil
    ) {
        guard topicId > 0 else { return }
        let account = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "guest"
        var all = loadEntries()
        let k = Self.key(topicId: topicId, baseURL: baseURL, username: username)
        all.removeAll { $0.storageKey == k }
        all.insert(
            Entry(
                topicId: topicId,
                baseURL: baseURL,
                username: account,
                title: title,
                addedAt: Date(),
                lastReadPostNumber: lastReadPostNumber
            ),
            at: 0
        )
        if all.count > 500 {
            all = Array(all.prefix(500))
        }
        save(all)
        notify()
    }

    func remove(topicId: Int, baseURL: String, username: String?) {
        let k = Self.key(topicId: topicId, baseURL: baseURL, username: username)
        var all = loadEntries()
        let before = all.count
        all.removeAll { $0.storageKey == k }
        guard all.count != before else { return }
        save(all)
        notify()
    }

    /// Keep resume watermark fresh while the topic stays in the queue.
    func updateProgress(
        topicId: Int,
        baseURL: String,
        username: String?,
        lastReadPostNumber: Int?,
        title: String? = nil
    ) {
        guard topicId > 0 else { return }
        let k = Self.key(topicId: topicId, baseURL: baseURL, username: username)
        var all = loadEntries()
        guard let index = all.firstIndex(where: { $0.storageKey == k }) else { return }
        var entry = all[index]
        var changed = false
        if let lastReadPostNumber, lastReadPostNumber > (entry.lastReadPostNumber ?? 0) {
            entry.lastReadPostNumber = lastReadPostNumber
            changed = true
        }
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != entry.title {
                entry.title = trimmed
                changed = true
            }
        }
        guard changed else { return }
        all[index] = entry
        save(all)
        notify()
    }

    // MARK: - Private

    private func loadEntries() -> [Entry] {
        guard let data = defaults.data(forKey: entriesKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }

    private func save(_ entries: [Entry]) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: entriesKey)
        }
        // Keep legacy set in sync for any old callers of raw keys.
        defaults.set(entries.map(\.storageKey).sorted(), forKey: legacyKey)
    }

    private func migrateLegacyIfNeeded() {
        guard defaults.data(forKey: entriesKey) == nil,
              let legacy = defaults.stringArray(forKey: legacyKey),
              !legacy.isEmpty
        else { return }
        var migrated: [Entry] = []
        for raw in legacy {
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, let topicId = Int(parts[2]) else { continue }
            migrated.append(
                Entry(
                    topicId: topicId,
                    baseURL: parts[0],
                    username: parts[1],
                    title: "#\(topicId)",
                    addedAt: Date(timeIntervalSince1970: 0),
                    lastReadPostNumber: nil
                )
            )
        }
        save(migrated)
    }

    private func notify() {
        NotificationCenter.default.post(name: .topicReadLaterDidChange, object: nil)
    }

    static func key(topicId: Int, baseURL: String, username: String?) -> String {
        let normalizedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let account = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "guest"
        return "\(normalizedBase)|\(account)|\(topicId)"
    }
}
