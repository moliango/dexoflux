import Foundation
import UIKit

struct MiniProgramMetadata: Equatable {
    var name: String
    var iconURL: URL?
    var sourceURL: URL
}

enum MiniProgramMetadataParser {
    static func parse(html: String, pageURL: URL) -> MiniProgramMetadata {
        let name = firstMetaContent(in: html, names: [
            #"property\s*=\s*["']og:site_name["']"#,
            #"name\s*=\s*["']application-name["']"#,
            #"property\s*=\s*["']og:title["']"#,
        ]) ?? title(in: html) ?? pageURL.host ?? pageURL.absoluteString

        let iconHref = firstLinkHref(in: html, relContains: "apple-touch-icon")
            ?? firstLinkHref(in: html, relContains: "icon")
            ?? firstMetaContent(in: html, names: [#"property\s*=\s*["']og:image["']"#])

        let iconURL = resolveIconURL(href: iconHref, pageURL: pageURL)
            ?? rootFaviconURL(for: pageURL)

        return MiniProgramMetadata(
            name: clean(name),
            iconURL: iconURL,
            sourceURL: pageURL
        )
    }

    /// Prefer page-relative resolution; for bare filenames (e.g. `favicon.ico`)
    /// fall back to site-root so deep pages still resolve correctly.
    static func resolveIconURL(href: String?, pageURL: URL) -> URL? {
        guard let href, !href.isEmpty else { return nil }
        let candidates: [URL?] = [
            URL(string: href, relativeTo: pageURL)?.absoluteURL,
            // Bare relative path without leading slash often lives at site root.
            href.hasPrefix("http") || href.hasPrefix("/") || href.hasPrefix("data:")
                ? nil
                : rootRelativeURL(path: href, pageURL: pageURL),
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if isRasterIconURL(candidate) {
                return candidate
            }
        }
        return nil
    }

    static func rootFaviconURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let url = components.url, isRasterIconURL(url) else { return nil }
        return url
    }

    static func publicFaviconServiceURL(for pageURL: URL) -> URL? {
        guard let host = pageURL.host, !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/s2/favicons"
        components.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "128"),
        ]
        return components.url
    }

    private static func rootRelativeURL(path: String, pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        components.path = normalized
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func firstMetaContent(in html: String, names: [String]) -> String? {
        for namePattern in names {
            let pattern = #"<meta\b(?=[^>]*"# + namePattern + #")(?=[^>]*content\s*=\s*["']([^"']+)["'])[^>]*>"#
            if let value = firstCapture(in: html, pattern: pattern) {
                return value
            }
        }
        return nil
    }

    private static func firstLinkHref(in html: String, relContains value: String) -> String? {
        let pattern = #"<link\b(?=[^>]*rel\s*=\s*["'][^"']*"# + NSRegularExpression.escapedPattern(for: value) + #"[^"']*["'])(?=[^>]*href\s*=\s*["']([^"']+)["'])[^>]*>"#
        return firstCapture(in: html, pattern: pattern)
    }

    private static func title(in html: String) -> String? {
        firstCapture(in: html, pattern: #"<title[^>]*>(.*?)</title>"#)
    }

    private static func firstCapture(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return clean(String(html[captureRange]))
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isRasterIconURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        guard !path.hasSuffix(".svg") && !path.contains(".svg?") else { return false }
        return true
    }
}

enum MiniProgramLogoFetchError: LocalizedError, Equatable {
    case invalidURL
    case downloadFailed
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "mini_program.logo.invalid_url", defaultValue: "网址无效，无法获取 Logo")
        case .downloadFailed:
            return String(localized: "mini_program.logo.download_failed", defaultValue: "无法从网站获取 Logo，请稍后重试或从相册选择")
        case .invalidImageData:
            return String(localized: "mini_program.logo.invalid_image", defaultValue: "获取到的 Logo 不是有效图片")
        }
    }
}

final class MiniProgramMetadataService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(url: URL) async -> MiniProgramMetadata {
        do {
            let (data, response) = try await session.data(from: url)
            let finalURL = response.url ?? url
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            return MiniProgramMetadataParser.parse(html: html, pageURL: finalURL)
        } catch {
            return MiniProgramMetadata(
                name: url.host ?? url.absoluteString,
                iconURL: MiniProgramMetadataParser.rootFaviconURL(for: url),
                sourceURL: url
            )
        }
    }

    /// Resolve best logo candidates for a page URL and download image bytes.
    /// Tries HTML metadata → root favicon → public favicon service.
    func fetchLogoImageData(for pageURL: URL) async throws -> Data {
        let metadata = await fetch(url: pageURL)
        var candidates: [URL] = []
        if let iconURL = metadata.iconURL {
            candidates.append(iconURL)
        }
        if let root = MiniProgramMetadataParser.rootFaviconURL(for: metadata.sourceURL),
           !candidates.contains(root) {
            candidates.append(root)
        }
        if let service = MiniProgramMetadataParser.publicFaviconServiceURL(for: metadata.sourceURL),
           !candidates.contains(service) {
            candidates.append(service)
        }

        guard !candidates.isEmpty else {
            throw MiniProgramLogoFetchError.downloadFailed
        }

        for candidate in candidates {
            if let data = try? await downloadImageData(from: candidate) {
                return data
            }
        }
        throw MiniProgramLogoFetchError.downloadFailed
    }

    /// Download remote icon and persist as a local mini-program icon file.
    func downloadAndSaveLogo(for pageURL: URL, programID: String) async throws -> String {
        let data = try await fetchLogoImageData(for: pageURL)
        return try MiniProgramIconStore.shared.saveIconData(data, programID: programID)
    }

    private func downloadImageData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MiniProgramLogoFetchError.downloadFailed
        }
        guard data.count >= 32 else {
            throw MiniProgramLogoFetchError.invalidImageData
        }
        // Accept any decodable image (png/jpeg/ico/webp/gif). Reject empty/corrupt payloads.
        guard UIImage(data: data) != nil else {
            // Some favicon.ico files decode poorly on older iOS; still keep raw bytes if MIME looks like an image.
            if let mime = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")?
                .lowercased(),
               mime.contains("image") {
                return data
            }
            throw MiniProgramLogoFetchError.invalidImageData
        }
        // Normalize to PNG for stable local storage when possible.
        if let png = UIImage(data: data)?.pngData(), !png.isEmpty {
            return png
        }
        return data
    }
}
