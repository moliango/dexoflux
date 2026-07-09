import XCTest
@testable import CookedHTML

final class IntegrationTests: XCTestCase {

    // MARK: - Discourse Quote

    func testDiscourseQuote() {
        let html = """
        <aside class="quote" data-username="john" data-post="25">
            <div class="title">
                <img src="/user_avatar/linux.do/john/48/123.png" class="avatar"> john:
            </div>
            <blockquote>
                <p>This is a quoted reply.</p>
            </blockquote>
        </aside>
        """
        let blocks = CookedHTMLParser.parse(html: html, baseURL: "https://linux.do")
        XCTAssertEqual(blocks.count, 1)
        if case .discourseQuote(let username, let avatarURL, _, _, _, _, let quotePostNumber, let content) = blocks[0] {
            XCTAssertEqual(username, "john")
            XCTAssertNotNil(avatarURL)
            XCTAssertTrue(avatarURL?.contains("john") ?? false)
            XCTAssertEqual(quotePostNumber, 25)
            XCTAssertFalse(content.isEmpty)
        } else {
            XCTFail("Expected discourseQuote, got \(blocks[0])")
        }
    }

    func testDiscourseQuoteBuildsTopicURLFromDataTopic() {
        let html = """
        <aside class="quote" data-username="jane" data-topic="12345" data-post="7">
            <div class="title">jane:</div>
            <blockquote><p>Quoted from another topic.</p></blockquote>
        </aside>
        """
        let blocks = CookedHTMLParser.parse(html: html, baseURL: "https://linux.do")
        if case .discourseQuote(_, _, _, let topicURL, _, _, let quotePostNumber, _) = blocks[0] {
            XCTAssertEqual(quotePostNumber, 7)
            XCTAssertEqual(topicURL, "https://linux.do/t/12345/7")
        } else {
            XCTFail("Expected discourseQuote, got \(blocks[0])")
        }
    }

    func testDiscourseQuoteFallbackTopicURLFromTitleLink() {
        let html = """
        <aside class="quote" data-username="jane" data-post="7">
            <div class="title"><a href="/t/some-topic/12345/7">Some topic</a></div>
            <blockquote><p>Quoted from another topic.</p></blockquote>
        </aside>
        """
        let blocks = CookedHTMLParser.parse(html: html, baseURL: "https://linux.do")
        if case .discourseQuote(_, _, let topicTitle, let topicURL, _, _, let quotePostNumber, _) = blocks[0] {
            XCTAssertEqual(topicTitle, "Some topic")
            XCTAssertEqual(topicURL, "https://linux.do/t/some-topic/12345/7")
            XCTAssertEqual(quotePostNumber, 7)
        } else {
            XCTFail("Expected discourseQuote, got \(blocks[0])")
        }
    }

    // MARK: - Onebox

