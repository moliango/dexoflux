import CryptoKit
import Foundation

enum EmojiStore {
    static let didUpdateNotification = Notification.Name("EmojiStore.didUpdate")

    private static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EmojiCacheV2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let aliasCatalog: (aliasToName: [String: String], knownNames: Set<String>) = {
        guard let url = Bundle.main.url(forResource: "aliases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return ([:], []) }
        var aliasToName: [String: String] = [:]
        var knownNames = Set<String>()
        for (name, aliases) in map {
            knownNames.insert(name)
            for alias in aliases {
                aliasToName[alias] = name
                knownNames.insert(alias)
            }
        }
        return (aliasToName, knownNames)
    }()

    private static var aliasToName: [String: String] { aliasCatalog.aliasToName }
    private static var knownStandardNames: Set<String> { aliasCatalog.knownNames }

    // Built once after load/fetch; queried per cell
    private(set) static var lookupMap: [String: String] = [:]

    static func load(for baseURL: String) -> Bool {
        guard let entries = cachedEntries(for: baseURL) else { return false }
        buildLookup(from: entries, baseURL: baseURL)
        NotificationCenter.default.post(name: didUpdateNotification, object: nil)
        return true
    }

    static func cachedEntries(for baseURL: String) -> [DiscourseEmojiEntry]? {
        let file = cacheFile(for: baseURL)
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([DiscourseEmojiEntry].self, from: data)
        else { return nil }
        return entries
    }

    static func save(_ entries: [DiscourseEmojiEntry], for baseURL: String) {
        buildLookup(from: entries, baseURL: baseURL)
        let file = cacheFile(for: baseURL)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
        NotificationCenter.default.post(name: didUpdateNotification, object: nil)
    }

    static func url(for code: String) -> String? {
        resolvedURLString(for: code, baseURL: nil)
    }

    static func lookup(for code: String) -> String? {
        resolvedURLString(for: code, baseURL: nil, allowDeterministicFallback: false)
    }

    /// Resolve emoji image URL.
    /// Prefers cached `/emojis.json` entries (custom + standard), then deterministic
    /// Discourse standard path when `baseURL` is available (FluxDO parity).
    static func resolvedURLString(
        for code: String,
        baseURL: String?,
        allowDeterministicFallback: Bool = true
    ) -> String? {
        let normalizedCode = normalizedEmojiCode(code)
        if let url = lookupMap[normalizedCode] {
            return url
        }
        let canonicalName = aliasToName[normalizedCode] ?? normalizedCode
        if let url = lookupMap[canonicalName] {
            return url
        }

        guard allowDeterministicFallback,
              let baseURL,
              !baseURL.isEmpty,
              !canonicalName.isEmpty
        else {
            return nil
        }

        // FluxDo parity: always synthesize `/images/emoji/twitter/{name}.png`.
        // Custom/site emojis are already covered by lookupMap above. Unknown names
        // may 404, but shortcodes must never remain stuck as English text.
        return standardEmojiURLString(for: canonicalName, baseURL: baseURL)
    }

    private static func standardEmojiURLString(for name: String, baseURL: String) -> String {
        // Discourse skin-tone shortcodes: name:t2
        if let toneMatch = name.range(of: #":t([1-6])$"#, options: .regularExpression) {
            let baseName = String(name[..<toneMatch.lowerBound])
            let tone = String(name[toneMatch]).replacingOccurrences(of: ":", with: "")
            return resolvedEmojiURL("/images/emoji/twitter/\(baseName)/\(tone).png?v=12", baseURL: baseURL)
        }
        return resolvedEmojiURL("/images/emoji/twitter/\(name).png?v=12", baseURL: baseURL)
    }

    static func clearCache() {
        lookupMap = [:]
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static func cacheSize() -> Int64 {
        directorySize(at: cacheDirectory)
    }

    private static func buildLookup(from entries: [DiscourseEmojiEntry], baseURL: String) {
        var map: [String: String] = [:]
        for entry in entries {
            let url = resolvedEmojiURL(entry.url, baseURL: baseURL)
            map[normalizedEmojiCode(entry.name)] = url
            for alias in entry.searchAliases ?? [] {
                map[normalizedEmojiCode(alias)] = url
            }
        }
        lookupMap = map
    }

    private static func normalizedEmojiCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .replacingOccurrences(of: ":t\\d$", with: "", options: .regularExpression)
    }

    private static func resolvedEmojiURL(_ rawURL: String, baseURL: String) -> String {
        if rawURL.hasPrefix("http") {
            return rawURL
        }
        if rawURL.hasPrefix("//") {
            return "https:\(rawURL)"
        }
        let normalizedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        guard let base = URL(string: normalizedBase),
              let url = URL(string: rawURL, relativeTo: base)?.absoluteURL
        else {
            return baseURL + rawURL
        }
        return url.absoluteString
    }

    private static func cacheFile(for baseURL: String) -> URL {
        let hash = SHA256.hash(data: Data(baseURL.utf8))
        let prefix = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(prefix).json")
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
