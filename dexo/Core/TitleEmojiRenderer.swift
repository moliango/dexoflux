import UIKit

/// Shared shortcode → attributed title rendering for topic list/detail surfaces.
enum TitleEmojiRenderer {
    /// FluxDo parity: `:([^\s:]+(?:\:t[1-6])?):`
    static let shortcodePattern = try! NSRegularExpression(pattern: #":([^\s:]+(?:\:t[1-6])?):"#)

    /// Build display title for list/detail.
    ///
    /// FluxDo uses raw `topic.title`. Discourse `fancy_title` often keeps HTML entities
    /// (`&hellip;`) and can introduce cook-time punctuation artifacts (extra `.` etc).
    /// Prefer raw title; only fall back to fancy HTML when we need emoji shortcodes from `<img>`.
    static func plainTitle(fancyTitle: String?, title: String) -> String {
        let fancy = fancyTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if !raw.isEmpty {
            var result = decodeHTMLEntities(raw)
            // Raw title has no shortcodes, but fancy HTML may carry emoji <img alt=":code:">.
            if !containsShortcode(result), fancy.contains("<img") || fancy.contains("<IMG") {
                let recovered = decodeHTMLEntities(recoverShortcodesFromHTML(fancy))
                if containsShortcode(recovered) {
                    return recovered
                }
            }
            return result
        }

        if fancy.isEmpty {
            return ""
        }
        if fancy.contains("<"), fancy.contains(">") {
            return decodeHTMLEntities(recoverShortcodesFromHTML(fancy))
        }
        return decodeHTMLEntities(fancy)
    }

    static func containsShortcode(_ title: String) -> Bool {
        let range = NSRange(title.startIndex..., in: title)
        return shortcodePattern.firstMatch(in: title, range: range) != nil
    }

    /// Builds an attributed title, replacing shortcodes with image attachments.
    static func attributedTitle(
        _ title: String,
        font: UIFont,
        textColor: UIColor? = nil,
        baseURL: String?
    ) -> NSAttributedString {
        var working = title.contains("<") ? recoverShortcodesFromHTML(title) : title
        working = decodeHTMLEntities(working)
        guard containsShortcode(working) else {
            return plainString(working, font: font, textColor: textColor)
        }

        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let textColor {
            attributes[.foregroundColor] = textColor
        }

        let matches = shortcodePattern.matches(
            in: working,
            range: NSRange(working.startIndex..., in: working)
        )
        guard !matches.isEmpty else {
            return plainString(working, font: font, textColor: textColor)
        }

        let result = NSMutableAttributedString()
        var lastEnd = working.startIndex
        var replacedAny = false

        for match in matches {
            guard let fullRange = Range(match.range, in: working),
                  let codeRange = Range(match.range(at: 1), in: working)
            else { continue }

            if lastEnd < fullRange.lowerBound {
                result.append(
                    NSAttributedString(
                        string: String(working[lastEnd..<fullRange.lowerBound]),
                        attributes: attributes
                    )
                )
            }

            let code = String(working[codeRange])
            if let urlString = EmojiStore.resolvedURLString(for: code, baseURL: baseURL),
               let url = URL(string: urlString) {
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.shortcode = ":\(code):"
                attachment.bounds = CGRect(
                    x: 0,
                    y: font.descender,
                    width: font.lineHeight,
                    height: font.lineHeight
                )
                result.append(NSAttributedString(attachment: attachment))
                replacedAny = true
            } else {
                result.append(
                    NSAttributedString(string: String(working[fullRange]), attributes: attributes)
                )
            }

            lastEnd = fullRange.upperBound
        }

        if lastEnd < working.endIndex {
            result.append(
                NSAttributedString(string: String(working[lastEnd...]), attributes: attributes)
            )
        }

        return replacedAny ? result : plainString(working, font: font, textColor: textColor)
    }

    static func apply(
        _ title: String,
        to label: UILabel,
        font: UIFont,
        textColor: UIColor? = nil,
        baseURL: String?
    ) {
        if let textColor {
            label.textColor = textColor
        }

        var working = title.contains("<") ? recoverShortcodesFromHTML(title) : title
        working = decodeHTMLEntities(working)
        guard containsShortcode(working) else {
            label.attributedText = nil
            label.text = working
            return
        }

        let rendered = attributedTitle(working, font: font, textColor: textColor, baseURL: baseURL)
        guard containsAttachment(rendered) else {
            label.attributedText = nil
            label.text = working
            return
        }

        label.text = nil
        label.attributedText = rendered
        loadImages(in: rendered, cloudflareBaseURL: baseURL) { [weak label] in
            guard let label else { return }
            label.attributedText = rendered
            label.setNeedsDisplay()
            label.invalidateIntrinsicContentSize()
        }
    }

    static func loadImages(
        in attributedString: NSAttributedString,
        cloudflareBaseURL: String? = nil,
        onImageLoaded: @escaping () -> Void
    ) {
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? EmojiTextAttachment, let url = attachment.emojiURL else { return }
            ForumImageLoader.loadImage(with: url, cloudflareBaseURL: cloudflareBaseURL) { image in
                guard let image else { return }
                attachment.image = image
                onImageLoaded()
            }
        }
    }

    /// Recover `:shortcode:` from Discourse fancy_title HTML img tags and strip markup.
    static func recoverShortcodesFromHTML(_ html: String) -> String {
        var result = html
        let imgPattern = try! NSRegularExpression(
            pattern: #"<img\b[^>]*(?:title|alt)\s*=\s*[\"']:([^\"']+)[\"'][^>]*>"#,
            options: [.caseInsensitive]
        )
        result = imgPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ":$1:"
        )
        let tagPattern = try! NSRegularExpression(pattern: #"<[^>]+>"#, options: [])
        result = tagPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        return result
    }

    /// Decode HTML entities commonly present in Discourse `fancy_title`.
    /// Example: `服务不崩&hellip;&hellip;` → `服务不崩……`
    static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var result = text

        // Numeric entities: &#8230; and &#x2026;
        let numericPattern = try! NSRegularExpression(
            pattern: #"&#(x?[0-9a-fA-F]+);"#
        )
        let ns = result as NSString
        let matches = numericPattern.matches(in: result, range: NSRange(location: 0, length: ns.length))
        // Replace from end to keep ranges valid.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let full = Range(match.range, in: result),
                  let body = Range(match.range(at: 1), in: result)
            else { continue }
            let token = String(result[body])
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token)
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                result.replaceSubrange(full, with: String(Character(scalar)))
            }
        }

        // Named entities (amp last).
        let named: [(String, String)] = [
            ("&hellip;", "…"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&nbsp;", " "),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private static func plainString(_ title: String, font: UIFont, textColor: UIColor?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let textColor {
            attributes[.foregroundColor] = textColor
        }
        return NSAttributedString(string: title, attributes: attributes)
    }

    private static func containsAttachment(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if value is NSTextAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
