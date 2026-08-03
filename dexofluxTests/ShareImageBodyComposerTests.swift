import XCTest
@testable import dexoflux

final class ShareImageBodyComposerTests: XCTestCase {
    func testTextOnlyPost() {
        let html = "<p>Hello <b>world</b></p>"
        let segments = ShareImageBodyComposer.segments(from: html, baseURL: "https://example.com")
        XCTAssertEqual(segments.count, 1)
        let text = readableText(segments[0])
        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("world"))
        // Must not keep markdown markers from cooked HTML.
        XCTAssertFalse(text.contains("**"))
    }

    func testImageAndTextOrder() {
        let html = """
        <p>before</p>
        <p><img src="/uploads/a.png" alt=""></p>
        <p>after</p>
        """
        let segments = ShareImageBodyComposer.segments(from: html, baseURL: "https://linux.do")
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(readableText(segments[0]), "before")
        guard case .image(let url) = segments[1] else { return XCTFail("image") }
        XCTAssertEqual(readableText(segments[2]), "after")
        XCTAssertEqual(url.absoluteString, "https://linux.do/uploads/a.png")
    }

    func testMaxImagesFootnote() {
        let imgs = (1...8).map { "<p><img src=\"/u/\($0).png\"></p>" }.joined()
        let segments = ShareImageBodyComposer.segments(from: imgs, baseURL: "https://linux.do")
        let images = segments.compactMap { seg -> URL? in
            if case .image(let url) = seg { return url }
            return nil
        }
        XCTAssertEqual(images.count, ShareImageBodyComposer.maxImages)
        guard case .moreImages(let count) = segments.last else {
            return XCTFail("expected moreImages footnote")
        }
        XCTAssertEqual(count, 2)
    }

    func testBareImageLinkBecomesImage() {
        let html = #"<p><a href="https://cdn.example.com/pic.jpg">https://cdn.example.com/pic.jpg</a></p>"#
        let segments = ShareImageBodyComposer.segments(from: html, baseURL: "https://linux.do")
        XCTAssertTrue(segments.contains { if case .image = $0 { return true }; return false })
    }

    func testResolveRelativeURL() {
        let url = ShareImageBodyComposer.resolveURL("/uploads/x.png", baseURL: "https://linux.do")
        XCTAssertEqual(url?.absoluteString, "https://linux.do/uploads/x.png")
    }

    func testMarkdownSourceIsConvertedToReadableText() {
        let markdown = """
        # Hello
        **bold** and [link](https://example.com)
        """
        let segments = ShareImageBodyComposer.segments(from: markdown, baseURL: "https://linux.do")
        let text = segments.map(readableText).joined(separator: "\n")
        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("bold"))
        XCTAssertTrue(text.contains("link"))
        XCTAssertFalse(text.contains("**"))
        XCTAssertFalse(text.contains("]("))
        XCTAssertFalse(text.contains("# Hello"))
    }

    func testHTMLWithEmbeddedMarkdownMarkersIsSanitized() {
        // Some posts keep uncooked markers inside <p> text nodes.
        let html = "<p>这是 **加粗** 和 [标题](https://example.com) 内容</p>"
        let segments = ShareImageBodyComposer.segments(from: html, baseURL: "https://linux.do")
        let text = segments.map(readableText).joined(separator: "\n")
        XCTAssertTrue(text.contains("加粗"), text)
        XCTAssertTrue(text.contains("标题"), text)
        XCTAssertFalse(text.contains("**"), text)
        XCTAssertFalse(text.contains("]("), text)
    }

    func testSanitizeStripsHeadingAndListMarkers() {
        let raw = "# 标题\n- 一项\n1. 二项\n> 引用"
        let cleaned = ShareImageBodyComposer.stripMarkdownArtifacts(raw)
        XCTAssertFalse(cleaned.contains("# 标题"), cleaned)
        XCTAssertTrue(cleaned.contains("标题"), cleaned)
        XCTAssertTrue(cleaned.contains("一项"), cleaned)
        XCTAssertFalse(cleaned.hasPrefix(">"), cleaned)
    }

    /// Regression: linux.do 公益推广 checklist leaves unpaired `**` on each line.
    func testUnpairedBoldMarkersInListAreStripped() {
        let html = """
        <p>本帖使用社区公益推广</p>
        <ul>
        <li>**我的项目是免费使用的，无收费部分： 是</li>
        <li>**我的帖子已经打上 公益推广 标签： 是</li>
        <li>**我的项目属于个人项目： 是</li>
        </ul>
        """
        let segments = ShareImageBodyComposer.segments(from: html, baseURL: "https://linux.do")
        let text = segments.map(readableText).joined(separator: "\n")
        XCTAssertTrue(text.contains("我的项目是免费使用的"), text)
        XCTAssertTrue(text.contains("公益推广"), text)
        XCTAssertFalse(text.contains("**"), "must not paint unpaired ** — got:\n\(text)")
        XCTAssertTrue(text.contains("•"), text)
    }

    func testStripMarkdownRemovesLoneAsterisks() {
        let cleaned = ShareImageBodyComposer.stripMarkdownArtifacts("• **我的项目： 是")
        XCTAssertEqual(cleaned, "• 我的项目： 是")
        XCTAssertFalse(cleaned.contains("*"))
    }

    private func readableText(_ segment: ShareImageBodySegment) -> String {
        switch segment {
        case .text(let text):
            return text
        case .richText(let attr):
            return attr.string
        case .image, .moreImages:
            return ""
        }
    }
}
