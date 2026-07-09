import XCTest
@testable import CookedHTML

final class BlockExtractorTests: XCTestCase {

    // MARK: - Paragraph

    func testSimpleParagraph() {
        let html = "<p>Hello world</p>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let inlines) = blocks[0] {
            XCTAssertEqual(inlines, [.text("Hello world")])
        } else {
            XCTFail("Expected paragraph, got \(blocks[0])")
        }
    }

    func testMultipleParagraphs() {
        let html = "<p>First</p><p>Second</p>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 2)
    }

    // MARK: - Headings

    func testHeadings() {
        let html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 3)

        if case .heading(let level, let content) = blocks[0] {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(content, [.text("Title")])
        } else {
            XCTFail("Expected h1")
        }

        if case .heading(let level, _) = blocks[1] {
            XCTAssertEqual(level, 2)
        } else {
            XCTFail("Expected h2")
        }
    }

    // MARK: - Code Block

    func testCodeBlock() {
        let html = """
        <pre><code class="lang-swift">let x = 42</code></pre>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .codeBlock(let lang, let code) = blocks[0] {
            XCTAssertEqual(lang, "swift")
            XCTAssertEqual(code, "let x = 42")
        } else {
            XCTFail("Expected codeBlock, got \(blocks[0])")
        }
    }

    func testCodeBlockNoLanguage() {
        let html = "<pre><code>plain code</code></pre>"
        let blocks = CookedHTMLParser.parse(html: html)
        if case .codeBlock(let lang, let code) = blocks[0] {
            XCTAssertNil(lang)
            XCTAssertEqual(code, "plain code")
        } else {
            XCTFail("Expected codeBlock")
        }
    }

    func testMermaidDivExtractsAsCodeBlock() {
        let html = """
        <div class="mermaid" id="flowchart-linux-do">
        flowchart TD
            User[用户] --> CF[Cloudflare<br>CDN]
        </div>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .codeBlock(let lang, let code) = blocks[0] {
            XCTAssertEqual(lang, "mermaid")
            XCTAssertTrue(code.contains("flowchart TD"))
            XCTAssertTrue(code.contains("Cloudflare"))
        } else {
            XCTFail("Expected mermaid codeBlock")
        }
    }

    // MARK: - Blockquote

    func testBlockquote() {
        let html = "<blockquote><p>Quoted text</p></blockquote>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .blockquote(let inner) = blocks[0] {
            XCTAssertEqual(inner.count, 1)
            if case .paragraph(let inlines) = inner[0] {
                XCTAssertEqual(inlines, [.text("Quoted text")])
            }
        } else {
            XCTFail("Expected blockquote")
        }
    }

    // MARK: - Divider

    func testHorizontalRule() {
        let html = "<p>Before</p><hr><p>After</p>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1], .divider)
    }

    // MARK: - Image

    func testStandaloneImage() {
        let html = "<p><img src=\"/uploads/test.png\" alt=\"test\" width=\"100\" height=\"50\"></p>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .image(let src, let alt, let w, let h, _) = blocks[0] {
            XCTAssertEqual(src, "/uploads/test.png")
            XCTAssertEqual(alt, "test")
            XCTAssertEqual(w, 100)
            XCTAssertEqual(h, 50)
        } else {
            XCTFail("Expected image, got \(blocks[0])")
        }
    }

    func testImageWithBaseURL() {
        let html = "<p><img src=\"/uploads/test.png\"></p>"
        let blocks = CookedHTMLParser.parse(html: html, baseURL: "https://linux.do")
        if case .image(let src, _, _, _, _) = blocks[0] {
            XCTAssertEqual(src, "https://linux.do/uploads/test.png")
        } else {
            XCTFail("Expected image")
        }
    }

    // MARK: - Details

    func testDetails() {
        let html = """
        <details>
            <summary>Click me</summary>
            <p>Hidden content</p>
        </details>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .details(let summary, let content) = blocks[0] {
            XCTAssertEqual(summary, [.text("Click me")])
            XCTAssertEqual(content.count, 1)
        } else {
            XCTFail("Expected details, got \(blocks[0])")
        }
    }

    // MARK: - Empty/Whitespace

    func testEmptyParagraphsAreSkipped() {
        let html = "<p>   </p><p>Real content</p>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
    }

    func testLineBreakOnlyParagraphsAreSkipped() {
        let html = "<p>Before</p><p><br></p><p><br><br></p><p>After</p>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .paragraph([.text("Before")]))
        XCTAssertEqual(blocks[1], .paragraph([.text("After")]))
    }

    func testConsecutiveLineBreaksAreCollapsedInsideParagraph() {
        let html = "<p>First<br><br><br>Second</p>"
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let inlines) = blocks[0] else {
            XCTFail("Expected paragraph, got \(blocks[0])")
            return
        }
        XCTAssertEqual(inlines, [.text("First"), .lineBreak, .text("Second")])
    }

    // MARK: - Spoiler

    func testBlockSpoiler() {
        let html = """
        <div class="spoiler">
        <p>此文本将被模糊处理</p>
        </div>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .spoiler(let inner) = blocks[0] {
            XCTAssertEqual(inner.count, 1)
            if case .paragraph(let inlines) = inner[0] {
                XCTAssertEqual(inlines, [.text("此文本将被模糊处理")])
            } else {
                XCTFail("Expected paragraph inside spoiler, got \(inner[0])")
            }
        } else {
            XCTFail("Expected .spoiler block, got \(blocks[0])")
        }
    }

    func testBlockSpoilerWithMultipleChildren() {
        let html = """
        <div class="spoiler">
        <p>First hidden paragraph</p>
        <p>Second hidden paragraph</p>
        </div>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .spoiler(let inner) = blocks[0] {
            XCTAssertEqual(inner.count, 2)
            for block in inner {
                if case .paragraph = block {
                    // OK
                } else {
                    XCTFail("Expected paragraph, got \(block)")
                }
            }
        } else {
            XCTFail("Expected .spoiler block, got \(blocks[0])")
        }
    }

    func testBlockSpoilerWithList() {
        let html = """
        <div class="spoiler">
        <ol>
        <li>First item</li>
        <li>Second item</li>
        </ol>
        </div>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .spoiler(let inner) = blocks[0] {
            XCTAssertEqual(inner.count, 1)
            if case .list(let ordered, let items) = inner[0] {
                XCTAssertTrue(ordered)
                XCTAssertEqual(items.count, 2)
            } else {
                XCTFail("Expected list inside spoiler, got \(inner[0])")
            }
        } else {
            XCTFail("Expected .spoiler block, got \(blocks[0])")
        }
    }

    // MARK: - Poll

    func testDiscoursePollDoesNotBecomeList() {
        let html = """
        <div class="poll" data-poll-name="poll" data-poll-type="regular" data-poll-status="open">
          <div class="poll-container">
            <ul>
              <li data-poll-option-id="18-23"><p>18-23</p></li>
              <li data-poll-option-id="24-29"><p>24-29</p></li>
              <li data-poll-option-id="30-35"><p>30-35</p></li>
              <li data-poll-option-id="35+"><p>35+</p></li>
            </ul>
          </div>
          <div class="poll-info">
            <span class="info-number">0</span>
            <span class="info-label">投票人</span>
          </div>
        </div>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .poll(let poll) = blocks[0] {
            XCTAssertEqual(poll.name, "poll")
            XCTAssertEqual(poll.options.map(\.text), ["18-23", "24-29", "30-35", "35+"])
            XCTAssertEqual(poll.votersText, "0 投票人")
            XCTAssertEqual(poll.status, "open")
        } else {
            XCTFail("Expected poll block, got \(blocks)")
        }
    }

    func testDiscoursePollParsesVoteMetadata() {
        let html = """
        <div class="poll" data-poll-name="poll" data-poll-type="regular" data-poll-status="open" data-poll-public="true" data-poll-results="always" data-poll-min="1" data-poll-max="1">
          <div class="poll-container">
            <ul>
              <li class="chosen" data-poll-option-id="alpha" data-poll-option-votes="8">
                <p>Alpha</p>
                <span class="percentage">80%</span>
              </li>
              <li data-poll-option-id="beta" data-poll-option-votes="2">
                <p>Beta</p>
                <span class="percentage">20%</span>
              </li>
            </ul>
          </div>
          <div class="poll-info">
            <span class="info-number">10</span>
            <span class="info-label">投票人</span>
          </div>
        </div>
        """
        let blocks = CookedHTMLParser.parse(html: html)
        XCTAssertEqual(blocks.count, 1)
        if case .poll(let poll) = blocks[0] {
            XCTAssertEqual(poll.name, "poll")
            XCTAssertEqual(poll.votersText, "10 投票人")
            XCTAssertEqual(poll.votersCount, 10)
            XCTAssertEqual(poll.minSelections, 1)
            XCTAssertEqual(poll.maxSelections, 1)
            XCTAssertEqual(poll.resultsMode, "always")
            XCTAssertTrue(poll.isPublic)
            XCTAssertEqual(poll.options[0].id, "alpha")
            XCTAssertEqual(poll.options[0].voteCount, 8)
            XCTAssertEqual(poll.options[0].percentageText, "80%")
            XCTAssertTrue(poll.options[0].isSelected)
            XCTAssertEqual(poll.options[1].id, "beta")
            XCTAssertEqual(poll.options[1].voteCount, 2)
            XCTAssertEqual(poll.options[1].percentageText, "20%")
            XCTAssertFalse(poll.options[1].isSelected)
        } else {
            XCTFail("Expected poll block, got \(blocks)")
        }
    }

    // MARK: - Lightbox + inline text

    func testLightboxFollowedByTextAndEmoji() {
        let html = "<p><div class=\"lightbox-wrapper\"><a class=\"lightbox\" href=\"https://cdn3.linux.do/original/img.jpeg\"><img src=\"https://cdn3.linux.do/optimized/img_245x500.jpeg\" alt=\"Screenshot\" width=\"245\" height=\"500\"><div class=\"meta\"></div></a></div><br>\n点开看到它了，这下真是全民<img src=\"https://cdn.linux.do/images/emoji/twemoji/lobster.png?v=15\" class=\"emoji\" alt=\"lobster\" width=\"20\" height=\"20\">了，微信那么庞大用户</p>"
        let blocks = CookedHTMLParser.parse(html: html)
        for (i, b) in blocks.enumerated() { print("Block \(i): \(b)") }
        // Should be: image block + single paragraph (text + emoji + text)
        XCTAssertEqual(blocks.count, 2, "Expected image + paragraph, got \(blocks.count) blocks: \(blocks)")
        if case .paragraph(let inlines) = blocks[1] {
            // Last inline should be the text after emoji
            if case .text(let t) = inlines.last {
                XCTAssertEqual(t, "了，微信那么庞大用户")
            } else {
                XCTFail("Last inline should be trailing text, got \(inlines)")
            }
        } else {
            XCTFail("Block 1 should be paragraph, got \(blocks[1])")
        }
    }

    func testImageSourceURLsCollectsNestedContentImages() {
        let html = """
        <p>inline <img src="/emoji.png" width="20" height="20"></p>
        <blockquote><p><img src="/quote.png"></p></blockquote>
        <details><summary>more</summary><p><img src="/details.png"></p></details>
        <aside class="onebox">
            <header class="source"><a href="https://example.com">example.com</a></header>
            <article class="onebox-body">
                <img src="/onebox.png">
                <h3><a href="https://example.com">Example</a></h3>
            </article>
        </aside>
        """
        let blocks = CookedHTMLParser.parse(html: html, baseURL: "https://linux.do")

        XCTAssertEqual(blocks.flatMap(\.imageSourceURLs), [
            "https://linux.do/emoji.png",
            "https://linux.do/quote.png",
            "https://linux.do/details.png",
            "https://linux.do/onebox.png",
        ])
    }
}
