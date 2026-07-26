import Foundation

struct NotionAPIError: LocalizedError {
    let message: String
    let statusCode: Int?
    var errorDescription: String? { message }
}

final class NotionClient {
    private let token: String
    private let session: URLSession
    private let notionVersion = "2022-06-28"
    private let baseURL = URL(string: "https://api.notion.com/v1/")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func retrieveDatabase(id: String) async throws -> [String: Any] {
        try await request(method: "GET", path: "databases/\(id)")
    }

    func queryPage(databaseId: String, topicId: Int) async throws -> String? {
        let body: [String: Any] = [
            "filter": [
                "and": [
                    ["property": "Topic ID", "number": ["equals": topicId]],
                    [
                        "or": [
                            ["property": "Post ID", "number": ["is_empty": true]],
                            ["property": "Post ID", "number": ["equals": 0]],
                        ]
                    ],
                ]
            ],
            "page_size": 1,
        ]
        let res = try await request(method: "POST", path: "databases/\(databaseId)/query", json: body)
        let results = res["results"] as? [[String: Any]] ?? []
        return results.first?["id"] as? String
    }

    func createPage(databaseId: String, properties: [String: Any], children: [[String: Any]]) async throws -> [String: Any] {
        var body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": properties,
        ]
        if !children.isEmpty {
            body["children"] = Array(children.prefix(100))
        }
        return try await request(method: "POST", path: "pages", json: body)
    }

    func appendChildren(blockId: String, children: [[String: Any]]) async throws {
        _ = try await request(
            method: "PATCH",
            path: "blocks/\(blockId)/children",
            json: ["children": children]
        )
    }

    func archivePage(id: String) async throws {
        _ = try await request(method: "PATCH", path: "pages/\(id)", json: ["archived": true])
    }

    func createDatabaseForExport(parentPageId: String, title: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": parentPageId],
            "title": [[
                "type": "text",
                "text": ["content": title],
            ]],
            "properties": [
                "Name": ["title": [:]],
                "URL": ["url": [:]],
                "Topic ID": ["number": [:]],
                "Post ID": ["number": [:]],
                "Author": ["rich_text": [:]],
                "Created": ["date": [:]],
                "Synced": ["date": [:]],
            ],
        ]
        return try await request(method: "POST", path: "databases", json: body)
    }

    func ensureNumberProperty(databaseId: String, propertyName: String) async throws {
        let db = try await retrieveDatabase(id: databaseId)
        let props = db["properties"] as? [String: Any] ?? [:]
        if props[propertyName] != nil { return }
        _ = try await request(
            method: "PATCH",
            path: "databases/\(databaseId)",
            json: ["properties": [propertyName: ["number": [:]]]]
        )
    }

    private func request(method: String, path: String, json: [String: Any]? = nil) async throws -> [String: Any] {
        // Build path manually; appendingPathComponent mangles nested segments.
        let full = URL(string: "https://api.notion.com/v1/" + path)!
        var req = URLRequest(url: full)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 429, attempt < 4 {
                let retry = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? Double(attempt)
                try await Task.sleep(nanoseconds: UInt64(max(retry, 0.35) * 1_000_000_000))
                continue
            }
            guard (200...299).contains(status) else {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                    ?? String(data: data, encoding: .utf8)
                    ?? "Notion API error"
                throw NotionAPIError(message: message, statusCode: status)
            }
            if data.isEmpty { return [:] }
            let obj = try JSONSerialization.jsonObject(with: data)
            return obj as? [String: Any] ?? [:]
        }
    }
}
