import XCTest
@testable import Doer

@MainActor
final class CookedContentPipelineTests: XCTestCase {
    func testPlainTextNeverReturnsHTMLTags() {
        let cooked = "<p>Hello <strong>world</strong></p><p>Line two</p>"
        let text = CookedContentPipeline.plainText(fromCooked: cooked)
        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("world"))
        XCTAssertFalse(text.contains("<p>"))
        XCTAssertFalse(text.contains("<strong>"))
    }

    func testMarkdownKeepsCodeFence() {
        let cooked = #"<pre><code class="lang-swift">print(1)</code></pre>"#
        let md = CookedContentPipeline.markdown(fromCooked: cooked)
        XCTAssertTrue(md.contains("print(1)"), md)
        // Prefer fenced output when parser recognizes code blocks.
        XCTAssertFalse(md.contains("<pre>"), md)
    }

    func testBlocksParseNonEmpty() {
        let cooked = "<p>Only paragraph</p>"
        let blocks = CookedContentPipeline.blocks(fromCooked: cooked)
        XCTAssertFalse(blocks.isEmpty)
    }

    func testPlainTextPreviewIsSingleLine() {
        let cooked = "<p>Hello</p><p>World<br>again</p>"
        let preview = CookedContentPipeline.plainTextPreview(fromCooked: cooked)
        XCTAssertFalse(preview.contains("\n"), preview)
        XCTAssertTrue(preview.contains("Hello"), preview)
        XCTAssertTrue(preview.contains("World"), preview)
        XCTAssertFalse(preview.contains("<p>"), preview)
    }

    func testHighlightedPreviewKeepsSearchHighlightClean() {
        let headline = #"Hello <span class="search-highlight">world</span> and <em>flux</em>"#
        let attr = CookedContentPipeline.highlightedPreview(
            fromCooked: headline,
            font: .systemFont(ofSize: 15, weight: .semibold),
            textColor: .label
        )
        let plain = attr.string
        XCTAssertEqual(plain, "Hello world and flux")
        XCTAssertFalse(plain.contains("<"))
        XCTAssertFalse(plain.contains("span"))

        var sawHighlight = false
        attr.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            if value != nil { sawHighlight = true }
        }
        XCTAssertTrue(sawHighlight, "expected highlighted ranges for search-highlight / em")
    }

    func testHighlightedPreviewStripsTagsWhenNoHighlight() {
        let headline = "Plain <b>title</b> only"
        let attr = CookedContentPipeline.highlightedPreview(
            fromCooked: headline,
            font: .systemFont(ofSize: 15, weight: .semibold),
            textColor: .label
        )
        XCTAssertEqual(attr.string, "Plain title only")
        XCTAssertFalse(attr.string.contains("<"))
    }
}
