import XCTest
@testable import CookedHTML

final class InlineExtractorTests: XCTestCase {

    private func parseInlines(_ html: String) -> [InlineNode] {
        let blocks = CookedHTMLParser.parse(html: "<p>\(html)</p>")
        guard case .paragraph(let inlines) = blocks.first else { return [] }
        return inlines
    }

    // MARK: - Plain Text

    func testPlainText() {
        let inlines = parseInlines("Hello world")
        XCTAssertEqual(inlines, [.text("Hello world")])
    }

    // MARK: - Bold

    func testBold() {
        let inlines = parseInlines("<strong>bold</strong>")
        XCTAssertEqual(inlines, [.styledText("bold", .bold)])
    }

    func testBoldWithB() {
        let inlines = parseInlines("<b>bold</b>")
        XCTAssertEqual(inlines, [.styledText("bold", .bold)])
    }

    // MARK: - Italic

    func testItalic() {
        let inlines = parseInlines("<em>italic</em>")
        XCTAssertEqual(inlines, [.styledText("italic", .italic)])
    }

    // MARK: - Strikethrough

    func testStrikethrough() {
        let inlines = parseInlines("<s>deleted</s>")
        XCTAssertEqual(inlines, [.styledText("deleted", .strikethrough)])
    }

    func testDel() {
        let inlines = parseInlines("<del>deleted</del>")
        XCTAssertEqual(inlines, [.styledText("deleted", .strikethrough)])
    }

    // MARK: - Combined Styles

    func testBoldItalic() {
        let inlines = parseInlines("<strong><em>bold italic</em></strong>")
        let expected: TextStyle = [.bold, .italic]
        XCTAssertEqual(inlines, [.styledText("bold italic", expected)])
    }

    // MARK: - Links

    func testLink() {
        let inlines = parseInlines("<a href=\"https://example.com\">click</a>")
        XCTAssertEqual(inlines, [.link(href: "https://example.com", children: [.text("click")])])
    }

    func testLinkWithBaseURL() {
        let blocks = CookedHTMLParser.parse(html: "<p><a href=\"/t/123\">topic</a></p>", baseURL: "https://linux.do")
        guard case .paragraph(let inlines) = blocks.first else {
            XCTFail("Expected paragraph")
            return
        }
        if case .link(let href, _) = inlines.first {
            XCTAssertEqual(href, "https://linux.do/t/123")
        } else {
            XCTFail("Expected link")
        }
    }

    // MARK: - Inline Code

    func testInlineCode() {
        let inlines = parseInlines("<code>let x = 1</code>")
        XCTAssertEqual(inlines, [.code("let x = 1")])
    }

    // MARK: - Inline Image

    func testInlineImage() {
        let inlines = parseInlines("Hello <img src=\"emoji.png\" class=\"emoji\" alt=\":smile:\">")
        // Find the image node in the inlines
        let imageNode = inlines.first(where: {
            if case .image = $0 { return true }
            return false
        })
        if case .image(let src, let alt, _, _, let isEmoji) = imageNode {
            XCTAssertEqual(src, "emoji.png")
            XCTAssertEqual(alt, ":smile:")
            XCTAssertTrue(isEmoji)
        } else {
            XCTFail("Expected inline image, got \(inlines)")
        }
    }

    // MARK: - Line Break

    func testLineBreak() {
        let inlines = parseInlines("line1<br>line2")
        XCTAssertTrue(inlines.contains(.lineBreak))
    }

    // MARK: - Mixed Content

    func testMixedContent() {
        let inlines = parseInlines("Hello <strong>bold</strong> and <em>italic</em>")
        XCTAssertTrue(inlines.count >= 4) // text, styled, text, styled (with possible whitespace merging)
    }

    // MARK: - Text Merging

    func testAdjacentTextMerging() {
        // Nested spans should produce merged text
        let inlines = parseInlines("<span>a</span><span>b</span>")
        XCTAssertEqual(inlines, [.text("ab")])
    }

    // MARK: - Mention

    func testMention() {
        let inlines = parseInlines("<a class=\"mention\" href=\"/u/sam\">@sam</a>")
        XCTAssertEqual(inlines, [.mention(username: "sam", href: "/u/sam")])
    }

    func testMentionGroup() {
        let inlines = parseInlines("<a class=\"mention-group\" href=\"/g/admins\">@admins</a>")
        XCTAssertEqual(inlines, [.mentionGroup(name: "admins", href: "/g/admins")])
    }

    func testMentionInParagraph() {
        let inlines = parseInlines("Hello <a class=\"mention\" href=\"/u/sam\">@sam</a> how are you?")
        XCTAssertEqual(inlines, [
            .text("Hello "),
            .mention(username: "sam", href: "/u/sam"),
            .text(" how are you?"),
        ])
    }

    // MARK: - Hashtag

    func testHashtagCooked() {
        let inlines = parseInlines("<a class=\"hashtag-cooked\" href=\"/c/feature\" data-type=\"category\">#feature</a>")
        XCTAssertEqual(inlines, [.hashtag(text: "feature", href: "/c/feature", type: "category")])
    }

    func testHashtagLegacy() {
        let inlines = parseInlines("<a class=\"hashtag\" href=\"/tag/swift\">#swift</a>")
        XCTAssertEqual(inlines, [.hashtag(text: "swift", href: "/tag/swift", type: nil)])
    }

    // MARK: - Spoiler

    func testInlineSpoiler() {
        let inlines = parseInlines("<span class=\"spoiler\">secret</span>")
        XCTAssertEqual(inlines, [.spoiler(children: [.text("secret")])])
    }

    func testSpoilerWithStyledContent() {
        let inlines = parseInlines("<span class=\"spoiler\"><strong>bold secret</strong></span>")
        XCTAssertEqual(inlines, [.spoiler(children: [.styledText("bold secret", .bold)])])
    }
}