    func testOnebox() {
        let html = """
        <aside class="onebox">
            <header class="source">
                <a href="https://github.com/test/repo">github.com</a>
            </header>
            <article class="onebox-body">
                <h3><a href="https://github.com/test/repo">Test Repo</a></h3>
                <p>A test repository</p>
            </article>
        </aside>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .onebox(let sourceURL, let title, let desc, _, _, _, _) = blocks[0] {
            XCTAssertEqual(sourceURL, "https://github.com/test/repo")
            XCTAssertEqual(title, "Test Repo")
            XCTAssertEqual(desc, "A test repository")
        } else {
            XCTFail("Expected onebox, got \(blocks[0])")
        }
    }

    // MARK: - Table

    func testTable() {
        let html = """
        <table>
            <thead><tr><th>Name</th><th>Value</th></tr></thead>
            <tbody>
                <tr><td>A</td><td>1</td></tr>
                <tr><td>B</td><td>2</td></tr>
            </tbody>
        </table>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .table(let headers, let rows) = blocks[0] {
            XCTAssertEqual(headers.count, 2)
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0].count, 2)
            // Headers are now [ContentBlock]; first header should be paragraph("Name")
            if case .paragraph(let inlines) = headers[0].first {
                XCTAssertEqual(inlines, [.text("Name")])
            } else {
                XCTFail("Expected paragraph in header, got \(headers[0])")
            }
        } else {
            XCTFail("Expected table, got \(blocks[0])")
        }
    }

    // MARK: - md-table wrapper

    func testMdTableWrapper() {
        let html = """
        <div class="md-table">
            <table>
                <thead>
                    <tr>
                        <th>Feature</th>
                        <th>Description</th>
                        <th>Link</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td><strong>Bold Feature</strong></td>
                        <td>A <em>fancy</em> description</td>
                        <td><a href="https://example.com">Visit</a></td>
                    </tr>
                    <tr>
                        <td><img src="/uploads/icon.png" alt="icon"></td>
                        <td>Row with image</td>
                        <td>Plain text</td>
                    </tr>
                </tbody>
            </table>
        </div>
        """
        let blocks = CookedHTMLParser.parse(html: html, baseURL: "https://linux.do")
        XCTAssertEqual(blocks.count, 1, "md-table div should produce a single .table block")

        guard case .table(let headers, let rows) = blocks[0] else {
            XCTFail("Expected .table, got \(blocks[0])")
            return
        }

        // Headers — cells are [ContentBlock], text is wrapped in .paragraph
        XCTAssertEqual(headers.count, 3)
        if case .paragraph(let inlines) = headers[0].first {
            XCTAssertEqual(inlines, [.text("Feature")])
        } else {
            XCTFail("Expected paragraph header, got \(headers[0])")
        }

        // Rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 3)
        XCTAssertEqual(rows[1].count, 3)

        // First row, first cell: bold text in paragraph
        if case .paragraph(let inlines) = rows[0][0].first,
           case .styledText(let t, .bold) = inlines.first {
            XCTAssertEqual(t, "Bold Feature")
        } else {
            XCTFail("Expected paragraph with bold text in row 0 col 0, got \(rows[0][0])")
        }

        // First row, third cell: link in paragraph
        if case .paragraph(let inlines) = rows[0][2].first,
           case .link(let href, _) = inlines.first {
            XCTAssertEqual(href, "https://example.com")
        } else {
            XCTFail("Expected paragraph with link in row 0 col 2, got \(rows[0][2])")
        }

        // Second row, first cell: image (block-level, not inline)
        if case .image(let src, _, _, _, _) = rows[1][0].first {
            XCTAssertTrue(src.hasPrefix("https://linux.do"), "Image src should be resolved to absolute URL")
        } else if case .paragraph(let inlines) = rows[1][0].first,
                  case .image(let src, _, _, _, _) = inlines.first {
            XCTAssertTrue(src.hasPrefix("https://linux.do"), "Image src should be resolved to absolute URL")
        } else {
            XCTFail("Expected image in row 1 col 0, got \(rows[1][0])")
        }
    }

    // MARK: - List

    func testUnorderedList() {
        let html = """
        <ul>
            <li>Item 1</li>
            <li>Item 2</li>
            <li>Item 3</li>
        </ul>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .list(let ordered, let items) = blocks[0] {
            XCTAssertFalse(ordered)
            XCTAssertEqual(items.count, 3)
        } else {
            XCTFail("Expected list, got \(blocks[0])")
        }
    }

    func testOrderedList() {
        let html = """
        <ol>
            <li>First</li>
            <li>Second</li>
        </ol>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        if case .list(let ordered, let items) = blocks[0] {
            XCTAssertTrue(ordered)
            XCTAssertEqual(items.count, 2)
        } else {
            XCTFail("Expected ordered list")
        }
    }

    func testNestedList() {
        let html = """
        <ul>
            <li>Parent
                <ul>
                    <li>Child 1</li>
                    <li>Child 2</li>
                </ul>
            </li>
        </ul>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        if case .list(_, let items) = blocks[0] {
            XCTAssertEqual(items.count, 1)
            XCTAssertFalse(items[0].children.isEmpty, "Expected nested list in children")
        } else {
            XCTFail("Expected list")
        }
    }

    // MARK: - Complex Post

    func testComplexPost() {
        let html = """
        <p>Hello <strong>everyone</strong>,</p>
        <p>Here is a code example:</p>
        <pre><code class="lang-python">print("hello")</code></pre>
        <blockquote><p>Some wisdom</p></blockquote>
        <ul><li>Point 1</li><li>Point 2</li></ul>
        <hr>
        <p>The end.</p>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertTrue(blocks.count >= 6, "Expected at least 6 blocks, got \(blocks.count)")

        // Verify block types in order
        if case .paragraph = blocks[0] {} else { XCTFail("Expected paragraph at 0") }
        if case .paragraph = blocks[1] {} else { XCTFail("Expected paragraph at 1") }
        if case .codeBlock = blocks[2] {} else { XCTFail("Expected codeBlock at 2") }
        if case .blockquote = blocks[3] {} else { XCTFail("Expected blockquote at 3") }
        if case .list = blocks[4] {} else { XCTFail("Expected list at 4") }
    }

    // MARK: - URL Resolution

    func testRelativeURLsResolved() {
        let html = """
        <p><a href="/t/topic/123">link</a></p>
        <p><img src="/uploads/image.png"></p>
        """
        let blocks = CookedHTMLParser.parse(html: html, baseURL: "https://linux.do")

        if case .paragraph(let inlines) = blocks[0],
           case .link(let href, _) = inlines.first {
            XCTAssertTrue(href.hasPrefix("https://linux.do"))
        } else {
            XCTFail("Expected resolved link")
        }
    }

    // MARK: - Empty HTML

    func testEmptyHTML() {
        let blocks = CookedHTMLParser.parse(html: "")
        XCTAssertTrue(blocks.isEmpty)
    }

    // MARK: - Raw HTML Fallback

    func testInvalidHTMLDoesNotCrash() {
        let html = "<div><p>Unclosed <strong>tag"
        let blocks = CookedHTMLParser.parse(html: html)
        // Should not crash and should produce some output
        XCTAssertFalse(blocks.isEmpty)
    }
}
