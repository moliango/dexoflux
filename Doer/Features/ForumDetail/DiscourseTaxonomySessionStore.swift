import Foundation

enum DiscourseTaxonomySessionStore {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var categoriesByBaseURL: [String: [Int: DiscourseCategory]] = [:]
        var refreshingBaseURLs = Set<String>()
        var waitersByBaseURL: [String: [CheckedContinuation<[DiscourseCategory], Never>]] = [:]
    }

    private static let state = State()

    static func categories(for baseURL: String) -> [DiscourseCategory] {
        state.lock.lock()
        defer { state.lock.unlock() }
        guard let values = state.categoriesByBaseURL[normalizedBaseURL(baseURL)]?.values else {
            return []
        }
        return Array(values)
    }

    static func category(id: Int, for baseURL: String) -> DiscourseCategory? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.categoriesByBaseURL[normalizedBaseURL(baseURL)]?[id]
    }

    static func replace(categories: [DiscourseCategory], for baseURL: String) {
        guard !categories.isEmpty else { return }
        let indexed = DiscourseCategory.indexedById(from: categories)
        state.lock.lock()
        state.categoriesByBaseURL[normalizedBaseURL(baseURL)] = indexed
        state.lock.unlock()
    }

    static func beginRefresh(for baseURL: String) -> Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.refreshingBaseURLs.insert(normalizedBaseURL(baseURL)).inserted
    }

    static func endRefresh(for baseURL: String) {
        let key = normalizedBaseURL(baseURL)
        state.lock.lock()
        state.refreshingBaseURLs.remove(key)
        let categories = state.categoriesByBaseURL[key].map { Array($0.values) } ?? []
        let waiters = state.waitersByBaseURL.removeValue(forKey: key) ?? []
        state.lock.unlock()
        waiters.forEach { $0.resume(returning: categories) }
    }

    static func waitForRefresh(for baseURL: String) async -> [DiscourseCategory] {
        let key = normalizedBaseURL(baseURL)
        return await withCheckedContinuation { continuation in
            state.lock.lock()
            if state.refreshingBaseURLs.contains(key) {
                state.waitersByBaseURL[key, default: []].append(continuation)
                state.lock.unlock()
            } else {
                let categories = state.categoriesByBaseURL[key].map { Array($0.values) } ?? []
                state.lock.unlock()
                continuation.resume(returning: categories)
            }
        }
    }

    static func resetForTesting() {
        state.lock.lock()
        let waiters = state.waitersByBaseURL.values.flatMap { $0 }
        state.categoriesByBaseURL.removeAll()
        state.refreshingBaseURLs.removeAll()
        state.waitersByBaseURL.removeAll()
        state.lock.unlock()
        waiters.forEach { $0.resume(returning: []) }
    }

    private static func normalizedBaseURL(_ baseURL: String) -> String {
        baseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
