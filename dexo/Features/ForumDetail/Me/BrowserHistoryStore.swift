import Foundation

enum BrowserNavigationURLKind: Equatable {
    case web
    case internalWebKit
    case externalApp
    case invalid
}

enum BrowserNavigationURLClassifier {
    static func classify(_ url: URL) -> BrowserNavigationURLKind {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return .invalid }
        switch scheme {
        case "http", "https":
            return url.host == nil ? .invalid : .web
        case "about", "data", "blob", "javascript":
            return .internalWebKit
        default:
            return .externalApp
        }
    }
}

enum AccountScopeKey {
    static func make(baseURL: String, username: String?) -> String {
        // 与论坛实例归一化一致，避免 https://linux.do 与 https://linux.do/ 分成两份数据。
        let normalized = ForumInstance.normalizedBaseURL(baseURL)
        return "\(normalized)|\(normalizedUsername(username))"
    }

    private static func normalizedUsername(_ username: String?) -> String {
        username?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "guest"
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate) else {
            return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" {
            components.path = ""
        }
        return components.string?.lowercased() ?? candidate.lowercased()
    }
}

struct BrowserPageRecord: Codable, Hashable, Identifiable {
    var id: String { urlString }

    let urlString: String
    let title: String
    let timestamp: Date
}

final class BrowserHistoryStore {
    private static var cache: [String: BrowserHistoryStore] = [:]
    private static let cacheLock = NSLock()

    /// 同账号/论坛共用同一 store，避免“浏览了但历史是空的”。
    static func shared(baseURL: String, username: String?) -> BrowserHistoryStore {
        let key = AccountScopeKey.make(baseURL: baseURL, username: username)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = cache[key] {
            existing.reload()
            return existing
        }
        let store = BrowserHistoryStore(baseURL: baseURL, username: username)
        cache[key] = store
        return store
    }

    private struct StorageFile: Codable {
        var accounts: [AccountData] = []
    }

    private struct AccountData: Codable {
        let scopeKey: String
        var history: [BrowserPageRecord]
        var bookmarks: [BrowserPageRecord]
    }

    private(set) var history: [BrowserPageRecord] = []
    private(set) var bookmarks: [BrowserPageRecord] = []

    private let scopeKey: String
    private let directoryURL: URL
    private let maxHistoryCount: Int

