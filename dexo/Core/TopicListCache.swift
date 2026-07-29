import Foundation

final class TopicListCache {
    private let cache = NSCache<NSString, NSArray>()
    private let userDefaults = UserDefaults.standard
    private let maxCacheAge: TimeInterval = 300 // 5分钟
    
    func getCachedTopics(for key: String) -> [DiscourseTopicList.Topic]? {
        let cacheKey = "\(key)_topics" as NSString
        let lastUpdate = userDefaults.double(forKey: "\(key)_timestamp")
        
        if let cached = cache.object(forKey: cacheKey) as? [DiscourseTopicList.Topic],
           Date().timeIntervalSince1970 - lastUpdate < maxCacheAge {
            return cached
        }
        return nil
    }
    
    func saveCachedTopics(_ topics: [DiscourseTopicList.Topic], for key: String) {
        cache.setObject(topics as NSArray, forKey: "\(key)_topics" as NSString)
        userDefaults.set(Date().timeIntervalSince1970, forKey: "\(key)_timestamp")
    }
}
