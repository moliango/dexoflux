import CookedHTML
import XCTest

final class CookedTextExporterTests: XCTestCase {
    func testPlainTextStripsTagsAndKeepsParagraphs() {
        let html = "<p>Hello <b>world</b></p><p>Second</p>"
        let text = CookedTextExporter.plainText(fromHTML: html)
        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("world"))
        XCTAssertFalse(text.contains("<p>"))
        XCTAssertFalse(text.contains("<b>"))
    }

    func testMarkdownCodeFence() {
        let html = #"<pre><code class="lang-swift">let x = 1</code></pre>"#
        let md = CookedTextExporter.markdown(fromHTML: html)
        XCTAssertTrue(md.contains("```"), md)
        XCTAssertTrue(md.contains("let x = 1"), md)
    }

    func testListBecomesBullets() {
        let html = "<ul><li>One</li><li>Two</li></ul>"
        let text = CookedTextExporter.plainText(fromHTML: html)
        XCTAssertTrue(text.contains("One"))
        XCTAssertTrue(text.contains("Two"))
    }

    func testNeverEmitsRawScriptTags() {
        let html = "<p>Safe</p><script>alert(1)</script>"
        let text = CookedTextExporter.plainText(fromHTML: html)
        XCTAssertFalse(text.contains("<script"))
    }
}
