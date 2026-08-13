import Foundation

enum NotionDuplicateAction {
    case skip
    case overwrite
}

struct NotionDuplicateError: Error {
    let pageId: String
    let pageURL: String
}

struct NotionSyncResult {
    let pageId: String
    let pageURL: String
    let postCount: Int
    let duplicated: Bool
}

enum NotionSyncPhase {
    case convert
    case create
    case append(current: Int, total: Int)
    case done
}

final class NotionSyncService {
    private let config: NotionConfig
    private let token: String
    private let client: NotionClient
    private let baseURL: String

    init(config: NotionConfig, token: String, baseURL: String, client: NotionClient? = nil) {
        self.config = config
        self.token = token
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.client = client ?? NotionClient(token: token)
    }

    func syncTopic(
        topicId: Int,
        title: String,
        posts: [DiscourseTopicDetail.Post],
        scope: NotionSyncScope,
        onDuplicate: NotionDuplicateAction = .skip,
        onProgress: ((NotionSyncPhase) -> Void)? = nil
    ) async throws -> NotionSyncResult {
        guard let databaseId = config.databaseId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !databaseId.isEmpty
        else {
            throw NotionAPIError(message: String(localized: "notion.not_configured", defaultValue: "请先配置 Notion"), statusCode: nil)
        }

        let export = TopicExportService(baseURL: baseURL, username: nil)
        let markdown = export.markdownString(
            topicId: topicId,
            title: title,
            posts: posts,
            range: scope.exportRange
        )
        let selectedCount: Int = {
            let sorted = posts.filter { $0.actionCode == nil }.sorted { $0.postNumber < $1.postNumber }
            switch scope {
            case .firstPostOnly: return min(1, sorted.count)
            case .allPosts: return sorted.count
            }
        }()
        guard selectedCount > 0 else {
            throw NotionAPIError(message: String(localized: "topic.export.no_posts", defaultValue: "没有可同步的帖子"), statusCode: nil)
        }

        onProgress?(.convert)
        let blocks = NotionMarkdownConverter.blocks(from: markdown)
        let chunks = NotionMarkdownConverter.chunked(blocks)

        if let existing = try await client.queryPage(databaseId: databaseId, topicId: topicId) {
            switch onDuplicate {
            case .skip:
                return NotionSyncResult(
                    pageId: existing,
                    pageURL: pageURL(from: existing),
                    postCount: selectedCount,
                    duplicated: true
                )
            case .overwrite:
                try await client.archivePage(id: existing)
            }
        }

        onProgress?(.create)
        let firstAuthor = posts.first(where: { $0.actionCode == nil })
        let author: String = {
            guard let post = firstAuthor else { return "" }
            if let name = post.name, !name.isEmpty { return "\(name) (@\(post.username))" }
            return "@\(post.username)"
        }()
        let properties = buildProperties(
            title: title,
            topicId: topicId,
            url: "\(baseURL)/t/\(topicId)",
            author: author,
            createdAt: firstAuthor?.createdAt
        )
        let firstChunk = chunks.first ?? []
        let page = try await client.createPage(
            databaseId: databaseId,
            properties: properties,
            children: firstChunk
        )
        guard let pageId = page["id"] as? String else {
            throw NotionAPIError(message: "Notion create page missing id", statusCode: nil)
        }

        if chunks.count > 1 {
            for (idx, chunk) in chunks.dropFirst().enumerated() {
                onProgress?(.append(current: idx + 1, total: chunks.count - 1))
                try await client.appendChildren(blockId: pageId, children: chunk)
                try await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        onProgress?(.done)
        let url = (page["url"] as? String) ?? pageURL(from: pageId)
        return NotionSyncResult(pageId: pageId, pageURL: url, postCount: selectedCount, duplicated: false)
    }

    func testConnection() async throws -> String {
        guard let databaseId = config.databaseId, !databaseId.isEmpty else {
            throw NotionAPIError(message: "Database ID empty", statusCode: nil)
        }
        let db = try await client.retrieveDatabase(id: databaseId)
        return Self.databaseTitle(from: db) ?? "Database"
    }

    func createTemplateDatabase(parentPageId: String) async throws -> String {
        let cleaned = Self.normalizeNotionID(parentPageId)
        let db = try await client.createDatabaseForExport(
            parentPageId: cleaned,
            title: "Doer Topics"
        )
        guard let id = db["id"] as? String else {
            throw NotionAPIError(message: "create database missing id", statusCode: nil)
        }
        return id.replacingOccurrences(of: "-", with: "")
    }

    static func databaseTitle(from db: [String: Any]) -> String? {
        guard let titleArr = db["title"] as? [[String: Any]] else { return nil }
        var parts: [String] = []
        for item in titleArr {
            if let plain = item["plain_text"] as? String {
                parts.append(plain)
            } else if let text = item["text"] as? [String: Any],
                      let content = text["content"] as? String {
                parts.append(content)
            }
        }
        let joined = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    static func normalizeNotionID(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let host = url.host?.lowercased(), host.contains("notion") {
            // last path component often contains 32-hex id, possibly with dashes
            let last = url.path.split(separator: "/").last.map(String.init) ?? value
            value = last
            if let range = value.range(of: #"[0-9a-fA-F]{32}"#, options: .regularExpression) {
                value = String(value[range])
            } else if let range = value.range(of: #"[0-9a-fA-F-]{36}"#, options: .regularExpression) {
                value = String(value[range])
            }
        }
        return value.replacingOccurrences(of: "-", with: "")
    }

    private func buildProperties(
        title: String,
        topicId: Int,
        url: String,
        author: String,
        createdAt: String?
    ) -> [String: Any] {
        var props: [String: Any] = [
            "Name": [
                "title": [[
                    "type": "text",
                    "text": ["content": String(title.prefix(200))],
                ]]
            ],
            "URL": ["url": url],
            "Topic ID": ["number": topicId],
            "Synced": ["date": ["start": ISO8601DateFormatter().string(from: Date())]],
        ]
        if !author.isEmpty {
            props["Author"] = [
                "rich_text": [[
                    "type": "text",
                    "text": ["content": String(author.prefix(200))],
                ]]
            ]
        }
        if let createdAt, !createdAt.isEmpty {
            props["Created"] = ["date": ["start": createdAt]]
        }
        return props
    }

    private func pageURL(from id: String) -> String {
        let compact = id.replacingOccurrences(of: "-", with: "")
        return "https://www.notion.so/\(compact)"
    }
}
