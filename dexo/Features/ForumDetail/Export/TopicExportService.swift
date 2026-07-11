import Foundation
import UIKit

enum TopicExportFormat: String, Codable, CaseIterable, Equatable {
    case markdown
    case html

    var fileExtension: String { rawValue == "markdown" ? "md" : "html" }

    var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .html: return "HTML"
        }
    }
}

enum TopicExportRange: CaseIterable, Equatable {
    case firstPost
    case loadedPosts

    var title: String {
        switch self {
        case .firstPost:
            return String(localized: "topic.export.first_post", defaultValue: "仅主帖")
        case .loadedPosts:
            return String(localized: "topic.export.loaded_posts", defaultValue: "全部已加载帖子")
        }
    }
}

final class TopicExportService {
    private let baseURL: String
    private let scopeKey: String
    private let directoryURL: URL

    init(baseURL: String, username: String?, directoryURL: URL? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.scopeKey = AccountScopeKey.make(baseURL: baseURL, username: username)
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func export(
        topicId: Int,
        title: String,
        posts: [DiscourseTopicDetail.Post],
        format: TopicExportFormat,
        range: TopicExportRange
    ) throws -> URL {
        let sortedPosts = posts
            .filter { $0.actionCode == nil }
            .sorted { $0.postNumber < $1.postNumber }
        let selectedPosts: [DiscourseTopicDetail.Post]
        switch range {
        case .firstPost:
            selectedPosts = Array(sortedPosts.prefix(1))
        case .loadedPosts:
            selectedPosts = sortedPosts
        }
        guard !selectedPosts.isEmpty else { throw TopicExportError.noPosts }

        let exportsDirectory = directoryURL
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(Self.scopeDirectoryName(scopeKey), isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        let filename = "\(Self.sanitizedFilename(title))-\(topicId)-\(UUID().uuidString.prefix(8)).\(format.fileExtension)"
        let outputURL = exportsDirectory.appendingPathComponent(filename)
        let content: String
        switch format {
        case .markdown:
            content = makeMarkdown(topicId: topicId, title: title, posts: selectedPosts)
        case .html:
            content = makeHTML(topicId: topicId, title: title, posts: selectedPosts)
        }
        try Data(content.utf8).write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func makeMarkdown(
        topicId: Int,
        title: String,
        posts: [DiscourseTopicDetail.Post]
    ) -> String {
        var sections = [
            "# \(title)",
            "",
            "- Source: \(baseURL)/t/\(topicId)",
            "- Exported: \(ISO8601DateFormatter().string(from: Date()))",
        ]
        for post in posts {
            let author = post.name?.isEmpty == false ? "\(post.name!) (@\(post.username))" : "@\(post.username)"
            sections.append(contentsOf: [
                "",
                "## #\(post.postNumber) · \(author)",
                "",
                Self.readableText(from: post.cooked),
            ])
        }
        return sections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func makeHTML(
        topicId: Int,
        title: String,
        posts: [DiscourseTopicDetail.Post]
    ) -> String {
        let postHTML = posts.map { post in
            let author = post.name?.isEmpty == false ? "\(post.name!) (@\(post.username))" : "@\(post.username)"
            return """
            <article class="post" id="post-\(post.postNumber)">
              <header><strong>#\(post.postNumber) · \(Self.htmlEscape(author))</strong><time>\(Self.htmlEscape(post.createdAt))</time></header>
              <div class="cooked">\(post.cooked)</div>
            </article>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(Self.htmlEscape(title))</title>
          <style>
            :root { color-scheme: light dark; }
            body { max-width: 820px; margin: 0 auto; padding: 28px 18px 60px; font: 16px/1.7 -apple-system, BlinkMacSystemFont, sans-serif; color: CanvasText; background: Canvas; }
            h1 { font-size: 28px; line-height: 1.3; }
            .source { color: GrayText; word-break: break-all; }
            .post { margin-top: 22px; padding: 18px; border: 1px solid color-mix(in srgb, CanvasText 16%, transparent); border-radius: 16px; background: color-mix(in srgb, CanvasText 4%, Canvas); }
            header { display: flex; justify-content: space-between; gap: 12px; color: GrayText; font-size: 13px; }
            .cooked { margin-top: 14px; overflow-wrap: anywhere; }
            img, video { max-width: 100%; height: auto; border-radius: 10px; }
            pre { overflow-x: auto; padding: 12px; border-radius: 10px; background: color-mix(in srgb, CanvasText 8%, Canvas); }
            blockquote { margin-left: 0; padding-left: 14px; border-left: 3px solid #0a84ff; color: GrayText; }
          </style>
        </head>
        <body>
          <h1>\(Self.htmlEscape(title))</h1>
          <p class="source"><a href="\(Self.htmlEscape(baseURL))/t/\(topicId)">\(Self.htmlEscape(baseURL))/t/\(topicId)</a></p>
          \(postHTML)
        </body>
        </html>
        """
    }

    private static func readableText(from cooked: String) -> String {
        guard let data = cooked.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else {
            return cooked.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributed.string
            .replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((sanitized.isEmpty ? "topic" : sanitized).prefix(80))
    }

    private static func scopeDirectoryName(_ scopeKey: String) -> String {
        Data(scopeKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum TopicExportError: LocalizedError {
    case noPosts

    var errorDescription: String? {
        String(localized: "topic.export.no_posts", defaultValue: "当前没有可导出的帖子。")
    }
}
