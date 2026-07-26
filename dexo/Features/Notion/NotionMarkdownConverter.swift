import Foundation

enum NotionMarkdownConverter {
    private static let richTextMax = 1800
    private static let childrenPerRequest = 100

    static func blocks(from markdown: String) -> [[String: Any]] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [[String: Any]] = []
        var index = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            let text = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphBuffer.removeAll()
            guard !text.isEmpty else { return }
            // Extract markdown images as separate blocks.
            let imagePattern = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
            let ns = text as NSString
            var last = 0
            let matches = imagePattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty {
                blocks.append(paragraph(text))
                return
            }
            for match in matches {
                if match.range.location > last {
                    let chunk = ns.substring(with: NSRange(location: last, length: match.range.location - last))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chunk.isEmpty { blocks.append(paragraph(chunk)) }
                }
                if match.numberOfRanges >= 3,
                   let urlRange = Range(match.range(at: 2), in: text) {
                    let url = String(text[urlRange])
                    if url.hasPrefix("http") {
                        blocks.append(image(url: url))
                    } else {
                        blocks.append(paragraph(ns.substring(with: match.range)))
                    }
                }
                last = match.range.location + match.range.length
            }
            if last < ns.length {
                let tail = ns.substring(from: last).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { blocks.append(paragraph(tail)) }
            }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(codeBlock(codeLines.joined(separator: "\n"), language: lang.isEmpty ? "plain text" : lang))
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                blocks.append(["object": "block", "type": "divider", "divider": [:]])
                index += 1
                continue
            }

            if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(heading(1, String(trimmed.dropFirst(2))))
                index += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(heading(2, String(trimmed.dropFirst(3))))
                index += 1
                continue
            }
            if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(heading(3, String(trimmed.dropFirst(4))))
                index += 1
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                var quoteLines: [String] = [String(trimmed.dropFirst(2))]
                index += 1
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    quoteLines.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    index += 1
                }
                blocks.append(quote(quoteLines.joined(separator: "\n")))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                while index < lines.count {
                    let t = lines[index].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("- ") || t.hasPrefix("* ") else { break }
                    blocks.append(bulleted(String(t.dropFirst(2))))
                    index += 1
                }
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            paragraphBuffer.append(line)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    static func chunked(_ blocks: [[String: Any]], size: Int = childrenPerRequest) -> [[[String: Any]]] {
        guard !blocks.isEmpty else { return [] }
        var result: [[[String: Any]]] = []
        var i = 0
        while i < blocks.count {
            let end = min(i + size, blocks.count)
            result.append(Array(blocks[i..<end]))
            i = end
        }
        return result
    }

    // MARK: - Block builders

    private static func richText(_ text: String) -> [[String: Any]] {
        let pieces = split(text, max: richTextMax)
        return pieces.map { piece in
            [
                "type": "text",
                "text": ["content": piece],
            ]
        }
    }

    private static func split(_ text: String, max: Int) -> [String] {
        guard text.count > max else { return [text] }
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: max, limitedBy: text.endIndex) ?? text.endIndex
            out.append(String(text[start..<end]))
            start = end
        }
        return out
    }

    private static func paragraph(_ text: String) -> [String: Any] {
        ["object": "block", "type": "paragraph", "paragraph": ["rich_text": richText(text)]]
    }

    private static func heading(_ level: Int, _ text: String) -> [String: Any] {
        let key = level == 1 ? "heading_1" : (level == 2 ? "heading_2" : "heading_3")
        return ["object": "block", "type": key, key: ["rich_text": richText(text)]]
    }

    private static func quote(_ text: String) -> [String: Any] {
        ["object": "block", "type": "quote", "quote": ["rich_text": richText(text)]]
    }

    private static func bulleted(_ text: String) -> [String: Any] {
        ["object": "block", "type": "bulleted_list_item", "bulleted_list_item": ["rich_text": richText(text)]]
    }

    private static func codeBlock(_ text: String, language: String) -> [String: Any] {
        [
            "object": "block",
            "type": "code",
            "code": [
                "rich_text": richText(text.isEmpty ? " " : text),
                "language": language.lowercased(),
            ],
        ]
    }

    private static func image(url: String) -> [String: Any] {
        [
            "object": "block",
            "type": "image",
            "image": [
                "type": "external",
                "external": ["url": url],
            ],
        ]
    }
}
