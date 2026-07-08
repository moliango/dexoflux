import CryptoKit
import Foundation

final class MeViewModel: DexoObservableObject {
    var currentUser: DiscourseCurrentUser?
    var userProfile: DiscourseUserProfile?
    var summary: DiscourseUserSummary?
    var isLoading = false
    var requiresLogin = false
    var errorMessage: String?

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadProfile(forceRefresh: Bool = false) async {
        guard let username = AuthManager.shared.username(for: api.baseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !username.isEmpty
        else {
            MeProfileCacheStore.clear(baseURL: api.baseURL)
            clearSessionState(requiresLogin: true)
            return
        }

        let cachedEntry = forceRefresh ? nil : MeProfileCacheStore.cachedProfile(
            baseURL: api.baseURL,
            username: username
        )
        let renderedCache = cachedEntry != nil

        if let cachedEntry {
            apply(cachedEntry)
        }

        isLoading = !renderedCache
        requiresLogin = false
        errorMessage = nil
        notifyChanged()

        do {
            async let profileTask = api.fetchUserProfile(username: username)
            async let summaryTask = api.fetchUserSummary(username: username)
            let (profile, userSummary) = try await (profileTask, summaryTask)
            let currentUser = DiscourseCurrentUser(
                id: profile.id,
                username: profile.username,
                name: profile.name,
                avatarTemplate: profile.avatarTemplate
            )
            self.currentUser = currentUser
            userProfile = profile
            summary = userSummary
            requiresLogin = false
            errorMessage = nil
            MeProfileCacheStore.save(
                baseURL: api.baseURL,
                username: username,
                currentUser: currentUser,
                userProfile: profile,
                summary: userSummary
            )
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                AuthManager.shared.invalidateWebSession(for: api.baseURL)
                currentUser = nil
                userProfile = nil
                summary = nil
                requiresLogin = true
            } else if !renderedCache {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
        notifyChanged()
    }

    func reload() async {
        await loadProfile(forceRefresh: true)
    }

    func clearSessionState(requiresLogin: Bool = true) {
        currentUser = nil
        userProfile = nil
        summary = nil
        isLoading = false
        self.requiresLogin = requiresLogin
        errorMessage = nil
        notifyChanged()
    }

    private func apply(_ entry: MeProfileCacheStore.Entry) {
        currentUser = entry.currentUser
        userProfile = entry.userProfile
        summary = entry.summary
    }
}

enum MeProfileCacheStore {
    struct Entry: Codable {
        let baseURL: String
        let username: String
        let storedAt: Date
        let currentUser: DiscourseCurrentUser
        let userProfile: DiscourseUserProfile
        let summary: DiscourseUserSummary
    }

    private static let expirationInterval: TimeInterval = 20 * 60

    private static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("MeProfileCacheV1", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func cachedProfile(baseURL: String, username: String, now: Date = Date()) -> Entry? {
        let file = cacheFile(baseURL: baseURL, username: username)
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }

        guard normalizedBaseURL(entry.baseURL) == normalizedBaseURL(baseURL),
              normalizedUsername(entry.username) == normalizedUsername(username)
        else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }

        guard now.timeIntervalSince(entry.storedAt) < expirationInterval else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }

        return entry
    }

    static func save(
        baseURL: String,
        username: String,
        currentUser: DiscourseCurrentUser,
        userProfile: DiscourseUserProfile,
        summary: DiscourseUserSummary,
        now: Date = Date()
    ) {
        let entry = Entry(
            baseURL: normalizedBaseURL(baseURL),
            username: username,
            storedAt: now,
            currentUser: currentUser,
            userProfile: userProfile,
            summary: summary
        )
        let baseDirectory = baseDirectory(for: baseURL)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: cacheFile(baseURL: baseURL, username: username), options: .atomic)
    }

    static func clear(baseURL: String) {
        try? FileManager.default.removeItem(at: baseDirectory(for: baseURL))
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static func cacheSize() -> Int64 {
        directorySize(at: cacheDirectory)
    }

    private static func cacheFile(baseURL: String, username: String) -> URL {
        baseDirectory(for: baseURL).appendingPathComponent("\(hash(normalizedUsername(username))).json")
    }

    private static func baseDirectory(for baseURL: String) -> URL {
        cacheDirectory.appendingPathComponent(hash(normalizedBaseURL(baseURL)), isDirectory: true)
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return enumerator.reduce(Int64(0)) { partialResult, item in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            else { return partialResult }
            return partialResult + Int64(values.fileSize ?? 0)
        }
    }
}
