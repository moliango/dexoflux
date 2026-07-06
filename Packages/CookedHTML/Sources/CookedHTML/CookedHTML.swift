import Foundation
import SwiftSoup

/// Main entry point for parsing Discourse `cooked` HTML into structured content blocks.
public enum CookedHTMLParser {
    /// Parse an HTML string into an array of `ContentBlock`.
    ///
    /// - Parameters:
    ///   - html: The raw `cooked` HTML from a Discourse post.
    ///   - baseURL: Optional base URL for resolving relative links and images.
    /// - Returns: An array of block-level content elements.
    public static func parse(html: String, baseURL: String? = nil) -> [ContentBlock] {
        let options = ParseOptions(baseURL: baseURL)
        do {
            let document = try SwiftSoup.parse(html)
            guard let body = document.body() else { return [] }
            return BlockExtractor.extract(from: body, options: options)
        } catch {
            return [.rawHTML(html)]
        }
    }

    /// Parse an HTML string into an array of `AnnotatedBlock`, preserving the source HTML for each block.
    public static func parseAnnotated(html: String, baseURL: String? = nil) -> [AnnotatedBlock] {
        let options = ParseOptions(baseURL: baseURL)
        do {
            let document = try SwiftSoup.parse(html)
            guard let body = document.body() else { return [] }
            return BlockExtractor.extractAnnotated(from: body, options: options)
        } catch {
            return [AnnotatedBlock(block: .rawHTML(html), sourceHTML: html)]
        }
    }
}
