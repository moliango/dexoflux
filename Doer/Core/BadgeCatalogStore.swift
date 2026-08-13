import Foundation

/// Site-wide badge catalog cache keyed by forum `baseURL`.
/// Used by notification medal chrome (`/badges.json`) so type color / image resolve without per-row fetches.
nonisolated enum BadgeCatalogStore {
    nonisolated(unsafe) private static var cache: [String: [Int: DiscourseBadge]] = [:]
    nonisolated(unsafe) private static var inflight: [String: Task<[Int: DiscourseBadge], Error>] = [:]
    private static let lock = NSLock()

    static func badge(id: Int, baseURL: String) -> DiscourseBadge? {
        let key = normalize(baseURL)
        lock.lock()
        defer { lock.unlock() }
        return cache[key]?[id]
    }

    static func cachedBadges(baseURL: String) -> [Int: DiscourseBadge] {
        let key = normalize(baseURL)
        lock.lock()
        defer { lock.unlock() }
        return cache[key] ?? [:]
    }

    @discardableResult
    static func ensureLoaded(using api: DiscourseAPI) async -> [Int: DiscourseBadge] {
        let key = normalize(api.baseURL)
        if let existing = cachedMap(for: key), !existing.isEmpty {
            return existing
        }
        if let task = inflightTask(for: key) {
            return (try? await task.value) ?? [:]
        }
        let task = Task<[Int: DiscourseBadge], Error> {
            let badges = try await api.fetchAllBadges()
            return Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0) })
        }
        storeInflight(task, for: key)

        do {
            let map = try await task.value
            storeCache(map, for: key)
            return map
        } catch {
            clearInflight(for: key)
            return [:]
        }
    }

    nonisolated private static func cachedMap(for key: String) -> [Int: DiscourseBadge]? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    nonisolated private static func inflightTask(for key: String) -> Task<[Int: DiscourseBadge], Error>? {
        lock.lock(); defer { lock.unlock() }
        return inflight[key]
    }

    nonisolated private static func storeInflight(_ task: Task<[Int: DiscourseBadge], Error>, for key: String) {
        lock.lock(); defer { lock.unlock() }
        inflight[key] = task
    }

    nonisolated private static func storeCache(_ map: [Int: DiscourseBadge], for key: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = map
        inflight[key] = nil
    }

    nonisolated private static func clearInflight(for key: String) {
        lock.lock(); defer { lock.unlock() }
        inflight[key] = nil
    }

    private static func normalize(_ baseURL: String) -> String {
        baseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
