import CookedHTML
import Foundation
import UIKit

/// Ordered body segments for share-image mixed media layout.
enum ShareImageBodySegment: Equatable {
    case text(String)
    case image(URL)
    case moreImages(Int)
}

enum ShareImageBodyComposer {
    static let maxImages = 6

    static func segments(from cookedHTML: String, baseURL: String) -> [ShareImageBodySegment] {
        let rewritten = PostImageLinkPreprocessor.rewrite(cookedHTML)
        let blocks = CookedHTMLParser.parse(html: rewritten, baseURL: baseURL)
        var imageCount = 0
        var omittedImages = 0
        var raw: [ShareImageBodySegment] = []

        for block in blocks {
            append(block: block, baseURL: baseURL, into: &raw, imageCount: &imageCount, omittedImages: &omittedImages)
        }

        var merged: [ShareImageBodySegment] = []
        for segment in raw {
            switch segment {
            case .text(let text):
                let trimmed = text
                    .replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if case .text(let previous)? = merged.last {
                    merged[merged.count - 1] = .text(previous + "\n\n" + trimmed)
                } else {
                    merged.append(.text(trimmed))
                }
            case .image, .moreImages:
                merged.append(segment)
            }
        }

        if omittedImages > 0 {
            merged.append(.moreImages(omittedImages))
        }
        return merged
    }

    static func imageURLs(in segments: [ShareImageBodySegment]) -> [URL] {
        segments.compactMap { segment in
            if case .image(let url) = segment { return url }
            return nil
        }
    }

    // MARK: - Block walk

    private static func append(
        block: ContentBlock,
        baseURL: String,
        into segments: inout [ShareImageBodySegment],
        imageCount: inout Int,
        omittedImages: inout Int
    ) {
        switch block {
        case .paragraph(let inlines), .heading(_, let inlines):
            append(inlines: inlines, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)

        case .image(let src, _, _, _, let href):
            appendImage(src: href ?? src, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)

        case .blockquote(let blocks), .spoiler(let blocks):
            for child in blocks {
                append(block: child, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)
            }

        case .discourseQuote(let username, _, _, _, _, _, _, let content):
            if let username, !username.isEmpty {
                segments.append(.text("@\(username):"))
            }
            for child in content {
                append(block: child, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)
            }

        case .list(_, let items):
            for (index, item) in items.enumerated() {
                let prefix = "• "
                let text = plainText(item.content)
                if !text.isEmpty {
                    segments.append(.text("\(prefix)\(text)"))
                }
                for child in item.children {
                    append(block: child, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)
                }
                _ = index
            }

        case .codeBlock(_, let code):
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let clipped = trimmed.count > 280 ? String(trimmed.prefix(280)) + "…" : trimmed
                segments.append(.text(clipped))
            }

        case .onebox(_, let title, let description, let imageURL, _, _, _):
            var lines: [String] = []
            if let title, !title.isEmpty { lines.append(title) }
            if let description, !description.isEmpty { lines.append(description) }
            if !lines.isEmpty {
                segments.append(.text(lines.joined(separator: "\n")))
            }
            if let imageURL {
                appendImage(src: imageURL, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)
            }

        case .video(_, let thumbnailURL, let title, _, _, _, _):
            if let title, !title.isEmpty {
                segments.append(.text(title))
            }
            if let thumbnailURL {
                appendImage(src: thumbnailURL, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)
            }

        case .details(let summary, let content):
            let summaryText = plainText(summary)
            if !summaryText.isEmpty {
                segments.append(.text(summaryText))
            }
            for child in content {
                append(block: child, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)
            }

        case .table(let headers, let rows):
            let headerText = headers
                .map { plainText(fromBlocks: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            if !headerText.isEmpty {
                segments.append(.text(headerText))
            }
            for row in rows.prefix(4) {
                let rowText = row
                    .map { plainText(fromBlocks: $0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                if !rowText.isEmpty {
                    segments.append(.text(rowText))
                }
            }

        case .poll(let poll):
            let options = poll.options.map(\.text).filter { !$0.isEmpty }.prefix(6).joined(separator: " / ")
            if !options.isEmpty {
                segments.append(.text(options))
            }

        case .rawHTML(let html):
            let stripped = html
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                segments.append(.text(stripped))
            }

        case .divider:
            break
        }
    }

    private static func append(
        inlines: [InlineNode],
        baseURL: String,
        into segments: inout [ShareImageBodySegment],
        imageCount: inout Int,
        omittedImages: inout Int
    ) {
        var textBuffer = ""
        for node in inlines {
            switch node {
            case .text(let value), .styledText(let value, _), .code(let value):
                textBuffer += value
            case .link(_, let children), .spoiler(let children):
                textBuffer += plainText(children)
            case .mention(let username, _):
                textBuffer += "@\(username)"
            case .mentionGroup(let name, _):
                textBuffer += "@\(name)"
            case .hashtag(let text, _, _):
                textBuffer += "#\(text)"
            case .lineBreak:
                textBuffer += "\n"
            case .image(let src, _, _, _, let isEmoji):
                // Keep emoji shortcodes/text flow; only block-ish content images become image segments.
                if isEmoji {
                    continue
                }
                if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(textBuffer))
                    textBuffer = ""
                }
                appendImage(src: src, baseURL: baseURL, into: &segments, imageCount: &imageCount, omittedImages: &omittedImages)
            }
        }
        if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(textBuffer))
        }
    }

    private static func appendImage(
        src: String,
        baseURL: String,
        into segments: inout [ShareImageBodySegment],
        imageCount: inout Int,
        omittedImages: inout Int
    ) {
        guard let url = resolveURL(src, baseURL: baseURL) else { return }
        if imageCount >= maxImages {
            omittedImages += 1
            return
        }
        imageCount += 1
        segments.append(.image(url))
    }

    private static func plainText(_ inlines: [InlineNode]) -> String {
        var result = ""
        for node in inlines {
            switch node {
            case .text(let value), .styledText(let value, _), .code(let value):
                result += value
            case .link(_, let children), .spoiler(let children):
                result += plainText(children)
            case .mention(let username, _):
                result += "@\(username)"
            case .mentionGroup(let name, _):
                result += "@\(name)"
            case .hashtag(let text, _, _):
                result += "#\(text)"
            case .lineBreak:
                result += "\n"
            case .image:
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainText(fromBlocks blocks: [ContentBlock]) -> String {
        var parts: [String] = []
        for block in blocks {
            switch block {
            case .paragraph(let inlines), .heading(_, let inlines):
                let text = plainText(inlines)
                if !text.isEmpty { parts.append(text) }
            case .rawHTML(let html):
                let stripped = html
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty { parts.append(stripped) }
            default:
                break
            }
        }
        return parts.joined(separator: " ")
    }

    static func resolveURL(_ raw: String, baseURL: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        let normalizedBase = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        return URL(string: trimmed, relativeTo: URL(string: normalizedBase))?.absoluteURL
    }
}
