import Foundation

enum NotionSyncScope: String, Codable, CaseIterable {
    case firstPostOnly = "first_post_only"
    case allPosts = "all_posts"

    var title: String {
        switch self {
        case .firstPostOnly:
            return String(localized: "notion.scope.first_post", defaultValue: "仅主帖")
        case .allPosts:
            return String(localized: "notion.scope.all_loaded", defaultValue: "全部已加载帖子")
        }
    }

    var exportRange: TopicExportRange {
        switch self {
        case .firstPostOnly: return .firstPost
        case .allPosts: return .loadedPosts
        }
    }
}

struct NotionConfig: Equatable {
    var databaseId: String?
    var autoSyncOnBookmark: Bool
    var syncScope: NotionSyncScope

    var hasDatabase: Bool {
        !(databaseId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let empty = NotionConfig(databaseId: nil, autoSyncOnBookmark: false, syncScope: .allPosts)
}

/// Token in Keychain; non-secret fields in UserDefaults, scoped by account.
final class NotionConfigStore {
    static let shared = NotionConfigStore()

    private let defaults: UserDefaults
    private let keychainService = "com.naine.doer.notion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func scopeKey(baseURL: String, username: String?) -> String {
        AccountScopeKey.make(baseURL: baseURL, username: username)
    }

    func loadConfig(scopeKey: String) -> NotionConfig {
        let raw = defaults.string(forKey: metaKey(scopeKey))
        guard let raw, let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .empty }
        let scope = NotionSyncScope(rawValue: json["sync_scope"] as? String ?? "") ?? .allPosts
        return NotionConfig(
            databaseId: json["database_id"] as? String,
            autoSyncOnBookmark: json["auto_sync_bookmark"] as? Bool ?? false,
            syncScope: scope
        )
    }

    func saveConfig(_ config: NotionConfig, scopeKey: String) {
        var payload: [String: Any] = [
            "auto_sync_bookmark": config.autoSyncOnBookmark,
            "sync_scope": config.syncScope.rawValue,
        ]
        if let databaseId = config.databaseId?.trimmingCharacters(in: .whitespacesAndNewlines), !databaseId.isEmpty {
            payload["database_id"] = databaseId
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: metaKey(scopeKey))
        }
    }

    func token(scopeKey: String) -> String? {
        KeychainHelper.string(service: keychainService, account: scopeKey)
    }

    func setToken(_ token: String?, scopeKey: String) throws {
        if let token, !token.isEmpty {
            try KeychainHelper.setString(token, service: keychainService, account: scopeKey)
        } else {
            KeychainHelper.deleteString(service: keychainService, account: scopeKey)
        }
    }

    func isComplete(scopeKey: String) -> Bool {
        let cfg = loadConfig(scopeKey: scopeKey)
        let tok = token(scopeKey: scopeKey) ?? ""
        return cfg.hasDatabase && !tok.isEmpty
    }

    func clear(scopeKey: String) {
        defaults.removeObject(forKey: metaKey(scopeKey))
        KeychainHelper.deleteString(service: keychainService, account: scopeKey)
    }

    private func metaKey(_ scopeKey: String) -> String {
        "notion_config_meta.\(scopeKey)"
    }
}
