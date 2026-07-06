import Foundation
import SwiftSoup

/// Extracts list content from `<ul>` and `<ol>` elements.
enum ListExtractor {
    static func extract(from element: Element, ordered: Bool, options: ParseOptions) -> ContentBlock {
        var items: [ListItem] = []

        for child in element.children() {
            guard child.tagName().lowercased() == "li" else { continue }
            let li = child
            items.append(extractItem(from: li, options: options))
        }

        return .list(ordered: ordered, items: items)
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
                    // Paragraph inside li — extract as inline content
                    inlineNodes.append(contentsOf: InlineExtractor.extract(from: element, options: options))
                } else {
                    // Other block elements inside li
                    let blockLevelTags: Set<String> = ["pre", "blockquote", "table", "div", "details"]
                    if blockLevelTags.contains(tag) {
                        childBlocks.append(contentsOf: BlockExtractor.extract(from: element, options: options))
                    } else {
                        inlineNodes.append(contentsOf: InlineExtractor.extract(from: element, options: options, style: []))
                    }
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
}
