import Foundation
import SwiftSoup

/// Extracts Discourse quote blocks (`aside.quote`).
enum QuoteExtractor {
    static func extract(from element: Element, options: ParseOptions) -> ContentBlock {
        let username = try? element.attr("data-username")
        let effectiveUsername = (username?.isEmpty ?? true) ? nil : username
        let quotePostNumber = firstInteger(
            in: [
                try? element.attr("data-post"),
                try? element.attr("data-post-number"),
                try? element.attr("data-post-number-id"),
            ]
        )
        let quoteTopicId = firstInteger(in: [try? element.attr("data-topic")])

        // Avatar URL from the img inside .title
        let avatarURL: String? = {
            guard let img = try? element.select(".title img").first() else { return nil }
            let src = (try? img.attr("src")) ?? ""
            return src.isEmpty ? nil : URLResolver.resolve(src, baseURL: options.baseURL)
        }()

        // Topic title + URL from .quote-title__text-content > a
        var topicTitle: String?
        var topicURL: String?
        if let titleContent = try? element.select(".quote-title__text-content").first() {
            // First <a> that is not the category badge is the topic link
            if let links = try? titleContent.select("a") {
                for link in links {
                    let cls = (try? link.attr("class")) ?? ""
                    if cls.contains("badge-category") { continue }
                    let text = (try? link.text()) ?? ""
                    let href = (try? link.attr("href")) ?? ""
                    if !text.isEmpty {
                        topicTitle = text
                        topicURL = href.isEmpty ? nil : URLResolver.resolve(href, baseURL: options.baseURL)
                        break
                    }
                }
            }
        }
        if topicURL == nil, let titleLink = firstTopicLink(in: element) {
            topicTitle = titleLink.title
            topicURL = URLResolver.resolve(titleLink.href, baseURL: options.baseURL)
        }
        if topicURL == nil, let quoteTopicId {
            let postPath = quotePostNumber.map { "/\($0)" } ?? ""
            topicURL = URLResolver.resolve("/t/\(quoteTopicId)\(postPath)", baseURL: options.baseURL)
        }

        // Category name + URL from .badge-category__wrapper
        var categoryName: String?
        var categoryURL: String?
        if let badge = try? element.select("a.badge-category__wrapper").first() {
            let href = (try? badge.attr("href")) ?? ""
            if !href.isEmpty {
                categoryURL = URLResolver.resolve(href, baseURL: options.baseURL)
            }
            if let nameSpan = try? badge.select(".badge-category__name").first() {
                let name = (try? nameSpan.text()) ?? ""
                if !name.isEmpty { categoryName = name }
            }
        }

        // Content comes from the blockquote inside the aside
        let contentBlocks: [ContentBlock]
        if let blockquote = try? element.select("blockquote").first() {
            contentBlocks = BlockExtractor.extract(from: blockquote, options: options)
        } else {
            contentBlocks = BlockExtractor.extract(from: element, options: options)
        }

        return .discourseQuote(
            username: effectiveUsername,
            avatarURL: avatarURL,
            topicTitle: topicTitle,
            topicURL: topicURL,
            categoryName: categoryName,
            categoryURL: categoryURL,
            quotePostNumber: quotePostNumber,
            content: contentBlocks
        )
    }

    private static func firstInteger(in values: [String?]) -> Int? {
        for value in values {
            guard let value, !value.isEmpty else { continue }
            if let integer = Int(value) {
                return integer
            }
        }
        return nil
    }

    private static func firstTopicLink(in element: Element) -> (title: String?, href: String)? {
        guard let links = try? element.select(".title a[href]") else { return nil }
        for link in links {
            let cls = (try? link.attr("class")) ?? ""
            if cls.contains("badge-category") { continue }
            let href = (try? link.attr("href")) ?? ""
            guard !href.isEmpty else { continue }
            let text = (try? link.text()) ?? ""
            return (text.isEmpty ? nil : text, href)
        }
        return nil
    }
}
