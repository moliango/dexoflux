import CookedHTML
import Foundation
import UIKit

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

    /// Discourse search highlight → attributed string (FluxDo-style).
    ///
    /// FluxDo parses `topic_title_headline` / blurb with:
    /// `RegExp(r'<span class="search-highlight">(.*?)</span>')`
    /// and paints `primaryContainer` background + `onPrimaryContainer` text.
    ///
    /// We also accept legacy `<em>` / `<mark>` wrappers some Discourse builds emit.
    static func highlightedPreview(
        fromCooked cooked: String,
        baseURL: String? = nil,
        font: UIFont,
        textColor: UIColor,
        highlightBackground: UIColor? = nil,
        highlightForeground: UIColor? = nil
    ) -> NSAttributedString {
        let bg = highlightBackground
            ?? UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.systemBlue.withAlphaComponent(0.35)
                    : UIColor.systemBlue.withAlphaComponent(0.18)
            }
        let fg = highlightForeground
            ?? UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.white
                    : UIColor.label
            }

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: font.pointSize, weight: .medium),
            .foregroundColor: fg,
            .backgroundColor: bg,
        ]

        let source = cooked.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return NSAttributedString(string: "", attributes: baseAttrs)
        }

        // Prefer FluxDo's exact Discourse marker first; fall back to em/mark.
        let pattern = #"(?is)<span\b[^>]*class\s*=\s*['\"][^'\"]*search-highlight[^'\"]*['\"][^>]*>(.*?)</span>|<em\b[^>]*>(.*?)</em>|<mark\b[^>]*>(.*?)</mark>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            let plain = stripTagsAndEntities(source)
            return NSAttributedString(string: plain, attributes: baseAttrs)
        }

        let nsSource = source as NSString
        let full = NSRange(location: 0, length: nsSource.length)
        let matches = regex.matches(in: source, options: [], range: full)

        guard !matches.isEmpty else {
            let plain = stripTagsAndEntities(source)
            // Still may contain emoji shortcodes / fancy title bits — keep plain clean.
            return NSAttributedString(string: plain.isEmpty ? plainTextPreview(fromCooked: source, baseURL: baseURL) : plain, attributes: baseAttrs)
        }

        let result = NSMutableAttributedString()
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let before = nsSource.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let cleaned = stripTagsAndEntities(before)
                if !cleaned.isEmpty {
                    result.append(NSAttributedString(string: cleaned, attributes: baseAttrs))
                }
            }

            var highlighted = ""
            for group in 1 ..< match.numberOfRanges {
                let r = match.range(at: group)
                if r.location != NSNotFound {
                    highlighted = stripTagsAndEntities(nsSource.substring(with: r))
                    break
                }
            }
            if !highlighted.isEmpty {
                result.append(NSAttributedString(string: highlighted, attributes: highlightAttrs))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsSource.length {
            let after = nsSource.substring(with: NSRange(location: cursor, length: nsSource.length - cursor))
            let cleaned = stripTagsAndEntities(after)
            if !cleaned.isEmpty {
                result.append(NSAttributedString(string: cleaned, attributes: baseAttrs))
            }
        }

        if result.length == 0 {
            let plain = plainTextPreview(fromCooked: source, baseURL: baseURL)
            return NSAttributedString(string: plain, attributes: baseAttrs)
        }
        return result
    }

    /// Lightweight markdown for export / Notion.
    static func markdown(fromCooked cooked: String, baseURL: String? = nil) -> String {
        let rewritten = PostImageLinkPreprocessor.rewrite(cooked)
        return CookedTextExporter.markdown(fromHTML: rewritten, baseURL: baseURL)
    }

    // MARK: - Helpers

    private static func stripTagsAndEntities(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
