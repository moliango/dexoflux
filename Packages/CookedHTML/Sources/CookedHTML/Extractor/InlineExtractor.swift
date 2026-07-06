import Foundation
import SwiftSoup

/// Extracts inline nodes from a DOM element's children.
enum InlineExtractor {
    /// Extract inline nodes from the children of the given element.
    static func extract(from element: Element, options: ParseOptions, style: TextStyle = []) -> [InlineNode] {
        var nodes: [InlineNode] = []
        for child in element.getChildNodes() {
            nodes.append(contentsOf: extractNode(child, options: options, style: style))
        }
        return mergeAdjacentText(nodes)
    }

    /// Extract inline nodes from a single DOM node.
    static func extractNode(_ node: Node, options: ParseOptions, style: TextStyle = []) -> [InlineNode] {
        if let textNode = node as? TextNode {
            let text = textNode.getWholeText()
            if text.allSatisfy({ $0.isWhitespace }) && text.contains("\n") {
                // Collapse pure whitespace containing newlines to a single space
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [.text(" ")] : [.text(text)]
            }
            if style.isEmpty {
                return [.text(text)]
            } else {
                return [.styledText(text, style)]
            }
        }

        guard let element = node as? Element else { return [] }
        let tagName = element.tagName().lowercased()

        switch tagName {
        case "strong", "b":
            return extract(from: element, options: options, style: style.union(.bold))

        case "em", "i":
            return extract(from: element, options: options, style: style.union(.italic))

        case "s", "del":
            return extract(from: element, options: options, style: style.union(.strikethrough))

        case "a":
            let href = resolveURL((try? element.attr("href")) ?? "", options: options)
            let classAttr = (try? element.attr("class")) ?? ""
            if classAttr.contains("mention-group") {
                let text = (try? element.text()) ?? ""
                let name = text.hasPrefix("@") ? String(text.dropFirst()) : text
                return [.mentionGroup(name: name, href: href)]
            }
            if classAttr.contains("mention") {
                let text = (try? element.text()) ?? ""
                let username = text.hasPrefix("@") ? String(text.dropFirst()) : text
                return [.mention(username: username, href: href)]
            }
            if classAttr.contains("hashtag-cooked") || classAttr.contains("hashtag") {
                let text = (try? element.text()) ?? ""
                let displayText = text.hasPrefix("#") ? String(text.dropFirst()) : text
                let dataType = try? element.attr("data-type")
                let type = (dataType?.isEmpty == false) ? dataType : nil
                return [.hashtag(text: displayText, href: href, type: type)]
            }
            let children = extract(from: element, options: options, style: style)
            return [.link(href: href, children: children)]

        case "img":
            return extractImage(from: element, options: options)

        case "code":
            let text = (try? element.text()) ?? ""
            return [.code(text)]

        case "br":
            return [.lineBreak]

        case "span":
            let classAttr = (try? element.attr("class")) ?? ""
            if classAttr.contains("spoiler") {
                let children = extract(from: element, options: options, style: style)
                return [.spoiler(children: children)]
            }
            return extract(from: element, options: options, style: style)

        case "div":
            let classAttr = (try? element.attr("class")) ?? ""
            if classAttr.contains("lightbox-wrapper") {
                if let img = try? element.select("img").first() {
                    let imageNodes = extractImage(from: img, options: options)
                    if let anchor = try? element.select("a.lightbox").first(),
                       let href = try? anchor.attr("href"), !href.isEmpty {
                        let resolvedHref = resolveURL(href, options: options)
                        return [.link(href: resolvedHref, children: imageNodes)]
                    }
                    return imageNodes
                }
            }
            return extract(from: element, options: options, style: style)

        default:
            // For other inline elements, just recurse into children
            return extract(from: element, options: options, style: style)
        }
    }

    /// Extract an image inline node from an `<img>` element.
    private static func extractImage(from element: Element, options: ParseOptions) -> [InlineNode] {
        let src = resolveURL((try? element.attr("src")) ?? "", options: options)
        let alt = try? element.attr("alt")
        let width = Int((try? element.attr("width")) ?? "")
        let height = Int((try? element.attr("height")) ?? "")

        let classAttr = (try? element.attr("class")) ?? ""
        let isEmoji = classAttr.contains("emoji")

        return [.image(src: src, alt: alt, width: width, height: height, isEmoji: isEmoji)]
    }

    /// Resolve a URL using the parse options.
    private static func resolveURL(_ url: String, options: ParseOptions) -> String {
        URLResolver.resolve(url, baseURL: options.baseURL)
    }

    /// Merge adjacent `.text` nodes and adjacent `.styledText` nodes with the same style.
    private static func mergeAdjacentText(_ nodes: [InlineNode]) -> [InlineNode] {
        guard !nodes.isEmpty else { return [] }
        var result: [InlineNode] = []

        for node in nodes {
            guard let last = result.last else {
                result.append(node)
                continue
            }
            switch (last, node) {
            case (.text(let a), .text(let b)):
                result[result.count - 1] = .text(a + b)
            case (.styledText(let a, let styleA), .styledText(let b, let styleB)) where styleA == styleB:
                result[result.count - 1] = .styledText(a + b, styleA)
            default:
                result.append(node)
            }
        }

        // Remove empty text nodes
        return result.filter { node in
            switch node {
            case .text(let t) where t.isEmpty: return false
            case .styledText(let t, _) where t.isEmpty: return false
            default: return true
            }
        }
    }
}
