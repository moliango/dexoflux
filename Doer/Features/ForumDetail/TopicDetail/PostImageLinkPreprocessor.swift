import Foundation

/// Rewrites Discourse cooked HTML so bare auto-linked image/badge URLs become
/// real `<img>` tags before CookedHTML parsing.
///
/// FluxDo ends up showing these as media. Discourse often leaves failed oneboxes
/// as `<a href="https://...jpg">https://...jpg</a>` which native rendering used
/// to keep as plain links.
nonisolated enum PostImageLinkPreprocessor {
    /// Match standalone anchor whose href looks like an image / badge endpoint.
    private static let anchorPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"<a\b([^>]*?)href\s*=\s*(["'])(https?://[^"']+)\2([^>]*)>([\s\S]*?)</a>"#,
            options: [.caseInsensitive]
        )
    }()

    static func rewrite(_ html: String) -> String {
        guard !html.isEmpty else { return html }
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)
        var output = ""
        var last = 0

        anchorPattern.enumerateMatches(in: html, options: [], range: full) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range
            if matchRange.location > last {
                output += ns.substring(with: NSRange(location: last, length: matchRange.location - last))
            }

            let href = ns.substring(with: match.range(at: 3))
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let inner = ns.substring(with: match.range(at: 5))
            let attrsBefore = ns.substring(with: match.range(at: 1))
            let attrsAfter = ns.substring(with: match.range(at: 4))
            let allAttrs = (attrsBefore + " " + attrsAfter).lowercased()

            // Keep real interactive anchors (mentions / hashtags / lightbox / attachments).
            let keepAsLink =
                allAttrs.contains("mention")
                || allAttrs.contains("hashtag")
                || allAttrs.contains("lightbox")
                || allAttrs.contains("attachment")
                || allAttrs.contains("badge-category")
                || inner.localizedCaseInsensitiveContains("<img")

            if !keepAsLink, isImageLikeURL(href) {
                let escaped = href
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                // Emit <img> so BlockExtractor extracts a real image block.
                output += "<img src=\"\(escaped)\" alt=\"\">"
            } else {
                output += ns.substring(with: matchRange)
            }
            last = matchRange.location + matchRange.length
        }

        if last < ns.length {
            output += ns.substring(with: NSRange(location: last, length: ns.length - last))
        }
        return output.isEmpty ? html : output
    }

    private static func isImageLikeURL(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return false
        }
        if lower.contains("iwooji.com/badge") || lower.contains("/badge?") || lower.hasSuffix("/badge") {
            return true
        }
        if lower.contains("/raw/") {
            return true
        }
        let path: String = {
            if let url = URL(string: value) {
                return url.path.lowercased()
            }
            return lower
        }()
        let exts = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif", ".heic", ".heif", ".bmp", ".svg"]
        if exts.contains(where: { path.hasSuffix($0) }) {
            return true
        }
        if lower.contains("format=png") || lower.contains("format=jpg") || lower.contains("format=webp") {
            return true
        }
        return false
    }
}
