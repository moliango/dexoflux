import Foundation

/// Site-wide badge catalog cache keyed by forum `baseURL`.
/// Used by notification medal chrome (`/badges.json`) so type color / image resolve without per-row fetches.
enum BadgeCatalogStore {
    private static var cache: [String: [Int: DiscourseBadge]] = [:]
    private static var inflight: [String: Task<[Int: DiscourseBadge], Error>] = [:]
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
        lock.lock()
        if let existing = cache[key], !existing.isEmpty {
            lock.unlock()
            return existing
        }
        if let task = inflight[key] {
            lock.unlock()
            return (try? await task.value) ?? [:]
        }
        let task = Task<[Int: DiscourseBadge], Error> {
            let badges = try await api.fetchAllBadges()
            return Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0) })
        }
        inflight[key] = task
        lock.unlock()

        do {
            let map = try await task.value
            lock.lock()
            cache[key] = map
            inflight[key] = nil
            lock.unlock()
            return map
        } catch {
            lock.lock()
            inflight[key] = nil
            lock.unlock()
            return [:]
        }
    }

    private static func normalize(_ baseURL: String) -> String {
        baseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
