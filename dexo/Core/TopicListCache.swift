import Foundation
import Combine

final class TopicListCache {
    private let cache = NSCache<NSString, NSArray>()
    private let userDefaults = UserDefaults.standard
    private let maxCacheAge: TimeInterval = 300 // 5分钟
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
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
    
    // Full spec implementation for users/categories isolation
    func getCachedData(for key: String) -> (topics: [DiscourseTopicList.Topic], users: [DiscourseTopicList.User], categories: [DiscourseCategory])? {
        let cacheKey = "\(key)_data" as NSString
        let lastUpdate = userDefaults.double(forKey: "\(key)_timestamp")
        
        if let cached = cache.object(forKey: cacheKey) as? [DiscourseTopicList.Topic, [DiscourseTopicList.User], [DiscourseCategory]],
           Date().timeIntervalSince1970 - lastUpdate < maxCacheAge {
            return cached
        }
        return nil
    }
    
    func saveCachedData(_ data: (topics: [DiscourseTopicList.Topic], users: [DiscourseTopicList.User], categories: [DiscourseCategory]), for key: String) {
        cache.setObject(data as NSArray, forKey: "\(key)_data" as NSString)
        userDefaults.set(Date().timeIntervalSince1970, forKey: "\(key)_timestamp")
    }
    
    func invalidateCache(for key: String) {
        let cacheKey = "\(key)_data" as NSString
        cache.removeObject(forKey: cacheKey)
        userDefaults.removeObject(forKey: "\(key)_timestamp")
    }
}
