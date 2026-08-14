import UIKit

extension NSAttributedString.Key {
    static let composerHeadingLevel = NSAttributedString.Key("doer.composer.headingLevel")
    static let composerQuoteDepth = NSAttributedString.Key("doer.composer.quoteDepth")
    static let composerListMarker = NSAttributedString.Key("doer.composer.listMarker")
    static let composerCodeLanguage = NSAttributedString.Key("doer.composer.codeLanguage")
    static let composerOpenTag = NSAttributedString.Key("doer.composer.openTag")
    static let composerCloseTag = NSAttributedString.Key("doer.composer.closeTag")
    static let composerImageURL = NSAttributedString.Key("doer.composer.imageURL")
    static let composerImageAlt = NSAttributedString.Key("doer.composer.imageAlt")
}

/// Native markdown ↔ visual attributed string.
/// ponytail: no Discourse cook JS; round-trip common Discourse markdown, keep exotic blocks as literal text.
enum ComposerMarkdownCodec {
    static func richAttributedString(from markdown: String) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var index = 0
        var openTag: String?

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if let language = fenceLanguage(trimmed) {
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if fenceLanguage(candidate.trimmingCharacters(in: .whitespaces)) != nil {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                result.append(makeCodeBlock(language: language, lines: codeLines))
                continue
            }

            if trimmed.hasPrefix("[quote") && trimmed.hasSuffix("]") && !trimmed.hasPrefix("[/quote") {
                openTag = trimmed
                index += 1
                continue
            }
            if trimmed == "[/quote]" {
                if result.length > 0 {
                    let last = NSRange(location: result.length - 1, length: 1)
                    result.addAttribute(.composerCloseTag, value: "[/quote]", range: last)
                }
                openTag = nil
                index += 1
                continue
            }
            if trimmed == "[spoiler]" {
                openTag = "[spoiler]"
                index += 1
                continue
            }
            if trimmed == "[/spoiler]" {
                if result.length > 0 {
                    result.addAttribute(.composerCloseTag, value: "[/spoiler]", range: NSRange(location: result.length - 1, length: 1))
                }
                openTag = nil
                index += 1
                continue
            }

            result.append(renderLine(rawLine, openTag: openTag))
            index += 1
        }

        if result.length == 0 {
            return NSMutableAttributedString(string: "", attributes: ComposerTypography.typingAttributes)
        }
        return result
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        var chunks: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage = ""
        var pendingOpen: String?
        var pendingClose: String?

        func flushCode() {
            guard !codeLanguage.isEmpty || !codeBuffer.isEmpty else { return }
            var block = "```\(codeLanguage)\n"
            block += codeBuffer.joined(separator: "\n")
            if !block.hasSuffix("\n") { block += "\n" }
            block += "```"
            chunks.append(block)
            codeBuffer = []
            codeLanguage = ""
        }

        func flushTagsAround(_ body: String) -> String {
            var text = body
            if let open = pendingOpen {
                text = "\(open)\n\(text)"
                pendingOpen = nil
            }
            if let close = pendingClose {
                text = "\(text)\n\(close)"
                pendingClose = nil
            }
            return text
        }

        attributed.enumerateParagraphs { paragraph, paragraphStart, attributes in
            if let language = attributes[.composerCodeLanguage] as? String {
                if codeLanguage != language {
                    flushCode()
                    codeLanguage = language
                }
                codeBuffer.append(paragraph.trimmingCharacters(in: CharacterSet.newlines))
                return
            }
            flushCode()

            if let open = attributes[.composerOpenTag] as? String {
                pendingOpen = open
            }
            if let close = attributes[.composerCloseTag] as? String {
                pendingClose = close
            }

            var line = serializeInlines(paragraph, attributesProvider: { loc in
                attributesAt(attributed, location: paragraphStart + loc)
            })
            line = line.trimmingCharacters(in: CharacterSet.newlines)

            if let level = attributes[.composerHeadingLevel] as? Int, (1...6).contains(level), !line.isEmpty {
                line = String(repeating: "#", count: level) + " " + line
            } else if let marker = attributes[.composerListMarker] as? String, !line.isEmpty {
                line = marker + line
            }

            let depth = attributes[.composerQuoteDepth] as? Int ?? 0
            if depth > 0, pendingOpen == nil {
                let prefix = String(repeating: "> ", count: depth)
                line = line.isEmpty ? String(repeating: ">", count: depth) : prefix + line
            }

            chunks.append(flushTagsAround(line))
        }
        flushCode()
        if let open = pendingOpen { chunks.insert(open, at: 0) }
        if let close = pendingClose { chunks.append(close) }

