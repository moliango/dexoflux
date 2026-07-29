import Foundation

enum ForumInternalLinkDestination {
    case topic(id: Int, postNumber: Int?)
    case category(slug: String, id: Int)
    case tag(name: String)
}

enum ForumInternalLinkParser {
    static func normalizedURL(from url: URL, baseURL: String) -> URL {
        if url.scheme == nil, url.absoluteString.hasPrefix("//") {
            return URL(string: "https:\(url.absoluteString)") ?? url
        }

        guard url.host == nil, url.scheme == nil,
              let base = URL(string: baseURL)
        else {
            return url
        }

        return URL(string: url.absoluteString, relativeTo: base)?.absoluteURL ?? url
    }

    static func isInternalURL(_ url: URL, baseURL: String) -> Bool {
        guard let baseHost = URL(string: baseURL)?.host,
              let linkHost = url.host
        else { return false }

        return normalizedHost(baseHost) == normalizedHost(linkHost)
    }

    static func destination(for url: URL) -> ForumInternalLinkDestination? {
        if let topic = parseTopicInfo(from: url) {
            return .topic(id: topic.id, postNumber: topic.postNumber)
        }
        if let (slug, categoryId) = parseCategoryInfo(from: url) {
            return .category(slug: slug, id: categoryId)
        }
        if let tagName = parseTagName(from: url) {
            return .tag(name: tagName)
        }
        return nil
    }

    private static func normalizedHost(_ host: String) -> String {
        var value = host.lowercased()
        while value.hasSuffix(".") {
            value.removeLast()
        }
        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }
        return value
    }

    private static func parseTopicInfo(from url: URL) -> (id: Int, postNumber: Int?)? {
        let components = url.pathComponents
        guard let tIndex = components.firstIndex(of: "t") else { return nil }
        var numbers: [Int] = []
        for component in components.dropFirst(tIndex + 1) {
            let cleaned = component.replacingOccurrences(of: ".json", with: "")
            if let id = Int(cleaned) {
                numbers.append(id)
            }
        }
        guard let topicId = numbers.first else { return nil }
        return (topicId, numbers.dropFirst().first)
    }

    private static func parseCategoryInfo(from url: URL) -> (slug: String, id: Int)? {
        let components = url.pathComponents
        guard let cIndex = components.firstIndex(of: "c"),
              cIndex + 2 < components.count else { return nil }
        let remaining = Array(components[(cIndex + 1)...])
        for i in remaining.indices.reversed() {
            let cleaned = remaining[i].replacingOccurrences(of: ".json", with: "")
            if let id = Int(cleaned), i > 0 {
                return (remaining[i - 1], id)
            }
        }
        return nil
    }

    private static func parseTagName(from url: URL) -> String? {
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(where: { $0 == "tag" || $0 == "tags" }),
              tagIndex + 1 < components.count
        else { return nil }
        return components[tagIndex + 1].removingPercentEncoding ?? components[tagIndex + 1]
    }
}

enum ForumAttachmentLinkParser {
    private static let mediaExtensions: Set<String> = [
        "apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "mov", "mp3", "mp4", "mpeg", "ogg", "png", "svg",
        "wav", "webm", "webp",
    ]

    private static let fileExtensions: Set<String> = [
        "7z", "apk", "bz2", "c", "conf", "cpp", "csv", "dart", "db", "diff", "dmg", "doc", "docx", "gz",
        "h", "hpp", "html", "ipa", "java", "js", "json", "key", "kt", "log", "md", "msi", "numbers", "otf",
        "pages", "patch", "pdf", "php", "pkg", "ppt", "pptx", "py", "rar", "rb", "rs", "sh", "sql", "sqlite",
        "swift", "tar", "toml", "ts", "ttf", "txt", "woff", "woff2", "xls", "xlsx", "xml", "xz", "yaml", "yml",
        "zip",
    ]

    static func isAttachmentURL(_ url: URL) -> Bool {
        let path = url.path.removingPercentEncoding?.lowercased() ?? url.path.lowercased()
        let ext = url.pathExtension.lowercased()

        if mediaExtensions.contains(ext) {
            return false
        }

        if fileExtensions.contains(ext) {
            return true
        }

        if path.contains("/uploads/") || path.contains("/secure-uploads/") {
            return true
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return queryItems.contains { item in
            let name = item.name.lowercased()
            if name == "download" { return true }
            if name == "dl", item.value == "1" { return true }
            return false
        }
    }
}

enum ForumAttachmentDownloadError: LocalizedError {
    case invalidFile
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return String(localized: "attachment.download_failed")
        case let .httpStatus(statusCode):
            return "\(String(localized: "attachment.download_failed")) (\(statusCode))"
        }
    }
}

enum ForumAttachmentDownloader {
    static func download(url: URL, baseURL: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let userAgent = WebCookieStore.shared.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        if let proxy = LightweightDohProxyService.shared.connectionProxyDictionary(for: proxyBaseURL(for: url, fallback: baseURL)) {
            config.connectionProxyDictionary = proxy
        }

        let session = URLSession(configuration: config)
        defer {
            session.finishTasksAndInvalidate()
        }

        let (temporaryURL, response) = try await session.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw ForumAttachmentDownloadError.httpStatus(httpResponse.statusCode)
        }

        let filename = sanitizedFilename(response.suggestedFilename, fallbackURL: url)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DexoAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        return destination
    }

    static func cleanupDownloadedFile(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
    }

    private static func proxyBaseURL(for url: URL, fallback: String) -> String {
        guard let scheme = url.scheme, let host = url.host else {
            return fallback
        }
        return "\(scheme)://\(host)"
    }

    private static func sanitizedFilename(_ suggestedName: String?, fallbackURL: URL) -> String {
        let fallback = fallbackURL.lastPathComponent.removingPercentEncoding
        let rawName = [suggestedName, fallback, "attachment"]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "attachment"

        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let clean = rawName.components(separatedBy: forbidden).joined(separator: "_")
        return clean.isEmpty ? "attachment" : clean
    }
}