    init(
        baseURL: String,
        username: String?,
        directoryURL: URL? = nil,
        maxHistoryCount: Int = 200
    ) {
        self.scopeKey = AccountScopeKey.make(baseURL: baseURL, username: username)
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = root.appendingPathComponent("DexoFlux/Browser", isDirectory: true)
        }
        self.maxHistoryCount = max(1, maxHistoryCount)
        try? FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        reload()
    }

    static func storageURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("dexo_browser_data.json")
    }

    /// 兼容旧路径：Application Support 根目录的历史文件。
    private static func legacyStorageURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dexo_browser_data.json")
    }

    func reload() {
        var storage = loadStorage()
        guard let index = storage.accounts.firstIndex(where: { $0.scopeKey == scopeKey }) else {
            history = []
            bookmarks = []
            return
        }
        let originalHistoryCount = storage.accounts[index].history.count
        let originalBookmarkCount = storage.accounts[index].bookmarks.count
        storage.accounts[index].history.removeAll { !Self.isValidStoredPage($0) }
        storage.accounts[index].bookmarks.removeAll { !Self.isValidStoredPage($0) }
        history = storage.accounts[index].history
        bookmarks = storage.accounts[index].bookmarks
        if history.count != originalHistoryCount || bookmarks.count != originalBookmarkCount {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(storage) {
                try? data.write(to: Self.storageURL(in: directoryURL), options: .atomic)
            }
        }
    }

    func recordVisit(url: URL, title: String?, visitedAt: Date = Date()) throws {
        guard let normalizedURL = Self.normalizedPageURL(url) else {
            throw BrowserHistoryStoreError.unsupportedURL
        }
        let record = BrowserPageRecord(
            urlString: normalizedURL.absoluteString,
            title: Self.displayTitle(title, fallbackURL: normalizedURL),
            timestamp: visitedAt
        )
        try mutate { account in
            account.history.removeAll { $0.urlString == record.urlString }
            account.history.insert(record, at: 0)
            if account.history.count > maxHistoryCount {
                account.history.removeLast(account.history.count - maxHistoryCount)
            }
        }
    }

    func addBookmark(url: URL, title: String?, addedAt: Date = Date()) throws {
        guard let normalizedURL = Self.normalizedPageURL(url) else {
            throw BrowserHistoryStoreError.unsupportedURL
        }
        let record = BrowserPageRecord(
            urlString: normalizedURL.absoluteString,
            title: Self.displayTitle(title, fallbackURL: normalizedURL),
            timestamp: addedAt
        )
        try mutate { account in
            account.bookmarks.removeAll { $0.urlString == record.urlString }
            account.bookmarks.insert(record, at: 0)
        }
    }

    func renameBookmark(_ record: BrowserPageRecord, title: String) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        try mutate { account in
            guard let index = account.bookmarks.firstIndex(where: { $0.urlString == record.urlString }) else {
                return
            }
            account.bookmarks[index] = BrowserPageRecord(
                urlString: record.urlString,
                title: trimmedTitle,
                timestamp: record.timestamp
            )
        }
    }

    func removeBookmark(url: URL) throws {
        guard let normalizedURL = Self.normalizedPageURL(url) else { return }
        try mutate { account in
            account.bookmarks.removeAll { $0.urlString == normalizedURL.absoluteString }
        }
    }

    func removeBookmark(_ record: BrowserPageRecord) throws {
        try mutate { account in
            account.bookmarks.removeAll { $0.urlString == record.urlString }
        }
    }

    func removeHistory(_ record: BrowserPageRecord) throws {
        try mutate { account in
            account.history.removeAll { $0.urlString == record.urlString }
        }
    }

    func clearHistory() throws {
        try mutate { $0.history.removeAll() }
    }

    func clearBookmarks() throws {
        try mutate { $0.bookmarks.removeAll() }
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url, let normalizedURL = Self.normalizedPageURL(url) else { return false }
        return bookmarks.contains { $0.urlString == normalizedURL.absoluteString }
    }

    private func mutate(_ update: (inout AccountData) -> Void) throws {
        var storage = loadStorage()
        var account = storage.accounts.first(where: { $0.scopeKey == scopeKey })
            ?? AccountData(scopeKey: scopeKey, history: [], bookmarks: [])
        update(&account)

        if let index = storage.accounts.firstIndex(where: { $0.scopeKey == scopeKey }) {
            storage.accounts[index] = account
        } else {
            storage.accounts.append(account)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(storage)
        try data.write(to: Self.storageURL(in: directoryURL), options: .atomic)
        history = account.history
        bookmarks = account.bookmarks
    }

    private func loadStorage() -> StorageFile {
        let url = Self.storageURL(in: directoryURL)
        if let data = try? Data(contentsOf: url),
           let storage = try? JSONDecoder().decode(StorageFile.self, from: data) {
            return storage
        }
        // 迁移旧位置数据，避免用户感觉「历史/书签是空的」。
        let legacy = Self.legacyStorageURL()
        if legacy != url,
           let data = try? Data(contentsOf: legacy),
           let storage = try? JSONDecoder().decode(StorageFile.self, from: data) {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            return storage
        }
        return StorageFile()
    }

    static func normalizedPageURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        components.scheme = scheme
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.url
    }

    private static func isValidStoredPage(_ record: BrowserPageRecord) -> Bool {
        guard let url = URL(string: record.urlString) else { return false }
        return normalizedPageURL(url) != nil
    }

    private static func displayTitle(_ title: String?, fallbackURL: URL) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? (fallbackURL.host ?? fallbackURL.absoluteString) : trimmed
    }
}

enum BrowserHistoryStoreError: LocalizedError {
    case unsupportedURL

    var errorDescription: String? {
        String(localized: "me.browser.unsupported_url", defaultValue: "仅支持 http 或 https 地址。")
    }
}
