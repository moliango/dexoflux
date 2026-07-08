import Foundation
import SwiftSoup

/// Extracts a `[ContentBlock]` array from the children of a DOM element.
enum BlockExtractor {
    /// Tags treated as block-level elements.
    private static let blockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "pre", "blockquote", "aside",
        "ul", "ol",
        "table",
        "details",
        "hr",
        "div", "figure",
    ]

    /// Extract content blocks from a parent element's children.
    static func extract(from parent: Element, options: ParseOptions) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        for child in parent.getChildNodes() {
            blocks.append(contentsOf: extractNode(child, options: options))
        }
        return mergeInlineImageBlocks(blocks).compactMap { trimBlock($0) }
    }

    /// Extract annotated blocks (block + source HTML) from a parent element's children.
    static func extractAnnotated(from parent: Element, options: ParseOptions) -> [AnnotatedBlock] {
        var raw: [AnnotatedBlock] = []
        for child in parent.getChildNodes() {
            let blocks = extractNode(child, options: options).compactMap { trimBlock($0) }
            guard !blocks.isEmpty else { continue }
            let sourceHTML: String
            if let element = child as? Element {
                sourceHTML = (try? element.outerHtml()) ?? ""
            } else if let textNode = child as? TextNode {
                sourceHTML = textNode.getWholeText()
            } else {
                sourceHTML = ""
            }
            for block in blocks {
                raw.append(AnnotatedBlock(block: block, sourceHTML: sourceHTML))
            }
        }
        // Apply the same inline-image merging as extract(), preserving sourceHTML by
        // concatenating the HTML of merged siblings.
        guard raw.count > 1 else { return raw }
        var result: [AnnotatedBlock] = []
        for annotated in raw {
            guard let lastIndex = result.indices.last else {
                result.append(annotated)
                continue
            }
            let prev = result[lastIndex]
            // Case 1: small image → inline emoji in preceding paragraph
            if case .image(let src, let alt, let w, let h, _) = annotated.block,
               let w, let h, w <= 80, h <= 80,
               case .paragraph(let inlines) = prev.block
            {
                let merged = ContentBlock.paragraph(inlines + [.image(src: src, alt: alt, width: w, height: h, isEmoji: true)])
                result[lastIndex] = AnnotatedBlock(block: merged, sourceHTML: prev.sourceHTML + annotated.sourceHTML)
                continue
            }
            // Case 2: paragraph following a paragraph that ends with inline emoji → merge
            if case .paragraph(let newInlines) = annotated.block,
               case .paragraph(let prevInlines) = prev.block,
               case .image(_, _, _, _, let isEmoji) = prevInlines.last, isEmoji
            {
                let merged = ContentBlock.paragraph(prevInlines + newInlines)
                result[lastIndex] = AnnotatedBlock(block: merged, sourceHTML: prev.sourceHTML + annotated.sourceHTML)
                continue
            }
            result.append(annotated)
        }
        return result
    }

    /// Extract content blocks from a single DOM node.
    private static func extractNode(_ node: Node, options: ParseOptions) -> [ContentBlock] {
        if let textNode = node as? TextNode {
            let raw = textNode.getWholeText()
            // Trim leading whitespace/newlines but preserve meaningful trailing spaces
            // (they serve as word separators when adjacent inline elements are merged).
            let text = raw.replacingOccurrences(of: "^[\\s]+", with: "", options: .regularExpression)
            if text.isEmpty { return [] }
            return [.paragraph([.text(text)])]
        }

        guard let element = node as? Element else { return [] }
        let tagName = element.tagName().lowercased()

        switch tagName {
        case "p":
            return extractParagraph(from: element, options: options)

        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tagName.last!))!
            let inlines = InlineExtractor.extract(from: element, options: options)
            if inlines.isEmpty { return [] }
            return [.heading(level: level, content: inlines)]

        case "pre":
            return extractCodeBlock(from: element)

        case "blockquote":
            let inner = extract(from: element, options: options)
            if inner.isEmpty { return [] }
            return [.blockquote(blocks: inner)]

        case "aside":
            return extractAside(from: element, options: options)

        case "ul":
            return [ListExtractor.extract(from: element, ordered: false, options: options)]

        case "ol":
            return [ListExtractor.extract(from: element, ordered: true, options: options)]

        case "table":
            return [TableExtractor.extract(from: element, options: options)]

        case "details":
            return extractDetails(from: element, options: options)

        case "br":
            // Bare <br> at block level is a DOM artifact from SwiftSoup splitting block-in-inline;
            // ignore it rather than emitting a lineBreak paragraph.
            return []

        case "hr":
            return [.divider]

        case "img":
            return extractBlockImage(from: element, options: options)

        case "div", "figure", "section", "article":
            // Check for specific div patterns first, otherwise recurse
            return extractDiv(from: element, options: options)

        default:
            // Unknown block-level or inline elements at top level
            if isBlockElement(element) {
                return extract(from: element, options: options)
            }
            // Inline spoiler at block level (e.g. <span class="spoiler"> wrapping block children in a <td>)
            let classAttr = (try? element.attr("class")) ?? ""
            if classAttr.contains("spoiler") {
                let inner = extract(from: element, options: options)
                if inner.isEmpty { return [] }
                return [.spoiler(blocks: inner)]
            }
            // Inline element at block level — extract as inline node preserving tag semantics (bold, link, etc.)
            let inlines = InlineExtractor.extractNode(element, options: options)
            if inlines.isEmpty { return [] }
            return [.paragraph(inlines)]
        }
    }

    // MARK: - Specific extractors

    private static func extractParagraph(from element: Element, options: ParseOptions) -> [ContentBlock] {
        // Check if paragraph only contains a single image
        let children = element.children()
        if children.size() == 1,
           let onlyChild = children.first(),
           element.textNodes().allSatisfy({ $0.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        {
            let childTag = onlyChild.tagName().lowercased()

            // <p><img></p>
            if childTag == "img" {
                return extractBlockImage(from: onlyChild, options: options)
            }

            // <p><a><img></a></p>
            if childTag == "a",
               onlyChild.children().size() == 1,
               let innerImg = onlyChild.children().first(),
               innerImg.tagName().lowercased() == "img"
            {
                let href = URLResolver.resolve((try? onlyChild.attr("href")) ?? "", baseURL: options.baseURL)
                return extractBlockImage(from: innerImg, options: options, href: href.isEmpty ? nil : href)
            }

            // <p><div class="lightbox-wrapper">...</div></p>
            if childTag == "div" || childTag == "figure" {
                return extractDiv(from: onlyChild, options: options)
            }
        }

        let inlines = InlineExtractor.extract(from: element, options: options)
        if inlines.isEmpty { return [] }
        return [.paragraph(inlines)]
    }

    private static func extractCodeBlock(from element: Element) -> [ContentBlock] {
        let codeElement = element.children().first { $0.tagName().lowercased() == "code" }
            ?? element

        let language: String? = {
            guard let cls = try? codeElement.attr("class"), !cls.isEmpty else { return nil }
            // Discourse uses class="lang-xxx" or "language-xxx"
            let parts = cls.split(separator: " ")
            for part in parts {
                let s = String(part)
                if s.hasPrefix("lang-") { return String(s.dropFirst(5)) }
                if s.hasPrefix("language-") { return String(s.dropFirst(9)) }
            }
            return nil
        }()

        let code = (try? codeElement.text()) ?? ""
        return [.codeBlock(language: language, code: code)]
    }

    private static func extractAside(from element: Element, options: ParseOptions) -> [ContentBlock] {
        let classAttr = (try? element.attr("class")) ?? ""
        if classAttr.contains("quote") {
            return [QuoteExtractor.extract(from: element, options: options)]
        }
        if classAttr.contains("onebox") {
            return [OneboxExtractor.extract(from: element, options: options)]
        }
        // Generic aside — recurse
        return extract(from: element, options: options)
    }

    private static func extractDetails(from element: Element, options: ParseOptions) -> [ContentBlock] {
        let summaryEl = element.children().first { $0.tagName().lowercased() == "summary" }
        let summaryInlines: [InlineNode]
        if let summaryEl {
            summaryInlines = InlineExtractor.extract(from: summaryEl, options: options).trimmedWhitespace()
        } else {
            summaryInlines = [.text("Details")]
        }

        // Content is everything except the summary element
        var contentBlocks: [ContentBlock] = []
        for child in element.getChildNodes() {
            if let el = child as? Element, el.tagName().lowercased() == "summary" { continue }
            contentBlocks.append(contentsOf: extractNode(child, options: options))
        }

        return [.details(summary: summaryInlines, content: contentBlocks)]
    }

    private static func extractBlockImage(from element: Element, options: ParseOptions, href: String? = nil) -> [ContentBlock] {
        let src = URLResolver.resolve((try? element.attr("src")) ?? "", baseURL: options.baseURL)
        let alt = try? element.attr("alt")
        let width = Int((try? element.attr("width")) ?? "")
        let height = Int((try? element.attr("height")) ?? "")
        return [.image(src: src, alt: alt, width: width, height: height, href: href)]
    }

    private static func extractDiv(from element: Element, options: ParseOptions) -> [ContentBlock] {
        let classAttr = (try? element.attr("class")) ?? ""

        if hasClassToken("poll", in: classAttr), let poll = extractPoll(from: element) {
            return [.poll(poll)]
        }

        // Lightbox wrapper
        if classAttr.contains("lightbox-wrapper") {
            if let img = try? element.select("img").first() {
                let href: String? = {
                    guard let anchor = try? element.select("a").first() else { return nil }
                    let h = URLResolver.resolve((try? anchor.attr("href")) ?? "", baseURL: options.baseURL)
                    return h.isEmpty ? nil : h
                }()
                return extractBlockImage(from: img, options: options, href: href)
            }
        }

        // Video embed (youtube-onebox, lazy-video-container, etc.)
        if classAttr.contains("lazy-video-container") || classAttr.contains("video-container") {
            return extractVideo(from: element, options: options)
        }

        // Block-level spoiler: wrap all child blocks in a single .spoiler container
        if classAttr.contains("spoiler") {
            let inner = extract(from: element, options: options)
            if inner.isEmpty { return [] }
            return [.spoiler(blocks: inner)]
        }

        // Generic div — recurse into children
        let inner = extract(from: element, options: options)
        if inner.isEmpty { return [] }
        return inner
    }

    private static func extractPoll(from element: Element) -> PollBlock? {
        let options = pollOptions(from: element)
        guard !options.isEmpty else { return nil }

        let name = nonEmptyAttribute("data-poll-name", from: element)
        let status = nonEmptyAttribute("data-poll-status", from: element)
        let type = nonEmptyAttribute("data-poll-type", from: element)
        let votersText = (try? element.select(".poll-info").first()?.text())
            .flatMap(normalizedNonEmptyText)
        let votersCount = pollVotersCount(from: element, votersText: votersText)

        return PollBlock(
            name: name,
            status: status,
            type: type,
            options: options,
            votersText: votersText,
            votersCount: votersCount,
            minSelections: lossyIntAttribute("data-poll-min", from: element),
            maxSelections: lossyIntAttribute("data-poll-max", from: element),
            resultsMode: nonEmptyAttribute("data-poll-results", from: element),
            isPublic: boolAttribute("data-poll-public", from: element)
        )
    }

    private static func pollOptions(from element: Element) -> [PollOption] {
        let optionElements = (try? element.select("li[data-poll-option-id]")) ?? Elements()
        return optionElements.array().compactMap { optionElement in
            let text = pollOptionText(from: optionElement)
            guard !text.isEmpty else { return nil }
            return PollOption(
                id: nonEmptyAttribute("data-poll-option-id", from: optionElement),
                text: text,
                voteCount: pollOptionVoteCount(from: optionElement),
                percentageText: pollOptionPercentageText(from: optionElement),
                isSelected: pollOptionIsSelected(optionElement)
            )
        }
    }

    private static func pollOptionVoteCount(from element: Element) -> Int? {
        for name in ["data-poll-option-votes", "data-votes", "data-poll-votes"] {
            if let value = lossyIntAttribute(name, from: element) {
                return value
            }
        }
        let selectors = [".poll-option-votes", ".option-votes", ".votes"]
        for selector in selectors {
            if let text = (try? element.select(selector).first()?.text()).flatMap(normalizedNonEmptyText),
               let value = firstInteger(in: text) {
                return value
            }
        }
        return nil
    }

    private static func pollOptionPercentageText(from element: Element) -> String? {
        for name in ["data-poll-option-percentage", "data-percentage"] {
            if let text = nonEmptyAttribute(name, from: element) {
                return normalizedPercentageText(text)
            }
        }
        let selectors = [".percentage", ".poll-option-percentage", ".option-percentage"]
        for selector in selectors {
            if let text = (try? element.select(selector).first()?.text()).flatMap(normalizedNonEmptyText) {
                return normalizedPercentageText(text)
            }
        }
        return nil
    }

    private static func pollOptionIsSelected(_ element: Element) -> Bool {
        let classAttr = (try? element.attr("class")) ?? ""
        let selectedTokens = ["chosen", "selected", "voted", "is-selected", "is-chosen"]
        if selectedTokens.contains(where: { hasClassToken($0, in: classAttr) }) {
            return true
        }
        for name in ["data-poll-option-selected", "data-selected", "aria-checked"] {
            if boolAttribute(name, from: element) {
                return true
            }
        }
        if (try? element.select("input[checked]").first()) != nil {
            return true
        }
        return false
    }

    private static func pollVotersCount(from element: Element, votersText: String?) -> Int? {
        if let value = lossyIntAttribute("data-poll-voters", from: element) {
            return value
        }
        if let text = (try? element.select(".poll-info .info-number").first()?.text()).flatMap(normalizedNonEmptyText),
           let value = firstInteger(in: text) {
            return value
        }
        if let votersText {
            return firstInteger(in: votersText)
        }
        return nil
    }

    private static func pollOptionText(from element: Element) -> String {
        if let paragraph = try? element.select("p").first(),
           let text = normalizedNonEmptyText(try? paragraph.text()) {
            return text
        }
        if let label = try? element.select("label").first(),
           let text = normalizedNonEmptyText(try? label.text()) {
            return text
        }
        return normalizedNonEmptyText(try? element.text()) ?? ""
    }

    private static func normalizedPercentageText(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains("%") ? normalized : "\(normalized)%"
    }

    private static func extractVideo(from element: Element, options: ParseOptions) -> [ContentBlock] {
        let videoId = (try? element.attr("data-video-id")) ?? ""
        let title: String? = {
            let t = (try? element.attr("data-video-title")) ?? ""
            return t.isEmpty ? nil : t
        }()
        let provider: String? = {
            let p = (try? element.attr("data-provider-name")) ?? ""
            return p.isEmpty ? nil : p
        }()

        // URL from <a> href
        let url: String = {
            if let anchor = try? element.select("a").first() {
                let href = (try? anchor.attr("href")) ?? ""
                if !href.isEmpty { return href }
            }
            return ""
        }()

        // Thumbnail from <img>
        var thumbnailURL: String?
        var width: Int?
        var height: Int?
        if let img = try? element.select("img").first() {
            let src = (try? img.attr("src")) ?? ""
            if !src.isEmpty {
                thumbnailURL = URLResolver.resolve(src, baseURL: options.baseURL)
            }
            if let w = try? img.attr("width"), let wInt = Int(w) { width = wInt }
            if let h = try? img.attr("height"), let hInt = Int(h) { height = hInt }
        }

        return [.video(
            url: url,
            thumbnailURL: thumbnailURL,
            title: title,
            width: width,
            height: height,
            videoId: videoId.isEmpty ? nil : videoId,
            provider: provider
        )]
    }

    // MARK: - Helpers

    private static func isBlockElement(_ element: Element) -> Bool {
        blockTags.contains(element.tagName().lowercased())
    }

    private static func hasClassToken(_ token: String, in classAttr: String) -> Bool {
        classAttr
            .split(whereSeparator: { $0.isWhitespace })
            .contains { $0 == token }
    }

    private static func nonEmptyAttribute(_ name: String, from element: Element) -> String? {
        normalizedNonEmptyText(try? element.attr(name))
    }

    private static func lossyIntAttribute(_ name: String, from element: Element) -> Int? {
        nonEmptyAttribute(name, from: element).flatMap(firstInteger(in:))
    }

    private static func boolAttribute(_ name: String, from element: Element) -> Bool {
        guard let raw = nonEmptyAttribute(name, from: element)?.lowercased() else {
            return false
        }
        return raw == "true" || raw == "1" || raw == "yes" || raw == "checked"
    }

    private static func firstInteger(in text: String) -> Int? {
        let pattern = #"-?\d+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return Int(text[range])
    }

    private static func normalizedNonEmptyText(_ text: String?) -> String? {
        guard let normalized = text?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty
        else { return nil }
        return normalized
    }

    /// Trim whitespace-only paragraphs.
    private static func trimBlock(_ block: ContentBlock) -> ContentBlock? {
        switch block {
        case .paragraph(let inlines):
            let trimmed = inlines.filter { node in
                switch node {
                case .text(let t): return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                case .styledText(let t, _): return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                default: return true
                }
            }
            return trimmed.isEmpty ? nil : .paragraph(trimmed)
        default:
            return block
        }
    }

    /// Merge blocks that result from SwiftSoup splitting inline content into separate top-level nodes.
    /// Handles two cases:
    /// 1. Small (emoji-sized) `.image` blocks following a `.paragraph` → merged as inline image.
    /// 2. Consecutive `.paragraph` blocks that are bare siblings (no intervening block) → merged.
    private static func mergeInlineImageBlocks(_ blocks: [ContentBlock]) -> [ContentBlock] {
        guard blocks.count > 1 else { return blocks }
        var result: [ContentBlock] = []
        for block in blocks {
            guard let lastIndex = result.indices.last else {
                result.append(block)
                continue
            }
            // Case 1: small image following a paragraph → inline emoji
            if case .image(let src, let alt, let w, let h, _) = block,
               let w, let h, w <= 80, h <= 80,
               case .paragraph(let inlines) = result[lastIndex]
            {
                result[lastIndex] = .paragraph(inlines + [.image(src: src, alt: alt, width: w, height: h, isEmoji: true)])
                continue
            }
            // Case 2: bare text/inline paragraph following a paragraph that ends with an inline image
            // (handles SwiftSoup splitting "text<img>text" into separate top-level nodes)
            if case .paragraph(let newInlines) = block,
               case .paragraph(let prevInlines) = result[lastIndex],
               case .image(_, _, _, _, let isEmoji) = prevInlines.last, isEmoji
            {
                result[lastIndex] = .paragraph(prevInlines + newInlines)
                continue
            }
            result.append(block)
        }
        return result
    }
}
