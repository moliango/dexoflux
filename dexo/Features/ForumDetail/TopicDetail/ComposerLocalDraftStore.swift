import Foundation

/// Local autosave for composers (Phase 2). Survives process kill; cleared on successful send.
/// Server drafts (Me → Drafts) remain separate; this covers in-progress typing.
enum ComposerLocalDraftStore {
    private static let defaults = UserDefaults.standard
    private static let prefix = "composer.local_draft."

    // MARK: - Reply

    static func replyKey(baseURL: String, topicId: Int, replyToPostNumber: Int?) -> String {
        let host = normalizedHost(baseURL)
        if let replyToPostNumber {
            return "\(prefix)reply.\(host).t\(topicId).p\(replyToPostNumber)"
        }
        return "\(prefix)reply.\(host).t\(topicId)"
    }

    static func loadReply(baseURL: String, topicId: Int, replyToPostNumber: Int?) -> String? {
        let key = replyKey(baseURL: baseURL, topicId: topicId, replyToPostNumber: replyToPostNumber)
        let text = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    static func saveReply(baseURL: String, topicId: Int, replyToPostNumber: Int?, raw: String) {
        let key = replyKey(baseURL: baseURL, topicId: topicId, replyToPostNumber: replyToPostNumber)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(raw, forKey: key)
        }
    }

    static func clearReply(baseURL: String, topicId: Int, replyToPostNumber: Int?) {
        defaults.removeObject(
            forKey: replyKey(baseURL: baseURL, topicId: topicId, replyToPostNumber: replyToPostNumber)
        )
    }

    // MARK: - New topic

    static func newTopicKey(baseURL: String) -> String {
        "\(prefix)new_topic.\(normalizedHost(baseURL))"
    }

    struct NewTopicDraft: Codable, Equatable {
        var title: String
        var raw: String
        var categoryId: Int?
        var tags: [String]
    }

    static func loadNewTopic(baseURL: String) -> NewTopicDraft? {
        guard let data = defaults.data(forKey: newTopicKey(baseURL: baseURL)),
              let draft = try? JSONDecoder().decode(NewTopicDraft.self, from: data)
        else { return nil }
        let hasContent = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasContent ? draft : nil
    }

    static func saveNewTopic(baseURL: String, title: String, raw: String, categoryId: Int?, tags: [String]) {
        let draft = NewTopicDraft(title: title, raw: raw, categoryId: categoryId, tags: tags)
        let hasContent = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let key = newTopicKey(baseURL: baseURL)
        if !hasContent {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: key)
        }
    }

    static func clearNewTopic(baseURL: String) {
        defaults.removeObject(forKey: newTopicKey(baseURL: baseURL))
    }

    // MARK: - Helpers

    private static func normalizedHost(_ baseURL: String) -> String {
        if let host = URL(string: baseURL)?.host?.lowercased(), !host.isEmpty {
            return host
        }
        return baseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
