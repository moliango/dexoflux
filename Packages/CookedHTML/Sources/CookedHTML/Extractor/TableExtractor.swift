import Foundation
import SwiftSoup

/// Extracts table content from `<table>` elements.
/// Each cell is extracted as `[ContentBlock]` using the standard block extraction pipeline,
/// so images, spoilers, and all other block types are handled uniformly.
enum TableExtractor {
    static func extract(from element: Element, options: ParseOptions) -> ContentBlock {
        var headers: [[ContentBlock]] = []
        var rows: [[[ContentBlock]]] = []

        // Extract headers from thead > tr > th
        if let thead = try? element.select("thead").first() {
            if let tr = try? thead.select("tr").first() {
                let thElements = (try? tr.select("th")) ?? Elements()
                for th in thElements {
                    headers.append(extractCellBlocks(from: th, options: options))
                }
            }
        }

        // Extract rows from tbody > tr > td
        let tbody = try? element.select("tbody").first()
        let rowParent = tbody ?? element
        let trElements = (try? rowParent.select("tr")) ?? Elements()

        for tr in trElements {
            // Skip header rows
            if let parent = tr.parent(), parent.tagName().lowercased() == "thead" { continue }

            var row: [[ContentBlock]] = []
            let cells = tr.children()
            for cell in cells {
                let tag = cell.tagName().lowercased()
                if tag == "td" || tag == "th" {
                    row.append(extractCellBlocks(from: cell, options: options))
                }
            }
            if !row.isEmpty {
                rows.append(row)
            }
        }

        return .table(headers: headers, rows: rows)
    }

    /// Extract blocks from a table cell, merging adjacent paragraphs that result
    /// from bare inline siblings being split into separate paragraph blocks.
    private static func extractCellBlocks(from element: Element, options: ParseOptions) -> [ContentBlock] {
        let blocks = BlockExtractor.extract(from: element, options: options)
        return mergeAdjacentParagraphs(blocks)
    }

    private static func mergeAdjacentParagraphs(_ blocks: [ContentBlock]) -> [ContentBlock] {
        guard blocks.count > 1 else { return blocks }
        var result: [ContentBlock] = []
        for block in blocks {
            if case .paragraph(let newInlines) = block,
               let lastIdx = result.indices.last,
               case .paragraph(let existingInlines) = result[lastIdx] {
                result[lastIdx] = .paragraph(existingInlines + newInlines)
            } else {
                result.append(block)
            }
        }
        return result
    }
}
