import Foundation

/// Multi-account username/password store for Discourse web login (per host).
/// Passwords stay in Keychain; usernames are ordered by last-used.
final class AccountCredentialStore {
    struct Account: Equatable {
        let username: String
        let password: String
    }

    private let service: String
    private let usernamesKey = "usernames"
    private let lastUsedKey = "lastUsed"
    private let legacyUsernameKey = "username"
    private let legacyPasswordKey = "password"

    init(host: String) {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        service = "com.naine.dexoflux.web-login.\(normalized.isEmpty ? "forum" : normalized)"
        migrateLegacySingleAccountIfNeeded()
    }

    /// Convenience for the default Linux.do host used by most call sites.
    static func forBaseURL(_ baseURL: String) -> AccountCredentialStore {
        let host = URL(string: baseURL)?.host
            ?? baseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .components(separatedBy: "/")
            .first
            ?? "forum"
        return AccountCredentialStore(host: host)
    }

    var accounts: [Account] {
        usernames.compactMap { username in
            guard let password = password(for: username), !password.isEmpty else { return nil }
            return Account(username: username, password: password)
        }
    }

    var hasCredentials: Bool { !accounts.isEmpty }

    var lastUsedUsername: String? {
        KeychainHelper.string(service: service, account: lastUsedKey)
    }

    var lastUsedAccount: Account? {
        if let last = lastUsedUsername,
           let password = password(for: last), !password.isEmpty {
            return Account(username: last, password: password)
        }
        return accounts.first
    }

    func save(username: String, password: String) {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !password.isEmpty else { return }
        try? KeychainHelper.setString(password, service: service, account: passwordAccount(for: trimmedUser))
        var list = usernames.filter { $0.caseInsensitiveCompare(trimmedUser) != .orderedSame }
        list.insert(trimmedUser, at: 0)
        saveUsernames(list)
        try? KeychainHelper.setString(trimmedUser, service: service, account: lastUsedKey)
        // Keep legacy single-slot keys in sync so older code paths still work.
        try? KeychainHelper.setString(trimmedUser, service: service, account: legacyUsernameKey)
        try? KeychainHelper.setString(password, service: service, account: legacyPasswordKey)
    }

    func remove(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainHelper.deleteString(service: service, account: passwordAccount(for: trimmed))
        let list = usernames.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        saveUsernames(list)
        if lastUsedUsername?.caseInsensitiveCompare(trimmed) == .orderedSame {
            if let next = list.first {
                try? KeychainHelper.setString(next, service: service, account: lastUsedKey)
                if let password = password(for: next) {
                    try? KeychainHelper.setString(next, service: service, account: legacyUsernameKey)
                    try? KeychainHelper.setString(password, service: service, account: legacyPasswordKey)
                }
            } else {
                KeychainHelper.deleteString(service: service, account: lastUsedKey)
                KeychainHelper.deleteString(service: service, account: legacyUsernameKey)
                KeychainHelper.deleteString(service: service, account: legacyPasswordKey)
            }
        }
    }

    func clear() {
        for username in usernames {
            KeychainHelper.deleteString(service: service, account: passwordAccount(for: username))
        }
        KeychainHelper.deleteString(service: service, account: usernamesKey)
        KeychainHelper.deleteString(service: service, account: lastUsedKey)
        KeychainHelper.deleteString(service: service, account: legacyUsernameKey)
        KeychainHelper.deleteString(service: service, account: legacyPasswordKey)
    }

    // MARK: - Private

    private var usernames: [String] {
        guard let raw = KeychainHelper.string(service: service, account: usernamesKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveUsernames(_ list: [String]) {
        guard let data = try? JSONEncoder().encode(list),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        try? KeychainHelper.setString(raw, service: service, account: usernamesKey)
    }

    private func password(for username: String) -> String? {
        KeychainHelper.string(service: service, account: passwordAccount(for: username))
    }

    private func passwordAccount(for username: String) -> String {
        "pwd.\(username.lowercased())"
    }

    private func migrateLegacySingleAccountIfNeeded() {
        guard usernames.isEmpty,
              let username = KeychainHelper.string(service: service, account: legacyUsernameKey),
              let password = KeychainHelper.string(service: service, account: legacyPasswordKey),
              !username.isEmpty, !password.isEmpty
        else { return }
        try? KeychainHelper.setString(password, service: service, account: passwordAccount(for: username))
        saveUsernames([username])
        try? KeychainHelper.setString(username, service: service, account: lastUsedKey)
    }
}
