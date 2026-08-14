import XCTest
@testable import Doer

final class ComposerMarkdownCodecTests: XCTestCase {
    func testComposerBodyFontMatchesTopicMarkdown() {
        XCTAssertEqual(
            ComposerTypography.bodyFont.pointSize,
            TopicDetailTypography.bodyContentFont().pointSize,
            accuracy: 0.01
        )
    }

    func testPlainParagraphRoundTrip() {
        assertRoundTrip("hello world")
    }

    func testBoldItalicStrikeRoundTrip() {
        assertRoundTrip("hello **bold** and *italic* and ~~strike~~")
    }

    func testHeadingAndQuoteRoundTrip() {
        let raw = "# Title\n\n> quoted"
        let attributed = ComposerMarkdownCodec.richAttributedString(from: raw)
        let back = ComposerMarkdownCodec.markdown(from: attributed)
        XCTAssertTrue(back.contains("Title"))
        XCTAssertTrue(back.contains("quoted"))
        XCTAssertTrue(back.contains("#"))
    }

    func testDiscourseQuoteCardRoundTrip() {
        let raw = DiscourseQuoteMarkdown.make(
            username: "alice",
            postNumber: 7,
            topicId: 42,
            excerpt: "hello world"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let attributed = ComposerMarkdownCodec.richAttributedString(from: raw)
        let back = ComposerMarkdownCodec.markdown(from: attributed)
        XCTAssertTrue(back.contains("[quote="))
        XCTAssertTrue(back.contains("hello world"))
        XCTAssertTrue(back.contains("[/quote]"))
    }

    func testFencedCodeRoundTrip() {
        let raw = "```swift\nlet a = 1\n```"
        let attributed = ComposerMarkdownCodec.richAttributedString(from: raw)
        let back = ComposerMarkdownCodec.markdown(from: attributed)
        XCTAssertTrue(back.contains("```"))
        XCTAssertTrue(back.contains("let a = 1"))
    }

    func testRichHidesMarkdownMarkers() {
        let attributed = ComposerMarkdownCodec.richAttributedString(from: "**hello**")
        XCTAssertFalse(attributed.string.contains("**"))
        XCTAssertTrue(attributed.string.contains("hello"))
    }

    private func assertRoundTrip(_ raw: String) {
        let attributed = ComposerMarkdownCodec.richAttributedString(from: raw)
        let back = ComposerMarkdownCodec.markdown(from: attributed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(back, raw)
    }
}
