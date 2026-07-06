import CryptoKit
import Foundation

enum EmojiStore {
    private static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EmojiCacheV2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let aliasToName: [String: String] = {
        guard let url = Bundle.main.url(forResource: "aliases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        var result: [String: String] = [:]
        for (name, aliases) in map {
            for alias in aliases {
                result[alias] = name
            }
        }
        return result
    }()

    // Built once after load/fetch; queried per cell
    private(set) static var lookupMap: [String: String] = [:]

    static func load(for baseURL: String) -> Bool {
        let file = cacheFile(for: baseURL)
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([DiscourseEmojiEntry].self, from: data)
        else { return false }
        buildLookup(from: entries, baseURL: baseURL)
        return true
    }

    static func save(_ entries: [DiscourseEmojiEntry], for baseURL: String) {
        buildLookup(from: entries, baseURL: baseURL)
        let file = cacheFile(for: baseURL)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func url(for code: String) -> String? {
        let name = aliasToName[code] ?? code
        return lookupMap[name]
    }

    static func lookup(for code: String) -> String? {
        return lookupMap[code]
    }

    private static func buildLookup(from entries: [DiscourseEmojiEntry], baseURL: String) {
        var map: [String: String] = [:]
        for entry in entries {
            let url = entry.url.hasPrefix("http") ? entry.url : baseURL + entry.url
            map[entry.name] = url
        }
        lookupMap = map
    }

    private static func cacheFile(for baseURL: String) -> URL {
        let hash = SHA256.hash(data: Data(baseURL.utf8))
        let prefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(prefix).json")
    }
}
