import XCTest
@testable import dexoflux

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
}
