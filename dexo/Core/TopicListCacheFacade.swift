import Foundation

/// Single entry for topic-list disk snapshots used by Home and background sync.
/// Wraps `BackgroundTopicListCache` so call sites stop inventing parallel caches.
enum TopicListCacheFacade {
    static func load(baseURL: String) -> DiscourseTopicList? {
        BackgroundTopicListCache.load(baseURL: baseURL)
    }

    static func save(_ rawData: Data, baseURL: String) {
        BackgroundTopicListCache.save(rawData, baseURL: baseURL)
    }

    static func clear(baseURL: String) {
        BackgroundTopicListCache.clear(baseURL: baseURL)
    }
}
