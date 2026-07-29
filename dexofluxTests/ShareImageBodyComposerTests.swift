import XCTest
@testable import dexoflux

final class ShareImageBodyComposerTests: XCTestCase {
    func testTextOnlyPost() {
        let html = "<p>Hello <b>world</b></p>"
        let segments = ShareImageBodyComposer.segments(from: html, baseURL: "https://example.com")
        XCTAssertEqual(segments.count, 1)
        guard case .text(let text) = segments[0] else {
            return XCTFail("expected text")
        }
        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("world"))
    }

    func testImageAndTextOrder() {
        let html = """
        <p>before</p>
        <p><img src="/uploads/a.png" alt=""></p>
        <p>after</p>
        """
        let segments = ShareImageBodyComposer.segments(from: html, baseURL: "https://linux.do")
        XCTAssertEqual(segments.count, 3)
        guard case .text(let before) = segments[0] else { return XCTFail("before text") }
        guard case .image(let url) = segments[1] else { return XCTFail("image") }
        guard case .text(let after) = segments[2] else { return XCTFail("after text") }
        XCTAssertEqual(before, "before")
        XCTAssertEqual(after, "after")
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
}
