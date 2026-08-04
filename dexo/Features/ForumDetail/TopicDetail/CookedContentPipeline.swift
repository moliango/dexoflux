import CookedHTML
import Foundation

/// Single entry for published post content (Phase 4).
/// Always starts from Discourse **cooked HTML** — never bare markdown source.
enum CookedContentPipeline {
    /// Preprocess + parse cooked HTML into content blocks.
    static func blocks(fromCooked cooked: String, baseURL: String? = nil) -> [ContentBlock] {
        let rewritten = PostImageLinkPreprocessor.rewrite(cooked)
        return CookedHTMLParser.parse(html: rewritten, baseURL: baseURL)
    }

    /// Readable plain text for export / AI context / previews.
    static func plainText(fromCooked cooked: String, baseURL: String? = nil) -> String {
        let rewritten = PostImageLinkPreprocessor.rewrite(cooked)
        return CookedTextExporter.plainText(fromHTML: rewritten, baseURL: baseURL)
    }

    /// Single-line plain text for list cells, search blurbs, and action-sheet excerpts.
    /// Collapses internal whitespace so previews never wrap on leftover `\n` from block export.
    static func plainTextPreview(fromCooked cooked: String, baseURL: String? = nil) -> String {
        plainText(fromCooked: cooked, baseURL: baseURL)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lightweight markdown for export / Notion.
    static func markdown(fromCooked cooked: String, baseURL: String? = nil) -> String {
        let rewritten = PostImageLinkPreprocessor.rewrite(cooked)
        return CookedTextExporter.markdown(fromHTML: rewritten, baseURL: baseURL)
    }
}