        while chunks.last?.isEmpty == true { chunks.removeLast() }
        return chunks.joined(separator: "\n")
    }

    static func typingAttributes(at location: Int, in attributed: NSAttributedString) -> [NSAttributedString.Key: Any] {
        guard attributed.length > 0 else { return ComposerTypography.typingAttributes }
        let index = min(max(location, 0), attributed.length - 1)
        var attrs = attributed.attributes(at: index, effectiveRange: nil)
        if attrs[.font] == nil {
            attrs[.font] = ComposerTypography.bodyFont
        }
        if attrs[.foregroundColor] == nil {
            attrs[.foregroundColor] = UIColor.label
        }
        if attrs[.paragraphStyle] == nil {
            attrs[.paragraphStyle] = ComposerTypography.paragraphStyle()
        }
        return attrs
    }

    // MARK: - Parse

    private static func renderLine(_ rawLine: String, openTag: String?) -> NSAttributedString {
        var line = rawLine
        var headingLevel = 0
        var quoteDepth = 0
        var listMarker: String?
        var font = ComposerTypography.bodyFont
        var color = UIColor.label
        var headIndent: CGFloat = 0

        while line.hasPrefix("> ") || line == ">" {
            quoteDepth += 1
            if line == ">" {
                line = ""
                break
            }
            line.removeFirst(2)
        }

        if let match = line.range(of: #"^(#{1,6})\s+"#, options: .regularExpression) {
            headingLevel = line[match].filter { $0 == "#" }.count
            line.removeSubrange(match)
            font = ComposerTypography.headingFont(level: headingLevel)
        } else if let match = line.range(of: #"^\s*([-*+])\s+"#, options: .regularExpression) {
            listMarker = "- "
            line = String(line[match.upperBound...])
            headIndent = 18
        } else if let match = line.range(of: #"^\s*(\d+)\.\s+"#, options: .regularExpression) {
            listMarker = String(line[match])
            line = String(line[match.upperBound...])
            headIndent = 22
        }

        if quoteDepth > 0 {
            color = .secondaryLabel
            headIndent += CGFloat(quoteDepth) * 14
        }
        if openTag != nil {
            color = .secondaryLabel
            headIndent = max(headIndent, 14)
            quoteDepth = max(quoteDepth, 1)
        }

        var base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: ComposerTypography.paragraphStyle(headIndent: headIndent),
        ]
        if headingLevel > 0 { base[.composerHeadingLevel] = headingLevel }
        if quoteDepth > 0 { base[.composerQuoteDepth] = quoteDepth }
        if let listMarker { base[.composerListMarker] = listMarker }
        if let openTag { base[.composerOpenTag] = openTag }

        let inline = parseInlines(line, base: base)
        let ending = NSMutableAttributedString(attributedString: inline)
        ending.append(NSAttributedString(string: "\n", attributes: base))
        return ending
    }

    private static func makeCodeBlock(language: String, lines: [String]) -> NSAttributedString {
        let body = (lines.isEmpty ? [""] : lines).joined(separator: "\n") + "\n"
        let style = ComposerTypography.paragraphStyle(paragraphSpacing: 10)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ComposerTypography.codeFont,
            .foregroundColor: UIColor.label,
            .backgroundColor: ComposerTypography.mutedFill,
            .paragraphStyle: style,
            .composerCodeLanguage: language,
        ]
        return NSAttributedString(string: body, attributes: attributes)
    }

    private static func parseInlines(_ line: String, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: line, attributes: base)
        applyInline(
            pattern: #"`([^`\n]+)`"#,
            in: attributed,
            transform: { content, attrs in
                var next = attrs
                next[.font] = ComposerTypography.codeFont
                next[.backgroundColor] = ComposerTypography.mutedFill
                return NSAttributedString(string: content, attributes: next)
            }
        )
        applyInline(
            pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#,
            in: attributed,
            transform: { content, attrs in
                var next = attrs
                next[.foregroundColor] = ComposerTypography.accentColor
                next[.underlineStyle] = NSUnderlineStyle.single.rawValue
                return NSAttributedString(string: content, attributes: next)
            },
            extraGroups: { match, original in
                var extras: [NSAttributedString.Key: Any] = [:]
                if match.numberOfRanges > 2 {
                    extras[.composerImageAlt] = (original as NSString).substring(with: match.range(at: 1))
                    extras[.composerImageURL] = (original as NSString).substring(with: match.range(at: 2))
                }
                return extras
            }
        )
        applyInline(
            pattern: #"\[([^\]]+)\]\((https?://[^\s)]+)\)"#,
            in: attributed,
            transform: { content, attrs in
                var next = attrs
                next[.foregroundColor] = ComposerTypography.accentColor
                next[.underlineStyle] = NSUnderlineStyle.single.rawValue
                return NSAttributedString(string: content, attributes: next)
            },
            extraGroups: { match, original in
                guard match.numberOfRanges > 2 else { return [:] }
                let url = (original as NSString).substring(with: match.range(at: 2))
                return [.link: url]
            }
        )
        applyInline(
            pattern: #"\*\*([^*\n]+)\*\*"#,
            in: attributed,
            transform: { content, attrs in
                var next = attrs
                let size = (attrs[.font] as? UIFont)?.pointSize ?? ComposerTypography.bodyFont.pointSize
                next[.font] = AppSettings.shared.contentFont(ofSize: size, weight: .bold)
                return NSAttributedString(string: content, attributes: next)
            }
        )
        applyInline(
            pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            in: attributed,
            transform: { content, attrs in
                var next = attrs
                let font = (attrs[.font] as? UIFont) ?? ComposerTypography.bodyFont
                next[.font] = italic(font)
                return NSAttributedString(string: content, attributes: next)
            }
        )
        applyInline(
            pattern: #"~~([^~\n]+)~~"#,
            in: attributed,
            transform: { content, attrs in
                var next = attrs
                next[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                return NSAttributedString(string: content, attributes: next)
            }
        )
        return attributed
    }

    private static func applyInline(
        pattern: String,
        in attributed: NSMutableAttributedString,
        transform: (_ content: String, _ base: [NSAttributedString.Key: Any]) -> NSAttributedString,
        extraGroups: ((NSTextCheckingResult, String) -> [NSAttributedString.Key: Any])? = nil
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let snapshot = attributed.string
        let matches = regex.matches(in: snapshot, range: NSRange(location: 0, length: attributed.length)).reversed()
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let full = match.range(at: 0)
            let contentRange = match.range(at: 1)
            guard full.location != NSNotFound, contentRange.location != NSNotFound else { continue }
            var base: [NSAttributedString.Key: Any] = [:]
            if attributed.length > 0 {
                base = attributed.attributes(at: min(contentRange.location, attributed.length - 1), effectiveRange: nil)
            }
            let content = (attributed.string as NSString).substring(with: contentRange)
            let replacement = NSMutableAttributedString(attributedString: transform(content, base))
            if let extraGroups {
                replacement.addAttributes(extraGroups(match, snapshot), range: NSRange(location: 0, length: replacement.length))
            }
            attributed.replaceCharacters(in: full, with: replacement)
        }
    }

    // MARK: - Serialize

    private static func serializeInlines(
        _ paragraph: String,
        attributesProvider: (Int) -> [NSAttributedString.Key: Any]
    ) -> String {
        let ns = paragraph as NSString
        guard ns.length > 0 else { return "" }
        var result = ""
        var index = 0
        while index < ns.length {
            let attrs = attributesProvider(index)
            var length = 1
            while index + length < ns.length {
                let next = attributesProvider(index + length)
                if inlineSignature(next) != inlineSignature(attrs) { break }
                length += 1
            }
            var piece = ns.substring(with: NSRange(location: index, length: length))
            piece = piece.replacingOccurrences(of: "\n", with: "")

            if let url = attrs[.composerImageURL] as? String {
                let alt = attrs[.composerImageAlt] as? String ?? piece
                piece = "![\(alt)](\(url))"
            } else if let link = linkString(attrs[.link]) {
                piece = "[\(piece)](\(link))"
            } else {
                let font = attrs[.font] as? UIFont
                let isBold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
                let isItalic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true
                let isCode = font?.fontName.lowercased().contains("mono") == true
                    || (attrs[.composerCodeLanguage] != nil && attrs[.composerHeadingLevel] == nil)
                let isStrike = (attrs[.strikethroughStyle] as? Int).map { $0 != 0 } ?? false
                if isCode, attrs[.composerCodeLanguage] == nil {
                    piece = "`\(piece)`"
                } else {
                    if isBold { piece = "**\(piece)**" }
                    if isItalic { piece = "*\(piece)*" }
                    if isStrike { piece = "~~\(piece)~~" }
                }
            }
            result += piece
            index += length
        }
        return result
    }

    private static func inlineSignature(_ attrs: [NSAttributedString.Key: Any]) -> String {
        let font = attrs[.font] as? UIFont
        let bold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
        let italic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true
        let strike = (attrs[.strikethroughStyle] as? Int) ?? 0
        let link = linkString(attrs[.link]) ?? ""
        let image = (attrs[.composerImageURL] as? String) ?? ""
        let code = font?.fontName.lowercased().contains("mono") == true
        return "\(bold)-\(italic)-\(strike)-\(link)-\(image)-\(code)"
    }

    private static func attributesAt(_ attributed: NSAttributedString, location: Int) -> [NSAttributedString.Key: Any] {
        guard attributed.length > 0 else { return [:] }
        let index = min(max(location, 0), attributed.length - 1)
        return attributed.attributes(at: index, effectiveRange: nil)
    }

    private static func linkString(_ value: Any?) -> String? {
        if let url = value as? URL { return url.absoluteString }
        if let string = value as? String { return string }
        return nil
    }

    private static func fenceLanguage(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func italic(_ font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) ?? font.fontDescriptor
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

private extension NSAttributedString {
    func enumerateParagraphs(
        _ body: (_ paragraph: String, _ start: Int, _ attributes: [NSAttributedString.Key: Any]) -> Void
    ) {
        let ns = string as NSString
        var location = 0
        while location < length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let paragraph = ns.substring(with: lineRange)
            let attrs = attributes(at: location, effectiveRange: nil)
            body(paragraph, location, attrs)
            let next = lineRange.location + lineRange.length
            if next <= location { break }
            location = next
        }
    }
}
