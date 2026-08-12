import Foundation
import SwiftSoup

/// Extracts list content from `<ul>` and `<ol>` elements.
enum ListExtractor {
    /// Block-level tags that should become `ListItem.children` (not inline text).
    ///
    /// `div` / `figure` cover Discourse lightbox wrappers; `img` covers bare block images.
    /// Nested lists are handled separately so numbering/bullets stay correct.
    private static let nestedBlockTags: Set<String> = [
        "pre", "blockquote", "table", "div", "details", "figure", "aside", "hr", "img",
    ]

    static func extract(from element: Element, ordered: Bool, options: ParseOptions) -> ContentBlock {
        var items: [ListItem] = []

        for child in element.children() {
            guard child.tagName().lowercased() == "li" else { continue }
            let li = child
            items.append(extractItem(from: li, options: options))
        }

        // Discourse may emit `<ol start="N">` when a numbered list is interrupted
        // (e.g. by `[details]`). Default is 1 when the attribute is absent/invalid.
        let start: Int = {
            guard ordered else { return 1 }
            let raw = ((try? element.attr("start")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(raw), value > 0 else { return 1 }
            return value
        }()

        return .list(ordered: ordered, start: start, items: items)
    }

    private static func extractItem(from li: Element, options: ParseOptions) -> ListItem {
        var inlineNodes: [InlineNode] = []
        var childBlocks: [ContentBlock] = []

        for child in li.getChildNodes() {
            if let element = child as? Element {
                let tag = element.tagName().lowercased()
                if tag == "ul" {
                    childBlocks.append(extract(from: element, ordered: false, options: options))
                } else if tag == "ol" {
                    childBlocks.append(extract(from: element, ordered: true, options: options))
                } else if tag == "p" {
                    // Full block extraction so sole-image / lightbox paragraphs promote
                    // to `.image` children instead of blank inline attachments.
                    appendBlocks(
                        BlockExtractor.extractBlocks(for: element, options: options),
                        toInlines: &inlineNodes,
                        children: &childBlocks
                    )
                } else if nestedBlockTags.contains(tag) {
                    // Process the element itself (not only its children) so
                    // `div.lightbox-wrapper` becomes a real image block.
                    appendBlocks(
                        BlockExtractor.extractBlocks(for: element, options: options),
                        toInlines: &inlineNodes,
                        children: &childBlocks
                    )
                } else {
                    inlineNodes.append(contentsOf: InlineExtractor.extract(from: element, options: options, style: []))
                }
            } else if let textNode = child as? TextNode {
                let text = textNode.getWholeText()
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inlineNodes.append(.text(text))
                }
            }
        }

        return ListItem(content: inlineNodes, children: childBlocks)
    }

    /// Fold paragraph blocks into list-item inlines; keep media / nested blocks as children.
    private static func appendBlocks(
        _ blocks: [ContentBlock],
        toInlines inlineNodes: inout [InlineNode],
        children childBlocks: inout [ContentBlock]
    ) {
        for block in blocks {
            switch block {
            case .paragraph(let inlines):
                let trimmed = inlines.trimmedWhitespace()
                guard !trimmed.isEmpty else { continue }
                if !inlineNodes.isEmpty {
                    inlineNodes.append(.lineBreak)
                }
                inlineNodes.append(contentsOf: trimmed)
            default:
                childBlocks.append(block)
            }
        }
    }
}
