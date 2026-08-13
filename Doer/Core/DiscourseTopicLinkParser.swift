import Foundation
import UIKit

struct DiscourseTopicLinkInfo: Equatable {
    let topicId: Int
    let postNumber: Int?
    let slug: String?
    let normalizedURL: String
}

enum DiscourseTopicLinkParser {
    private static let topicIdOnly = try! NSRegularExpression(
        pattern: #"/t/(\d+)(?:/(\d+))?(?:[/?#]|$)"#,
        options: [.caseInsensitive]
    )
    private static let topicWithSlug = try! NSRegularExpression(
        pattern: #"/t/([^/]+)/(\d+)(?:/(\d+))?"#,
        options: [.caseInsensitive]
    )

    /// Parse first topic link in free text for a given forum base URL host.
    static func firstTopicLink(in text: String, forumBaseURL: String) -> DiscourseTopicLinkInfo? {
        guard let forumHost = host(from: forumBaseURL) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Prefer explicit URLs containing /t/
        let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let detector = urlDetector {
            let matches = detector.matches(in: text, range: full)
            for match in matches {
                guard let url = match.url else { continue }
                if let info = parse(url: url, allowedHost: forumHost) {
                    return info
                }
            }
        }

        // Fallback: raw path-like snippets for same host text
        if let info = parse(pathOrURL: text, allowedHost: forumHost) {
            return info
        }
        return nil
    }

    static func parse(url: URL, allowedHost: String) -> DiscourseTopicLinkInfo? {
        guard let host = url.host?.lowercased() else { return nil }
        guard host == allowedHost || host == "www." + allowedHost || allowedHost == "www." + host else {
            return nil
        }
        return parse(path: url.path, query: url.query, fragment: url.fragment, absoluteString: url.absoluteString)
    }

    static func parse(pathOrURL raw: String, allowedHost: String) -> DiscourseTopicLinkInfo? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("/t/") {
            value = "https://\(allowedHost)" + value
        } else if !value.contains("://") && value.lowercased().contains(allowedHost) {
            value = "https://" + value
        }
        guard let url = URL(string: value), let host = url.host?.lowercased() else { return nil }
        guard host == allowedHost || host == "www." + allowedHost || allowedHost == "www." + host else {
            return nil
        }
        return parse(path: url.path, query: url.query, fragment: url.fragment, absoluteString: url.absoluteString)
    }

    private static func parse(path: String, query: String?, fragment: String?, absoluteString: String) -> DiscourseTopicLinkInfo? {
        let nsPath = path as NSString
        let range = NSRange(location: 0, length: nsPath.length)

        if let match = topicIdOnly.firstMatch(in: path, range: range),
           match.numberOfRanges >= 2,
           let topicRange = Range(match.range(at: 1), in: path),
           let topicId = Int(path[topicRange]), topicId > 0 {
            var postNumber: Int?
            if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound,
               let postRange = Range(match.range(at: 2), in: path) {
                postNumber = Int(path[postRange])
            }
            return DiscourseTopicLinkInfo(
                topicId: topicId,
                postNumber: postNumber,
                slug: nil,
                normalizedURL: normalize(absoluteString)
            )
        }

        if let match = topicWithSlug.firstMatch(in: path, range: range),
           match.numberOfRanges >= 3,
           let slugRange = Range(match.range(at: 1), in: path),
           let topicRange = Range(match.range(at: 2), in: path),
           let topicId = Int(path[topicRange]), topicId > 0 {
            let slug = String(path[slugRange])
            // Avoid treating pure numeric first segment as slug when id-only already failed
            if Int(slug) != nil { return nil }
            var postNumber: Int?
            if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound,
               let postRange = Range(match.range(at: 3), in: path) {
                postNumber = Int(path[postRange])
            }
            return DiscourseTopicLinkInfo(
                topicId: topicId,
                postNumber: postNumber,
                slug: slug == "topic" ? nil : slug,
                normalizedURL: normalize(absoluteString)
            )
        }
        return nil
    }

    static func host(from baseURL: String) -> String? {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: raw), let host = url.host?.lowercased() {
            return host
        }
        if let url = URL(string: "https://\(raw)"), let host = url.host?.lowercased() {
            return host
        }
        return nil
    }

    private static func normalize(_ absolute: String) -> String {
        absolute.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

final class ClipboardTopicLinkService {
    static let shared = ClipboardTopicLinkService()

    private let defaults: UserDefaults
    private let lastHashKey = "clipboard_topic_link_last_prompted_hash"
    private var seenHashes = Set<Int>()
    private let maxSeen = 64

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func check(forumBaseURL: String, enabled: Bool) -> DiscourseTopicLinkInfo? {
        guard enabled else { return nil }
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return nil }
        guard let info = DiscourseTopicLinkParser.firstTopicLink(in: text, forumBaseURL: forumBaseURL) else {
            return nil
        }
        let hash = info.normalizedURL.hashValue
        let last = defaults.object(forKey: lastHashKey) as? Int
        if hash == last || seenHashes.contains(hash) {
            return nil
        }
        return info
    }

    func markPrompted(_ info: DiscourseTopicLinkInfo) {
        let hash = info.normalizedURL.hashValue
        seenHashes.insert(hash)
        if seenHashes.count > maxSeen, let first = seenHashes.first {
            seenHashes.remove(first)
        }
        defaults.set(hash, forKey: lastHashKey)
    }
}

